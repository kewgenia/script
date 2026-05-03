#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: ОПРЕДЕЛЕНИЕ ОКРУЖЕНИЯ              == #
# ============================================================ #
# Этот модуль определяет тип виртуализации, провайдера и окружения.
# Версия: 2.1.0

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

# --- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ (экспортируются из common.sh) ---
# DETECTED_VIRT_TYPE, DETECTED_MANUFACTURER, DETECTED_PRODUCT
# ENVIRONMENT_TYPE, DETECTED_PROVIDER_NAME, IS_CONTAINER

# --- ОСНОВНАЯ ФУНКЦИЯ ОПРЕДЕЛЕНИЯ ОКРУЖЕНИЯ ---
detect_environment() {
    local VIRT_TYPE=""
    local MANUFACTURER=""
    local PRODUCT=""
    local IS_CLOUD_VPS=false
    local DETECTED_BIOS_VENDOR=""

    print_section "Определение окружения"

    # systemd-detect-virt
    if command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    fi

    # dmidecode для аппаратной информации
    if command -v dmidecode &>/dev/null && [[ $(id -u) -eq 0 ]]; then
        MANUFACTURER=$(dmidecode -s system-manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown")
        PRODUCT=$(dmidecode -s system-product-name 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown")
    fi

    # Проверка /sys/class/dmi/id/ (fallback, не требует dmidecode)
    if [[ -z "$MANUFACTURER" || "$MANUFACTURER" == "unknown" ]]; then
        if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
            MANUFACTURER=$(tr '[:upper:]' '[:lower:]' < /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "unknown")
        fi
    fi

    if [[ -z "$PRODUCT" || "$PRODUCT" == "unknown" ]]; then
        if [[ -r /sys/class/dmi/id/product_name ]]; then
            PRODUCT=$(tr '[:upper:]' '[:lower:]' < /sys/class/dmi/id/product_name 2>/dev/null || echo "unknown")
        fi
    fi

    if command -v dmidecode &>/dev/null && [[ $(id -u) -eq 0 ]]; then
        DETECTED_BIOS_VENDOR=$(dmidecode -s bios-vendor 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown")
    elif [[ -r /sys/class/dmi/id/bios_vendor ]]; then
        DETECTED_BIOS_VENDOR=$(tr '[:upper:]' '[:lower:]' < /sys/class/dmi/id/bios_vendor 2>/dev/null || echo "unknown")
    fi

    # Облачные провайдеры (паттерны для поиска)
    local CLOUD_PATTERNS=(
        # VPS/Cloud Providers
        "digitalocean" "linode" "vultr" "hetzner" "ovh" "scaleway" "contabo"
        "netcup" "ionos" "hostinger" "racknerd" "upcloud" "dreamhost"
        "kimsufi" "online.net" "equinix metal" "lightsail"
        # Major Cloud Platforms
        "amazon" "amazon ec2" "aws" "google" "gce" "google compute engine"
        "microsoft" "azure" "oracle cloud" "alibaba" "tencent" "rackspace"
        # Virtualization indicating cloud VPS
        "droplet" "linodekvm" "kvm" "openstack"
    )

    # Проверка соответствия производителя или продукта облачным паттернам
    for pattern in "${CLOUD_PATTERNS[@]}"; do
        if [[ "$MANUFACTURER" == *"$pattern"* ]] || [[ "$PRODUCT" == *"$pattern"* ]]; then
            IS_CLOUD_VPS=true
            break
        fi
    done

    # Дополнительные проверки на основе типа виртуализации
    case "$VIRT_TYPE" in
        kvm|qemu)
            if [[ -z "$IS_CLOUD_VPS" ]] || [[ "$IS_CLOUD_VPS" == "false" ]]; then
                if [[ -d /etc/cloud/cloud.cfg.d ]] && grep -qE "(Hetzner|DigitalOcean|Vultr|OVH)" /etc/cloud/cloud.cfg.d/* 2>/dev/null; then
                    IS_CLOUD_VPS=true
                fi
            fi
            ;;
        vmware)
            IS_CLOUD_VPS=false
            ;;
        oracle|virtualbox)
            IS_CLOUD_VPS=false
            ;;
        xen)
            IS_CLOUD_VPS=true
            ;;
        hyperv|microsoft)
            if [[ "$MANUFACTURER" == *"microsoft"* ]] && [[ "$PRODUCT" == *"virtual machine"* ]]; then
                IS_CLOUD_VPS=false
            fi
            ;;
        none)
            IS_CLOUD_VPS=false
            ;;
    esac

    # Определение типа окружения
    if [[ "$VIRT_TYPE" == "none" ]]; then
        ENVIRONMENT_TYPE="bare-metal"
    elif [[ "$IS_CLOUD_VPS" == "true" ]]; then
        ENVIRONMENT_TYPE="commercial-cloud"
    elif [[ "$VIRT_TYPE" =~ ^(kvm|qemu)$ ]]; then
        if [[ "$MANUFACTURER" == "qemu" && "$PRODUCT" =~ ^(standard pc|pc-|pc ) ]]; then
            ENVIRONMENT_TYPE="uncertain-kvm"
        else
            ENVIRONMENT_TYPE="commercial-cloud"
        fi
    elif [[ "$VIRT_TYPE" =~ ^(vmware|virtualbox|oracle)$ ]]; then
        ENVIRONMENT_TYPE="personal-vm"
    elif [[ "$VIRT_TYPE" == "xen" ]]; then
        ENVIRONMENT_TYPE="uncertain-xen"
    else
        ENVIRONMENT_TYPE="unknown"
    fi

    # Определение имени провайдера
    DETECTED_PROVIDER_NAME=""
    case "$ENVIRONMENT_TYPE" in
        commercial-cloud)
            if [[ "$MANUFACTURER" =~ digitalocean ]]; then
                DETECTED_PROVIDER_NAME="DigitalOcean"
            elif [[ "$MANUFACTURER" =~ hetzner ]]; then
                DETECTED_PROVIDER_NAME="Hetzner Cloud"
            elif [[ "$MANUFACTURER" =~ vultr ]]; then
                DETECTED_PROVIDER_NAME="Vultr"
            elif [[ "$MANUFACTURER" =~ linode || "$PRODUCT" =~ akamai ]]; then
                DETECTED_PROVIDER_NAME="Linode/Akamai"
            elif [[ "$MANUFACTURER" =~ ovh ]]; then
                DETECTED_PROVIDER_NAME="OVH"
            elif [[ "$MANUFACTURER" =~ amazon || "$PRODUCT" =~ "ec2" ]]; then
                DETECTED_PROVIDER_NAME="Amazon Web Services (AWS)"
            elif [[ "$MANUFACTURER" =~ google ]]; then
                DETECTED_PROVIDER_NAME="Google Cloud Platform"
            elif [[ "$MANUFACTURER" =~ microsoft ]]; then
                DETECTED_PROVIDER_NAME="Microsoft Azure"
            else
                DETECTED_PROVIDER_NAME="Cloud VPS Provider"
            fi
            ;;
        personal-vm)
            if [[ "$VIRT_TYPE" == "virtualbox" || "$MANUFACTURER" =~ innotek ]]; then
                DETECTED_PROVIDER_NAME="VirtualBox"
            elif [[ "$VIRT_TYPE" == "vmware" ]]; then
                DETECTED_PROVIDER_NAME="VMware"
            else
                DETECTED_PROVIDER_NAME="Personal VM"
            fi
            ;;
        uncertain-kvm)
            DETECTED_PROVIDER_NAME="KVM/QEMU Hypervisor"
            ;;
    esac

    # Экспорт результатов в глобальные переменные
    DETECTED_VIRT_TYPE="$VIRT_TYPE"
    DETECTED_MANUFACTURER="$MANUFACTURER"
    DETECTED_PRODUCT="$PRODUCT"
    DETECTED_BIOS_VENDOR="${DETECTED_BIOS_VENDOR:-unknown}"

    # Вывод информации об окружении
    if [[ $VERBOSE == true ]]; then
        echo ""
        print_info "=== Информация об окружении ==="
        printf 'Тип виртуализации: %s\n' "${DETECTED_VIRT_TYPE:-unknown}"
        printf 'Производитель: %s\n' "${DETECTED_MANUFACTURER:-unknown}"
        printf 'Продукт: %s\n' "${DETECTED_PRODUCT:-unknown}"
        printf 'Тип окружения: %s\n' "${ENVIRONMENT_TYPE:-unknown}"
        
        if [[ -n "${DETECTED_BIOS_VENDOR}" && "${DETECTED_BIOS_VENDOR}" != "unknown" ]]; then
            printf 'BIOS Vendor: %s\n' "${DETECTED_BIOS_VENDOR}"
        fi
        
        if [[ -n "${DETECTED_PROVIDER_NAME}" ]]; then
            printf 'Обнаружен провайдер: %s\n' "${DETECTED_PROVIDER_NAME}"
        fi
        echo ""
    fi

    log "Environment detection: VIRT=$VIRT_TYPE, MANUFACTURER=$MANUFACTURER, PRODUCT=$PRODUCT, IS_CLOUD=$IS_CLOUD_VPS, TYPE=$ENVIRONMENT_TYPE"
}

# --- ФУНКЦИЯ ОЧИСТКИ ОТ ПРОВАЙДЕРСКИХ ПАКЕТОВ (заглушка) ---
cleanup_provider_packages() {
    print_section "Очистка провайдерских пакетов (опционально)"
    
    # Проверка на тихий режим
    if [[ "$VERBOSE" == "false" ]]; then
        print_warning "Очистка провайдера не может быть запущена в тихом режиме из-за интерактивности."
        log "Очистка провайдера пропущена из-за тихого режима."
        return 0
    fi
    
    # Сначала определяем окружение
    detect_environment
    
    # Вывод информации об окружении
    printf '%s\n' "${CYAN}=== Обнаружение окружения ===${NC}"
    printf 'Тип виртуализации: %s\n' "${DETECTED_VIRT_TYPE:-unknown}"
    printf 'Производитель: %s\n' "${DETECTED_MANUFACTURER:-unknown}"
    printf 'Продукт: %s\n' "${DETECTED_PRODUCT:-unknown}"
    printf 'Тип окружения: %s\n' "${ENVIRONMENT_TYPE:-unknown}"
    
    if [[ -n "${DETECTED_BIOS_VENDOR}" && "${DETECTED_BIOS_VENDOR}" != "unknown" ]]; then
        printf 'BIOS Vendor: %s\n' "${DETECTED_BIOS_VENDOR}"
    fi
    
    if [[ -n "${DETECTED_PROVIDER_NAME}" ]]; then
        printf 'Обнаружен провайдер: %s\n' "${CYAN}${DETECTED_PROVIDER_NAME}${NC}"
    fi
    printf '\n'
    
    # Реализация очистки будет добавлена в будущем
    warn "Функция очистки провайдерских пакетов находится в разработке."
    info "Пока что рекомендуется вручную проверить наличие лишних пакетов."
    wait_for_enter
}
