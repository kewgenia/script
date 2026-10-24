#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: АВТОМАТИЧЕСКАЯ НАСТРОЙКА (--auto)    == #
# ============================================================ #
# Неинтерактивная первоначальная настройка сервера по файлу
# конфигурации (config/server.conf). Использует те же функции,
# что и интерактивное меню.
# Версия: 1.0.0

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

# Результаты шагов для итогового отчета: "СТАТУС|Шаг|Комментарий"
AUTO_RESULTS=()
AUTO_GENERATED_PASSWORD=""

# === ЗАГРУЗКА И ПРОВЕРКА КОНФИГУРАЦИИ =====================

# Значения по умолчанию (переопределяются файлом конфигурации)
_auto_set_defaults() {
    CFG_USER=""
    CFG_SSH_KEY=""
    CFG_SUDO_NOPASSWD="no"
    CFG_SSH_PORT=""
    CFG_DISABLE_ROOT_LOGIN="yes"
    CFG_DISABLE_PASSWORD_AUTH="yes"
    CFG_HOSTNAME=""
    CFG_TIMEZONE=""
    CFG_SYSTEM_UPGRADE="yes"
    CFG_SWAP_SIZE="2G"
    CFG_TIME_SYNC="yes"
    CFG_KERNEL_HARDENING="yes"
    CFG_AUTO_UPDATES="yes"
    CFG_UFW="yes"
    CFG_UFW_ALLOW_PORTS=""
    CFG_FAIL2BAN="yes"
    CFG_DOCKER="no"
}

_is_yes() {
    [[ "${1,,}" =~ ^(yes|y|true|1|да)$ ]]
}

