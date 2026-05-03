#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: ОБНОВЛЕНИЕ СИСТЕМЫ                  == #
# ============================================================ #
# Обновление пакетов, очистка системы и проверка перезагрузки.
# Версия: 2.0.0

#
# @menu.manifest
#
# @item( main | 1 | 🔄 Обновление системы | show_system_update_menu | 10 | 10 | Обновление пакетов Debian/Ubuntu )
# @item( system_update | 1 | Обновить списки пакетов | _update_package_lists | 10 | 10 | apt-get update )
# @item( system_update | 2 | Обновить установленные пакеты | _upgrade_packages | 20 | 10 | apt-get upgrade )
# @item( system_update | 3 | Удалить ненужные пакеты | _autoremove_packages | 30 | 10 | apt-get autoremove )
# @item( system_update | 4 | Очистить кэш пакетов | _clean_cache | 40 | 10 | apt-get clean && autoclean )
# @item( system_update | 5 | Проверить необходимость перезагрузки | _check_reboot_required | 50 | 10 | Проверка /var/run/reboot-required )
# @item( system_update | 6 | ПОЛНОЕ ОБНОВЛЕНИЕ (Все пункты) | _full_system_update | 60 | 20 | Выполнить пункты 1-4 + проверка перезагрузки )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_update_package_lists() {
    info "Обновление списков пакетов..."
    if run_cmd "apt-get update"; then
        ok "Списки пакетов успешно обновлены."
    else
        err "Не удалось обновить списки пакетов."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_upgrade_packages() {
    info "Обновление установленных пакетов..."
    if run_cmd "apt-get upgrade -y"; then
        ok "Пакеты успешно обновлены."
    else
        err "Не удалось обновить пакеты."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_check_reboot_required() {
    info "Проверка необходимости перезагрузки..."
    if [[ -f /var/run/reboot-required ]]; then
        warn "⚠️  ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА СИСТЕМЫ!"
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            info "Пакеты, требующие перезагрузки:"
            while IFS= read -r pkg; do
                echo -e "  ${CYAN}- $pkg${NC}"
            done < /var/run/reboot-required.pkgs
        fi
    else
        ok "Перезагрузка не требуется."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_autoremove_packages() {
    info "Удаление ненужных пакетов..."
    if run_cmd "apt-get autoremove -y"; then
        ok "Ненужные пакеты успешно удалены."
    else
        warn "Не удалось удалить некоторые пакеты."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_clean_cache() {
    info "Очистка кэша пакетов..."
    if run_cmd "apt-get clean && apt-get autoclean -y"; then
        ok "Кэш пакетов успешно очищен."
    else
        warn "Не удалось очистить кэш."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_full_system_update() {
    if ! ask_yes_no "Вы уверены, что хотите выполнить ПОЛНОЕ обновление системы?"; then
        info "Отменено пользователем."
        [[ $VERBOSE == true ]] && wait_for_enter
        return
    fi
    
    _update_package_lists
    _upgrade_packages
    _autoremove_packages
    _clean_cache
    _check_reboot_required
    
    ok "ПОЛНОЕ ОБНОВЛЕНИЕ СИСТЕМЫ ЗАВЕРШЕНО!"
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_system_update_menu() {
    local menu_id="system_update"
    
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "🔄 Обновление системы"
        printf_description "Выберите действие для обновления вашей системы Debian/Ubuntu."
        
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
