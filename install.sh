#!/bin/bash
# ============================================================ #
# ==           СКРИПТ УСТАНОВКИ SERVER SETUP              == #
# ============================================================ #
# Этот скрипт устанавливает Server Setup в систему.
# Поддерживает как локальную установку, так и удаленную через curl.
# Удаленная установка: bash <(curl -Ls https://raw.githubusercontent.com/kewgenia/script/main/install.sh)

set -euo pipefail

# Конфигурация репозитория
REPO_URL="https://github.com/kewgenia/script"
RAW_BASE_URL="https://raw.githubusercontent.com/kewgenia/script/main"
ARCHIVE_URL="https://github.com/kewgenia/script/archive/refs/heads/main.tar.gz"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Функция для проверки наличия необходимых утилит
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Функция для скачивания файла
download_file() {
    local url="$1"
    local output="$2"
    
    if check_dependency "curl"; then
        curl -fsSL "$url" -o "$output"
    elif check_dependency "wget"; then
        wget -q "$url" -O "$output"
    else
        print_msg "$RED" "Ошибка: Не найдены curl или wget для скачивания файлов"
        return 1
    fi
}

# Определяем, запущен ли скрипт удаленно (через curl | bash)
# Проверяем несколько условий:
# 1. Скрипт запущен из stdin (pipe)
# 2. Директория скрипта не содержит ожидаемую структуру (нет server-setup.sh)
is_remote_install() {
    local script_dir="$1"
    
    # Проверка на pipe (stdin не терминал)
    if [[ ! -t 0 ]]; then
        return 0
    fi
    
    # Проверка на отсутствие файлов проекта в директории скрипта
    if [[ ! -f "$script_dir/server-setup.sh" ]] || [[ ! -d "$script_dir/modules" ]]; then
        return 0
    fi
    
    return 1
}

# Основная логика удаленной установки
remote_install() {
    print_msg "$BLUE" "============================================"
    print_msg "$BLUE" "  Удаленная установка Server Setup"
    print_msg "$BLUE" "  Репозиторий: $REPO_URL"
    print_msg "$BLUE" "============================================"
    echo ""
    
    # Проверка прав root
    if [[ "$(id -u)" -ne 0 ]]; then
        print_msg "$RED" "Ошибка: Скрипт должен запускаться от root (используйте sudo)"
        exit 1
    fi
    
    # Создаем временную директорию
    local temp_dir
    temp_dir=$(mktemp -d)
    print_msg "$YELLOW" "Создана временная директория: $temp_dir"
    
    # Скачиваем архив репозитория
    print_msg "$YELLOW" "Скачивание репозитория..."
    local archive_path="$temp_dir/repo.tar.gz"
    
    if ! download_file "$ARCHIVE_URL" "$archive_path"; then
        print_msg "$RED" "Ошибка: Не удалось скачать репозиторий"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Распаковываем архив
    print_msg "$YELLOW" "Распаковка репозитория..."
    if ! tar -xzf "$archive_path" -C "$temp_dir"; then
        print_msg "$RED" "Ошибка: Не удалось распаковать архив"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Находим распакованную директорию (обычно script-main или script-branch)
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "script-*" | head -n 1)
    
    if [[ -z "$extracted_dir" ]]; then
        print_msg "$RED" "Ошибка: Не удалось найти распакованную директорию"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    print_msg "$GREEN" "Репозиторий успешно скачан и распакован"
    
    # Запускаем локальную установку из распакованной директории
    print_msg "$YELLOW" "Запуск локальной установки..."
    cd "$extracted_dir"
    bash install.sh --local-install
    
    # Очистка
    print_msg "$YELLOW" "Очистка временных файлов..."
    rm -rf "$temp_dir"
    
    exit 0
}

# Определяем директорию, где находится скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Проверяем, не является ли это вызовом из удаленной установки с флагом --local-install
if [[ "${1:-}" == "--local-install" ]]; then
    shift
    print_msg "$CYAN" "(Локальная установка из скачанного репозитория)"
else
    # Проверяем, запущен ли скрипт удаленно
    if is_remote_install "$SCRIPT_DIR"; then
        remote_install
    fi
fi

# =================== ЛОКАЛЬНАЯ УСТАНОВКА ===================

# Проверка прав root
if [[ "$(id -u)" -ne 0 ]]; then
    print_msg "$RED" "Ошибка: Скрипт должен запускаться от root (sudo ./install.sh)"
    exit 1
fi

INSTALL_DIR="/opt/server-setup"
LINK_PATH="/usr/local/bin/server-setup"

print_msg "$BLUE" "============================================"
print_msg "$BLUE" "  Установка Server Setup"
print_msg "$BLUE" "============================================"
echo ""

# 1. Создание директории
print_msg "$YELLOW" "1. Создание директории установки: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 2. Копирование файлов
print_msg "$YELLOW" "2. Копирование файлов..."

# Проверяем, не запущен ли скрипт уже из директории установки
if [[ "$SCRIPT_DIR" == "$INSTALL_DIR" ]]; then
    print_msg "$YELLOW" "Скрипт уже находится в директории установки. Пропускаем копирование."
else
    # Очищаем директорию установки перед копированием
    rm -rf "$INSTALL_DIR"/*
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
fi

# 3. Установка прав на исполнение
print_msg "$YELLOW" "3. Установка прав на исполнение..."
chmod +x "$INSTALL_DIR/server-setup.sh"
chmod +x "$INSTALL_DIR/install.sh"
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;

# 4. Создание симлинка
print_msg "$YELLOW" "4. Создание симлинка: $LINK_PATH"
# Удаляем старый симлинк или файл, если существует
if [[ -e "$LINK_PATH" ]]; then
    rm -f "$LINK_PATH"
fi
ln -s "$INSTALL_DIR/server-setup.sh" "$LINK_PATH"

# Проверяем, что симлинк создан и доступен в PATH
if [[ -L "$LINK_PATH" ]]; then
    print_msg "$GREEN" "Симлинк успешно создан: $LINK_PATH"
else
    print_msg "$RED" "Ошибка: Не удалось создать симлинк"
    exit 1
fi

# 5. Проверка зависимостей
print_msg "$YELLOW" "5. Проверка зависимостей..."
MISSING_DEPS=()

if ! command -v bash &> /dev/null; then
    MISSING_DEPS+=("bash")
fi

if ! command -v apt-get &> /dev/null; then
    print_msg "$YELLOW" "Внимание: apt-get не найден. Этот скрипт предназначен для Debian/Ubuntu."
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    print_msg "$RED" "Отсутствуют зависимости: ${MISSING_DEPS[*]}"
    print_msg "$YELLOW" "Установите их вручную: apt-get install ${MISSING_DEPS[*]}"
fi

print_msg "$GREEN" "============================================"
print_msg "$GREEN" "  Установка завершена успешно!"
print_msg "$GREEN" "============================================"
echo ""

print_msg "$BLUE" "Как использовать:"
print_msg "$CYAN" "  sudo server-setup"
echo ""
print_msg "$BLUE" "Или запустите напрямую:"
print_msg "$CYAN" "  sudo $INSTALL_DIR/server-setup.sh"
echo ""
