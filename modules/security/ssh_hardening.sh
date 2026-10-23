#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: НАСТРОЙКА SSH И 2FA                  == #
# ============================================================ #
# Жесткая настройка SSH, управление портами, 2FA.
# Версия: 1.1.0

#
# @menu.manifest
#
# @item( main | 3 | 🔒 Настройка SSH и 2FA | show_ssh_hardening_menu | 30 | 10 | Безопасность SSH и двухфакторная аутентификация )
# @item( ssh_hardening | 1 | Настроить SSH (порт, ключи) | _configure_ssh | 10 | 10 | Изменение порта, отключение root )
# @item( ssh_hardening | 2 | Настроить 2FA (Google Authenticator) | _configure_2fa | 20 | 10 | Двухфакторная аутентификация )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ МОДУЛЯ ===
SSH_SERVICE=""
SSH_HARDENING_CONF="/etc/ssh/sshd_config.d/10-hardening.conf"
SSH_SOCKET_OVERRIDE="/etc/systemd/system/ssh.socket.d/override.conf"
SSH_ROLLBACK_DIR=""
CURRENT_SSH_PORT=22
NEW_SSH_PORT=22

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

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

# Перезапуск SSH с учетом socket-активации (Ubuntu 22.10+)
_restart_ssh() {
    systemctl daemon-reload
    if [[ "$SSH_SERVICE" == "ssh.socket" ]]; then
        systemctl restart ssh.socket
    else
        systemctl restart "$SSH_SERVICE"
    fi
}

# Список не-root пользователей с непустым authorized_keys
_users_with_ssh_keys() {
    local name uid home
    while IFS=: read -r name _ uid _ _ home _; do
        (( uid >= 1000 && uid < 65534 )) || continue
        [[ -s "$home/.ssh/authorized_keys" ]] && echo "$name"
    done < /etc/passwd
}

# Сохраняет все файлы, которые изменяет модуль, для последующего отката
_backup_ssh_config() {
    SSH_ROLLBACK_DIR="$BACKUP_DIR/ssh_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$SSH_ROLLBACK_DIR" && chmod 700 "$SSH_ROLLBACK_DIR"

    local file
    for file in /etc/ssh/sshd_config "$SSH_HARDENING_CONF" "$SSH_SOCKET_OVERRIDE" \
                /etc/systemd/system/ssh.service.d/override.conf \
                /etc/systemd/system/sshd.service.d/override.conf; do
        if [[ -f "$file" ]]; then
            mkdir -p "$SSH_ROLLBACK_DIR$(dirname "$file")"
            cp -p "$file" "$SSH_ROLLBACK_DIR$file"
        fi
    done
    ok "Конфигурация SSH сохранена в $SSH_ROLLBACK_DIR"
    log "SSH config backed up to $SSH_ROLLBACK_DIR"
}

_rollback_ssh() {
    warn "Откат изменений SSH..."
    local file
    for file in /etc/ssh/sshd_config "$SSH_HARDENING_CONF" "$SSH_SOCKET_OVERRIDE" \
                /etc/systemd/system/ssh.service.d/override.conf \
                /etc/systemd/system/sshd.service.d/override.conf; do
        if [[ -f "$SSH_ROLLBACK_DIR$file" ]]; then
            cp -p "$SSH_ROLLBACK_DIR$file" "$file"
        else
            rm -f "$file"
        fi
    done
    _restart_ssh 2>/dev/null
    warn "SSH откачен к предыдущей конфигурации."
    log "SSH config rolled back from $SSH_ROLLBACK_DIR"
}

