#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ: КАСТОМИЗАЦИЯ .BASHRC          == #
# ============================================================ #
# Установка кастомного .bashrc для пользователей.
# Версия: 1.0.0.

#
# @menu.manifest
#
# @item( main | 12 | 🎨 Кастомизация .bashrc | show_custom_bashrc_menu | 120 | 120 | Установка кастомного .bashrc )
# @item( custom_bashrc | 1 | Установить кастомный .bashrc | _install_custom_bashrc | 10 | 10 | Замена .bashrc пользователя )
# @item( custom_bashrc | 2 | Показать содержимое .bashrc | _show_bashrc | 20 | 10 | Просмотр текущего .bashrc )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# === ЛОКАЛЬНЫЕ ХЕЛПЕРЫ =====================

# === ОСНОВНЫЕ ФУНКЦИИ =====================

_install_custom_bashrc() {
    local section="Установка кастомного .bashrc"
    [[ $VERBOSE != false ]] && printf '\n%s\n' "${BLUE}▓▓▓ $section ▓▓▓${NC}" | tee -a "$LOG_FILE"
    
    local username
    read -rp "$(printf '%s' "${CYAN}Введите имя пользователя: ${NC}")" username
    
    if [[ -z "$username" ]]; then
        err "Имя пользователя не может быть пустым."
        return 1
    fi
    
    if ! id "$username" &>/dev/null; then
        err "Пользователь '$username' не существует."
        return 1
    fi
    
    if ! ask_yes_no "Заменить .bashrc для '$username' на кастомный?" "y"; then
        info "Пропуск установки кастомного .bashrc."
        return 0
    fi
    
    local user_home
    user_home=$(getent passwd "$username" | cut -d: -f6)
    local bashrc_path="$user_home/.bashrc"
    
    # Создание временного файла с содержимым
    local temp_bashrc
    temp_bashrc=$(mktemp "/tmp/custom_bashrc.XXXXXX")
    if [[ -z "$temp_bashrc" || ! -f "$temp_bashrc" ]]; then
        err "Не удалось создать временный файл."
        return 1
    fi
    chmod 600 "$temp_bashrc"
    
    # Запись содержимого кастомного .bashrc
    cat > "$temp_bashrc" <<'EOF'
# ===================================================================
#   Universal Portable .bashrc
#   For Debian/Ubuntu servers with multi-terminal support
# ===================================================================

# If not running interactively, don't do anything.
case $- in
    *i*) ;;
      *) return;;
esac

# --- History Control ---
# Don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth:erasedups
# Append to the history file, don't overwrite it.
shopt -s histappend
# Set history length with reasonable values for server use.
HISTSIZE=10000
HISTFILESIZE=20000
# Allow editing of commands recalled from history.
shopt -s histverify
# Add timestamp to history entries for audit trail (ISO 8601 format).
HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "
# Ignore common commands from history to reduce clutter.
HISTIGNORE="ls:ll:la:l:cd:pwd:exit:clear:c:history:h"

# --- General Shell Behavior & Options ---
# Check the window size after each command and update LINES and COLUMNS.
shopt -s checkwinsize
# Allow using '**' for recursive globbing (Bash 4.0+, suppress errors on older versions).
shopt -s globstar 2>/dev/null
# Allow changing to a directory by just typing its name (Bash 4.0+).
shopt -s autocd 2>/dev/null
# Autocorrect minor spelling errors in directory names (Bash 4.0+).
shopt -s cdspell 2>/dev/null
shopt -s dirspell 2>/dev/null
# Correct multi-line command editing.
shopt -s cmdhist 2>/dev/null
# Case-insensitive globbing (commented out to avoid unexpected behavior).
# shopt -s nocaseglob 2>/dev/null

# Set command-line editing mode. Emacs (default) or Vi.
set -o emacs
# For vi keybindings, uncomment the following line and comment the one above:
# set -o vi

# Make `less` more friendly for non-text input files.
[ -x /usr/bin/less ] && eval "$(SHELL=/bin/sh lesspipe)"

# --- Better Less Configuration ---
# Make less more friendly - R shows colors, F quits if one screen, X prevents screen clear.
export LESS='-R -F -X -i -M -w'
# Colored man pages using less (TERMCAP sequences).
export LESS_TERMCAP_mb=$'\e[1;31m'      # begin blink
export LESS_TERMCAP_md=$'\e[1;36m'      # begin bold
export LESS_TERMCAP_me=$'\e[0m'         # reset bold/blink
export LESS_TERMCAP_so=$'\e[01;44;33m'  # begin reverse video
export LESS_TERMCAP_se=$'\e[0m'         # reset reverse video
export LESS_TERMCAP_us=$'\e[1;32m'      # begin underline
export LESS_TERMCAP_ue=$'\e[0m'         # reset underline

