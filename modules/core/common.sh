#!/bin/bash
# ============================================================ #
# ==                 CORE COMMON FUNCTIONS                  == #
# ============================================================ #
# Этот файл содержит базовые функции для UI, цвета и взаимодействие
# с пользователем.
# Версия: 2.1.0

# --- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ---
# Определяем реальный путь к скрипту (с учетом симлинков)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SCRIPT_DIR

# Конфигурация логирования
LOG_FILE="/var/log/server-setup.log"
REPORT_FILE="/var/log/server-setup_report_$(date +%Y%m%d_%H%M%S).txt"
BACKUP_DIR="/root/setup-backup_$(date +%Y%m%d_%H%M%S)"
VERBOSE=true

# Глобальные переменные для отслеживания состояния
FAILED_SERVICES=()
DETECTED_VIRT_TYPE=""
DETECTED_MANUFACTURER=""
DETECTED_PRODUCT=""
ENVIRONMENT_TYPE="unknown"
DETECTED_PROVIDER_NAME=""

# --- ЦВЕТА И ВЫВОД ---
if command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW="$(tput bold)$(tput setaf 3)"
    BLUE=$(tput setaf 4)
    PURPLE=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED=$'\e[0;31m'
    GREEN=$'\e[0;32m'
    YELLOW=$'\e[1;33m'
    BLUE=$'\e[0;34m'
    PURPLE=$'\e[0;35m'
    CYAN=$'\e[0;36m'
    NC=$'\e[0m'
    BOLD=$'\e[1m'
fi

# Для обратной совместимости (старые модули)
export C_RED="$RED"
export C_GREEN="$GREEN"
export C_YELLOW="$YELLOW"
export C_BLUE="$BLUE"
export C_CYAN="$CYAN"
export C_GRAY=$'\033[0;90m'
export C_BOLD="$BOLD"
export C_RESET="$NC"

# --- ЛОГИРОВАНИЕ ---
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
}

debug_log() {
    [[ $VERBOSE == false ]] && return
    echo -e "${C_GRAY}[DEBUG] $1${C_RESET}" | tee -a "$LOG_FILE"
}

info() {
    [[ $VERBOSE == false ]] && return
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

ok() {
    [[ $VERBOSE == false ]] && return
    echo -e "${GREEN}[OK] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    [[ $VERBOSE == false ]] && return
    echo -e "${YELLOW}[WARN] $1${NC}" | tee -a "$LOG_FILE"
}

err() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    sleep 2
}

# --- ФУНКЦИИ ПЕЧАТИ ---
print_header() {
    [[ $VERBOSE == false ]] && return
    printf '\n'
    printf '%s\n' "${CYAN}╔═════════════════════════════════════════════════════════════════╗${NC}"
    printf '%s\n' "${CYAN}║                                                                 ║${NC}"
    printf '%s\n' "${CYAN}║       SERVER SETUP AND HARDENING SCRIPT                       ║${NC}"
    printf '%s\n' "${CYAN}║                      v2.1.0 | 2026-05-03                       ║${NC}"
    printf '%s\n' "${CYAN}║                                                                 ║${NC}"
    printf '%s\n' "${CYAN}╚═════════════════════════════════════════════════════════════════╝${NC}"
    printf '\n'
}

print_section() {
    [[ $VERBOSE == false ]] && return
    printf '\n%s\n' "${BLUE}▓▓▓ $1 ▓▓▓${NC}" | tee -a "$LOG_FILE"
    printf '%s\n' "${BLUE}$(printf '═%.0s' {1..65})${NC}"
}

