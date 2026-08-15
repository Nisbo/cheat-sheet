#!/usr/bin/env bash

# ==============================================================================
# UniFi <-> Debian IPsec S2S Manager
# TEST VERSION - CONFIGURATION / STATE MANAGEMENT ONLY
#
# This script DOES NOT:
#   - install packages
#   - modify strongSwan
#   - modify UFW
#   - modify routes
#   - create VTI interfaces
#   - modify systemd
#
# All test data is stored below:
#   /root/s2s-manager-test/
# ==============================================================================

set -u

STATE_DIR="/root/s2s-manager-test"
TUNNEL_DIR="${STATE_DIR}/tunnels"
ROUTE_DIR="${STATE_DIR}/routes"
SECRET_DIR="${STATE_DIR}/secrets"

DEFAULT_NET_PREFIX_A=10
DEFAULT_NET_PREFIX_B=200
DEFAULT_NET_START_C=201

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------

if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_CYAN="\033[36m"
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

# ------------------------------------------------------------------------------
# UI helpers
# ------------------------------------------------------------------------------

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

    printf '%b\n' "${C_CYAN}${C_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 UniFi IPsec S2S Manager                    ║"
    echo "║                Configuration Test Version                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    printf '%b' "${C_RESET}"

    echo
    printf '%b\n' "${C_YELLOW}${C_BOLD}TEST MODE${C_RESET}"
    echo
    echo "This version only manages configuration data."
    echo "It does NOT change networking, strongSwan, UFW or systemd."
    echo
    echo "Test data directory:"
    printf '  %b%s%b\n' "${C_CYAN}" "${STATE_DIR}" "${C_RESET}"
    echo
}

section() {
    echo
    line
    printf '  %b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
    line
    echo
}

# ------------------------------------------------------------------------------
# Environment
# ------------------------------------------------------------------------------

ensure_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "This test manager must be run as root."
        exit 1
    fi
}

init_state_dirs() {
    mkdir -p "${TUNNEL_DIR}" "${ROUTE_DIR}" "${SECRET_DIR}"
    chmod 700 "${STATE_DIR}" "${TUNNEL_DIR}" "${ROUTE_DIR}" "${SECRET_DIR}"
}

detect_public_ipv4() {
    local ip=""

    ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '
            {
                for (i=1; i<=NF; i++) {
                    if ($i == "src") {
                        print $(i+1)
                        exit
                    }
                }
            }'
    )

    printf '%s' "${ip}"
}

# ------------------------------------------------------------------------------
# IPv4 helpers
# ------------------------------------------------------------------------------

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

    return 0
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
    local ip prefix
    local n network

    if [[ "${input}" == */* ]]; then
        ip="${input%%/*}"
        prefix="${input##*/}"
    else
        ip="${input}"
        prefix="30"
    fi

    valid_ipv4 "${ip}" || return 1

    if [[ "${prefix}" != "30" ]]; then
        return 2
    fi

    n=$(ipv4_to_int "${ip}")
    network=$(( n & 0xFFFFFFFC ))

    printf '%s/30' "$(int_to_ipv4 "${network}")"
}

network_base_ip() {
    printf '%s' "${1%%/*}"
}

calculate_30_addresses() {
    local network="$1"
    local base
    local n

    base=$(network_base_ip "${network}")
    n=$(ipv4_to_int "${base}")

    CALC_NETWORK="$(int_to_ipv4 "${n}")/30"
    CALC_DEBIAN="$(int_to_ipv4 "$((n + 1))")"
    CALC_UNIFI="$(int_to_ipv4 "$((n + 2))")"
    CALC_BROADCAST="$(int_to_ipv4 "$((n + 3))")"
}

network_is_exact_base() {
    local input="$1"
    local ip normalized

    ip="${input%%/*}"
    normalized=$(normalize_30_network "${input}") || return 1

    [[ "${ip}" == "${normalized%%/*}" ]]
}

networks_overlap_30() {
    local net1="$1"
    local net2="$2"

    [[ "${net1}" == "${net2}" ]]
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

valid_tunnel_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$ ]]
}

valid_auth_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$ ]]
}

