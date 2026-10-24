#!/bin/bash
# ============================================================ #
# ==                 CORE COMMON FUNCTIONS                  == #
# ============================================================ #
# Этот файл содержит базовые функции для UI, цвета и взаимодействие
# с пользователем.
# Версия: 2.2.0

# --- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ---
# Определяем реальный путь к скрипту (с учетом симлинков)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SCRIPT_DIR

# Конфигурация логирования
LOG_FILE="/var/log/server-setup.log"
REPORT_FILE="/var/log/server-setup_report_$(date +%Y%m%d_%H%M%S).txt"
BACKUP_DIR="/root/setup-backup_$(date +%Y%m%d_%H%M%S)"
VERBOSE=true
# Неинтерактивный режим (--auto): вопросы получают ответ по умолчанию
AUTO_MODE=false

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
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
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
    [[ "$AUTO_MODE" == "true" ]] || sleep 2
}

# --- ФУНКЦИИ ПЕЧАТИ ---
print_header() {
    [[ $VERBOSE == false ]] && return
    printf '\n'
    printf '%s\n' "${CYAN}╔═════════════════════════════════════════════════════════════════╗${NC}"
    printf '%s\n' "${CYAN}║                                                                 ║${NC}"
    printf '%s\n' "${CYAN}║               SERVER SETUP AND HARDENING SCRIPT                 ║${NC}"
    printf '%s\n' "${CYAN}║                       v2.2.0 | 2026-05-03                       ║${NC}"
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
# Читает строку от пользователя. Возвращает код ошибки при EOF (Ctrl+D,
# закрытый stdin), чтобы циклы меню могли корректно завершиться.
safe_read() {
    local prompt="$1"
    local result
    if ! read -rp "$(echo -e "${CYAN}${prompt}${NC}")" result; then
        echo ""
        return 1
    fi
    echo "$result"
}

# ask_yes_no "Вопрос" [y|n] — второй аргумент задает ответ по умолчанию (Enter).
ask_yes_no() {
    local prompt="${1:-Продолжить?}"
    local default="${2:-}"
    local hint="y/n"
    local answer
    case "$default" in
        [Yy]) hint="Y/n" ;;
        [Nn]) hint="y/N" ;;
    esac
    if [[ "$AUTO_MODE" == "true" ]]; then
        log "[auto] ${prompt} -> ${default:-n}"
        [[ "$default" == [Yy] ]]
        return
    fi
    while true; do
        if ! answer=$(safe_read "${prompt} (${hint}): "); then
            # EOF: используем ответ по умолчанию, иначе считаем отказом
            [[ "$default" == [Yy] ]] && return 0
            return 1
        fi
        [[ -z "$answer" ]] && answer="$default"
        case "$answer" in
            # Кириллица перечислена явно: [Дд] не работает в локали C/POSIX
            Y|y|Д|д) return 0 ;;
            N|n|Н|н) return 1 ;;
            *) warn "Пожалуйста, введите y или n." ;;
        esac
    done
}

wait_for_enter() {
    [[ "$AUTO_MODE" == "true" ]] && return 0
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
    # Команда передается строкой (с && и перенаправлениями), поэтому eval
    if eval "$*" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        err "Команда не удалась: $*"
        return 1
    fi
}

# Функция с проверкой ошибок и логированием
execute_command() {
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

# --- СИСТЕМНЫЕ ХЕЛПЕРЫ ---

# Текущий порт SSH из эффективной конфигурации sshd (учитывает drop-in файлы)
get_ssh_port() {
    local port=""
    if command -v sshd >/dev/null 2>&1; then
        port=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}')
    fi
    if [[ -z "$port" && -f /etc/ssh/sshd_config ]]; then
        port=$(awk 'tolower($1) == "port" {print $2; exit}' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null)
    fi
    echo "${port:-22}"
}

