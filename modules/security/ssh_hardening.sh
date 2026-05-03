#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: НАСТРОЙКА SSH И 2FA            == #
# ============================================================ #
# Жесткая настройка SSH, управление портами, 2FA.
# Версия: 1.0.0

#
# @menu.manifest
#
# @item( main | 3 | 🔒 Настройка SSH и 2FA | show_ssh_hardening_menu | 30 | 30 | Безопасность SSH и двухфакторная аутентификация )
# @item( ssh_hardening | 1 | Настроить SSH (порт, ключи) | _configure_ssh | 10 | 10 | Изменение порта, отключение root )
# @item( ssh_hardening | 2 | Настроить 2FA (Google Authenticator) | _configure_2fa | 20 | 10 | Двухфакторная аутентификация )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ МОДУЛЯ ===
SSH_SERVICE=""
SSHD_BACKUP_FILE=""
CURRENT_SSH_PORT=22
NEW_SSH_PORT=22

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_print_section() {
    [[ $VERBOSE == false ]] && return
    printf '\n%s\n' "${BLUE}▓▓▓ $1 ▓▓▓${NC}" | tee -a "$LOG_FILE"
    printf '%s\n' "${BLUE}$(printf '═%.0s' {1..65})${NC}"
}

_detect_ssh_service() {
    if systemctl is-active ssh.socket >/dev/null 2>&1 || systemctl is-enabled ssh.socket >/dev/null 2>&1; then
        SSH_SERVICE="ssh.socket"
    elif systemctl is-active ssh.service >/dev/null 2>&1 || systemctl is-enabled ssh.service >/dev/null 2>&1; then
        SSH_SERVICE="ssh.service"
    elif systemctl is-active sshd.service >/dev/null 2>&1 || systemctl is-enabled sshd.service >/dev/null 2>&1; then
        SSH_SERVICE="sshd.service"
    else
        err "SSH сервис не обнаружен."
        return 1
    fi
    info "Обнаружен SSH сервис: $SSH_SERVICE"
    return 0
}

_get_current_ssh_port() {
    local port
    port=$(ss -tuln | grep ssh | awk '{print $5}' | grep -oE '[0-9]+$' | head -1)
    if [[ -z "$port" ]]; then
        port=$(grep -E "^Port\s+[0-9]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    fi
    if [[ -n "$port" ]]; then
        CURRENT_SSH_PORT=$port
    else
        CURRENT_SSH_PORT=22
    fi
    info "Текущий порт SSH: $CURRENT_SSH_PORT"
}

_backup_ssh_config() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    SSHD_BACKUP_FILE="$BACKUP_DIR/sshd_config.backup_$(date +%Y%m%d_%H%M%S)"
    if cp /etc/ssh/sshd_config "$SSHD_BACKUP_FILE" 2>/dev/null; then
        ok "Конфигурация SSH сохранена в $SSHD_BACKUP_FILE"
        log "SSH config backed up to $SSHD_BACKUP_FILE"
        return 0
    else
        err "Не удалось создать резервную копию sshd_config"
        return 1
    fi
}

