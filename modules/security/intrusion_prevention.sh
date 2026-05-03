#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: ЗАЩИТА (FAIL2BAN/CROWDSEC)    == #
# ============================================================ #
# Настройка Fail2Ban или CrowdSec для защиты от брутфорса.
# Версия: 1.0.0

#
# @menu.manifest
#
# @item( main | 5 | 🛡️ Защита (Fail2Ban/CrowdSec) | show_intrusion_prevention_menu | 50 | 50 | Защита от брутфорса )
# @item( intrusion_prevention | 1 | Настроить Fail2Ban | _configure_fail2ban | 10 | 10 | Классическая защита )
# @item( intrusion_prevention | 2 | Настроить CrowdSec | _configure_crowdsec | 20 | 10 | Современная защита )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_validate_ip_or_cidr() {
    local input="$1"
    # Простая проверка IP или CIDR
    if [[ "$input" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]+)?$ ]] || \
       [[ "$input" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}(/[0-9]+)?$ ]]; then
        return 0
    else
        return 1
    fi
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_configure_fail2ban() {
    local section="Настройка Fail2Ban"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    # Установка Fail2Ban
    if ! dpkg -l fail2ban 2>/dev/null | grep -q ^ii; then
        info "Установка Fail2Ban..."
        if ! run_cmd "apt-get install -y fail2ban"; then
            err "Не удалось установить Fail2Ban."
            return 1
        fi
    else
        info "Fail2Ban уже установлен."
    fi
    
    # Сбор IP для игнорирования
    local -a ignore_ips=("127.0.0.1/8" "::1")
    local detected_ip=""
    
    # Пытаемся определить текущий IP подключения
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        detected_ip=$(echo "$SSH_CONNECTION" | awk '{print $1}')
    fi
    if [[ -z "$detected_ip" ]]; then
        detected_ip=$(who -m 2>/dev/null | awk '{print $NF}' | tr -d '()')
    fi
    if [[ -n "$detected_ip" ]] && _validate_ip_or_cidr "$detected_ip"; then
        info "Обнаружен IP текущего подключения: $detected_ip"
        if ask_yes_no "Добавить этот IP в игнор-лист Fail2Ban?" "y"; then
            ignore_ips+=("$detected_ip")
        fi
    fi
    
    # Запрос дополнительных IP
    if ask_yes_no "Добавить дополнительные IP или CIDR в игнор-лист?" "n"; then
        while true; do
            local -a add_ips
            read -rp "$(printf '%s' "${CYAN}Введите IP/CIDR (через пробел): ${NC}")" -a add_ips
            if (( ${#add_ips[@]} == 0 )); then
                break
            fi
            local valid=true
            for ip in "${add_ips[@]}"; do
                if ! _validate_ip_or_cidr "$ip"; then
                    warn "Неверный формат: $ip"
                    valid=false
                    break
                fi
            done
            if [[ "$valid" == true ]]; then
                ignore_ips+=("${add_ips[@]}")
                break
            fi
        done
    fi
    
    # Создание конфигурации
    local jail_local="/etc/fail2ban/jail.local"
    local ufw_filter="/etc/fail2ban/filter.d/ufw-probes.conf"
    
    # UFW probes filter
    mkdir -p /etc/fail2ban/filter.d
    cat > "$ufw_filter" <<'EOF'
[Definition]
# Ищет сообщения [UFW BLOCK] в логах
failregex = \[UFW BLOCK\] IN=.* OUT=.* SRC=<HOST>
ignoreregex =
EOF
    
    # jail.local
    local ignore_ip_str="${ignore_ips[*]}"
    cat > "$jail_local" <<EOF
[DEFAULT]
ignoreip = $ignore_ip_str
bantime = 1d
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ${NEW_SSH_PORT:-22}

[ufw-probes]
enabled = true
port = all
filter = ufw-probes
logpath = /var/log/ufw.log
maxretry = 3
EOF
    
    # Создание лог-файла если нет
    if [[ ! -f /var/log/ufw.log ]]; then
        touch /var/log/ufw.log
        log "Создан /var/log/ufw.log для Fail2Ban."
    fi
    
    # Перезапуск
    info "Перезапуск Fail2Ban..."
    systemctl enable fail2ban
    if systemctl restart fail2ban; then
        ok "Fail2Ban активирован и настроен."
        fail2ban-client status 2>&1 | tee -a "$LOG_FILE"
    else
        err "Не удалось запустить Fail2Ban. Проверьте 'journalctl -u fail2ban'."
        return 1
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_crowdsec() {
    local section="Настройка CrowdSec"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    # Установка CrowdSec
    if ! command -v crowdsec >/dev/null 2>&1; then
        info "Настройка репозитория CrowdSec..."
        if ! curl -s https://install.crowdsec.net | sh >> "$LOG_FILE" 2>&1; then
            err "Не удалось настроить репозиторий CrowdSec."
            return 1
        fi
        info "Установка агента CrowdSec..."
        if ! run_cmd "apt-get install -y crowdsec"; then
            err "Не удалось установить CrowdSec."
            return 1
        fi
        ok "CrowdSec агент установлен."
    else
        info "CrowdSec уже установлен."
    fi
    
    # Установка bouncer (iptables)
    if ! dpkg -l crowdsec-firewall-bouncer-iptables 2>/dev/null | grep -q ^ii; then
        info "Установка firewall bouncer..."
        if ! run_cmd "apt-get install -y crowdsec-firewall-bouncer-iptables"; then
            warn "Не удалось установить bouncer. CrowdSec будет обнаруживать, но не блокировать."
        else
            ok "Firewall bouncer установлен."
        fi
    fi
    
    # Базовые коллекции
    info "Установка базовых коллекций (Linux & Iptables)..."
    if cscli collections install crowdsecurity/linux crowdsecurity/iptables 2>&1 | tee -a "$LOG_FILE"; then
        ok "Базовые коллекции установлены."
    else
        warn "Не удалось установить коллекции."
    fi
    
    # Настройка мониторинга UFW логов
    mkdir -p /etc/crowdsec/acquis.d
    if [[ ! -f /var/log/ufw.log ]]; then
        touch /var/log/ufw.log
    fi
    cat > /etc/crowdsec/acquis.d/ufw.yaml <<EOF
filenames:
  - /var/log/ufw.log
labels:
  type: syslog
EOF
    ok "Добавлен мониторинг /var/log/ufw.log в CrowdSec."
    
    # Перезапуск
    info "Перезапуск CrowdSec..."
    systemctl restart crowdsec
    sleep 2
    if systemctl is-active --quiet crowdsec; then
        ok "CrowdSec активен."
        info "Полезные команды:"
        info "  sudo cscli metrics"
        info "  sudo cscli decisions list"
        info "  sudo cscli collections list"
    else
        err "CrowdSec не запустился. Проверьте 'journalctl -u crowdsec'."
        return 1
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_intrusion_prevention_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🛡️ Защита (Fail2Ban/CrowdSec)"
        printf_description "Настройка защиты от брутфорса."
        
        printf_menu_option "1" "Настроить Fail2Ban"
        printf_menu_option "2" "Настроить CrowdSec"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _configure_fail2ban ;;
            2) _configure_crowdsec ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
