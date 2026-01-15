#!/bin/bash
# =============================================================================
# BLOCK 5: УСТАНОВКА REAR (с поддержкой exFAT)
# =============================================================================

# Загружаем функции установки пакетов
if [ -f /usr/local/sbin/block3-package-functions.sh ]; then
    # shellcheck source=/usr/local/sbin/block3-package-functions.sh
    source /usr/local/sbin/block3-package-functions.sh || true
elif [ -f ./block3-package-functions.sh ]; then
    # shellcheck source=./block3-package-functions.sh
    source ./block3-package-functions.sh || true
fi

check_rear_exfat_support() {
    echo "[INFO] Проверка поддержки exFAT в ReaR..."
    if rear -V 2>&1 | grep -qi "exfat"; then
        echo "[INFO] ReaR поддержива��т exFAT"
        return 0
    fi
    if [[ -f /usr/share/rear/conf/default.conf ]]; then
        if grep -qi "exfat" /usr/share/rear/conf/default.conf 2>/dev/null; then
            echo "[INFO] ReaR настроен для поддержки exFAT"
            return 0
        fi
    fi
    echo "[WARNING] ReaR может не иметь встроенной поддержки exFAT"
    echo "[INFO] Для rescue образа потребуются дополнительные утилиты (exfatprogs)"
    return 0
}

install_rear() {
    echo "[INFO] Установка ReaR..."
    if command -v rear >/dev/null 2>&1; then
        echo "[SUCCESS] ReaR уже установлен"
        rear -V 2>/dev/null || true
        check_rear_exfat_support
        return 0
    fi

    if grep -Eqi "ID=alt|ID=altlinux" /etc/os-release 2>/dev/null; then
        if declare -f setup_sisyphus_repo >/dev/null 2>&1; then setup_sisyphus_repo || true; fi
    fi

    if declare -f install_package >/dev/null 2>&1; then
        install_package "rear" || { echo "[ERROR] Не удалось установить rear"; return 1; }
    else
        echo "[WARNING] Функции установки пакетов недоступны. Попробуйте установить rear вручную."
        return 1
    fi

    rear -V 2>/dev/null || true
    check_rear_exfat_support

    local dependencies=( xorriso genisoimage dosfstools e2fsprogs parted lvm2 mdadm )
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            install_package "$dep" >/dev/null 2>&1 || true
        fi
    done

    if ! command -v mkfs.exfat >/dev/null 2>&1 && ! command -v mkexfatfs >/dev/null 2>&1; then
        install_package exfatprogs >/dev/null 2>&1 || install_package exfat-utils >/dev/null 2>&1 || true
    fi

    return 0
}

prepare_rear_dirs() {
    echo "[INFO] Подготовка директорий ReaR..."
    mkdir -p /var/lib/rear/{backup,output} 2>/dev/null || true
    mkdir -p /var/log/rear 2>/dev/null || true
    echo "[SUCCESS] Директории подготовлены"
}

run_block5() {
    echo "=== УСТАНОВКА REAR (с поддержкой exFAT) ==="
    if install_rear; then
        prepare_rear_dirs
        echo "[SUCCESS] REA R установлен и подготовлен"
        return 0
    else
        echo "[ERROR] Не удалось установить ReaR"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block5
fi