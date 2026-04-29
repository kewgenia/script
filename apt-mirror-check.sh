#!/bin/sh
#
# apt-mirror-check.sh - Скрипт для проверки и замены apt репозиториев
# Этот скрипт анализирует текущие репозитории, предлагает заменить их
# на зеркала Yandex или позволяет ввести свои собственные зеркала.
#
# Использование: sudo ./apt-mirror-check.sh
#

set -eu  # Выход при ошибке, выход при использовании неопределённой переменной

# Конфигурация
LOG_FILE="/var/log/apt-mirror-check.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
BACKUP_DIR="/etc/apt/backup-$(date '+%Y%m%d-%H%M%S')"

# Цветовые коды для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Определение дистрибутива
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_CODENAME=""
        if command -v lsb_release >/dev/null 2>&1; then
            DISTRO_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
        elif [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
            DISTRO_CODENAME="$DISTRIB_CODENAME"
        elif [ -n "${VERSION_CODENAME:-}" ]; then
            DISTRO_CODENAME="$VERSION_CODENAME"
        fi
    else
        print_msg "$YELLOW" "Не удалось определить дистрибутив. Будут использованы общие настройки."
        DISTRO_ID="unknown"
        DISTRO_CODENAME=""
    fi
    
    print_msg "$BLUE" "Обнаружен дистрибутив: $DISTRO_ID ${DISTRO_CODENAME:+(кодовое имя: $DISTRO_CODENAME)}"
}

