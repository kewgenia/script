#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: ОБНОВЛЕНИЕ СИСТЕМЫ                  == #
# ============================================================ #
#
# @menu.manifest
# @item( main | 1 | 🔄 Обновление системы | show_system_update_menu | 10 | 10 | Обновление пакетов Debian/Ubuntu )
# @item( system_update | 1 | Обновить списки пакетов | _update_package_lists | 10 | 10 | apt-get update )
# @item( system_update | 2 | Обновить установленные пакеты | _upgrade_packages | 20 | 10 | apt-get upgrade )
# @item( system_update | 3 | Дистрибутивное обновление | _dist_upgrade | 30 | 10 | apt-get dist-upgrade )
# @item( system_update | 4 | Удалить ненужные пакеты | _autoremove_packages | 40 | 10 | apt-get autoremove )
# @item( system_update | 5 | Очистить кэш пакетов | _clean_cache | 50 | 10 | apt-get clean && autoclean )
# @item( system_update | 6 | ПОЛНОЕ ОБНОВЛЕНИЕ (Все пункты) | _full_system_update | 60 | 20 | Выполнить все действия последовательно )
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
    wait_for_enter
}

_upgrade_packages() {
    info "Обновление установленных пакетов..."
    if run_cmd "apt-get upgrade -y"; then
        ok "Пакеты успешно обновлены."
    else
        err "Не удалось обновить пакеты."
    fi
    wait_for_enter
}

_dist_upgrade() {
    info "Выполнение дистрибутивного обновления..."
    if run_cmd "apt-get dist-upgrade -y"; then
        ok "Дистрибутивное обновление успешно завершено."
    else
        warn "Дистрибутивное обновление завершилось с предупреждениями."
    fi
    wait_for_enter
}

_autoremove_packages() {
    info "Удаление ненужных пакетов..."
    if run_cmd "apt-get autoremove -y"; then
        ok "Ненужные пакеты успешно удалены."
    else
        warn "Не удалось удалить некоторые пакеты."
    fi
    wait_for_enter
}

_clean_cache() {
    info "Очистка кэша пакетов..."
    if run_cmd "apt-get clean && apt-get autoclean -y"; then
        ok "Кэш пакетов успешно очищен."
    else
        warn "Не удалось очистить кэш."
    fi
    wait_for_enter
}

_full_system_update() {
    if ! ask_yes_no "Вы уверены, что хотите выполнить ПОЛНОЕ обновление системы?"; then
        info "Отменено пользователем."
        wait_for_enter
        return
    fi
    
    _update_package_lists
    _upgrade_packages
    _dist_upgrade
    _autoremove_packages
    _clean_cache
    
    ok "ПОЛНОЕ ОБНОВЛЕНИЕ СИСТЕМЫ ЗАВЕРШЕНО!"
    wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_system_update_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🔄 Обновление системы"
        printf_description "Выберите действие для обновления вашей системы Debian/Ubuntu."

        printf_menu_option "1" "Обновить списки пакетов"
        printf_menu_option "2" "Обновить установленные пакеты"
        printf_menu_option "3" "Дистрибутивное обновление"
        printf_menu_option "4" "Удалить ненужные пакеты"
        printf_menu_option "5" "Очистить кэш пакетов"
        printf_menu_option "6" "ПОЛНОЕ ОБНОВЛЕНИЕ (Все пункты)"
        printf_menu_option "b" "Назад в главное меню"

        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _update_package_lists ;;
            2) _upgrade_packages ;;
            3) _dist_upgrade ;;
            4) _autoremove_packages ;;
            5) _clean_cache ;;
            6) _full_system_update ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
