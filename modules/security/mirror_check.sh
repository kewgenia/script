#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: УПРАВЛЕНИЕ ЗЕРКАЛАМИ APT            == #
# ============================================================ #
# Настройка и управление репозиториями APT.
# Версия: 2.0.0

#
# @menu.manifest
#
# @item( main | 2 | 🌐 Зеркала APT | show_mirror_check_menu | 20 | 10 | Настройка репозиториев )
# @item( mirror_check | 1 | Заменить на зеркала Yandex | _replace_with_yandex_menu | 10 | 10 | Быстрая замена на mirror.yandex.ru )
# @item( mirror_check | 2 | Ввести зеркала вручную | _manual_mirror_input | 20 | 10 | Настройка пользовательских зеркал )
# @item( mirror_check | 3 | Обновить списки пакетов | _update_package_lists | 30 | 10 | apt-get update )
# @item( mirror_check | 4 | Восстановить из бэкапа | _restore_backup | 40 | 10 | Откат к сохраненной конфигурации )
# @item( mirror_check | 5 | Показать текущие репозитории | _show_repositories | 50 | 10 | Просмотр активных источников )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# --- Локальные переменные модуля ---
BACKUP_DIR="/etc/apt/backup-$(date '+%Y%m%d-%H%M%S')"

# --- ЛОКАЛЬНЫЕ ХЕЛПЕРЫ ---

_detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_CODENAME=""
        if command -v lsb_release >/dev/null 2>&1; then
            DISTRO_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
        elif [[ -f /etc/lsb-release ]]; then
            . /etc/lsb-release
            DISTRO_CODENAME="$DISTRIB_CODENAME"
        elif [[ -n "${VERSION_CODENAME:-}" ]]; then
            DISTRO_CODENAME="$VERSION_CODENAME"
        fi
    else
        warn "Не удалось определить дистрибутив."
        DISTRO_ID="unknown"
        DISTRO_CODENAME=""
    fi
    info "Обнаружен дистрибутив: $DISTRO_ID ${DISTRO_CODENAME:+(кодовое имя: $DISTRO_CODENAME)}"
}

