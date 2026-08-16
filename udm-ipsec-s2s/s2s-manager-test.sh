#!/usr/bin/env bash
# ==============================================================================
# UniFi <-> Debian IPsec S2S Manager
# Development / Test Build
#
# Purpose:
#   Interactive setup and management of route-based IKEv2/IPsec S2S tunnels
#   between Debian 13 (strongSwan/swanctl) and UniFi UDM gateways.
#
# State:
#   /root/s2s-manager-test/
#
# System changes:
#   - can install required strongSwan packages
#   - can disable the unused TPM plugin
#   - can create/remove managed strongSwan tunnel configs
#   - can create/remove managed VTI scripts and systemd services
#   - can add/remove managed UFW rules
#
# Safety:
#   - does NOT enable UFW automatically
#   - shows an installation/change summary before applying
#   - uses uniquely named managed files
#   - keeps per-tunnel PSKs in mode 600 files
# ==============================================================================

set -u
set -o pipefail

VERSION="0.14-test"

STATE_DIR="/root/s2s-manager-test"
TUNNEL_DIR="${STATE_DIR}/tunnels"
ROUTE_DIR="${STATE_DIR}/routes"
SECRET_DIR="${STATE_DIR}/secrets"

SWANCTL_DIR="/etc/swanctl/conf.d"
MANAGED_PREFIX="s2s-manager"
VTI_SCRIPT_DIR="/usr/local/sbin"
SYSTEMD_DIR="/etc/systemd/system"

REQUIRED_PACKAGES=(
    strongswan
    charon-systemd
    strongswan-swanctl
    libstrongswan-standard-plugins
    libstrongswan-extra-plugins
)

DEFAULT_NET_PREFIX_A=10
DEFAULT_NET_PREFIX_B=200
DEFAULT_NET_START_C=201
DEFAULT_VTI_KEY=42

# ==============================================================================
# Colors
# ==============================================================================

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
fi

# ==============================================================================
# UI
# ==============================================================================

clear_screen() {
    printf '\033c'
}

line() {
    printf '%b\n' "${C_DIM}──────────────────────────────────────────────────────────────${C_RESET}"
}

ok() {
    printf '%b\n' "${C_GREEN}[✓]${C_RESET} $*"
}

warn() {
    printf '%b\n' "${C_YELLOW}[!]${C_RESET} $*"
}

error() {
    printf '%b\n' "${C_RED}[✗]${C_RESET} $*"
}

info() {
    printf '%b\n' "${C_CYAN}[i]${C_RESET} $*"
}

pause() {
    echo
    read -r -p "Press ENTER to continue..." _
}

