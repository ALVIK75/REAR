#!/bin/bash
# =============================================================================
# БЛОК 8: Проверки безопасности (verbose)
# - Подхватывает SELECTED_DEVICE из /run/rear-selected-device если не задана
# - Все интерактивные prompts идут в /dev/tty
# - Выводит подробные статусы для каждой проверки (лог /var/log/rear-setup.log и stdout)
# =============================================================================

LOGFILE="/var/log/rear-setup.log"
PERSIST="/run/rear-selected-device"

log() { echo "$(date '+%F %T') [block8] $*" | tee -a "$LOGFILE"; }
err() { echo "$(date '+%F %T') [block8][ERROR] $*" | tee -a "$LOGFILE" >&2; }
warn() { echo "$(date '+%F %T') [block8][WARN] $*" | tee -a "$LOGFILE"; }
ok() { echo "$(date '+%F %T') [block8][OK] $*" | tee -a "$LOGFILE"; }

# If SELECTED_DEVICE not set, try to read persisted value
if [[ -z "${SELECTED_DEVICE:-}" && -f "$PERSIST" ]]; then
    SELECTED_DEVICE=$(sed -n '1p' "$PERSIST" 2>/dev/null || true)
    export SELECTED_DEVICE
    if [[ -n "${SELECTED_DEVICE:-}" ]]; then
        log "SELECTED_DEVICE загружена из $PERSIST -> $SELECTED_DEVICE"
    fi
fi

tty_read() {
    local prompt="$1"
    printf "%s" "$prompt" > /dev/tty
    read -r ans < /dev/tty
    echo "$ans"
}

check_usb_size() {
    local usb_device=$1
    [[ "$usb_device" =~ ^/dev/ ]] || usb_device="/dev/$usb_device"
    log "check_usb_size: $usb_device"
    if [ ! -b "$usb_device" ]; then
        err "block device $usb_device not found"
        return 1
    fi
    local usb_size_bytes
    usb_size_bytes=$(lsblk -b -n -o SIZE "$usb_device" 2>/dev/null | head -1 || echo 0)
    usb_size_bytes=${usb_size_bytes:-0}
    log "Detected size: $usb_size_bytes bytes"
    if [ "$usb_size_bytes" -eq 0 ]; then
        err "Не удалось определить размер устройства $usb_device"
        return 1
    fi
    if [[ -n "${ESTIMATED_BACKUP_SIZE:-}" && "${ESTIMATED_BACKUP_SIZE}" -gt 0 ]]; then
        local required_size=$(( ESTIMATED_BACKUP_SIZE * 120 / 100 ))
        log "Estimated backup size: ${ESTIMATED_BACKUP_SIZE}, required (120%): $required_size"
        if [ "$usb_size_bytes" -ge "$required_size" ]; then
            ok "Размер флешки достаточен"
            return 0
        else
            err "Размер флешки недостаточен: $usb_size_bytes < $required_size"
            return 1
        fi
    else
        local min_recommended_size=8589934592
        if [ "$usb_size_bytes" -ge "$min_recommended_size" ]; then
            ok "Размер флешки >= 8GB"
            return 0
        else
            warn "Размер флешки менее 8GB ($usb_size_bytes bytes) — продолжим с предупреждением"
            return 0
        fi
    fi
}

check_device_type() {
    local usb_device=$1
    [[ "$usb_device" =~ ^/dev/ ]] || usb_device="/dev/$usb_device"
    log "check_device_type: $usb_device"
    local base_device="$usb_device"
    if [[ "$usb_device" =~ [0-9]$ ]]; then base_device="${usb_device%[0-9]*}"; fi
    local device_type model
    device_type=$(lsblk -d -n -o TRAN "$base_device" 2>/dev/null || echo "")
    model=$(lsblk -d -n -o MODEL "$base_device" 2>/dev/null || echo "")
    log "Transport: $device_type, Model: $model"
    case "$device_type" in
        usb)
            ok "Device transport is usb"
            return 0
            ;;
        sata)
            err "Устройство выглядит как SATA (внутренний диск) — отказ"
            return 1
            ;;
        "")
            if [[ "$model" == *USB* || "$model" == *Flash* || "$base_device" =~ /dev/sd[b-z] ]]; then
                ok "Heuristic: device looks like USB"
                return 0
            else
                warn "Тип устройства не определён (model='$model', transport='$device_type') — продолжаем с предупреждением"
                return 0
            fi
            ;;
        *)
            warn "Transport = $device_type — проверяем у пользователя"
            local ans
            ans=$(tty_read "Вы уверены, что это USB флешка? (y/N): ")
            if [[ "$ans" =~ ^[YyДд]$ ]]; then
                ok "Пользователь подтвердил, считаем устройством USB"
                return 0
            fi
            err "Пользователь отказал — устройство не принято"
            return 1
            ;;
    esac
}

