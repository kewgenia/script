#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: СЕТЕВЫЕ ИНСТРУМЕНТЫ            == #
# ============================================================ #
# Установка и настройка Docker, Tailscale, NetBird.
# Версия: 1.1.0

#
# @menu.manifest
#
# @item( main | 8 | 🌐 Сетевые инструменты | show_network_tools_menu | 80 | 20 | Docker, VPN, мониторинг )
# @item( network_tools | 1 | Установить Docker | _install_docker | 10 | 10 | Docker Engine и docker-compose )
# @item( network_tools | 2 | Установить Tailscale VPN | _install_tailscale | 20 | 10 | Настройка Tailscale )
# @item( network_tools | 3 | Установить NetBird VPN | _install_netbird | 30 | 10 | Настройка NetBird )
# @item( network_tools | 4 | Установить dtop (Docker мониторинг) | _install_dtop | 40 | 10 | TUI для Docker контейнеров )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

# Установка утилит, нужных для подключения сторонних репозиториев
_ensure_repo_tools() {
    local -a missing=()
    command -v curl >/dev/null 2>&1 || missing+=(curl)
    command -v gpg >/dev/null 2>&1 || missing+=(gnupg)
    [[ -f /etc/ssl/certs/ca-certificates.crt ]] || missing+=(ca-certificates)
    (( ${#missing[@]} == 0 )) && return 0
    info "Установка зависимостей: ${missing[*]}"
    run_cmd "apt-get install -y ${missing[*]}"
}

_validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        return 0
    else
        return 1
    fi
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_install_docker() {
    print_section "Установка Docker"
    
    if command -v docker >/dev/null 2>&1; then
        info "Docker уже установлен."
        return 0
    fi
    
    if ! ask_yes_no "Установить Docker Engine?" "y"; then
        info "Пропуск установки Docker."
        return 0
    fi
    
    _ensure_repo_tools || { err "Не удалось установить зависимости."; return 1; }
    
    local distro_id distro_codename
    distro_id=$(. /etc/os-release && echo "${ID:-}")
    distro_codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    if [[ "$distro_id" != "debian" && "$distro_id" != "ubuntu" ]]; then
        err "Docker репозиторий поддерживается только для Debian/Ubuntu (обнаружено: $distro_id)."
        return 1
    fi
    
    info "Удаление старых версий..."
    apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc >> "$LOG_FILE" 2>&1 || true
    
    info "Добавление репозитория Docker..."
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL "https://download.docker.com/linux/${distro_id}/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg; then
        err "Не удалось загрузить GPG ключ Docker."
        return 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Исправлено: в URL должен быть ID дистрибутива, а codename — отдельным полем
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distro_id} ${distro_codename} stable" > /etc/apt/sources.list.d/docker.list
    
    info "Установка Docker пакетов..."
    if ! run_cmd "apt-get update -qq" || ! run_cmd "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"; then
        err "Не удалось установить Docker."
        return 1
    fi
    
    # Настройка daemon.json
    local daemon_config="/etc/docker/daemon.json"
    mkdir -p /etc/docker
    local tmp_daemon
    tmp_daemon=$(mktemp)
    cat > "$tmp_daemon" <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "5",
        "compress": "true"
    },
    "live-restore": true,
    "dns": [
        "9.9.9.9",
        "1.1.1.1"
    ],
    "default-address-pools": [
        {
            "base": "172.20.0.0/16",
            "size": 24
        }
    ],
    "userland-proxy": false,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    },
    "features": {
        "buildkit": true
    }
}
EOF
    
    if [[ -f "$daemon_config" ]] && cmp -s "$tmp_daemon" "$daemon_config"; then
        info "Конфигурация Docker уже корректна."
        rm -f "$tmp_daemon"
    else
        [[ -f "$daemon_config" ]] && cp "$daemon_config" "${daemon_config}.backup_$(date +%Y%m%d_%H%M%S)"
        mv "$tmp_daemon" "$daemon_config"
        chmod 644 "$daemon_config"
        ok "Конфигурация Docker обновлена."
    fi
    
    # Добавление пользователя в группу docker (эквивалент root-доступа!)
    if ask_yes_no "Добавить пользователя в группу docker (дает права, эквивалентные root)?" "n"; then
        local username
        if username=$(ask_existing_user "Имя пользователя"); then
            usermod -aG docker "$username"
            ok "Пользователь '$username' добавлен в группу docker (перелогиньтесь для применения)."
        fi
    fi
    
    systemctl daemon-reload
    systemctl enable --now docker >/dev/null 2>&1
    systemctl restart docker
    
    # Проверка
    info "Проверка Docker..."
    if docker run --rm hello-world 2>&1 | tee -a "$LOG_FILE" | grep -q "Hello from Docker"; then
        ok "Docker успешно установлен и работает."
    else
        warn "Тест Docker не прошел. Проверьте установку."
    fi
    
    warn "Внимание: опубликованные порты контейнеров (-p) обходят правила UFW!"
    info "Публикуйте порты на 127.0.0.1 (-p 127.0.0.1:8080:80) или используйте обратный прокси."
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_install_dtop() {
    if ! ask_yes_no "Установить dtop (Docker мониторинг)?" "y"; then
        return 0
    fi
    
    local username
    username=$(ask_existing_user "Для какого пользователя установить dtop") || return 1
    
    local user_home user_local_bin
    user_home=$(getent passwd "$username" | cut -d: -f6)
    user_local_bin="$user_home/.local/bin"
    
    if [[ -x "$user_local_bin/dtop" ]]; then
        info "dtop уже установлен: $user_local_bin/dtop"
        return 0
    fi
    
    local installer
    installer=$(mktemp)
    if ! curl -fsSL "https://github.com/amir20/dtop/releases/latest/download/dtop-installer.sh" -o "$installer"; then
        warn "Не удалось скачать установщик dtop."
        rm -f "$installer"
        return 1
    fi
    chmod 755 "$installer"
    
    sudo -u "$username" mkdir -p "$user_local_bin"
    if sudo -u "$username" -H bash "$installer" < /dev/null >> "$LOG_FILE" 2>&1 && [[ -f "$user_local_bin/dtop" ]]; then
        ok "dtop установлен в $user_local_bin/dtop"
        # Добавление в PATH если нужно
        local bashrc="$user_home/.bashrc"
        if [[ -f "$bashrc" ]] && ! grep -q "\.local/bin" "$bashrc"; then
            {
                echo ''
                echo '# Add local bin to PATH'
                # shellcheck disable=SC2016
                echo 'if [ -d "$HOME/.local/bin" ]; then PATH="$HOME/.local/bin:$PATH"; fi'
            } >> "$bashrc"
            ok "PATH обновлен в $bashrc"
        fi
    else
        warn "Установка dtop не удалась. Подробности в $LOG_FILE"
    fi
    rm -f "$installer"
    [[ $VERBOSE == true ]] && wait_for_enter
}

