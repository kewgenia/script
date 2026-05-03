#!/bin/bash
# ============================================================ #
# ==           СКРИПТ УСТАНОВКИ VPS SECURITY              == #
# ============================================================ #
# Этот скрипт устанавливает VPS Security Setup в систему.
# По умолчанию устанавливает в /opt/vps-security-setup
# и создает симлинк в /usr/local/bin.

set -euo pipefail

# Определяем директорию, где находится скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Проверка прав root
if [[ "$(id -u)" -ne 0 ]]; then
    print_msg "$RED" "Ошибка: Скрипт должен запускаться от root (sudo ./install.sh)"
    exit 1
fi

INSTALL_DIR="/opt/vps-security-setup"
LINK_PATH="/usr/local/bin/vps-security-setup"

print_msg "$BLUE" "============================================"
print_msg "$BLUE" "  Установка VPS Security Initial Setup"
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
    # Очищаем директорию установки перед копированием (кроме самого скрипта install.sh, если он там есть)
    rm -rf "$INSTALL_DIR"/*
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
fi

# 3. Установка прав на исполнение
print_msg "$YELLOW" "3. Установка прав на исполнение..."
chmod +x "$INSTALL_DIR/vps-security-setup.sh"
chmod +x "$INSTALL_DIR/install.sh"
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;

# 4. Создание симлинка
print_msg "$YELLOW" "4. Создание симлинка: $LINK_PATH"
# Удаляем старый симлинк или файл, если существует
if [[ -e "$LINK_PATH" ]]; then
    rm -f "$LINK_PATH"
fi
ln -s "$INSTALL_DIR/vps-security-setup.sh" "$LINK_PATH"

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
print_msg "$CYAN" "  sudo vps-security-setup"
echo ""
print_msg "$BLUE" "Или запустите напрямую:"
print_msg "$CYAN" "  sudo $INSTALL_DIR/vps-security-setup.sh"
echo ""