valid_cidr() {
    local input="$1"
    local ip prefix

    [[ "${input}" == */* ]] || return 1

    ip="${input%%/*}"
    prefix="${input##*/}"

    valid_ipv4 "${ip}" || return 1
    [[ "${prefix}" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 )) || return 1

    return 0
}

# ------------------------------------------------------------------------------
# State helpers
# ------------------------------------------------------------------------------

tunnel_config_file() {
    printf '%s/%s.conf' "${TUNNEL_DIR}" "$1"
}

tunnel_route_file() {
    printf '%s/%s.routes' "${ROUTE_DIR}" "$1"
}

tunnel_secret_file() {
    printf '%s/%s.psk' "${SECRET_DIR}" "$1"
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
    local count=0
    local name

    while read -r name; do
        [[ -n "${name}" ]] && ((count += 1))
    done < <(list_tunnel_names)

    printf '%d' "${count}"
}

load_tunnel() {
    local name="$1"
    local file

    file=$(tunnel_config_file "${name}")

    [[ -f "${file}" ]] || return 1

    unset NAME PUBLIC_IP AUTH_ID VTI_INTERFACE VTI_KEY
    unset VTI_NETWORK DEBIAN_VTI_IP UNIFI_VTI_IP CREATED_AT

    # shellcheck disable=SC1090
    source "${file}"
}

auth_id_in_use() {
    local wanted="$1"
    local ignore_name="${2:-}"
    local name

    while read -r name; do
        [[ -z "${name}" ]] && continue
        [[ "${name}" == "${ignore_name}" ]] && continue

        load_tunnel "${name}" || continue

        if [[ "${AUTH_ID}" == "${wanted}" ]]; then
            return 0
        fi
    done < <(list_tunnel_names)

    return 1
}

network_in_use() {
    local wanted="$1"
    local ignore_name="${2:-}"
    local name

    while read -r name; do
        [[ -z "${name}" ]] && continue
        [[ "${name}" == "${ignore_name}" ]] && continue

        load_tunnel "${name}" || continue

        if networks_overlap_30 "${VTI_NETWORK}" "${wanted}"; then
            return 0
        fi
    done < <(list_tunnel_names)

    return 1
}

next_interface_index() {
    local index=0

    while :; do
        local used=0
        local name

        while read -r name; do
            [[ -z "${name}" ]] && continue

            load_tunnel "${name}" || continue

            if [[ "${VTI_INTERFACE}" == "ipsec${index}" ]]; then
                used=1
                break
            fi
        done < <(list_tunnel_names)

        if (( used == 0 )); then
            printf '%d' "${index}"
            return
        fi

        ((index += 1))
    done
}

next_vti_key() {
    local idx
    idx=$(next_interface_index)
    printf '%d' "$((42 + idx))"
}

next_vti_network() {
    local c

    for (( c=DEFAULT_NET_START_C; c<=250; c++ )); do
        local candidate="${DEFAULT_NET_PREFIX_A}.${DEFAULT_NET_PREFIX_B}.${c}.0/30"

        if ! network_in_use "${candidate}"; then
            printf '%s' "${candidate}"
            return
        fi
    done

    printf '10.200.251.0/30'
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

    local config
    config=$(tunnel_config_file "${name}")

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
    } > "${config}"

    chmod 600 "${config}"
}

write_routes() {
    local name="$1"
    shift

    local file
    file=$(tunnel_route_file "${name}")

    : > "${file}"

    local route

    for route in "$@"; do
        [[ -n "${route}" ]] && printf '%s\n' "${route}" >> "${file}"
    done

    chmod 600 "${file}"
}

read_routes() {
    local name="$1"
    local file

    file=$(tunnel_route_file "${name}")

    [[ -f "${file}" ]] || return 0

    cat "${file}"
}

generate_psk() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 | tr -d '\n'
        return
    fi

    return 1
}

save_psk() {
    local name="$1"
    local psk="$2"
    local file

    file=$(tunnel_secret_file "${name}")

    printf '%s\n' "${psk}" > "${file}"
    chmod 600 "${file}"
}

# ------------------------------------------------------------------------------
# Display
# ------------------------------------------------------------------------------

show_existing_tunnels() {
    local count
    count=$(tunnel_count)

    if (( count == 0 )); then
        info "No existing test tunnels found."
        return
    fi

    printf '%-4s %-16s %-12s %-20s %-24s\n' \
        "#" "Name" "Interface" "Tunnel Network" "Authentication ID"

    printf '%-4s %-16s %-12s %-20s %-24s\n' \
        "──" "────────────────" "────────────" "────────────────────" "────────────────────────"

    local index=1
    local name

    while read -r name; do
        [[ -z "${name}" ]] && continue

        load_tunnel "${name}" || continue

        printf '%-4s %-16s %-12s %-20s %-24s\n' \
            "${index}" \
            "${NAME}" \
            "${VTI_INTERFACE}" \
            "${VTI_NETWORK}" \
            "${AUTH_ID}"

        ((index += 1))
    done < <(list_tunnel_names)
}

