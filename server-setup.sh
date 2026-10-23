#!/bin/bash
# ============================================================ #
# ==           SERVER SETUP                                == #
# ============================================================ #
# Главный скрипт для первоначальной настройки и администрирования сервера.
# Использует модульную архитектуру с манифестами меню.
# Версия: 2.2.0

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
    printf "  - Logs are saved to %s%s%s\n" "$BOLD" "$LOG_FILE" "$NC"
    printf "  - Backups of modified configs are in %s/root/setup-backup_*%s\n" "$BOLD" "$NC"
    
    printf "\n"
    exit 0
}

show_version() {
    echo "Server Setup Script v2.2.0 (2026-05-03)"
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
            printf "Неизвестный параметр: %s (см. --help)\n" "$1" >&2
            exit 1
            ;;
    esac
done

# --- ПОДКЛЮЧЕНИЕ МОДУЛЕЙ ---
# Каждый модуль объявляет свои пункты меню через @menu.manifest,
# главное меню строится автоматически (render_menu_items "main").
MODULES=(
    "security/system_update.sh"
    "security/mirror_check.sh"
    "security/user_management.sh"
    "security/ssh_hardening.sh"
    "security/firewall.sh"
    "security/intrusion_prevention.sh"
    "system/auto_updates.sh"
    "system/system_hardening.sh"
    "network/network_tools.sh"
    "system/backup.sh"
    "system/resource_management.sh"
    "system/audit_cleanup.sh"
    "core/custom_bashrc.sh"
)

for module in "${MODULES[@]}"; do
    if [[ -f "$SCRIPT_DIR/modules/$module" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/modules/$module"
    else
        printf "Модуль не найден: %s\n" "$SCRIPT_DIR/modules/$module" >&2
    fi
done
unset module

# --- Обработка выбора в главном меню ---
handle_choice() {
    local choice="$1"
    local action
    action=$(get_menu_action "main" "$choice") || return 1
    if ! declare -F "$action" >/dev/null; then
        err "Функция '$action' не найдена."
        return 0
    fi
    "$action"
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
    if ! check_dependencies; then
        exit 1
    fi
    
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
        render_menu_items "main"
        
        printf_menu_option "q" "Выход"
        echo ""
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            info "Выход из скрипта."
            break
        fi
        
        [[ -z "$choice" ]] && continue
        
        if ! handle_choice "$choice"; then
            err "Нет такого пункта." 
        fi
    done
}

# Запуск главной функции
main "$@"
