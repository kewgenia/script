#!/bin/bash
# ============================================================ #
# ==           SERVER SETUP                                == #
# ============================================================ #
# Главный скрипт для первоначальной настройки и администрирования сервера.
# Использует модульную архитектуру с манифестами меню.
# Версия: 1.0.0

set -euo pipefail

# --- Конфигурация ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR
LOG_FILE="/var/log/server-setup.log"
export LOG_FILE

# --- Подключение ядра ---
source "$SCRIPT_DIR/modules/core/common.sh"

# --- Генератор меню (Заглушка, пока не реализован парсер манифестов) ---
# В полной версии здесь должен быть source "$SCRIPT_DIR/modules/core/menu_generator.sh"
# Пока реализуем простой роутинг вручную для работоспособности.

# Подключаем модули
source "$SCRIPT_DIR/modules/security/system_update.sh"
source "$SCRIPT_DIR/modules/security/mirror_check.sh"

# Заглушки для будущих модулей (пункты 2-8 из документации)
_placeholder_action() {
    local name="$1"
    warn "Модуль '$name' находится в разработке."
    info "Этот пункт меню будет реализован позднее."
    wait_for_enter
}

# Функции-заглушки для пунктов меню
create_user() { _placeholder_action "Создание пользователя"; }
setup_ssh_keys() { _placeholder_action "Настройка SSH-ключей"; }
setup_firewall() { _placeholder_action "Настройка фаервола"; }
setup_fail2ban() { _placeholder_action "Установка Fail2ban"; }
disable_services() { _placeholder_action "Отключение служб"; }
auto_updates() { _placeholder_action "Автообновления"; }
extra_security() { _placeholder_action "Доп. меры защиты"; }

# --- Рендеринг меню (Упрощенный аналог render_menu_items) ---
# В будущем заменится на автоматическую генерацию из манифестов
show_main_menu_items() {
    printf_menu_option "1" "Обновление системы (apt update/upgrade)"
    printf_menu_option "2" "Создание пользователя с ограниченными правами"
    printf_menu_option "3" "Настройка SSH-ключей и безопасности SSH"
    printf_menu_option "4" "Настройка фаервола (UFW/Firewalld)"
    printf_menu_option "5" "Установка и настройка Fail2ban"
    printf_menu_option "6" "Отключение ненужных служб"
    printf_menu_option "7" "Настройка автоматических обновлений"
    printf_menu_option "8" "Дополнительные меры защиты"
    echo ""
    printf_menu_option "m" "🌐 Зеркала APT (Управление репозиториями)"
    echo ""
}

# --- Обработка выбора (Упрощенный аналог get_menu_action) ---
handle_choice() {
    local choice="$1"
    case "$choice" in
        1) show_system_update_menu ;;
        2) create_user ;;
        3) setup_ssh_keys ;;
        4) setup_firewall ;;
        5) setup_fail2ban ;;
        6) disable_services ;;
        7) auto_updates ;;
        8) extra_security ;;
        m|M) show_mirror_check_menu ;;
        *) return 1 ;;
    esac
    return 0
}

# --- ГЛАВНОЕ МЕНЮ ---
main() {
    check_root
    
    while true; do
        menu_header "🛡️ Server Setup"
        printf_description "Первоначальная настройка, установка ПО и администрирование сервера."
        
        echo -e "${C_BOLD}Основные шаги:${C_RESET}"
        show_main_menu_items
        
        printf_menu_option "q" "Выход"
        echo ""
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            info "Выход из скрипта."
            break
        fi
        
        if ! handle_choice "$choice"; then
            err "Нет такого пункта." 
        fi
    done
}

main "$@"
