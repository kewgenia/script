#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: УПРАВЛЕНИЕ РЕСУРСАМИ         == #
# ============================================================ #
# Настройка Swap, синхронизация времени (chrony).
# Версия: 1.0.0.

#
# @menu.manifest
#
# @item( main | 10 | ⚙️ Ресурсы (Swap/Время) | show_resource_management_menu | 100 | 100 | Swap и синхронизация времени )
# @item( resource_management | 1 | Настроить Swap | _configure_swap | 10 | 10 | Swap файл или раздел )
# @item( resource_management | 2 | Настроить синхронизацию времени | _configure_time_sync | 20 | 10 | chrony setup )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_convert_to_mb() {
    local size_str="$1"
    local size_num unit
    size_num=$(echo "$size_str" | sed 's/[^0-9]//g')
    unit=$(echo "$size_str" | sed 's/[0-9]//g' | tr -d '[:space:]')
    
    case "$unit" in
        G|g) echo $((size_num * 1024)) ;;
        M|m) echo "$size_num" ;;
        K|k) echo $((size_num / 1024)) ;;
        *) echo "$size_num" ;;
    esac
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_configure_swap() {
    local section="Настройка Swap"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    # Проверка на контейнер
    if [[ "${IS_CONTAINER:-false}" == "true" ]]; then
        info "В контейнере Swap не настраивается."
        return 0
    fi
    
    # Проверка существующего swap
    local existing_swap swap_type display_size
    existing_swap=$(swapon --show=NAME,TYPE,SIZE --noheadings --bytes 2>/dev/null | head -n 1 | awk '{print $1}')
    
    if [[ -n "$existing_swap" ]]; then
        swap_type=$(swapon --show=NAME,TYPE,SIZE --noheadings | head -n 1 | awk '{print $2}')
        display_size=$(du -h "$existing_swap" 2>/dev/null | awk '{print $1}' || echo "Unknown")
        info "Обнаружен Swap: $existing_swap (Тип: $swap_type, Размер: $display_size)"
        
        if [[ "$swap_type" == "partition" ]] || [[ "$existing_swap" =~ ^/dev/ ]]; then
            warn "Обнаружен раздел подкачки. Его размер нельзя изменить этим скриптом."
            if ask_yes_no "Отключить раздел и создать файл подкачки?" "n"; then
                info "Отключение раздела $existing_swap..."
                if ! swapoff "$existing_swap"; then
                    err "Не удалось отключить раздел подкачки."
                    return 1
                fi
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
                return 0
            fi
        else
            # Это файл подкачки - можно изменить размер
            if ask_yes_no "Изменить размер файла подкачки?" "y"; then
                local swap_size required_mb
                while true; do
                    read -rp "$(printf '%s' "${CYAN}Введите новый размер (например, 2G, 512M) [текущий: $display_size]: ${NC}")" swap_size
                    swap_size=${swap_size:-$display_size}
                    
                    if ! required_mb=$(_convert_to_mb "$swap_size"); then
                        err "Неверный формат размера."
                        continue
                    fi
                    if (( required_mb < 128 )); then
                        err "Минимальный размер: 128M."
                        continue
                    fi
                    # Проверка места на диске
                    local avail_kb avail_mb
                    avail_kb=$(df -k / | tail -n 1 | awk '{print $4}')
                    avail_mb=$((avail_kb / 1024))
                    if (( avail_mb < required_mb )); then
                        err "Недостаточно места. Нужно: ${required_mb}MB, Доступно: ${avail_mb}MB"
                        local max_safe_mb=$(( avail_mb * 80 / 100 ))
                        if (( max_safe_mb >= 128 )); then
                            info "Предлагаемый максимум: ${max_safe_mb}M (оставляет 20% свободного места)"
                        fi
                        continue
                    fi
                    break
                done
                
                info "Изменение размера файла подкачки до $swap_size..."
                swapoff "$existing_swap" || true
                rm -f "$existing_swap" 2>/dev/null || true
                
                # Создание нового файла
                if ! fallocate -l "$swap_size" /swapfile 2>/dev/null; then
                    warn "fallocate не удался. Используем dd..."
                    local dd_status=""
                    if dd --version 2>&1 | grep -q "progress"; then dd_status="status=progress"; fi
                    dd if=/dev/zero of=/swapfile bs=1M count="$required_mb" $dd_status 2>/dev/null || true
                fi
                
                chmod 600 /swapfile
                mkswap /swapfile >/dev/null 2>&1
                swapon /swapfile
                
                # Обновление fstab
                if ! grep -q '^/swapfile ' /etc/fstab; then
                    echo '/swapfile none swap sw 0 0' >> /etc/fstab
                fi
                ok "Файл подкачки изменен: $swap_size"
            else
                info "Оставляем текущий размер."
            fi
            return 0
        fi
    fi
    
    # Создание нового swap файла
    if [[ -z "$existing_swap" ]]; then
        if ! ask_yes_no "Настроить файл подкачки (рекомендуется при RAM < 4GB)?" "y"; then
            info "Пропуск настройки Swap."
            return 0
        fi
        
        local swap_size required_mb
        while true; do
            read -rp "$(printf '%s' "${CYAN}Введите размер swap файла (например, 2G, 512M) [2G]: ${NC}")" swap_size
            swap_size=${swap_size:-2G}
            
            if ! required_mb=$(_convert_to_mb "$swap_size"); then
                err "Неверный формат размера."
                continue
            fi
            if (( required_mb < 128 )); then
                err "Минимальный размер: 128M."
                continue
            fi
            # Проверка места на диске
            local avail_kb avail_mb
            avail_kb=$(df -k / | tail -n 1 | awk '{print $4}')
            avail_mb=$((avail_kb / 1024))
            if (( avail_mb < required_mb )); then
                err "Недостаточно места. Нужно: ${required_mb}MB, Доступно: ${avail_mb}MB"
                local max_safe_mb=$(( avail_mb * 80 / 100 ))
                if (( max_safe_mb >= 128 )); then
                    info "Предлагаемый максимум: ${max_safe_mb}M (оставляет 20% свободного места)"
                fi
                continue
            fi
            break
        done
        
        info "Создание swap файла размером $swap_size..."
        if ! fallocate -l "$swap_size" /swapfile 2>/dev/null; then
            warn "fallocate не удался. Используем dd..."
            local dd_status=""
            if dd --version 2>&1 | grep -q "progress"; then dd_status="status=progress"; fi
            dd if=/dev/zero of=/swapfile bs=1M count="$required_mb" $dd_status 2>/dev/null || true
        fi
        
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile
        
        if ! grep -q '^/swapfile ' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            ok "Запись добавлена в /etc/fstab."
        fi
        ok "Swap файл создан: $swap_size"
    fi
    
    # Настройка параметров ядра для swap
    _configure_swap_settings
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_swap_settings() {
    info "Настройка параметров Swap..."
    local swappiness=10
    local cache_pressure=50
    
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
    
    local swap_config="/etc/sysctl.d/99-swap.conf"
    cat > /tmp/swap-settings.conf <<EOF
vm.swappiness=$swappiness
vm.vfs_cache_pressure=$cache_pressure
EOF
    
    if [[ -f "$swap_config" ]] && cmp -s /tmp/swap-settings.conf "$swap_config"; then
        info "Настройки Swap уже применены."
        rm -f /tmp/swap-settings.conf
    else
        mv /tmp/swap-settings.conf "$swap_config"
        chmod 644 "$swap_config"
        sysctl -p "$swap_config" >/dev/null 2>&1
        ok "Настройки Swap применены."
    fi
}

_configure_time_sync() {
    local section="Синхронизация времени"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    info "Проверка chrony..."
    if ! dpkg -l chrony 2>/dev/null | grep -q ^ii; then
        info "Установка chrony..."
        if ! run_cmd "apt-get install -y chrony"; then
            err "Не удалось установить chrony."
            return 1
        fi
    fi
    
    info "Включение и запуск chrony..."
    systemctl enable --now chrony
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
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
