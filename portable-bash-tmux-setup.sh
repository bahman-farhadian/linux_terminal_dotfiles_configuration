#!/usr/bin/env bash
# portable-bash-tmux-setup.sh — bash + tmux for any Debian 13 box, no dependency
# on the rest of this repository or on any of the three hosts it documents.
#
# Self-contained on purpose: every file below is embedded, so this script is
# the whole thing. Copy it anywhere — scp, paste into a root SSH session,
# curl a raw copy from wherever you host it — and run it as the account that
# should get the shell. Safe to re-run; it overwrites the same five files each
# time and backs up whatever was there first.
#
# What it does:
#   - apt installs the packages the config below actually uses
#   - backs up any existing ~/.bashrc, ~/.bash_aliases, ~/.bash_profile,
#     ~/.tmux.conf, ~/.hushlogin to ~/.dotfiles-backup-<timestamp>/
#   - writes those five files
#   - fetches tmux's bash completion, which Debian ships none of
#   - drops you into the new shell
#
# What it deliberately leaves alone: SSH client/server settings, MOTD/banner,
# system-wide history policy, anything under /etc. Those are choices for a
# specific fleet, not defaults for someone else's box.
set -euo pipefail

_run() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

echo "==> installing packages"
_run apt-get update -qq
_run apt-get install -y bash-completion tmux git vim curl jq tree openssl
_run apt-get install -y btop 2>/dev/null || _run apt-get install -y htop

echo "==> backing up any existing dotfiles"
_backup="$HOME/.dotfiles-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$_backup"
for f in .bashrc .bash_aliases .bash_profile .tmux.conf .hushlogin; do
    [ -e "$HOME/$f" ] && cp -a "$HOME/$f" "$_backup/"
done
echo "    saved to $_backup (only if anything existed)"

echo "==> writing ~/.bashrc"
cat > "$HOME/.bashrc" <<'BASHRC_EOF'
# ~/.bashrc (Linux)

# If not running interactively, bail
case $- in
    *i*) ;;
      *) return;;
esac

# Start tmux automatically. Set NO_AUTO_TMUX=1 to skip it. tmux is run rather
# than exec'd so that a broken tmux config drops you at a usable shell instead
# of closing the terminal.
#
# Every SSH login lands in a tmux session of its own, ssh1, ssh2 and so on, for
# whichever account is logging in. One session shared between two connections
# mirrors them: both clients see the same windows, and tmux sizes them for the
# smaller, which crops one and leaves an unpainted band in the other. The same
# argument separates remote sessions from local ones.
#
# A dropped connection is the exception worth having. Reconnecting attaches to a
# detached ssh session rather than opening yet another, so the work survives a
# lost link — which is the reason for running tmux over SSH in the first place.
#
# "Am I already inside tmux, on this machine?" $TMUX answers it outright, but
# sudo -i and su - scrub the environment, so a shell that really is in a pane
# can arrive with it unset. Walking up the process tree answers it anyway:
# those commands change the environment, not who the parent is.
#
# $TERM is no help and was actively wrong here. ssh carries the client's TERM
# across, so a login from a tmux window on another machine arrives reading
# tmux-256color with no tmux running on this one — and a test on $TERM then
# skips every SSH session it exists to serve.
#
# Over SSH it asks first, apt-style: Enter takes the default and starts tmux, n
# declines. tmux repaints the whole screen as it starts, which wipes the
# pre-authentication banner before anyone can read it, so taking the terminal
# outright would make that banner pointless on exactly the logins it is for.
# There is deliberately no timeout — a prompt that gave up on its own would
# clear the banner while it was still being read, which is the thing it exists
# to prevent. Local terminals are not asked: no banner is shown there.
_in_mux=""
if [ -n "$TMUX" ]; then
    _in_mux=1
else
    _p=$PPID
    while [ "${_p:-0}" -gt 1 ]; do
        read -r _pcomm < "/proc/$_p/comm" 2>/dev/null || break
        case "$_pcomm" in tmux*) _in_mux=1; break ;; esac
        _p=$(awk '/^PPid:/{print $2}' "/proc/$_p/status" 2>/dev/null)
    done
    unset _p _pcomm
