#!/usr/bin/env bash

set -e

FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
SEARCH="data.status.toLowerCase() !== 'active'"
REPLACE="false"

echo
echo "== Proxmox No-Subscription Popup Patch =="
echo

# Root prüfen
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Bitte als root ausführen."
    exit 1
fi

# Datei prüfen
if [[ ! -f "$FILE" ]]; then
    echo "[ERROR] Datei nicht gefunden:"
    echo "        $FILE"
    exit 1
fi

echo "[INFO] Prüfe auf bekannte Signatur..."

MATCHES=$(grep -nF "$SEARCH" "$FILE" || true)

if [[ -z "$MATCHES" ]]; then
    echo
    echo "[INFO] Keine passende Stelle gefunden."
    echo "        Möglicherweise bereits gepatcht oder andere Proxmox-Version."
    exit 0
fi

echo
echo "[FOUND] Folgende Stelle(n) wurden gefunden:"
echo
echo "$MATCHES"
echo

read -rp "Möchtest du den Patch anwenden? [y/N]: " PATCH_CONFIRM

if [[ ! "$PATCH_CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "[ABORT] Abgebrochen."
    exit 0
fi

echo

read -rp "Backup der Originaldatei erstellen? [Y/n]: " BACKUP_CONFIRM

if [[ ! "$BACKUP_CONFIRM" =~ ^[Nn]$ ]]; then
    BACKUP_FILE="${FILE}.bak.$(date +%Y%m%d-%H%M%S)"

    cp "$FILE" "$BACKUP_FILE"

    echo "[OK] Backup erstellt:"
    echo "     $BACKUP_FILE"
    echo
fi

echo "[INFO] Wende Patch an..."

sed -i "s/${SEARCH//\//\\/}/${REPLACE}/g" "$FILE"

echo
echo "[INFO] Prüfe Patch-Ergebnis..."

VERIFY=$(grep -nF "$SEARCH" "$FILE" || true)

if [[ -z "$VERIFY" ]]; then
    echo "[SUCCESS] Patch erfolgreich angewendet."
else
    echo "[ERROR] Patch scheint fehlgeschlagen zu sein."
    echo
    echo "$VERIFY"
    exit 1
fi

echo
echo "[INFO] Cache wird bereinigt..."

rm -rf /var/cache/pve-manager/*

echo
read -rp "pveproxy jetzt neu starten? [Y/n]: " RESTART_CONFIRM

if [[ ! "$RESTART_CONFIRM" =~ ^[Nn]$ ]]; then
    systemctl restart pveproxy
    echo
    echo "[OK] pveproxy wurde neu gestartet."
else
    echo
    echo "[INFO] Kein Neustart durchgeführt."
    echo "       Bitte später manuell ausführen:"
    echo "       systemctl restart pveproxy"
fi

echo
echo "Fertig."
