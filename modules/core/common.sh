#!/bin/bash
# ============================================================ #
# ==                 CORE COMMON FUNCTIONS                  == #
# ============================================================ #
# Этот файл содержит базовые функции для UI, цвета и взаимодействие
# с пользователем.

# --- Цвета ---
export C_RED='\033[0;31m'
export C_GREEN='\033[0;32m'
export C_YELLOW='\033[1;33m'
export C_BLUE='\033[0;34m'
export C_CYAN='\033[0;36m'
export C_GRAY='\033[0;90m'
export C_BOLD='\033[1m'
export C_RESET='\033[0m'

# --- Логирование ---
LOG_FILE="/var/log/server-setup.log"
debug_log() { echo -e "${C_GRAY}[DEBUG] $1${C_RESET}"; }
info()    { echo -e "${C_BLUE}[INFO] $1${C_RESET}"; }
ok()      { echo -e "${C_GREEN}[OK] $1${C_RESET}"; }
warn()    { echo -e "${C_YELLOW}[WARN] $1${C_RESET}"; }
err()     { echo -e "${C_RED}[ERROR] $1${C_RESET}"; sleep 2; }

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
}

# --- Ввод/Вывод ---
safe_read() {
    local prompt="$1"
    local result
    read -rp "$(echo -e "${C_CYAN}${prompt}${C_RESET}")" result
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

# --- UI Хелперы ---
menu_header() {
    clear
    echo -e "${C_BOLD}${C_BLUE}============================================${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}  $1${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}============================================${C_RESET}"
    echo ""
}

printf_description() {
    echo -e "${C_GRAY}  $1${C_RESET}"
    echo ""
}

printf_menu_option() {
    local key="$1"
    local text="$2"
    echo -e "  ${C_GREEN}${key})${C_RESET} ${text}"
}

# --- Защита от Ctrl+C ---
enable_graceful_ctrlc() {
    trap 'echo -e "\n${C_YELLOW}Выход...${C_RESET}"; exit 130' INT
}

disable_graceful_ctrlc() {
    trap - INT
}

# --- Выполнение команды ---
run_cmd() {
    log "Выполнение: $*"
    if eval "$@" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        err "Команда не удалась: $*"
        return 1
    fi
}

# --- Проверка прав ---
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        err "Этот скрипт должен выполняться от имени root. Используйте sudo."
        exit 1
    fi
}

# --- Парсер манифестов меню (@menu.manifest) ---
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
