#!/bin/bash
# =============================================================================
# БЛОК 14: Создание helper-скриптов администратора
# =============================================================================

set -euo pipefail

create_rear_check_before_backup() {
    local target="/usr/local/sbin/rear-check-before-backup.sh"

    if [[ -f "$target" ]]; then
        echo "[OK] Скрипт проверки уже существует: $target"
        return 0
    fi

    echo "[INFO] Создание скрипта проверки перед бэкапом: $target"

    install -m 0755 /dev/stdin "$target" <<'EOF2'
#!/bin/bash
set -euo pipefail

echo "[INFO] Проверка готовности системы к ReaR backup..."

command -v rear >/dev/null 2>&1 || {
    echo "[ERROR] ReaR не найден"
    exit 1
}

mountpoint -q /mnt/rear-usb || {
    echo "[ERROR] USB не смонтирован в /mnt/rear-usb"
    exit 1
}

echo "[OK] Система готова к выполнению rear mkbackup"
EOF2
}

run_block14() {
    echo "=== СОЗДАНИЕ HELPER-СКРИПТОВ ==="
    create_rear_check_before_backup
    echo "[OK] Helper-скрипты готовы"
}