show_tunnel_details() {
    local name="$1"

    load_tunnel "${name}" || {
        error "Tunnel not found: ${name}"
        return 1
    }

    section "Tunnel configuration: ${name}"

    printf '%-26s %s\n' "Name:" "${NAME}"
    printf '%-26s %s\n' "Debian public IP:" "${PUBLIC_IP}"
    printf '%-26s %s\n' "Authentication ID:" "${AUTH_ID}"
    printf '%-26s %s\n' "VTI interface:" "${VTI_INTERFACE}"
    printf '%-26s %s\n' "VTI key / mark:" "${VTI_KEY}"
    printf '%-26s %s\n' "Tunnel network:" "${VTI_NETWORK}"
    printf '%-26s %s\n' "Debian VTI IP:" "${DEBIAN_VTI_IP}"
    printf '%-26s %s\n' "UniFi VTI IP:" "${UNIFI_VTI_IP}"

    echo
    echo "Remote networks:"

    local route_count=0
    local route

    while read -r route; do
        [[ -z "${route}" ]] && continue
        printf '  • %s\n' "${route}"
        ((route_count += 1))
    done < <(read_routes "${name}")

    if (( route_count == 0 )); then
        echo "  None"
    fi

    echo
    printf '%-26s %s\n' "PSK file:" "$(tunnel_secret_file "${name}")"
}

