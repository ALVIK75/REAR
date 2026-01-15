#!/bin/bash
#
# БЛОК 11: Создание конфигурации ReaR (исправленная версия)
# В этом файле интерактивные подтверждения читаются из /dev/tty
#

# Основная функция блока 11
run_block11() {
    echo "=== БЛОК 11: КОНФИГУРАЦИЯ REAR (исправленная) ==="
    echo "[INFO] Запуск блока 11..."

    if [[ -z "$LVM_USED" ]]; then LVM_USED=0; fi
    if [[ -z "$RAID_USED" ]]; then RAID_USED=0; fi

    local MOUNTPOINT="${MOUNTPOINT:-/mnt/rear-usb}"
    local SELECTED_DEVICE="${SELECTED_DEVICE:-}"

    echo "[INFO] LVM_USED=$LVM_USED, RAID_USED=$RAID_USED"
    echo "[INFO] Точка монтирования флешки: $MOUNTPOINT"
    echo "[INFO] Устройство флешки: $SELECTED_DEVICE"

    if ! command -v rear >/dev/null 2>&1; then
        echo "[ERROR] ReaR не установлен. Установите его сначала: apt-get install rear"
        return 1
    fi

    if ! mountpoint -q "$MOUNTPOINT" 2>/dev/null; then
        echo "[WARNING] Флешка не смонтирована в $MOUNTPOINT"
        echo "[INFO] Попробую смонтировать автоматически..."
        if [[ -n "$SELECTED_DEVICE" && -b "${SELECTED_DEVICE}1" ]]; then
            mkdir -p "$MOUNTPOINT"
            if mount -t exfat "${SELECTED_DEVICE}1" "$MOUNTPOINT" 2>/dev/null; then
                echo "[SUCCESS] Флешка exFAT смонтирована в $MOUNTPOINT"
            elif mount "${SELECTED_DEVICE}1" "$MOUNTPOINT" 2>/dev/null; then
                echo "[SUCCESS] Флешка смонтирована с автоопределением типа"
            else
                echo "[ERROR] Не удалось смонтировать флешку"
                echo "[INFO] Смонтируйте вручную: mount -t exfat ${SELECTED_DEVICE}1 $MOUNTPOINT"
                return 1
            fi
        else
            echo "[ERROR] Не удалось определить устройство флешки"
            return 1
        fi
    else
        echo "[SUCCESS] Флешка уже смонтирована в $MOUNTPOINT"
        local fstype
        fstype=$(df -T "$MOUNTPOINT" 2>/dev/null | awk 'NR==2 {print $2}')
        echo "[INFO] Тип файловой системы флешки: $fstype"
        if [[ "$fstype" == "exfat" || "$fstype" == "fuseblk" ]]; then
            echo "[INFO] Флешка использует exFAT - поддержка больших файлов (>4GB)"
        elif [[ "$fstype" == "vfat" ]]; then
            echo "[WARNING] Флешка использует FAT32 - ограничение 4GB на файл!"
            echo "[INFO] Для бэкапов >4GB рекомендуется переформатировать в exFAT"
        fi
    fi

    echo "[INFO] Создание структуры директорий на флешке..."
    mkdir -p "$MOUNTPOINT/backups" "$MOUNTPOINT/output" 2>/dev/null || true
    if ! touch "$MOUNTPOINT/backups/test_write" 2>/dev/null; then
        echo "[ERROR] Нет прав на запись в $MOUNTPOINT/backups"
        return 1
    fi
    rm -f "$MOUNTPOINT/backups/test_write"

    REAR_CONF="/etc/rear/local.conf"
    if [ -f "$REAR_CONF" ]; then
        BACKUP_CONF="${REAR_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$REAR_CONF" "$BACKUP_CONF" || true
        echo "[INFO] Создан backup конфига: $BACKUP_CONF"
    fi

    mkdir -p /var/lib/rear/{backup,output} 2>/dev/null || true
    mkdir -p /var/log/rear 2>/dev/null || true

    # (далее по тексту создаём директории, скрипты, конфиг — без интерактива)
    # Создание automount-скрипта
    local AUTOMOUNT_SCRIPT="/usr/share/rear/rescue/GNU/Linux/20_mount_rear_usb.sh"
    mkdir -p "$(dirname "$AUTOMOUNT_SCRIPT")"
    cat > "$AUTOMOUNT_SCRIPT" <<'AUTOMOUNT_EOF'
#!/bin/bash
# Минимальный POSIX-автомаунт для ReaR (как в предыдущей версии)
REAR_MOUNTPOINT="${REAR_MOUNTPOINT:-/mnt/rear-usb}"
LABEL="REAR_BACKUP"
LOGFILE="${LOGFILE:-/tmp/rear-usb-mount.log}"
DEVICE_WAIT_TIMEOUT=8
SLEEP_INTERVAL=1
log() { printf '%s - %s\n' "$(date '+%F %T')" "$*" >> "${LOGFILE}" 2>/dev/null || true; }
is_rear_structure() { [ -d "$1/backups" ] || [ -d "$1/output" ] || [ -f "$1/README.txt" ] || [ -f "$1/check-usb.sh" ]; }
try_mount() { dev="$1"; mp="$2"; mkdir -p "$mp" 2>/dev/null || true; if mount -L "$LABEL" "$mp" 2>/dev/null; then log "mounted by label $LABEL -> $mp"; return 0; fi; if command -v blkid >/dev/null 2>&1; then uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true); fi; if [ -n "${uuid:-}" ] && mount -U "$uuid" "$mp" 2>/dev/null; then log "mounted by uuid"; return 0; fi; for fs in exfat vfat ntfs ext4 xfs btrfs; do if mount -t "$fs" "$dev" "$mp" 2>/dev/null; then log "mounted $dev as $fs -> $mp"; return 0; fi; done; if mount "$dev" "$mp" 2>/dev/null; then log "mounted $dev (auto) -> $mp"; return 0; fi; return 1; }
find_rear_device() { if command -v blkid >/dev/null 2>&1; then bylabel=$(blkid -L "$LABEL" 2>/dev/null || true); [ -n "$bylabel" ] && { echo "$bylabel"; return 0; }; fi; mount | awk '/\/dev\// {print $1, $3}' | while read -r dev mp; do [ -n "$mp" ] && is_rear_structure "$mp" && { echo "$mp"; return 0; }; done; for pat in /dev/sd[b-z]* /dev/mmcblk*[p0-9]* /dev/nvme*n*; do for node in $pat; do [ -b "$node" ] || continue; for cand in "$node" "${node}1" "${node}p1"; do [ -b "$cand" ] || continue; tmp=$(mktemp -d 2>/dev/null || echo /tmp); if mount "$cand" "$tmp" 2>/dev/null; then if is_rear_structure "$tmp"; then umount "$tmp" 2>/dev/null || true; rmdir "$tmp" 2>/dev/null || true; echo "$cand"; return 0; fi; umount "$tmp" 2>/dev/null || true; fi; rmdir "$tmp" 2>/dev/null || true; done; done; done; return 1; }
wait_for_device() { deadline=$((SECONDS + DEVICE_WAIT_TIMEOUT)); while [ $SECONDS -lt $deadline ]; do found=$(find_rear_device 2>/dev/null || true); [ -n "$found" ] && { echo "$found"; return 0; }; sleep "$SLEEP_INTERVAL"; done; return 1; }
main() { log "automount start"; mountpoint -q "$REAR_MOUNTPOINT" 2>/dev/null && { log "already mounted"; exit 0; }; dev=$(find_rear_device || true); [ -z "$dev" ] && dev=$(wait_for_device || true); [ -z "$dev" ] && { log "no REAR device found"; echo "REAR USB not found"; exit 1; }; if [ -d "$dev" ] && mountpoint -q "$dev" 2>/dev/null; then mkdir -p "$REAR_MOUNTPOINT" 2>/dev/null || true; ln -sf "$dev" "$REAR_MOUNTPOINT" 2>/dev/null || true; log "found already mounted at $dev"; echo "$REAR_MOUNTPOINT"; exit 0; fi; [ -b "$dev" ] && [ -b "${dev}1" ] && dev="${dev}1"; try_mount "$dev" "$REAR_MOUNTPOINT" && { log "mounted $dev -> $REAR_MOUNTPOINT"; echo "$REAR_MOUNTPOINT"; exit 0; }; log "failed to mount $dev"; exit 1; }
main "$@"
AUTOMOUNT_EOF
    chmod +x "$AUTOMOUNT_SCRIPT"

    # Создание конфигурации local.conf (минимум — снабжать COPY_AS_IS на automount)
    cat > "$REAR_CONF" <<EOF
### Auto-generated /etc/rear/local.conf
BACKUP=NETFS
BACKUP_URL="file://${MOUNTPOINT}/backups"
OUTPUT=ISO
OUTPUT_URL="file://${MOUNTPOINT}/output"
INCLUDE_FILES=( "/boot/grub/grubenv" )
COPY_AS_IS+=( "$AUTOMOUNT_SCRIPT" )
COPY_AS_IS+=( "/usr/share/rear/conf/default.conf" )
COPY_AS_IS+=( "/usr/share/rear/conf/default.conf" )
EOF

    echo "[SUCCESS] Конфигурация ReaR создана: $REAR_CONF"
    echo "[SUCCESS] Automount script created: $AUTOMOUNT_SCRIPT"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block11
fi