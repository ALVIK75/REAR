#!/bin/bash
# =============================================================================
# ПОЛНАЯ НАСТРОЙКА ReaR ДЛЯ ALT LINUX
# Размещайте рядом с блоками (например /opt/rear-setup) и запускайте от root:
#   sudo ./full-rear-setup.sh [--force-format] [--really-force]
# =============================================================================

set -euo pipefail

# Simple status printers
error()   { echo "❌ ОШИБКА: $*"; }
success() { echo "✅ УСПЕХ: $*"; }
warning() { echo "⚠️  ВНИМАНИЕ: $*"; }
info()    { echo "ℹ️  ИНФО: $*"; }

# ----- CLI options -----------------------------------------------------------
FORCE_FORMAT="${FORCE_FORMAT:-0}"
REALLY_FORCE="${REALLY_FORCE:-0}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-format) FORCE_FORMAT=1; shift ;;
        --really-force) REALLY_FORCE=1; shift ;;
        -h|--help)
            cat <<'USAGE'
Usage: sudo ./full-rear-setup.sh [--force-format] [--really-force]

Options:
  --force-format   Пометить флешку на форматирование (обходит выбор 1/2).
                   Финальное wipe всё равно требует ввода REALLY, если не
                   указать --really-force.
  --really-force   Полное подтверждение: пропускает финальный safety prompt.
  -h, --help       Показать это сообщение.
USAGE
            exit 0
            ;;
        *) break ;;
    esac
done
export FORCE_FORMAT REALLY_FORCE

# ----- Globals ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/rear-setup.log"
START_TIME=$(date +%s)
PERSIST="/run/rear-selected-device"

export SELECTED_DEVICE="${SELECTED_DEVICE:-}"
export MOUNTPOINT="${MOUNTPOINT:-/mnt/rear-usb}"
export USE_EXISTING_USB="${USE_EXISTING_USB:-0}"
export SKIP_USB_PREP="${SKIP_USB_PREP:-0}"

log() { echo "$(date '+%F %T') - $*" | tee -a "$LOG_FILE"; }

# ----- Environment checks ---------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Скрипт должен запускаться от root"
        exit 1
    fi
}

check_alt_linux() {
    if grep -Eqi "ID=alt|ID=altlinux|NAME=.*ALT" /etc/os-release 2>/dev/null; then
        success "ALT Linux обнаружен"
    else
        warning "Система, похоже, не ALT Linux — некоторые шаги могут отличаться"
    fi
}

# ----- Block discovery & loader ---------------------------------------------
find_block_file() {
    local block_file="$1"
    local paths=(
        "$SCRIPT_DIR/$block_file"
        "/usr/local/sbin/$block_file"
        "./$block_file"
    )
    for p in "${paths[@]}"; do
        [[ -f "$p" ]] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

load_block() {
    local block_key="$1"
    local block_file="$2"

    local path
    if ! path=$(find_block_file "$block_file"); then
        error "Файл блока не найден: $block_file"
        return 1
    fi

    info "Загрузка блока: $path"
    # shellcheck source=/dev/null
    if ! source "$path"; then
        error "Ошибка при source $path"
        return 1
    fi

    local func="run_${block_key}"
    if ! declare -f "$func" >/dev/null 2>&1; then
        error "Функция $func не найдена в $path"
        return 1
    fi

    info "Выполнение $func ..."
    if "$func"; then
        success "$block_key завершён"
        return 0
    else
        error "$block_key завершён с ошибкой"
        return 1
    fi
}

# ----- UI helpers -----------------------------------------------------------
show_progress() {
    local current=$1 total=$2 width=40
    local completed=$(( current * width / total ))
    local remaining=$(( width - completed ))
    printf "\r["
    printf "%${completed}s" | tr ' ' '='
    printf "%${remaining}s" | tr ' ' '-'
    printf "] %d/%d\n" "$current" "$total"
}

read_tty() {
    local prompt="$1"
    printf "%s" "$prompt" > /dev/tty
    read -r ans < /dev/tty
    printf '%s' "$ans"
}

# ----- Fixes: grubenv & default.conf ---------------------------------------
check_and_fix_grubenv() {
    info "Доп. проверка и исправление grubenv..."
    local GRUBENV="/boot/grub/grubenv"
    if [[ ! -f "$GRUBENV" ]]; then
        warning "grubenv не найден, создаю минимальный"
        mkdir -p "$(dirname "$GRUBENV")" 2>/dev/null || true
        touch "$GRUBENV" 2>/dev/null || true
        dd if=/dev/zero bs=1 count=1024 of="$GRUBENV" &>/dev/null || true
        chmod 600 "$GRUBENV" 2>/dev/null || true
        success "grubenv создан"
    else
        local size
        size=$(stat -c %s "$GRUBENV" 2>/dev/null || echo 0)
        if [[ "$size" -lt 1024 ]]; then
            warning "grubenv слишком мал ($size), добиваю до 1024"
            dd if=/dev/zero bs=1 count=$((1024 - size)) oflag=append conv=notrunc of="$GRUBENV" &>/dev/null || true
            success "grubenv исправлен"
        else
            success "grubenv в порядке ($size байт)"
        fi
    fi

    local REAR_CONF="/etc/rear/local.conf"
    if [[ -f "$REAR_CONF" ]] && ! grep -q "INCLUDE_FILES.*grubenv" "$REAR_CONF" 2>/dev/null; then
        cp "$REAR_CONF" "${REAR_CONF}.backup.grubenv.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        {
            echo ""
            echo "# ========== GRUBENV FIX =========="
            echo "INCLUDE_FILES+=( \"/boot/grub/grubenv\" )"
            echo "# =================================="
        } >> "$REAR_CONF"
        success "Добавлен INCLUDE_FILES grubenv в $REAR_CONF"
    fi
}