banner() {
    clear_screen

    local width=62
    local title="UniFi IPsec S2S Manager"
    local version_text="Version ${VERSION}"
    local left right

    printf '%b' "${C_CYAN}${C_BOLD}"
    printf '╔%s╗\n' "$(printf '═%.0s' $(seq 1 ${width}))"

    left=$(( (width - ${#title}) / 2 ))
    right=$(( width - ${#title} - left ))
    printf '║%*s%s%*s║\n' "${left}" '' "${title}" "${right}" ''

    left=$(( (width - ${#version_text}) / 2 ))
    right=$(( width - ${#version_text} - left ))
    printf '║%*s%s%*s║\n' "${left}" '' "${version_text}" "${right}" ''

    printf '╚%s╝\n' "$(printf '═%.0s' $(seq 1 ${width}))"
    printf '%b' "${C_RESET}"
    echo
    printf '%b\n' "${C_YELLOW}${C_BOLD}DEVELOPMENT / TEST BUILD${C_RESET}"
    printf 'State directory: %b%s%b\n' "${C_CYAN}" "${STATE_DIR}" "${C_RESET}"
    echo
}

section() {
    echo
    line
    printf '  %b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
    line
    echo
}

confirm_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local answer

    if [[ "${default}" == "Y" ]]; then
        read -r -p "${prompt} [Y/n]: " answer
        [[ -z "${answer}" || "${answer}" =~ ^[Yy]$ ]]
    else
        read -r -p "${prompt} [y/N]: " answer
        [[ "${answer}" =~ ^[Yy]$ ]]
    fi
}

# ==============================================================================
# Environment / package checks
# ==============================================================================


swanctl_clean() {
    # Hide the known harmless swanctl agent-plugin warning on Debian 13.
    # Keep all other stdout/stderr output intact.
    "$@" 2>&1 | sed \
        -e '/^agent plugin requires CAP_SETUID\/CAP_SETGID capability$/d' \
        -e "/^plugin 'agent': failed to load - agent_plugin_create returned NULL$/d"
    local rc=${PIPESTATUS[0]}
    return "${rc}"
}


ensure_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "This manager must be run as root."
        exit 1
    fi
}

init_state_dirs() {
    mkdir -p "${TUNNEL_DIR}" "${ROUTE_DIR}" "${SECRET_DIR}"
    chmod 700 "${STATE_DIR}" "${TUNNEL_DIR}" "${ROUTE_DIR}" "${SECRET_DIR}"
}

debian_major_version() {
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID:-}" == "debian" ]]; then
            printf '%s' "${VERSION_ID:-unknown}"
            return
        fi
    fi
    printf 'unknown'
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

missing_packages() {
    local pkg
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        package_installed "${pkg}" || printf '%s\n' "${pkg}"
    done
}

command_available() {
    command -v "$1" >/dev/null 2>&1
}

detect_public_ipv4() {
    local detected=""

    detected=$(
        ip -4 route get 1.1.1.1 2>/dev/null |
        awk '{
            for (i=1; i<=NF; i++) {
                if ($i == "src") {
                    print $(i+1)
                    exit
                }
            }
        }'
    )

    printf '%s' "${detected}"
}

tpm_disabled() {
    grep -Eq '^[[:space:]]*load[[:space:]]*=[[:space:]]*no[[:space:]]*$' \
        /etc/strongswan.d/charon/tpm.conf 2>/dev/null
}

agent_disabled() {
    grep -Eq '^[[:space:]]*load[[:space:]]*=[[:space:]]*no[[:space:]]*$' \
        /etc/strongswan.d/charon/agent.conf 2>/dev/null
}

route_based_global_ready() {
    grep -Eq '^[[:space:]]*install_routes[[:space:]]*=[[:space:]]*no[[:space:]]*$' \
        /etc/strongswan.d/charon/route-based.conf 2>/dev/null
}

ufw_installed() {
    command_available ufw
}

ufw_active() {
    ufw_installed && ufw status 2>/dev/null | grep -q '^Status: active'
}

preflight_ready() {
    [[ "$(debian_major_version)" == "13" ]] || return 1
    command_available ip || return 1
    command_available openssl || return 1
    command_available swanctl || return 1

    local missing
    missing="$(missing_packages)"
    [[ -z "${missing}" ]] || return 1

    tpm_disabled || return 1
    agent_disabled || return 1
    route_based_global_ready || return 1

    return 0
}

show_preflight() {
    banner
    section "SYSTEM PRE-FLIGHT CHECK"

    local ready=1
    local version
    version="$(debian_major_version)"

    if [[ "${version}" == "13" ]]; then
        ok "Debian 13 detected"
    else
        error "Debian 13 required (detected: ${version})"
        ready=0
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        ok "Running as root"
    else
        error "Root privileges required"
        ready=0
    fi

    if command_available ip; then
        ok "iproute2 / ip command available"
    else
        error "ip command missing"
        ready=0
    fi

    if command_available openssl; then
        ok "OpenSSL available"
    else
        error "OpenSSL missing"
        ready=0
    fi

    echo
    printf '%b\n' "${C_BOLD}Required packages:${C_RESET}"

    local pkg
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if package_installed "${pkg}"; then
            ok "${pkg}"
        else
            error "${pkg} - NOT INSTALLED"
            ready=0
        fi
    done

    echo
    printf '%b\n' "${C_BOLD}strongSwan preparation:${C_RESET}"

    if command_available swanctl; then
        ok "swanctl available"
    else
        error "swanctl missing"
        ready=0
    fi

    if tpm_disabled; then
        ok "Unused TPM plugin disabled"
    else
        error "TPM plugin is not disabled by the manager"
        ready=0
    fi

    if agent_disabled; then
        ok "Unused agent plugin disabled for charon"
    else
        error "Agent plugin is not disabled for charon"
        ready=0
    fi

    if route_based_global_ready; then
        ok "Route-based strongSwan mode prepared"
    else
        error "Route-based strongSwan setting missing"
        ready=0
    fi

    echo
    printf '%b\n' "${C_BOLD}Firewall:${C_RESET}"

    if ufw_installed; then
        ok "UFW installed"
        if ufw_active; then
            ok "UFW active"
        else
            warn "UFW installed but inactive"
        fi
    else
        info "Local UFW not installed (optional)"
        echo "    External/provider firewall can be used instead."
        echo "    Required for IPsec: UDP 500 and UDP 4500"
    fi

    echo
    printf '%b\n' "${C_BOLD}Detected server IPv4:${C_RESET}"
    local public_ip
    public_ip="$(detect_public_ipv4)"
    if [[ -n "${public_ip}" ]]; then
        ok "${public_ip}"
    else
        warn "Could not determine a local IPv4 automatically"
    fi

    echo
    if (( ready == 1 )); then
        ok "System is READY for S2S tunnel management."
        return 0
    fi

    warn "System setup / repair is required before tunnels can be installed."
    return 1
}

install_or_repair_prerequisites() {
    banner
    section "INSTALL / REPAIR PREREQUISITES"

    echo "The following shared prerequisites will be prepared:"
    echo
    echo "Packages:"
    local pkg
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if package_installed "${pkg}"; then
            printf '  = %-38s already installed\n' "${pkg}"
        else
            printf '  + %-38s install\n' "${pkg}"
        fi
    done

    echo
    echo "strongSwan:"
    echo "  + disable unused TPM plugin"
    echo "  + disable unused agent plugin"
    echo "  + disable automatic strongSwan route installation"
    echo "  + restart strongSwan"
    echo
    echo "No tunnel will be created by this step."
    echo "No firewall rule will be added by this step."
    echo

    confirm_yes_no "Apply prerequisite setup?" "N" || return

    echo
    section "APPLYING PREREQUISITES"

    local -a missing=()
    mapfile -t missing < <(missing_packages)

    if (( ${#missing[@]} > 0 )); then
        printf '[1/5] Installing required packages... '
        if apt-get update >/tmp/s2s-manager-apt-update.log 2>&1 &&
           DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" \
               >/tmp/s2s-manager-apt-install.log 2>&1; then
            printf '%b\n' "${C_GREEN}OK${C_RESET}"
        else
            printf '%b\n' "${C_RED}FAILED${C_RESET}"
            error "Package installation failed."
            echo "See:"
            echo "  /tmp/s2s-manager-apt-update.log"
            echo "  /tmp/s2s-manager-apt-install.log"
            pause
            return 1
        fi
    else
        printf '[1/5] Installing required packages... %b\n' "${C_GREEN}ALREADY OK${C_RESET}"
    fi

    printf '[2/5] Disabling unused TPM plugin... '
    mkdir -p /etc/strongswan.d/charon
    cat > /etc/strongswan.d/charon/tpm.conf <<'EOF'
tpm {
    load = no
}
EOF
    printf '%b\n' "${C_GREEN}OK${C_RESET}"

    printf '[3/5] Disabling unused agent plugin... '
    cat > /etc/strongswan.d/charon/agent.conf <<'EOF'
agent {
    load = no
}
EOF
    printf '%b\n' "${C_GREEN}OK${C_RESET}"

    printf '[4/5] Preparing route-based strongSwan mode... '
    cat > /etc/strongswan.d/charon/route-based.conf <<'EOF'
charon {
    install_routes = no
}
EOF
    printf '%b\n' "${C_GREEN}OK${C_RESET}"

    printf '[5/5] Restarting and validating strongSwan... '
    if systemctl restart strongswan >/tmp/s2s-manager-strongswan-restart.log 2>&1 &&
       systemctl is-active --quiet strongswan; then
        printf '%b\n' "${C_GREEN}OK${C_RESET}"
    else
        printf '%b\n' "${C_RED}FAILED${C_RESET}"
        error "strongSwan did not restart successfully."
        journalctl -u strongswan -n 30 --no-pager
        pause
        return 1
    fi

    echo
    if journalctl -u strongswan --since "1 minute ago" --no-pager |
       grep -qi "failed to load"; then
        warn "Recent strongSwan plugin load errors were found:"
        journalctl -u strongswan --since "1 minute ago" --no-pager |
            grep -i "failed to load"
    else
        ok "No recent strongSwan plugin load errors."
    fi

    echo
    ok "Prerequisites are prepared."
    pause
}

# ==============================================================================
# IPv4 / CIDR helpers
# ==============================================================================

valid_ipv4() {
    local ip="$1"
    local IFS=.
    local -a octets
    read -r -a octets <<< "${ip}"

    [[ ${#octets[@]} -eq 4 ]] || return 1

    local o
    for o in "${octets[@]}"; do
        [[ "${o}" =~ ^[0-9]+$ ]] || return 1
        (( o >= 0 && o <= 255 )) || return 1
    done
}

ipv4_to_int() {
    local ip="$1"
    local a b c d
    IFS=. read -r a b c d <<< "${ip}"
    printf '%u' "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
}

int_to_ipv4() {
    local n="$1"
    printf '%d.%d.%d.%d' \
        $(( (n >> 24) & 255 )) \
        $(( (n >> 16) & 255 )) \
        $(( (n >> 8) & 255 )) \
        $(( n & 255 ))
}

normalize_30_network() {
    local input="$1"
    local ip prefix n network

    if [[ "${input}" == */* ]]; then
        ip="${input%%/*}"
        prefix="${input##*/}"
    else
        ip="${input}"
        prefix="30"
    fi

    valid_ipv4 "${ip}" || return 1
    [[ "${prefix}" == "30" ]] || return 2

    n=$(ipv4_to_int "${ip}")
    network=$(( n & 0xFFFFFFFC ))
    printf '%s/30' "$(int_to_ipv4 "${network}")"
}

calculate_30_addresses() {
    local network="$1"
    local base="${network%%/*}"
    local n
    n=$(ipv4_to_int "${base}")

    CALC_NETWORK="$(int_to_ipv4 "${n}")/30"
    CALC_DEBIAN="$(int_to_ipv4 "$((n + 1))")"
    CALC_UNIFI="$(int_to_ipv4 "$((n + 2))")"
    CALC_BROADCAST="$(int_to_ipv4 "$((n + 3))")"
}

network_is_exact_base() {
    local input="$1"
    local normalized
    normalized=$(normalize_30_network "${input}") || return 1
    [[ "${input%%/*}" == "${normalized%%/*}" ]]
}

valid_cidr() {
    local input="$1"
    local ip prefix

    [[ "${input}" == */* ]] || return 1
    ip="${input%%/*}"
    prefix="${input##*/}"

    valid_ipv4 "${ip}" || return 1
    [[ "${prefix}" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 ))
}

valid_tunnel_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$ ]]
}

valid_auth_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$ ]]
}

# ==============================================================================
# State
# ==============================================================================

tunnel_config_file() { printf '%s/%s.conf' "${TUNNEL_DIR}" "$1"; }
tunnel_route_file()  { printf '%s/%s.routes' "${ROUTE_DIR}" "$1"; }
tunnel_secret_file() { printf '%s/%s.psk' "${SECRET_DIR}" "$1"; }

managed_swan_file() {
    printf '%s/%s-%s.conf' "${SWANCTL_DIR}" "${MANAGED_PREFIX}" "$1"
}

managed_vti_script() {
    printf '%s/%s-vti-%s.sh' "${VTI_SCRIPT_DIR}" "${MANAGED_PREFIX}" "$1"
}

managed_service_file() {
    printf '%s/%s-vti-%s.service' "${SYSTEMD_DIR}" "${MANAGED_PREFIX}" "$1"
}

managed_service_name() {
    printf '%s-vti-%s.service' "${MANAGED_PREFIX}" "$1"
}

tunnel_exists() {
    [[ -f "$(tunnel_config_file "$1")" ]]
}

list_tunnel_names() {
    local file
    shopt -s nullglob
    for file in "${TUNNEL_DIR}"/*.conf; do
        basename "${file}" .conf
    done
    shopt -u nullglob
}

tunnel_count() {
    local count=0 name
    while read -r name; do
        [[ -n "${name}" ]] && ((count += 1))
    done < <(list_tunnel_names)
    printf '%d' "${count}"
}

load_tunnel() {
    local name="$1"
    local file
    file="$(tunnel_config_file "${name}")"
    [[ -f "${file}" ]] || return 1

    unset NAME PUBLIC_IP AUTH_ID VTI_INTERFACE VTI_KEY
    unset VTI_NETWORK DEBIAN_VTI_IP UNIFI_VTI_IP CREATED_AT INSTALLED

    # shellcheck disable=SC1090
    source "${file}"

    : "${INSTALLED:=0}"
}

save_tunnel() {
    local name="$1"
    local public_ip="$2"
    local auth_id="$3"
    local interface="$4"
    local key="$5"
    local network="$6"
    local debian_ip="$7"
    local unifi_ip="$8"
    local installed="${9:-0}"

    local config
    config="$(tunnel_config_file "${name}")"

    {
        printf 'NAME=%q\n' "${name}"
        printf 'PUBLIC_IP=%q\n' "${public_ip}"
        printf 'AUTH_ID=%q\n' "${auth_id}"
        printf 'VTI_INTERFACE=%q\n' "${interface}"
        printf 'VTI_KEY=%q\n' "${key}"
        printf 'VTI_NETWORK=%q\n' "${network}"
        printf 'DEBIAN_VTI_IP=%q\n' "${debian_ip}"
        printf 'UNIFI_VTI_IP=%q\n' "${unifi_ip}"
        printf 'CREATED_AT=%q\n' "$(date -Is)"
        printf 'INSTALLED=%q\n' "${installed}"
    } > "${config}"

    chmod 600 "${config}"
}

read_routes() {
    local file
    file="$(tunnel_route_file "$1")"
    [[ -f "${file}" ]] && cat "${file}"
}

write_routes() {
    local name="$1"
    shift
    local file route
    file="$(tunnel_route_file "${name}")"
    : > "${file}"
    for route in "$@"; do
        [[ -n "${route}" ]] && printf '%s\n' "${route}" >> "${file}"
    done
    chmod 600 "${file}"
}

save_psk() {
    local file
    file="$(tunnel_secret_file "$1")"
    printf '%s\n' "$2" > "${file}"
    chmod 600 "${file}"
}

read_psk() {
    local file
    file="$(tunnel_secret_file "$1")"
    [[ -f "${file}" ]] || return 1
    cat "${file}"
}

generate_psk() {
    openssl rand -base64 32 | tr -d '\n'
}

auth_id_in_use() {
    local wanted="$1"
    local ignore="${2:-}"
    local name

    while read -r name; do
        [[ -z "${name}" || "${name}" == "${ignore}" ]] && continue
        load_tunnel "${name}" || continue
        [[ "${AUTH_ID}" == "${wanted}" ]] && return 0
    done < <(list_tunnel_names)

    return 1
}

network_in_use() {
    local wanted="$1"
    local ignore="${2:-}"
    local name

    while read -r name; do
        [[ -z "${name}" || "${name}" == "${ignore}" ]] && continue
        load_tunnel "${name}" || continue
        [[ "${VTI_NETWORK}" == "${wanted}" ]] && return 0
    done < <(list_tunnel_names)

    return 1
}

next_interface_index() {
    local index=0 name used

    while :; do
        used=0
        while read -r name; do
            [[ -z "${name}" ]] && continue
            load_tunnel "${name}" || continue
            if [[ "${VTI_INTERFACE}" == "ipsec${index}" ]]; then
                used=1
                break
            fi
        done < <(list_tunnel_names)

        (( used == 0 )) && { printf '%d' "${index}"; return; }
        ((index += 1))
    done
}

next_vti_network() {
    local c candidate
    for (( c=DEFAULT_NET_START_C; c<=250; c++ )); do
        candidate="${DEFAULT_NET_PREFIX_A}.${DEFAULT_NET_PREFIX_B}.${c}.0/30"
        if ! network_in_use "${candidate}"; then
            printf '%s' "${candidate}"
            return
        fi
    done
    printf '10.200.251.0/30'
}

tunnel_connection_state() {
    local name="$1"
    local conn="${MANAGED_PREFIX}-${name}"
    local sa

    if ! command_available swanctl; then
        printf 'UNKNOWN'
        return
    fi

    sa="$(swanctl_clean swanctl --list-sas 2>/dev/null || true)"

    if grep -qE "^${conn}: .*ESTABLISHED" <<< "${sa}" && \
       awk -v c="${conn}:" '
           $0 ~ "^" c {show=1; next}
           show && /^[^[:space:]]/ {exit}
           show && /INSTALLED/ {found=1; exit}
           END {exit found ? 0 : 1}
       ' <<< "${sa}"; then
        printf 'CONNECTED'
    else
        printf 'DISCONNECTED'
    fi
}

# ==============================================================================
# Tunnel list / selection
# ==============================================================================

show_existing_tunnels() {
    local count
    count="$(tunnel_count)"

    if (( count == 0 )); then
        info "No tunnels configured."
        return
    fi

    printf '%-4s %-16s %-10s %-20s %-12s %-14s %-24s\n' \
        "#" "Name" "Interface" "Tunnel Network" "State" "Connection" "Authentication ID"
    printf '%-4s %-16s %-10s %-20s %-12s %-14s %-24s\n' \
        "──" "────────────────" "──────────" "────────────────────" "────────────" "──────────────" "────────────────────────"

    local index=1 name state connection
    while read -r name; do
        [[ -z "${name}" ]] && continue
        load_tunnel "${name}" || continue

        if [[ "${INSTALLED}" == "1" ]]; then
            state="INSTALLED"
            connection="$(tunnel_connection_state "${NAME}")"
        else
            state="DEFINED"
            connection="-"
        fi

        printf '%-4s %-16s %-10s %-20s %-12s ' \
            "${index}" "${NAME}" "${VTI_INTERFACE}" "${VTI_NETWORK}" "${state}"

        case "${connection}" in
            CONNECTED)
                printf '%b%-14s%b ' "${C_GREEN}${C_BOLD}" "${connection}" "${C_RESET}"
                ;;
            DISCONNECTED)
                printf '%b%-14s%b ' "${C_RED}${C_BOLD}" "${connection}" "${C_RESET}"
                ;;
            *)
                printf '%-14s ' "${connection}"
                ;;
        esac

        printf '%-24s\n' "${AUTH_ID}"
        ((index += 1))
    done < <(list_tunnel_names)
}

select_tunnel() {
    local -a names=()
    local name selection i

    while read -r name; do
        [[ -n "${name}" ]] && names+=("${name}")
    done < <(list_tunnel_names)

    (( ${#names[@]} > 0 )) || { warn "No tunnels configured."; return 1; }

    echo
    for i in "${!names[@]}"; do
        printf '  [%d] %s\n' "$((i + 1))" "${names[$i]}"
    done
    echo
    echo "Enter tunnel number and press ENTER."
    echo "B = Back    E = Exit"
    echo
    read -r -p "Selection: " selection

    case "${selection}" in
        ""|b|B|0) return 1 ;;
        e|E) clear_screen; echo "Bye."; exit 0 ;;
    esac

    [[ "${selection}" =~ ^[0-9]+$ ]] || return 1
    (( selection >= 1 && selection <= ${#names[@]} )) || return 1

    SELECTED_TUNNEL="${names[$((selection - 1))]}"
    return 0
}

# ==============================================================================
# Prompts
# ==============================================================================

prompt_tunnel_name() {
    local suggested="$1" value
    while :; do
        echo "The tunnel name is used locally by the S2S Manager."
        echo "Examples: home, office, backup"
        echo
        echo "Press ENTER to accept the suggested value or enter another value."
        echo
        read -r -p "Tunnel name [${suggested}]: " value
        value="${value:-${suggested}}"

        valid_tunnel_name "${value}" || { error "Invalid tunnel name."; echo; continue; }
        tunnel_exists "${value}" && { error "Tunnel '${value}' already exists."; echo; continue; }

        PROMPT_RESULT="${value}"
        return
    done
}

prompt_public_ip() {
    local suggested="$1" value
    while :; do
        echo "This is the public IPv4 address of the Debian server."
        echo "It will be used as the local IPsec endpoint and UniFi remote gateway."
        echo
        echo "Press ENTER to accept the suggested value or enter another value."
        echo
        read -r -p "Debian public IP [${suggested}]: " value
        value="${value:-${suggested}}"
        valid_ipv4 "${value}" || { error "Invalid IPv4 address."; echo; continue; }
        PROMPT_RESULT="${value}"
        return
    done
}

prompt_tunnel_network() {
    local suggested="$1"
    local value normalized rc choice

    while :; do
        echo "Every Site-to-Site tunnel needs its own private /30 transfer network."
        echo
        echo "You may enter either:"
        echo "  10.200.201.0"
        echo "or"
        echo "  10.200.201.0/30"
        echo
        echo "Both formats are accepted."
        echo
        echo "The network must not overlap with LAN, VLAN, VPN, Teleport or other S2S networks."
        echo

        if (( $(tunnel_count) > 0 )); then
            echo "Existing S2S networks:"
            local n
            while read -r n; do
                [[ -z "${n}" ]] && continue
                load_tunnel "${n}" || continue
                printf '  • %s (%s)\n' "${VTI_NETWORK}" "${NAME}"
            done < <(list_tunnel_names)
            echo
        fi

        echo "Press ENTER to accept the suggested value or enter another network."
        echo
        read -r -p "Tunnel network [${suggested%%/*}]: " value
        value="${value:-${suggested}}"

        normalized="$(normalize_30_network "${value}")"
        rc=$?

        if (( rc == 1 )); then
            error "Invalid IPv4 network."
            echo
            continue
        elif (( rc == 2 )); then
            warn "This manager uses /30 networks."
            echo "You entered: ${value}"
            echo "Suggested:   ${value%%/*}/30"
            echo
            echo "  [1] Use ${value%%/*}/30"
            echo "  [2] Enter another network"
            echo "  [B] Back"
            echo "  [E] Exit"
            echo
            read -r -p "Selection: " choice
            case "${choice}" in
                1) value="${value%%/*}/30"; normalized="$(normalize_30_network "${value}")" || continue ;;
                b|B|0) return 1 ;;
                e|E) clear_screen; echo "Bye."; exit 0 ;;
                *) continue ;;
            esac
        fi

        if ! network_is_exact_base "${value}"; then
            calculate_30_addresses "${normalized}"
            warn "${value%%/*} is not a /30 network address."
            printf '%-14s %s\n' "Network:" "${CALC_NETWORK}"
            printf '%-14s %s\n' "Debian IP:" "${CALC_DEBIAN}"
            printf '%-14s %s\n' "UniFi IP:" "${CALC_UNIFI}"
            printf '%-14s %s\n' "Broadcast:" "${CALC_BROADCAST}"
            echo
            confirm_yes_no "Use this calculated /30 network?" "N" || continue
        fi

        network_in_use "${normalized}" && {
            error "Network ${normalized} is already used by another tunnel."
            echo
            continue
        }

        calculate_30_addresses "${normalized}"

        ok "Valid /30 network"
        printf '%-14s %s\n' "Network:" "${CALC_NETWORK}"
        printf '%-14s %s\n' "Debian IP:" "${CALC_DEBIAN}"
        printf '%-14s %s\n' "UniFi IP:" "${CALC_UNIFI}"
        printf '%-14s %s\n' "Broadcast:" "${CALC_BROADCAST}"
        echo

        confirm_yes_no "Use these addresses?" "Y" || continue

        PROMPT_NETWORK="${CALC_NETWORK}"
        PROMPT_DEBIAN_IP="${CALC_DEBIAN}"
        PROMPT_UNIFI_IP="${CALC_UNIFI}"
        return
    done
}

prompt_auth_id() {
    local suggested="$1" value
    while :; do
        echo "The UniFi gateway identifies itself to Debian using this IKE identity."
        echo "This is not an IP address and does not need to resolve in DNS."
        echo "Use a unique Authentication ID for every S2S tunnel."
        echo
        echo "Press ENTER to accept the suggested value or enter another value."
        echo
        read -r -p "UniFi authentication ID [${suggested}]: " value
        value="${value:-${suggested}}"

        valid_auth_id "${value}" || { error "Invalid Authentication ID."; echo; continue; }
        auth_id_in_use "${value}" && { error "Authentication ID already in use."; echo; continue; }

        PROMPT_RESULT="${value}"
        return
    done
}

prompt_remote_networks() {
    PROMPT_ROUTES=()
    echo "Enter UniFi-side networks that Debian must return through the S2S tunnel."
    echo
    echo "Examples:"
    echo "  192.168.178.0/23   Main LAN"
    echo "  192.168.4.0/24     UniFi Teleport"
    echo
    echo "Enter one network per line."
    echo "Press ENTER on an empty line when finished."
    echo

    local index=1 route existing duplicate
    while :; do
        read -r -p "Remote network #${index}: " route
        [[ -z "${route}" ]] && break

        valid_cidr "${route}" || { error "Invalid CIDR network."; echo; continue; }

        duplicate=0
        for existing in "${PROMPT_ROUTES[@]:-}"; do
            [[ "${existing}" == "${route}" ]] && duplicate=1
        done
        (( duplicate == 1 )) && { warn "Network already added."; continue; }

        PROMPT_ROUTES+=("${route}")
        ((index += 1))
    done
}

prompt_psk() {
    local choice value
    echo "The same Pre-Shared Key must later be entered in UniFi."
    echo
    echo "  [1] Generate a secure random PSK"
    echo "  [2] Enter my own PSK"
    echo "  [B] Back"
    echo "  [E] Exit"
    echo
    echo "Press ENTER to use option 1."
    echo

    while :; do
        read -r -p "Selection [1]: " choice
        choice="${choice:-1}"
        case "${choice}" in
            1)
                PROMPT_PSK="$(generate_psk)"
                ok "Secure random PSK generated."
                return
                ;;
            2)
                read -r -s -p "Pre-Shared Key: " value
                echo
                [[ -n "${value}" ]] || { error "PSK must not be empty."; continue; }
                PROMPT_PSK="${value}"
                return
                ;;
            b|B|0) return 1 ;;
            e|E) clear_screen; echo "Bye."; exit 0 ;;
            *) error "Invalid selection." ;;
        esac
    done
}

# ==============================================================================
# Firewall management
# ==============================================================================

ufw_comment_exists() {
    local comment="$1"
    ufw status 2>/dev/null | grep -Fq "${comment}"
}

ensure_shared_firewall_rules() {
    local public_ip="$1"
    local choice ssh_port action proto port desc

    if ! ufw_installed; then
        clear
        banner
        section "OPTIONAL UFW FIREWALL SETUP"

        cat <<'EOF'
UFW is currently not installed.

UFW is NOT required for the S2S Manager.
An external/provider firewall can be used instead.

If UFW is installed and enabled, incoming connections that are not
explicitly allowed may be blocked.

IMPORTANT:
Before enabling UFW, make sure every service you still need is allowed.

Examples:
  SSH             TCP 22
  HTTP            TCP 80
  HTTPS           TCP 443
  IKE             UDP 500
  IPsec NAT-T     UDP 4500

Web servers, mail servers, VPN servers and other custom services are
NOT opened automatically.
EOF

        ssh_port=""
        if [[ -n "${SSH_CONNECTION:-}" ]]; then
            ssh_port="$(awk '{print $4}' <<<"${SSH_CONNECTION}")"
        fi
        if [[ -z "${ssh_port}" ]] && command_available sshd; then
            ssh_port="$(sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}')"
        fi
        [[ -n "${ssh_port}" ]] || ssh_port="22"

        echo
        echo "Detected SSH port: TCP ${ssh_port}"
        echo
        echo "  [1] Install UFW and configure it safely"
        echo "  [2] Continue without UFW"
        echo "  [B] Back"
        echo "  [E] Exit"
        echo
        read -r -p "Selection: " choice

        case "${choice}" in
            1)
                apt-get update || return 1
                DEBIAN_FRONTEND=noninteractive apt-get install -y ufw || return 1

                # SSH first: never offer ufw enable without protecting remote access.
                ufw allow "${ssh_port}/tcp" comment 'S2S Manager SSH safety' >/dev/null || return 1
                ufw allow 500/udp comment 'S2S Manager IKE' >/dev/null || return 1
                ufw allow 4500/udp comment 'S2S Manager NAT-T' >/dev/null || return 1

                while true; do
                    clear
                    banner
                    section "UFW CONFIGURATION SUMMARY"
                    echo "Mandatory rules prepared by the manager:"
                    echo
                    printf "  TCP %-8s SSH / current remote access\n" "${ssh_port}"
                    printf "  UDP %-8s IPsec IKE\n" "500"
                    printf "  UDP %-8s IPsec NAT-T\n" "4500"
                    echo
                    echo "Existing UFW rules are preserved."
                    echo
                    echo "WARNING:"
                    echo "Other incoming ports may be blocked after UFW is enabled unless"
                    echo "matching allow rules already exist or are added now."
                    echo
                    echo "  [1] Add additional firewall rule"
                    echo "  [2] Review and continue"
                    echo "  [B] Back (UFW remains disabled)"
                    echo "  [E] Exit"
                    echo
                    read -r -p "Selection: " action

                    case "${action}" in
                        1)
                            echo
                            read -r -p "Protocol [tcp]: " proto
                            proto="${proto:-tcp}"
                            proto="${proto,,}"
                            if [[ "${proto}" != "tcp" && "${proto}" != "udp" ]]; then
                                error "Protocol must be tcp or udp."
                                pause
                                continue
                            fi
                            read -r -p "Port: " port
                            if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
                                error "Port must be between 1 and 65535."
                                pause
                                continue
                            fi
                            read -r -p "Description [Additional service]: " desc
                            desc="${desc:-Additional service}"
                            ufw allow "${port}/${proto}" comment "S2S Manager ${desc}" >/dev/null || return 1
                            ok "Added ${proto^^} ${port} (${desc})"
                            pause
                            ;;
                        2) break ;;
                        b|B|0) return 0 ;;
                        e|E) clear_screen; echo "Bye."; exit 0 ;;
                    esac
                done

                clear
                banner
                section "FINAL UFW SAFETY CHECK"
                ufw status numbered || true
                echo
                echo "Current SSH access detected on TCP port ${ssh_port}."

                if ufw status | grep -Eq "(^|[[:space:]])${ssh_port}/tcp[[:space:]]+ALLOW"; then
                    ok "Matching SSH allow rule is present."
                else
                    error "No matching SSH allow rule found."
                    echo "UFW will NOT be enabled."
                    pause
                    return 0
                fi

                echo
                echo "Default incoming policy will be DENY when UFW is enabled."
                echo "Review ALL required service ports above before continuing."
                echo
                read -r -p "Enable UFW now? [y/N]: " choice
                if [[ "${choice,,}" == "y" ]]; then
                    ufw default deny incoming >/dev/null
                    ufw default allow outgoing >/dev/null
                    ufw --force enable >/dev/null || return 1
                    ok "UFW enabled."
                else
                    info "UFW installed and rules prepared, but UFW was NOT enabled."
                fi
                return 0
                ;;
            2) return 0 ;;
            b|B|0) return 1 ;;
            e|E) clear_screen; echo "Bye."; exit 0 ;;
            *) return 1 ;;
        esac
    fi

    # UFW already exists. Add only the IPsec rules; never change its enabled state.
    if ! ufw_active; then
        info "UFW is installed but inactive."
        echo "The manager will not enable it automatically in this path."
        echo
        echo "  [1] Add managed IPsec rules and keep UFW disabled"
        echo "  [2] Skip firewall changes"
        echo "  [B] Back"
        echo "  [E] Exit"
        echo
        read -r -p "Selection: " choice
        case "${choice}" in
            1) ;;
            2) return 0 ;;
            b|B|0) return 1 ;;
            e|E) clear_screen; echo "Bye."; exit 0 ;;
            *) return 1 ;;
        esac
    fi

    ufw_comment_exists "S2S Manager IKE" ||
        ufw allow 500/udp comment 'S2S Manager IKE' >/dev/null
    ufw_comment_exists "S2S Manager NAT-T" ||
        ufw allow 4500/udp comment 'S2S Manager NAT-T' >/dev/null

    ok "Managed IPsec firewall rules are present (UDP 500 / 4500)."
}

remove_managed_ufw_rules() {
    ufw_installed || return 0

    local numbers
    numbers=$(
        ufw status numbered 2>/dev/null |
        awk '/S2S Manager (IKE|NAT-T)/ {
            gsub(/\[|\]/,"",$1)
            print $1
        }' |
        sort -rn
    )

    local n
    while read -r n; do
        [[ -n "${n}" ]] && yes | ufw delete "${n}" >/dev/null 2>&1 || true
    done <<< "${numbers}"
}

# ==============================================================================
# Generated system configuration
# ==============================================================================

render_strongswan_config() {
    local name="$1"
    load_tunnel "${name}" || return 1

    local psk
    psk="$(read_psk "${name}")" || return 1

    mkdir -p "${SWANCTL_DIR}"

    cat > "$(managed_swan_file "${name}")" <<EOF
connections {
    ${MANAGED_PREFIX}-${NAME} {
        version = 2
        local_addrs = ${PUBLIC_IP}
        remote_addrs = %any
        encap = yes

        proposals = aes256-sha256-modp2048

        # UniFi IKE lifetime: 28800s (8h).
        # strongSwan's hard IKE lifetime is rekey_time + over_time.
        rekey_time = 26182s
        over_time = 2618s
        rand_time = 2618s

        local {
            auth = psk
            id = ${PUBLIC_IP}
        }

        remote {
            auth = psk
            id = ${AUTH_ID}
        }

        children {
            ${MANAGED_PREFIX}-${NAME} {
                local_ts = 0.0.0.0/0
                remote_ts = 0.0.0.0/0

                esp_proposals = aes256-sha256-modp2048

                # UniFi ESP lifetime: 3600s (1h).
                # Rekey early to avoid both peers reaching the hard lifetime together.
                life_time = 3600s
                rekey_time = 3273s
                rand_time = 327s

                mark_in = ${VTI_KEY}
                mark_out = ${VTI_KEY}

                start_action = none
                dpd_action = restart
            }
        }

        dpd_delay = 30s
        reauth_time = 0s
    }
}

secrets {
    ike-${MANAGED_PREFIX}-${NAME} {
        id-local = ${PUBLIC_IP}
        id-remote = ${AUTH_ID}
        secret = "${psk}"
    }
}
EOF

    chmod 600 "$(managed_swan_file "${name}")"
}

render_vti_script() {
    local name="$1"
    load_tunnel "${name}" || return 1

    local script
    script="$(managed_vti_script "${name}")"

    cat > "${script}" <<EOF
#!/usr/bin/env bash
set -e

ip link show ${VTI_INTERFACE} >/dev/null 2>&1 || \\
ip tunnel add ${VTI_INTERFACE} \\
    local ${PUBLIC_IP} \\
    remote 0.0.0.0 \\
    mode vti \\
    key ${VTI_KEY}

ip link set ${VTI_INTERFACE} up

ip addr show dev ${VTI_INTERFACE} | grep -q '${DEBIAN_VTI_IP}/30' || \\
ip addr add ${DEBIAN_VTI_IP}/30 dev ${VTI_INTERFACE}

ip route replace ${VTI_NETWORK} dev ${VTI_INTERFACE} table 220
EOF

    local route
    while read -r route; do
        [[ -n "${route}" ]] &&
            printf 'ip route replace %s dev %s table 220\n' "${route}" "${VTI_INTERFACE}" >> "${script}"
    done < <(read_routes "${name}")

    cat >> "${script}" <<EOF

sysctl -w net.ipv4.conf.${VTI_INTERFACE}.disable_policy=1 >/dev/null
sysctl -w net.ipv4.conf.${VTI_INTERFACE}.rp_filter=0 >/dev/null
EOF

    chmod 755 "${script}"
}

render_systemd_service() {
    local name="$1"
    load_tunnel "${name}" || return 1

    cat > "$(managed_service_file "${name}")" <<EOF
[Unit]
Description=UniFi IPsec S2S VTI - ${NAME}
After=network-online.target
Wants=network-online.target
Before=strongswan.service

[Service]
Type=oneshot
ExecStart=$(managed_vti_script "${name}")
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

mark_tunnel_installed() {
    local name="$1"
    load_tunnel "${name}" || return 1

    save_tunnel \
        "${NAME}" "${PUBLIC_IP}" "${AUTH_ID}" "${VTI_INTERFACE}" "${VTI_KEY}" \
        "${VTI_NETWORK}" "${DEBIAN_VTI_IP}" "${UNIFI_VTI_IP}" "1"
}

mark_tunnel_defined() {
    local name="$1"
    load_tunnel "${name}" || return 1

    save_tunnel \
        "${NAME}" "${PUBLIC_IP}" "${AUTH_ID}" "${VTI_INTERFACE}" "${VTI_KEY}" \
        "${VTI_NETWORK}" "${DEBIAN_VTI_IP}" "${UNIFI_VTI_IP}" "0"
}

install_tunnel_system_config() {
    local name="$1"

    preflight_ready || {
        error "System prerequisites are not ready."
        pause
        return 1
    }

    load_tunnel "${name}" || return 1

    section "INSTALLATION PLAN"

    printf '%-28s %s\n' "Tunnel:" "${NAME}"
    printf '%-28s %s\n' "Debian public IP:" "${PUBLIC_IP}"
    printf '%-28s %s\n' "VTI interface:" "${VTI_INTERFACE}"
    printf '%-28s %s\n' "VTI network:" "${VTI_NETWORK}"
    printf '%-28s %s\n' "Debian VTI IP:" "${DEBIAN_VTI_IP}"
    printf '%-28s %s\n' "UniFi VTI IP:" "${UNIFI_VTI_IP}"
    printf '%-28s %s\n' "Authentication ID:" "${AUTH_ID}"

    echo
    echo "System changes:"
    echo "  + managed strongSwan connection"
    echo "  + managed VTI startup script"
    echo "  + managed systemd VTI service"
    echo "  + table 220 return routes"
    echo "  + shared UFW IPsec rules for UDP 500 / 4500 (if UFW is available)"
    echo

    confirm_yes_no "Install this tunnel on the Debian system?" "N" || return

    ensure_shared_firewall_rules "${PUBLIC_IP}" || {
        error "Firewall step cancelled or failed."
        pause
        return 1
    }

    echo
    section "INSTALLING TUNNEL"

    printf '[1/6] Writing strongSwan configuration... '
    render_strongswan_config "${name}" &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; pause; return 1; }

    printf '[2/6] Writing VTI script... '
    render_vti_script "${name}" &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; pause; return 1; }

    printf '[3/6] Writing systemd service... '
    render_systemd_service "${name}" &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; pause; return 1; }

    printf '[4/6] Reloading systemd... '
    systemctl daemon-reload &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; pause; return 1; }

    printf '[5/6] Enabling / starting VTI service... '
    if systemctl enable --now "$(managed_service_name "${name}")" >/tmp/s2s-manager-vti.log 2>&1; then
        printf '%b\n' "${C_GREEN}OK${C_RESET}"
    else
        printf '%b\n' "${C_RED}FAILED${C_RESET}"
        cat /tmp/s2s-manager-vti.log
        pause
        return 1
    fi

    printf '[6/6] Loading strongSwan configuration... '
    if swanctl --load-all >/tmp/s2s-manager-swanctl.log 2>&1; then
        printf '%b\n' "${C_GREEN}OK${C_RESET}"
    else
        printf '%b\n' "${C_RED}FAILED${C_RESET}"
        cat /tmp/s2s-manager-swanctl.log
        pause
        return 1
    fi

    mark_tunnel_installed "${name}"

    echo
    ok "Tunnel '${name}' is installed on Debian."
    info "The IPsec SA will remain waiting until the UniFi side is configured."
    pause
}

remove_tunnel_system_config() {
    local name="$1"
    load_tunnel "${name}" || return 1

    warn "This will remove the managed system configuration for tunnel '${name}'."
    echo
    echo "It will remove:"
    echo "  - $(managed_swan_file "${name}")"
    echo "  - $(managed_vti_script "${name}")"
    echo "  - $(managed_service_file "${name}")"
    echo "  - ${VTI_INTERFACE} (if present)"
    echo
    echo "State / PSK files will be kept unless you delete the tunnel definition separately."
    echo

    confirm_yes_no "Remove installed tunnel configuration?" "N" || return

    systemctl disable --now "$(managed_service_name "${name}")" >/dev/null 2>&1 || true
    ip link del "${VTI_INTERFACE}" >/dev/null 2>&1 || true

    rm -f \
        "$(managed_swan_file "${name}")" \
        "$(managed_vti_script "${name}")" \
        "$(managed_service_file "${name}")"

    systemctl daemon-reload
    swanctl --load-all >/dev/null 2>&1 || true

    mark_tunnel_defined "${name}"

    if (( $(installed_tunnel_count) == 0 )) && ufw_installed; then
        echo
        warn "No other managed S2S tunnels are installed."
        if confirm_yes_no "Remove shared S2S Manager UFW rules?" "Y"; then
            remove_managed_ufw_rules
            ok "Managed UFW rules removed."
        fi
    fi

    ok "Installed system configuration removed."
    pause
}

installed_tunnel_count() {
    local count=0 name
    while read -r name; do
        [[ -z "${name}" ]] && continue
        load_tunnel "${name}" || continue
        [[ "${INSTALLED}" == "1" ]] && ((count += 1))
    done < <(list_tunnel_names)
    printf '%d' "${count}"
}


tunnel_is_installed() {
    local name="$1"

    # Primary source: manager state.
    if load_tunnel "${name}" 2>/dev/null && [[ "${INSTALLED:-0}" == "1" ]]; then
        return 0
    fi

    # Fallbacks: detect an actually installed manager-owned tunnel even if
    # the state flag is stale or was unexpectedly overwritten in memory.
    if [[ -f "$(managed_swan_file "${name}")" ]] ||
       [[ -f "$(managed_vti_script "${name}")" ]] ||
       [[ -f "$(managed_service_file "${name}")" ]]; then
        return 0
    fi

    if systemctl list-unit-files "$(managed_service_name "${name}")" 2>/dev/null |
       grep -Fq "$(managed_service_name "${name}")"; then
        return 0
    fi

    return 1
}

# ==============================================================================
# Re-apply installed tunnel from saved state
# ==============================================================================

reapply_installed_tunnel() {
    local name="$1"
    local mode="${2:-changed}"

    load_tunnel "${name}" || return 1

    echo
    info "Tunnel '${name}' is currently installed."

    if [[ "${mode}" == "manual" ]]; then
        echo "The manager will regenerate and re-apply the Debian-side configuration"
        echo "from the currently saved tunnel definition."
    else
        echo "The saved configuration has changed."
        echo
        echo "The manager can re-apply the Debian-side configuration now."
    fi

    echo
    echo "The existing PSK is kept unchanged."
    echo "No UniFi-side settings need to be changed."
    echo

    if [[ "${mode}" == "manual" ]]; then
        confirm_yes_no "Re-apply this tunnel now?" "Y" || return 0
    else
        confirm_yes_no "Apply the updated configuration now?" "Y" || {
            warn "Change saved in manager state only."
            info "The installed tunnel still uses the previous generated configuration."
            return 0
        }
    fi

    section "RE-APPLYING TUNNEL"

    printf '[1/6] Rewriting strongSwan configuration... '
    render_strongswan_config "${name}" &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; return 1; }

    printf '[2/6] Rewriting VTI script... '
    render_vti_script "${name}" &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; return 1; }

    printf '[3/6] Rewriting systemd service... '
    render_systemd_service "${name}" &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; return 1; }

    printf '[4/6] Reloading systemd... '
    systemctl daemon-reload &&
        printf '%b\n' "${C_GREEN}OK${C_RESET}" ||
        { printf '%b\n' "${C_RED}FAILED${C_RESET}"; return 1; }

    printf '[5/6] Re-applying VTI and routes... '
    if "$(managed_vti_script "${name}")" >/tmp/s2s-manager-reapply-vti.log 2>&1; then
        printf '%b\n' "${C_GREEN}OK${C_RESET}"
    else
        printf '%b\n' "${C_RED}FAILED${C_RESET}"
        cat /tmp/s2s-manager-reapply-vti.log
        return 1
    fi

    printf '[6/6] Reloading strongSwan configuration... '
    if swanctl --load-all >/tmp/s2s-manager-reapply-swanctl.log 2>&1; then
        printf '%b\n' "${C_GREEN}OK${C_RESET}"
    else
        printf '%b\n' "${C_RED}FAILED${C_RESET}"
        cat /tmp/s2s-manager-reapply-swanctl.log
        return 1
    fi

    echo
    ok "Updated configuration applied."
    return 0
}

manual_reapply_tunnel() {
    banner
    section "RE-APPLY INSTALLED TUNNEL"

    select_tunnel || return

    local name="${SELECTED_TUNNEL}"
    load_tunnel "${name}" || return

    if [[ "${INSTALLED}" != "1" ]]; then
        warn "Tunnel '${name}' is not installed on Debian."
        echo "Use 'Install defined tunnel on Debian' first."
        pause
        return
    fi

    echo
    printf '%-28s %s\n' "Tunnel:" "${NAME}"
    printf '%-28s %s\n' "VTI interface:" "${VTI_INTERFACE}"
    printf '%-28s %s\n' "Tunnel network:" "${VTI_NETWORK}"
    printf '%-28s %s\n' "Authentication ID:" "${AUTH_ID}"
    echo
    info "Re-apply regenerates the manager-owned strongSwan, VTI and systemd"
    echo "configuration from the saved definition."
    echo
    echo "The PSK is NOT regenerated."
    echo "The tunnel definition is NOT changed."
    echo "The UniFi configuration is NOT changed."
    echo

    reapply_installed_tunnel "${name}" "manual" || {
        error "Re-applying tunnel '${name}' failed."
        pause
        return 1
    }

    pause
}

# ==============================================================================
# Create / edit state
# ==============================================================================

add_tunnel_definition() {
    banner
    section "ADD SITE-TO-SITE TUNNEL"

    local detected_ip
    detected_ip="$(detect_public_ipv4)"
    [[ -n "${detected_ip}" ]] || detected_ip="0.0.0.0"

    local tunnel_number suggested_name
    tunnel_number=$(( $(tunnel_count) + 1 ))
    suggested_name="home"
    (( tunnel_number > 1 )) && suggested_name="s2s-${tunnel_number}"

    section "STEP 1/6  Tunnel Name"
    prompt_tunnel_name "${suggested_name}"
    local name="${PROMPT_RESULT}"

    section "STEP 2/6  Debian Public IP"
    prompt_public_ip "${detected_ip}"
    local public_ip="${PROMPT_RESULT}"

    section "STEP 3/6  Site-to-Site Tunnel Network"
    local suggested_network
    suggested_network="$(next_vti_network)"
    prompt_tunnel_network "${suggested_network}" || return

    local network="${PROMPT_NETWORK}"
    local debian_ip="${PROMPT_DEBIAN_IP}"
    local unifi_ip="${PROMPT_UNIFI_IP}"

    section "STEP 4/6  UniFi Authentication ID"
    prompt_auth_id "unifi-${name}"
    local auth_id="${PROMPT_RESULT}"

    section "STEP 5/6  Remote Networks"
    prompt_remote_networks
    local -a routes=("${PROMPT_ROUTES[@]:-}")

    section "STEP 6/6  Pre-Shared Key"
    prompt_psk || return
    local psk="${PROMPT_PSK}"

    local idx interface key
    idx="$(next_interface_index)"
    interface="ipsec${idx}"
    key=$((DEFAULT_VTI_KEY + idx))

    section "CONFIGURATION SUMMARY"

    printf '%-28s %s\n' "Tunnel name:" "${name}"
    printf '%-28s %s\n' "Debian public IP:" "${public_ip}"
    printf '%-28s %s\n' "Authentication ID:" "${auth_id}"
    printf '%-28s %s\n' "VTI interface:" "${interface}"
    printf '%-28s %s\n' "VTI key / mark:" "${key}"
    printf '%-28s %s\n' "Tunnel network:" "${network}"
    printf '%-28s %s\n' "Debian VTI IP:" "${debian_ip}"
    printf '%-28s %s\n' "UniFi VTI IP:" "${unifi_ip}"

    echo
    echo "Remote networks:"
    if (( ${#routes[@]} == 0 )); then
        echo "  None"
    else
        local r
        for r in "${routes[@]}"; do printf '  • %s\n' "${r}"; done
    fi

    echo
    confirm_yes_no "Save tunnel definition?" "N" || return

    save_tunnel "${name}" "${public_ip}" "${auth_id}" "${interface}" "${key}" \
        "${network}" "${debian_ip}" "${unifi_ip}" "0"
    write_routes "${name}" "${routes[@]:-}"
    save_psk "${name}" "${psk}"

    ok "Tunnel definition saved."

    echo
    if preflight_ready; then
        if confirm_yes_no "Install this tunnel on Debian now?" "N"; then
            install_tunnel_system_config "${name}"
            return
        fi
    else
        warn "System prerequisites are not ready, so the tunnel definition was saved only."
    fi

    pause
}

add_remote_network() {
    banner
    section "ADD REMOTE NETWORK"
    select_tunnel || return

    local name="${SELECTED_TUNNEL}"
    load_tunnel "${name}" || return

    echo "Current remote networks:"
    local route count=0
    while read -r route; do
        [[ -z "${route}" ]] && continue
        printf '  • %s\n' "${route}"
        ((count += 1))
    done < <(read_routes "${name}")
    (( count == 0 )) && echo "  None"

    echo
    echo "Enter a CIDR network, e.g. 192.168.50.0/24"
    echo "Press ENTER or B to go back. E = Exit."
    echo

    local new_route
    while :; do
        read -r -p "New remote network: " new_route
        case "${new_route}" in
            ""|b|B|0) return ;;
            e|E) clear_screen; echo "Bye."; exit 0 ;;
        esac

        valid_cidr "${new_route}" || { error "Invalid CIDR network."; echo; continue; }
        read_routes "${name}" | grep -Fxq "${new_route}" &&
            { warn "Network already configured."; echo; continue; }

        confirm_yes_no "Add ${new_route}?" "N" || return

        printf '%s\n' "${new_route}" >> "$(tunnel_route_file "${name}")"
        chmod 600 "$(tunnel_route_file "${name}")"

        ok "Remote network added to manager state."
        printf '  State file: %s\n' "$(tunnel_route_file "${name}")"

        if tunnel_is_installed "${name}"; then
            echo
            reapply_installed_tunnel "${name}" || {
                error "State was updated, but re-applying the installed tunnel failed."
                pause
                return 1
            }
        else
            info "Tunnel is only defined, so no live system configuration needs updating."
        fi

        pause
        return
    done
}

remove_remote_network() {
    banner
    section "REMOVE REMOTE NETWORK"
    select_tunnel || return

    local name="${SELECTED_TUNNEL}"
    load_tunnel "${name}" || return

    local -a routes=()
    local route
    while read -r route; do
        [[ -n "${route}" ]] && routes+=("${route}")
    done < <(read_routes "${name}")

    (( ${#routes[@]} > 0 )) || { warn "No remote networks configured."; pause; return; }

    local i selection
    for i in "${!routes[@]}"; do
        printf '  [%d] %s\n' "$((i + 1))" "${routes[$i]}"
    done
    echo
    echo "Enter network number and press ENTER."
    echo "B = Back    E = Exit"
    echo
    read -r -p "Selection: " selection

    case "${selection}" in
        ""|b|B|0) return ;;
        e|E) clear_screen; echo "Bye."; exit 0 ;;
    esac
    [[ "${selection}" =~ ^[0-9]+$ ]] || return
    (( selection >= 1 && selection <= ${#routes[@]} )) || return

    local remove="${routes[$((selection - 1))]}"
    confirm_yes_no "Remove ${remove}?" "N" || return

    local file
    file="$(tunnel_route_file "${name}")"
    grep -Fxv "${remove}" "${file}" > "${file}.tmp" || true
    mv "${file}.tmp" "${file}"
    chmod 600 "${file}"

    ok "Remote network removed from manager state."
    printf '  State file: %s\n' "$(tunnel_route_file "${name}")"

    if tunnel_is_installed "${name}"; then
        # Reload the tunnel state because tunnel_is_installed() may source it.
        load_tunnel "${name}" || return 1

        # Remove the live route immediately if present, then regenerate from state.
        ip route del "${remove}" dev "${VTI_INTERFACE}" table 220 >/dev/null 2>&1 || true

        echo
        reapply_installed_tunnel "${name}" || {
            error "State was updated, but re-applying the installed tunnel failed."
            pause
            return 1
        }
    else
        info "Tunnel is only defined, so no live system configuration needs updating."
    fi

    pause
}

delete_tunnel_definition() {
    banner
    section "DELETE TUNNEL"
    select_tunnel || return

    local name="${SELECTED_TUNNEL}"
    load_tunnel "${name}" || return

    if [[ "${INSTALLED}" == "1" ]]; then
        error "Tunnel is currently installed."
        echo "Remove its installed system configuration first."
        pause
        return
    fi

    echo "Tunnel: ${name}"
    echo
    echo "This removes its state and PSK files."
    echo
    read -r -p "Type DELETE to confirm: " confirm
    [[ "${confirm}" == "DELETE" ]] || return

    rm -f \
        "$(tunnel_config_file "${name}")" \
        "$(tunnel_route_file "${name}")" \
        "$(tunnel_secret_file "${name}")"

    ok "Tunnel definition deleted."
    pause
}

# ==============================================================================
# Configuration views
# ==============================================================================

show_tunnel_details() {
    local name="$1"
    load_tunnel "${name}" || return 1

    section "Tunnel configuration: ${name}"

    printf '%-28s %s\n' "Name:" "${NAME}"
    printf '%-28s %s\n' "State:" "$([[ "${INSTALLED}" == "1" ]] && echo INSTALLED || echo DEFINED)"
    printf '%-28s %s\n' "Debian public IP:" "${PUBLIC_IP}"
    printf '%-28s %s\n' "Authentication ID:" "${AUTH_ID}"
    printf '%-28s %s\n' "VTI interface:" "${VTI_INTERFACE}"
    printf '%-28s %s\n' "VTI key / mark:" "${VTI_KEY}"
    printf '%-28s %s\n' "Tunnel network:" "${VTI_NETWORK}"
    printf '%-28s %s\n' "Debian VTI IP:" "${DEBIAN_VTI_IP}"
    printf '%-28s %s\n' "UniFi VTI IP:" "${UNIFI_VTI_IP}"

    echo
    echo "Remote networks:"
    local r count=0
    while read -r r; do
        [[ -z "${r}" ]] && continue
        printf '  • %s\n' "${r}"
        ((count += 1))
    done < <(read_routes "${name}")
    (( count == 0 )) && echo "  None"
}

show_configuration() {
    banner
    section "SHOW TUNNEL CONFIGURATION"
    select_tunnel || return
    show_tunnel_details "${SELECTED_TUNNEL}"
    pause
}

print_unifi_config() {
    local name="$1"
    local show_psk="${2:-0}"
    load_tunnel "${name}" || return 1

    local psk_display="••••••••••••••••••••••••••••••••••••••••"
    if (( show_psk == 1 )); then
        psk_display="$(read_psk "${name}" 2>/dev/null || echo '[PSK file not found]')"
    fi

    banner
    printf '%b' "${C_CYAN}${C_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    printf '║  %-58s║\n' "UniFi Site-to-Site Configuration"
    printf '║  %-58s║\n' "${NAME}"
    echo "╚══════════════════════════════════════════════════════════════╝"
    printf '%b' "${C_RESET}"

    section "VPN"
    printf '%-32s %s\n' "VPN Type:" "IPsec"
    printf '%-32s %s\n' "Name:" "${NAME}"
    printf '%-32s %s\n' "Pre-Shared Key:" "${psk_display}"

    section "CONNECTION"
    printf '%-32s %s\n' "Local IP:" "Select UniFi WAN interface"
    printf '%-32s %s\n' "Remote IP / Hostname:" "${PUBLIC_IP}"

    section "NETWORK CONFIGURATION"
    printf '%-32s %s\n' "VPN Method:" "Route Based"
    printf '%-32s %s\n' "Tunnel IP:" "Enabled"
    printf '%-32s %s\n' "IPv4 Address:" "${UNIFI_VTI_IP}"
    printf '%-32s %s\n' "Netmask:" "30"
    printf '%-32s %s\n' "Remote Subnets:" "None"

    section "ADVANCED"
    printf '%-32s %s\n' "Mode:" "Manual"
    printf '%-32s %s\n' "Key Exchange Version:" "IKEv2"

    echo
    printf '%b\n' "${C_BOLD}IKE${C_RESET}"
    printf '%-24s %-18s %-24s %s\n' "Encryption:" "AES-256" "Hash:" "SHA256"
    printf '%-24s %-18s %-24s %s\n' "DH Group:" "14" "Lifetime:" "28800"

    echo
    printf '%b\n' "${C_BOLD}ESP${C_RESET}"
    printf '%-24s %-18s %-24s %s\n' "Encryption:" "AES-256" "Hash:" "SHA256"
    printf '%-24s %-18s %-24s %s\n' "DH Group:" "14" "Lifetime:" "3600"

    echo
    printf '%-32s %s\n' "Perfect Forward Secrecy:" "Enabled"
    printf '%-32s %s\n' "Local Authentication ID:" "${AUTH_ID}"
    printf '%-32s %s\n' "Remote Authentication ID:" "${PUBLIC_IP}"
    printf '%-32s %s\n' "Maximum Transmission Unit:" "Auto"
    printf '%-32s %s\n' "Maximum Segment Size:" "Auto"
    echo
}

show_unifi_configuration() {
    banner
    section "SHOW UNIFI CONFIGURATION"
    select_tunnel || return

    local tunnel="${SELECTED_TUNNEL}"
    local show_psk=0 choice

    while :; do
        print_unifi_config "${tunnel}" "${show_psk}"
        line

        if (( show_psk == 0 )); then
            echo "  [1] Show Pre-Shared Key"
        else
            echo "  [1] Hide Pre-Shared Key"
        fi
        echo "  [B] Back"
        echo "  [E] Exit"
        echo

        read -r -p "Selection: " choice
        case "${choice}" in
            1)
                if (( show_psk == 0 )); then
                    warn "The Pre-Shared Key is sensitive information."
                    confirm_yes_no "Show PSK?" "N" && show_psk=1
                else
                    show_psk=0
                fi
                ;;
            0|""|b|B) return ;;
            e|E) clear_screen; echo "Bye."; exit 0 ;;
            *) error "Invalid selection."; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# Tunnel install/remove menu
# ==============================================================================

install_defined_tunnel() {
    banner
    section "INSTALL TUNNEL ON DEBIAN"
    select_tunnel || return

    load_tunnel "${SELECTED_TUNNEL}" || return
    if [[ "${INSTALLED}" == "1" ]]; then
        warn "This tunnel is already marked as installed."
        pause
        return
    fi

    install_tunnel_system_config "${SELECTED_TUNNEL}"
}

remove_installed_tunnel() {
    banner
    section "REMOVE INSTALLED TUNNEL"
    select_tunnel || return

    load_tunnel "${SELECTED_TUNNEL}" || return
    if [[ "${INSTALLED}" != "1" ]]; then
        warn "This tunnel is not installed."
        pause
        return
    fi

    remove_tunnel_system_config "${SELECTED_TUNNEL}"
}

show_system_status() {
    banner
    section "SYSTEM STATUS"

    show_preflight || true

    echo
    section "MANAGED TUNNELS"
    show_existing_tunnels

    echo
    section "STRONGSWAN"
    if systemctl is-active --quiet strongswan 2>/dev/null; then
        ok "strongSwan active"
    else
        warn "strongSwan not active"
    fi

    if command_available swanctl; then
        echo
        swanctl_clean swanctl --list-sas || true
    fi

    echo
    section "FIREWALL"
    if ufw_installed; then
        ufw status | grep -E 'S2S Manager|500/udp|4500/udp|esp' || true
    else
        info "Local UFW not installed (optional)"
        echo "External/provider firewall can be used instead."
        echo "Required for IPsec: UDP 500 and UDP 4500"
    fi

    pause
}


# ==============================================================================
# Tunnel diagnostics
# ==============================================================================

human_bytes() {
    local bytes="${1:-0}"

    if ! [[ "${bytes}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${bytes}"
        return
    fi

    if (( bytes >= 1073741824 )); then
        awk -v b="${bytes}" 'BEGIN { printf "%.2f GiB", b/1073741824 }'
    elif (( bytes >= 1048576 )); then
        awk -v b="${bytes}" 'BEGIN { printf "%.2f MiB", b/1048576 }'
    elif (( bytes >= 1024 )); then
        awk -v b="${bytes}" 'BEGIN { printf "%.2f KiB", b/1024 }'
    else
        printf '%s B' "${bytes}"
    fi
}


human_duration() {
    local seconds="${1:-0}"
    local d h m s

    [[ "${seconds}" =~ ^[0-9]+$ ]] || { printf '%s' "${seconds}"; return; }

    d=$((seconds / 86400))
    h=$(((seconds % 86400) / 3600))
    m=$(((seconds % 3600) / 60))
    s=$((seconds % 60))

    if (( d > 0 )); then
        printf '%dd %02dh %02dm %02ds' "${d}" "${h}" "${m}" "${s}"
    elif (( h > 0 )); then
        printf '%dh %02dm %02ds' "${h}" "${m}" "${s}"
    elif (( m > 0 )); then
        printf '%dm %02ds' "${m}" "${s}"
    else
        printf '%ds' "${s}"
    fi
}

get_tunnel_sa_output() {
    local name="$1"
    local conn="${MANAGED_PREFIX}-${name}"

    swanctl_clean swanctl --list-sas 2>/dev/null | \
        awk -v c="${conn}:" '
            $0 ~ "^" c {show=1}
            show {print}
            show && /^[^[:space:]]/ && $0 !~ "^" c {exit}
        '
}


get_tunnel_connected_since_epoch() {
    local name="$1"
    local conn="${MANAGED_PREFIX}-${name}"
    local line epoch msg id
    local history_known=0
    local connected_since=""
    local active_count=0
    declare -A active_ike=()

    # We only report a continuous connection start if the retained journal
    # contains a reliable anchor. A strongSwan service start is such an anchor:
    # no IKE SA can predate the daemon start.
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue

        epoch="${line%% *}"
        epoch="${epoch%%.*}"
        [[ "${epoch}" =~ ^[0-9]+$ ]] || continue
        msg="${line#* }"

        if [[ "${msg}" == *"Started strongswan.service"* ]] || \
           [[ "${msg}" == *"Started strongSwan IPsec"* ]]; then
            active_ike=()
            active_count=0
            connected_since=""
            history_known=1
            continue
        fi

        if [[ "${msg}" =~ IKE_SA[[:space:]]+${conn}\[([0-9]+)\][[:space:]]+established[[:space:]]+between ]]; then
            id="${BASH_REMATCH[1]}"
            if [[ -z "${active_ike[$id]+x}" ]]; then
                if (( active_count == 0 )) && (( history_known == 1 )); then
                    connected_since="${epoch}"
                fi
                active_ike[$id]=1
                ((active_count += 1))
            fi
            continue
        fi

        if [[ "${msg}" =~ deleting[[:space:]]+IKE_SA[[:space:]]+${conn}\[([0-9]+)\] ]]; then
            id="${BASH_REMATCH[1]}"
            if [[ -n "${active_ike[$id]+x}" ]]; then
                unset 'active_ike[$id]'
                ((active_count -= 1))
                if (( active_count == 0 )); then
                    connected_since=""
                fi
            fi
            continue
        fi
    done < <(journalctl -u strongswan --no-pager -o short-unix 2>/dev/null)

    # If the currently active SA is visible but we have no anchored start in
    # the retained journal, do not guess. Let the caller report that it cannot
    # be determined from logs.
    if (( history_known == 1 )) && (( active_count > 0 )) && [[ -n "${connected_since}" ]]; then
        printf '%s' "${connected_since}"
        return 0
    fi

    return 1
}

show_tunnel_diagnostics() {
    banner
    section "TUNNEL DIAGNOSTICS"

    select_tunnel || return

    local name="${SELECTED_TUNNEL}"
    load_tunnel "${name}" || return

    local service
    service="$(managed_service_name "${name}")"

    printf '%-28s %s\n' "Tunnel:" "${NAME}"
    printf '%-28s %s\n' "Manager state:" "$([[ "${INSTALLED}" == "1" ]] && echo INSTALLED || echo DEFINED)"
    printf '%-28s %s\n' "VTI interface:" "${VTI_INTERFACE}"
    printf '%-28s %s\n' "Debian VTI IP:" "${DEBIAN_VTI_IP}"
    printf '%-28s %s\n' "UniFi VTI IP:" "${UNIFI_VTI_IP}"
    printf '%-28s %s\n' "Tunnel network:" "${VTI_NETWORK}"
    printf '%-28s %s\n' "Authentication ID:" "${AUTH_ID}"

    echo
    section "SERVICE / INTERFACE"

    if systemctl is-active --quiet strongswan 2>/dev/null; then
        ok "strongSwan: active"
    else
        error "strongSwan: inactive"
    fi

    if systemctl is-active --quiet "${service}" 2>/dev/null; then
        ok "${service}: active"
    else
        warn "${service}: not active"
    fi

    if ip link show "${VTI_INTERFACE}" >/dev/null 2>&1; then
        ok "${VTI_INTERFACE}: present"
        local current_addr
        current_addr="$(ip -4 -o addr show dev "${VTI_INTERFACE}" 2>/dev/null | awk '{print $4}' | head -1)"
        printf '%-28s %s\n' "Current VTI address:" "${current_addr:-none}"
    else
        error "${VTI_INTERFACE}: missing"
    fi

    echo
    section "ROUTING"

    local route test_ip lookup
    printf '%-28s %s\n' "Table:" "220"
    while read -r route; do
        [[ -z "${route}" ]] && continue

        if [[ "${route}" == "${VTI_NETWORK}" ]]; then
            test_ip="${UNIFI_VTI_IP}"
        else
            test_ip="${route%%/*}"
        fi

        lookup="$(ip route get "${test_ip}" 2>/dev/null || true)"

        if grep -q "dev ${VTI_INTERFACE}" <<< "${lookup}" && \
           grep -q "table 220" <<< "${lookup}"; then
            ok "${route} -> ${VTI_INTERFACE}"
        else
            error "${route} is not routed via ${VTI_INTERFACE} / table 220"
            [[ -n "${lookup}" ]] && printf '    Kernel lookup: %s\n' "${lookup}"
        fi
    done < <(printf '%s\n' "${VTI_NETWORK}"; read_routes "${name}")

    echo
    section "IPSEC STATUS"

    local sa
    sa="$(get_tunnel_sa_output "${name}")"

    if [[ -z "${sa}" ]]; then
        warn "No active IKE/CHILD SA found."
        printf '%-28s %s\n' "Connection:" "NOT CONNECTED"
    else
        if grep -q 'ESTABLISHED' <<< "${sa}"; then
            ok "IKE: ESTABLISHED"
        else
            warn "IKE: not established"
        fi

        if grep -q 'INSTALLED' <<< "${sa}"; then
            ok "CHILD_SA: INSTALLED"
        else
            warn "CHILD_SA: not installed"
        fi

        if grep -q 'TUNNEL-in-UDP' <<< "${sa}"; then
            ok "Transport: ESP-in-UDP / NAT-T"
        elif grep -q 'TUNNEL' <<< "${sa}"; then
            info "Transport: native ESP tunnel"
        fi

        local established ike_age_seconds child_installed child_age_seconds

        established="$(grep -m1 -oE 'established [0-9]+s ago' <<< "${sa}" || true)"
        if [[ -n "${established}" ]]; then
            ike_age_seconds="$(grep -oE '[0-9]+' <<< "${established}" | head -1)"
            printf '%-28s %s\n' "Current IKE SA age:" "$(human_duration "${ike_age_seconds}")"
        fi

        child_installed="$(grep -m1 -oE 'installed [0-9]+s ago' <<< "${sa}" || true)"
        if [[ -n "${child_installed}" ]]; then
            child_age_seconds="$(grep -oE '[0-9]+' <<< "${child_installed}" | head -1)"
            printf '%-28s %s\n' "Current CHILD SA age:" "$(human_duration "${child_age_seconds}")"
        fi

        local in_bytes out_bytes in_packets out_packets
        in_bytes="$(awk '/^[[:space:]]+in[[:space:]]/ {for(i=1;i<=NF;i++) if($i=="bytes,"){print $(i-1); exit}}' <<< "${sa}")"
        out_bytes="$(awk '/^[[:space:]]+out[[:space:]]/ {for(i=1;i<=NF;i++) if($i=="bytes,"){print $(i-1); exit}}' <<< "${sa}")"
        in_packets="$(awk '/^[[:space:]]+in[[:space:]]/ {for(i=1;i<=NF;i++) if($i=="packets," || $i=="packets"){print $(i-1); exit}}' <<< "${sa}")"
        out_packets="$(awk '/^[[:space:]]+out[[:space:]]/ {for(i=1;i<=NF;i++) if($i=="packets," || $i=="packets"){print $(i-1); exit}}' <<< "${sa}")"

        [[ -n "${in_bytes}" ]] && printf '%-28s %s (%s packets)\n' "Traffic IN:" "$(human_bytes "${in_bytes}")" "${in_packets:-0}"
        [[ -n "${out_bytes}" ]] && printf '%-28s %s (%s packets)\n' "Traffic OUT:" "$(human_bytes "${out_bytes}")" "${out_packets:-0}"
    fi

    while :; do
        echo
        section "OPTIONAL TESTS"

        echo "  [1] Ping UniFi VTI address"
        echo "      Test connectivity to ${UNIFI_VTI_IP}"
        echo
        echo "  [2] Analyze connection uptime"
        echo "      Determine continuous connection time from strongSwan logs."
        echo "      This may take several seconds."
        echo
        echo "  [3] Show recent strongSwan logs"
        echo
        echo "  [B] Back"
        echo "  [E] Exit"
        echo

        local choice connected_since_epoch now_epoch connected_for_seconds
        read -r -p "Selection: " choice

        case "${choice}" in
            1)
                echo
                section "CONNECTIVITY TEST"
                echo "Pinging UniFi VTI address ${UNIFI_VTI_IP}..."
                echo

                if ping -c 3 -W 2 "${UNIFI_VTI_IP}" >/tmp/s2s-manager-diag-ping.log 2>&1; then
                    ok "Ping to ${UNIFI_VTI_IP}: SUCCESS"
                    tail -2 /tmp/s2s-manager-diag-ping.log
                else
                    error "Ping to ${UNIFI_VTI_IP}: FAILED"
                    cat /tmp/s2s-manager-diag-ping.log
                fi
                pause
                ;;
            2)
                echo
                section "CONNECTION UPTIME"
                echo "Analyzing strongSwan connection history..."
                echo "This may take several seconds."
                echo

                connected_since_epoch="$(get_tunnel_connected_since_epoch "${name}" 2>/dev/null || true)"
                if [[ -n "${connected_since_epoch}" ]]; then
                    now_epoch="$(date +%s)"
                    connected_for_seconds=$((now_epoch - connected_since_epoch))
                    if (( connected_for_seconds >= 0 )); then
                        printf '%-28s %s\n' "Connected for:" "$(human_duration "${connected_for_seconds}")"
                    else
                        printf '%-28s %s\n' "Connected for:" "Cannot be determined from available logs"
                    fi
                else
                    printf '%-28s %s\n' "Connected for:" "Cannot be determined from available logs"
                fi
                pause
                ;;
            3)
                echo
                section "RECENT STRONGSWAN LOGS"
                journalctl -u strongswan -n 30 --no-pager |
                    sed \
                        -e '/agent plugin requires CAP_SETUID\/CAP_SETGID capability/d' \
                        -e "/plugin 'agent': failed to load - agent_plugin_create returned NULL/d"
                pause
                ;;
            [bB]|0)
                return
                ;;
            [eE])
                clear_screen
                echo "Bye."
                exit 0
                ;;
            *)
                error "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# Menus
# ==============================================================================

setup_required_menu() {
    while ! preflight_ready; do
        banner
        show_preflight || true

        section "SETUP REQUIRED"
        echo "  [1] Install / repair prerequisites"
        echo "  [2] Run pre-flight check again"
        echo "  [E] Exit"
        echo

        local choice
        read -r -p "Selection: " choice

        case "${choice}" in
            1) install_or_repair_prerequisites ;;
            2) ;;
            e|E|0) clear_screen; echo "Bye."; exit 0 ;;
            *) error "Invalid selection."; sleep 1 ;;
        esac
    done
}

main_menu() {
    while :; do
        banner

        section "CONFIGURED TUNNELS"
        show_existing_tunnels

        section "MENU"
        echo "  [1] Show tunnel configuration"
        echo "  [2] Add S2S tunnel definition"
        echo "  [3] Add remote network"
        echo "  [4] Remove remote network"
        echo "  [5] Install defined tunnel on Debian"
        echo "  [6] Remove installed tunnel from Debian"
        echo "  [7] Delete tunnel definition"
        echo "  [8] Show UniFi configuration"
        echo "  [9] Tunnel diagnostics"
        echo "  [10] Show system status"
        echo "  [11] Re-apply installed tunnel"
        echo "  [E] Exit"
        echo

        local choice
        read -r -p "Selection: " choice

        case "${choice}" in
            1) show_configuration ;;
            2) add_tunnel_definition ;;
            3) add_remote_network ;;
            4) remove_remote_network ;;
            5) install_defined_tunnel ;;
            6) remove_installed_tunnel ;;
            7) delete_tunnel_definition ;;
            8) show_unifi_configuration ;;
            9) show_tunnel_diagnostics ;;
            10) show_system_status ;;
            11) manual_reapply_tunnel ;;
            [eE]|0) clear_screen; echo "Bye."; exit 0 ;;
            *) error "Invalid selection."; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# Start
# ==============================================================================

ensure_root
init_state_dirs

setup_required_menu
main_menu