# Override с "sshd -D -p PORT", созданный прошлыми версиями скрипта,
# перекрывает Port из конфигурации и теряет $SSHD_OPTS — удаляем его.
_remove_legacy_service_override() {
    local file
    for file in /etc/systemd/system/ssh.service.d/override.conf /etc/systemd/system/sshd.service.d/override.conf; do
        if [[ -f "$file" ]] && grep -q "sshd -D -p" "$file"; then
            rm -f "$file"
            info "Удален устаревший override: $file"
        fi
    done
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_configure_ssh() {
    print_section "Настройка SSH"

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
    CURRENT_SSH_PORT=$(get_ssh_port)
    info "Текущий порт SSH: $CURRENT_SSH_PORT"

    # --- Защита от потери доступа ---
    local key_users
    key_users=$(_users_with_ssh_keys | tr '\n' ' ')
    local disable_root="y" disable_password="y"
    if [[ -z "$key_users" ]]; then
        warn "Не найдено ни одного обычного пользователя с SSH-ключом (~/.ssh/authorized_keys)."
        warn "Если отключить вход root и вход по паролю, вы ПОТЕРЯЕТЕ доступ к серверу!"
        info "Сначала создайте пользователя и добавьте ключ: меню 'Управление пользователями'."
        disable_root="n"
        disable_password="n"
    else
        info "Пользователи с SSH-ключами: $key_users"
    fi

    local permit_root="no" password_auth="no"
    ask_yes_no "Отключить вход по паролю (только ключи)?" "$disable_password" || password_auth="yes"
    if ! ask_yes_no "Запретить вход под root по SSH?" "$disable_root"; then
        # root сохраняет доступ тем же способом, что и остальные пользователи
        if [[ "$password_auth" == "yes" ]]; then
            permit_root="yes"
        else
            permit_root="prohibit-password"
        fi
    fi

    local input_port
    input_port=$(safe_read "Введите новый порт SSH (текущий: $CURRENT_SSH_PORT): ") || return 1
    NEW_SSH_PORT="${input_port:-$CURRENT_SSH_PORT}"
    if ! [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || (( NEW_SSH_PORT < 1 || NEW_SSH_PORT > 65535 )); then
        err "Неверный номер порта."
        return 1
    fi
    if [[ "$NEW_SSH_PORT" != "$CURRENT_SSH_PORT" ]] && is_port_listening "$NEW_SSH_PORT"; then
        err "Порт $NEW_SSH_PORT уже занят другим процессом."
        return 1
    fi

    _backup_ssh_config

    # Drop-in файлы подключаются в начале sshd_config, и первое значение
    # параметра имеет приоритет. Убеждаемся, что Include присутствует.
    mkdir -p /etc/ssh/sshd_config.d
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
        info "В sshd_config добавлена директива Include."
    fi

    cat > "$SSH_HARDENING_CONF" <<EOF
# Сгенерировано Server Setup $(date '+%Y-%m-%d %H:%M:%S')
Port $NEW_SSH_PORT
PermitRootLogin $permit_root
PasswordAuthentication $password_auth
PermitEmptyPasswords no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
PrintMotd no
EOF
    chmod 644 "$SSH_HARDENING_CONF"
    ok "Создан файл настроек: $SSH_HARDENING_CONF"

    _remove_legacy_service_override

    if [[ "$SSH_SERVICE" == "ssh.socket" ]]; then
        mkdir -p "$(dirname "$SSH_SOCKET_OVERRIDE")"
        cat > "$SSH_SOCKET_OVERRIDE" <<EOF
[Socket]
ListenStream=
ListenStream=$NEW_SSH_PORT
EOF
    fi

    info "Проверка конфигурации SSH..."
    if ! sshd -t 2>&1 | tee -a "$LOG_FILE"; then
        err "Ошибка в конфигурации SSH. Откат изменений."
        _rollback_ssh
        return 1
    fi

    # Открываем новый порт в UFW ДО перезапуска SSH
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        if run_cmd "ufw allow $NEW_SSH_PORT/tcp comment 'SSH'"; then
            ok "Порт $NEW_SSH_PORT/tcp открыт в UFW."
        else
            err "Не удалось открыть порт в UFW. Откат изменений."
            _rollback_ssh
            return 1
        fi
    fi

    info "Перезапуск SSH сервиса..."
    if ! _restart_ssh; then
        err "Не удалось перезапустить SSH. Откат изменений."
        _rollback_ssh
        return 1
    fi
    sleep 2
    if ! is_port_listening "$NEW_SSH_PORT"; then
        err "SSH не слушает на порту $NEW_SSH_PORT. Откат."
        _rollback_ssh
        return 1
    fi
    ok "SSH настроен на порту $NEW_SSH_PORT."

    warn "НЕ ЗАКРЫВАЙТЕ текущую сессию! Проверьте подключение в ОТДЕЛЬНОМ терминале:"
    info "  ssh -p $NEW_SSH_PORT <пользователь>@<сервер>"
    if ! ask_yes_no "Подключение по новым настройкам работает?" "n"; then
        _rollback_ssh
        return 1
    fi

    # Синхронизируем порт в Fail2Ban, если он уже настроен
    local jail_local="/etc/fail2ban/jail.local"
    if [[ -f "$jail_local" ]] && grep -q '^\[sshd\]' "$jail_local"; then
        sed -i "/^\[sshd\]/,/^\[/ s/^port[[:space:]]*=.*/port = $NEW_SSH_PORT/" "$jail_local"
        systemctl restart fail2ban 2>/dev/null && ok "Порт SSH обновлен в Fail2Ban."
    fi

    if [[ "$NEW_SSH_PORT" != "$CURRENT_SSH_PORT" ]] && command -v ufw >/dev/null 2>&1 \
        && ufw status 2>/dev/null | grep -qE "^${CURRENT_SSH_PORT}(/tcp)?[[:space:]]"; then
        if ask_yes_no "Закрыть старый порт $CURRENT_SSH_PORT в UFW?" "y"; then
            run_cmd "ufw delete allow $CURRENT_SSH_PORT/tcp" || run_cmd "ufw delete allow $CURRENT_SSH_PORT"
        fi
    fi

    log "SSH hardened: port=$NEW_SSH_PORT root=$permit_root password=$password_auth"
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_2fa() {
    print_section "Настройка 2FA (Google Authenticator)"

    local username
    username=$(ask_existing_user "Введите имя пользователя для 2FA") || return 1

    local user_home
    user_home=$(getent passwd "$username" | cut -d: -f6)
    if [[ ! -s "$user_home/.ssh/authorized_keys" ]]; then
        err "У пользователя '$username' нет SSH-ключей. 2FA настраивается поверх входа по ключу."
        return 1
    fi

    if ! ask_yes_no "Настроить 2FA для пользователя '$username'?" "y"; then
        info "Пропуск настройки 2FA."
        return 0
    fi

    if ! _detect_ssh_service; then
        return 1
    fi

    info "Установка libpam-google-authenticator и qrencode..."
    if ! run_cmd "apt-get install -y libpam-google-authenticator qrencode"; then
        err "Не удалось установить необходимые пакеты."
        return 1
    fi

    local ga_file="$user_home/.google_authenticator"
    local generate=true
    if [[ -f "$ga_file" ]]; then
        if ask_yes_no "2FA уже настроен. Перегенерировать секрет (старые коды перестанут работать)?" "n"; then
            rm -f "$ga_file"
        else
            info "Используется существующий секрет."
            generate=false
        fi
    fi

    if [[ "$generate" == true ]]; then
        info "Генерация 2FA секрета для '$username'..."
        # -t: TOTP, -d: запрет повторного кода, -f: без вопросов, -r/-R: rate limit, -w: окно
        if ! sudo -u "$username" google-authenticator -t -d -f -r 3 -R 30 -w 3 -q; then
            err "Не удалось сгенерировать 2FA конфигурацию."
            return 1
        fi

        # Секрет и коды выводим только на экран, НЕ в лог
        local secret otp_url
        secret=$(head -n 1 "$ga_file")
        otp_url="otpauth://totp/${username}@$(hostname)?secret=${secret}&issuer=$(hostname)"

        printf '\n%s\n' "${YELLOW}1. Откройте приложение-аутентификатор (Google Authenticator, Aegis и т.д.)${NC}"
        printf '%s\n\n' "${YELLOW}2. Отсканируйте QR-код:${NC}"
        qrencode -t ANSIUTF8 "$otp_url"
        printf '\n   %s %s\n\n' "${CYAN}Секретный ключ (если QR не работает):${NC}" "${BOLD}${secret}${NC}"
        printf '%s\n' "${RED}СОХРАНИТЕ АВАРИЙНЫЕ КОДЫ:${NC}"
        grep -E '^[0-9]{8}$' "$ga_file"
        printf '\n'

        if ! ask_yes_no "Вы сохранили секрет/коды и добавили аккаунт в приложение?" "n"; then
            warn "Настройка 2FA прервана во избежание потери доступа."
            rm -f "$ga_file"
            return 1
        fi
    fi

    # --- PAM ---
    local pam_file="/etc/pam.d/sshd"
    local pam_backup
    pam_backup="${pam_file}.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$pam_file" "$pam_backup"
    if ! grep -q "pam_google_authenticator.so" "$pam_file"; then
        sed -i '1i auth required pam_google_authenticator.so nullok' "$pam_file"
    fi
    # Без этого после кода 2FA будет запрошен пароль пользователя (которого может не быть).
    # Отключаем common-auth только если вход по паролю и keyboard-interactive глобально
    # запрещены — иначе nullok позволил бы войти без пароля пользователям без 2FA.
    local sshd_global
    sshd_global=$(sshd -T 2>/dev/null)
    if grep -q '^passwordauthentication no' <<< "$sshd_global" \
        && grep -q '^kbdinteractiveauthentication no' <<< "$sshd_global"; then
        sed -i 's/^@include common-auth/# @include common-auth  # отключено Server Setup (2FA)/' "$pam_file"
    else
        warn "Вход по паролю разрешен — после кода 2FA будет запрошен пароль пользователя."
    fi
    ok "PAM настроен для 2FA."

    # --- SSH ---
    local ssh_2fa_conf="/etc/ssh/sshd_config.d/95-2fa-${username}.conf"
    cat > "$ssh_2fa_conf" <<EOF
Match User $username
    AuthenticationMethods publickey,keyboard-interactive
    KbdInteractiveAuthentication yes
EOF
    ok "Создан файл конфигурации 2FA: $ssh_2fa_conf"

    local rollback_2fa=false
    if ! sshd -t 2>&1 | tee -a "$LOG_FILE" || ! _restart_ssh; then
        err "Ошибка применения конфигурации SSH."
        rollback_2fa=true
    else
        ok "SSH перезапущен. 2FA активирована."
        warn "НЕ ЗАКРЫВАЙТЕ текущую сессию! Проверьте вход в ОТДЕЛЬНОМ терминале:"
        info "  ssh -p $(get_ssh_port) $username@<сервер>"
        info "Должен быть запрошен код подтверждения после проверки ключа."
        if ! ask_yes_no "Вход с 2FA работает?" "n"; then
            rollback_2fa=true
        fi
    fi

    if [[ "$rollback_2fa" == true ]]; then
        warn "Откат изменений 2FA..."
        rm -f "$ssh_2fa_conf"
        cp "$pam_backup" "$pam_file"
        _restart_ssh
        return 1
    fi

    log "2FA enabled for user $username."
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_ssh_hardening_menu() {
    local menu_id="ssh_hardening"

    enable_graceful_ctrlc
    while true; do
        menu_header "🔒 Настройка SSH и 2FA"
        printf_description "Жесткая настройка SSH и двухфакторная аутентификация."

        render_menu_items "$menu_id"
        printf_menu_option "b" "Назад"

        local choice
        choice=$(safe_read "Ваш выбор: ") || break

        if [[ "$choice" == "b" || "$choice" == "B" ]]; then
            break
        fi

        local action
        action=$(get_menu_action "$menu_id" "$choice")

        if [[ -n "$action" ]]; then
            "$action"
        else
            err "Нет такого пункта."
        fi
    done
    disable_graceful_ctrlc
}