fi
if [ -z "$TMUX" ] && [ -z "$_in_mux" ] && [ -z "$NO_AUTO_TMUX" ] && command -v tmux &>/dev/null; then
    if [ -n "$SSH_CONNECTION" ]; then
        _tmux_orphan=$(tmux list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null \
                       | awk '$1 ~ /^ssh[0-9]+$/ && $2 == 0 { print $1; exit }')
        if [ -n "$_tmux_orphan" ]; then
            _tmux_prompt="Reattach to tmux session $_tmux_orphan?"
        else
            _n=1
            while tmux has-session -t "=ssh$_n" 2>/dev/null; do _n=$((_n + 1)); done
            _tmux_prompt="Start tmux session ssh$_n?"
        fi
        # No terminal on stdin means no tmux either: it would fail to open one.
        if [ -t 0 ]; then
            printf '%s [Y/n] ' "$_tmux_prompt"
            read -r _reply || { _reply=n; printf '\n'; }
        else
            _reply=n
        fi
        case "$_reply" in
            [Nn]*) printf 'No tmux. Run `tmux` to start one, or log in again.\n' ;;
            *)
                if [ -n "$_tmux_orphan" ]; then
                    tmux attach-session -t "$_tmux_orphan" && exit
                else
                    # Recomputed rather than reused: the wait for an answer is
                    # long enough for another login to have taken the name.
                    _n=1
                    while tmux has-session -t "=ssh$_n" 2>/dev/null; do _n=$((_n + 1)); done
                    tmux new-session -s "ssh$_n" && exit
                fi
                ;;
        esac
        unset _tmux_orphan _tmux_prompt _reply _n
    else
        _tmux_detached=$(tmux list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null \
                         | awk '$1 !~ /^ssh[0-9]*$/ && $2 == 0 { print $1; exit }')
        if [ -n "$_tmux_detached" ]; then
            tmux attach-session -t "$_tmux_detached" && exit
        else
            tmux new-session && exit
        fi
        unset _tmux_detached
    fi
fi
unset _in_mux

# History. ignoreboth is ignoredups plus ignorespace, so a command typed with a
# leading space is never written to the file — that is the way to keep a
# password or a token out of it. erasedups drops older copies of a repeat.
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=100000
HISTFILESIZE=200000
shopt -s histappend
shopt -s checkwinsize

# PATH extras. Debian gives root the sbin directories but leaves them out for
# everyone else, so sysctl, swapon and efibootmgr read as "command not found"
# for a user who can run them under sudo anyway. Adding them here makes this
# user's PATH cover the same directories as root's. The case test stops a
# re-sourced .bashrc from stacking duplicate entries.
_path_prepend() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}
_path_prepend /sbin
_path_prepend /usr/sbin
_path_prepend /usr/local/sbin
_path_prepend /usr/local/bin
_path_prepend "$HOME/.local/bin"
unset -f _path_prepend
export PATH

# Editor
export EDITOR=vim
export VISUAL=vim

# Prevent venv from overwriting our custom prompt
export VIRTUAL_ENV_DISABLE_PROMPT=1

# Gruvbox dark — foreground colours only, no badges. Published values, used as
# they ship. The bright variants carry the prompt because the normal ones sit
# too dark on bg0: blue is 3.48:1 normal against 5.48:1 bright, purple the same,
# red 2.69:1 against 4.29:1.
#
# Bright red is the one value under 4.5:1, at 4.29:1. It is Gruvbox's own
# pairing of bright red on bg0 and it only ever draws the single-character marks
# — the dirty asterisk, the root hash, the failed prompt symbol — all in bold.
#
# The colour lives here, in the prompt. The tmux bar uses the bg ramp so the two
# do not compete.

_C_GREEN='\[\e[38;2;184;187;38m\]'  # #b8bb26 bright green 7.14:1
_C_RED='\[\e[38;2;251;73;52m\]'  # #fb4934 bright red 4.29:1
_C_YELLOW='\[\e[38;2;250;189;47m\]'  # #fabd2f bright yellow 8.69:1
_C_BLUE='\[\e[38;2;131;165;152m\]'  # #83a598 bright blue 5.48:1
_C_PEACH='\[\e[38;2;254;128;25m\]'  # #fe8019 orange 5.84:1
_C_MAUVE='\[\e[38;2;211;134;155m\]'  # #d3869b bright purple 5.37:1
_C_SKY='\[\e[38;2;142;192;124m\]'  # #8ec07c bright aqua 7.01:1
_C_FLAMINGO='\[\e[38;2;213;196;161m\]'  # #d5c4a1 fg2 8.59:1
_C_GREY='\[\e[38;2;146;131;116m\]'  # #928374 gray 4.02:1
_C_RST='\[\e[0m\]'

