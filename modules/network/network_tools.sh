#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: СЕТЕВЫЕ ИНСТРУМЕНТЫ            == #
# ============================================================ #
# Установка и настройка Docker, Tailscale, NetBird.
# Версия: 1.0.0.

#
# @menu.manifest
#
# @item( main | 8 | 🌐 Сетевые инструменты | show_network_tools_menu | 80 | 80 | Docker, VPN, мониторинг )
# @item( network_tools | 1 | Установить Docker | _install_docker | 10 | 10 | Docker Engine и docker-compose )
# @item( network_tools | 2 | Установить Tailscale VPN | _install_tailscale | 20 | 10 | Настройка Tailscale )
# @item( network_tools | 3 | Установить NetBird VPN | _install_netbird | 30 | 10 | Настройка NetBird )
# @item( network_tools | 4 | Установить dtop (Docker мониторинг) | _install_dtop | 40 | 10 | TUI для Docker контейнеров )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

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
    local section="Установка Docker"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    if command -v docker >/dev/null 2>&1; then
        info "Docker уже установлен."
        return 0
    fi
    
    if ! ask_yes_no "Установить Docker Engine?" "y"; then
        info "Пропуск установки Docker."
        return 0
    fi
    
    info "Удаление старых версий..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    info "Добавление репозитория Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    
    info "Установка Docker пакетов..."
    if ! apt-get update -qq || ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        err "Не удалось установить Docker."
        return 1
    fi
    
    # Настройка daemon.json
    local daemon_config="/etc/docker/daemon.json"
    mkdir -p /etc/docker
    cat > /tmp/docker-daemon.json <<'EOF'
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
    
    if [[ -f "$daemon_config" ]] && cmp -s /tmp/docker-daemon.json "$daemon_config"; then
        info "Конфигурация Docker уже корректна."
        rm -f /tmp/docker-daemon.json
    else
        mv /tmp/docker-daemon.json "$daemon_config"
        chmod 644 "$daemon_config"
        ok "Конфигурация Docker обновлена."
    fi
    
    # Добавление пользователя в группу docker
    local username="${USERNAME:-root}"
    if getent group docker >/dev/null || groupadd docker; then
        if ! groups "$username" | grep -qw docker; then
            usermod -aG docker "$username"
            ok "Пользователь '$username' добавлен в группу docker."
        fi
    fi
    
    systemctl daemon-reload
    systemctl enable --now docker
    
    # Проверка
    info "Проверка Docker..."
    if sudo -u "$username" docker run --rm hello-world 2>&1 | tee -a "$LOG_FILE" | grep -q "Hello from Docker"; then
        ok "Docker успешно установлен и работает."
    else
        warn "Тест Docker не прошел. Проверьте установку."
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_install_dtop() {
    if command -v dtop >/dev/null 2>&1; then
        info "dtop уже установлен."
        return 0
    fi
    
    if ! ask_yes_no "Установить dtop (Docker мониторинг)?" "y"; then
        return 0
    fi
    
    local installer="/tmp/dtop-installer.sh"
    if ! curl -fsSL "https://github.com/amir20/dtop/releases/latest/download/dtop-installer.sh" -o "$installer"; then
        warn "Не удалось скачать установщик dtop."
        return 1
    fi
    
    chmod +x "$installer"
    local user_home="$HOME"
    if [[ -n "${USERNAME:-}" ]]; then
        user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
    fi
    
    local user_local_bin="$user_home/.local/bin"
    mkdir -p "$user_local_bin"
    
    if sudo -u "$USERNAME" bash "$installer" < /dev/null >> "$LOG_FILE" 2>&1; then
        if [[ -f "$user_local_bin/dtop" ]]; then
            sudo -u "$USERNAME" chmod +x "$user_local_bin/dtop"
            ok "dtop установлен в $user_local_bin/dtop"
            # Добавление в PATH если нужно
            local bashrc="$user_home/.bashrc"
            if [[ -f "$bashrc" ]] && ! grep -q "\.local/bin" "$bashrc"; then
                echo '' >> "$bashrc"
                echo '# Add local bin to PATH' >> "$bashrc"
                echo 'if [ -d "$HOME/.local/bin" ]; then PATH="$HOME/.local/bin:$PATH"; fi' >> "$bashrc"
                ok "PATH обновлен в $bashrc"
            fi
        fi
    else
        warn "Установка dtop не удалась."
    fi
    rm -f "$installer"
}

_install_tailscale() {
    local section="Установка Tailscale VPN"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    if command -v tailscale >/dev/null 2>&1; then
        if systemctl is-active --quiet tailscaled && tailscale ip >/dev/null 2>&1; then
            local ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
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
    read -rp "$(printf '%s' "${CYAN}Введите pre-auth key (или пусто для стандартного метода): ${NC}")" auth_key
    
    local ts_command="tailscale up"
    if [[ -n "$auth_key" ]]; then
        ts_command="$ts_command --auth-key=$auth_key"
    fi
    
    if ask_yes_no "Использовать кастомный сервер Tailscale?" "n"; then
        read -rp "$(printf '%s' "${CYAN}Введите URL сервера: ${NC}")" login_server
        if [[ -n "$login_server" ]]; then
            ts_command="$ts_command --login-server=$login_server"
        fi
    fi
    
    info "Подключение к Tailscale..."
    if ! $ts_command; then
        warn "Не удалось подключиться к Tailscale."
        return 1
    fi
    
    local ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
    ok "Tailscale подключен. IP: $ts_ip"
    log "Tailscale connected: $ts_command"
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_install_netbird() {
    local section="Установка NetBird VPN"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    if command -v netbird >/dev/null 2>&1; then
        if systemctl is-active --quiet netbird && netbird status 2>/dev/null | grep -q "Connected"; then
            local nb_ip=$(ip -4 addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
            ok "NetBird уже активен. IP: $nb_ip"
            return 0
        fi
    fi
    
    if ! ask_yes_no "Установить и настроить NetBird?" "y"; then
        info "Пропуск установки NetBird."
        return 0
    fi
    
    # Установка зависимостей и репозитория
    apt-get install -y ca-certificates curl gnupg
    curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --output /usr/share/keyrings/netbird-archive-keyring.gpg 2>/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' > /etc/apt/sources.list.d/netbird.list
    
    if ! apt-get update -qq || ! apt-get install -y netbird; then
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
    read -rp "$(printf '%s' "${CYAN}Введите setup key: ${NC}")" setup_key
    
    local nb_command="netbird up --setup-key $setup_key"
    if ask_yes_no "Использовать кастомный сервер NetBird?" "n"; then
        read -rp "$(printf '%s' "${CYAN}Введите URL сервера: ${NC}")" management_url
        if [[ -n "$management_url" ]]; then
            nb_command="$nb_command --management-url $management_url"
        fi
    fi
    
    info "Подключение к NetBird..."
    if ! $nb_command; then
        warn "Не удалось подключиться к NetBird."
        return 1
    fi
    
    local nb_ip=$(ip -4 addr show wt0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
    ok "NetBird подключен. IP: $nb_ip"
    
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
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
