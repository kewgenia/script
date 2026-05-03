#!/bin/bash
# ============================================================ #
# ==           SERVER SETUP                                == #
# ============================================================ #
# Главный скрипт для первоначальной настройки и администрирования сервера.
# Использует модульную архитектуру с манифестами меню.
# Версия: 2.1.0

set -uo pipefail

# --- Подключение ядра ---
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
export SCRIPT_DIR

source "$SCRIPT_DIR/modules/core/common.sh"
source "$SCRIPT_DIR/modules/core/environment.sh"

# --- ПАРСИНГ АРГУМЕНТОВ ---
QUIET_MODE=false
AUTO_MODE=false

show_usage() {
    printf "\n"
    printf "%s%s%s\n" "$CYAN" "Server Setup & Hardening Script" "$NC"
    
    printf "\n%sUsage:%s\n" "$BOLD" "$NC"
    printf "  sudo -E %s [OPTIONS]\n" "$(basename "$0")"
    
    printf "\n%sDescription:%s\n" "$BOLD" "$NC"
    printf "  This script provisions a fresh Debian or Ubuntu server with secure base configurations.\n"
    printf "  It handles updates, firewall, SSH hardening, user creation, and optional tools.\n"
    
    printf "\n%sOptions:%s\n" "$BOLD" "$NC"
    printf "  %-22s %s\n" "--quiet" "Suppress non-critical output (for automation)."
    printf "  %-22s %s\n" "--auto" "Run automated setup (non-interactive mode)."
    printf "  %-22s %s\n" "-h, --help" "Display this help message and exit."
    printf "  %-22s %s\n" "--version" "Show script version."
    
    printf "\n%sExamples:%s\n" "$BOLD" "$NC"
    printf "  # Run interactive setup\n"
    printf "  %ssudo -E ./%s%s\n\n" "$YELLOW" "$(basename "$0")" "$NC"
    printf "  # Run in quiet mode\n"
    printf "  %ssudo -E ./%s --quiet%s\n\n" "$YELLOW" "$(basename "$0")" "$NC"
    
    printf "\n%sImportant Notes:%s\n" "$BOLD" "$NC"
    printf "  - The -E flag preserves your environment variables (recommended)\n"
    printf "  - Logs are saved to %s/var/log/server-setup_*.log%s\n" "$BOLD" "$NC"
    printf "  - Backups of modified configs are in %s/root/setup_backup_*%s\n" "$BOLD" "$NC"
    
    printf "\n"
    exit 0
}

show_version() {
    echo "Server Setup Script v2.1.0 (2026-05-03)"
    exit 0
}

# Парсинг аргументов командной строки
while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet)
            QUIET_MODE=true
            VERBOSE=false
            shift
            ;;
        --auto)
            AUTO_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        --version)
            show_version
            ;;
        *)
            shift
            ;;
    esac
done

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

# --- Рендеринг меню ---
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

# --- Обработка выбора ---
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

# --- АВТОМАТИЧЕСКИЙ РЕЖИМ (заглушка для будущей реализации) ---
run_automated_setup() {
    print_section "Автоматическая настройка сервера"
    info "Этот режим находится в разработке."
    info "Пока что используйте интерактивное меню."
    wait_for_enter
}

# --- ГЛАВНОЕ МЕНЮ ---
main() {
    # Устанавливаем обработчики ошибок и выхода
    trap 'handle_error $LINENO' ERR
    trap 'cleanup_temp_files' EXIT
    
    # Проверка прав root
    check_root
    
    # Создаем файл лога
    touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
    log "Запуск скрипта Server Setup."
    
    # Проверка зависимостей
    check_dependencies
    
    # Вывод заголовка
    print_header
    
    # Если тихий режим, пропускаем меню
    if [[ "$QUIET_MODE" == "true" ]]; then
        info "Тихий режим включен. Вывод подавлен."
        # В будущем здесь будет автоматическая настройка
        return 0
    fi
    
    # Если автоматический режим
    if [[ "$AUTO_MODE" == "true" ]]; then
        run_automated_setup
        return 0
    fi
    
    # Интерактивное меню
    while true; do
        menu_header "🛡️ Server Setup"
        printf_description "Первоначальная настройка, установка ПО и администрирование сервера."
        
        echo -e "${BOLD}Основные шаги:${NC}"
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

# Запуск главной функции
main "$@"
