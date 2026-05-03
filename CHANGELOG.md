# Журнал изменений (Changelog)

Все значимые изменения в проекте Server Setup документируются в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [2.2.0] - 2026-05-03

### Добавлено
- **11 новых модулей** для расширения функциональности:
  - `modules/security/user_management.sh` — управление пользователями (создание, SSH-ключи, sudo)
  - `modules/security/ssh_hardening.sh` — настройка SSH и 2FA
  - `modules/security/firewall.sh` — фаервол UFW (правила, IPv6)
  - `modules/security/intrusion_prevention.sh` — защита (Fail2Ban/CrowdSec)
  - `modules/system/auto_updates.sh` — автообновления (unattended-upgrades)
  - `modules/system/system_hardening.sh` — ядро и система (sysctl, hostname)
  - `modules/network/network_tools.sh` — сетевые инструменты (Docker, Tailscale, NetBird)
  - `modules/system/backup.sh` — бэкапы (rsync)
  - `modules/system/resource_management.sh` — ресурсы (swap, время)
  - `modules/system/audit_cleanup.sh` — аудит и очистка (Lynis, провайдеры)
  - `modules/core/custom_bashrc.sh` — кастомизация .bashrc

### Изменено
- **Улучшение существующих модулей:**
  - `modules/security/system_update.sh` — исправлены UI хелперы, обновлены переменные цветов, меню переведено на `render_menu_items`/`get_menu_action`
  - `modules/security/mirror_check.sh` — аналогичные улучшения для соответствия единому стилю

- **Соблюдение стандартов:**
  - Все модули соответствуют `docs/STYLE_GUIDE.md` и `docs/GUIDE_MODULES.md`
  - Используются функции из `modules/core/common.sh`: `info`, `ok`, `warn`, `err`, `ask_yes_no`, `safe_read`, `run_cmd`, `menu_header`, `printf_description`, `printf_menu_option`, `render_menu_items`, `get_menu_action`

### Планируется
- Добавление пользовательского дашборда (dashboard)
- Плагины для виджетов дашборда
- Расширение системы конфигурации (`config/server.conf`)

### Исправлено
- Исправлена кодировка файла `modules/core/common.sh` (удален BOM, исправлен русский текст, отображавшийся некорректно)

## [2.1.0] - 2026-05-03

### Добавлено
- **Реорганизация под архитектуру эталонного скрипта:**
  - Модульная структура с сохранением лучших практик
  - Улучшенное логирование с поддержкой уровней вывода
  - Система аргументов командной строки (`--help`, `--quiet`, `--auto`, `--version`)
  - Глобальные переменные конфигурации (`LOG_FILE`, `REPORT_FILE`, `BACKUP_DIR`, `VERBOSE`)
  - Обработка ошибок через `trap` и функцию `handle_error()`
  - Main flow с последовательным выполнением

- **Новые возможности:**
  - Модуль `modules/core/environment.sh` для определения окружения
    - Определение типа виртуализации (KVM, VMware, Docker и т.д.)
    - Определение провайдера (Hetzner, DigitalOcean и др.)
    - Определение типа окружения (commercial-cloud, personal-vm, bare-metal)
  - Поддержка `tput` для корректного отображения цветов в разных терминалах
  - Новые функции вывода: `print_header()`, `print_section()`, `print_success()`, `print_error()`, `print_warning()`, `print_info()`, `print_separator()`
  - Функция `check_dependencies()` для проверки зависимостей

- **Обновление модулей:**
  - `modules/core/common.sh` — полностью обновлен с улучшенным логированием
  - `modules/security/system_update.sh` — добавлена поддержка `$VERBOSE`
  - `modules/security/mirror_check.sh` — добавлена поддержка `$VERBOSE`

### Изменено
- **Рефакторинг главного скрипта:**
  - `server-setup.sh` — добавлен парсинг аргументов, функция `main()`, обработка `trap`
  - Удалены все упоминания эталонного скрипта из файлов проекта
  - Версию скрипта обновлена до v2.1.0