# Segments are spread around the wheel so no two neighbours share a hue: green
# user, yellow host, blue path, orange branch, magenta venv, cyan k8s. The user
# name carries the privilege colour and is the only thing that changes; the host
# keeps its own so it never moves. Everything after the path is conditional and
# absent when it has nothing to say.
#
# The _C_PEACH, _C_MAUVE, _C_SKY and _C_FLAMINGO names are left over from an
# earlier palette. They now hold Gruvbox orange, bright purple, bright aqua and
# fg2; the names are kept only so the prompt builder below did not have to be
# rewritten for a colour change.
_set_prompt() {
    local exit_code=$?
    local line sym sym_col user_col
    local branch marks counts ahead behind stash kctx

    if [ "$(id -u)" -eq 0 ]; then
        user_col="$_C_RED"; sym='#'
    else
        user_col="$_C_GREEN"; sym='$'
    fi

    line="${user_col}\u${_C_RST} ${_C_GREY}@${_C_RST} ${_C_YELLOW}\h${_C_RST} ${_C_BLUE}\w${_C_RST}"

    if git -C "$PWD" rev-parse --is-inside-work-tree &>/dev/null; then
        branch=$(git -C "$PWD" symbolic-ref --quiet --short HEAD 2>/dev/null \
                 || git -C "$PWD" rev-parse --short HEAD 2>/dev/null)
        marks=""
        git -C "$PWD" diff --quiet 2>/dev/null          || marks+="${_C_RED}*"
        git -C "$PWD" diff --staged --quiet 2>/dev/null || marks+="${_C_GREEN}+"
        counts=$(git -C "$PWD" rev-list --left-right --count "HEAD...@{upstream}" 2>/dev/null)
        if [ -n "$counts" ]; then
            ahead=${counts%%[!0-9]*}
            behind=${counts##*[!0-9]}
            [ "${ahead:-0}" -gt 0 ]  && marks+="${_C_SKY}⇡${ahead}"
            [ "${behind:-0}" -gt 0 ] && marks+="${_C_SKY}⇣${behind}"
        fi
        stash=$(git -C "$PWD" stash list 2>/dev/null | wc -l | tr -d '[:space:]')
        [ "${stash:-0}" -gt 0 ] && marks+="${_C_FLAMINGO}{${stash}}"
        line+=" ${_C_PEACH}${branch}${marks}${_C_RST}"
    fi

    [ -n "$VIRTUAL_ENV" ] && \
        line+=" ${_C_MAUVE}venv:${VIRTUAL_ENV_PROMPT:-$(basename "$VIRTUAL_ENV")}${_C_RST}"

    if command -v kubectl &>/dev/null; then
        kctx=$(kubectl config current-context 2>/dev/null)
        [ -n "$kctx" ] && line+=" ${_C_SKY}k8s:${kctx}${_C_RST}"
    fi

    if [ "$exit_code" -eq 0 ]; then sym_col="$_C_GREEN"; else sym_col="$_C_RED"; fi
    PS1="${line} ${sym_col}${sym}${_C_RST} "
}
# history -a appends this shell's new lines to the file at every prompt rather
# than only at exit, so a tmux pane that is killed still keeps its history.
PROMPT_COMMAND='history -a; _set_prompt'

# ls colours — Linux uses --color=auto and LS_COLORS (set by dircolors)
alias ls='ls --color=auto'
command -v dircolors &>/dev/null && eval "$(dircolors -b)"

# bash-completion — package name varies by distro:
#   Debian/Ubuntu: bash-completion   Fedora/RHEL: bash-completion
_bc=""
for _p in /usr/share/bash-completion/bash_completion \
           /etc/bash_completion; do
    [ -r "$_p" ] && { _bc="$_p"; break; }
done
[ -n "$_bc" ] && . "$_bc"
unset _bc _p

# Strip tab-separated descriptions from COMPREPLY (cobra/kubectl/docker output)
_strip_comp_descriptions() {
    local i
    for i in "${!COMPREPLY[@]}"; do
        COMPREPLY[$i]="${COMPREPLY[$i]%%$'\t'*}"
    done
}

# CLI tool completions
_bash_load_completions() {
    type _get_comp_words_by_ref &>/dev/null || return 0

    local tool output comp_fn wrapper_fn
    for tool in kubectl helm flux kind k3d docker; do
        if command -v "$tool" &>/dev/null; then
            output=$("$tool" completion bash 2>/dev/null)
            if [ -n "$output" ]; then
                eval "$output"
                comp_fn=$(complete -p "$tool" 2>/dev/null | sed -n 's/.*-F \([^ ]*\).*/\1/p')
                if [ -n "$comp_fn" ]; then
                    wrapper_fn="_nodesc_${tool}"
                    eval "
${wrapper_fn}() {
    { ${comp_fn} \"\$@\"; } > /dev/null
    _strip_comp_descriptions
}
"
                    complete -F "$wrapper_fn" "$tool"
                fi
            fi
        fi
    done
    command -v kubectl &>/dev/null && complete -o default -F __start_kubectl k
    type _nodesc_docker &>/dev/null && complete -F _nodesc_docker d || true

    local _bcd="/usr/share/bash-completion/completions"
    if [ -r "$_bcd/git" ]; then
        . "$_bcd/git"
        type __git_complete &>/dev/null && __git_complete g __git_main || true
    fi
    # Debian ships no tmux completion, so this script fetches one into the user
    # directory. Upstream names its function _tmux; Debian's convention would be
    # _comp_cmd_tmux. Load whichever exists and bind the t alias to it.
    for _tc in "$HOME/.local/share/bash-completion/completions/tmux" "$_bcd/tmux"; do
        [ -r "$_tc" ] || continue
        . "$_tc"
        type _tmux          &>/dev/null && complete -F _tmux          t 2>/dev/null
        type _comp_cmd_tmux &>/dev/null && complete -F _comp_cmd_tmux t 2>/dev/null
        break
    done
    unset _tc
    [ -r "$_bcd/python3" ] && . "$_bcd/python3" && complete -F _comp_cmd_python py 2>/dev/null || true
}
_bash_load_completions
unset -f _bash_load_completions

# Ollama completion
if command -v ollama &>/dev/null; then
    _ollama_bash() {
        local cur prev
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        local subcmds="serve create show run pull push list ps cp rm help"
        if [ "$COMP_CWORD" -eq 1 ]; then
            COMPREPLY=($(compgen -W "$subcmds" -- "$cur"))
            return
        fi
        case "$prev" in
            run|show|cp|rm|push)
                local models
                models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
                COMPREPLY=($(compgen -W "$models" -- "$cur"))
                ;;
        esac
    }
    complete -F _ollama_bash ollama
fi

# Aliases
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# tmux shortcut
alias t='tmux'

# readline — set AFTER all completion loading so nothing can override these
bind 'TAB: menu-complete'
bind '"\e[Z": menu-complete-backward'
bind 'set completion-ignore-case on'
bind 'set mark-symlinked-directories on'
bind 'set colored-stats on'
bind 'set colored-completion-prefix on'
BASHRC_EOF

echo "==> writing ~/.bash_aliases"
cat > "$HOME/.bash_aliases" <<'ALIASES_EOF'
# aliases — sourced by .bashrc
# Linux · DevOps + Data Engineering/Science

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

# Listing — ls --color=auto is set in bashrc; extend it here
alias ll='ls -AlhiF'
alias l='ls -A'
alias la='ls -A'

# General
alias c='clear'
command -v btop &>/dev/null && alias b='btop' || { command -v htop &>/dev/null && alias b='htop'; }
alias reload='exec $SHELL -l'
alias path='echo $PATH | tr ":" "\n"'
alias pubip='curl -s https://ipwho.is/ | jq .'
# Every private address this host holds, named by the interface carrying it.
# `hostname -I` prints the same addresses as one unlabelled line in kernel
# interface order, which answers nothing on a machine with more than one: with
# a VPN up and Docker or libvirt running there can easily be several, and which
# one comes first depends on the order the interfaces happened to appear. So
# print all of them and say which is which.
#
# The default route is marked by asking the kernel which source address it
# would route out with. That is a routing table lookup only — no packet is
# sent, and 1.1.1.1 is never contacted.
privip() {
    local routed out
    routed=$(ip -4 route get 1.1.1.1 2>/dev/null |
             awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i+1); exit }}')

    # Sorted by the rank in column one, which is then cut away: the routed
    # address first, the local bridges last — docker0 and virbr0 are this host
    # talking to its own containers and guests, not addresses anything else
    # reaches it on. sort -s keeps interface order within each rank.
    out=$(ip -4 -o addr show scope global 2>/dev/null |
          awk -v routed="$routed" '
              {
                  split($4, a, "/")
                  rank = (a[1] == routed) ? 0 : ($2 ~ /^(docker|virbr|br-|veth)/ ? 2 : 1)
                  mark = (a[1] == routed) ? "  ← default route" : ""
                  printf "%d\t%-11s %s%s\n", rank, $2, a[1], mark
              }' |
          sort -s -k1,1n | cut -f2-)

    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        echo "No global IPv4 address on any interface." >&2
        return 1
    fi
}
# Prints the key and puts it on the clipboard, so it can go straight into a
# GitHub form or an authorized_keys file. xclip is fed from the file rather than
# through a pipe: it forks to own the selection and returns at once, so the
# shell is never held waiting on it. On a headless host there is no X server to
# own a selection, so it prints and says nothing about copying.
#
# X11 selections belong to a live process, so the copy lasts as long as the
# shell that made it. Closing the terminal before pasting loses it, and the
# clipboard falls back to whatever GNOME held before. The same is true of cpy.
pubkey() {
    local key
    for key in ~/.ssh/id_ed25519.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_rsa.pub; do
        [ -f "$key" ] || continue
        cat "$key"
        if command -v xclip &>/dev/null && [ -n "$DISPLAY" ]; then
            xclip -selection clipboard < "$key"
            echo "[key: $(basename "$key") — copied to clipboard]" >&2
        else
            echo "[key: $(basename "$key")]" >&2
        fi
        return
    done
    echo "No public key found (~/.ssh/id_ed25519.pub, id_ecdsa.pub, id_rsa.pub)" >&2
    return 1
}
alias pubkeys='ls ~/.ssh/*.pub 2>/dev/null | xargs -I{} sh -c "echo \"=== {} ===\"; cat {}"'
alias password='openssl rand -base64 48'

