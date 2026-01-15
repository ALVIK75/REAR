#!/bin/bash
# =============================================================================
# БЛОК 13: Финальные проверки (подробный вывод)
# Этот вариант выводит детализированный результат каждой проверки и суммарный отчет.
# =============================================================================

# Не выходим при ошибке — нужно собрать результаты всех проверок
# set -e  # intentionally not set

# Функции проверок (оставлены прежние, без перенаправления вывода)
check_rear() {
    if command -v rear >/dev/null 2>&1; then
        echo "[OK] ReaR найден: $(rear --version 2>/dev/null | head -1 || true)"
        return 0
    else
        echo "[ERROR] ReaR не установлен"
        return 1
    fi
}

check_config() {
    if [[ -f "/etc/rear/local.conf" ]]; then
        local errors=0
        local msgs=()

        if ! grep -q "BACKUP=NETFS" /etc/rear/local.conf; then
            ((errors++))
            msgs+=("missing BACKUP=NETFS")
        fi

        if ! grep -q "INCLUDE_FILES.*grubenv" /etc/rear/local.conf; then
            ((errors++))
            msgs+=("grubenv not included (INCLUDE_FILES)")
        fi

        if ! grep -q "20_mount_rear_usb.sh" /etc/rear/local.conf; then
            ((errors++))
            msgs+=("automount script 20_mount_rear_usb.sh not included (COPY_AS_IS)")
        fi

        if [[ $errors -eq 0 ]]; then
            echo "[OK] /etc/rear/local.conf: ключевые параметры присутствуют"
            return 0
        else
            echo "[WARNING] /etc/rear/local.conf: найдено $errors проблемы"
            for m in "${msgs[@]}"; do echo "  - $m"; done
            return 1
        fi
    else
        echo "[ERROR] /etc/rear/local.conf отсутствует"
        return 1
    fi
}

check_usb() {
    if [[ -n "$SELECTED_DEVICE" && -b "$SELECTED_DEVICE" ]]; then
        local mp="${MOUNTPOINT:-/mnt/rear-usb}"
        if mountpoint -q "$mp"; then
            echo "[OK] Флешка смонтирована в $mp"
            return 0
        else
            echo "[ERROR] Флешка $SELECTED_DEVICE не смонтирована (ожидается $mp)"
            return 1
        fi
    else
        echo "[ERROR] SELECTED_DEVICE не задано или не является блочным устройством"
        return 1
    fi
}

check_grubenv() {
    local grub="/boot/grub/grubenv"
    if [[ -f "$grub" ]]; then
        local size
        size=$(stat -c %s "$grub" 2>/dev/null || echo 0)
        if [[ $size -ge 1024 ]]; then
            echo "[OK] grubenv существует ($size bytes)"
            return 0
        else
            echo "[WARNING] grubenv слишком мал (${size} bytes) — рекомендовано >=1024"
            return 1
        fi
    else
        echo "[ERROR] grubenv не существует: $grub"
        return 1
    fi
}

check_automount_script() {
    local script="/usr/share/rear/rescue/GNU/Linux/20_mount_rear_usb.sh"
    if [[ -f "$script" ]]; then
        if [[ ! -x "$script" ]]; then
            chmod +x "$script" 2>/dev/null || true
            echo "[INFO] Сделан исполняемым: $script"
        fi
        echo "[OK] Скрипт автомонтирования найден: $script"
        return 0
    else
        echo "[ERROR] Скрипт автомонтирования не найден: $script"
        return 1
    fi
}

check_check_script() {
    local check_script="/usr/local/sbin/rear-check-before-backup.sh"
    if [[ -f "$check_script" ]]; then
        if [[ ! -x "$check_script" ]]; then
            chmod +x "$check_script" 2>/dev/null || true
        fi
        if bash -n "$check_script" 2>/dev/null; then
            echo "[OK] Скрипт проверки синтаксически корректен: $check_script"
            return 0
        else
            echo "[WARNING] Синтаксические ошибки в скрипте проверки: $check_script"
            # не критично, считаем предупреждением (как в оригинальном блоке)
            return 0
        fi
    else
        echo "[INFO] Скрипт проверки отсутствует и будет создан основным скриптом"
        return 0
    fi
}

# Helper — выполнение отдельной проверки с накоплением вывода и статуса
run_check() {
    local name="$1"
    shift
    local cmd=( "$@" )

    # Временный файл для вывода
    local out
    out=$(mktemp) || out="/tmp/block13-out.$$"
    # запускаем команду, собирая вывод
    "${cmd[@]}" >"$out" 2>&1
    local rc=$?

    # Печатаем заголовок и содержимое
    printf "\n--- %s ---\n" "$name"
    sed 's/^/    /' "$out" || true

    rm -f "$out" 2>/dev/null || true

    return $rc
}

# Основная функция блока 13 — детализированный вывод
run_block13() {
    echo "=== ФИНАЛЬНЫЕ ПРОВЕРКИ (подробно) ==="

    local total_checks=6
    local passed_checks=0
    local critical_failed=0

    # Перечень проверок: имя + функция
    declare -a checks=(
        "ReaR установлен:check_rear"
        "Конфигурация /etc/rear/local.conf:check_config"
        "USB (монтирование и устройство):check_usb"
        "grubenv (наличие и размер):check_grubenv"
        "Скрипт автомонтирования:check_automount_script"
        "Скрипт проверки перед бэкапом:check_check_script"
    )

    for entry in "${checks[@]}"; do
        # split
        local label="${entry%%:*}"
        local func="${entry#*:}"

        # run and capture
        run_check "$label" "$func"
        local rc=$?

        if [ $rc -eq 0 ]; then
            ((passed_checks++))
        else
            # treat some checks as critical (errors) and others as warnings
            case "$func" in
                check_rear|check_usb|check_grubenv|check_automount_script)
                    ((critical_failed++))
                    ;;
                check_config|check_check_script)
                    # config and check_script treated as warnings in original logic
                    ;;
            esac
        fi
    done

    echo
    echo "=== ИТОГИ ==="
    echo "Пройдено: $passed_checks из $total_checks"
    if [ $critical_failed -gt 0 ]; then
        echo "[ERROR] Критические проверки не пройдены: $critical_failed"
    elif [ $passed_checks -eq $total_checks ]; then
        echo "[OK] Все проверки пройдены"
    elif [ $passed_checks -ge 4 ]; then
        echo "[WARNING] Некоторые проверки не пройдены — см. вывод выше"
    else
        echo "[ERROR] Слишком много ошибок — необходимо исправить"
    fi

    # Решение о возврате кода: сохранить совместимость с оригинальным поведением
    if [ $critical_failed -gt 0 ]; then
        return 1
    elif [ $passed_checks -eq $total_checks ]; then
        return 0
    elif [ $passed_checks -ge 4 ]; then
        # предупреждения, но разрешаем продолжать (как в оригинале)
        return 0
    else
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block13
fi