- **Обновление документации:**
  - `plans/plan.md` — детальный план реорганизации с диаграммой потока
  - Обновлены ссылки на версию в README.md и других файлах

### Исправлено
- Корректная обработка ошибок с использованием `trap ERR` и `trap EXIT`
- Улучшена проверка прав root с понятным выводом
- Исправлена логика тихого режима (`--quiet`)

## [2.0.1] - 2026-05-03

### Добавлено
- Файл инструкций `.instructions` для ассистента
- Журнал изменений `CHANGELOG.md`
- Поддержка установки одной командой через curl: `bash <(curl -Ls https://raw.githubusercontent.com/kewgenia/script/main/install.sh)`
- Автоматическое скачивание и распаковка репозитория при удаленной установке

### Изменено
- **Ребрендинг проекта:** удаление "VPS" из названия и контекста
  - Переименование `vps-security-setup.sh` → `server-setup.sh`
  - Переименование `docs/vps-security-initial-setup.md` → `docs/server-initial-setup.md`
  - Обновление путей установки: `/opt/server-setup`, команда `server-setup`
  - Обновление лог-файла: `/var/log/server-setup.log`
- Обновление `install.sh` с поддержкой удаленной установки и новыми путями
- Обновление `README.md` с профессиональным оформлением и командой установки одной строкой
- Обновление `RELEASE_NOTES.md` для версии v2.0 с новыми инструкциями
- Обновление документации: `docs/GUIDE_MODULES.md`, `docs/STYLE_GUIDE.md`, `docs/Структура.md`
- Обновление модулей: `modules/security/mirror_check.sh`, `modules/core/common.sh`

### Удалено
- Устаревшие файлы: `apt-mirror-check.sh`, `debian-update.sh`

## [2.0.0] - 2026-05-02

### Добавлено
- Модульная архитектура с автоматической генерацией меню через манифесты `@menu.manifest`
- Модуль управления зеркалами APT (`modules/security/mirror_check.sh`)
  - Быстрая замена репозиториев на Yandex Mirror
  - Ручная настройка зеркал
  - Создание бэкапов и восстановление конфигурации
  - Просмотр текущих репозиториев
- Обновленная документация:
  - `docs/STYLE_GUIDE.md` — строгий стандарт оформления кода
  - `docs/GUIDE_MODULES.md` — гайд по созданию модулей
  - `docs/Структура.md` — описание структуры проекта
  - `docs/server-initial-setup.md` — документация по настройке сервера
- Файл `RELEASE_NOTES.md` с описанием релиза
- Скрипт установки `install.sh` с улучшенной логикой
- Цветной вывод и улучшенный UI в главном меню

### Изменено
- Рефакторинг главного скрипта `server-setup.sh`
- Перемещение документации из корня в папку `docs/`
- Обновление `README.md` в профессиональном стиле

### Исправлено
- Корректная обработка запуска install.sh из директории установки
- Улучшена проверка создания симлинка

## [1.2.0] - 2026-04-29

### Добавлено
- Скрипт для управления APT репозиториями (`apt-mirror-check.sh`)
- Документация `APT_MIRROR_CHECK.md`
- Документация `DEBIAN_UPDATE.md`
- Папка `docs/` для централизованного хранения документации

### Изменено
- Перемещение документации из корня в папку `docs/`
- Обновление ссылок в `README.md`

## [1.1.0] - 2026-04-28

### Добавлено
- Скрипт обновления системы Debian (`debian-update.sh`)
- Документация к скрипту обновления
- Ссылки на документацию в коде

## [1.0.0] - 2026-04-28

### Добавлено
- Первоначальная структура проекта Server Setup
- Главный скрипт `server-setup.sh` с базовым меню
- Модуль обновления системы (`modules/security/system_update.sh`)
- Базовые функции ядра (`modules/core/common.sh`)
- Файл `README.md` с описанием проекта
- Лицензия MIT (`LICENSE`)

---

[2.2.0]: https://github.com/kewgenia/script/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/kewgenia/script/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/kewgenia/script/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/kewgenia/script/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/kewgenia/script/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/kewgenia/script/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kewgenia/script/releases/tag/v1.0.0
