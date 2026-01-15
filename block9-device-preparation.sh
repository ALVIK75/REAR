#!/bin/bash
# =============================================================================
# БЛОК 9: Подготовка USB-устройства (ТОЛЬКО ПРОВЕРКИ)
# =============================================================================

check_device_usage() {
    local device=$1
    [[ "$device" =~ ^/dev/ ]] || device="/dev/$device"
    echo "[INFO] Проверка занятости устройства..."
    local mounted_partitions=()
    while IFS= read -r line; do
        if [[ "$line" == "$device"* ]]; then
            local part_name
            part_name=$(awk '{print $1}' <<<"$line")
            local mount_point
            mount_point=$(awk '{print $2}' <<<"$line")
            if [[ -n "$mount_point" ]]; then mounted_partitions+=("$part_name -> $mount_point"); fi
        fi
    done < <(lsblk -o NAME,MOUNTPOINT 2>/dev/null | sed '1d')
    if [ ${#mounted_partitions[@]} -gt 0 ]; then
        echo "[WARNING] На устройстве $device есть смонтированные разделы:"
        for partition in "${mounted_partitions[@]}"; do echo "  - $partition"; done
        echo "[INFO] Автоматическое размонтирование разделов..."
        for partition in "${mounted_partitions[@]}"; do
            local part_name mount_point
            part_name=$(awk -F ' -> ' '{print $1}' <<<"$partition")
            mount_point=$(awk -F ' -> ' '{print $2}' <<<"$partition")
            echo "[INFO] Размонтируем $part_name с $mount_point..."
            umount "$part_name" 2>/dev/null || umount "$mount_point" 2>/dev/null || umount -f "$part_name" 2>/dev/null || true
        done
        sleep 2
        local remaining_mounts
        remaining_mounts=$(lsblk -o MOUNTPOINT "$device" 2>/dev/null | grep -v '^$' | grep -v '^MOUNTPOINT' | wc -l)
        if [ "$remaining_mounts" -gt 0 ]; then echo "[WARNING] Не все разделы были размонтированы"; else echo "[SUCCESS] Все разделы размонтированы"; fi
    else
        echo "[INFO] На устройстве $device нет смонтированных разделов"
    fi
    return 0
}

verify_device_access() {
    local device=$1
    [[ "$device" =~ ^/dev/ ]] || device="/dev/$device"
    echo "[INFO] Проверка доступности устройства..."
    [ -b "$device" ] || { echo "[ERROR] Устройство $device не найдено"; return 1; }
    [ -r "$device" ] || { echo "[ERROR] Нет доступа на чтение устройства $device"; return 1; }
    [ -w "$device" ] || { echo "[ERROR] Нет доступа на запись устройства $device"; return 1; }
    echo "[SUCCESS] Устройство $device доступно для записи"
    return 0
}

verify_device_type() {
    local device=$1
    [[ "$device" =~ ^/dev/ ]] || device="/dev/$device"
    echo "[INFO] Проверка типа устройства..."
    local device_type transport
    device_type=$(lsblk -no TYPE "$device" 2>/dev/null | head -1 || echo "")
    transport=$(lsblk -no TRAN "$device" 2>/dev/null | head -1 || echo "")
    [ "$device_type" == "disk" ] || echo "[WARNING] Устройство $device не является диском (тип: $device_type)"
    [ "$transport" == "usb" ] || echo "[WARNING] Устройство $device транспорт: $transport"
    echo "[INFO] Проверка типа устройства завершена"
    return 0
}

show_device_info() {
    local device=$1
    [[ "$device" =~ ^/dev/ ]] || device="/dev/$device"
    echo "[INFO] Информация об устройстве:"
    echo "========================================"
    lsblk -o NAME,SIZE,MODEL,TYPE,TRAN,MOUNTPOINT,FSTYPE,LABEL "$device" 2>/dev/null
    echo "========================================"
}

run_block9() {
    echo "=== ПОДГОТОВКА USB-УСТРОЙСТВА (ПРОВЕРКИ) ==="
    if [[ -z "$SELECTED_DEVICE" ]]; then echo "[ERROR] Переменная SELECTED_DEVICE не установлена"; return 1; fi
    echo "[INFO] Подготовка устройства: $SELECTED_DEVICE"
    show_device_info "$SELECTED_DEVICE"
    if ! verify_device_access "$SELECTED_DEVICE"; then echo "[ERROR] Проблемы с доступом к устройству"; return 1; fi
    verify_device_type "$SELECTED_DEVICE"
    if [[ "${USE_EXISTING_USB:-0}" == "1" ]]; then
        echo "[INFO] Используется существующая флешка"
        local mount_info
        mount_info=$(lsblk -no MOUNTPOINT "$SELECTED_DEVICE" 2>/dev/null | grep -v '^$')
        if [[ -n "$mount_info" ]]; then echo "[INFO] Флешка уже смонтирована: $mount_info"; else echo "[INFO] Флешка не смонтирована, будет смонтирована позже"; fi
    else
        if ! check_device_usage "$SELECTED_DEVICE"; then echo "[WARNING] Проблемы с размонтированием устройства"; fi
    fi
    echo "[SUCCESS] Блок 9 завершен: устройство проверено"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block9
fi