print_success() {
    [[ $VERBOSE == false ]] && return
    printf '%s\n' "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

print_error() {
    printf '%s\n' "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
}

print_warning() {
    [[ $VERBOSE == false ]] && return
    printf '%s\n' "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

print_info() {
    [[ $VERBOSE == false ]] && return
    printf '%s\n' "${PURPLE}ℹ $1${NC}" | tee -a "$LOG_FILE"
}

print_separator() {
    local header_text="$1"
    local color="${2:-$YELLOW}"
    local separator_char="${3:-=}"
    
    printf '%s\n' "${color}${header_text}${NC}"
    printf "${separator_char}%.0s" $(seq 1 ${#header_text})
    printf '\n'
}

# --- ВВОД/ВЫВОД ---
safe_read() {
    local prompt="$1"
    local result
    read -rp "$(echo -e "${CYAN}${prompt}${NC}")" result
    echo "$result"
}

ask_yes_no() {
    local prompt="${1:-Продолжить?}"
    local answer
    while true; do
        answer=$(safe_read "${prompt} (y/n): ")
        case "$answer" in
            [Yy]|[Дд]) return 0 ;;
            [Nn]|[Нн]) return 1 ;;
            *) warn "Пожалуйста, введите y или n." ;;
        esac
    done
}

wait_for_enter() {
    echo -e "${C_GRAY}Нажмите Enter для продолжения...${C_RESET}"
    read -r
}

# --- UI ХЕЛПЕРЫ ---
menu_header() {
    clear
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo ""
}

printf_description() {
    echo -e "${C_GRAY}  $1${NC}"
    echo ""
}

printf_menu_option() {
    local key="$1"
    local text="$2"
    echo -e "  ${GREEN}${key})${NC} ${text}"
}

# --- ЗАЩИТА ОТ Ctrl+C ---
enable_graceful_ctrlc() {
    trap 'echo -e "\n${YELLOW}Выход...${NC}"; exit 130' INT
}

disable_graceful_ctrlc() {
    trap - INT
}

# --- ОБРАБОТКА ОШИБОК ---
handle_error() {
    local exit_code=$?
    local line_no="$1"
    print_error "Произошла ошибка на строке $line_no (код выхода: $exit_code)."
    print_info "Файл лога: $LOG_FILE"
    print_info "Резервные копии: $BACKUP_DIR"
    exit $exit_code
}

cleanup_temp_files() {
    # Очистка временных файлов при выходе
    rm -f /tmp/server-setup_*.tmp 2>/dev/null || true
}

# --- ВЫПОЛНЕНИЕ КОМАНД ---
run_cmd() {
    log "Выполнение: $*"
    if eval "$@" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        err "Команда не удалась: $*"
        return 1
    fi
}

# Функция с проверкой ошибок и логированием
execute_command() {
    local cmd_string="$*"
    
    if [[ "$VERBOSE" == "false" ]]; then
        "$@" >> "$LOG_FILE" 2>&1
        return $?
    else
        "$@" 2>&1 | tee -a "$LOG_FILE"
        return ${PIPESTATUS[0]}
    fi
}

# --- ПРОВЕРКА ПРАВ ---
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        err "Этот скрипт должен выполняться от имени root. Используйте sudo."
        echo -e "${YELLOW}Запустите скрипт следующей командой:${NC}"
        echo -e "${CYAN}  sudo -E ./server-setup.sh${NC}"
        exit 1
    fi
}

# --- ПРОВЕРКА ЗАВИСИМОСТЕЙ ---
check_dependencies() {
    print_section "Проверка зависимостей"
    
    local deps=(apt-get systemctl)
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Отсутствуют необходимые утилиты: ${missing[*]}"
        return 1
    fi
    
    print_success "Все необходимые зависимости установлены."
    return 0
}

# --- ПАРСЕР МАНИФЕСТОВ МЕНЮ ---
# Глобальные переменные для кэширования манифестов
declare -a _MANIFEST_ITEMS=()

# Парсинг всех манифестов в модулях
_parse_all_manifests() {
    _MANIFEST_ITEMS=()
    local module_dir="$SCRIPT_DIR/modules"
    
    if [[ ! -d "$module_dir" ]]; then
        return
    fi
    
    # Находим все .sh файлы
    local files
    files=$(find "$module_dir" -name "*.sh" -type f 2>/dev/null) || return
    
    local file
    while IFS= read -r file; do
        [[ -r "$file" ]] || continue
        
        while IFS= read -r line; do
            # Ищем строки вида: # @item( menu_id | key | label | action | ... )
            if [[ "$line" == *"@item("* ]]; then
                # Извлекаем содержимое между скобками @item( и )
                local content
                content=$(echo "$line" | sed 's/.*@item(//' | sed 's/).*//')
                
                # Сохраняем в массив: "menu_id|key|label|action"
                if [[ -n "$content" ]]; then
                    _MANIFEST_ITEMS+=("$content")
                fi
            fi
        done < "$file"
    done <<< "$files"
}

# Рендеринг пунктов меню для указанного menu_id
render_menu_items() {
    local menu_id="$1"
    
    # Парсим манифесты, если еще не сделано
    if [[ ${#_MANIFEST_ITEMS[@]} -eq 0 ]]; then
        _parse_all_manifests
    fi
    
    # Выводим пункты для указанного menu_id
    local item
    for item in "${_MANIFEST_ITEMS[@]}"; do
        IFS='|' read -ra parts <<< "$item"
        
        local item_menu_id=$(echo "${parts[0]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        local item_key=$(echo "${parts[1]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        local item_label=$(echo "${parts[2]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        
        if [[ "$item_menu_id" == "$menu_id" ]]; then
            printf_menu_option "$item_key" "$item_label"
        fi
    done
}

# Получение действия для указанного menu_id и ключа выбора
get_menu_action() {
    local menu_id="$1"
    local key="$2"
    
    # Парсим манифесты, если еще не сделано
    if [[ ${#_MANIFEST_ITEMS[@]} -eq 0 ]]; then
        _parse_all_manifests
    fi
    
    local item
    for item in "${_MANIFEST_ITEMS[@]}"; do
        IFS='|' read -ra parts <<< "$item"
        
        local item_menu_id=$(echo "${parts[0]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        local item_key=$(echo "${parts[1]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        local item_action=$(echo "${parts[3]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        
        if [[ "$item_menu_id" == "$menu_id" ]] && [[ "$item_key" == "$key" ]]; then
            echo "$item_action"
            return 0
        fi
    done
    return 1
}
