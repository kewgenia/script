#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: АУДИТ И ОЧИСТКА              == #
# ============================================================ #
# Аудит безопасности (Lynis/debsecan) и очистка пакетов провайдера.
# Версия: 1.0.0.

#
# @menu.manifest
#
# @item( main | 11 | 🔍 Аудит и Очистка | show_audit_cleanup_menu | 110 | 110 | Проверка безопасности и очистка )
# @item( audit_cleanup | 1 | Запустить аудит безопасности | _run_security_audit | 10 | 10 | Lynis и debsecan )
# @item( audit_cleanup | 2 | Очистка пакетов провайдера | _cleanup_provider_packages | 20 | 10 | Удаление пакетов VPS )
# @item( audit_cleanup | 3 | Финальная очистка системы | _final_cleanup | 30 | 10 | Обновление и очистка )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

# Проверка, является ли система Debian
_is_debian() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "debian" ]]; then
            return 0
        fi
    fi
    return 1
}

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_run_security_audit() {
    local section="Аудит безопасности"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    if ! ask_yes_no "Запустить аудит безопасности с помощью Lynis?" "y"; then
        info "Аудит безопасности пропущен."
        return 0
    fi
    
    local audit_log="/var/log/setup_harden_security_audit_$(date +%Y%m%d_%H%M%S).log"
    touch "$audit_log" && chmod 600 "$audit_log"
    
    # Установка Lynis
    info "Установка Lynis..."
    if ! apt-get update -qq; then
        err "Не удалось обновить списки пакетов."
        return 1
    fi
    
    if ! apt-get install -y -qq lynis; then
        warn "Не удалось установить Lynis."
        return 1
    fi
    
    # Запуск аудита
    info "Запуск аудита Lynis (это займет несколько минут)..."
    warn "Результаты аудита будут в $audit_log"
    
    if lynis audit system --quick >> "$audit_log" 2>&1; then
        ok "Аудит Lynis завершен. Проверьте $audit_log"
        log "Lynis audit completed."
        
        # Извлечение индекса hardening
        local hardening_index
        hardening_index=$(grep -oP "Hardening index : \K\d+" "$audit_log" || echo "Unknown")
        info "Индекс hardening: $hardening_index"
        
        # Извлечение топ-5 рекомендаций
        grep "Suggestion:" /var/log/lynis-report.dat 2>/dev/null | head -n 5 > /tmp/lynis_suggestions.txt || true
        if [[ -s /tmp/lynis_suggestions.txt ]]; then
            info "Топ-5 рекомендаций:"
            cat /tmp/lynis_suggestions.txt
        fi
    else
        err "Аудит Lynis не удался. Проверьте $audit_log"
        return 1
    fi
    
    # Debsecan (только для Debian)
    if _is_debian; then
        if ask_yes_no "Также запустить debsecan для проверки уязвимостей?" "y"; then
            info "Установка debsecan..."
            if ! apt-get install -y -qq debsecan; then
                warn "Не удалось установить debsecan."
            else
                info "Запуск debsecan..."
                if debsecan --suite "$VERSION_CODENAME" >> "$audit_log" 2>&1; then
                    local vuln_count
                    vuln_count=$(grep -c "CVE-" "$audit_log" || echo "0")
                    print_warning "Найдено уязвимостей: $vuln_count"
                    log "debsecan audit completed with $vuln_count vulnerabilities."
                else
                    err "Аудит debsecan не удался."
                fi
            fi
        fi
    else
        info "debsecan не поддерживается в Ubuntu."
    fi
    
    warn "Просмотрите результаты аудита в $audit_log"
    [[ $VERBOSE == true ]] && wait_for_enter
}