# Получение списка всех активных репозиториев
get_repositories() {
    print_msg "$BLUE" "Сбор информации о текущих репозиториях..."
    
    # Основной файл sources.list
    SOURCES_LIST="/etc/apt/sources.list"
    
    # Временный файл для хранения всех репозиториев
    REPO_LIST=$(mktemp)
    
    # Чтение основного файла
    if [ -f "$SOURCES_LIST" ]; then
        grep -E "^deb\s" "$SOURCES_LIST" | grep -v "^#" >> "$REPO_LIST" 2>/dev/null || true
    fi
    
    # Чтение файлов из sources.list.d
    if [ -d /etc/apt/sources.list.d ]; then
        for file in /etc/apt/sources.list.d/*.list; do
            if [ -f "$file" ]; then
                grep -E "^deb\s" "$file" | grep -v "^#" >> "$REPO_LIST" 2>/dev/null || true
            fi
        done
        
        # Также проверяем .sources файлы (новый формат DEB822)
        for file in /etc/apt/sources.list.d/*.sources; do
            if [ -f "$file" ]; then
                # Для файлов в новом формате просто отмечаем их наличие
                echo "# Файл в формате DEB822: $file" >> "$REPO_LIST"
            fi
        done
    fi
    
    # Сохраняем путь к временному файлу
    echo "$REPO_LIST"
}

# Отображение текущих репозиториев
show_repositories() {
    local repo_list="$1"
    
    print_msg "$GREEN" "========================================"
    print_msg "$GREEN" " Текущие APT репозитории"
    print_msg "$GREEN" "========================================"
    
    if [ ! -s "$repo_list" ]; then
        print_msg "$YELLOW" "Активные репозитории не найдены."
        return 1
    fi
    
    local count=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            if echo "$line" | grep -q "^#"; then
                echo -e "${CYAN}$line${NC}"
            else
                count=$((count + 1))
                echo -e "${BLUE}$count.${NC} $line"
            fi
        fi
    done < "$repo_list"
    
    print_msg "$GREEN" "========================================"
    return 0
}

# Создание резервной копии
create_backup() {
    print_msg "$BLUE" "Создание резервной копии конфигурации apt..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Копирование sources.list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list "$BACKUP_DIR/sources.list.bak"
    fi
    
    # Копирование sources.list.d
    if [ -d /etc/apt/sources.list.d ]; then
        mkdir -p "$BACKUP_DIR/sources.list.d"
        cp -r /etc/apt/sources.list.d/* "$BACKUP_DIR/sources.list.d/" 2>/dev/null || true
    fi
    
    print_msg "$GREEN" "Резервная копия создана в: $BACKUP_DIR"
    log "Создана резервная копия: $BACKUP_DIR"
}

# Формирование URL зеркала Yandex для дистрибутива
get_yandex_mirror() {
    local distro="$1"
    local mirror=""
    
    case "$distro" in
        debian)
            mirror="http://mirror.yandex.ru/debian/"
            ;;
        ubuntu)
            mirror="http://mirror.yandex.ru/ubuntu/"
            ;;
        linuxmint)
            mirror="http://mirror.yandex.ru/linuxmint-packages/"
            ;;
        pop)
            mirror="http://mirror.yandex.ru/pop-os/"
            ;;
        elementary)
            mirror="http://mirror.yandex.ru/elementary/"
            ;;
        *)
            # Для неизвестных дистрибутивов используем общий подход
            mirror="http://mirror.yandex.ru/debian/"
            print_msg "$YELLOW" "Неизвестный дистрибутив, будет использовано зеркало Debian по умолчанию."
            ;;
    esac
    
    echo "$mirror"
}

# Замена репозиториев на зеркала Yandex
replace_with_yandex() {
    local repo_list="$1"
    local distro="$2"
    local codename="$3"
    local yandex_mirror
    
    yandex_mirror=$(get_yandex_mirror "$distro")
    
    print_msg "$BLUE" "Замена репозиториев на зеркала Yandex..."
    print_msg "$CYAN" "Зеркало Yandex: $yandex_mirror"
    
    create_backup
    
    # Обработка основного файла sources.list
    if [ -f /etc/apt/sources.list ]; then
        # Создание нового sources.list
        local new_sources=$(mktemp)
        
        # Добавление заголовка
        echo "# Файл сгенерирован скриптом apt-mirror-check.sh" > "$new_sources"
        echo "# Дата: $DATE" >> "$new_sources"
        echo "# Оригинал сохранён в: $BACKUP_DIR/sources.list.bak" >> "$new_sources"
        echo "" >> "$new_sources"
        
        # Основной репозиторий
        echo "deb $yandex_mirror $codename main contrib non-free non-free-firmware" >> "$new_sources"
        
        # Обновления безопасности
        if [ "$distro" = "debian" ]; then
            echo "deb http://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware" >> "$new_sources"
        elif [ "$distro" = "ubuntu" ]; then
            echo "deb $yandex_mirror $codename-security main restricted universe multiverse" >> "$new_sources"
        fi
        
        # Обновления (updates)
        if [ "$distro" = "debian" ]; then
            echo "deb $yandex_mirror $codename-updates main contrib non-free non-free-firmware" >> "$new_sources"
        elif [ "$distro" = "ubuntu" ]; then
            echo "deb $yandex_mirror $codename-updates main restricted universe multiverse" >> "$new_sources"
        fi
        
        # Замена файла
        mv "$new_sources" /etc/apt/sources.list
        print_msg "$GREEN" "Файл /etc/apt/sources.list обновлён."
    fi
    
    # Обработка sources.list.d - отключаем сторонние репозитории
    if [ -d /etc/apt/sources.list.d ]; then
        print_msg "$BLUE" "Отключение сторонних репозиториев в sources.list.d..."
        for file in /etc/apt/sources.list.d/*.list; do
            if [ -f "$file" ] && [ -s "$file" ]; then
                # Переименование файла для отключения
                mv "$file" "${file}.disabled"
                print_msg "$YELLOW" "Отключен: $(basename "$file")"
            fi
        done
    fi
    
    print_msg "$GREEN" "Замена репозиториев завершена."
    log "Репозитории заменены на зеркала Yandex"
}

# Ручной ввод зеркал
manual_mirror_input() {
    local distro="$1"
    local codename="$2"
    
    print_msg "$BLUE" "Ручная настройка зеркал"
    print_msg "$CYAN" "Текущий дистрибутив: $distro"
    print_msg "$CYAN" "Кодовое имя: ${codename:-не определено}"
    echo ""
    
    create_backup
    
    # Запрос URL зеркала
    print_msg "$YELLOW" "Введите URL основного зеркала (например: http://mirror.yandex.ru/debian/):"
    read -r mirror_url
    
    if [ -z "$mirror_url" ]; then
        print_msg "$RED" "URL не может быть пустым. Операция отменена."
        return 1
    fi
    
    # Проверка корректности URL (простая проверка)
    if ! echo "$mirror_url" | grep -qE "^https?://"; then
        print_msg "$RED" "Некорректный URL. Должен начинаться с http:// или https://"
        return 1
    fi
    
    # Удаление лишнего слэша в конце
    mirror_url="${mirror_url%/}"
    
    # Создание нового sources.list
    local new_sources=$(mktemp)
    
    echo "# Файл сгенерирован скриптом apt-mirror-check.sh" > "$new_sources"
    echo "# Дата: $DATE" >> "$new_sources"
    echo "# Оригинал сохранён в: $BACKUP_DIR/sources.list.bak" >> "$new_sources"
    echo "# Пользовательское зеркало: $mirror_url" >> "$new_sources"
    echo "" >> "$new_sources"
    
    # Основной репозиторий
    if [ -n "$codename" ]; then
        echo "deb $mirror_url $codename main contrib non-free non-free-firmware" >> "$new_sources"
    else
        print_msg "$YELLOW" "Кодовое имя не определено. Введите вручную:"
        read -r codename_manual
        echo "deb $mirror_url $codename_manual main contrib non-free non-free-firmware" >> "$new_sources"
    fi
    
    # Запрос дополнительных репозиториев
    print_msg "$YELLOW" "Хотите добавить репозиторий security? (y/n)"
    read -r add_security
    if [ "$add_security" = "y" ] || [ "$add_security" = "Y" ]; then
        if [ "$distro" = "debian" ]; then
            echo "deb http://security.debian.org/debian-security $codename-security main contrib non-free non-free-firmware" >> "$new_sources"
        elif [ "$distro" = "ubuntu" ]; then
            echo "deb $mirror_url $codename-security main restricted universe multiverse" >> "$new_sources"
        fi
    fi
    
    # Замена файла
    mv "$new_sources" /etc/apt/sources.list
    print_msg "$GREEN" "Файл /etc/apt/sources.list обновлён с пользовательским зеркалом."
    
    # Отключение сторонних репозиториев
    if [ -d /etc/apt/sources.list.d ]; then
        print_msg "$BLUE" "Отключение сторонних репозиториев..."
        for file in /etc/apt/sources.list.d/*.list; do
            if [ -f "$file" ] && [ -s "$file" ]; then
                mv "$file" "${file}.disabled" 2>/dev/null || true
            fi
        done
    fi
    
    log "Репозитории заменены на пользовательское зеркало: $mirror_url"
    return 0
}

# Обновление списков пакетов
update_package_lists() {
    print_msg "$BLUE" "Обновление списков пакетов..."
    if apt-get update >> "$LOG_FILE" 2>&1; then
        print_msg "$GREEN" "Списки пакетов успешно обновлены."
    else
        print_msg "$YELLOW" "Предупреждение при обновлении списков. Проверьте $LOG_FILE для деталей."
    fi
}

# Восстановление из резервной копии
restore_backup() {
    print_msg "$BLUE" "Доступные резервные копии:"
    
    local backups
    backups=$(find /etc/apt -maxdepth 1 -type d -name "backup-*" 2>/dev/null | sort -r)
    
    if [ -z "$backups" ]; then
        print_msg "$YELLOW" "Резервные копии не найдены."
        return 1
    fi
    
    local i=1
    echo "$backups" | while IFS= read -r backup; do
        echo -e "${CYAN}$i.${NC} $backup"
        i=$((i + 1))
    done
    
    print_msg "$YELLOW" "Введите номер резервной копии для восстановления (или 0 для отмены):"
    read -r backup_choice
    
    if [ "$backup_choice" = "0" ] || [ -z "$backup_choice" ]; then
        print_msg "$YELLOW" "Восстановление отменено."
        return 0
    fi
    
    local selected_backup
    selected_backup=$(echo "$backups" | sed -n "${backup_choice}p")
    
    if [ -z "$selected_backup" ] || [ ! -d "$selected_backup" ]; then
        print_msg "$RED" "Неверный выбор."
        return 1
    fi
    
    print_msg "$BLUE" "Восстановление из $selected_backup..."
    
    # Восстановление sources.list
    if [ -f "$selected_backup/sources.list.bak" ]; then
        cp "$selected_backup/sources.list.bak" /etc/apt/sources.list
        print_msg "$GREEN" "Файл sources.list восстановлен."
    fi
    
    # Восстановление sources.list.d
    if [ -d "$selected_backup/sources.list.d" ]; then
        # Включение отключенных файлов
        for file in /etc/apt/sources.list.d/*.disabled; do
            if [ -f "$file" ]; then
                mv "$file" "${file%.disabled}"
            fi
        done
        
        # Копирование файлов из резервной копии
        cp -r "$selected_backup/sources.list.d/"* /etc/apt/sources.list.d/ 2>/dev/null || true
        print_msg "$GREEN" "Файлы sources.list.d восстановлены."
    fi
    
    log "Восстановление из резервной копии: $selected_backup"
    return 0
}

# Главное меню
show_menu() {
    echo ""
    print_msg "$GREEN" "========================================"
    print_msg "$GREEN" " Меню управления репозиториями"
    print_msg "$GREEN" "========================================"
    echo -e "${CYAN}1.${NC} Заменить репозитории на зеркала Yandex"
    echo -e "${CYAN}2.${NC} Ввести свои зеркала вручную"
    echo -e "${CYAN}3.${NC} Обновить списки пакетов"
    echo -e "${CYAN}4.${NC} Восстановить из резервной копии"
    echo -e "${CYAN}5.${NC} Показать текущие репозитории"
    echo -e "${CYAN}0.${NC} Выход"
    print_msg "$GREEN" "========================================"
    echo ""
}

# Основная функция выполнения
main() {
    print_msg "$GREEN" "========================================"
    print_msg "$GREEN" " Скрипт проверки APT репозиториев"
    print_msg "$GREEN" " Начато: $DATE"
    print_msg "$GREEN" "========================================"
    
    log "Начато выполнение скрипта проверки репозиториев"
    
    # Проверка прав root
    check_root
    
    # Определение дистрибутива
    detect_distro
    
    # Получение списка репозиториев
    REPO_LIST=$(get_repositories)
    
    # Показ текущих репозиториев
    show_repositories "$REPO_LIST" || true
    
    # Главный цикл меню
    while true; do
        show_menu
        print_msg "$YELLOW" "Выберите действие:"
        read -r choice
        
        case $choice in
            1)
                if [ -z "$DISTRO_CODENAME" ]; then
                    print_msg "$YELLOW" "Кодовое имя не определено. Введите вручную:"
                    read -r DISTRO_CODENAME
                fi
                replace_with_yandex "$REPO_LIST" "$DISTRO_ID" "$DISTRO_CODENAME"
                ;;
            2)
                if [ -z "$DISTRO_CODENAME" ]; then
                    print_msg "$YELLOW" "Кодовое имя не определено. Введите вручную:"
                    read -r DISTRO_CODENAME
                fi
                manual_mirror_input "$DISTRO_ID" "$DISTRO_CODENAME"
                ;;
            3)
                update_package_lists
                ;;
            4)
                restore_backup
                ;;
            5)
                REPO_LIST=$(get_repositories)
                show_repositories "$REPO_LIST" || true
                ;;
            0)
                print_msg "$GREEN" "Выход из скрипта."
                break
                ;;
            *)
                print_msg "$RED" "Неверный выбор. Попробуйте снова."
                ;;
        esac
        echo ""
    done
    
    # Очистка временных файлов
    if [ -n "${REPO_LIST:-}" ] && [ -f "$REPO_LIST" ]; then
        rm -f "$REPO_LIST"
    fi
    
    END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
    print_msg "$GREEN" "========================================"
    print_msg "$GREEN" " Работа скрипта завершена!"
    print_msg "$GREEN" " Завершено: $END_DATE"
    print_msg "$GREEN" " Файл журнала: $LOG_FILE"
    print_msg "$GREEN" "========================================"
    
    log "Скрипт завершил работу"
}

# Запуск основной функции
main "$@"
