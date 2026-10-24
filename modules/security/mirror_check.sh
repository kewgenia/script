#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: УПРАВЛЕНИЕ ЗЕРКАЛАМИ APT            == #
# ============================================================ #
# Настройка и управление репозиториями APT.
# Версия: 2.0.0

#
# @menu.manifest
#
# @item( main | m | 🌐 Зеркала APT | show_mirror_check_menu | 5 | 5 | Настройка репозиториев )
# @item( mirror_check | 1 | Заменить на зеркала Yandex | _replace_with_yandex_menu | 10 | 10 | Быстрая замена на mirror.yandex.ru )
# @item( mirror_check | 2 | Ввести зеркала вручную | _manual_mirror_input | 20 | 10 | Настройка пользовательских зеркал )
# @item( mirror_check | 3 | Обновить списки пакетов | _mirror_update_package_lists | 30 | 10 | apt-get update )
# @item( mirror_check | 4 | Восстановить из бэкапа | _restore_backup | 40 | 10 | Откат к сохраненной конфигурации )
# @item( mirror_check | 5 | Показать текущие репозитории | _show_repositories | 50 | 10 | Просмотр активных источников )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# --- Локальные переменные модуля ---
# Отдельное имя, чтобы не перетирать глобальный BACKUP_DIR из common.sh
APT_BACKUP_DIR=""

# Системные deb822-файлы дистрибутива (Debian 12+, Ubuntu 24.04+)
APT_DISTRO_SOURCES=(
    "/etc/apt/sources.list.d/debian.sources"
    "/etc/apt/sources.list.d/ubuntu.sources"
)

# --- ЛОКАЛЬНЫЕ ХЕЛПЕРЫ ---