# Загружает конфигурацию. Файл исполняется как bash, поэтому принимается
# только файл root, недоступный для записи группе и остальным.
auto_load_config() {
    local config_file="$1"
    _auto_set_defaults

    if [[ ! -f "$config_file" ]]; then
        err "Файл конфигурации не найден: $config_file"
        info "Создайте его из примера: cp $SCRIPT_DIR/config/server.conf.example $config_file"
        return 1
    fi

    local owner perms
    owner=$(stat -c '%u' "$config_file")
    perms=$(stat -c '%a' "$config_file")
    if [[ "$owner" != "0" ]] || (( (8#$perms & 8#022) != 0 )); then
        err "Небезопасные права на $config_file (владелец должен быть root, без записи для группы и остальных)."
        info "Исправьте: chown root:root $config_file && chmod 600 $config_file"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$config_file"
    log "Загружена конфигурация: $config_file"
}

# Проверка значений конфигурации. Ошибки выводятся все сразу.
auto_validate_config() {
    local errors=0

    if ! is_valid_username "$CFG_USER"; then
        err "CFG_USER: некорректное или пустое имя пользователя '$CFG_USER'."
        errors=$((errors + 1))
    elif [[ "$CFG_USER" == "root" ]]; then
        err "CFG_USER: укажите обычного пользователя, а не root."
        errors=$((errors + 1))
    fi

    if [[ -n "$CFG_SSH_KEY" ]]; then
        if ! _validate_ssh_key "$CFG_SSH_KEY"; then
            err "CFG_SSH_KEY: неверный формат публичного ключа."
            errors=$((errors + 1))
        fi
    else
        local home=""
        id "$CFG_USER" &>/dev/null && home=$(getent passwd "$CFG_USER" | cut -d: -f6)
        if [[ -z "$home" || ! -s "$home/.ssh/authorized_keys" ]]; then
            err "CFG_SSH_KEY: ключ не задан, а у пользователя '$CFG_USER' нет authorized_keys."
            errors=$((errors + 1))
        fi
    fi

    if [[ -n "$CFG_SSH_PORT" ]] && { ! [[ "$CFG_SSH_PORT" =~ ^[0-9]+$ ]] || (( CFG_SSH_PORT < 1 || CFG_SSH_PORT > 65535 )); }; then
        err "CFG_SSH_PORT: неверный порт '$CFG_SSH_PORT'."
        errors=$((errors + 1))
    fi

    if [[ -n "$CFG_TIMEZONE" ]] && ! _validate_timezone "$CFG_TIMEZONE"; then
        err "CFG_TIMEZONE: неизвестный часовой пояс '$CFG_TIMEZONE'."
        errors=$((errors + 1))
    fi

    if [[ -n "$CFG_HOSTNAME" && ! "$CFG_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        err "CFG_HOSTNAME: некорректное имя хоста '$CFG_HOSTNAME'."
        errors=$((errors + 1))
    fi

    if [[ -n "$CFG_SWAP_SIZE" && "$CFG_SWAP_SIZE" != "0" ]] && ! _convert_to_mb "$CFG_SWAP_SIZE" >/dev/null; then
        err "CFG_SWAP_SIZE: неверный размер '$CFG_SWAP_SIZE' (примеры: 2G, 512M, 0)."
        errors=$((errors + 1))
    fi

    local port
    for port in $CFG_UFW_ALLOW_PORTS; do
        if ! _validate_port_format "$port"; then
            err "CFG_UFW_ALLOW_PORTS: неверный порт '$port'."
            errors=$((errors + 1))
        fi
    done

    if (( errors > 0 )); then
        err "Найдено ошибок в конфигурации: $errors. Настройка не выполнена."
        return 1
    fi
    ok "Конфигурация корректна."
}

# План действий (для --check и перед запуском)
auto_print_plan() {
    local yn
    _plan() { if _is_yes "$2"; then yn="${GREEN}да${NC}"; else yn="нет"; fi; printf '  %s: %s\n' "$1" "$yn"; }
    printf '\n%s\n' "${BOLD}План автоматической настройки:${NC}"
    _plan "Обновление системы" "$CFG_SYSTEM_UPGRADE"
    printf '  %s: %s\n' "Пользователь (sudo, SSH-ключ)" "$CFG_USER"
    printf '  %s: %s\n' "Имя хоста" "${CFG_HOSTNAME:-без изменений}"
    printf '  %s: %s\n' "Часовой пояс" "${CFG_TIMEZONE:-без изменений}"
    printf '  %s: %s\n' "Swap" "${CFG_SWAP_SIZE:-0}"
    _plan "Синхронизация времени (chrony)" "$CFG_TIME_SYNC"
    _plan "Настройки безопасности ядра" "$CFG_KERNEL_HARDENING"
    _plan "Автообновления безопасности" "$CFG_AUTO_UPDATES"
    _plan "Фаервол UFW" "$CFG_UFW"
    [[ -n "$CFG_UFW_ALLOW_PORTS" ]] && printf '  %s: %s\n' "  дополнительные порты" "$CFG_UFW_ALLOW_PORTS"
    printf '  %s: %s\n' "Порт SSH" "${CFG_SSH_PORT:-без изменений}"
    _plan "Запрет входа root по SSH" "$CFG_DISABLE_ROOT_LOGIN"
    _plan "Запрет входа по паролю" "$CFG_DISABLE_PASSWORD_AUTH"
    _plan "Fail2Ban" "$CFG_FAIL2BAN"
    _plan "Docker" "$CFG_DOCKER"
    printf '\n'
    unset -f _plan
}

# === ШАГИ НАСТРОЙКИ =====================

# Запуск шага с записью результата. Аргументы: название, функция.
_auto_step() {
    local title="$1" func="$2"
    print_section "$title"
    if "$func"; then
        AUTO_RESULTS+=("OK|$title|")
    else
        AUTO_RESULTS+=("FAIL|$title|см. $LOG_FILE")
        warn "Шаг «$title» завершился с ошибкой. Продолжаем."
        return 1
    fi
}

_auto_skip() {
    AUTO_RESULTS+=("SKIP|$1|${2:-}")
}

_auto_system_upgrade() {
    run_cmd "apt-get update" || return 1
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade"
}

_auto_user() {
    if ! id "$CFG_USER" &>/dev/null; then
        _create_user_account "$CFG_USER" || return 1
    else
        info "Пользователь '$CFG_USER' уже существует."
    fi

    [[ -n "$CFG_SSH_KEY" ]] && { _add_ssh_key_to_user "$CFG_USER" "$CFG_SSH_KEY" || return 1; }
    _add_user_to_sudo "$CFG_USER" || return 1

    if _is_yes "$CFG_SUDO_NOPASSWD"; then
        local sudoers="/etc/sudoers.d/90-server-setup-$CFG_USER"
        echo "$CFG_USER ALL=(ALL) NOPASSWD:ALL" > "$sudoers.tmp"
        chmod 440 "$sudoers.tmp"
        if visudo -cf "$sudoers.tmp" >/dev/null 2>&1; then
            mv "$sudoers.tmp" "$sudoers"
            ok "sudo без пароля включен для '$CFG_USER'."
        else
            rm -f "$sudoers.tmp"
            err "Ошибка проверки файла sudoers."
            return 1
        fi
    elif [[ "$(passwd -S "$CFG_USER" 2>/dev/null | awk '{print $2}')" != "P" ]]; then
        # Без пароля пользователь не сможет выполнять sudo
        AUTO_GENERATED_PASSWORD=$(_generate_password)
        if echo "$CFG_USER:$AUTO_GENERATED_PASSWORD" | chpasswd; then
            ok "Для '$CFG_USER' сгенерирован пароль (будет показан в итоговом отчете)."
        else
            AUTO_GENERATED_PASSWORD=""
            err "Не удалось установить пароль."
            return 1
        fi
    fi
}

_auto_hostname() { _apply_hostname "$CFG_HOSTNAME"; }
_auto_timezone() { _apply_timezone "$CFG_TIMEZONE"; }

_auto_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q .; then
        info "Swap уже настроен — пропуск."
        return 0
    fi
    if systemd-detect-virt --container --quiet 2>/dev/null; then
        info "В контейнере swap не настраивается."
        return 0
    fi
    local size_mb avail_mb
    size_mb=$(_convert_to_mb "$CFG_SWAP_SIZE") || return 1
    avail_mb=$(( $(df -k --output=avail / | tail -n 1) / 1024 ))
    if (( avail_mb < size_mb + 1024 )); then
        err "Недостаточно места для swap ${size_mb}M (свободно ${avail_mb}M)."
        return 1
    fi
    _create_swap_file /swapfile "$size_mb" || return 1
    _write_swap_sysctl 10 50
}

_auto_firewall() {
    _ensure_ufw_installed || return 1
    local -a extra_ports=()
    read -ra extra_ports <<< "$CFG_UFW_ALLOW_PORTS"
    # Новый порт SSH открываем заранее: модуль SSH проверит, что он доступен
    if [[ -n "$CFG_SSH_PORT" ]]; then
        extra_ports+=("$CFG_SSH_PORT/tcp")
    fi
    _ufw_enable "${extra_ports[@]}"
}

_auto_ssh() {
    _ssh_prepare || return 1

    # Последняя защита от потери доступа: ключ пользователя должен быть на месте
    local home
    home=$(getent passwd "$CFG_USER" | cut -d: -f6)
    if [[ ! -s "$home/.ssh/authorized_keys" ]] || ! id -nG "$CFG_USER" | grep -qw sudo; then
        err "У '$CFG_USER' нет SSH-ключа или прав sudo — настройка SSH пропущена во избежание потери доступа."
        return 1
    fi

    local permit_root="prohibit-password" password_auth="no"
    _is_yes "$CFG_DISABLE_ROOT_LOGIN" && permit_root="no"
    _is_yes "$CFG_DISABLE_PASSWORD_AUTH" || password_auth="yes"
    [[ "$password_auth" == "yes" && "$permit_root" != "no" ]] && permit_root="yes"

    _apply_ssh_hardening "${CFG_SSH_PORT:-$CURRENT_SSH_PORT}" "$permit_root" "$password_auth"
}

_auto_fail2ban() { _configure_fail2ban; }
_auto_time_sync() { _configure_time_sync; }
_auto_kernel() { _apply_kernel_hardening; }
_auto_updates() { _enable_auto_updates; }
_auto_docker() { _install_docker; }

# === ИТОГОВЫЙ ОТЧЕТ =====================

auto_print_summary() {
    local entry status title note color failed=0
    printf '\n%s\n' "${BOLD}${BLUE}============ Итог автоматической настройки ============${NC}"
    for entry in "${AUTO_RESULTS[@]}"; do
        IFS='|' read -r status title note <<< "$entry"
        case "$status" in
            OK)   color="$GREEN"; status="готово" ;;
            FAIL) color="$RED"; status="ошибка"; failed=$((failed + 1)) ;;
            *)    color="$YELLOW"; status="пропуск" ;;
        esac
        printf '  %s%-8s%s %s%s\n' "$color" "$status" "$NC" "$title" "${note:+ — $note}"
    done

    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    printf '\n  Подключение: %sssh -p %s %s@%s%s\n' "$CYAN" "$(get_ssh_port)" "$CFG_USER" "${ip:-IP_СЕРВЕРА}" "$NC"
    if [[ -n "$AUTO_GENERATED_PASSWORD" ]]; then
        # Пароль выводится только на экран, в лог не пишется
        printf '  Пароль sudo для %s: %s%s%s (смените командой passwd)\n' "$CFG_USER" "$BOLD" "$AUTO_GENERATED_PASSWORD" "$NC"
    fi
    if [[ -f /var/run/reboot-required ]]; then
        printf '  %sТребуется перезагрузка сервера (reboot).%s\n' "$YELLOW" "$NC"
    fi
    printf '  Журнал: %s\n\n' "$LOG_FILE"
    warn "Проверьте вход в НОВОМ терминале, прежде чем закрывать текущую сессию."
    log "Auto setup finished: ${#AUTO_RESULTS[@]} steps, $failed failed."
    (( failed == 0 ))
}

# === ГЛАВНАЯ ФУНКЦИЯ =====================

# run_automated_setup <файл конфигурации> [check]
run_automated_setup() {
    local config_file="$1" check_only="${2:-}"
    AUTO_MODE=true

    auto_load_config "$config_file" || return 1
    auto_validate_config || return 1
    auto_print_plan
    if [[ "$check_only" == "check" ]]; then
        info "Режим проверки: изменения не вносились."
        return 0
    fi

    log "Запуск автоматической настройки."
    if _is_yes "$CFG_SYSTEM_UPGRADE"; then _auto_step "Обновление системы" _auto_system_upgrade; else _auto_skip "Обновление системы"; fi

    # Без пользователя с ключом настраивать SSH опасно
    local user_ok=true
    _auto_step "Пользователь $CFG_USER" _auto_user || user_ok=false

    if [[ -n "$CFG_HOSTNAME" ]]; then _auto_step "Имя хоста" _auto_hostname; else _auto_skip "Имя хоста"; fi
    if [[ -n "$CFG_TIMEZONE" ]]; then _auto_step "Часовой пояс" _auto_timezone; else _auto_skip "Часовой пояс"; fi
    if [[ -n "$CFG_SWAP_SIZE" && "$CFG_SWAP_SIZE" != "0" ]]; then _auto_step "Swap" _auto_swap; else _auto_skip "Swap"; fi
    if _is_yes "$CFG_TIME_SYNC"; then _auto_step "Синхронизация времени" _auto_time_sync; else _auto_skip "Синхронизация времени"; fi
    if _is_yes "$CFG_KERNEL_HARDENING"; then _auto_step "Настройки ядра" _auto_kernel; else _auto_skip "Настройки ядра"; fi
    if _is_yes "$CFG_AUTO_UPDATES"; then _auto_step "Автообновления" _auto_updates; else _auto_skip "Автообновления"; fi
    if _is_yes "$CFG_UFW"; then _auto_step "Фаервол UFW" _auto_firewall; else _auto_skip "Фаервол UFW"; fi

    if [[ "$user_ok" == true ]]; then
        _auto_step "Настройка SSH" _auto_ssh
    else
        _auto_skip "Настройка SSH" "пользователь не настроен"
    fi

    # Fail2Ban — после SSH, чтобы защищать уже новый порт
    if _is_yes "$CFG_FAIL2BAN"; then _auto_step "Fail2Ban" _auto_fail2ban; else _auto_skip "Fail2Ban"; fi
    if _is_yes "$CFG_DOCKER"; then _auto_step "Docker" _auto_docker; else _auto_skip "Docker"; fi

    auto_print_summary
}
