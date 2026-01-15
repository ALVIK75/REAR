#!/bin/bash
#
# БЛОК 4: Функции работы с USB (УПРОЩЕННЫЙ)
#

run_block4() {
    echo "[INFO] Запуск блока 4..."

    get_size_gb() {
        local size_str=$1
        echo "$size_str" | sed 's/,/./g' | awk -F'[.Gg]' '{print int($1)}'
    }

    normalize_size() {
        echo "$1" | sed 's/,/./g'
    }

    echo "[INFO] Функции работы с USB загружены"
    echo "[SUCCESS] Блок 4 завершен: базовые функции работы с USB"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_block4
fi