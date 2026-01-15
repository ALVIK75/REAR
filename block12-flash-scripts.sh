#!/bin/bash
# =============================================================================
# БЛОК 12: Минимальные скрипты для флешки
# =============================================================================

create_readme() {
    local mountpoint="${1:-/mnt/rear-usb}"
    local readme_path="$mountpoint/README.txt"
    echo "[INFO] Создание README файла..."
    local HOSTNAME OS_RELEASE
    HOSTNAME=$(hostname -s)
    if [ -f /etc/altlinux-release ]; then OS_RELEASE=$(head -1 /etc/altlinux-release); fi
    cat > "$readme_path" <<EOF
USB-ФЛЕШКА ДЛЯ REAR ВОССТАНОВЛЕНИЯ
==================================

СИСТЕМА: $HOSTNAME ($OS_RELEASE)
ДАТА НАСТРОЙКИ: $(date)
МЕТКА ФЛЕШКИ: REAR_BACKUP
ФАЙЛОВАЯ СИСТЕМА: exFAT

СТРУКТУРА ФЛЕШКИ:
• /backups/    - бэкапы системы
• /output/     - rescue образы
• /README.txt  - этот файл

ОСНОВНЫЕ КОМАНДЫ REAR:
1. СОЗДАНИЕ БЭКАПА (в рабочей системе):
   sudo rear mkbackup

2. СОЗДАНИЕ RESCUE ОБРАЗА:
   sudo rear mkrescue

3. ВОССТАНОВЛЕНИЕ (после загрузки с флешки):
   sudo rear recover

4. ПРОВЕРКИ:
   sudo rear checklayout
   sudo rear validate
EOF
    echo "[SUCCESS] README файл создан: $readme_path"
}

run_block12() {
    echo "=== БЛОК 12: СОЗДАНИЕ СКРИПТОВ ДЛЯ ФЛЕШКИ ==="
    MOUNTPOINT="${MOUNTPOINT:-/mnt/rear-usb}"
    if ! mountpoint -q "$MOUNTPOINT" 2>/dev/null; then
        echo "[WARNING] Флешка не смонтирована в $MOUNTPOINT"; return 1
    fi
    create_readme "$MOUNTPOINT"
    cat > "$MOUNTPOINT/check-usb.sh" <<'EOF'
#!/bin/bash
echo "=== ПРОВЕРКА USB ФЛЕШКИ REAR ==="
echo "Дата: $(date)"
echo
echo "Структура флешки:"
ls -la
echo
echo "Свободное место:"
df -h .
echo
echo "Метка флешки:"
lsblk -no LABEL $(df . | awk 'NR==2 {print $1}')
echo
echo "✅ Флешка готова к использованию"
EOF
    chmod +x "$MOUNTPOINT/check-usb.sh"
    if [[ -f "$MOUNTPOINT/README.txt" ]]; then
        echo "[SUCCESS] Файлы на флешке:"; ls -la "$MOUNTPOINT"
        echo "[SUCCESS] Флешка готова"
        return 0
    else
        echo "[ERROR] Не удалось создать файлы на флешке"; return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block12
fi