_get_repositories() {
    local repo_list
    repo_list=$(mktemp)
    
    if [[ -f /etc/apt/sources.list ]]; then
        grep -E "^deb\s" /etc/apt/sources.list | grep -v "^#" >> "$repo_list" 2>/dev/null || true
    fi
    
    if [[ -d /etc/apt/sources.list.d ]]; then
        for file in /etc/apt/sources.list.d/*.list; do
            if [[ -f "$file" ]]; then
                grep -E "^deb\s" "$file" | grep -v "^#" >> "$repo_list" 2>/dev/null || true
            fi
        done
    fi
    echo "$repo_list"
}

_show_repositories() {
    local repo_list
    repo_list=$(_get_repositories)
    
    menu_header "Текущие APT репозитории"
    
    if [[ ! -s "$repo_list" ]]; then
        warn "Активные репозитории не найдены."
        [[ $VERBOSE == true ]] && wait_for_enter
        return
    fi
    
    local count=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            count=$((count + 1))
            echo -e "  ${CYAN}$count.${NC} $line"
        fi
    done < "$repo_list"
    
    echo ""
    [[ $VERBOSE == true ]] && wait_for_enter
    
    if [[ -f "$repo_list" ]]; then
        rm -f "$repo_list"
    fi
}

_create_backup() {
    info "Создание резервной копии конфигурации apt..."
    mkdir -p "$BACKUP_DIR"
    
    if [[ -f /etc/apt/sources.list ]]; then
        cp /etc/apt/sources.list "$BACKUP_DIR/sources.list.bak"
    fi
    
    if [[ -d /etc/apt/sources.list.d ]]; then
        mkdir -p "$BACKUP_DIR/sources.list.d"
        cp -r /etc/apt/sources.list.d/* "$BACKUP_DIR/sources.list.d/" 2>/dev/null || true
    fi
    
    ok "Резервная копия создана в: $BACKUP_DIR"
    log "Создана резервная копия: $BACKUP_DIR"
}

_get_yandex_mirror() {
    local distro="$1"
    case "$distro" in
        debian) echo "http://mirror.yandex.ru/debian/" ;;
        ubuntu) echo "http://mirror.yandex.ru/ubuntu/" ;;
        linuxmint) echo "http://mirror.yandex.ru/linuxmint-packages/" ;;
        *) echo "http://mirror.yandex.ru/debian/" ;;
    esac
}

_replace_with_yandex_menu() {
    _detect_distro
    
    if [[ -z "$DISTRO_CODENAME" ]]; then
        DISTRO_CODENAME=$(safe_read "Кодовое имя не определено. Введите вручную (например, bookworm): ")
    fi
    
    if ! ask_yes_no "Заменить текущие репозитории на зеркала Yandex?"; then
        return
    fi
    
    local yandex_mirror
    yandex_mirror=$(_get_yandex_mirror "$DISTRO_ID")
    
    _create_backup
    
    local new_sources
    new_sources=$(mktemp)
    
    {
        echo "# Файл сгенерирован скриптом Server Setup"
        echo "# Дата: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Зеркало: $yandex_mirror"
        echo ""
        echo "deb $yandex_mirror $DISTRO_CODENAME main contrib non-free non-free-firmware"
        
        if [[ "$DISTRO_ID" == "debian" ]]; then
            echo "deb http://security.debian.org/debian-security ${DISTRO_CODENAME}-security main contrib non-free non-free-firmware"
            echo "deb $yandex_mirror ${DISTRO_CODENAME}-updates main contrib non-free non-free-firmware"
        elif [[ "$DISTRO_ID" == "ubuntu" ]]; then
            echo "deb $yandex_mirror ${DISTRO_CODENAME}-security main restricted universe multiverse"
            echo "deb $yandex_mirror ${DISTRO_CODENAME}-updates main restricted universe multiverse"
        fi
    } > "$new_sources"
    
    mv "$new_sources" /etc/apt/sources.list
    ok "Файл /etc/apt/sources.list обновлён."
    
    # Отключаем сторонние репозитории
    if [[ -d /etc/apt/sources.list.d ]]; then
        for file in /etc/apt/sources.list.d/*.list; do
            if [[ -f "$file" ]] && [[ -s "$file" ]]; then
                mv "$file" "${file}.disabled" 2>/dev/null || true
            fi
        done
    fi
    
    ok "Замена репозиториев завершена."
    [[ $VERBOSE == true ]] && wait_for_enter
}

_manual_mirror_input() {
    _detect_distro
    
    if [[ -z "$DISTRO_CODENAME" ]]; then
        DISTRO_CODENAME=$(safe_read "Введите кодовое имя дистрибутива (например, jammy): ")
    fi
    
    local mirror_url
    mirror_url=$(safe_read "Введите URL основного зеркала (например, http://mirror.yandex.ru/debian/): ")
    
    if [[ -z "$mirror_url" ]]; then
        err "URL не может быть пустым."
        return
    fi
    
    _create_backup
    
    local new_sources
    new_sources=$(mktemp)
    
    {
        echo "# Файл сгенерирован скриптом Server Setup"
        echo "# Пользовательское зеркало: $mirror_url"
        echo ""
        echo "deb ${mirror_url%/} $DISTRO_CODENAME main contrib non-free non-free-firmware"
    } > "$new_sources"
    
    mv "$new_sources" /etc/apt/sources.list
    ok "Репозитории обновлены с пользовательским зеркалом."
    [[ $VERBOSE == true ]] && wait_for_enter
}

_update_package_lists() {
    info "Обновление списков пакетов..."
    if run_cmd "apt-get update"; then
        ok "Списки пакетов успешно обновлены."
    else
        warn "Предупреждение при обновлении списков. Проверьте лог."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_restore_backup() {
    info "Поиск доступных резервных копий..."
    local backups
    backups=$(find /etc/apt -maxdepth 1 -type d -name "backup-*" 2>/dev/null | sort -r)
    
    if [[ -z "$backups" ]]; then
        warn "Резервные копии не найдены."
        [[ $VERBOSE == true ]] && wait_for_enter
        return
    fi
    
    menu_header "Доступные резервные копии"
    local i=1
    echo "$backups" | while IFS= read -r backup; do
        echo -e "  ${GREEN}$i.${NC} $backup"
        i=$((i + 1))
    done
    
    local choice
    choice=$(safe_read "Введите номер для восстановления (0 для отмены): ")
    
    if [[ "$choice" == "0" || -z "$choice" ]]; then
        info "Восстановление отменено."
        return
    fi
    
    local selected_backup
    selected_backup=$(echo "$backups" | sed -n "${choice}p")
    
    if [[ -n "$selected_backup" ]] && [[ -d "$selected_backup" ]]; then
        if [[ -f "$selected_backup/sources.list.bak" ]]; then
            cp "$selected_backup/sources.list.bak" /etc/apt/sources.list
            ok "Файл sources.list восстановлен."
        fi
        ok "Восстановление завершено."
    else
        err "Неверный выбор."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_mirror_check_menu() {
    local menu_id="mirror_check"
    
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "🌐 Управление зеркалами APT"
        printf_description "Настройка источников пакетов для вашей системы."
        
        # Автоматическая отрисовка пунктов меню
        render_menu_items "$menu_id"
        
        printf_menu_option "b" "Назад в главное меню"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        # Выход из меню
        if [[ "$choice" == "b" || "$choice" == "B" ]]; then
            break
        fi
        
        # Получаем и выполняем действие
        local action
        action=$(get_menu_action "$menu_id" "$choice")
        
        if [[ -n "$action" ]]; then
            eval "$action"
        else
            err "Нет такого пункта." && sleep 1
        fi
    done
    disable_graceful_ctrlc
}
