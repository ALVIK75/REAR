#!/bin/bash
# =============================================================================
# БЛОК 3: Проверка и установка пакетов (ALT Linux)
# Самодостаточный блок: все используемые функции определены здесь
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Helper: create minimal default.conf if missing
# -----------------------------------------------------------------------------
create_minimal_default_conf() {
    local DEFAULT_CONF="/usr/share/rear/conf/default.conf"

    if [[ -f "$DEFAULT_CONF" ]]; then
        echo "[INFO] default.conf уже существует"
        return 0
    fi

    echo "[INFO] default.conf не найден — создаю минимальный"

    mkdir -p "$(dirname "$DEFAULT_CONF")"

    cat > "$DEFAULT_CONF" <<'EOF'
# Minimal default.conf (auto-generated)
BACKUP=NETFS
BACKUP_PROG=tar
OUTPUT=ISO
ISO_IS_HYBRID="yes"
MODULES=( 'all_modules' )
MODULES_LOAD=( 'yes' )
VERBOSE="1"
EOF

    chmod 644 "$DEFAULT_CONF"
    echo "[SUCCESS] Создан $DEFAULT_CONF"
}

# -----------------------------------------------------------------------------
# Helper: fix rear shebang if needed
# -----------------------------------------------------------------------------
fix_rear_shebang() {
    local rear_bin
    rear_bin="$(command -v rear 2>/dev/null || true)"

    [[ -z "$rear_bin" ]] && return 0

    local shebang
    shebang="$(head -n1 "$rear_bin" 2>/dev/null || true)"

    if [[ "$shebang" == "#!/bin/bash" || "$shebang" == "#!/usr/bin/env bash" ]]; then
        echo "[INFO] shebang у rear корректен"
        return 0
    fi

    echo "[WARNING] Некорректный shebang у rear ($shebang) — исправляю"
    sed -i '1s@^.*$@#!/usr/bin/env bash@' "$rear_bin"
    chmod +x "$rear_bin"
    echo "[SUCCESS] shebang у rear исправлен"
}

# -----------------------------------------------------------------------------
# Main block
# -----------------------------------------------------------------------------
run_block3() {
    echo "=== ПРОВЕРКА И УСТАНОВКА ПАКЕТОВ (ALT Linux) ==="

    # Проверка наличия rear
    if ! command -v rear >/dev/null 2>&1; then
        echo "[INFO] ReaR не найден — установка"
        apt-get update
        apt-get install -y rear
    else
        echo "[INFO] ReaR уже установлен"
    fi

    # Проверка и создание default.conf
    create_minimal_default_conf

    # Проверка shebang у rear
    fix_rear_shebang

    echo "[SUCCESS] Блок 3 завершен"
}
