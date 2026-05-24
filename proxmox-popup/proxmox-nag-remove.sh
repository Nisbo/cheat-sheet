#!/usr/bin/env bash

set -e

FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

ORIGINAL="data.status.toLowerCase() !== 'active'"
PATCHED="42 === 0"

echo
echo "== Proxmox No-Subscription Popup Patch =="
echo

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Please run this script as root."
    exit 1
fi

# File check
if [[ ! -f "$FILE" ]]; then
    echo "[ERROR] File not found:"
    echo "        $FILE"
    exit 1
fi

echo "[INFO] Checking file..."

MATCHES=$(grep -nF "$ORIGINAL" "$FILE" || true)
PATCHED_MATCHES=$(grep -nF "$PATCHED" "$FILE" || true)

# Already patched
if [[ -z "$MATCHES" && -n "$PATCHED_MATCHES" ]]; then
    echo
    echo "[INFO] Already patched."
    echo
    echo "$PATCHED_MATCHES"
    echo

    read -rp "Revert patch? [y/N]: " REVERT_CONFIRM

    if [[ "$REVERT_CONFIRM" =~ ^[Yy]$ ]]; then
        echo
        echo "[INFO] Reverting patch..."

        read -rp "Create backup before reverting? [Y/n]: " BACKUP_CONFIRM

        if [[ ! "$BACKUP_CONFIRM" =~ ^[Nn]$ ]]; then
            BACKUP_FILE="${FILE}.revertbak.$(date +%Y%m%d-%H%M%S)"
            cp "$FILE" "$BACKUP_FILE"

            echo "[OK] Backup created:"
            echo "     $BACKUP_FILE"
        fi

        sed -i "s|$PATCHED|$ORIGINAL|g" "$FILE"

        VERIFY=$(grep -nF "$ORIGINAL" "$FILE" || true)

        if [[ -n "$VERIFY" ]]; then
            echo "[SUCCESS] Revert successful."
        else
            echo "[ERROR] Revert failed."
            exit 1
        fi

        echo
        echo "[INFO] Clearing cache..."
        rm -rf /var/cache/pve-manager/*

        read -rp "Restart pveproxy now? [Y/n]: " RESTART_CONFIRM

        if [[ ! "$RESTART_CONFIRM" =~ ^[Nn]$ ]]; then
            systemctl restart pveproxy
            echo "[OK] pveproxy restarted."
        else
            echo "[INFO] Restart skipped."
        fi

        exit 0
    fi

    echo "[INFO] Nothing done."
    exit 0
fi

# No match found
if [[ -z "$MATCHES" ]]; then
    echo
    echo "[INFO] No matching pattern found."
    exit 0
fi

# Found original
echo
echo "[FOUND] Matches:"
echo
echo "$MATCHES"
echo

read -rp "Apply patch? [y/N]: " APPLY_CONFIRM

if [[ ! "$APPLY_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "[ABORT] Cancelled."
    exit 0
fi

echo

read -rp "Create backup? [Y/n]: " BACKUP_CONFIRM

if [[ ! "$BACKUP_CONFIRM" =~ ^[Nn]$ ]]; then
    BACKUP_FILE="${FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$FILE" "$BACKUP_FILE"

    echo "[OK] Backup created:"
    echo "     $BACKUP_FILE"
fi

echo
echo "[INFO] Applying patch..."

sed -i "s|$ORIGINAL|$PATCHED|g" "$FILE"

echo
echo "[INFO] Verifying..."

VERIFY=$(grep -nF "$PATCHED" "$FILE" || true)

if [[ -n "$VERIFY" ]]; then
    echo "[SUCCESS] Patch applied."
else
    echo "[ERROR] Patch failed."
    exit 1
fi

echo
echo "[INFO] Clearing cache..."
rm -rf /var/cache/pve-manager/*

read -rp "Restart pveproxy now? [Y/n]: " RESTART_CONFIRM

if [[ ! "$RESTART_CONFIRM" =~ ^[Nn]$ ]]; then
    systemctl restart pveproxy
    echo "[OK] pveproxy restarted."
else
    echo "[INFO] Restart skipped."
fi

echo
echo "Done."
