#!/bin/bash
# =============================================================================
# БЛОК 3: Проверка и установка пакетов (ALT Linux 11)
# Самодостаточный блок — не зависит от orchestrator
# =============================================================================

set -euo pipefail

create_minimal_default_conf() {
    local DEFAULT_CONF="/usr/share/rear/conf/default.conf"

    echo "[INFO] Проверка default.conf..."

    if [[ -f "$DEFAULT_CONF" ]]; then
        echo "[INFO] default.conf уже существует"
        return 0
    fi

    echo "[WARNING] default.conf не найден — создаю минимальный"
    mkdir -p "$(dirname "$DEFAULT_CONF")" 2>/dev/null || true

    cat > "$DEFAULT_CONF" <<'CONF'
# Minimal default.conf for ReaR (auto-generated)
BACKUP=NETFS
BACKUP_PROG=tar
OUTPUT=ISO
ISO_IS_HYBRID="yes"
MODULES=( 'all_modules' )
MODULES_LOAD=( 'yes' )
VERBOSE="1"
CONF

    chmod 644 "$DEFAULT_CONF" 2>/dev/null || true
    echo "[SUCCESS] Создан $DEFAULT_CONF"
}

fix_rear_shebang() {
    local rear_bin
    rear_bin="$(command -v rear 2>/dev/null || true)"

    [[ -z "$rear_bin" ]] && return 0

    local shebang
    shebang="$(head -n1 "$rear_bin" 2>/dev/null || true)"

    if [[ "$shebang" != "#!/bin/bash" && "$shebang" != "#!/usr/bin/env bash" ]]; then
        echo "[WARNING] Некорректный shebang у rear ($shebang) — исправляю"
        sed -i '1s@^.*$@#!/usr/bin/env bash@' "$rear_bin" 2>/dev/null || true
        chmod +x "$rear_bin" 2>/dev/null || true
        echo "[SUCCESS] shebang у rear исправлен"
    else
        echo "[INFO] shebang у rear корректен"
    fi
}

run_block3() {
    echo "=== ПРОВЕРКА И УСТАНОВКА ПАКЕТОВ (ALT Linux 11) ==="

    create_minimal_default_conf
    fix_rear_shebang

    echo "[SUCCESS] Блок 3 завершен"
}
