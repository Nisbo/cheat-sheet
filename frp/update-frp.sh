#!/bin/bash

set -e

FRP_DIR="/opt/frp"
TMP_DIR="/tmp"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Please run this script as root."
    exit 1
fi

echo
echo "================================="
echo "      FRP Update Utility"
echo "================================="
echo

echo "Select component:"
echo "  1) frps (Server)"
echo "  2) frpc (Client)"
echo

read -rp "Selection [1-2]: " MODE

case "$MODE" in
    1)
        BINARY="frps"
        SERVICE="frps.service"
        ;;
    2)
        BINARY="frpc"
        SERVICE="frpc.service"
        ;;
    *)
        echo "ERROR: Invalid selection."
        exit 1
        ;;
esac

echo
echo "Checking installed version..."

if [[ -f "$FRP_DIR/$BINARY" ]]; then
    INSTALLED_VERSION=$("$FRP_DIR/$BINARY" --version 2>/dev/null || echo "unknown")
else
    INSTALLED_VERSION="unknown"
fi

echo "Installed version : $INSTALLED_VERSION"

echo
echo "Checking latest release..."

LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/fatedier/frp/releases/latest \
    | sed -n 's/.*"tag_name":[[:space:]]*"v\?\([^"]*\)".*/\1/p' \
    | head -n1)

if [[ -z "$LATEST_VERSION" ]]; then
    echo "ERROR: Could not fetch latest version."
    exit 1
fi

echo "Latest version    : $LATEST_VERSION"
echo

read -rp "Press ENTER to install latest or type version [$LATEST_VERSION]: " VERSION
VERSION=${VERSION:-$LATEST_VERSION}

echo
echo "Selected version  : $VERSION"
echo

ARCH="linux_amd64"
FILE="frp_${VERSION}_${ARCH}.tar.gz"
EXTRACT_DIR="frp_${VERSION}_${ARCH}"
URL="https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILE}"

echo "Component         : $BINARY"
echo "Service           : $SERVICE"
echo "Download URL      : $URL"
echo

read -rp "Continue update? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

BACKUP_DIR="${FRP_DIR}_backup_$(date +%F_%H-%M-%S)"

echo
echo "Creating backup..."
cp -a "$FRP_DIR" "$BACKUP_DIR"

cd "$TMP_DIR"

rm -rf "$EXTRACT_DIR" "$FILE"

echo "Downloading..."
wget --show-progress "$URL"

echo "Extracting..."
tar -xzf "$FILE"

echo "Stopping service..."
systemctl stop "$SERVICE"

echo "Installing..."
cp "$EXTRACT_DIR/$BINARY" "$FRP_DIR/"
chmod +x "$FRP_DIR/$BINARY"

echo "Starting service..."
systemctl start "$SERVICE"

sleep 2

echo
echo "Checking service..."

if systemctl is-active --quiet "$SERVICE"; then
    echo "SUCCESS: Service is running."
else
    echo "ERROR: Service failed!"
    journalctl -u "$SERVICE" -n 30 --no-pager
    exit 1
fi

echo
echo "Done."
echo "Backup: $BACKUP_DIR"
echo
