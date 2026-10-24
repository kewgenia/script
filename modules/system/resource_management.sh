#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: УПРАВЛЕНИЕ РЕСУРСАМИ         == #
# ============================================================ #
# Настройка Swap, синхронизация времени (chrony).
# Версия: 1.1.0

#
# @menu.manifest
#
# @item( main | 10 | ⚙️ Ресурсы (Swap/Время) | show_resource_management_menu | 100 | 20 | Swap и синхронизация времени )
# @item( resource_management | 1 | Настроить Swap | _configure_swap | 10 | 10 | Swap файл или раздел )
# @item( resource_management | 2 | Настроить синхронизацию времени | _configure_time_sync | 20 | 10 | chrony setup )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

# Перевод размера (2G, 512M, 1024) в мегабайты; код 1 при неверном формате
_convert_to_mb() {
    local size_str="$1"
    if [[ ! "$size_str" =~ ^([0-9]+)([GgMm]?)$ ]]; then
        return 1
    fi
    local size_num="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}"
    case "$unit" in
        G|g) echo $((size_num * 1024)) ;;
        *) echo "$size_num" ;;
    esac
}

# Запрашивает размер swap и проверяет свободное место. Результат (МБ) — в stdout.
_ask_swap_size_mb() {
    local default="$1"
    local swap_size required_mb avail_mb
    while true; do
        swap_size=$(safe_read "Введите размер swap (например, 2G, 512M) [$default]: ") || return 1
        swap_size=${swap_size:-$default}
        
        if ! required_mb=$(_convert_to_mb "$swap_size"); then
            err "Неверный формат размера. Примеры: 2G, 512M." >&2
            continue
        fi
        if (( required_mb < 128 )); then
            err "Минимальный размер: 128M." >&2
            continue
        fi
        avail_mb=$(( $(df -k --output=avail / | tail -n 1) / 1024 ))
        if (( avail_mb < required_mb )); then
            err "Недостаточно места. Нужно: ${required_mb}MB, Доступно: ${avail_mb}MB" >&2
            continue
        fi
        echo "$required_mb"
        return 0
    done
}

# Создает и включает файл подкачки указанного размера (МБ)
_create_swap_file() {
    local path="$1" size_mb="$2"
    rm -f "$path"
    # fallocate не поддерживается для swap на некоторых ФС (btrfs, старый xfs)
    if ! fallocate -l "${size_mb}M" "$path" 2>/dev/null; then
        warn "fallocate не удался. Используем dd..."
        if ! dd if=/dev/zero of="$path" bs=1M count="$size_mb" status=none; then
            err "Не удалось создать файл $path."
            rm -f "$path"
            return 1
        fi
    fi
    chmod 600 "$path"
    if ! mkswap "$path" >/dev/null 2>&1 || ! swapon "$path"; then
        err "Не удалось активировать swap $path."
        rm -f "$path"
        return 1
    fi
    if ! grep -qE "^${path}[[:space:]]" /etc/fstab; then
        echo "$path none swap sw 0 0" >> /etc/fstab
        ok "Запись добавлена в /etc/fstab."
    fi
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_configure_swap() {
    print_section "Настройка Swap"
    
    # Проверка на контейнер
    if systemd-detect-virt --container --quiet 2>/dev/null; then
        info "В контейнере Swap не настраивается."
        return 0
    fi
    
    # Проверка существующего swap
    local existing_swap swap_type swap_size_mb
    read -r existing_swap swap_type swap_size_mb < <(swapon --show=NAME,TYPE,SIZE --noheadings --bytes 2>/dev/null | head -n 1 | awk '{print $1, $2, int($3/1048576)}')
    
    if [[ -n "$existing_swap" ]]; then
        info "Обнаружен Swap: $existing_swap (Тип: $swap_type, Размер: ${swap_size_mb}M)"
        
        if [[ "$swap_type" == "partition" ]]; then
            warn "Обнаружен раздел подкачки. Его размер нельзя изменить этим скриптом."
            if ask_yes_no "Отключить раздел и создать файл подкачки?" "n"; then
                info "Отключение раздела $existing_swap..."
                if ! swapoff "$existing_swap"; then
                    err "Не удалось отключить раздел подкачки."
                    return 1
                fi
                cp /etc/fstab "/etc/fstab.backup_$(date +%Y%m%d_%H%M%S)"
                # Комментируем в fstab
                sed -i "s|^${existing_swap}[[:space:]]|#&|" /etc/fstab
                local swap_uuid
                swap_uuid=$(blkid -s UUID -o value "$existing_swap" 2>/dev/null || true)
                if [[ -n "$swap_uuid" ]]; then
                    sed -i "s|^UUID=${swap_uuid}[[:space:]]|#&|" /etc/fstab
                fi
                ok "Раздел подкачки отключен."
                existing_swap=""
            else
                info "Оставляем существующий раздел."
                _configure_swap_settings
                [[ $VERBOSE == true ]] && wait_for_enter
                return 0
            fi
        else
            # Это файл подкачки - можно изменить размер (сохраняем исходный путь, например /swap.img)
            if ask_yes_no "Изменить размер файла подкачки?" "n"; then
                local required_mb
                required_mb=$(_ask_swap_size_mb "${swap_size_mb}M") || return 1
                
                info "Изменение размера $existing_swap до ${required_mb}M..."
                if ! swapoff "$existing_swap"; then
                    err "Не удалось отключить swap (недостаточно RAM для выгрузки?)."
                    return 1
                fi
                _create_swap_file "$existing_swap" "$required_mb" || return 1
                ok "Файл подкачки изменен: ${required_mb}M"
            else
                info "Оставляем текущий размер."
            fi
        fi
    fi
    
    # Создание нового swap файла
    if [[ -z "$existing_swap" ]]; then
        if ! ask_yes_no "Настроить файл подкачки (рекомендуется при RAM < 4GB)?" "y"; then
            info "Пропуск настройки Swap."
            return 0
        fi
        
        local required_mb
        required_mb=$(_ask_swap_size_mb "2G") || return 1
        
        info "Создание swap файла /swapfile размером ${required_mb}M..."
        _create_swap_file /swapfile "$required_mb" || return 1
        ok "Swap файл создан: ${required_mb}M"
    fi
    
    # Настройка параметров ядра для swap
    _configure_swap_settings
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_swap_settings() {
    info "Настройка параметров Swap..."
    local swappiness=10
    local cache_pressure=50
    local input
    
    if ask_yes_no "Настроить параметры (vm.swappiness и vm.vfs_cache_pressure)?" "y"; then
        while true; do
            read -rp "$(printf '%s' "${CYAN}Введите vm.swappiness (0-100) [по умолчанию: $swappiness]: ${NC}")" input
            input=${input:-$swappiness}
            if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 0 && input <= 100 )); then
                swappiness=$input
                break
            else
                err "Неверное значение (0-100)."
            fi
        done
        
        while true; do
            read -rp "$(printf '%s' "${CYAN}Введите vm.vfs_cache_pressure (1-1000) [по умолчанию: $cache_pressure]: ${NC}")" input
            input=${input:-$cache_pressure}
            if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 1000 )); then
                cache_pressure=$input
                break
            else
                err "Неверное значение (1-1000)."
            fi
        done
    else
        info "Используются настройки по умолчанию (vm.swappiness=$swappiness, vm.vfs_cache_pressure=$cache_pressure)."
    fi
    
    _write_swap_sysctl "$swappiness" "$cache_pressure"
}

