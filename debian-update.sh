#!/bin/sh
#
# debian-update.sh - Скрипт для обновления системы семейства Debian
# Этот скрипт выполняет полное обновление системы: обновление списков пакетов,
# обновление установленных пакетов, удаление ненужных пакетов и очистку кэша.
#
# Использование: sudo ./debian-update.sh
#

set -eu  # Выход при ошибке, выход при использовании неопределённой переменной

# Конфигурация
LOG_FILE="/var/log/debian-update.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Цветовые коды для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Без цвета

# Функция логирования
log() {
    echo "[$DATE] $1" | tee -a "$LOG_FILE"
}

# Функция вывода цветного сообщения
print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    log "$message"
}

# Проверка прав root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_msg "$RED" "Ошибка: Этот скрипт должен выполняться от имени root. Используйте sudo."
        exit 1
    fi
}

# Обновление списков пакетов
update_package_lists() {
    print_msg "$BLUE" "Обновление списков пакетов..."
    if apt-get update >> "$LOG_FILE" 2>&1; then
        print_msg "$GREEN" "Списки пакетов успешно обновлены."
    else
        print_msg "$RED" "Не удалось обновить списки пакетов. Проверьте $LOG_FILE для деталей."
        exit 1
    fi
}

# Обновление установленных пакетов
upgrade_packages() {
    print_msg "$BLUE" "Обновление установленных пакетов..."
    if apt-get upgrade -y >> "$LOG_FILE" 2>&1; then
        print_msg "$GREEN" "Пакеты успешно обновлены."
    else
        print_msg "$RED" "Не удалось обновить пакеты. Проверьте $LOG_FILE для деталей."
        exit 1
    fi
}

# Выполнение дистрибутивного обновления (если доступно)
dist_upgrade() {
    print_msg "$BLUE" "Выполнение дистрибутивного обновления..."
    if apt-get dist-upgrade -y >> "$LOG_FILE" 2>&1; then
        print_msg "$GREEN" "Дистрибутивное обновление успешно завершено."
    else
        print_msg "$YELLOW" "Дистрибутивное обновление завершилось с предупреждениями. Проверьте $LOG_FILE для деталей."
    fi
}

# Удаление ненужных пакетов
autoremove_packages() {
    print_msg "$BLUE" "Удаление ненужных пакетов..."
    if apt-get autoremove -y >> "$LOG_FILE" 2>&1; then
        print_msg "$GREEN" "Ненужные пакеты успешно удалены."
    else
        print_msg "$YELLOW" "Не удалось удалить некоторые пакеты. Проверьте $LOG_FILE для деталей."
    fi
}

# Очистка кэша пакетов
clean_cache() {
    print_msg "$BLUE" "Очистка кэша пакетов..."
    if apt-get clean >> "$LOG_FILE" 2>&1; then
        print_msg "$GREEN" "Кэш пакетов успешно очищен."
    else
        print_msg "$YELLOW" "Не удалось очистить кэш. Проверьте $LOG_FILE для деталей."
    fi
}

# Удаление устаревших пакетов (для Debian)
autoclean_packages() {
    print_msg "$BLUE" "Удаление устаревших пакетов..."
    if apt-get autoclean -y >> "$LOG_FILE" 2>&1; then
        print_msg "$GREEN" "Устаревшие пакеты успешно удалены."
    else
        print_msg "$YELLOW" "Не удалось удалить устаревшие пакеты. Проверьте $LOG_FILE для деталей."
    fi
}

# Проверка необходимости перезагрузки
check_reboot() {
    if [ -f /var/run/reboot-required ]; then
        print_msg "$YELLOW" "Требуется перезагрузка для завершения обновления."
        if [ -f /var/run/reboot-required.pkgs ]; then
            print_msg "$YELLOW" "Пакеты, требующие перезагрузки:"
            cat /var/run/reboot-required.pkgs | tee -a "$LOG_FILE"
        fi
    else
        print_msg "$GREEN" "Перезагрузка не требуется."
    fi
}

# Основная функция выполнения
main() {
    print_msg "$GREEN" "========================================"
    print_msg "$GREEN" " Скрипт обновления системы Debian"
    print_msg "$GREEN" " Начато: $DATE"
    print_msg "$GREEN" "========================================"
    
    log "Начато обновление системы"
    
    # Проверка прав root
    check_root
    
    # Обновление списков пакетов
    update_package_lists
    
    # Обновление пакетов
    upgrade_packages
    
    # Дистрибутивное обновление
    dist_upgrade
    
    # Удаление ненужных пакетов
    autoremove_packages
    
    # Очистка кэша
    clean_cache
    
    # Удаление устаревших пакетов
    autoclean_packages
    
    # Проверка необходимости перезагрузки
    check_reboot
    
    END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
    print_msg "$GREEN" "========================================"
    print_msg "$GREEN" " Обновление успешно завершено!"
    print_msg "$GREEN" " Завершено: $END_DATE"
    print_msg "$GREEN" " Файл журнала: $LOG_FILE"
    print_msg "$GREEN" "========================================"
    
    log "Обновление системы завершено"
}

# Запуск основной функции
main "$@"