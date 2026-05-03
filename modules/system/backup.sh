#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: БЭКАПЫ (RSYNC)               == #
# ============================================================ #
# Настройка автоматических бэкапов через rsync over SSH.
# Версия: 1.0.0.

#
# @menu.manifest
#
# @item( main | 9 | 💾 Бэкапы (rsync) | show_backup_menu | 90 | 90 | Настройка автоматических бэкапов )
# @item( backup | 1 | Настроить бэкапы | _setup_backup | 10 | 10 | Конфигурация rsync over SSH )
# @item( backup | 2 | Проверить бэкап | _test_backup | 20 | 10 | Тестовый запуск бэкапа )
# @item( backup | 3 | Статус бэкапов | _backup_status | 30 | 10 | Просмотр настроек и крона )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

_validate_backup_dest() {
    local dest="$1"
    if [[ "$dest" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

_validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    else
        return 1
    fi
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_setup_backup() {
    local section="Настройка бэкапов (rsync over SSH)"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    if ! ask_yes_no "Настроить автоматические бэкапы через rsync?" "y"; then
        info "Пропуск настройки бэкапов."
        return 0
    fi
    
    local username="${USERNAME:-root}"
    if ! id "$username" &>/dev/null; then
        err "Пользователь '$username' не существует."
        return 1
    fi
    
    # Генерация SSH ключа для root если нет
    local root_ssh_dir="/root/.ssh"
    local root_ssh_key="$root_ssh_dir/id_ed25519"
    if [[ ! -f "$root_ssh_key" ]]; then
        info "Генерация SSH ключа для root..."
        mkdir -p "$root_ssh_dir" && chmod 700 "$root_ssh_dir"
        ssh-keygen -t ed25519 -f "$root_ssh_key" -N "" -q
        chown -R root:root "$root_ssh_dir"
        ok "SSH ключ для root сгенерирован: $root_ssh_key"
    else
        info "SSH ключ для root уже существует."
    fi
    
    # Сбор данных о бэкапе
    local backup_dest backup_port remote_path
    while true; do
        read -rp "$(printf '%s' "${CYAN}Введите цель бэкапа (user@host): ${NC}")" backup_dest
        if _validate_backup_dest "$backup_dest"; then break; else print_error "Неверный формат. Ожидается user@host."; fi
    done
    
    while true; do
        read -rp "$(printf '%s' "${CYAN}Введите порт SSH [22]: ${NC}")" backup_port
        backup_port=${backup_port:-22}
        if _validate_port "$backup_port"; then break; else print_error "Неверный порт."; fi
    done
    
    while true; do
        read -rp "$(printf '%s' "${CYAN}Введите удаленный путь (например, /home/backups/): ${NC}")" remote_path
        if [[ "$remote_path" =~ ^/[^[:space:]]*/$ ]]; then break; else print_error "Путь должен начинаться с / и заканчиваться на /"; fi
    done
    
    info "Цель бэкапа: ${backup_dest}:${remote_path} (порт $backup_port)"
    
    # Копирование ключа
    if ask_yes_no "Скопировать SSH ключ на удаленный сервер?" "y"; then
        info "Копирование ключа..."
        if ssh-copy-id -i "$root_ssh_key.pub" -p "$backup_port" "$backup_dest" 2>&1 | tee -a "$LOG_FILE"; then
            ok "Ключ скопирован."
        else
            warn "Не удалось скопировать ключ автоматически."
            info "Скопируйте вручную: cat ${root_ssh_key}.pub | ssh -p $backup_port $backup_dest 'cat >> ~/.ssh/authorized_keys'"
        fi
    fi
    
    # Тест подключения
    if ask_yes_no "Проверить SSH подключение?" "y"; then
        info "Тест подключения..."
        if ssh -p "$backup_port" -o BatchMode=yes -o ConnectTimeout=10 "$backup_dest" true 2>&1 | tee -a "$LOG_FILE"; then
            ok "SSH подключение успешно."
        else
            warn "SSH подключение не удалось. Проверьте настройки."
        fi
    fi
    
    # Выбор директорий для бэкапа
    local backup_dirs_string="/home/${username}/"
    if ask_yes_no "Указать другие директории для бэкапа?" "n"; then
        read -rp "$(printf '%s' "${CYAN}Введите директории через пробел: ${NC}")" -a user_dirs
        if (( ${#user_dirs[@]} > 0 )); then
            backup_dirs_string="${user_dirs[*]}"
        fi
    fi
    info "Директории для бэкапа: $backup_dirs_string"
    
    # Создание скрипта бэкапа
    local backup_script="/root/run_backup.sh"
    cat > "$backup_script" <<EOF
#!/bin/bash
# Скрипт бэкапа, сгенерирован $(date)
set -euo pipefail
BACKUP_DIRS="$backup_dirs_string"
REMOTE_DEST="$backup_dest"
REMOTE_PATH="$remote_path"
SSH_PORT="$backup_port"
EXCLUDE_FILE="/root/rsync_exclude.txt"
LOG_FILE="/var/log/backup_rsync.log"

# Создание файла исключений
cat > "\$EXCLUDE_FILE" <<'EXCLUDE'
.cache/
.docker/
.local/
.npm/
.ssh/
.vscode-server/
*.log
*.tmp
node_modules/
.bashrc
.bash_history
.bash_logout
.cloud-locale-test.skip
.profile
EXCLUDE

echo "--- Starting Backup at \$(date) ---" >> "\$LOG_FILE"
rsync -avz --delete --exclude-from="\$EXCLUDE_FILE" -e "ssh -p \$SSH_PORT" \$BACKUP_DIRS "\${REMOTE_DEST}:\${REMOTE_PATH}" >> "\$LOG_FILE" 2>&1
echo "--- Backup completed at \$(date) ---" >> "\$LOG_FILE"
EOF
    chmod 700 "$backup_script"
    ok "Скрипт бэкапа создан: $backup_script"
    
    # Настройка cron
    local cron_schedule="5 3 * * *"
    read -rp "$(printf '%s' "${CYAN}Введите расписание cron [5 3 * * *]: ${NC}")" input_schedule
    cron_schedule=${input_schedule:-"5 3 * * *"}
    
    # Добавление в crontab
    if ! crontab -l 2>/dev/null | grep -q "$backup_script"; then
        (crontab -l 2>/dev/null; echo "$cron_schedule $backup_script") | crontab -
        ok "Задача добавлена в crontab."
    else
        info "Задача уже есть в crontab."
    fi
    
    # Тестовый запуск
    if ask_yes_no "Запустить тестовый бэкап сейчас?" "y"; then
        info "Запуск тестового бэкапа..."
        if bash "$backup_script" 2>&1 | tee -a "$LOG_FILE"; then
            ok "Тестовый бэкап завершен."
        else
            warn "Тестовый бэкап не удался. Проверьте логи."
        fi
    fi
    
    ok "Настройка бэкапов завершена."
    [[ $VERBOSE == true ]] && wait_for_enter
}

_test_backup() {
    local backup_script="/root/run_backup.sh"
    if [[ ! -f "$backup_script" ]]; then
        err "Скрипт бэкапа не найден: $backup_script"
        return 1
    fi
    
    info "Запуск тестового бэкапа..."
    if bash "$backup_script" 2>&1 | tee -a "$LOG_FILE"; then
        ok "Тестовый бэкап успешен."
    else
        err "Тестовый бэкап не удался."
        return 1
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_backup_status() {
    menu_header "Статус бэкапов"
    
    local backup_script="/root/run_backup.sh"
    if [[ -f "$backup_script" ]]; then
        ok "Скрипт бэкапа найден: $backup_script"
        echo ""
        info "Содержимое скрипта:"
        cat "$backup_script" | head -20
        echo ""
    else
        warn "Скрипт бэкапа не найден."
    fi
    
    info "Задачи в crontab:"
    crontab -l 2>/dev/null | grep -i backup || echo "  Нет задач бэкапа в crontab."
    
    if [[ -f "/var/log/backup_rsync.log" ]]; then
        info "Последние записи лога:"
        tail -10 "/var/log/backup_rsync.log"
    fi
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_backup_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "💾 Бэкапы (rsync)"
        printf_description "Настройка автоматических бэкапов через rsync over SSH."
        
        printf_menu_option "1" "Настроить бэкапы"
        printf_menu_option "2" "Проверить бэкап"
        printf_menu_option "3" "Статус бэкапов"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _setup_backup ;;
            2) _test_backup ;;
            3) _backup_status ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