_rollback_ssh() {
    warn "Откат изменений SSH..."
    if [[ -f "$SSHD_BACKUP_FILE" ]]; then
        cp "$SSHD_BACKUP_FILE" /etc/ssh/sshd_config
        ok "Восстановлен оригинальный sshd_config"
    fi
    rm -f /etc/ssh/sshd_config.d/10-hardening.conf 2>/dev/null
    rm -f /etc/systemd/system/ssh.socket.d/override.conf 2>/dev/null
    rm -f "/etc/systemd/system/ssh.service.d/override.conf" 2>/dev/null
    rm -f "/etc/systemd/system/sshd.service.d/override.conf" 2>/dev/null
    systemctl daemon-reload 2>/dev/null
    systemctl restart "$SSH_SERVICE" 2>/dev/null
    warn "SSH откачен к предыдущей конфигурации."
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_configure_ssh() {
    _print_section "Настройка SSH"
    
    if ! dpkg -l openssh-server 2>/dev/null | grep -q ^ii; then
        if ask_yes_no "openssh-server не установлен. Установить?" "y"; then
            if run_cmd "apt-get install -y openssh-server"; then
                ok "openssh-server установлен."
            else
                err "Не удалось установить openssh-server."
                return 1
            fi
        else
            info "Пропуск настройки SSH."
            return 0
        fi
    fi
    
    if ! _detect_ssh_service; then
        return 1
    fi
    _get_current_ssh_port
    
    read -rp "$(printf '%s' "${CYAN}Введите новый порт SSH (текущий: $CURRENT_SSH_PORT): ${NC}")" NEW_SSH_PORT
    if [[ -z "$NEW_SSH_PORT" ]]; then
        NEW_SSH_PORT=$CURRENT_SSH_PORT
    fi
    if ! [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || (( NEW_SSH_PORT < 1 || NEW_SSH_PORT > 65535 )); then
        err "Неверный номер порта."
        return 1
    fi
    
    if ! _backup_ssh_config; then
        return 1
    fi
    
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/10-hardening.conf <<EOF
Port $NEW_SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
X11Forwarding no
PrintMotd no
EOF
    ok "Создан файл жестких настроек: /etc/ssh/sshd_config.d/10-hardening.conf"
    
    if [[ "$SSH_SERVICE" == "ssh.socket" ]]; then
        mkdir -p /etc/systemd/system/ssh.socket.d
        cat > /etc/systemd/system/ssh.socket.d/override.conf <<EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:$NEW_SSH_PORT
ListenStream=[::]:$NEW_SSH_PORT
EOF
    else
        mkdir -p "/etc/systemd/system/${SSH_SERVICE}.d"
        cat > "/etc/systemd/system/${SSH_SERVICE}.d/override.conf" <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/sshd -D -p $NEW_SSH_PORT
EOF
    fi
    
    info "Проверка конфигурации SSH..."
    if ! sshd -t 2>&1 | tee -a "$LOG_FILE"; then
        err "Ошибка в конфигурации SSH. Откат изменений."
        _rollback_ssh
        return 1
    fi
    
    info "Перезапуск SSH сервиса..."
    systemctl daemon-reload
    if ! systemctl restart "$SSH_SERVICE"; then
        err "Не удалось перезапустить SSH. Откат изменений."
        _rollback_ssh
        return 1
    fi
    sleep 2
    if ! ss -tuln | grep -q ":$NEW_SSH_PORT"; then
        err "SSH не слушает на порту $NEW_SSH_PORT. Откат."
        _rollback_ssh
        return 1
    fi
    ok "SSH успешно настроен на порту $NEW_SSH_PORT."
    warn "ВАЖНО: Проверьте подключение с новым портом в ОТДЕЛЬНОМ терминале!"
    info "Пример: ssh -p $NEW_SSH_PORT пользователь@сервер"
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_2fa() {
    _print_section "Настройка 2FA (Google Authenticator)"
    
    local username
    read -rp "$(printf '%s' "${CYAN}Введите имя пользователя для 2FA: ${NC}")" username
    
    if [[ -z "$username" ]]; then
        err "Имя пользователя не может быть пустым."
        return 1
    fi
    
    if ! id "$username" &>/dev/null; then
        err "Пользователь '$username' не существует."
        return 1
    fi
    
    if ! ask_yes_no "Настроить 2FA для пользователя '$username'?" "y"; then
        info "Пропуск настройки 2FA."
        return 0
    fi
    
    # Установка зависимостей
    info "Установка libpam-google-authenticator и qrencode..."
    if ! run_cmd "apt-get install -y libpam-google-authenticator qrencode"; then
        err "Не удалось установить необходимые пакеты."
        return 1
    fi
    
    local user_home="$HOME"
    user_home=$(getent passwd "$username" | cut -d: -f6)
    local ga_file="$user_home/.google_authenticator"
    
    # Генерация секрета
    if [[ -f "$ga_file" ]]; then
        if ask_yes_no "2FA уже настроен. Перегенерировать секрет?" "n"; then
            rm -f "$ga_file"
        else
            info "Используется существующая конфигурация."
            return 0
        fi
    fi
    
    info "Генерация 2FA секрета для '$username'..."
    info "В новом терминале выполните: sudo -u $username google-authenticator -t -d -f -r 3 -R 30 -w 3"
    warn "Сохраните секретный ключ и коды восстановления!"
    
    if ask_yes_no "Продолжить с автоматической настройкой?" "y"; then
        if ! sudo -u "$username" google-authenticator -t -d -f -r 3 -R 30 -w 3 -q; then
            err "Не удалось сгенерировать 2FA конфигурацию."
            return 1
        fi
        
        # Настройка PAM
        local pam_file="/etc/pam.d/sshd"
        if ! grep -q "pam_google_authenticator.so" "$pam_file"; then
            cp "$pam_file" "${pam_file}.backup_$(date +%Y%m%d_%H%M%S)"
            sed -i '1i auth required pam_google_authenticator.so nullok' "$pam_file"
            ok "PAM настроен для 2FA."
        fi
        
        # Настройка SSH
        local ssh_dropin_dir="/etc/ssh/sshd_config.d"
        local ssh_2fa_conf="$ssh_dropin_dir/95-2fa-${username}.conf"
        mkdir -p "$ssh_dropin_dir"
        
        cat > "$ssh_2fa_conf" <<EOF
Match User $username
    AuthenticationMethods publickey,keyboard-interactive
    KbdInteractiveAuthentication yes
EOF
        ok "Создан файл конфигурации 2FA: $ssh_2fa_conf"
        
        # Перезапуск SSH
        if ! _detect_ssh_service; then
            return 1
        fi
        
        info "Перезапуск SSH для применения 2FA..."
        if systemctl restart "$SSH_SERVICE"; then
            ok "SSH перезапущен. 2FA активирована."
            warn "Проверьте подключение: ssh -p $NEW_SSH_PORT $username@сервер"
        else
            err "Не удалось перезапустить SSH. Откат 2FA..."
            rm -f "$ssh_2fa_conf"
            sed -i '/pam_google_authenticator.so/d' "$pam_file"
            return 1
        fi
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_ssh_hardening_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🔒 Настройка SSH и 2FA"
        printf_description "Жесткая настройка SSH и двухфакторная аутентификация."
        
        printf_menu_option "1" "Настроить SSH (порт, ключи)"
        printf_menu_option "2" "Настроить 2FA (Google Authenticator)"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _configure_ssh ;;
            2) _configure_2fa ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
