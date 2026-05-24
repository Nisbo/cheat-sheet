#!/usr/bin/env bash

set -e

FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

ORIGINAL="data.status.toLowerCase() !== 'active'"
PATCHED="false /* patched-by-script */"

echo
echo "== Proxmox No-Subscription Popup Patch =="
echo

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Please run this script as root."
    exit 1
fi

# Check if file exists
if [[ ! -f "$FILE" ]]; then
    echo "[ERROR] File not found:"
    echo "        $FILE"
    exit 1
fi

echo "[INFO] Checking Proxmox library..."

# Search for original pattern
MATCHES=$(grep -nF "$ORIGINAL" "$FILE" || true)

# Search for patched pattern
PATCHED_MATCHES=$(grep -nF "patched-by-script" "$FILE" || true)

#
# Already patched
#
if [[ -z "$MATCHES" && -n "$PATCHED_MATCHES" ]]; then

    echo
    echo "[INFO] The file already appears to be patched."
    echo
    echo "$PATCHED_MATCHES"
    echo

    read -rp "Would you like to revert the patch? [y/N]: " REVERT_CONFIRM

    if [[ "$REVERT_CONFIRM" =~ ^[Yy]$ ]]; then

        echo
        echo "[INFO] Reverting patch..."

        sed -i "s|$PATCHED|$ORIGINAL|g" "$FILE"

        VERIFY_RESTORE=$(grep -nF "$ORIGINAL" "$FILE" || true)

        if [[ -n "$VERIFY_RESTORE" ]]; then
            echo "[SUCCESS] Patch reverted successfully."
        else
            echo "[ERROR] Failed to restore original content."
            exit 1
        fi

        echo
        read -rp "Restart pveproxy now? [Y/n]: " RESTART_CONFIRM

        if [[ ! "$RESTART_CONFIRM" =~ ^[Nn]$ ]]; then
            systemctl restart pveproxy

            echo
            echo "[OK] pveproxy restarted."
        else
            echo
            echo "[INFO] Restart skipped."
            echo "       Please restart manually later:"
            echo "       systemctl restart pveproxy"
        fi

        echo
        echo "Done."
        exit 0
    fi

    echo
    echo "Nothing to do."
    exit 0
fi

#
# No valid signature found
#
if [[ -z "$MATCHES" ]]; then
    echo
    echo "[INFO] No matching signature found."
    echo "       Your Proxmox version may use a different pattern."
    exit 0
fi

#
# Found original pattern
#
echo
echo "[FOUND] Matching signature(s):"
echo
echo "$MATCHES"
echo

read -rp "Would you like to apply the patch? [y/N]: " PATCH_CONFIRM

if [[ ! "$PATCH_CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "[ABORT] Operation cancelled."
    exit 0
fi

echo

read -rp "Create a backup of the original file? [Y/n]: " BACKUP_CONFIRM

if [[ ! "$BACKUP_CONFIRM" =~ ^[Nn]$ ]]; then

    BACKUP_FILE="${FILE}.bak.$(date +%Y%m%d-%H%M%S)"

    cp "$FILE" "$BACKUP_FILE"

    echo
    echo "[OK] Backup created:"
    echo "     $BACKUP_FILE"
fi

echo
echo "[INFO] Applying patch..."

sed -i "s|$ORIGINAL|$PATCHED|g" "$FILE"

echo
echo "[INFO] Verifying patch..."

VERIFY=$(grep -nF "patched-by-script" "$FILE" || true)

if [[ -n "$VERIFY" ]]; then
    echo "[SUCCESS] Patch applied successfully."
    echo
    echo "$VERIFY"
else
    echo "[ERROR] Patch verification failed."
    exit 1
fi

echo
echo "[INFO] Clearing Proxmox cache..."

rm -rf /var/cache/pve-manager/*

echo
read -rp "Restart pveproxy now? [Y/n]: " RESTART_CONFIRM

if [[ ! "$RESTART_CONFIRM" =~ ^[Nn]$ ]]; then

    systemctl restart pveproxy

    echo
    echo "[OK] pveproxy restarted successfully."
else
    echo
    echo "[INFO] Restart skipped."
    echo "       Please restart manually later:"
    echo "       systemctl restart pveproxy"
fi

echo
echo "Done."