check_and_fix_default_conf() {
    info "Проверка default.conf..."
    local DEFAULT_CONF="/usr/share/rear/conf/default.conf"
    if [[ ! -f "$DEFAULT_CONF" ]]; then
        warning "default.conf не найден — создаю минимальный"
        mkdir -p "$(dirname "$DEFAULT_CONF")" 2>/dev/null || true
        cat > "$DEFAULT_CONF" <<'DEFAULT'
# Minimal default.conf for ReaR (auto-generated)
BACKUP=NETFS
BACKUP_PROG=tar
OUTPUT=ISO
ISO_IS_HYBRID="yes"
MODULES=( 'all_modules' )
MODULES_LOAD=( 'yes' )
LOG_FILE="/var/log/rear/rear-$HOSTNAME.log";
VERBOSE="1"
COPY_AS_IS+=( "/usr/share/rear/conf/default.conf" )
SHARE_DIR="/usr/share/rear"
DEFAULT
        chmod 644 "$DEFAULT_CONF" 2>/dev/null || true
        success "Создан $DEFAULT_CONF"
    else
        local size
        size=$(stat -c %s "$DEFAULT_CONF" 2>/dev/null || echo 0)
        if [[ "$size" -lt 100 ]]; then
            warning "default.conf слишком мал ($size), пересоздаю"
            cp "$DEFAULT_CONF" "${DEFAULT_CONF}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            rm -f "$DEFAULT_CONF" 2>/dev/null || true
            check_and_fix_default_conf
        else
            success "default.conf OK ($size байт)"
            if ! grep -q "COPY_AS_IS.*default.conf" "$DEFAULT_CONF" 2>/dev/null; then
                echo "" >> "$DEFAULT_CONF"
                echo "# Ensure default.conf is included in rescue" >> "$DEFAULT_CONF"
                echo "COPY_AS_IS+=( \"/usr/share/rear/conf/default.conf\" )" >> "$DEFAULT_CONF"
                success "Добавлен COPY_AS_IS для default.conf"
            fi
        fi
    fi

    local REAR_CONF="/etc/rear/local.conf"
    if [[ -f "$REAR_CONF" ]] && ! grep -q "COPY_AS_IS.*default.conf" "$REAR_CONF" 2>/dev/null; then
        cp "$REAR_CONF" "${REAR_CONF}.backup.defaultconf.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        {
            echo ""
            echo "# ========== DEFAULT.CONF FIX =========="
            echo "COPY_AS_IS+=( \"/usr/share/rear/conf/default.conf\" )"
            echo "SHARE_DIR=\"/usr/share/rear\""
            echo "# ====================================="
        } >> "$REAR_CONF"
        success "Добавлен default.conf в $REAR_CONF"
    fi
}

