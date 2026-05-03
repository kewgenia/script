# План удаления "VPS" и ребрендинга проекта

## Концепция
Проект переименовывается в **Server Setup** — инструмент для первоначальной настройки, установки ПО и администрирования серверов под управлением Debian/Ubuntu.

## 1. Переименование файлов

| Было | Станет |
|------|--------|
| `vps-security-setup.sh` | `server-setup.sh` |
| `docs/vps-security-initial-setup.md` | `docs/server-initial-setup.md` |

## 2. Обновление путей установки

| Было | Станет |
|------|--------|
| `/opt/vps-security-setup` | `/opt/server-setup` |
| Команда `vps-security-setup` | `server-setup` |
| Симлинк `/usr/local/bin/vps-security-setup` | `/usr/local/bin/server-setup` |
| Лог-файл `/var/log/vps-security-setup.log` | `/var/log/server-setup.log` |

## 3. Обновление описания проекта

**Старое:** "Модульный скрипт для первоначальной настройки и усиления безопасности VPS серверов (Debian/Ubuntu)"

**Новое:** "Модульный инструмент для первоначальной настройки, установки ПО и администрирования серверов (Debian/Ubuntu)"

## 4. Адаптация текста

### В русском тексте:
- "VPS серверов" → "серверов"
- "настройки VPS" → "настройки сервера"
- "защита VPS" → "защита сервера"
- "аренде VPS" → "аренде сервера"

### В английском тексте и названиях:
- "VPS Security Initial Setup" → "Server Setup"
- "VPS SECURITY" → "SERVER SETUP"
- "VPS Security Setup" → "Server Setup"

### Теги в статье:
- "vps" → "server"

## 5. Список файлов для редактирования

### `.instructions`
- Строка 1: "Инструкции для ассистента проекта VPS Security Initial Setup" → "Инструкции для ассистента проекта Server Setup"
- Строка 18: обновить PROJECT_DESCRIPTION
- Строка 25: INSTALL_PATH=/opt/server-setup

### `server-setup.sh` (бывший `vps-security-setup.sh`)
- Строка 3: "VPS SECURITY INITIAL SETUP" → "SERVER SETUP"
- Строка 5: "Главный скрипт для первоначальной настройки безопасности VPS" → "Главный скрипт для первоначальной настройки и администрирования сервера"
- Строка 14: LOG_FILE="/var/log/server-setup.log"
- Строка 84: menu_header "🛡️ Server Setup"

### `RELEASE_NOTES.md`
- Заголовок: "VPS Security Initial Setup - Релиз v2.0" → "Server Setup - Релиз v2.0"
- Описание: убрать VPS, обновить под полный функционал
- Пути установки: /opt/server-setup
- Команды запуска: server-setup

### `README.md`
- Заголовок: "🛡️ VPS Security Initial Setup" → "🛡️ Server Setup"
- Описание: обновить под полный функционал настройки и администрирования
- Команды запуска: server-setup
- Бейджи: обновить описание

### `install.sh`
- Строка 3: "СКРИПТ УСТАНОВКИ VPS SECURITY" → "СКРИПТ УСТАНОВКИ SERVER SETUP"
- Строка 5-6: обновить описание и пути
- Строка 34: INSTALL_DIR="/opt/server-setup"
- Строка 35: LINK_PATH="/usr/local/bin/server-setup"
- Строка 38: "Установка VPS Security Initial Setup" → "Установка Server Setup"

### `CHANGELOG.md`
- Строка 3: обновить описание проекта
- Строка 31: обновить имя файла документации
- Строка 37: обновить имя файла в истории изменений

### `docs/Структура.md`
- Строка 2: обновить имя файла и описание
- Строка 5: обновить имя конфигурационного файла (опционально)
- Строка 7: обновить описание install.sh

### `docs/server-initial-setup.md` (бывший `docs/vps-security-initial-setup.md`)
- title: убрать VPS
- tags: заменить "vps" на "server"
- description: убрать VPS
- Текст статьи: заменить все упоминания VPS на "сервер"

### `modules/security/mirror_check.sh`
- Строка 135: "VPS Security Setup" → "Server Setup"
- Строка 187: "VPS Security Setup" → "Server Setup"

### Дополнительная проверка
- `docs/GUIDE_MODULES.md` - проверить на упоминания VPS
- `docs/STYLE_GUIDE.md` - проверить на упоминания VPS
- Выполнить поиск по проекту на оставшиеся упоминания "vps" (строчными)

## 6. Порядок выполнения

1. Переименование файлов (vps-security-setup.sh → server-setup.sh, docs/vps-security-initial-setup.md → docs/server-initial-setup.md)
2. Обновление .instructions
3. Обновление server-setup.sh
4. Обновление install.sh (пути и имена)
5. Обновление README.md
6. Обновление RELEASE_NOTES.md
7. Обновление CHANGELOG.md
8. Обновление docs/Структура.md
9. Обновление docs/server-initial-setup.md
10. Обновление modules/security/mirror_check.sh
11. Финальная проверка поиском на оставшиеся упоминания