# --- Terminal & SSH Compatibility Fixes ---
# Handle Kitty terminal over SSH - fallback to xterm-256color if terminfo unavailable.
if [[ "$TERM" == "xterm-kitty" ]]; then
    # Check if kitty terminfo is available, otherwise fallback.
    if ! infocmp xterm-kitty &>/dev/null; then
        export TERM=xterm-256color
    fi
    # Ensure the shell looks for user-specific terminfo files.
    [[ -d "$HOME/.terminfo" ]] && export TERMINFO="$HOME/.terminfo"
fi

# Fix for other modern terminals that might not be recognized on older servers.
case "$TERM" in
    alacritty|wezterm)
        if ! infocmp "$TERM" &>/dev/null; then
            export TERM=xterm-256color
        fi
        ;;
esac

# Optional: if kitty exists locally, provide a convenience alias for SSH.
# (No effect on hosts without kitty installed.)
if command -v kitty &>/dev/null; then
    alias kssh='kitty +kitten ssh'
fi

# --- Prompt Configuration ---
# Set variable identifying the chroot you work in (used in the prompt below).
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(</etc/debian_chroot)
fi

# Set a colored prompt only if the terminal has color capability.
case "$TERM" in
    xterm-color|*-256color|xterm-kitty|alacritty|wezterm) color_prompt=yes;;
esac

# Force color prompt support check using tput.
if [ -z "${color_prompt}" ] && [ -x /usr/bin/tput ] && tput setaf 1 &>/dev/null; then
    color_prompt=yes
fi

# --- Function to parse git branch only if in a git repo ---
parse_git_branch() {
    if git rev-parse --git-dir &>/dev/null; then
        git branch 2>/dev/null | sed -n '/^\*/s/* \(.*\)/\1/p'
    fi
    return 0
}

# --- Main prompt command function ---
__bash_prompt_command() {
    local rc=$?  # Capture last command exit status
    history -a
    history -n

    # --- Initialize prompt components ---
    local prompt_err="" prompt_git="" prompt_jobs="" prompt_venv=""
    local git_branch job_count

    # Error indicator
    (( rc != 0 )) && prompt_err="\[\e[31m\]✗\[\e[0m\]"

    # Git branch (dim yellow)
    git_branch=$(parse_git_branch)
    [[ -n "$git_branch" ]] && prompt_git="\[\e[2;33m\]($git_branch)\[\e[0m\]"

    # Background jobs (cyan)
    job_count=$(jobs -p | wc -l)
    (( job_count > 0 )) && prompt_jobs="\[\e[36m\]⚡${job_count}\[\e[0m\]"

    # Python virtualenv (dim green)
    [[ -n "$VIRTUAL_ENV" ]] && prompt_venv="\[\e[2;32m\][${VIRTUAL_ENV##*/}]\[\e[0m\]"

    # Ensure spacing between components
    [[ -n "$prompt_venv" ]] && prompt_venv=" $prompt_venv"
    [[ -n "$prompt_git" ]] && prompt_git=" $prompt_git"
    [[ -n "$prompt_jobs" ]] && prompt_jobs=" $prompt_jobs"
    [[ -n "$prompt_err" ]] && prompt_err=" $prompt_err"

    # --- Assemble PS1 ---
    if [ "$color_prompt" = yes ]; then
        PS1='${debian_chroot:+($debian_chroot)}\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]'"${prompt_venv}${prompt_git}${prompt_jobs}${prompt_err}"' \$ '
    else
        PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w'"${prompt_venv}${git_branch}${prompt_jobs}${prompt_err}"' \$ '
    fi

    # --- Set Terminal Window Title ---
    case "$TERM" in
      xterm*|rxvt*|xterm-kitty|alacritty|wezterm)
        PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
        ;;
    esac
}

# --- Activate dynamic prompt ---
PROMPT_COMMAND=__bash_prompt_command

# --- Editor Configuration ---
if command -v nano &>/dev/null; then
    export EDITOR=nano
    export VISUAL=nano
elif command -v vim &>/dev/null; then
    export EDITOR=vim
    export VISUAL=vim
else
    export EDITOR=vi
    export VISUAL=vi
fi

# --- Additional Environment Variables ---
# Set default pager.
export PAGER=less
# Prevent Ctrl+S from freezing the terminal.
stty -ixon 2>/dev/null