# System update — apt and flatpak together.
# Functions rather than aliases: an alias cannot decide whether sudo is needed.
_asroot() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# What would change. Refreshes the sources, then lists it without touching
# anything.
update() {
    _asroot apt update
    apt list --upgradable
    command -v flatpak >/dev/null 2>&1 && flatpak remote-ls --updates
}

# Apply it, then clean up after both.
upgrade() {
    _asroot apt full-upgrade
    _asroot apt autoremove --purge
    if command -v flatpak >/dev/null 2>&1; then
        _asroot flatpak update
        _asroot flatpak uninstall --unused
    fi
}

# Editors
alias nano='vim'
alias v='vim'

# Pipe filter — prints output and copies to clipboard if xclip is available;
# on headless servers without X11/xclip it just prints (tee with no sink).
cpy() {
    if command -v xclip &>/dev/null && [ -n "$DISPLAY" ]; then
        tee >(xclip -selection clipboard)
    else
        tee
    fi
}

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -m'
alias gca='git commit --amend --no-edit'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbD='git branch -D'
alias gl='git log --oneline --graph --decorate --all'
alias gll='git log --stat'
alias gd='git diff'
alias gds='git diff --staged'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull'
alias gpr='git pull --rebase'
alias gst='git stash'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gf='git fetch --all --prune'
alias grb='git rebase'
alias grbi='git rebase -i'
alias gcp='git cherry-pick'
alias gtag='git tag'
alias gclean='git clean -fd'
alias gwip='git add -A && git commit -m "wip: checkpoint"'

