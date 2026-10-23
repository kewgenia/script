#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: НАСТРОЙКА СИСТЕМЫ И ЯДРА       == #
# ============================================================ #
# Жесткие настройки ядра (sysctl), часового пояса, локали, имени хоста.
# Версия: 1.1.0

#
# @menu.manifest
#
# @item( main | 7 | ⚙️ Система и Ядро | show_system_hardening_menu | 70 | 10 | Настройка ядра и системы )
# @item( system_hardening | 1 | Настроить часовой пояс | _configure_timezone | 10 | 10 | timedatectl set-timezone )
# @item( system_hardening | 2 | Настроить локаль | _configure_locale | 20 | 10 | dpkg-reconfigure locales )
# @item( system_hardening | 3 | Настроить имя хоста | _configure_hostname | 30 | 10 | hostnamectl set-hostname )
# @item( system_hardening | 4 | Жесткие настройки ядра | _configure_kernel_hardening | 40 | 10 | sysctl security settings )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_validate_timezone() {
    local tz="$1"
    if timedatectl list-timezones 2>/dev/null | grep -q "^${tz}$"; then
        return 0
    else
        return 1
    fi
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_configure_timezone() {
    print_section "Настройка часового пояса"
    
    local current_tz
    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    info "Текущий часовой пояс: ${current_tz:-не определен}"
    
    local timezone
    read -rp "$(printf '%s' "${CYAN}Введите часовой пояс (например, Europe/Moscow) [${current_tz:-Etc/UTC}]: ${NC}")" timezone
    timezone=${timezone:-${current_tz:-Etc/UTC}}
    
    if ! _validate_timezone "$timezone"; then
        err "Неверный часовой пояс. Просмотрите список: timedatectl list-timezones"
        return 1
    fi
    
    if [[ "$current_tz" != "$timezone" ]]; then
        if run_cmd "timedatectl set-timezone $timezone"; then
            ok "Часовой пояс установлен: $timezone"
            log "Timezone set to $timezone."
        else
            err "Не удалось установить часовой пояс."
            return 1
        fi
    else
        info "Часовой пояс уже установлен: $timezone"
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_locale() {
    print_section "Настройка локали"
    
    if ask_yes_no "Настроить системные локали интерактивно?" "y"; then
        if ! dpkg -l locales 2>/dev/null | grep -q ^ii; then
            run_cmd "apt-get install -y locales" || { err "Не удалось установить пакет locales."; return 1; }
        fi
        # Диалог интерактивный — запускаем напрямую, а не через run_cmd (он пишет вывод в лог)
        if dpkg-reconfigure locales; then
            ok "Локали настроены."
            log "Locales reconfigured."
            info "Новая локаль применится при следующем входе в систему."
        else
            warn "Не удалось перенастроить локали."
        fi
    else
        info "Пропуск настройки локали."
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_hostname() {
    print_section "Настройка имени хоста"
    
    local current_hostname
    current_hostname=$(hostname 2>/dev/null || echo "unknown")
    info "Текущее имя хоста: $current_hostname"
    
    local new_hostname
    read -rp "$(printf '%s' "${CYAN}Введите имя хоста: ${NC}")" new_hostname
    if [[ -z "$new_hostname" ]]; then
        warn "Имя хоста не может быть пустым. Используется текущее."
        return 0
    fi
    # RFC 1123: метки из букв, цифр и '-', не начинаются/заканчиваются '-'
    if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]] || (( ${#new_hostname} > 253 )); then
        err "Некорректное имя хоста."
        return 1
    fi
    
    if [[ "$current_hostname" != "$new_hostname" ]]; then
        if run_cmd "hostnamectl set-hostname $new_hostname"; then
            ok "Имя хоста изменено на: $new_hostname"
            # Обновление /etc/hosts
            # Короткое имя добавляется как алиас для FQDN
            local hosts_entry="$new_hostname"
            [[ "$new_hostname" == *.* ]] && hosts_entry="$new_hostname ${new_hostname%%.*}"
            if ! grep -q "^127\.0\.1\.1" /etc/hosts; then
                echo "127.0.1.1 $hosts_entry" >> /etc/hosts
                ok "Добавлена запись в /etc/hosts"
            else
                sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$hosts_entry/" /etc/hosts
                ok "Обновлена запись в /etc/hosts"
            fi
            log "Hostname set to $new_hostname."
        else
            err "Не удалось изменить имя хоста."
            return 1
        fi
    else
        info "Имя хоста уже установлено: $new_hostname"
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_configure_kernel_hardening() {
    print_section "Жесткие настройки ядра (sysctl)"
    
    if ! ask_yes_no "Применить рекомендуемые настройки безопасности ядра (sysctl)?" "y"; then
        info "Пропуск настройки ядра."
        log "Kernel hardening skipped by user."
        return 0
    fi
    
    local sysctl_config="/etc/sysctl.d/99-du-hardening.conf"
    
    # Проверка идентичности (идемпотентность)
    local temp_config
    temp_config=$(mktemp)
    
    cat > "$temp_config" <<'EOF'
# Рекомендуемые настройки безопасности (Server Setup)
# Подробнее: https://www.kernel.org/doc/Documentation/sysctl/

# --- IPv4 Networking ---
# Защита от IP spoofing
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
# Блокировка SYN-FLOOD атак
net.ipv4.tcp_syncookies=1
# Игнорирование ICMP перенаправлений
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
# Не отправлять ICMP перенаправления (сервер не маршрутизатор)
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
# Игнорирование широковещательных ping и ложных ICMP ошибок
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
# Игнорирование source-routed пакетов
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
# Логирование martian пакетов
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1

# --- IPv6 Networking (если включено) ---
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0

# --- Kernel Security ---
# Включение ASLR для защиты памяти
kernel.randomize_va_space=2
# Ограничение доступа к указателям ядра
kernel.kptr_restrict=2
# Ограничение доступа к dmesg
kernel.dmesg_restrict=1
# Ограничение ptrace для защиты процессов
kernel.yama.ptrace_scope=1

# --- Filesystem Security ---
# Защита от TOCTOU (Time-of-Check to Time-of-Use)
fs.protected_hardlinks=1
fs.protected_symlinks=1
EOF
    
    # Проверка, нужно ли обновление
    if [[ -f "$sysctl_config" ]] && cmp -s "$temp_config" "$sysctl_config"; then
        info "Настройки ядра уже применены."
        rm -f "$temp_config"
        log "Kernel hardening settings already in place."
        return 0
    fi
    
    info "Применение настроек к $sysctl_config..."
    mv "$temp_config" "$sysctl_config"
    chmod 644 "$sysctl_config"
    
    info "Загрузка новых настроек..."
    # -e: пропускать параметры, отсутствующие в ядре (например, yama в контейнерах)
    local sysctl_out
    if sysctl_out=$(sysctl -e -p "$sysctl_config" 2>&1); then
        ok "Настройки ядра успешно применены."
        log "Applied kernel hardening settings."
    else
        warn "Часть параметров не применена (возможно, контейнер или старое ядро):"
        grep -i "error\|denied\|read-only" <<< "$sysctl_out" | head -n 10
        log "sysctl -p partially failed: $sysctl_out"
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_system_hardening_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "⚙️ Система и Ядро"
        printf_description "Настройка часового пояса, локали, имени хоста и защиты ядра."
        
        printf_menu_option "1" "Настроить часовой пояс"
        printf_menu_option "2" "Настроить локаль"
        printf_menu_option "3" "Настроить имя хоста"
        printf_menu_option "4" "Жесткие настройки ядра"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _configure_timezone ;;
            2) _configure_locale ;;
            3) _configure_hostname ;;
            4) _configure_kernel_hardening ;;
            b|B) break ;;
            *) err "Нет такого пункта." ;;
        esac
    done
    disable_graceful_ctrlc
}