_install_tailscale() {
    print_section "Установка Tailscale VPN"
    
    if command -v tailscale >/dev/null 2>&1; then
        if systemctl is-active --quiet tailscaled && tailscale ip >/dev/null 2>&1; then
            local ts_ip
            ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
            ok "Tailscale уже активен. IP: $ts_ip"
            return 0
        fi
    fi
    
    if ! ask_yes_no "Установить и настроить Tailscale?" "y"; then
        info "Пропуск установки Tailscale."
        return 0
    fi
    
    # Установка
    if ! curl -fsSL https://tailscale.com/install.sh | sh >> "$LOG_FILE" 2>&1; then
        err "Не удалось установить Tailscale."
        return 1
    fi
    ok "Tailscale установлен."
    
    # Настройка
    if ! ask_yes_no "Настроить Tailscale сейчас?" "y"; then
        info "Настройте позже: sudo tailscale up"
        return 0
    fi
    
    local auth_key login_server=""
    read -rsp "$(printf '%s' "${CYAN}Введите pre-auth key (или пусто для входа по ссылке): ${NC}")" auth_key
    printf '\n'
    
    local -a ts_args=(up)
    if [[ -n "$auth_key" ]]; then
        ts_args+=("--auth-key=$auth_key")
    fi
    
    if ask_yes_no "Использовать кастомный сервер Tailscale (Headscale)?" "n"; then
        read -rp "$(printf '%s' "${CYAN}Введите URL сервера: ${NC}")" login_server
        if _validate_url "$login_server"; then
            ts_args+=("--login-server=$login_server")
        else
            warn "Некорректный URL, используется сервер по умолчанию."
        fi
    fi
    
    info "Подключение к Tailscale..."
    if ! tailscale "${ts_args[@]}"; then
        warn "Не удалось подключиться к Tailscale."
        return 1
    fi
    
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
    ok "Tailscale подключен. IP: $ts_ip"
    # Ключ авторизации в лог не пишем
    log "Tailscale connected${login_server:+ (login-server: $login_server)}."
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_install_netbird() {
    print_section "Установка NetBird VPN"
    
    if command -v netbird >/dev/null 2>&1; then
        if systemctl is-active --quiet netbird && netbird status 2>/dev/null | grep -q "Connected"; then
            local nb_ip
            nb_ip=$(ip -4 addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            ok "NetBird уже активен. IP: $nb_ip"
            return 0
        fi
    fi
    
    if ! ask_yes_no "Установить и настроить NetBird?" "y"; then
        info "Пропуск установки NetBird."
        return 0
    fi
    
    # Установка зависимостей и репозитория
    _ensure_repo_tools || { err "Не удалось установить зависимости."; return 1; }
    if ! curl -fsSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --yes --output /usr/share/keyrings/netbird-archive-keyring.gpg; then
        err "Не удалось загрузить GPG ключ NetBird."
        return 1
    fi
    echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' > /etc/apt/sources.list.d/netbird.list
    
    if ! run_cmd "apt-get update -qq" || ! run_cmd "apt-get install -y netbird"; then
        err "Не удалось установить NetBird."
        return 1
    fi
    ok "NetBird установлен."
    
    # Настройка
    if ! ask_yes_no "Настроить NetBird сейчас?" "y"; then
        info "Настройте позже: sudo netbird up"
        return 0
    fi
    
    local setup_key management_url=""
    read -rsp "$(printf '%s' "${CYAN}Введите setup key (или пусто для входа через браузер): ${NC}")" setup_key
    printf '\n'
    
    local -a nb_args=(up)
    if [[ -n "$setup_key" ]]; then
        nb_args+=(--setup-key "$setup_key")
    fi
    if ask_yes_no "Использовать кастомный сервер NetBird?" "n"; then
        read -rp "$(printf '%s' "${CYAN}Введите URL сервера: ${NC}")" management_url
        if _validate_url "$management_url"; then
            nb_args+=(--management-url "$management_url")
        else
            warn "Некорректный URL, используется сервер по умолчанию."
        fi
    fi
    
    info "Подключение к NetBird..."
    if ! netbird "${nb_args[@]}"; then
        warn "Не удалось подключиться к NetBird."
        return 1
    fi
    
    local nb_ip
    nb_ip=$(ip -4 addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
    ok "NetBird подключен. IP: $nb_ip"
    log "NetBird connected${management_url:+ (management-url: $management_url)}."
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_network_tools_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🌐 Сетевые инструменты"
        printf_description "Docker, VPN решения и мониторинг контейнеров."
        
        printf_menu_option "1" "Установить Docker"
        printf_menu_option "2" "Установить Tailscale VPN"
        printf_menu_option "3" "Установить NetBird VPN"
        printf_menu_option "4" "Установить dtop (Docker мониторинг)"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _install_docker ;;
            2) _install_tailscale ;;
            3) _install_netbird ;;
            4) _install_dtop ;;
            b|B) break ;;
            *) err "Нет такого пункта." ;;
        esac
    done
    disable_graceful_ctrlc
}
