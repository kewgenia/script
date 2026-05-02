---
title: "Первоначальная настройка VPS: защищаем сервер с нуля"
date: 2026-05-02T16:00:00+03:00
draft: false
tags: ["vps", "security", "linux", "ssh", "firewall"]
categories: ["Сетевая безопасность"]
description: "Пошаговое руководство по первоначальной настройке VPS сервера с акцентом на сетевую безопасность. Защищаем сервер от первых минут работы."
---

## Введение

После аренды VPS сервера большинство пользователей сразу приступают к установке необходимого ПО, забывая о базовой безопасности. Между тем, статистика показывает, что незащищенные серверы подвергаются атакам в течение первых нескольких минут после запуска. В этой статье разберем пошаговую настройку VPS с акцентом на сетевую безопасность.

## 1. Обновление системы

Первым делом обновляем систему до последних версий пакетов:

```bash
# Для Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# Для CentOS/RHEL
sudo yum update -y
```

Это закрывает известные уязвимости в установленном ПО.

## 2. Создание пользователя с ограниченными правами

Работать под root — плохая практика. Создаем отдельного пользователя:

```bash
# Создание пользователя
sudo adduser username

# Добавление в группу sudo (для Ubuntu/Debian)
sudo usermod -aG sudo username

# Для CentOS/RHEL
sudo usermod -aG wheel username
```

## 3. Настройка SSH-ключей

Аутентификация по паролю уязвима для brute-force атак. Используем SSH-ключи:

### На локальной машине:
```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

### Копирование ключа на сервер:
```bash
ssh-copy-id username@server_ip
```

### Настройка SSH-сервера

Редактируем конфигурацию SSH (`/etc/ssh/sshd_config`):

```bash
# Меняем порт (по умолчанию 22 — первая цель сканеров)
Port 2222

# Отключаем вход под root
PermitRootLogin no

# Разрешаем только аутентификацию по ключу
PasswordAuthentication no
PubkeyAuthentication yes

# Ограничиваем пользователей
AllowUsers username
```

Перезапускаем SSH:
```bash
sudo systemctl restart sshd
```

## 4. Настройка фаервола

### Для Ubuntu/Debian (UFW):

```bash
# Включаем фаервол
sudo ufw enable

# Разрешаем SSH (на новом порту)
sudo ufw allow 2222/tcp

# Разрешаем HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Проверяем статус
sudo ufw status verbose
```

### Для CentOS/RHEL (firewalld):

```bash
# Запуск и включение
sudo systemctl start firewalld
sudo systemctl enable firewalld

# Добавление правил
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## 5. Установка и настройка Fail2ban

Fail2ban блокирует IP-адреса, с которых происходят неудачные попытки входа:

```bash
# Установка
sudo apt install fail2ban -y  # Ubuntu/Debian
sudo yum install fail2ban -y   # CentOS/RHEL

# Создание локальной конфигурации
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Базовая настройка (в jail.local)
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = 2222
```

Запуск:
```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

## 6. Отключение ненужных служб

Проверяем запущенные службы:
```bash
sudo ss -tulpn
```

Отключаем все, что не используется:
```bash
sudo systemctl disable service_name
```

## 7. Настройка автоматических обновлений

Для Ubuntu/Debian:
```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Для CentOS/RHEL:
```bash
sudo yum install yum-cron -y
sudo systemctl enable yum-cron
sudo systemctl start yum-cron
```

## 8. Дополнительные меры защиты

### Ограничение прав доступа:
```bash
# Проверка прав на критические файлы
ls -la /etc/ssh/sshd_config
chmod 600 /etc/ssh/sshd_config
```

### Настройка двухфакторной аутентификации (опционально):
```bash
sudo apt install libpam-google-authenticator -y
google-authenticator
```

## Чек-лист безопасности

- [ ] Система обновлена
- [ ] Создан пользователь с sudo правами
- [ ] Настроена аутентификация по SSH-ключам
- [ ] Порт SSH изменен с 22 на нестандартный
- [ ] Вход под root отключен
- [ ] Настроен фаервол (UFW/firewalld)
- [ ] Установлен и настроен Fail2ban
- [ ] Отключены ненужные службы
- [ ] Настроены автоматические обновления

## Заключение

Первоначальная настройка VPS — это фундамент безопасности вашего сервера. Потратив 30 минут на базовую защиту, вы избавите себя от множества проблем в будущем. Помните: безопасность — это процесс, а не разовое действие. Регулярно проверяйте логи, обновляйте систему и следите за новыми уязвимостями.

---

**Полезные команды для мониторинга:**
```bash
# Просмотр попыток входа
sudo journalctl -u ssh | grep "Failed password"

# Статистика Fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

*Статья подготовлена для канала по сетевой безопасности. Подписывайтесь, чтобы не пропустить новые материалы!*
