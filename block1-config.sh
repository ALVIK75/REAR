#!/bin/bash
#
# ALT Linux 11 - Полная подготовка системы и флешки для ReaR
# БЛОК 1: Основные функции и конфигурация
#

set -euo pipefail

### === GLOBAL CONFIG ===
MOUNTPOINT="/mnt/rear-usb"
LABEL="REAR_BACKUP"
BACKUP_DIR="${MOUNTPOINT}/backups"
REAR_CONF="/etc/rear/local.conf"
MIN_FREE_SPACE_GB=50
AUTOMOUNT_SCRIPT="/usr/local/bin/rear-automount.sh"

EXISTING_BACKUP=""
EXISTING_ISO=""
EXISTING_OTHER_BACKUPS=()
SKIP_USB_PREP=0
REAR_MISSING=0
AUTO_DISKNAME=""

echo "================================================="
echo "    Полная подготовка ALT Linux 11 для ReaR"
echo "================================================="

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Запустите скрипт с правами root: sudo $0"
    exit 1
fi

normalize_size() { echo "$1" | sed 's/,/./g'; }

get_size_gb() {
    local size_str=$1
    local normalized
    normalized=$(normalize_size "$size_str")
    echo "$normalized" | awk -F'[.G]' '{print int($1)}'
}

run_block1() {
    echo "[INFO] Запуск блока 1..."
    echo "[SUCCESS] Блок 1 завершен: базовая конфигурация"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block1
fi