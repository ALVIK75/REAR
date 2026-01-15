#!/bin/bash
# =============================================================================
# БЛОК 7: Выбор USB устройство (с сохранением выбора в /run/rear-selected-device)
# =============================================================================

PERSIST="/run/rear-selected-device"

select_usb_device() {
    echo "=== ВЫБОР USB УСТРОЙСТВА ==="
    echo "[INFO] Поиск доступных USB устройств..."
    echo "ДОСТУПНЫЕ УСТРОЙСТВА:"
    echo "========================================"
    lsblk -o NAME,SIZE,MODEL,TYPE,TRAN,MOUNTPOINT,FSTYPE,LABEL 2>/dev/null | sed '1d'
    echo "========================================"

    local usb_devices=()
    local all_devices=()

    while IFS= read -r line; do
        name=$(awk '{print $1}' <<<"$line")
        # skip partitions
        if [[ "$name" =~ [0-9]$ ]]; then
            continue
        fi
        all_devices+=("$name")

        transport=$(lsblk -no TRAN "/dev/$name" 2>/dev/null | head -1)
        model=$(lsblk -no MODEL "/dev/$name" 2>/dev/null | head -1)
        is_usb=0

        if [[ "$transport" == "usb" ]]; then is_usb=1; fi
        if [[ "$model" == *"USB"* ]] || [[ "$model" == *"Flash"* ]]; then is_usb=1; fi
        if [[ ! "$name" =~ ^(sda|nvme0n1|mmcblk0)$ ]]; then is_usb=1; fi
        if [ -d "/sys/block/$name/device" ] && readlink "/sys/block/$name/device" 2>/dev/null | grep -qi "usb"; then
            is_usb=1
        fi

        if [ $is_usb -eq 1 ]; then usb_devices+=("$name"); fi
    done < <(lsblk -o NAME,TYPE 2>/dev/null | grep 'disk' | sed '1d')

    if [ ${#usb_devices[@]} -eq 0 ]; then
        echo "[WARNING] Не найдено USB устройств по строгим критериям"
        echo "[INFO] Показываю все доступные НЕсистемные диски..."

        local device_index=1
        local device_map=()

        echo "ВСЕ ДОСТУПНЫЕ НЕСИСТЕМНЫЕ ДИСКИ:"
        echo "========================================"

        for device in "${all_devices[@]}"; do
            if [[ "$device" == "sda" ]] || [[ "$device" == "nvme0n1" ]] || [[ "$device" == "mmcblk0" ]]; then
                continue
            fi
            mount_info=$(lsblk -no MOUNTPOINT "/dev/$device" 2>/dev/null)
            if echo "$mount_info" | grep -Eq "^/|/boot|/home|/var|/usr"; then
                continue
            fi
            device_map+=("$device")
            size=$(lsblk -no SIZE "/dev/$device" 2>/dev/null | head -1)
            model=$(lsblk -no MODEL "/dev/$device" 2>/dev/null | head -1)
            echo "  $device_index) /dev/$device - $size - $model"
            ((device_index++))
        done
        echo "========================================"

        if [ ${#device_map[@]} -eq 0 ]; then
            echo "[ERROR] Не найдено подходящих устройств"
            return 1
        fi

        while :; do
            printf "Номер устройства (1-%d): " "${#device_map[@]}" > /dev/tty
            read -r choice < /dev/tty
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#device_map[@]}" ]; then
                SELECTED_DEVICE="/dev/${device_map[$((choice-1))]}"
                break
            fi
            printf "Неверный выбор. Введите номер от 1 до %d\n" "${#device_map[@]}" > /dev/tty
        done
    else
        echo "НАЙДЕНЫ USB УСТРОЙСТВА:"
        echo "========================================"
        usb_index=1
        usb_map=()
        for device in "${usb_devices[@]}"; do
            usb_map+=("$device")
            size=$(lsblk -no SIZE "/dev/$device" 2>/dev/null | head -1)
            model=$(lsblk -no MODEL "/dev/$device" 2>/dev/null | head -1)
            transport=$(lsblk -no TRAN "/dev/$device" 2>/dev/null | head -1)
            echo "  $usb_index) /dev/$device - $size - $model (TRAN: $transport)"
            ((usb_index++))
        done
        echo "========================================"

        while :; do
            printf "Номер USB устройства (1-%d): " "${#usb_map[@]}" > /dev/tty
            read -r choice < /dev/tty
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#usb_map[@]}" ]; then
                SELECTED_DEVICE="/dev/${usb_map[$((choice-1))]}"
                break
            fi
            printf "Неверный выбор. Введите номер от 1 до %d\n" "${#usb_map[@]}" > /dev/tty
        done
    fi

    # persist selection for other processes
    if [[ -n "${SELECTED_DEVICE:-}" ]]; then
        mkdir -p /run
        printf "%s\n" "$SELECTED_DEVICE" > "$PERSIST"
        chmod 644 "$PERSIST" 2>/dev/null || true
        export SELECTED_DEVICE
        echo "[INFO] Выбрано устройство: $SELECTED_DEVICE (сохранено в $PERSIST)"
        return 0
    fi

    return 1
}

run_block7() {
    echo "=== ВЫБОР USB УСТРОЙСТВА ==="
    SELECTED_DEVICE=""
    if select_usb_device; then
        export SELECTED_DEVICE
        return 0
    else
        echo "[ERROR] Не удалось выбрать устройство"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block7
fi