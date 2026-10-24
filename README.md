# 🛡️ Server Setup

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Linux](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)
![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)
[![CI](https://github.com/kewgenia/script/actions/workflows/ci.yml/badge.svg)](https://github.com/kewgenia/script/actions/workflows/ci.yml)

**Модульный инструмент для первоначальной настройки, установки ПО и администрирования серверов под управлением Debian/Ubuntu.**

Проект предоставляет интерактивное меню и режим автоматической настройки по файлу конфигурации (`--auto`) для рутинных задач по настройке и администрированию сервера, следуя лучшим практикам информационной безопасности.

---

## 🚀 Возможности

### ✅ Реализовано (v2.2.0)

| Модуль | Описание |
|---------|-----------|
| **👤 Управление пользователями** | Создание пользователей, настройка SSH-ключей, управление sudo-правами. |
| **🔒 Настройка SSH и 2FA** | Смена порта, отключение root, SSH-ключи, двухфакторная аутентификация. |
| **🛡️ Фаервол (UFW)** | Настройка правил UFW, поддержка IPv6, защита портов. |
| **🛡️ Защита (Fail2Ban/CrowdSec)** | Защита от брутфорса, мониторинг логов, блокировка IP. |
| **🔄 Автообновления** | Настройка unattended-upgrades для автоматических обновлений безопасности. |
| **⚙️ Система и Ядро** | Настройка sysctl, hostname, локализации, параметры ядра. |
| **🌐 Сетевые инструменты** | Docker, Tailscale, NetBird, мониторинг контейнеров (dtop). |
| **💾 Бэкапы (rsync)** | Автоматические бэкапы через rsync на удаленные серверы. |
| **⚙️ Ресурсы (Swap/Время)** | Настройка swap-файла, синхронизация времени (NTP). |
| **🔍 Аудит и Очистка** | Lynis аудит безопасности, очистка пакетов провайдеров. |
| **🎨 Кастомизация .bashrc** | Установка кастомного .bashrc с полезными алиасами. |
| **🔄 Обновление системы** | Полный цикл: `apt update`, `upgrade`, `autoremove`, очистка кэша. |
| **🌐 Зеркала APT** | Быстрая замена на Yandex Mirror, ручная настройка, бэкапы. |
| **🤖 Автонастройка (`--auto`)** | Первоначальная настройка сервера одной командой по `config/server.conf`. |

### 🔜 В планах развития

*   Создание пользовательского дашборда (dashboard)
*   Плагины для виджетов дашборда
*   Дополнительные инструменты мониторинга

---

## 🎉 Быстрый старт

### Установка одной командой

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kewgenia/script/main/install.sh)
```

### Установка вручную

```bash
# 1. Скачайте скрипт установки
curl -O https://raw.githubusercontent.com/kewgenia/script/main/install.sh

# 2. Сделайте его исполняемым
chmod +x install.sh

# 3. Запустите от имени root
sudo ./install.sh
```

### Использование

После установки команда `server-setup` будет доступна из любого места:

```bash
sudo server-setup                 # интерактивное меню
```

### Автоматическая настройка

```bash
cd /opt/server-setup
sudo cp config/server.conf.example config/server.conf
sudo chmod 600 config/server.conf
sudo nano config/server.conf      # пользователь, SSH-ключ, порт, часовой пояс…
sudo server-setup --auto --check  # проверка конфигурации и план без изменений
sudo server-setup --auto          # настройка
```

Подробнее — в [инструкции по работе с VPS](docs/VPS_GUIDE.md#33-вариант-а-автоматическая-настройка---auto).

---

## 📋 Требования

*   **ОС:** Debian 11+ или Ubuntu 20.04+
*   **Права:** Доступ к root (через `sudo`)
*   **Сеть:** Интернет-соединение для установки пакетов

---

## 📖 Документация

*   **[Руководство по стилю кода](docs/STYLE_GUIDE.md)** — стандарты оформления
*   **[Гайд по модулям](docs/GUIDE_MODULES.md)** — как создавать модули
*   **[Структура проекта](docs/Структура.md)** — описание архитектуры
*   **[Работа с удалённым VPS](docs/VPS_GUIDE.md)** — Claude Code с Remote Control, VS Code Remote-SSH, первоначальная настройка сервера

### Тесты

```bash
bash tests/run_tests.sh
shellcheck -x -S warning server-setup.sh install.sh modules/*/*.sh tests/*.sh
```

Те же проверки и smoke-тесты на Debian 12 и Ubuntu 24.04 запускаются в GitHub Actions для каждого pull request.

---

## 🤝 Вклад в проект

1. Сделайте fork репозитория
2. Создайте ветку для вашей фичи (`git checkout -b feature/amazing-feature`)
3. Закоммитьте изменения (`git commit -m 'Добавлена потрясающая фича'`)
4. Отправьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

---

## 📄 Лицензия

Проект распространяется под лицензией MIT. См. файл [LICENSE](LICENSE) для подробностей.

---

## 🔗 Ссылки

*   **GitHub:** [https://github.com/kewgenia/script](https://github.com/kewgenia/script)
*   **Журнал изменений:** [CHANGELOG.md](CHANGELOG.md)
*   **Примечания к релизу:** [RELEASE_NOTES.md](RELEASE_NOTES.md)