# Python / venv
alias py='python3'
alias pip='pip3'
alias piv='python3 -m venv .venv'
alias va='source .venv/bin/activate'
alias vd='deactivate'
alias pipi='pip3 install'
alias pipu='pip3 install --upgrade'
alias pipf='pip3 freeze'
alias pipff='pip3 freeze > requirements.txt'
alias pipr='pip3 install -r requirements.txt'
alias pipuu='pip3 list --outdated | awk "NR>2 {print \$1}" | xargs pip3 install --upgrade'

# Jupyter
alias jn='jupyter notebook'
alias jl='jupyter lab'
alias jnb='jupyter nbconvert'

# Docker
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drm='docker rm'
alias drmi='docker rmi'
alias drmf='docker rm -f'
alias dex='docker exec -it'
alias dlogs='docker logs -f'
alias dstop='docker stop'
alias dstart='docker start'
alias dprune='docker system prune -af --volumes'
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dcr='docker compose restart'
alias dcb='docker compose build'

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deployments'
alias kdes='kubectl describe'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdn='kubectl describe node'
alias klogs='kubectl logs -f'
alias kex='kubectl exec -it'
alias kap='kubectl apply -f'
alias kdel='kubectl delete -f'
alias kctx='kubectl config get-contexts'
alias kuse='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'
alias krun='kubectl run --rm -it --image=busybox debug -- sh'