_cleanup_provider_packages() {
    local section="Очистка пакетов провайдера"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    # Определение окружения
    if ! command -v detect_environment >/dev/null 2>&1; then
        warn "Функция detect_environment недоступна. Пропуск."
        return 0
    fi
    detect_environment
    
    # Вывод информации об окружении
    info "Тип виртуализации: ${DETECTED_VIRT_TYPE:-unknown}"
    info "Производитель: ${DETECTED_MANUFACTURER:-unknown}"
    info "Продукт: ${DETECTED_PRODUCT:-unknown}"
    info "Тип окружения: ${ENVIRONMENT_TYPE:-unknown}"
    
    if [[ "$ENVIRONMENT_TYPE" == "bare-metal" ]]; then
        info "Обнаружен физический сервер. Очистка не требуется."
        return 0
    fi
    
    # Определение рекомендаций
    local cleanup_recommended=false
    local default_answer="n"
    
    case "$ENVIRONMENT_TYPE" in
        commercial-cloud)
            cleanup_recommended=true
            default_answer="y"
            warn "☁  Обнаружен коммерческий облачный VPS"
            info "Очистка РЕКОМЕНДУЕТСЯ для облачных VPS."
            ;;
        uncertain-kvm)
            warn "⚠  KVM/QEMU виртуализация (неопределенно)"
            info "Возможно: облачный VPS или личный VM."
            info "Очистка ОПЦИОНАЛЬНА."
            ;;
        personal-vm)
            info "ℹ  Личный VM (VirtualBox, VMware и т.д.)"
            info "Очистка НЕ РЕКОМЕНДУЕТСЯ."
            ;;
        *)
            warn "⚠  Неопределенное окружение."
            info "Очистка ОПЦИОНАЛЬНА."
            ;;
    esac
    
    if [[ "$cleanup_recommended" == "false" ]]; then
        if ! ask_yes_no "Продолжить очистку пакетов провайдера?" "n"; then
            info "Очистка пропущена."
            return 0
        fi
    else
        if ! ask_yes_no "Запустить очистку пакетов провайдера?" "$default_answer"; then
            info "Очистка пропущена."
            return 0
        fi
    fi
    
    # Создание резервной копии
    local backup_dir="/root/setup-backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir" && chmod 700 "$backup_dir"
    info "Резервная копия будет сохранена в $backup_dir"
    
    # Список пакетов провайдера
    local common_provider_pkgs=(
        "qemu-guest-agent"
        "virtio-utils"
        "virt-what"
        "cloud-init"
        "cloud-guest-utils"
        "cloud-initramfs-growroot"
        "cloud-utils"
        "open-vm-tools"
        "xe-guest-utilities"
        "xen-tools"
        "hyperv-daemons"
        "oracle-cloud-agent"
        "aws-systems-manager-agent"
        "amazon-ssm-agent"
        "google-compute-engine"
        "google-osconfig-agent"
        "walinuxagent"
        "hetzner-needrestart"
        "digitalocean-agent"
        "do-agent"
        "linode-agent"
        "vultr-monitoring"
        "scaleway-ecosystem"
        "ovh-rtm"
    )
    
    local found_pkgs=()
    for pkg in "${common_provider_pkgs[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            found_pkgs+=("$pkg")
            info "Найден пакет: $pkg"
        fi
    done
    
    if (( ${#found_pkgs[@]} == 0 )); then
        ok "Пакетов провайдера не обнаружено."
        return 0
    fi
    
    # Удаление пакетов
    for pkg in "${found_pkgs[@]}"; do
        if [[ "$pkg" == "cloud-init" ]]; then
            if ask_yes_no "Отключить cloud-init (рекомендуется)?" "y"; then
                touch /etc/cloud/cloud-init.disabled
                ok "cloud-init отключен."
                # Не удаляем, просто отключаем
                continue
            fi
        fi
        
        if ask_yes_no "Удалить пакет $pkg?" "n"; then
            if apt-get remove --purge -y "$pkg" >> "$LOG_FILE" 2>&1; then
                ok "Пакет $pkg удален."
            else
                warn "Не удалось удалить $pkg."
            fi
        fi
    done
    
    # Очистка
    apt-get autoremove --purge -y >> "$LOG_FILE" 2>&1 || true
    apt-get autoclean -y >> "$LOG_FILE" 2>&1 || true
    
    ok "Очистка пакетов провайдера завершена."
    [[ $VERBOSE == true ]] && wait_for_enter
}

_final_cleanup() {
    local section="Финальная очистка и обновление"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    info "Выполнение финального обновления системы..."
    info "Это может занять некоторое время..."
    
    # Обновление пакетов
    if ! apt-get update -qq >> "$LOG_FILE" 2>&1; then
        warn "Не удалось обновить списки пакетов."
    fi
    
    if DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >> "$LOG_FILE" 2>&1; then
        ok "Система успешно обновлена (включая ядро)."
    else
        warn "Финальное обновление столкнулось с проблемами. Проверьте лог."
    fi
    
    # Очистка
    info "Удаление неиспользуемых пакетов..."
    apt-get --purge autoremove -y -qq >> "$LOG_FILE" 2>&1 || true
    apt-get autoclean -y -qq >> "$LOG_FILE" 2>&1 || true
    
    systemctl daemon-reload
    ok "Финальная очистка завершена."
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_audit_cleanup_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🔍 Аудит и Очистка"
        printf_description "Аудит безопасности и очистка системы от пакетов провайдера."
        
        printf_menu_option "1" "Аудит безопасности (Lynis/debsecan)"
        printf_menu_option "2" "Очистка пакетов провайдера"
        printf_menu_option "3" "Финальная очистка системы"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _run_security_audit ;;
            2) _cleanup_provider_packages ;;
            3) _final_cleanup ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
