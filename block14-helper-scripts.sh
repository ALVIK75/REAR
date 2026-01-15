#!/bin/bash
# =============================================================================
# БЛОК 14: Создание helper-скриптов администратора
# =============================================================================

set -euo pipefail

create_rear_check_before_backup() {
    local target="/usr/local/sbin/rear-check-before-backup.sh"

    # Гарантируем существование каталога
    mkdir -p /usr/local/sbin

    # Идемпотентность
    if [[ -f "$target" ]]; then
        echo "[OK] Скрипт проверки уже существует: $target"
        return 0
    fi

    echo "[INFO] Создание скрипта проверки перед бэкапом: $target"

    install -m 0755 /dev/stdin "$target" <<'EOF'
#!/bin/bash
# -----------------------------------------------------------------------------
# ReaR pre-backup sanity check
# -----------------------------------------------------------------------------

set -euo pipefail

echo "[INFO] Проверка готовности системы к ReaR backup..."

# Проверка ReaR
if ! command -v rear >/dev/null 2>&1; then
    echo "[ERROR] ReaR не найден"
    exit 1
fi

# Проверка монтирования флешки
if ! mountpoint -q /mnt/rear-usb; then
    echo "[ERROR] USB не смонтирован в /mnt/rear-usb"
    exit 1
fi

echo "[OK] Система готова к выполнению rear mkbackup"
exit 0
EOF

    echo "[SUCCESS] Скрипт проверки создан: $target"
}

run_block14() {
    echo "=== СОЗДАНИЕ HELPER-СКРИПТОВ ==="
    create_rear_check_before_backup
    echo "[OK] Helper-скрипты готовы"
}
