#!/bin/bash
# =============================================================================
# БЛОК 10: Форматирование флешки (exFAT) — исправленная, более надёжная версия
# - Убирает проблемы с некорректными пробелами и неправильной проверкой
# - Использует grep -c / findmnt для получения числовых значений без ведущих пробело��
# - Надёжно размонтирует разделы, завершает процессы, очищает таблицу, создаёт GPT и exFAT
# =============================================================================

set -euo pipefail

# Переменные по умолчанию (можно переопределить извне)
MOUNTPOINT="${MOUNTPOINT:-/mnt/rear-usb}"
SELECTED_DEVICE="${SELECTED_DEVICE:-}"

log()  { printf '%s [block10] %s\n' "$(date '+%F %T')" "$*"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*"; }
err()  { log "ERROR: $*"; }

# Проверка предварительных условий
_preflight_check() {
    if [[ -z "$SELECTED_DEVICE" ]]; then
        err "SELECTED_DEVICE не установлена"
        return 1
    fi
    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        err "Устройство $SELECTED_DEVICE не найдено как блочное устройство"
        return 1
    fi
    return 0
}

# Завершаем процессы, использующие устройство (по имени базового устройства)
kill_processes_using_usb() {
    local dev_base
    dev_base=$(basename "$SELECTED_DEVICE")
    info "Поиск процессов, работающих с /dev/${dev_base}*"
    if command -v lsof >/dev/null 2>&1; then
        local pids
        pids=$(lsof -t "/dev/${dev_base}"* 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            info "Найдено процессов: $(echo "$pids" | wc -w)"
            for pid in $pids; do
                kill -TERM "$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
    else
        info "lsof не установлен — пропускаем явное завершение процессов"
    fi
}

# Размонтирование всех разделов устройства
unmount_device() {
    local device="$1"
    info "Размонтирование устройства $device ..."

    # Получаем список дочерних имен (без базового диска)
    # Используем lsblk, берем строки после первой (NR>1)
    local parts
    IFS=$'\n' read -r -d '' -a parts < <(lsblk -ln -o NAME "$device" 2>/dev/null | awk 'NR>1{print $1}' || true; printf '\0')

    if [[ ${#parts[@]} -eq 0 ]]; then
        info "Разделов для размонтирования не найдено"
    else
        for part in "${parts[@]}"; do
            [[ -z "$part" ]] && continue
            local full="/dev/${part}"
            # определяем точку монтирования безопасно через findmnt или lsblk
            local mp
            if command -v findmnt >/dev/null 2>&1; then
                mp=$(findmnt -n -o TARGET --source "$full" 2>/dev/null || true)
            else
                mp=$(lsblk -n -o MOUNTPOINT "$full" 2>/dev/null | grep -v '^$' || true)
            fi
            if [[ -n "$mp" ]]; then
                info "Попытка размонтировать $full (точка: $mp)"
                umount "$mp" 2>/dev/null || umount -f "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || umount "$full" 2>/dev/null || true
                sleep 1
            fi
        done
    fi

    # Даем системе время и проверяем наличие монтирований по базовому устройству
    sleep 1
    local still_mounted
    # используем grep -c чтобы получить целое число без ведущих пробелов
    still_mounted=$(mount | grep -cE "^/dev/$(basename "$device")" || true)
    if [[ -z "$still_mounted" ]]; then
        still_mounted=0
    fi

    if [ "$still_mounted" -eq 0 ]; then
        info "Все разделы размонтированы"
        return 0
    fi

    err "Устройство всё ещё смонтировано (count=$still_mounted)"
    return 1
}

# Очистка таблицы разделов (wipefs + dd)
clean_partition_table() {
    local device="$1"
    info "Очистка таблицы разделов на $device ..."
    if command -v wipefs >/dev/null 2>&1; then
        wipefs -a "$device" 2>/dev/null || true
    fi
    # Сбрасываем первые 10MiB чтобы убрать MBR/GPT и подписи
    dd if=/dev/zero of="$device" bs=1M count=10 conv=fsync >/dev/null 2>&1 || true
    sync
    return 0
}

# Создание GPT и одного раздела на весь диск
create_partition_table() {
    local device="$1"
    info "Создание GPT и одного partition на $device ..."
    if command -v parted >/dev/null 2>&1; then
        parted -s "$device" mklabel gpt >/dev/null 2>&1 || true
        parted -s "$device" mkpart primary 1MiB 100% >/dev/null 2>&1 || true
        # дать ядру пересканировать таблицу
        if command -v partprobe >/dev/null 2>&1; then
            partprobe "$device" 2>/dev/null || true
        fi
        sleep 1
        return 0
    fi

    # fallback to sfdisk/fdisk
    if command -v sfdisk >/dev/null 2>&1; then
        echo ',,L' | sfdisk "$device" >/dev/null 2>&1 || true
        sleep 1
        return 0
    fi

    # fdisk fallback
    printf 'g\nn\n\n\n\nw\n' | fdisk "$device" >/dev/null 2>&1 || true
    sleep 1
    return 0
}

# Создание exFAT файловой системы (предпочтительно mkfs.exfat)
create_filesystem() {
    local partition="${SELECTED_DEVICE}1"
    info "Создание файловой системы на $partition ..."
    # Ждём появления раздела
    local tries=0
    while [[ ! -b "$partition" && $tries -lt 10 ]]; do
        sleep 1
        tries=$((tries + 1))
    done
    if [[ ! -b "$partition" ]]; then
        err "Раздел $partition не найден после ожидания"
        return 1
    fi

    if command -v mkfs.exfat >/dev/null 2>&1; then
        mkfs.exfat -n "REAR_BACKUP" "$partition" >/dev/null 2>&1 || {
            err "mkfs.exfat завершился с ошибкой"
            return 1
        }
        info "mkfs.exfat успешно"
        return 0
    fi

    if command -v mkexfatfs >/dev/null 2>&1; then
        mkexfatfs -n "REAR_BACKUP" "$partition" >/dev/null 2>&1 || {
            err "mkexfatfs завершился с ошибкой"
            return 1
        }
        info "mkexfatfs успешно"
        return 0
    fi

    # fallback: mkfs.vfat (FAT32) — предупреждение о лимите 4GB
    if command -v mkfs.vfat >/dev/null 2>&1; then
        warn "mkfs.exfat не найден — используем FAT32 (ограничение 4GB на файл)"
        mkfs.vfat -F32 -n "REAR_BACKUP" "$partition" >/dev/null 2>&1 || {
            err "mkfs.vfat завершился с ошибкой"
            return 1
        }
        info "mkfs.vfat успешно"
        return 0
    fi

    err "Нет утилит для создания exFAT/FAT. Установите exfatprogs или dosfstools."
    return 1
}

# Монтирование раздела в MOUNTPOINT
mount_device() {
    info "Монтирование в $MOUNTPOINT ..."
    mkdir -p "$MOUNTPOINT"
    local partition="${SELECTED_DEVICE}1"

    if mount -L REAR_BACKUP "$MOUNTPOINT" 2>/dev/null; then
        info "Смонтировано по метке REAR_BACKUP"
        return 0
    fi

    if mount -t exfat "$partition" "$MOUNTPOINT" 2>/dev/null; then
        info "Смонтировано как exfat"
        return 0
    fi

    if mount "$partition" "$MOUNTPOINT" 2>/dev/null; then
        info "Смонтировано (автоопределение)"
        return 0
    fi

    err "Не удалось смонтировать $partition"
    return 1
}

# Основная логика выполнения блока 10
run_block10() {
    info "=== ФОРМАТИРОВАНИЕ USB-ФЛЕШКИ (exFAT) ==="

    _preflight_check || return 1

    local max_attempts=3
    local attempt=1
    local success_flag=0

    while [[ $attempt -le $max_attempts && $success_flag -eq 0 ]]; do
        info "Попытка #$attempt"

        # Завершаем процессы
        kill_processes_using_usb >/dev/null 2>&1 || true

        # Размонтируем все разделы устройства
        if ! unmount_device "$SELECTED_DEVICE"; then
            warn "Не удалось размонтировать устройство (попытка $attempt)"
            attempt=$((attempt + 1))
            sleep 1
            continue
        fi

        # Очистка таблицы разделов
        if ! clean_partition_table "$SELECTED_DEVICE"; then
            warn "Очистка таблицы разделов не удалась (попытка $attempt)"
            attempt=$((attempt + 1))
            sleep 1
            continue
        fi

        # Создаём новую таблицу разделов
        if ! create_partition_table "$SELECTED_DEVICE"; then
            warn "Создание таблицы разделов не удалось (попытка $attempt)"
            attempt=$((attempt + 1))
            sleep 1
            continue
        fi

        # Создаём exFAT файловую систему
        if ! create_filesystem; then
            warn "Создание файловой системы не удалось (попытка $attempt)"
            attempt=$((attempt + 1))
            sleep 1
            continue
        fi

        # Монтируем и проверяем
        if ! mount_device; then
            warn "Монтирование не удалось (попытка $attempt)"
            attempt=$((attempt + 1))
            sleep 1
            continue
        fi

        success_flag=1
    done

    if [[ $success_flag -eq 1 ]]; then
        info "Форматирование и подготовка флешки выполнены успешно"
        return 0
    else
        err "Не удалось отформатировать флешку после $max_attempts попыток"
        return 1
    fi
}

# если запущен напрямую, выполнить
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block10
fi