select_tunnel() {
    local -a names=()
    local name

    while read -r name; do
        [[ -n "${name}" ]] && names+=("${name}")
    done < <(list_tunnel_names)

    if (( ${#names[@]} == 0 )); then
        warn "No tunnels configured."
        return 1
    fi

    echo
    local i

    for i in "${!names[@]}"; do
        printf '  [%d] %s\n' "$((i + 1))" "${names[$i]}"
    done

    echo
    read -r -p "Selection: " selection

    [[ "${selection}" =~ ^[0-9]+$ ]] || return 1

    if (( selection < 1 || selection > ${#names[@]} )); then
        return 1
    fi

    SELECTED_TUNNEL="${names[$((selection - 1))]}"
    return 0
}

# ------------------------------------------------------------------------------
# Prompt helpers
# ------------------------------------------------------------------------------

prompt_public_ip() {
    local detected="$1"
    local value

    while :; do
        echo
        echo "This is the public IPv4 address of the Debian server."
        echo
        echo "It will later be used as:"
        echo "  • the local strongSwan endpoint"
        echo "  • the UniFi remote gateway"
        echo "  • the Debian IKE authentication identity"
        echo
        echo "Press ENTER to accept the suggested value or enter another value."
        echo

        read -r -p "Debian public IP [${detected}]: " value
        value="${value:-${detected}}"

        if valid_ipv4 "${value}"; then
            PROMPT_RESULT="${value}"
            return
        fi

        error "Invalid IPv4 address: ${value}"
    done
}

prompt_tunnel_name() {
    local suggested="$1"
    local value

    while :; do
        echo
        echo "The tunnel name is used by the S2S Manager to identify this tunnel."
        echo
        echo "Examples:"
        echo "  home"
        echo "  office"
        echo "  backup"
        echo
        echo "Allowed characters:"
        echo "  letters, numbers, underscore and dash"
        echo
        echo "Press ENTER to accept the suggested value or enter another value."
        echo

        read -r -p "Tunnel name [${suggested}]: " value
        value="${value:-${suggested}}"

        if ! valid_tunnel_name "${value}"; then
            error "Invalid tunnel name."
            continue
        fi

        if tunnel_exists "${value}"; then
            error "A tunnel named '${value}' already exists."
            continue
        fi

        PROMPT_RESULT="${value}"
        return
    done
}

prompt_auth_id() {
    local suggested="$1"
    local ignore_name="${2:-}"
    local value

    while :; do
        echo
        echo "The UniFi gateway identifies itself to Debian using this IKE identity."
        echo
        echo "This is NOT an IP address and does not need to resolve in DNS."
        echo
        echo "Use a unique Authentication ID for every S2S tunnel."
        echo
        echo "Examples:"
        echo "  unifi-home"
        echo "  unifi-office"
        echo "  unifi-backup"
        echo
        echo "Press ENTER to accept the suggested value or enter another value."
        echo

        read -r -p "UniFi authentication ID [${suggested}]: " value
        value="${value:-${suggested}}"

        if ! valid_auth_id "${value}"; then
            error "Invalid authentication ID."
            continue
        fi

        if auth_id_in_use "${value}" "${ignore_name}"; then
            error "Authentication ID '${value}' is already used by another tunnel."
            continue
        fi

        PROMPT_RESULT="${value}"
        return
    done
}

prompt_tunnel_network() {
    local suggested="$1"
    local ignore_name="${2:-}"
    local value normalized
    local rc

    while :; do
        echo
        echo "Every Site-to-Site tunnel needs its own private transfer network."
        echo
        echo "This manager always uses a /30 network."
        echo
        echo "A /30 provides exactly two usable IP addresses:"
        echo "  • one for Debian"
        echo "  • one for the UniFi gateway"
        echo
        echo "You may enter either:"
        echo "  10.200.201.0"
        echo "or"
        echo "  10.200.201.0/30"
        echo
        echo "Both formats are accepted."
        echo
        echo "The network must NOT overlap with any existing:"
        echo "  • LAN"
        echo "  • VLAN"
        echo "  • VPN"
        echo "  • Teleport network"
        echo "  • Site-to-Site tunnel"

        local count
        count=$(tunnel_count)

        if (( count > 0 )); then
            echo
            echo "Existing S2S networks:"

            local name

            while read -r name; do
                [[ -z "${name}" ]] && continue
                load_tunnel "${name}" || continue

                [[ "${name}" == "${ignore_name}" ]] && continue

                printf '  • %s  (%s)\n' "${VTI_NETWORK}" "${NAME}"
            done < <(list_tunnel_names)
        fi

        echo
        echo "Press ENTER to accept the suggested value or enter another network."
        echo

        read -r -p "Tunnel network [${suggested%%/*}]: " value
        value="${value:-${suggested}}"

        set +e
        normalized=$(normalize_30_network "${value}")
        rc=$?
        set -e 2>/dev/null || true

        if (( rc == 1 )); then
            error "Invalid IPv4 network."
            continue
        fi

        if (( rc == 2 )); then
            local entered_ip="${value%%/*}"

            warn "This manager uses /30 networks for S2S tunnel addressing."
            echo
            echo "You entered:"
            echo "  ${value}"
            echo
            echo "Use:"
            echo "  ${entered_ip}/30"
            echo
            echo "  [1] Use ${entered_ip}/30"
            echo "  [2] Enter another network"
            echo "  [0] Cancel"
            echo

            read -r -p "Selection: " choice

            case "${choice}" in
                1)
                    value="${entered_ip}/30"

                    if ! normalized=$(normalize_30_network "${value}"); then
                        error "Invalid network."
                        continue
                    fi
                    ;;
                0)
                    return 1
                    ;;
                *)
                    continue
                    ;;
            esac
        fi

        if ! network_is_exact_base "${value}"; then
            local original_ip="${value%%/*}"

            calculate_30_addresses "${normalized}"

            warn "${original_ip} is not the network address of a /30 subnet."
            echo
            echo "The matching /30 network is:"
            echo "  ${CALC_NETWORK}"
            echo
            echo "Addresses:"
            echo "  Debian:    ${CALC_DEBIAN}"
            echo "  UniFi:     ${CALC_UNIFI}"
            echo "  Broadcast: ${CALC_BROADCAST}"
            echo
            read -r -p "Use this network? [y/N]: " use_it

            if [[ ! "${use_it}" =~ ^[Yy]$ ]]; then
                continue
            fi
        fi

        if network_in_use "${normalized}" "${ignore_name}"; then
            error "Network ${normalized} is already used by another S2S tunnel."
            continue
        fi

        calculate_30_addresses "${normalized}"

        echo
        ok "Valid /30 network"
        echo
        printf '%-14s %s\n' "Network:" "${CALC_NETWORK}"
        printf '%-14s %s\n' "Debian IP:" "${CALC_DEBIAN}"
        printf '%-14s %s\n' "UniFi IP:" "${CALC_UNIFI}"
        printf '%-14s %s\n' "Broadcast:" "${CALC_BROADCAST}"
        echo

        read -r -p "Use these addresses? [Y/n]: " confirm

        if [[ "${confirm}" =~ ^[Nn]$ ]]; then
            continue
        fi

        PROMPT_NETWORK="${CALC_NETWORK}"
        PROMPT_DEBIAN_IP="${CALC_DEBIAN}"
        PROMPT_UNIFI_IP="${CALC_UNIFI}"
        return
    done
}

prompt_remote_networks() {
    PROMPT_ROUTES=()

    echo
    echo "Enter the UniFi networks that Debian must be able to reach through"
    echo "the Site-to-Site tunnel."
    echo
    echo "These will later be used as return routes."
    echo
    echo "Examples:"
    echo "  192.168.178.0/23    Main LAN"
    echo "  192.168.4.0/24      UniFi Teleport"
    echo
    echo "Enter one network per line."
    echo "Press ENTER on an empty line when finished."
    echo

    local index=1

    while :; do
        local route
        read -r -p "Remote network #${index}: " route

        if [[ -z "${route}" ]]; then
            break
        fi

        if ! valid_cidr "${route}"; then
            error "Invalid CIDR network: ${route}"
            continue
        fi

        local duplicate=0
        local existing

        for existing in "${PROMPT_ROUTES[@]:-}"; do
            if [[ "${existing}" == "${route}" ]]; then
                duplicate=1
                break
            fi
        done

        if (( duplicate == 1 )); then
            warn "Network already added."
            continue
        fi

        PROMPT_ROUTES+=("${route}")
        ((index += 1))
    done
}

prompt_psk() {
    local generated

    echo
    echo "The Pre-Shared Key must later be entered in UniFi."
    echo
    echo "Choose:"
    echo
    echo "  [1] Generate a secure random PSK"
    echo "  [2] Enter my own PSK"
    echo

    while :; do
        read -r -p "Selection [1]: " choice
        choice="${choice:-1}"

        case "${choice}" in
            1)
                if generated=$(generate_psk); then
                    PROMPT_PSK="${generated}"
                    ok "Secure random PSK generated."
                    return
                fi

                error "OpenSSL is not available. Please enter the PSK manually."
                ;;
            2)
                echo
                read -r -s -p "Pre-Shared Key: " PROMPT_PSK
                echo

                if [[ -z "${PROMPT_PSK}" ]]; then
                    error "PSK must not be empty."
                    continue
                fi

                return
                ;;
            *)
                error "Invalid selection."
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Add tunnel
# ------------------------------------------------------------------------------

add_tunnel() {
    banner
    section "ADD SITE-TO-SITE TUNNEL"

    local detected_ip
    detected_ip=$(detect_public_ipv4)

    if [[ -n "${detected_ip}" ]]; then
        ok "Detected Debian IPv4 address: ${detected_ip}"
    else
        warn "Could not automatically detect the Debian IPv4 address."
        detected_ip="0.0.0.0"
    fi

    local tunnel_number
    tunnel_number=$(( $(tunnel_count) + 1 ))

    local suggested_name="home"

    if (( tunnel_number > 1 )); then
        suggested_name="s2s-${tunnel_number}"
    fi

    section "STEP 1/6  Tunnel Name"
    prompt_tunnel_name "${suggested_name}"
    local name="${PROMPT_RESULT}"

    section "STEP 2/6  Debian Public IP"
    prompt_public_ip "${detected_ip}"
    local public_ip="${PROMPT_RESULT}"

    section "STEP 3/6  Site-to-Site Tunnel Network"

    local suggested_network
    suggested_network=$(next_vti_network)

    prompt_tunnel_network "${suggested_network}" || return
    local vti_network="${PROMPT_NETWORK}"
    local debian_vti_ip="${PROMPT_DEBIAN_IP}"
    local unifi_vti_ip="${PROMPT_UNIFI_IP}"

    section "STEP 4/6  UniFi Authentication ID"

    local suggested_auth="unifi-${name}"
    prompt_auth_id "${suggested_auth}"
    local auth_id="${PROMPT_RESULT}"

    section "STEP 5/6  Remote Networks"

    prompt_remote_networks
    local -a remote_networks=("${PROMPT_ROUTES[@]:-}")

    section "STEP 6/6  Pre-Shared Key"

    prompt_psk
    local psk="${PROMPT_PSK}"

    local interface_index
    interface_index=$(next_interface_index)

    local interface="ipsec${interface_index}"
    local key=$((42 + interface_index))

    section "CONFIGURATION SUMMARY"

    printf '%-28s %s\n' "Tunnel name:" "${name}"
    printf '%-28s %s\n' "Debian public IP:" "${public_ip}"
    printf '%-28s %s\n' "Authentication ID:" "${auth_id}"
    printf '%-28s %s\n' "VTI interface:" "${interface}"
    printf '%-28s %s\n' "VTI key / mark:" "${key}"
    printf '%-28s %s\n' "Tunnel network:" "${vti_network}"
    printf '%-28s %s\n' "Debian VTI IP:" "${debian_vti_ip}"
    printf '%-28s %s\n' "UniFi VTI IP:" "${unifi_vti_ip}"

    echo
    echo "Remote networks:"

    if (( ${#remote_networks[@]} == 0 )); then
        echo "  None"
    else
        local route
        for route in "${remote_networks[@]}"; do
            printf '  • %s\n' "${route}"
        done
    fi

    echo
    echo "No system configuration will be changed."
    echo "Only test state files will be written."
    echo
    printf 'State directory: %s\n' "${STATE_DIR}"
    echo

    while :; do
        echo "  [y] Save this configuration"
        echo "  [n] Cancel"
        echo

        read -r -p "Save configuration? [y/N]: " confirm

        case "${confirm}" in
            y|Y)
                save_tunnel \
                    "${name}" \
                    "${public_ip}" \
                    "${auth_id}" \
                    "${interface}" \
                    "${key}" \
                    "${vti_network}" \
                    "${debian_vti_ip}" \
                    "${unifi_vti_ip}"

                write_routes "${name}" "${remote_networks[@]:-}"
                save_psk "${name}" "${psk}"

                echo
                ok "Configuration saved."
                echo
                echo "Files:"
                echo "  $(tunnel_config_file "${name}")"
                echo "  $(tunnel_route_file "${name}")"
                echo "  $(tunnel_secret_file "${name}")"
                pause
                return
                ;;
            n|N|"")
                warn "Configuration was not saved."
                pause
                return
                ;;
            *)
                error "Invalid selection."
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------------------

add_remote_network() {
    banner
    section "ADD REMOTE NETWORK"

    select_tunnel || {
        pause
        return
    }

    local name="${SELECTED_TUNNEL}"

    echo
    echo "Current routes:"

    local existing_count=0
    local route

    while read -r route; do
        [[ -z "${route}" ]] && continue
        printf '  • %s\n' "${route}"
        ((existing_count += 1))
    done < <(read_routes "${name}")

    if (( existing_count == 0 )); then
        echo "  None"
    fi

    echo

    while :; do
        read -r -p "New remote network (CIDR): " new_route

        if ! valid_cidr "${new_route}"; then
            error "Invalid CIDR network."
            continue
        fi

        if read_routes "${name}" | grep -Fxq "${new_route}"; then
            warn "This route already exists."
            pause
            return
        fi

        echo
        echo "Changes to apply:"
        printf '  + %s\n' "${new_route}"
        echo
        echo "TEST MODE: only the state file will be updated."
        echo

        read -r -p "Apply change? [y/N]: " confirm

        if [[ "${confirm}" =~ ^[Yy]$ ]]; then
            printf '%s\n' "${new_route}" >> "$(tunnel_route_file "${name}")"
            ok "Remote network added."
        else
            warn "No changes made."
        fi

        pause
        return
    done
}

remove_remote_network() {
    banner
    section "REMOVE REMOTE NETWORK"

    select_tunnel || {
        pause
        return
    }

    local name="${SELECTED_TUNNEL}"
    local -a routes=()
    local route

    while read -r route; do
        [[ -n "${route}" ]] && routes+=("${route}")
    done < <(read_routes "${name}")

    if (( ${#routes[@]} == 0 )); then
        warn "This tunnel has no remote networks."
        pause
        return
    fi

    echo

    local i
    for i in "${!routes[@]}"; do
        printf '  [%d] %s\n' "$((i + 1))" "${routes[$i]}"
    done

    echo
    read -r -p "Select network to remove: " selection

    if [[ ! "${selection}" =~ ^[0-9]+$ ]] \
        || (( selection < 1 || selection > ${#routes[@]} )); then
        error "Invalid selection."
        pause
        return
    fi

    local remove="${routes[$((selection - 1))]}"

    echo
    echo "Changes to apply:"
    printf '  - %s\n' "${remove}"
    echo
    echo "TEST MODE: only the state file will be updated."
    echo

    read -r -p "Apply change? [y/N]: " confirm

    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        warn "No changes made."
        pause
        return
    fi

    local file
    file=$(tunnel_route_file "${name}")

    grep -Fxv "${remove}" "${file}" > "${file}.tmp" || true
    mv "${file}.tmp" "${file}"
    chmod 600 "${file}"

    ok "Remote network removed."
    pause
}

# ------------------------------------------------------------------------------
# Edit tunnel
# ------------------------------------------------------------------------------

edit_tunnel() {
    banner
    section "EDIT TUNNEL"

    select_tunnel || {
        pause
        return
    }

    local tunnel="${SELECTED_TUNNEL}"

    while :; do
        load_tunnel "${tunnel}"

        banner
        show_tunnel_details "${tunnel}"

        section "EDIT OPTIONS"

        echo "  [1] Debian public IP"
        echo "  [2] UniFi authentication ID"
        echo "  [3] Tunnel network"
        echo "  [4] Add remote network"
        echo "  [5] Remove remote network"
        echo "  [6] Generate new PSK"
        echo "  [0] Back"
        echo

        read -r -p "Selection: " choice

        case "${choice}" in
            1)
                section "EDIT DEBIAN PUBLIC IP"
                prompt_public_ip "${PUBLIC_IP}"

                local new_ip="${PROMPT_RESULT}"

                echo
                echo "Changes to apply:"
                printf '  %s -> %s\n' "${PUBLIC_IP}" "${new_ip}"
                echo

                read -r -p "Apply change? [y/N]: " confirm

                if [[ "${confirm}" =~ ^[Yy]$ ]]; then
                    save_tunnel \
                        "${NAME}" \
                        "${new_ip}" \
                        "${AUTH_ID}" \
                        "${VTI_INTERFACE}" \
                        "${VTI_KEY}" \
                        "${VTI_NETWORK}" \
                        "${DEBIAN_VTI_IP}" \
                        "${UNIFI_VTI_IP}"

                    ok "Public IP updated."
                    pause
                fi
                ;;
            2)
                section "EDIT AUTHENTICATION ID"
                prompt_auth_id "${AUTH_ID}" "${NAME}"

                local new_auth="${PROMPT_RESULT}"

                echo
                echo "Changes to apply:"
                printf '  %s -> %s\n' "${AUTH_ID}" "${new_auth}"
                echo

                read -r -p "Apply change? [y/N]: " confirm

                if [[ "${confirm}" =~ ^[Yy]$ ]]; then
                    save_tunnel \
                        "${NAME}" \
                        "${PUBLIC_IP}" \
                        "${new_auth}" \
                        "${VTI_INTERFACE}" \
                        "${VTI_KEY}" \
                        "${VTI_NETWORK}" \
                        "${DEBIAN_VTI_IP}" \
                        "${UNIFI_VTI_IP}"

                    ok "Authentication ID updated."
                    pause
                fi
                ;;
            3)
                section "EDIT TUNNEL NETWORK"

                prompt_tunnel_network "${VTI_NETWORK}" "${NAME}" || continue

                local new_net="${PROMPT_NETWORK}"
                local new_debian="${PROMPT_DEBIAN_IP}"
                local new_unifi="${PROMPT_UNIFI_IP}"

                echo
                echo "Changes to apply:"
                printf '  Network: %s -> %s\n' "${VTI_NETWORK}" "${new_net}"
                printf '  Debian:  %s -> %s\n' "${DEBIAN_VTI_IP}" "${new_debian}"
                printf '  UniFi:   %s -> %s\n' "${UNIFI_VTI_IP}" "${new_unifi}"
                echo

                read -r -p "Apply change? [y/N]: " confirm

                if [[ "${confirm}" =~ ^[Yy]$ ]]; then
                    save_tunnel \
                        "${NAME}" \
                        "${PUBLIC_IP}" \
                        "${AUTH_ID}" \
                        "${VTI_INTERFACE}" \
                        "${VTI_KEY}" \
                        "${new_net}" \
                        "${new_debian}" \
                        "${new_unifi}"

                    ok "Tunnel network updated."
                    pause
                fi
                ;;
            4)
                add_remote_network
                ;;
            5)
                remove_remote_network
                ;;
            6)
                section "GENERATE NEW PSK"

                local new_psk

                if ! new_psk=$(generate_psk); then
                    error "OpenSSL is not available."
                    pause
                    continue
                fi

                warn "This will replace the stored PSK for tunnel '${NAME}'."
                echo
                read -r -p "Generate and save a new PSK? [y/N]: " confirm

                if [[ "${confirm}" =~ ^[Yy]$ ]]; then
                    save_psk "${NAME}" "${new_psk}"
                    ok "New PSK generated and stored."
                else
                    warn "No changes made."
                fi

                pause
                ;;
            0)
                return
                ;;
            *)
                error "Invalid selection."
                pause
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Delete tunnel
# ------------------------------------------------------------------------------

delete_tunnel() {
    banner
    section "DELETE TUNNEL"

    select_tunnel || {
        pause
        return
    }

    local name="${SELECTED_TUNNEL}"

    show_tunnel_details "${name}"

    echo
    printf '%b\n' "${C_RED}${C_BOLD}This deletes only TEST STATE FILES.${C_RESET}"
    echo
    echo "No networking or system configuration will be changed."
    echo
    echo "Files to delete:"
    echo "  $(tunnel_config_file "${name}")"
    echo "  $(tunnel_route_file "${name}")"
    echo "  $(tunnel_secret_file "${name}")"
    echo

    read -r -p "Delete tunnel '${name}'? Type DELETE to confirm: " confirm

    if [[ "${confirm}" != "DELETE" ]]; then
        warn "Tunnel was not deleted."
        pause
        return
    fi

    rm -f \
        "$(tunnel_config_file "${name}")" \
        "$(tunnel_route_file "${name}")" \
        "$(tunnel_secret_file "${name}")"

    ok "Tunnel '${name}' deleted from test state."
    pause
}

# ------------------------------------------------------------------------------
# Show configuration
# ------------------------------------------------------------------------------

show_configuration_menu() {
    banner
    section "SHOW CONFIGURATION"

    select_tunnel || {
        pause
        return
    }

    show_tunnel_details "${SELECTED_TUNNEL}"

    echo
    echo "Stored test files:"
    echo "  $(tunnel_config_file "${SELECTED_TUNNEL}")"
    echo "  $(tunnel_route_file "${SELECTED_TUNNEL}")"
    echo "  $(tunnel_secret_file "${SELECTED_TUNNEL}")"

    pause
}

# ------------------------------------------------------------------------------
# Main menu
# ------------------------------------------------------------------------------

main_menu() {
    while :; do
        banner

        section "CONFIGURED TUNNELS"
        show_existing_tunnels

        section "MENU"

        echo "  [1] Show tunnel configuration"
        echo "  [2] Edit tunnel"
        echo "  [3] Add remote network"
        echo "  [4] Remove remote network"
        echo "  [5] Add another S2S tunnel"
        echo "  [6] Delete tunnel"
        echo "  [7] Show test state directory"
        echo "  [0] Exit"
        echo

        read -r -p "Selection: " choice

        case "${choice}" in
            1)
                show_configuration_menu
                ;;
            2)
                edit_tunnel
                ;;
            3)
                add_remote_network
                ;;
            4)
                remove_remote_network
                ;;
            5)
                add_tunnel
                ;;
            6)
                delete_tunnel
                ;;
            7)
                banner
                section "TEST STATE DIRECTORY"

                echo "${STATE_DIR}"
                echo
                find "${STATE_DIR}" -maxdepth 3 -type f -printf '%p\n' | sort

                pause
                ;;
            0)
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

# ------------------------------------------------------------------------------
# Start
# ------------------------------------------------------------------------------

ensure_root
init_state_dirs

if (( $(tunnel_count) == 0 )); then
    banner

    ok "Running as root"

    detected_ip=$(detect_public_ipv4)

    if [[ -n "${detected_ip}" ]]; then
        ok "Detected Debian IPv4 address: ${detected_ip}"
    else
        warn "Could not detect Debian IPv4 address."
    fi

    echo
    info "No existing S2S test configuration found."
    echo
    echo "The setup wizard will now create the first TEST configuration."
    echo
    read -r -p "Press ENTER to start..." _

    add_tunnel
fi

main_menu