# Проверка, слушает ли что-либо TCP-порт
is_port_listening() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -Htln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
        return
    fi
    # Без iproute2: LISTEN-сокеты (состояние 0A) из /proc, порт в hex
    local hex file
    local -a files=()
    hex=$(printf '%04X' "$port")
    for file in /proc/net/tcp /proc/net/tcp6; do
        [[ -r "$file" ]] && files+=("$file")
    done
    (( ${#files[@]} > 0 )) || return 1
    awk -v p=":$hex" '$4 == "0A" && substr($2, length($2) - 4) == p {found = 1} END {exit !found}' "${files[@]}"
}

# Проверка корректности имени пользователя Linux
is_valid_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

# Запрашивает имя существующего пользователя.
# По умолчанию предлагается пользователь, запустивший sudo (SUDO_USER).
# Результат выводится в stdout; код возврата 1 при ошибке.
ask_existing_user() {
    local prompt="${1:-Введите имя пользователя}"
    local default="${SUDO_USER:-}"
    [[ "$default" == "root" ]] && default=""
    local username
    username=$(safe_read "${prompt}${default:+ [$default]}: ") || return 1
    username="${username:-$default}"
    if [[ -z "$username" ]]; then
        err "Имя пользователя не может быть пустым." >&2
        return 1
    fi
    if ! id "$username" &>/dev/null; then
        err "Пользователь '$username' не существует." >&2
        return 1
    fi
    echo "$username"
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
    
    local file line
    while IFS= read -r file; do
        [[ -r "$file" ]] || continue
        
        while IFS= read -r line; do
            # Ищем строки вида: # @item( menu_id | key | label | action | ... )
            if [[ "$line" =~ ^#[[:space:]]*@item\( ]]; then
                # Извлекаем содержимое между скобками @item( и )
                local content
                # Обрезаем по ПОСЛЕДНЕЙ скобке: заголовки могут содержать "(...)"
                content="${line#*@item(}"
                content="${content%)*}"
                
                # Сохраняем в массив: "menu_id|key|label|action"
                if [[ -n "$content" ]]; then
                    _MANIFEST_ITEMS+=("$content")
                fi
            fi
        done < "$file"
    done <<< "$files"
}

# Удаление пробелов по краям строки
_trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

# Рендеринг пунктов меню для указанного menu_id.
# Пункты сортируются по ORDER, между разными GROUP выводится пустая строка.
render_menu_items() {
    local menu_id="$1"
    
    # Парсим манифесты, если еще не сделано
    if [[ ${#_MANIFEST_ITEMS[@]} -eq 0 ]]; then
        _parse_all_manifests
    fi
    
    local item rows=""
    local -a parts
    for item in "${_MANIFEST_ITEMS[@]}"; do
        IFS='|' read -ra parts <<< "$item"
        [[ "$(_trim "${parts[0]}")" == "$menu_id" ]] || continue
        rows+="$(_trim "${parts[4]:-0}")"$'\t'"$(_trim "${parts[5]:-0}")"$'\t'"$(_trim "${parts[1]}")"$'\t'"$(_trim "${parts[2]}")"$'\n'
    done
    [[ -z "$rows" ]] && return 0
    
    local order group key label prev_group=""
    while IFS=$'\t' read -r order group key label; do
        [[ -z "$key" ]] && continue
        if [[ -n "$prev_group" && "$group" != "$prev_group" ]]; then
            echo ""
        fi
        printf_menu_option "$key" "$label"
        prev_group="$group"
    done < <(printf '%s' "$rows" | sort -t $'\t' -k1,1n)
    echo ""
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
    local -a parts
    for item in "${_MANIFEST_ITEMS[@]}"; do
        IFS='|' read -ra parts <<< "$item"
        
        if [[ "$(_trim "${parts[0]}")" == "$menu_id" ]] && [[ "$(_trim "${parts[1]}")" == "$key" ]]; then
            _trim "${parts[3]}"
            echo ""
            return 0
        fi
    done
    return 1
}
