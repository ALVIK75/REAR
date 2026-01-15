#!/bin/bash
# =============================================================================
# БЛОК 6: Анализ системы
# =============================================================================

analyze_boot() {
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
        echo "[INFO] Режим загрузки: UEFI"
    else
        BOOT_MODE="BIOS"
        echo "[INFO] Режим загрузки: BIOS"
    fi
}

analyze_disks() {
    local root_disk
    root_disk=$(lsblk -lnpo NAME,MOUNTPOINT | awk '$2=="/"{print $1}' | sed 's/[0-9]*$//' | head -1 || true)
    echo "[INFO] Корневой диск: ${root_disk:-не определен}"

    if command -v pvs >/dev/null 2>&1 && pvs 2>/dev/null | grep -q .; then
        LVM_USED=1
        echo "[INFO] Обнаружено использование LVM"
    else
        LVM_USED=0
    fi

    if [ -f /proc/mdstat ] && grep -q active /proc/mdstat 2>/dev/null; then
        RAID_USED=1
        echo "[INFO] Обнаружено использование RAID"
    else
        RAID_USED=0
    fi
}

estimate_backup_size() {
    echo "[INFO] Оценка размера бэкапа..."
    local root_size=0 home_size=0 total_size
    root_size=$(df -B1 / 2>/dev/null | awk 'NR==2 {print $3}' || echo 0)
    if [ -d /home ]; then home_size=$(df -B1 /home 2>/dev/null | awk 'NR==2 {print $3}' || echo 0); fi
    total_size=$(( root_size + home_size ))
    if [ "$total_size" -eq 0 ]; then
        ESTIMATED_BACKUP_SIZE=17179869184
    else
        ESTIMATED_BACKUP_SIZE=$(( total_size * 60 / 100 ))
    fi
    if command -v numfmt >/dev/null 2>&1; then
        local display
        display=$(numfmt --to=iec "$ESTIMATED_BACKUP_SIZE")
        echo "[INFO] Ориентировочный размер бэкапа: $display"
    fi
}

run_block6() {
    echo "=== АНАЛИЗ СИСТЕМЫ ==="
    analyze_boot
    analyze_disks
    estimate_backup_size
    USE_EXISTING_USB=0
    echo "[INFO] Будет подготовлена новая флешка"
    export BOOT_MODE LVM_USED RAID_USED ESTIMATED_BACKUP_SIZE USE_EXISTING_USB
    echo "[SUCCESS] Анализ системы завершен"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block6
fi