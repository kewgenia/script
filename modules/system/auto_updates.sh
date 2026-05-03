#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: АВТООБНОВЛЕНИЯ                == #
# ============================================================ #
# Настройка автоматических обновлений безопасности.
# Версия: 1.0.0

#
# @menu.manifest
#
# @item( main | 6 | 🔄 Автообновления | show_auto_updates_menu | 60 | 60 | Настройка unattended-upgrades )
# @item( auto_updates | 1 | Включить автообновления | _enable_auto_updates | 10 | 10 | Настройка unattended-upgrades )
# @item( auto_updates | 2 | Проверить статус | _check_auto_updates_status | 20 | 10 | Проверка конфигурации )
# @item( auto_updates | 3 | Настроить параметры | _configure_auto_updates_params | 30 | 10 | Изменение настроек )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_check_unattended_installed() {
    if ! dpkg -l unattended-upgrades 2>/dev/null | grep -q ^ii; then
        return 1
    fi
    return 0
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_enable_auto_updates() {
    local section="Настройка автообновлений"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    # Проверка установки unattended-upgrades
    if ! _check_unattended_installed; then
        if ask_yes_no "Пакет unattended-upgrades не установлен. Установить?" "y"; then
            if ! run_cmd "apt-get install -y unattended-upgrades"; then
                err "Не удалось установить unattended-upgrades."
                return 1
            fi
            ok "unattended-upgrades установлен."
        else
            info "Пропуск настройки автообновлений."
            return 0
        fi
    else
        info "unattended-upgrades уже установлен."
    fi
    
    # Проверка существующей конфигурации
    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [[ -f "$config_file" ]] && grep -q "Unattended-Upgrade::Allowed-Origins" "$config_file"; then
        info "Конфигурация unattended-upgrades уже существует."
        if ! ask_yes_no "Перезаписать существующую конфигурацию?" "n"; then
            info "Используется существующая конфигурация."
            return 0
        fi
    fi
    
    # Настройка автообновлений
    info "Настройка автоматических обновлений..."
    
    # Используем debconf для настройки
    echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
    
    # Перенастройка пакета
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades
    
    # Проверка результата
    if [[ -f "$config_file" ]] && grep -q "Unattended-Upgrade::Allowed-Origins" "$config_file"; then
        ok "Автообновления успешно настроены."
        log "Automatic security updates enabled."
    else
        warn "Конфигурация может быть неполной. Проверьте $config_file"
    fi
    
    # Включение в автозагрузку
    systemctl enable unattended-upgrades 2>/dev/null || true
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_check_auto_updates_status() {
    menu_header "Статус автообновлений"
    
    if ! _check_unattended_installed; then
        warn "unattended-upgrades не установлен."
        return 1
    fi
    
    info "Проверка конфигурации..."
    
    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [[ -f "$config_file" ]]; then
        ok "Конфигурационный файл найден: $config_file"
        echo ""
        info "Содержимое конфигурации:"
        grep -v "^//" "$config_file" | grep -v "^$" | head -20
    else
        warn "Конфигурационный файл не найден."
    fi
    
    # Проверка службы
    if systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
        ok "Служба unattended-upgrades включена."
    else
        warn "Служба unattended-upgrades не включена."
    fi
    
    echo ""
    info "Для просмотра полной конфигурации выполните:"
    info "  cat $config_file"
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_auto_updates_params() {
    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    
    if ! _check_unattended_installed; then
        err "unattended-upgrades не установлен."
        return 1
    fi
    
    # Создание резервной копии
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.backup_$(date +%Y%m%d_%H%M%S)"
        ok "Создана резервная копия конфигурации."
    fi
    
    # Основные параметры для настройки
    info "Настройка параметров автообновлений..."
    
    # Пример создания базовой конфигурации
    cat > "$config_file" <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}:${distro_codename}-updates";
};

// Do automatic removal of new unused dependencies after the upgrade
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot system if any upgraded package requires it, via the
// "Install-Recommends" mechanism.
Unattended-Upgrade::Automatic-Reboot "false";

// If automatic reboot is enabled and needed, reboot at the specific
// time instead of random delay
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Send email to this address for problems or packages upgrades
// Unattended-Upgrade::Mail "root@localhost";
EOF
    
    ok "Параметры автообновлений настроены."
    info "Вы можете отредактировать файл: $config_file"
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_auto_updates_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🔄 Автообновления"
        printf_description "Настройка автоматических обновлений безопасности."
        
        printf_menu_option "1" "Включить автообновления"
        printf_menu_option "2" "Проверить статус"
        printf_menu_option "3" "Настроить параметры"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _enable_auto_updates ;;
            2) _check_auto_updates_status ;;
            3) _configure_auto_updates_params ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
