#!/usr/bin/env bash
set -euo pipefail

INTERVAL=5
LOG_FILE="monitor.log"

fail() {
    printf 'Ошибка: %s\n' "$1" >&2
    exit 1
}

if [[ ! "$INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    fail "INTERVAL должен быть целым положительным числом."
fi

for cmd in date free df uptime sleep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Не найдена необходимая команда: $cmd"
    fi
done

if ! { : >> "$LOG_FILE"; } 2>/dev/null; then
    fail "Не удалось открыть $LOG_FILE для записи."
fi

stop() {
    printf '\nМониторинг остановлен.\n'
    exit 0
}

trap stop INT TERM

printf 'Мониторинг запущен: интервал %s секунд, файл %s. Остановка: Ctrl+C.\n' \
    "$INTERVAL" "$LOG_FILE"

while true; do
    {
        printf -- '--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Память (free -h):\n'
        free -h
        printf '\nФайловые системы (df -h):\n'
        df -h
        printf '\nВремя работы и нагрузка (uptime):\n'
        uptime
        printf '\n'
    } >> "$LOG_FILE"

    sleep "$INTERVAL"
done
