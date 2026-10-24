#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: АВТООБНОВЛЕНИЯ                == #
# ============================================================ #
# Настройка автоматических обновлений безопасности.
# Версия: 1.1.0

#
# @menu.manifest
#
# @item( main | 6 | 🔄 Автообновления | show_auto_updates_menu | 60 | 10 | Настройка unattended-upgrades )
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

AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
UNATTENDED_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
UNATTENDED_LOCAL_CONF="/etc/apt/apt.conf.d/52unattended-upgrades-local"

_auto_updates_enabled() {
    [[ -f "$AUTO_UPGRADES_FILE" ]] && grep -qE 'APT::Periodic::Unattended-Upgrade[[:space:]]+"1"' "$AUTO_UPGRADES_FILE"
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_enable_auto_updates() {
    print_section "Настройка автообновлений"
    
    # Проверка установки unattended-upgrades
    if ! _check_unattended_installed; then
        if ask_yes_no "Пакет unattended-upgrades не установлен. Установить?" "y"; then
            if ! run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades apt-listchanges"; then
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
    
    if _auto_updates_enabled; then
        ok "Автообновления уже включены ($AUTO_UPGRADES_FILE)."
    else
        # Именно этот файл включает ежедневный запуск unattended-upgrade
        cat > "$AUTO_UPGRADES_FILE" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
        chmod 644 "$AUTO_UPGRADES_FILE"
        ok "Автообновления включены: $AUTO_UPGRADES_FILE"
        log "Automatic security updates enabled."
    fi
    
    # Таймеры apt, запускающие обновления
    systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
    systemctl enable unattended-upgrades >/dev/null 2>&1 || true
    
    info "Проверка конфигурации (dry-run)..."
    if unattended-upgrade --dry-run >> "$LOG_FILE" 2>&1; then
        ok "Проверка unattended-upgrade прошла успешно."
    else
        warn "unattended-upgrade --dry-run завершился с ошибкой. Проверьте $LOG_FILE"
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_check_auto_updates_status() {
    menu_header "Статус автообновлений"
    
    if ! _check_unattended_installed; then
        warn "unattended-upgrades не установлен."
        [[ $VERBOSE == true ]] && wait_for_enter
        return 1
    fi
    
    if _auto_updates_enabled; then
        ok "Автообновления включены ($AUTO_UPGRADES_FILE)."
    else
        warn "Автообновления выключены ($AUTO_UPGRADES_FILE)."
    fi
    
    if [[ -f "$UNATTENDED_LOCAL_CONF" ]]; then
        info "Пользовательские параметры ($UNATTENDED_LOCAL_CONF):"
        grep -vE '^[[:space:]]*(//|$)' "$UNATTENDED_LOCAL_CONF"
    fi
    
    local timer
    for timer in apt-daily.timer apt-daily-upgrade.timer; do
        if systemctl is-enabled "$timer" >/dev/null 2>&1; then
            ok "Таймер $timer включен."
        else
            warn "Таймер $timer не включен."
        fi
    done
    
    if [[ -f /var/log/unattended-upgrades/unattended-upgrades.log ]]; then
        echo ""
        info "Последние записи лога:"
        tail -n 5 /var/log/unattended-upgrades/unattended-upgrades.log
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_auto_updates_params() {
    if ! _check_unattended_installed; then
        err "unattended-upgrades не установлен."
        return 1
    fi
    
    info "Настройка параметров автообновлений..."
    info "Параметры записываются в $UNATTENDED_LOCAL_CONF (дополняет $UNATTENDED_CONF)."
    
    local auto_reboot="false" reboot_time="03:00"
    if ask_yes_no "Автоматически перезагружать сервер, если это требуется после обновления?" "n"; then
        auto_reboot="true"
        local input
        input=$(safe_read "Время перезагрузки (ЧЧ:ММ) [$reboot_time]: ") || return 1
        input="${input:-$reboot_time}"
        if [[ ! "$input" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            err "Неверный формат времени."
            return 1
        fi
        reboot_time="$input"
    fi
    
    local remove_unused="true"
    ask_yes_no "Удалять неиспользуемые зависимости после обновления?" "y" || remove_unused="false"
    
    if [[ -f "$UNATTENDED_LOCAL_CONF" ]]; then
        cp "$UNATTENDED_LOCAL_CONF" "${UNATTENDED_LOCAL_CONF}.backup_$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Список источников (Origins-Pattern) не трогаем: дистрибутивный
    # 50unattended-upgrades уже корректно настроен для security-обновлений.
    cat > "$UNATTENDED_LOCAL_CONF" <<EOF
// Сгенерировано Server Setup $(date '+%Y-%m-%d %H:%M:%S')
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "$remove_unused";
Unattended-Upgrade::Automatic-Reboot "$auto_reboot";
Unattended-Upgrade::Automatic-Reboot-Time "$reboot_time";
EOF
    chmod 644 "$UNATTENDED_LOCAL_CONF"
    
    ok "Параметры автообновлений настроены."
    log "Unattended-upgrades params: reboot=$auto_reboot at $reboot_time, remove_unused=$remove_unused"
    
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
            *) err "Нет такого пункта." ;;
        esac
    done
    disable_graceful_ctrlc
}