# ----- Create helper scripts in SCRIPT_DIR ----------------------------------
create_check_script() {
    local out="$SCRIPT_DIR/rear-check-before-backup.sh"
    info "Создание скрипта проверки: $out"
    cat > "$out" <<'CHECK'
#!/bin/bash
set -euo pipefail
echo "=== QUICK ReaR PRE-CHECK ==="
# 1. ReaR
if command -v rear >/dev/null 2>&1; then
  echo "ReaR: OK - $(rear --version 2>/dev/null | head -1 || true)"
else
  echo "ReaR: MISSING"; exit 1
fi
# 2. default.conf
DEFAULT="/usr/share/rear/conf/default.conf"
if [[ -f "$DEFAULT" ]]; then
  echo "default.conf present ($(stat -c%s "$DEFAULT")) bytes"
else
  echo "default.conf MISSING"; exit 1
fi
# 3. grubenv
GRUBENV="/boot/grub/grubenv"
if [[ -f "$GRUBENV" ]]; then
  echo "grubenv ok ($(stat -c%s "$GRUBENV")) bytes"
else
  echo "grubenv MISSING"; exit 1
fi
echo "=== QUICK CHECK COMPLETE ==="
CHECK
    chmod +x "$out" 2>/dev/null || true
    success "Скрипт проверки создан: $out"
}

create_prepare_usb_script() {
    local out="$SCRIPT_DIR/prepare-rear-usb.sh"
    info "Создание скрипта подготовки флешки: $out"
    cat > "$out" <<'PREP'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNTPOINT="${MOUNTPOINT:-/mnt/rear-usb}"
SELECTED_DEVICE="${SELECTED_DEVICE:-}"

usage(){ echo "Usage: sudo $0 [--device /dev/sdX]"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) SELECTED_DEVICE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if [[ -z "$SELECTED_DEVICE" ]]; then
  read -rp "Device to prepare (e.g. /dev/sdc): " SELECTED_DEVICE
fi
if [[ ! -b "$SELECTED_DEVICE" ]]; then echo "ERROR: $SELECTED_DEVICE not a block device"; exit 1; fi

echo "Preparing $SELECTED_DEVICE ..."
for p in $(lsblk -ln -o NAME "$SELECTED_DEVICE" 2>/dev/null | tail -n +2); do
  dev="/dev/$p"
  mp=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | grep -v '^$' || true)
  [[ -n "$mp" ]] && (umount "$mp" 2>/dev/null || umount -f "$dev" 2>/dev/null || true)
done

command -v wipefs >/dev/null 2>&1 && wipefs -a "$SELECTED_DEVICE" 2>/dev/null || true
dd if=/dev/zero of="$SELECTED_DEVICE" bs=1M count=10 conv=fsync 2>/dev/null || true
sync

if command -v parted >/dev/null 2>&1; then
  parted -s "$SELECTED_DEVICE" mklabel gpt >/dev/null 2>&1 || true
  parted -s "$SELECTED_DEVICE" mkpart primary 1MiB 100% >/dev/null 2>&1 || true
  partprobe "$SELECTED_DEVICE" 2>/dev/null || true
else
  printf 'g\nn\n\n\n\nw\n' | fdisk "$SELECTED_DEVICE" >/dev/null 2>&1 || true
fi
sleep 1

PART="${SELECTED_DEVICE}1"
[[ ! -b "$PART" && -b "${SELECTED_DEVICE}p1" ]] && PART="${SELECTED_DEVICE}p1"

if command -v mkfs.exfat >/dev/null 2>&1; then
  mkfs.exfat -n "REAR_BACKUP" "$PART"
elif command -v mkexfatfs >/dev/null 2>&1; then
  mkexfatfs -n "REAR_BACKUP" "$PART"
else
  mkfs.vfat -F32 -n "REAR_BACKUP" "$PART"
  echo "NOTE: mkfs.exfat not found; created FAT32 (4GB limit)."
fi

mkdir -p "$MOUNTPOINT"
if mount -L REAR_BACKUP "$MOUNTPOINT" 2>/dev/null || mount "$PART" "$MOUNTPOINT" 2>/dev/null; then
  echo "Mounted at $MOUNTPOINT"
else
  echo "Failed to mount $PART"; exit 1
fi

mkdir -p "$MOUNTPOINT/backups" "$MOUNTPOINT/output"
chmod 755 "$MOUNTPOINT/backups" "$MOUNTPOINT/output" 2>/dev/null || true

if [[ -d "$SCRIPT_DIR" ]]; then
  cp -a "$SCRIPT_DIR/rear-check-before-backup.sh" "$MOUNTPOINT/" 2>/dev/null || true
  cp -a "$SCRIPT_DIR/prepare-rear-usb.sh" "$MOUNTPOINT/" 2>/dev/null || true
  chmod +x "$MOUNTPOINT/rear-check-before-backup.sh" "$MOUNTPOINT/prepare-rear-usb.sh" 2>/dev/null || true
fi

echo "Preparation complete. Mounted at $MOUNTPOINT"
ls -la "$MOUNTPOINT"
exit 0
PREP
    chmod +x "$out" 2>/dev/null || true
    success "Скрипт подготовки создан: $out"
}