# Запись и применение vm.swappiness / vm.vfs_cache_pressure
_write_swap_sysctl() {
    local swappiness="$1" cache_pressure="$2"
    local swap_config="/etc/sysctl.d/99-swap.conf"
    local tmp_conf
    tmp_conf=$(mktemp)
    cat > "$tmp_conf" <<EOF
vm.swappiness=$swappiness
vm.vfs_cache_pressure=$cache_pressure
EOF
    
    if [[ -f "$swap_config" ]] && cmp -s "$tmp_conf" "$swap_config"; then
        info "Настройки Swap уже применены."
        rm -f "$tmp_conf"
    else
        mv "$tmp_conf" "$swap_config"
        chmod 644 "$swap_config"
        if sysctl -e -p "$swap_config" >/dev/null 2>&1; then
            ok "Настройки Swap применены."
        else
            warn "Не удалось применить настройки sysctl (контейнер?)."
        fi
    fi
}

_configure_time_sync() {
    print_section "Синхронизация времени"
    
    info "Проверка chrony..."
    if ! dpkg -l chrony 2>/dev/null | grep -q ^ii; then
        info "Установка chrony..."
        if ! run_cmd "apt-get install -y chrony"; then
            err "Не удалось установить chrony."
            return 1
        fi
    fi
    
    info "Включение и запуск chrony..."
    systemctl enable --now chrony >/dev/null 2>&1
    sleep 2
    
    if systemctl is-active --quiet chrony; then
        ok "Chrony активен и синхронизирует время."
        chronyc tracking 2>&1 | tee -a "$LOG_FILE" | head -10
    else
        err "Служба chrony не запустилась."
        return 1
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_resource_management_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "⚙️ Ресурсы (Swap/Время)"
        printf_description "Настройка файла подкачки и синхронизации времени."
        
        printf_menu_option "1" "Настроить Swap"
        printf_menu_option "2" "Настроить синхронизацию времени"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _configure_swap ;;
            2) _configure_time_sync ;;
            b|B) break ;;
            *) err "Нет такого пункта." ;;
        esac
    done
    disable_graceful_ctrlc
}
