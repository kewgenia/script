#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ          == #
# ============================================================ #
# Создание пользователей, настройка SSH-ключей и sudo-прав.
# Версия: 1.0.0

#
# @menu.manifest
#
# @item( main | 2 | 👤 Управление пользователями | show_user_management_menu | 20 | 20 | Создание и настройка пользователей )
# @item( user_management | 1 | Создать нового пользователя | _create_user | 10 | 10 | Настройка нового пользователя с SSH-ключами )
# @item( user_management | 2 | Настроить SSH-ключи | _setup_ssh_keys_menu | 20 | 10 | Добавление SSH-ключей для пользователя )
# @item( user_management | 3 | Управление sudo-правами | _manage_sudo | 30 | 10 | Добавление/удаление из группы sudo )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_validate_ssh_key() {
    local key="$1"
    if [[ "$key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        return 0
    else
        return 1
    fi
}

_setup_ssh_keys_for_user() {
    local username="$1"
    local user_home ssh_dir auth_keys
    
    user_home=$(getent passwd "$username" | cut -d: -f6)
    ssh_dir="$user_home/.ssh"
    auth_keys="$ssh_dir/authorized_keys"
    
    if ! ask_yes_no "Добавить SSH-ключи для '$username'?"; then
        info "Пропуск добавления SSH-ключей."
        return 0
    fi
    
    while true; do
        local ssh_key
        read -rp "$(printf '%s' "${CYAN}Вставьте ваш публичный SSH-ключ: ${NC}")" ssh_key
        
        if _validate_ssh_key "$ssh_key"; then
            mkdir -p "$ssh_dir"
            chmod 700 "$ssh_dir"
            chown "$username:$username" "$ssh_dir"
            
            echo "$ssh_key" >> "$auth_keys"
            # Удаление дубликатов
            awk '!seen[$0]++' "$auth_keys" > "$auth_keys.tmp" && mv "$auth_keys.tmp" "$auth_keys"
            
            chmod 600 "$auth_keys"
            chown "$username:$username" "$auth_keys"
            
            ok "SSH-ключ добавлен для '$username'."
            log "Добавлен SSH-ключ для пользователя '$username'."
        else
            warn "Неверный формат SSH-ключа. Ключ должен начинаться с 'ssh-rsa', 'ssh-ed25519' или 'ecdsa-*'."
        fi
        
        if ! ask_yes_no "Добавить еще один SSH-ключ?" "n"; then
            break
        fi
    done
}

_generate_ssh_keys_for_user() {
    local username="$1"
    local user_home ssh_dir auth_keys
    
    user_home=$(getent passwd "$username" | cut -d: -f6)
    ssh_dir="$user_home/.ssh"
    auth_keys="$ssh_dir/authorized_keys"
    
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        err "ssh-keygen не найден. Установите openssh-client."
        return 1
    fi
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$username:$username" "$ssh_dir"
    
    # Генерация ключей пользователя
    if sudo -u "$username" ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -q; then
        cat "$ssh_dir/id_ed25519.pub" >> "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$username:$username" "$auth_keys"
        
        ok "SSH-ключи сгенерированы для '$username'."
        info "Приватный ключ: $ssh_dir/id_ed25519"
        info "Публичный ключ: $ssh_dir/id_ed25519.pub"
        log "Сгенерированы SSH-ключи для '$username'."
    else
        err "Не удалось сгенерировать SSH-ключи."
        return 1
    fi
}

_create_user() {
    local username password pass1 pass2
    
    read -rp "$(printf '%s' "${CYAN}Введите имя пользователя: ${NC}")" username
    
    if [[ -z "$username" ]]; then
        err "Имя пользователя не может быть пустым."
        return 1
    fi
    
    if id "$username" &>/dev/null; then
        warn "Пользователь '$username' уже существует."
        if ask_yes_no "Настроить SSH-ключи для существующего пользователя?"; then
            _setup_ssh_keys_for_user "$username"
        fi
        return 0
    fi
    
    info "Создание пользователя '$username'..."
    
    local -a adduser_opts=("--disabled-password" "--gecos" "")
    
    # Проверка существования группы
    if getent group "$username" >/dev/null 2>&1; then
        warn "Группа '$username' уже существует. Добавляем пользователя в эту группу."
        adduser_opts+=("--ingroup" "$username")
    fi
    
    if ! adduser "${adduser_opts[@]}" "$username"; then
        err "Не удалось создать пользователя '$username'."
        return 1
    fi
    
    # Настройка пароля
    info "Настройка пароля для '$username' (или Enter для пропуска):"
    
    while true; do
        read -rsp "$(printf '%s' "${CYAN}Новый пароль: ${NC}")" pass1
        printf '\n'
        read -rsp "$(printf '%s' "${CYAN}Повторите пароль: ${NC}")" pass2
        printf '\n'
        
        if [[ -z "$pass1" && -z "$pass2" ]]; then
            warn "Пароль пропущен. Используется только SSH-аутентификация."
            if ask_yes_no "Сгенерировать случайный пароль?" "y"; then
                local rand_pass
                rand_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24)
                if echo "$username:$rand_pass" | chpasswd >/dev/null 2>&1; then
                    ok "Сгенерирован случайный пароль."
                    warn "СОХРАНИТЕ ЭТОТ ПАРОЛЬ: $rand_pass"
                    log "Сгенерирован пароль для '$username'."
                    break
                fi
            else
                info "Пароль не установлен."
                break
            fi
        elif [[ "$pass1" == "$pass2" ]]; then
            if echo "$username:$pass1" | chpasswd >/dev/null 2>&1; then
                ok "Пароль для '$username' установлен."
                break
            else
                err "Не удалось установить пароль."
            fi
        else
            err "Пароли не совпадают."
        fi
    done
    
    # Настройка SSH-ключей
    _setup_ssh_keys_for_user "$username"
    
    # Добавление в группу sudo
    if ask_yes_no "Добавить пользователя '$username' в группу sudo?" "y"; then
        if usermod -aG sudo "$username"; then
            ok "Пользователь '$username' добавлен в группу sudo."
            log "Пользователь '$username' добавлен в sudo."
        else
            err "Не удалось добавить в группу sudo."
        fi
    fi
    
    ok "Пользователь '$username' успешно настроен."
    log "Пользователь '$username' создан и настроен."
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_setup_ssh_keys_menu() {
    local username
    
    read -rp "$(printf '%s' "${CYAN}Введите имя пользователя: ${NC}")" username
    
    if [[ -z "$username" ]]; then
        err "Имя пользователя не может быть пустым."
        return 1
    fi
    
    if ! id "$username" &>/dev/null; then
        err "Пользователь '$username' не существует."
        return 1
    fi
    
    _setup_ssh_keys_for_user "$username"
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_manage_sudo() {
    local username
    
    read -rp "$(printf '%s' "${CYAN}Введите имя пользователя: ${NC}")" username
    
    if [[ -z "$username" ]]; then
        err "Имя пользователя не может быть пустым."
        return 1
    fi
    
    if ! id "$username" &>/dev/null; then
        err "Пользователь '$username' не существует."
        return 1
    fi
    
    if groups "$username" | grep -qw sudo; then
        info "Пользователь '$username' уже в группе sudo."
        if ask_yes_no "Удалить из группы sudo?" "n"; then
            if gpasswd -d "$username" sudo; then
                ok "Пользователь '$username' удален из группы sudo."
            else
                err "Не удалось удалить из группы sudo."
            fi
        fi
    else
        info "Пользователь '$username' не в группе sudo."
        if ask_yes_no "Добавить в группу sudo?" "y"; then
            if usermod -aG sudo "$username"; then
                ok "Пользователь '$username' добавлен в группу sudo."
            else
                err "Не удалось добавить в группу sudo."
            fi
        fi
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_user_management_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "👤 Управление пользователями"
        printf_description "Создание пользователей, настройка SSH-ключей и прав доступа."
        
        printf_menu_option "1" "Создать нового пользователя"
        printf_menu_option "2" "Настроить SSH-ключи"
        printf_menu_option "3" "Управление sudo-правами"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _create_user ;;
            2) _setup_ssh_keys_menu ;;
            3) _manage_sudo ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
