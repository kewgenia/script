#!/bin/bash
# ============================================================ #
# ==           ТЕСТЫ SERVER SETUP                           == #
# ============================================================ #
# Проверяют хелперы ядра, парсер манифестов, валидаторы и
# конфигурацию --auto. Не требуют root и не меняют систему.
# Запуск: bash tests/run_tests.sh

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '  \e[32m✓\e[0m %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  \e[31m✗ %s\e[0m\n' "$1"; }

# assert_true "описание" команда...
assert_true() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

assert_false() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$name"; else pass "$name"; fi
}

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name (ожидалось '$expected', получено '$actual')"
    fi
}

# --- Загрузка модулей без root: лог и бэкапы во временной папке ---
export TERM=dumb
# shellcheck source=../modules/core/common.sh
source "$ROOT_DIR/modules/core/common.sh"
LOG_FILE="$TMP_DIR/test.log"
BACKUP_DIR="$TMP_DIR/backup"
SCRIPT_DIR="$ROOT_DIR"
for module in security/system_update.sh security/mirror_check.sh security/user_management.sh \
              security/ssh_hardening.sh security/firewall.sh security/intrusion_prevention.sh \
              system/auto_updates.sh system/system_hardening.sh network/network_tools.sh \
              system/backup.sh system/resource_management.sh system/audit_cleanup.sh \
              core/custom_bashrc.sh core/auto_setup.sh core/environment.sh; do
    # shellcheck source=/dev/null
    source "$ROOT_DIR/modules/$module"
done

echo "Синтаксис"
for file in "$ROOT_DIR"/server-setup.sh "$ROOT_DIR"/install.sh "$ROOT_DIR"/modules/*/*.sh; do
    assert_true "bash -n ${file#"$ROOT_DIR"/}" bash -n "$file"
done

echo "Ввод: ask_yes_no и safe_read"
assert_true  "Enter при умолчании y"   bash -c "source '$ROOT_DIR/modules/core/common.sh'; LOG_FILE=/dev/null; ask_yes_no q y <<< ''"
assert_false "Enter при умолчании n"   bash -c "source '$ROOT_DIR/modules/core/common.sh'; LOG_FILE=/dev/null; ask_yes_no q n <<< ''"
assert_true  "Ответ 'д' = да"          bash -c "source '$ROOT_DIR/modules/core/common.sh'; LOG_FILE=/dev/null; ask_yes_no q n <<< 'д'"
assert_false "EOF без умолчания = нет" bash -c "source '$ROOT_DIR/modules/core/common.sh'; LOG_FILE=/dev/null; ask_yes_no q < /dev/null"
assert_false "safe_read: код ошибки при EOF" bash -c "source '$ROOT_DIR/modules/core/common.sh'; safe_read p < /dev/null"
AUTO_MODE=true
assert_true  "AUTO_MODE: умолчание y без ввода" ask_yes_no "q" "y"
assert_false "AUTO_MODE: умолчание n без ввода" ask_yes_no "q" "n"
AUTO_MODE=false

echo "Валидаторы"
assert_eq    "_convert_to_mb 2G"   "2048" "$(_convert_to_mb 2G)"
assert_eq    "_convert_to_mb 512M" "512"  "$(_convert_to_mb 512M)"
assert_false "_convert_to_mb 2.5G отклонен" _convert_to_mb 2.5G
assert_false "_convert_to_mb abc отклонен"  _convert_to_mb abc
assert_true  "имя deploy"    is_valid_username deploy
assert_false "имя 'Bad User'" is_valid_username "Bad User"
assert_false "имя 1abc"      is_valid_username 1abc
assert_true  "порт 443/tcp"  _validate_port_format 443/tcp
assert_false "порт 70000"    _validate_port_format 70000
assert_false "порт 0"        _validate_port_format 0
assert_true  "ключ ed25519"  _validate_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl user@pc"
assert_false "мусор вместо ключа" _validate_ssh_key "hello world"
assert_false "пустой ключ"        _validate_ssh_key ""

echo "Манифесты меню"
_parse_all_manifests
assert_true "манифесты найдены" test "${#_MANIFEST_ITEMS[@]}" -gt 10
assert_eq   "заголовок со скобками не обрезается" "show_firewall_menu" "$(get_menu_action main 4)"
assert_eq   "зеркала APT на клавише m" "show_mirror_check_menu" "$(get_menu_action main m)"
assert_false "несуществующий пункт" get_menu_action main zz

main_keys=$(for item in "${_MANIFEST_ITEMS[@]}"; do IFS='|' read -ra p <<< "$item"; [[ "$(_trim "${p[0]}")" == "main" ]] && _trim "${p[1]}" && echo; done | sort)
assert_eq "клавиши главного меню уникальны" "" "$(uniq -d <<< "$main_keys")"

missing=""
for item in "${_MANIFEST_ITEMS[@]}"; do
    IFS='|' read -ra p <<< "$item"
    action=$(_trim "${p[3]:-}")
    [[ -n "$action" ]] && ! declare -F "$action" >/dev/null && missing+="$action "
done
assert_eq "все функции из манифестов существуют" "" "$missing"

first=$(render_menu_items main | sed 's/\x1b\[[0-9;]*m//g' | grep -m1 ')')
assert_true "сортировка по ORDER: первым идет пункт m" grep -q "m)" <<< "$first"

echo "Конфигурация --auto"
_validate_timezone() { [[ "$1" == "Europe/Moscow" || "$1" == "Etc/UTC" ]]; }
config="$TMP_DIR/server.conf"
cp "$ROOT_DIR/config/server.conf.example" "$config"
chmod 600 "$config"
sed -i 's|^CFG_SSH_KEY=""|CFG_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl user@pc"|' "$config"
if [[ "$(id -u)" -eq 0 ]]; then
    assert_true "пример конфигурации загружается" auto_load_config "$config"
    chmod 666 "$config"
    assert_false "конфиг с записью для всех отклоняется" auto_load_config "$config"
    chmod 600 "$config"
    auto_load_config "$config"
else
    # Без root проверка владельца не пройдет — загружаем напрямую
    _auto_set_defaults
    # shellcheck source=/dev/null
    source "$config"
fi
assert_true "пример конфигурации валиден" auto_validate_config
CFG_USER="Bad User"; CFG_SWAP_SIZE="2.5G"; CFG_SSH_PORT="99999"; CFG_UFW_ALLOW_PORTS="80/tcp abc"
: > "$LOG_FILE"
assert_false "ошибки конфигурации обнаружены" auto_validate_config
errors=$(grep -c "\[ERROR\] CFG_" "$LOG_FILE")
assert_eq "найдены все 4 ошибки за один проход" "4" "$errors"

echo ""
printf 'Пройдено: %d, провалено: %d\n' "$PASSED" "$FAILED"
(( FAILED == 0 ))