# ----- Final report ---------------------------------------------------------
show_final_report() {
    echo
    echo "================================================="
    echo "            ФИНАЛЬНЫЙ ОТЧЁТ НАСТРОЙКИ"
    echo "================================================="
    echo
    echo "ReaR: $(rear --version 2>/dev/null | head -1 || echo 'не найден')"
    echo "Selected device: ${SELECTED_DEVICE:-не задано}"
    echo "Mountpoint: ${MOUNTPOINT:-/mnt/rear-usb}"
    echo
    echo "Созданы вспомогательные скрипты (в каталоге со скриптами):"
    echo "  $SCRIPT_DIR/rear-check-before-backup.sh"
    echo "  $SCRIPT_DIR/prepare-rear-usb.sh"
    echo
}

# ----- Main orchestration ---------------------------------------------------
setup_rear() {
    log "Начало полной настройки ReaR"
    info "Скрипты: $SCRIPT_DIR"
    echo

    # Blocks: block_key:description:block_file
    local blocks=(
        "block1:Базовые настройки и проверки:block1-config.sh"
        "block2:Функции работы с данными:block2-data-functions.sh"
        "block3:Функции установки пакетов:block3-package-functions.sh"
        "block4:Функции работы с USB:block4-usb-functions.sh"
        "block5:Установка ReaR:block5-rear-install.sh"
        "block6:Анализ системы:block6-system-analysis.sh"
        "block7:Выбор USB устройства:block7-usb-selection.sh"
        "block8:Проверки безопасности:block8-safety-checks.sh"
        "block9:Подготовка устройства:block9-device-preparation.sh"
    )

    local total=${#blocks[@]}
    local i=0
    info "ЭТАП 1: Подготовка и выбор устройства (блоки 1-9)"
    echo

    for entry in "${blocks[@]}"; do
        IFS=':' read -r block_key block_desc block_file <<< "$entry"
        ((i++))
        echo "ЗАПУСК $block_key — $block_desc"
        show_progress "$i" "$total"
        echo

        if ! load_block "$block_key" "$block_file"; then
            error "Ошибка в $block_key ($block_file)"
            # if block7 failed, special guidance contained in block or caller
            return 1
        fi

        echo; echo "-------------------------------------------------"; echo
    done

    # Pull SELECTED_DEVICE from persisted file if not set
    if [[ -z "${SELECTED_DEVICE:-}" && -f "$PERSIST" ]]; then
        SELECTED_DEVICE=$(sed -n '1p' "$PERSIST" 2>/dev/null || true)
        export SELECTED_DEVICE
        info "SELECTED_DEVICE загружена из $PERSIST -> $SELECTED_DEVICE"
    fi

    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        error "USB устройство не выбрано. Завершение."
        return 1
    fi

    # Check device existence
    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        error "Устройство $SELECTED_DEVICE не найдено"
        return 1
    fi

    info "Устройство выбрано: $SELECTED_DEVICE"

    # Detect if USB already prepared (by label REAR_BACKUP or structure)
    local is_already_prepared=false
    local rear_mountpoint=""
    if command -v blkid >/dev/null 2>&1; then
        local rear_dev
        rear_dev=$(blkid -L REAR_BACKUP 2>/dev/null || true)
        if [[ -n "$rear_dev" ]]; then
            local base_rear base_sel
            base_rear=$(echo "$rear_dev" | sed 's/[0-9]*$//')
            base_sel=$(echo "$SELECTED_DEVICE" | sed 's/[0-9]*$//')
            if [[ "$base_rear" == "$base_sel" ]]; then
                is_already_prepared=true
                rear_mountpoint=$(mount | awk -v dev="$rear_dev" '$1==dev {print $3; exit}' 2>/dev/null || true)
            fi
        fi
    fi

    if [[ "$is_already_prepared" == false ]]; then
        if mountpoint -q "$MOUNTPOINT" 2>/dev/null; then
            local mounted_dev
            mounted_dev=$(mount | awk -v m="$MOUNTPOINT" '$3==m {print $1; exit}' 2>/dev/null || true)
            local label=""
            [[ -n "$mounted_dev" ]] && label=$(lsblk -no LABEL "$mounted_dev" 2>/dev/null || true)
            [[ "$label" == "REAR_BACKUP" ]] && { is_already_prepared=true; rear_mountpoint="$MOUNTPOINT"; }
        fi
    fi

    echo; echo "================================================="; echo " ВЫБЕРИТЕ ДЕЙСТВИЕ ДЛЯ USB ФЛЕШКИ"; echo "================================================="

    local format_choice=""
    if [[ "$is_already_prepared" == true ]]; then
        echo "✅ НАЙДЕНА ПОДГОТОВЛЕННАЯ ФЛЕШКА REAR: $(basename "$SELECTED_DEVICE")"
        [[ -n "$rear_mountpoint" ]] && echo "Смонтирована в: $rear_mountpoint"
        if [[ "$FORCE_FORMAT" == "1" ]]; then
            info "--force-format: помечаем на форматирование"
            format_choice="2"
        else
            while :; do
                printf "Выберите действие: 1) использовать  2) переформатировать (1/2): " > /dev/tty
                read -r ans < /dev/tty
                case "$ans" in 1) format_choice="1"; break ;; 2) format_choice="2"; break ;; *) printf "Введите 1 или 2\n" > /dev/tty ;; esac
            done
        fi
    else
        while :; do
            printf "Флешка не подготовлена. Выполнить форматирование и подготовку? (ДА/нет): " > /dev/tty
            read -r ans < /dev/tty
            case "$ans" in
                ДА|Да|да|YES|Yes|yes|Y|y) format_choice="2"; break ;;
                НЕТ|Нет|нет|NO|No|no|N|n) echo "Отмена пользователем"; return 1 ;;
                *) printf "Введите ДА или НЕТ\n" > /dev/tty ;;
            esac
        done
    fi

    # Safety additional step if FORCE_FORMAT set but REALLY_FORCE not
    if [[ "${format_choice:-}" == "2" && "$FORCE_FORMAT" == "1" && "$REALLY_FORCE" != "1" ]]; then
        echo; echo "!!! FINAL SAFETY: Введите 'REALLY' чтобы подтвердить wipe флешки !!!"
        final=$(read_tty "Введите 'REALLY' -> ")
        if [[ "$final" != "REALLY" ]]; then
            echo "Подтверждение не получено. Отмена."
            return 1
        fi
        info "Финальное подтверждение получено"
    fi

    # Build remaining blocks list
    local remaining_blocks=()
    if [[ "${format_choice:-}" == "1" ]]; then
        remaining_blocks=(
            "block11:Конфигурация ReaR:block11-rear-config.sh"
            "block12:Скрипты на флешке:block12-flash-scripts.sh"
            "block13:Финальные проверки:block13-final-checks.sh"
        )
    else
        remaining_blocks=(
            "block10:Форматирование:block10-formatting.sh"
            "block11:Конфигурация ReaR:block11-rear-config.sh"
            "block12:Скрипты на флешке:block12-flash-scripts.sh"
            "block13:Финальные проверки:block13-final-checks.sh"
        )
    fi

    info "ЭТАП 2: Форматирование и настройка"
    local total2=${#remaining_blocks[@]}
    local j=0
    for entry in "${remaining_blocks[@]}"; do
        IFS=':' read -r block_key block_desc block_file <<< "$entry"
        ((j++))
        echo "ЗАПУСК $block_key — $block_desc"
        show_progress "$j" "$total2"
        if ! load_block "$block_key" "$block_file"; then
            error "Ошибка в $block_key ($block_file)"
            return 1
        fi
        echo; echo "-------------------------------------------------"; echo
    done

    # Create helper scripts next to main scripts
    create_check_script || warning "Не удалось создать скрипт проверки (non-fatal)"
    create_prepare_usb_script || warning "Не удалось создать скрипт подготовки флешки (non-fatal)"

    return 0
}

# ----- Main -----------------------------------------------------------------
main() {
    echo
    info "Начало полной настройки ReaR"
    info "Скрипты: $SCRIPT_DIR  Options: --force-format=$FORCE_FORMAT --really-force=$REALLY_FORCE"
    echo

    check_root
    check_alt_linux

    printf "Нажмите Enter для продолжения или Ctrl+C для отмены..."
    read -r _ </dev/tty || true
    echo

    check_and_fix_grubenv
    check_and_fix_default_conf

    # Run orchestration
    if setup_rear; then
        success "НАСТРОЙКА ВЫПОЛНЕНА УСПЕШНО!"
        echo
        show_final_report
        # remove persisted selection on success
        [[ -f "$PERSIST" ]] && rm -f "$PERSIST" 2>/dev/null || true
        info "Удалён файл выбора устройства (если был): $PERSIST"
        return 0
    else
        error "НАСТРОЙКА ЗАВЕРШЕНА С ОШИБКОЙ"
        info "Если хотите, сохранённый выбор устройства находится в: $PERSIST (если есть)"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi