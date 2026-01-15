#!/bin/bash
#
# БЛОК 2: Функции для работы с данными
#

run_block2() {
    echo "[INFO] Запуск блока 2..."

    local mount_point="${MOUNTPOINT:-/mnt/rear-usb}"

    echo "[INFO] Проверка существующих данных на флешке в $mount_point..."

    EXISTING_BACKUP=""
    EXISTING_ISO=""
    EXISTING_OTHER_BACKUPS=()

    if [ -d "$mount_point" ]; then
        local hostname
        hostname=$(hostname -s)
        if [ -d "${mount_point}/backups/${hostname}" ]; then
            local -a backup_files
            mapfile -t backup_files < <(find "${mount_point}/backups/${hostname}/" -maxdepth 1 -type f 2>/dev/null | head -10)
            if [ ${#backup_files[@]} -gt 0 ]; then
                EXISTING_BACKUP="${mount_point}/backups/${hostname}/"
                echo "[INFO] Найден существующий бэкап: ${EXISTING_BACKUP}"
            fi
        fi

        local iso_pattern="${mount_point}/output/rear-${hostname}.iso"
        if [ -f "$iso_pattern" ]; then
            EXISTING_ISO="$iso_pattern"
            echo "[INFO] Найден существующий ISO: $(basename "$EXISTING_ISO")"
        fi

        if [ -d "${mount_point}/backups" ]; then
            for dir in "${mount_point}/backups"/*; do
                [ -d "$dir" ] || continue
                if [ "$(basename "$dir")" != "$hostname" ]; then
                    EXISTING_OTHER_BACKUPS+=("$(basename "$dir")")
                fi
            done
        fi

        if [ ${#EXISTING_OTHER_BACKUPS[@]} -gt 0 ]; then
            echo "[INFO] Найдены бэкапы других систем: ${EXISTING_OTHER_BACKUPS[*]}"
        fi

        if mount | grep -q " on /media " || mount | grep -q " on /mnt "; then
            echo "[WARNING] Обнаружены точки монтирования /media или /mnt - будут исключены из бэкапа"
        fi

        local total_used
        total_used=$(du -sh "$mount_point" 2>/dev/null | cut -f1 || echo "0")
        echo "[INFO] Всего занято на флешке: $total_used"
    else
        echo "[INFO] Точка монтирования $mount_point не существует (это нормально для новой флешки)"
    fi

    echo "[SUCCESS] Блок 2 завершен: функции работы с данными"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block2
fi