# Network
# ss -p only shows the process for sockets you own, so this needs privilege to
# name the service behind a system port.
ports() { _asroot ss -tunlp; }

# Filesystem / safety
alias cp='cp -iv'
alias mv='mv -iv'
alias mkdir='mkdir -pv'
alias df='df -h'
alias du='du -sh'
alias dud='du -sh -- *'

# Directory stack
alias pd='pushd'
alias pp='popd'
alias ds='dirs -v'

# Find
alias fd='find . -type d -name'
alias ff='find . -type f -name'

# Size and tree
alias dsize='du -sh -- */ | sort -h'
alias count='ls -1 | wc -l'
alias t2='tree -L 2'
alias t3='tree -L 3'
alias th='tree -L 2 -a -I ".git|.venv|__pycache__|node_modules|*.pyc"'
ALIASES_EOF

echo "==> writing ~/.bash_profile"
cat > "$HOME/.bash_profile" <<'PROFILE_EOF'
# ~/.bash_profile — Linux login shell entry point

if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
PROFILE_EOF

echo "==> writing ~/.tmux.conf"
cat > "$HOME/.tmux.conf" <<'TMUXCONF_EOF'
# ~/.tmux.conf

# Size the session to the smallest attached client. A larger client fills the
# leftover area with dots rather than the session resizing every time another
# client is used, which is what the default 'latest' does.
set -g window-size smallest

# Windows and panes index from 1
set -g base-index 1
setw -g pane-base-index 1

# tmux has no session-base-index, so unnamed sessions are 0, 1, 2. Rename any
# all-numeric session to the first free tmuxNN. Sessions created with an
# explicit name are left alone. The dollar signs must be escaped or tmux
# expands them itself while reading this file, leaving the script empty.
set-hook -g session-created 'run-shell "n=#{session_name}; case \$n in *[!0-9]*) exit 0;; esac; for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20; do if ! tmux has-session -t =tmux\$i 2>/dev/null; then tmux rename-session -t =\$n tmux\$i; break; fi; done"'

# Large scrollback (1 MiB lines)
set -g history-limit 1048576

# No mouse
set -g mouse off

# Status bar — Gruvbox dark. The bar itself takes the terminal's own
# background, so it follows any transparency set in the terminal profile and
# leaves no seam against the strip below the last row.
#
# Gruvbox's background ramp only — no accents in the chrome. The bar stays out
# of the way and lets the prompt carry the colour. Blocks are told apart by
# lightness, stepping up that ramp:
#   inactive window  bg1 #3c3836 with fg1  8.45:1
#   session name     bg2 #504945 with bright yellow  5.20:1
#   active window    bg3 #665c54 with fg0  5.74:1  lightest, leads
#
# Both tabs stay light so the window list reads easily; the active one is told
# apart by its lighter block. The session name is the exception and carries
# bright yellow, since it names the session and is worth picking out at a glance.
#
# bright red is the only other accent, used where it means something: the zoomed
# marker and the synchronised-panes borders are warnings, not decoration.
set -g status-style          "bg=default,fg=#a89984"
set -g status-position       bottom
set -g status-interval       5
set -g status-left-length    30

# Session name badge
set -g status-left  "#[bg=#504945,fg=#fabd2f,bold] #S #[default] "

# Nothing on the right. Setting it empty is required: left unset, tmux shows
# its own default date and time there.
set -g status-right ""

# Inactive window tab
setw -g window-status-style          "bg=#3c3836,fg=#ebdbb2"
setw -g window-status-format         " #I:#W "

# Active window tab — shows Z in Red when pane is zoomed
setw -g window-status-current-style  "bg=#665c54,fg=#fbf1c7,bold"
setw -g window-status-current-format " #I:#W#{?window_zoomed_flag,#[fg=#fb4934] Z #[fg=#fbf1c7],} "

