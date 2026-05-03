#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: НАСТРОЙКА ФАЕРВОЛА (UFW)       == #
# ============================================================ #
# Управление UFW, открытие портов, поддержка IPv6.
# Версия: 1.0.0

#
# @menu.manifest
#
# @item( main | 4 | 🛡️ Фаервол (UFW) | show_firewall_menu | 40 | 40 | Настройка брандмауэра )
# @item( firewall | 1 | Включить/Выключить UFW | _toggle_ufw | 10 | 10 | Изменение статуса фаервола )
# @item( firewall | 2 | Открыть порт | _allow_port | 20 | 10 | Добавление правила для порта )
# @item( firewall | 3 | Закрыть порт | _deny_port | 30 | 10 | Удаление правила )
# @item( firewall | 4 | Настроить IPv6 поддержку | _configure_ipv6 | 40 | 10 | Включение IPv6 в UFW )
# @item( firewall | 5 | Статус фаервола | _ufw_status | 50 | 10 | Просмотр текущих правил )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_ufw_is_active() {
    ufw status 2>/dev/null | grep -q "Status: active"
    return $?
}

_validate_port_format() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+(/(tcp|udp))?$ ]]; then
        return 0
    else
        return 1
    fi
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_toggle_ufw() {
    if _ufw_is_active; then
        info "UFW уже активен."
        if ask_yes_no "Выключить UFW?" "n"; then
            if run_cmd "ufw --force disable"; then
                ok "UFW выключен."
            else
                err "Не удалось выключить UFW."
            fi
        fi
    else
        info "UFW не активен."
        if ask_yes_no "Включить UFW?" "y"; then
            # Устанавливаем дефолтные политики
            run_cmd "ufw default deny incoming"
            run_cmd "ufw default allow outgoing"
            # Разрешаем SSH порт (берем из ssh_hardening переменных или 22)
            local ssh_port=${NEW_SSH_PORT:-22}
            if ! ufw status | grep -qw "$ssh_port/tcp"; then
                run_cmd "ufw allow $ssh_port/tcp comment 'SSH'"
            fi
            if run_cmd "ufw --force enable"; then
                ok "UFW включен."
            else
                err "Не удалось включить UFW."
            fi
        fi
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_allow_port() {
    if ! _ufw_is_active; then
        warn "UFW не активен. Сначала включите его."
        return 1
    fi
    local port comment
    read -rp "$(printf '%s' "${CYAN}Введите порт (например, 80/tcp или 443): ${NC}")" port
    if [[ -z "$port" ]]; then
        err "Порт не может быть пустым."
        return 1
    fi
    if ! _validate_port_format "$port"; then
        err "Неверный формат порта. Используйте <порт> или <порт>/<протокол>."
        return 1
    fi
    if ufw status | grep -qw "$port"; then
        warn "Правило для $port уже существует."
        return 0
    fi
    read -rp "$(printf '%s' "${CYAN}Введите комментарий (необязательно): ${NC}")" comment
    if [[ -z "$comment" ]]; then
        comment="Custom port $port"
    fi
    if run_cmd "ufw allow $port comment '$comment'"; then
        ok "Порт $port открыт."
        log "Добавлено правило UFW для $port с комментарием '$comment'."
    else
        err "Не удалось добавить правило для $port."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_deny_port() {
    if ! _ufw_is_active; then
        warn "UFW не активен."
        return 1
    fi
    local port
    read -rp "$(printf '%s' "${CYAN}Введите порт для закрытия: ${NC}")" port
    if [[ -z "$port" ]]; then
        err "Порт не может быть пустым."
        return 1
    fi
    if ufw status | grep -qw "$port"; then
        if run_cmd "ufw delete allow $port"; then
            ok "Правило для $port удалено."
            log "Удалено правило UFW для $port."
        else
            err "Не удалось удалить правило."
        fi
    else
        warn "Правило для $port не найдено."
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_ipv6() {
    local ufw_default="/etc/default/ufw"
    if [[ ! -f "$ufw_default" ]]; then
        err "Файл $ufw_default не найден."
        return 1
    fi
    if grep -q '^IPV6=yes' "$ufw_default"; then
        info "IPv6 поддержка в UFW уже включена."
        if ask_yes_no "Выключить IPv6 поддержку?" "n"; then
            sed -i 's/^IPV6=yes/IPV6=no/' "$ufw_default"
            ok "IPv6 поддержка выключена."
        fi
    else
        info "IPv6 поддержка в UFW выключена."
        if ask_yes_no "Включить IPv6 поддержку?" "y"; then
            if grep -q '^IPV6=' "$ufw_default"; then
                sed -i 's/^IPV6=.*/IPV6=yes/' "$ufw_default"
            else
                echo "IPV6=yes" >> "$ufw_default"
            fi
            ok "IPv6 поддержка включена."
            warn "Перезапустите UFW для применения изменений."
            log "Включена IPv6 поддержка в UFW."
        fi
    fi
    [[ $VERBOSE == true ]] && wait_for_enter
}

_ufw_status() {
    if ! command -v ufw >/dev/null 2>&1; then
        err "UFW не установлен."
        return 1
    fi
    menu_header "Статус UFW"
    ufw status verbose 2>/dev/null | tee -a "$LOG_FILE"
    echo ""
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_firewall_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🛡️ Настройка фаервола (UFW)"
        printf_description "Управление брандмауэром Uncomplicated Firewall."
        
        printf_menu_option "1" "Включить/Выключить UFW"
        printf_menu_option "2" "Открыть порт"
        printf_menu_option "3" "Закрыть порт"
        printf_menu_option "4" "Настроить IPv6 поддержку"
        printf_menu_option "5" "Статус фаервола"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _toggle_ufw ;;
            2) _allow_port ;;
            3) _deny_port ;;
            4) _configure_ipv6 ;;
            5) _ufw_status ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
