#!/bin/bash
# =============================================================================
# FULL REAR SETUP — Orchestrator
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
info()    { echo -e "ℹ️  ИНФО: $*"; }
success() { echo -e "✅ УСПЕХ: $*"; }
error()   { echo -e "❌ ОШИБКА: $*" >&2; }
warning() { echo -e "⚠️  WARNING: $*"; }

# -----------------------------------------------------------------------------
# Load blocks
# -----------------------------------------------------------------------------
for b in block{1..14}-*.sh; do
    if [ -f "$SCRIPT_DIR/$b" ]; then
        source "$SCRIPT_DIR/$b"
    fi
done

# -----------------------------------------------------------------------------
# Safety
# -----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт должен выполняться от root"
    exit 1
fi

# -----------------------------------------------------------------------------
# Progress bar
# -----------------------------------------------------------------------------
progress() {
    local current="$1"
    local total="$2"
    local width=40
    local done=$(( current * width / total ))
    local left=$(( width - done ))
    printf "\r["
    printf "%${done}s" | tr ' ' '='
    printf "%${left}s" | tr ' ' '-'
    printf "] %d/%d\n" "$current" "$total"
}

# -----------------------------------------------------------------------------
# Fix grubenv (safe, standalone)
# -----------------------------------------------------------------------------
check_and_fix_grubenv() {
    info "Проверка grubenv…"
    local grub="/boot/grub/grubenv"

    if [[ ! -f "$grub" ]]; then
        warning "grubenv не найден, создаю минимальный"
        mkdir -p "$(dirname "$grub")"
        dd if=/dev/zero bs=1 count=1024 of="$grub" &>/dev/null
        chmod 600 "$grub"
        success "grubenv создан"
    else
        local size
        size=$(stat -c %s "$grub" 2>/dev/null || echo 0)
        if (( size < 1024 )); then
            warning "grubenv слишком мал (${size} байт), дополняю до 1024"
            dd if=/dev/zero bs=1 count=$((1024 - size)) oflag=append conv=notrunc of="$grub" &>/dev/null
            success "grubenv исправлен"
        else
            success "grubenv в порядке (${size} байт)"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Main flow
# -----------------------------------------------------------------------------
main() {
    local total=14
    local step=0

    step=$((step+1)); progress "$step" "$total"; run_block1
    step=$((step+1)); progress "$step" "$total"; run_block2
    step=$((step+1)); progress "$step" "$total"; run_block3
    step=$((step+1)); progress "$step" "$total"; run_block4
    step=$((step+1)); progress "$step" "$total"; run_block5
    step=$((step+1)); progress "$step" "$total"; run_block6
    step=$((step+1)); progress "$step" "$total"; run_block7
    step=$((step+1)); progress "$step" "$total"; run_block8
    step=$((step+1)); progress "$step" "$total"; run_block9
    step=$((step+1)); progress "$step" "$total"; run_block10
    step=$((step+1)); progress "$step" "$total"; run_block11
    step=$((step+1)); progress "$step" "$total"; run_block12
    step=$((step+1)); progress "$step" "$total"; run_block13

    # -------------------------------------------------------------------------
    # Helper scripts (единственное место генерации)
    # -------------------------------------------------------------------------
    step=$((step+1)); progress "$step" "$total"; run_block14

    # -------------------------------------------------------------------------
    # Final system fixes
    # -------------------------------------------------------------------------
    check_and_fix_grubenv

    success "НАСТРОЙКА ВЫПОЛНЕНА УСПЕШНО!"
}

main "$@"