# --- Useful Functions ---
# Create a directory and change into it.
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Create a backup of a file with timestamp.
backup() {
    if [ -f "$1" ]; then
        local backup_file; backup_file="$1.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$1" "$backup_file"
        echo "Backup created: $backup_file"
    else
        echo "'$1' is not a valid file" >&2
        return 1
    fi
}

# Extract any archive file with a single command.
extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"      ;;
            *.tar.gz)    tar xzf "$1"      ;;
            *.tar.xz)    tar xJf "$1"      ;;
            *.bz2)       bunzip2 "$1"      ;;
            *.gz)        gunzip "$1"       ;;
            *.tar)       tar xf "$1"       ;;
            *.tbz2)      tar xjf "$1"      ;;
            *.tgz)       tar xzf "$1"      ;;
            *.zip)       unzip "$1"        ;;
            *.Z)         uncompress "$1"   ;;
            *.7z)        7z x "$1"         ;;
            *.deb)        ar x "$1"         ;;
            *.tar.zst)
                if command -v zstd &>/dev/null; then
                    zstd -dc "$1" | tar xf -
                else
                    tar --zstd -xf "$1"
                fi
                ;;
            *)
                echo "'$1' cannot be extracted via extract()" >&2
                return 1
                ;;
        esac
    else
        echo "'$1' is not a valid file" >&2
        return 1
    fi
}

# Quick directory navigation up multiple levels.
up() {
    local d=""
    local limit="${1:-1}"
    for ((i=1; i<=limit; i++)); do
        d="../$d"
    done
    cd "$d" || return
}

# Find files by name in current directory tree.
ff() {
    find . -type f -iname "*$1*" 2>/dev/null
}

# Find directories by name in current directory tree.
fd() {
    find . -type d -iname "*$1*" 2>/dev/null
}

# Search for text in files recursively.
ftext() {
    grep -rnw . -e "$1" 2>/dev/null
}

# Search history easily
hgrep() { history | grep -i --color=auto "$@"; }

# Create a tarball of a directory.
targz() {
    if [ -d "$1" ]; then
        tar czf "${1%%/}.tar.gz" "${1%%/}"
        echo "Created ${1%%/}.tar.gz"
    else
        echo "'$1' is not a valid directory" >&2
        return 1
    fi
}

# Show disk usage of current directory, sorted by size.
duh() {
    du -h --max-depth=1 "${1:-.}" | sort -hr
}

# Get the size of a file or directory.
get_size() {
    if [ -e "$1" ]; then
        du -sh "$1" | awk '{print $1}'
    else
        echo "0"
    fi
}
EOF
    
    # Резервное копирование существующего .bashrc
    if [[ -f "$bashrc_path" ]]; then
        cp "$bashrc_path" "${bashrc_path}.backup_$(date +%Y%m%d_%H%M%S)"
        info "Создана резервная копия: ${bashrc_path}.backup_*"
    fi
    
    # Установка нового .bashrc
    mv "$temp_bashrc" "$bashrc_path"
    chown "$username:$username" "$bashrc_path"
    chmod 644 "$bashrc_path"
    
    ok "Кастомный .bashrc установлен для '$username'."
    info "Файл: $bashrc_path"
    log "Custom .bashrc installed for $username."
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

_show_bashrc() {
    local username
    read -rp "$(printf '%s' "${CYAN}Введите имя пользователя: ${NC}")" username
    
    if [[ -z "$username" ]]; then
        err "Имя пользователя не может быть пустым."
        return 1
    fi
    
    local user_home
    user_home=$(getent passwd "$username" | cut -d: -f6)
    local bashrc_path="$user_home/.bashrc"
    
    if [[ ! -f "$bashrc_path" ]]; then
        warn "Файл .bashrc не найден для '$username'."
        return 1
    fi
    
    menu_header "Содержимое .bashrc для '$username'"
    echo ""
    head -50 "$bashrc_path"
    echo ""
    info "Полный файл: $bashrc_path"
    
    [[ $VERBOSE == true ]] && wait_for_enter
}

# === ГЛАВНОЕ МЕНЮ МОДУЛЯ =====================================

show_custom_bashrc_menu() {
    enable_graceful_ctrlc
    while true; do
        menu_header "🎨 Кастомизация .bashrc"
        printf_description "Установка кастомного .bashrc для пользователей."
        
        printf_menu_option "1" "Установить кастомный .bashrc"
        printf_menu_option "2" "Показать содержимое .bashrc"
        echo ""
        printf_menu_option "b" "Назад"
        
        local choice
        choice=$(safe_read "Ваш выбор: ") || break
        
        case "$choice" in
            1) _install_custom_bashrc ;;
            2) _show_bashrc ;;
            b|B) break ;;
            *) printf_error "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
