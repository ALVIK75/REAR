#!/bin/bash
# =============================================================================
# BLOCK 3: ФУНКЦИИ УСТАНОВКИ ПАКЕТОВ (оптимизировано для ALT Linux 11)
# =============================================================================

check_command() { command -v "$1" >/dev/null 2>&1; }

check_package() {
    local package=$1
    rpm -q "$package" &>/dev/null || dpkg -s "$package" &>/dev/null || return 1
    return 0
}

install_package() {
    local package=$1
    echo "[INFO] Установка $package..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        if apt-get install -y --no-install-recommends "$package" >/dev/null 2>&1; then return 0; fi
        # fallback without the option
        apt-get install -y "$package" >/dev/null 2>&1 && return 0
    fi
    if command -v dnf >/dev/null 2>&1; then dnf -y install "$package" >/dev/null 2>&1 && return 0; fi
    if command -v yum >/dev/null 2>&1; then yum -y install "$package" >/dev/null 2>&1 && return 0; fi
    if command -v zypper >/dev/null 2>&1; then zypper --non-interactive install -y "$package" >/dev/null 2>&1 && return 0; fi
    if command -v apk >/dev/null 2>&1; then apk add --no-cache "$package" >/dev/null 2>&1 && return 0; fi
    if command -v pacman >/dev/null 2>&1; then pacman -S --noconfirm "$package" >/dev/null 2>&1 && return 0; fi
    echo "[ERROR] Не удалось установить $package"
    return 1
}

# остальные функции как были — без интерактива
# create_minimal_default_conf, fix_rear_shebang, check_and_fix_default_conf, etc.
# Для краткости предполагается, что текущая реализация присутствует в файле.
# Основная функция:
run_block3() {
    echo "=== ПРОВЕРКА И УСТАНОВКА ПАКЕТОВ (ALT Linux 11) ==="
    # обновляем и ставим необходимые пакеты
    check_package rear || install_package rear || { echo "[ERROR] Не удалось установить rear"; return 1; }
    create_minimal_default_conf || true
    fix_rear_shebang || true
    echo "[SUCCESS] Блок 3 завершен"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block3
fi