# No gap between window tabs
setw -g window-status-separator ""

# Pane borders
set -g pane-border-style        "fg=#504945"
set -g pane-active-border-style "fg=#7c6f64"

# Command/message bar — same Mantle background as the status bar
set -g message-style         "bg=#3c3836,fg=#ebdbb2,bold"
set -g message-command-style "bg=#3c3836,fg=#d5c4a1,bold"

# Copy mode highlight
setw -g mode-style "bg=#504945,fg=#ebdbb2"

# Window navigation — Shift+Left/Right, no prefix
bind-key -n S-Left  previous-window
bind-key -n S-Right next-window

# Pane navigation — Ctrl+b prefix (vim style + arrows)
bind-key h select-pane -L
bind-key j select-pane -D
bind-key k select-pane -U
bind-key l select-pane -R
bind-key Left  select-pane -L
bind-key Right select-pane -R
bind-key Up    select-pane -U
bind-key Down  select-pane -D

# Pane creation — Ctrl+b " creates a stacked pane, then equalizes all pane
# heights in the window. This keeps repeated horizontal splits aligned.
bind-key '"' split-window -v \; select-layout even-vertical

# Pane removal — keep the remaining stacked panes at equal heights after a
# confirmed Ctrl+b x action.
bind-key x confirm-before -p "kill-pane #P? (y/n)" kill-pane

# Re-equalize the stack whenever a pane goes away. The two close paths fire
# different hooks: Ctrl+b x runs kill-pane and fires after-kill-pane, while
# Ctrl+d exits the shell and fires pane-exited. Both are needed.
#
# Two details that make this work. The target must be #{window_id}, because
# #{hook_window} expands to nothing in after-kill-pane. And the layout must be
# deferred with run-shell -b, because pane-exited fires while the pane still
# exists and would otherwise divide the space including the pane being closed.
set-hook -g after-kill-pane 'run-shell -b "tmux select-layout -t #{window_id} even-vertical >/dev/null 2>&1 || true"'
set-hook -g pane-exited     'run-shell -b "tmux select-layout -t #{window_id} even-vertical >/dev/null 2>&1 || true"'

# Synchronize all panes — borders turn Red while sync is on
bind-key @ if -F '#{pane_synchronized}' \
    'setw synchronize-panes off; set-window-option pane-border-style "fg=#504945"; set-window-option pane-active-border-style "fg=#7c6f64"' \
    'setw synchronize-panes on; set-window-option pane-border-style "fg=#fb4934"; set-window-option pane-active-border-style "fg=#fb4934"'

# Scrollback — PgUp/PgDown enters copy-mode
bind-key -n PPage copy-mode -u
bind-key    PPage copy-mode -u
bind-key -T copy-mode PPage  send -X page-up
bind-key -T copy-mode NPage  send -X page-down
bind-key -T copy-mode Escape send -X cancel
bind-key -T copy-mode q      send -X cancel

# Nested tmux (SSH → remote tmux) — F12 toggles passthrough mode
# ON  → local tmux handles all keys normally
# OFF → local tmux ignores all keys; everything goes to the remote tmux
#       status bar dims to grey so you always know which mode you're in
bind-key -n F12 \
    set prefix None \;\
    set key-table off \;\
    set status-style "bg=default,fg=#928374" \;\
    set status-left "#[fg=#928374] #S [passthrough]  " \;\
    refresh-client -S

bind-key -T off F12 \
    set -u prefix \;\
    set -u key-table \;\
    set -u status-style \;\
    set -u status-left \;\
    refresh-client -S
TMUXCONF_EOF

echo "==> writing ~/.hushlogin (silences the login MOTD)"
: > "$HOME/.hushlogin"

echo "==> fetching tmux bash completion (Debian packages none)"
mkdir -p "$HOME/.local/share/bash-completion/completions"
_tc_tmp=$(mktemp)
if curl -fsSL https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux -o "$_tc_tmp" && [ -s "$_tc_tmp" ]; then
    mv "$_tc_tmp" "$HOME/.local/share/bash-completion/completions/tmux"
    echo "    installed"
else
    rm -f "$_tc_tmp"
    echo "    fetch failed — skipped, harmless (just no tab-completion for tmux)"
fi

echo "==> done. Reloading shell."
exec bash -l