_detect_distro() {
    if [[ -f /etc/os-release ]]; then
        DISTRO_ID=$(. /etc/os-release && echo "${ID:-unknown}")
        DISTRO_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
        if [[ -z "$DISTRO_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
            DISTRO_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
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
        local file
        for file in /etc/apt/sources.list.d/*.list; do
            if [[ -f "$file" ]]; then
                grep -E "^deb\s" "$file" | grep -v "^#" >> "$repo_list" 2>/dev/null || true
            fi
        done
        # Формат deb822 (*.sources): выводим URIs и Suites каждого блока
        for file in /etc/apt/sources.list.d/*.sources; do
            if [[ -f "$file" ]]; then
                awk -v f="$(basename "$file")" '
                    tolower($1) == "enabled:" && tolower($2) == "no" { disabled = 1 }
                    tolower($1) == "uris:"   { uris = substr($0, index($0, $2)) }
                    tolower($1) == "suites:" { suites = substr($0, index($0, $2)) }
                    /^[[:space:]]*$/ { if (uris != "" && !disabled) print "[" f "] " uris " " suites; uris = ""; suites = ""; disabled = 0 }
                    END { if (uris != "" && !disabled) print "[" f "] " uris " " suites }
                ' "$file" >> "$repo_list" 2>/dev/null || true
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
        rm -f "$repo_list"
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
    rm -f "$repo_list"
    [[ $VERBOSE == true ]] && wait_for_enter
}

_create_backup() {
    info "Создание резервной копии конфигурации apt..."
    APT_BACKUP_DIR="/etc/apt/backup-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$APT_BACKUP_DIR"
    
    if [[ -f /etc/apt/sources.list ]]; then
        cp /etc/apt/sources.list "$APT_BACKUP_DIR/sources.list.bak"
    fi
    
    if [[ -d /etc/apt/sources.list.d ]]; then
        mkdir -p "$APT_BACKUP_DIR/sources.list.d"
        cp -r /etc/apt/sources.list.d/* "$APT_BACKUP_DIR/sources.list.d/" 2>/dev/null || true
    fi
    
    ok "Резервная копия создана в: $APT_BACKUP_DIR"
    log "Создана резервная копия: $APT_BACKUP_DIR"
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

# Записывает /etc/apt/sources.list для указанного зеркала с учетом дистрибутива
_write_sources_list() {
    local mirror="${1%/}/"
    local components security_line
    
    case "$DISTRO_ID" in
        ubuntu)
            components="main restricted universe multiverse"
            security_line="deb ${mirror} ${DISTRO_CODENAME}-security ${components}"
            ;;
        *)
            components="main contrib non-free"
            # non-free-firmware существует начиная с Debian 12 (bookworm)
            if [[ ! "$DISTRO_CODENAME" =~ ^(buster|bullseye)$ ]]; then
                components+=" non-free-firmware"
            fi
            security_line="deb http://security.debian.org/debian-security ${DISTRO_CODENAME}-security ${components}"
            ;;
    esac
    
    local new_sources
    new_sources=$(mktemp)
    {
        echo "# Файл сгенерирован скриптом Server Setup"
        echo "# Дата: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Зеркало: $mirror"
        echo ""
        echo "deb ${mirror} ${DISTRO_CODENAME} ${components}"
        echo "deb ${mirror} ${DISTRO_CODENAME}-updates ${components}"
        echo "$security_line"
    } > "$new_sources"
    
    mv "$new_sources" /etc/apt/sources.list
    chmod 644 /etc/apt/sources.list
    ok "Файл /etc/apt/sources.list обновлён."
    
    # Отключаем только системные deb822-источники дистрибутива, иначе
    # они продолжат использоваться параллельно с новым зеркалом.
    # Сторонние репозитории (Docker, NetBird и т.д.) не трогаем.
    local file
    for file in "${APT_DISTRO_SOURCES[@]}"; do
        if [[ -f "$file" ]]; then
            mv "$file" "${file}.disabled"
            info "Отключен системный источник: $file"
        fi
    done
    log "sources.list заменен на зеркало $mirror ($DISTRO_ID $DISTRO_CODENAME)"
}

_ask_codename_if_empty() {
    if [[ -z "$DISTRO_CODENAME" ]]; then
        DISTRO_CODENAME=$(safe_read "Кодовое имя не определено. Введите вручную (например, bookworm): ")
    fi
    if [[ ! "$DISTRO_CODENAME" =~ ^[a-z]+$ ]]; then
        err "Некорректное кодовое имя: '$DISTRO_CODENAME'."
        return 1
    fi
}

_replace_with_yandex_menu() {
    _detect_distro
    _ask_codename_if_empty || return 1
    
    if ! ask_yes_no "Заменить текущие репозитории на зеркала Yandex?"; then
        return
    fi
    
    _create_backup
    _write_sources_list "$(_get_yandex_mirror "$DISTRO_ID")"
    
    ok "Замена репозиториев завершена. Выполните 'Обновить списки пакетов'."
    [[ $VERBOSE == true ]] && wait_for_enter
}

_manual_mirror_input() {
    _detect_distro
    _ask_codename_if_empty || return 1
    
    local mirror_url
    mirror_url=$(safe_read "Введите URL основного зеркала (например, http://mirror.yandex.ru/debian/): ")
    
    if [[ ! "$mirror_url" =~ ^https?://[^[:space:]]+$ ]]; then
        err "Некорректный URL зеркала."
        return 1
    fi
    
    _create_backup
    _write_sources_list "$mirror_url"
    
    ok "Репозитории обновлены с пользовательским зеркалом."
    [[ $VERBOSE == true ]] && wait_for_enter
}

_mirror_update_package_lists() {
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
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        err "Неверный выбор."
        return 1
    fi
    
    local selected_backup
    selected_backup=$(echo "$backups" | sed -n "${choice}p")
    
    if [[ -n "$selected_backup" ]] && [[ -d "$selected_backup" ]]; then
        if [[ -f "$selected_backup/sources.list.bak" ]]; then
            cp "$selected_backup/sources.list.bak" /etc/apt/sources.list
            ok "Файл sources.list восстановлен."
        fi
        if [[ -d "$selected_backup/sources.list.d" ]]; then
            local file
            for file in "$selected_backup"/sources.list.d/*; do
                [[ -f "$file" ]] || continue
                cp "$file" /etc/apt/sources.list.d/
                rm -f "/etc/apt/sources.list.d/$(basename "$file").disabled"
            done
            ok "Каталог sources.list.d восстановлен."
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
            err "Нет такого пункта."
        fi
    done
    disable_graceful_ctrlc
}