check_mount_status() {
    local usb_device=$1
    [[ "$usb_device" =~ ^/dev/ ]] || usb_device="/dev/$usb_device"
    log "check_mount_status: $usb_device"
    local mountpoints
    mountpoints=$(lsblk -n -o MOUNTPOINT "$usb_device" 2>/dev/null | grep -v '^$' || true)
    if [ -z "$mountpoints" ]; then
        ok "Device has no mounted partitions"
        return 0
    fi
    log "Found mountpoints: $(echo "$mountpoints" | tr '\n' ' | ')"
    local is_rear_flash=0
    while IFS= read -r mp; do
        [ -z "$mp" ] && continue
        local device_path label
        device_path=$(mount | awk -v m="$mp" '$3==m {print $1; exit}' || true)
        label=$(lsblk -no LABEL "$device_path" 2>/dev/null || true)
        log "Mount $mp -> device_path=$device_path label=$label"
        if [ "$label" = "REAR_BACKUP" ] || [ -d "$mp/backups" ] || [ -d "$mp/output" ] || [ -f "$mp/README.txt" ]; then
            is_rear_flash=1
            break
        fi
    done <<< "$mountpoints"
    if [ "$is_rear_flash" -eq 1 ]; then
        ok "Найдена структура ReaR на смонтированном разделе — можно использовать без форматирования"
        return 0
    fi
    warn "Устройство смонтировано, но не содержит ReaR-структуру"
    local answer
    answer=$(tty_read "Размонтировать для подготовки флешки? (y/N): ")
    if [[ "$answer" =~ ^[YyДд]$ ]]; then
        log "User agreed to unmount partitions"
        # unmount all partitions of device
        while IFS= read -r part; do
            [ -z "$part" ] && continue
            log "Attempting to umount /dev/$part"
            umount "/dev/$part" 2>/dev/null || umount -f "/dev/$part" 2>/dev/null || true
        done < <(lsblk -n -o NAME "$usb_device" 2>/dev/null)
        ok "Partitions unmounted (attempted)"
        return 0
    fi
    err "Partitions remain mounted and user declined unmount — cannot proceed"
    return 1
}

check_permissions() {
    local usb_device=$1
    [[ "$usb_device" =~ ^/dev/ ]] || usb_device="/dev/$usb_device"
    log "check_permissions: $usb_device"
    if [ -r "$usb_device" ] && [ -w "$usb_device" ]; then
        ok "Read/write access to block device OK"
        return 0
    fi
    err "No read/write access to $usb_device (device node permissions)"
    ls -l "$usb_device" | tee -a "$LOGFILE"
    return 1
}

check_device_usage() {
    local usb_device=$1
    [[ "$usb_device" =~ ^/dev/ ]] || usb_device="/dev/$usb_device"
    log "check_device_usage: $usb_device"
    if [ -f /proc/mdstat ] && grep -q "$(basename "$usb_device")" /proc/mdstat 2>/dev/null; then
        err "Device appears in /proc/mdstat (RAID member)"
        return 1
    fi
    if command -v pvs >/dev/null 2>&1; then
        if pvs "$usb_device" 2>/dev/null | grep -q .; then
            err "Device used by LVM"
            return 1
        fi
    fi
    local device_name
    device_name=$(basename "$usb_device")
    if mount | grep -q "^/dev/$device_name .* / "; then
        err "Device contains system root or critical partitions"
        return 1
    fi
    ok "Device not used by RAID/LVM/system mounts"
    return 0
}

run_safety_checks_verbose() {
    local usb_device=$1
    log "Starting verbose safety checks for $usb_device"

    local checks=(check_usb_size check_device_type check_mount_status check_permissions check_device_usage)
    local names=("Size" "Type" "Mount" "Permissions" "Usage")
    local i=0
    local critical_failed=0
    for fn in "${checks[@]}"; do
        log "Running ${names[$i]} check (${fn})..."
        if ! "$fn" "$usb_device"; then
            err "${names[$i]} check FAILED"
            ((critical_failed++))
        else
            ok "${names[$i]} check PASSED"
        fi
        ((i++))
    done

    if [ "$critical_failed" -eq 0 ]; then
        ok "All critical checks passed"
        return 0
    else
        err "Critical checks failed: $critical_failed"
        return 1
    fi
}

run_block8() {
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        err "Переменная SELECTED_DEVICE не установлена"
        err "Запустите сначала блок выбора USB устройства или укажите устройство вручную"
        err "Пример: sudo SELECTED_DEVICE=/dev/sdc ./block8-safety-checks.sh"
        return 1
    fi

    # show quick info for debugging
    log "Selected device: $SELECTED_DEVICE"
    lsblk -o NAME,FSTYPE,LABEL,MOUNTPOINT,SIZE "$SELECTED_DEVICE"* 2>/dev/null | tee -a "$LOGFILE"

    if ! run_safety_checks_verbose "$SELECTED_DEVICE"; then
        err "Проверки безопасности не пройдены"
        return 1
    fi

    ok "Блок 8 пройден"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block8
    exit $?
fi