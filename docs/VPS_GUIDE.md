# Работа с удалённым VPS

Инструкция описывает работу с VPS-сервером (Debian 11–13, Ubuntu 20.04–24.04) из Windows.

- **[Способ 1 (основной)](#способ-1-основной-claude-code-на-vps--remote-control)** — Claude Code прямо на сервере с управлением с телефона или из браузера через Remote Control.
- **[Способ 2](#способ-2-vs-code--remote-ssh)** — VS Code с расширением Remote-SSH: редактор на вашем компьютере, файлы и терминал — на сервере.
- **[Способ 3](#способ-3-установка-и-настройка-сервера-скриптом-server-setup)** — первоначальная настройка и защита сервера скриптом Server Setup. На новом сервере её стоит выполнить до способов 1 и 2.

> Пока исправления не влиты в `main`, используйте ветку `claude/vps-setup-script-review-0wy78q`.

---

## Способ 1 (основной). Claude Code на VPS + Remote Control

Claude Code устанавливается прямо на сервер и работает там постоянно, а вы управляете им с телефона (вкладка **Code** в приложении Claude) или из браузера (`claude.ai/code`). Держать включённым компьютер с открытым терминалом не нужно.

### 1.1. Что понадобится

- Подписка claude.ai: Pro, Max, Team или Enterprise. Со входом по ключу API Remote Control не работает.
- VPS и SSH-доступ к нему. Если сервер новый, сначала выполните базовую настройку скриптом Server Setup ([способ 3](#способ-3-установка-и-настройка-сервера-скриптом-server-setup)): обычный пользователь с sudo и вход по SSH-ключу.
- Оперативная память: рекомендуется от 4 ГБ. На небольших VPS добавьте swap (пункт 10 скрипта).

### 1.2. Подключение и установка

Подключайтесь под обычным пользователем, а не под root:

```bash
ssh ИМЯ@IP_СЕРВЕРА            # или ssh -p ПОРТ ИМЯ@IP_СЕРВЕРА, или ssh myvps (раздел 2.4)
sudo apt update
sudo apt install -y git curl tmux
curl -fsSL https://claude.ai/install.sh | bash
claude --version
```

Если `claude` не находится, добавьте `~/.local/bin` в PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 1.3. Проект и вход в аккаунт

```bash
git clone -b claude/vps-setup-script-review-0wy78q https://github.com/kewgenia/script.git ~/script
claude auth login
```

На сервере нет браузера, поэтому Claude Code покажет ссылку. Откройте её на компьютере или телефоне, войдите в claude.ai и подтвердите доступ. Если появится код, вставьте его в терминал.

### 1.4. Запуск Remote Control в tmux

1. `tmux new -s claude`
2. `cd ~/script`
3. `claude remote-control`
4. На вопрос о доверии к папке ответьте `y` — только если это ваш проект.
5. На вопрос «Enable Remote Control?» ответьте `y`.
6. Режим запуска (Spawn mode) — `1` (same-dir).

Не запускайте Remote Control в домашней папке целиком: Claude получит доступ ко всем файлам пользователя.

Отключиться, не останавливая Claude: `Ctrl+B`, затем `D`. Вернуться: `ssh ИМЯ@IP_СЕРВЕРА`, затем `tmux attach -t claude`. Остановить — `Ctrl+C` в окне tmux.

### 1.5. Работа с телефона и из браузера

1. Откройте приложение Claude → вкладка **Code**, или `claude.ai/code` в браузере.
2. Выберите ваш сервер и начните новую сессию.
3. Пишите задачи обычным языком: «Покажи статус UFW и Fail2Ban», «Найди в логах причину ошибки».
4. Перед изменением файлов и выполнением команд Claude запрашивает разрешение — подтверждайте только то, что понимаете.

### 1.6. Запуск после перезагрузки

Сессия tmux пропадает после перезагрузки VPS. Можно снова выполнить шаги 1.4 или добавить задачу в `crontab -e`:

```
@reboot tmux new -d -s claude "cd ~/script && ~/.local/bin/claude remote-control --spawn=same-dir"
```

Сначала хотя бы раз запустите Remote Control вручную. Если после перезагрузки сервер не появился в приложении, подключитесь (`tmux attach -t claude`) и проверьте, не ждёт ли запуск ответа на вопрос.

### 1.7. Безопасность и частые проблемы

- Запускайте Claude от обычного пользователя и только в папке проекта.
- Не поручайте Claude менять SSH и фаервол без доступа к VNC-консоли провайдера.
- Не храните пароли и токены в файлах проекта.

| Сообщение | Решение |
|---|---|
| `You must be logged in to use Remote Control` | `claude auth login` |
| `Remote Control is only available with claude.ai subscriptions` | Выполнен вход по ключу API: `claude auth logout`, затем `claude auth login` с аккаунтом claude.ai |
| `claude: command not found` | Добавьте `~/.local/bin` в PATH (раздел 1.2) |
| Сервер не появляется в приложении | Проверьте `tmux attach -t claude`, обновите страницу |
| Установка прерывается с `Killed` | Не хватает памяти — добавьте swap |

---

## Способ 2. VS Code + Remote-SSH

### 2.1. Установка

1. Установите VS Code с [code.visualstudio.com](https://code.visualstudio.com).
2. В расширениях (`Ctrl+Shift+X`) установите **Remote - SSH** (Microsoft).

### 2.2. SSH-ключ

В терминале VS Code (**Terminal → New Terminal**, это PowerShell):

```powershell
ssh-keygen -t ed25519
```

`C:\Users\<имя>\.ssh\id_ed25519` — секретный ключ, никому не передавайте; `id_ed25519.pub` — публичный.

### 2.3. Копирование ключа на сервер

```powershell
type $HOME\.ssh\id_ed25519.pub | ssh root@IP_СЕРВЕРА "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### 2.4. Файл ~/.ssh/config

`F1` → **Remote-SSH: Open SSH Configuration File…** → `C:\Users\<имя>\.ssh\config`:

```
Host myvps
    HostName IP_СЕРВЕРА
    User root
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

После настройки сервера скриптом замените `User` на созданного пользователя и `Port` на новый порт SSH.

### 2.5. Подключение и работа

1. `F1` → **Remote-SSH: Connect to Host…** → `myvps` → платформа **Linux**.
2. Подключение установлено, когда в левом нижнем углу появится **SSH: myvps**.
3. **File → Open Folder…** — папка на сервере; **Terminal → New Terminal** — терминал на сервере.
4. Расширение **Claude Code** можно установить прямо в это окно (**Install in SSH: myvps**).

| Проблема | Решение |
|---|---|
| `Could not establish connection` | Проверьте `HostName`, `User`, `Port`; запустите `ssh -v myvps` |
| `Permission denied (publickey)` | Ключ не скопирован или указан не тот `IdentityFile` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | `ssh-keygen -R IP_СЕРВЕРА` (с портом: `ssh-keygen -R "[IP]:ПОРТ"`) |
| Зависание после обновления VS Code | `F1` → **Remote-SSH: Kill VS Code Server on Host…** |

---

## Способ 3. Установка и настройка сервера скриптом Server Setup

### 3.1. Подстраховка

1. Сделайте **снапшот** сервера в панели провайдера.
2. Узнайте, где открывается **VNC/веб-консоль** — запасной вход при закрытом SSH.
3. Создайте SSH-ключ и скопируйте его на сервер (разделы 2.2–2.3).

### 3.2. Установка

```bash
ssh root@IP_СЕРВЕРА
apt update && apt install -y git
git clone -b claude/vps-setup-script-review-0wy78q https://github.com/kewgenia/script.git
cd script && bash install.sh
```

После слияния в `main` достаточно одной команды:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kewgenia/script/main/install.sh)
```

Скрипт устанавливается в `/opt/server-setup`, команда запуска — `server-setup` (не под root — `sudo server-setup`).

### 3.3. Вариант А: автоматическая настройка (`--auto`)

Вся первоначальная настройка одной командой по файлу конфигурации:

```bash
cd /opt/server-setup
cp config/server.conf.example config/server.conf
chmod 600 config/server.conf
nano config/server.conf          # укажите CFG_USER и CFG_SSH_KEY (содержимое id_ed25519.pub)
server-setup --auto --check      # проверка конфигурации и план, без изменений
server-setup --auto              # настройка
```

Порядок шагов: обновление системы → пользователь с sudo и ключом → имя хоста и часовой пояс → swap → синхронизация времени → настройки ядра → автообновления → UFW (заранее открывает новый порт SSH) → SSH (порт, запрет root и паролей) → Fail2Ban → Docker (по желанию).

Защита от потери доступа:

- SSH настраивается, только если у пользователя есть ключ и права sudo; иначе шаг пропускается.
- Перед перезапуском SSH проверяется конфигурация (`sshd -t`), после — что сервер слушает новый порт. При любой ошибке изменения откатываются.
- Ошибка одного шага не прерывает остальные; в конце выводится отчёт.
- Если для sudo нужен пароль (`CFG_SUDO_NOPASSWD="no"`), он генерируется и показывается **только в итоговом отчёте** — сохраните его и смените командой `passwd`.

В авторежиме подтвердить вход по новым настройкам некому, поэтому **после завершения проверьте вход в новом терминале**, не закрывая текущую сессию: `ssh -p ПОРТ ИМЯ@IP_СЕРВЕРА`. Параметр `--quiet` оставляет только ошибки и итоговый отчёт.

### 3.4. Вариант Б: интерактивное меню

```bash
server-setup
```

| Клавиша | Пункт |
|---|---|
| `m` | Зеркала APT |
| `1` | Обновление системы |
| `2` | Управление пользователями |
| `3` | Настройка SSH и 2FA |
| `4` | Фаервол UFW |
| `5` | Защита Fail2Ban/CrowdSec |
| `6` | Автообновления |
| `7` | Система и ядро |
| `8` | Сетевые инструменты (Docker, Tailscale, NetBird) |
| `9` | Бэкапы (rsync) |
| `10` | Ресурсы (swap, время) |
| `11` | Аудит и очистка |
| `12` | Кастомизация .bashrc |

В подменю `b` — назад. В вопросах «да/нет» заглавная буква (`Y/n`, `y/N`) — ответ по умолчанию для Enter.

Рекомендуемый порядок:

1. **Зеркала APT (m)** — по желанию, если обновления медленные.
2. **Обновление системы (1)** → «ПОЛНОЕ ОБНОВЛЕНИЕ», при необходимости `reboot`.
3. **Пользователь (2 → 1)**: имя, пароль для sudo, публичный ключ (`Get-Content $HOME\.ssh\id_ed25519.pub` в PowerShell), группа sudo.
4. **Проверьте вход** в новом окне: `ssh ИМЯ@IP_СЕРВЕРА`, затем `sudo whoami` → `root`. Не продолжайте, пока это не работает.
5. **SSH (3 → 1)**: запрет паролей и root, новый порт. Скрипт попросит проверить вход в отдельном окне; ответ `n` откатывает изменения.
6. **UFW (4 → 1)**: открывает текущий порт SSH и включает фаервол; порты сайта — «Открыть порт» (`80/tcp`, `443/tcp`).
7. **Fail2Ban (5 → 1)**: добавьте свой IP в исключения.
8. **Автообновления (6)**, **система (7)**: часовой пояс, имя хоста, настройки ядра.
9. **Ресурсы (10)**: swap при RAM до 4 ГБ, синхронизация времени.
10. По необходимости: Docker (опубликованные порты обходят UFW — публикуйте на `127.0.0.1`), VPN, бэкапы, аудит Lynis.

### 3.5. Логи, бэкапы, восстановление

- `/var/log/server-setup.log` — журнал действий скрипта.
- `/root/setup-backup_*` — копии изменённых настроек; `/etc/apt/backup-*` — копии источников APT.

Если потерян доступ по SSH:

1. Войдите через VNC-консоль провайдера под root.
2. `ufw disable`
3. `rm /etc/ssh/sshd_config.d/10-hardening.conf` (и `rm /etc/ssh/sshd_config.d/95-2fa-*.conf`, если включали 2FA).
4. `systemctl daemon-reload && systemctl restart ssh` (Ubuntu 24.04: `systemctl restart ssh.socket`).
5. Если не помогло — откат к снапшоту.

### 3.6. Обновление скрипта

```bash
cd ~/script && git pull && bash install.sh   # конфигурация config/server.conf сохраняется
```
