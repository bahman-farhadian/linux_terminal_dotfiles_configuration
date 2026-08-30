#!/usr/bin/env bash
# Dionysus/install.sh — idempotent dotfiles installer for the headless host.
#
# The same bash, tmux and SSH configuration as Silenus, without anything that
# needs a desktop: no keyboard-lock service, no GNOME shortcuts, no GTK3 theme.
# Silenus/install.sh is the workstation counterpart.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(uname -s)" = "Linux" ] || { echo "Linux only." >&2; exit 1; }

_ok()   { printf '\033[38;2;184;187;38m✔ %s\033[0m\n' "$*"; }
_warn() { printf '\033[38;2;250;189;47m⚠ %s\033[0m\n' "$*"; }
_skip() { printf '\033[38;2;146;131;116m⊘ %s\033[0m\n' "$*"; }
_hdr()  { printf '\n%s\n' "$*"; }

cp_file() { mkdir -p "$(dirname "$2")"; cp "$1" "$2"; _ok "applied: $2"; }
sudo_cp() { sudo mkdir -p "$(dirname "$2")"; sudo cp "$1" "$2"; _ok "applied (root): $2"; }

# Detect package manager (Debian/Ubuntu or Red Hat/Fedora only)
_pkg_cmd() {
    local pkgs="$1"
    if command -v apt-get &>/dev/null; then
        echo "sudo apt-get install -y $pkgs"
    elif command -v dnf &>/dev/null; then
        echo "sudo dnf install -y $pkgs"
    elif command -v yum &>/dev/null; then
        echo "sudo yum install -y $pkgs"
    else
        _warn "unsupported distro — install manually: $pkgs"
        echo ""
    fi
}

_check_prereqs() {
    _hdr "prerequisites"
    local missing=() cmd

    for cmd in bash tmux vim git curl jq tree python3 openssl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    local bc_ok=false
    { [ -r /usr/share/bash-completion/bash_completion ] || \
      [ -r /etc/bash_completion ]; } && bc_ok=true

    if [ ${#missing[@]} -eq 0 ] && $bc_ok; then
        _ok "all required packages present"
        return
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        _warn "missing: ${missing[*]}"
        local cmd; cmd="$(_pkg_cmd "${missing[*]}")"
        [ -n "$cmd" ] && printf '  Run: %s\n' "$cmd"
    fi
    if ! $bc_ok; then
        _warn "bash-completion not found (Tab completions will not load)"
        local cmd; cmd="$(_pkg_cmd "bash-completion")"
        [ -n "$cmd" ] && printf '  Run: %s\n' "$cmd"
    fi
}

_check_prereqs

# Root is configured again whenever it was configured before. A prompt that
# defaults to N meant one Enter left /root holding whatever an earlier run had
# put there, with no way to notice and no later run to correct it: reapplying
# converged for this account and quietly drifted for the other one. The stamp
# records the answer, so the question is asked once and both accounts stay in
# step from then on. --root and --no-root answer it for an unattended run.
ROOT_STAMP=/etc/dotfiles-root-configured
ROOT_WANTED=
for _arg in "$@"; do
    case "$_arg" in
        --root)    ROOT_WANTED=yes ;;
        --no-root) ROOT_WANTED=no ;;
    esac
done

if [ -n "$ROOT_WANTED" ]; then
    :
elif [ -e "$ROOT_STAMP" ]; then
    ROOT_WANTED=yes
    _ok "root was configured before — keeping it in step (--no-root to stop)"
else
    printf '\nConfigure root user as well? [y/N]: '
    read -r _ans
    [[ "$_ans" =~ ^[Yy] ]] && ROOT_WANTED=yes || ROOT_WANTED=no
fi

HAS_SUDO=false
if [ "$ROOT_WANTED" = yes ]; then
    if sudo -v; then HAS_SUDO=true; _ok "sudo granted"
    else _warn "sudo failed — root skipped"
    fi
else
    _skip "root configuration"
    [ -e "$ROOT_STAMP" ] && _warn "/root still holds an older copy — rerun with --root to refresh it"
fi

_hdr "bash"
cp_file "$REPO/bash/bash_profile" "$HOME/.bash_profile"
cp_file "$REPO/bash/bashrc"       "$HOME/.bashrc"
cp_file "$REPO/bash/bash_aliases" "$HOME/.bash_aliases"
if [ "$HAS_SUDO" = true ]; then
    sudo_cp "$REPO/bash/bash_profile" /root/.bash_profile
    sudo_cp "$REPO/bash/bashrc"       /root/.bashrc
    sudo_cp "$REPO/bash/bash_aliases" /root/.bash_aliases
    # Remembered so the question is asked once and never silently answered N on
    # a later run. World readable on purpose: the check has to work before sudo.
    sudo tee "$ROOT_STAMP" >/dev/null <<'STAMP'
# /root is configured from this dotfiles repository. install.sh refreshes it on
# every run because this file exists. Delete it to stop that.
STAMP
    sudo chmod 0644 "$ROOT_STAMP"
fi

_hdr "tmux"
cp_file "$REPO/tmux/tmux.conf" "$HOME/.tmux.conf"
[ "$HAS_SUDO" = true ] && sudo_cp "$REPO/tmux/tmux.conf" /root/.tmux.conf || true

_hdr "ssh"
# The repository's settings live between markers and are rewritten on every run,
# so editing ssh/config here actually reaches the machine. The old version added
# them once and then returned early forever on finding `AddKeysToAgent 5m`, which
# meant no later edit was ever applied.
#
# Everything outside the markers is left byte for byte as it was: these files
# carry personal Host entries the repository knows nothing about.
#
# The block goes at the END of the file. ssh takes the first value it finds for
# each keyword, so a `Host *` section placed above the specific hosts silently
# wins over them — `Port 22` in the defaults defeats the `Port 443` written for
# a host that has to reach the outside on 443.
_ssh_py=$(mktemp)
cat > "$_ssh_py" << 'PYEOF'
import re, sys

path, block_path = sys.argv[1], sys.argv[2]
BEGIN = "# >>> dotfiles managed block >>>"
END = "# <<< dotfiles managed block <<<"

try:
    text = open(path).read()
except FileNotFoundError:
    text = ""

# This run replaces the previous run's block.
text = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"[ \t]*\n?", "", text, flags=re.S)


# Installs from before the markers existed wrote the same settings unmarked, and
# usually at the top where they override every host below. Recognise that block
# by the options only this repository sets, so a `Host *` section someone wrote
# themselves is not touched.
def drop_if_ours(match):
    body = match.group(0)
    mine = "UserKnownHostsFile /dev/null" in body or "AddKeysToAgent" in body
    return "" if mine else body


text = re.sub(r"(?m)^Host \*[ \t]*\n(?:[ \t]+[^\n]*\n?)*", drop_if_ours, text)
text = re.sub(r"\n{3,}", "\n\n", text).strip("\n")

managed = "\n".join([
    BEGIN,
    "# Written by install.sh and replaced on every run. Edit ssh/config in the",
    "# repository, not here. Put your own Host entries ABOVE this block: ssh uses",
    "# the first value it finds for each keyword, so these defaults have to come",
    "# last or they override every host above them.",
    open(block_path).read().strip("\n"),
    END,
])

open(path, "w").write((text + "\n\n" if text else "") + managed + "\n")
PYEOF

_apply_ssh() {
    local config="$1" label="$2"
    if ! command -v python3 >/dev/null 2>&1; then
        _warn "python3 not found — $label left alone"
        return 1
    fi
    # Rewritten via a temporary file, so a failure partway through cannot leave a
    # half-written config behind for a file holding every host you log in to.
    local tmp; tmp=$(mktemp); chmod 600 "$tmp"
    cat "$config" > "$tmp" 2>/dev/null || true
    if python3 "$_ssh_py" "$tmp" "$REPO/ssh/config"; then
        cat "$tmp" > "$config"
        rm -f "$tmp"
        _ok "$label — managed block refreshed, your own Host entries untouched"
    else
        rm -f "$tmp"
        _warn "$label unchanged — could not rewrite it"
        return 1
    fi
}

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
_apply_ssh "$HOME/.ssh/config" "~/.ssh/config" || true
chmod 600 "$HOME/.ssh/config"

if [ "$HAS_SUDO" = true ]; then
    sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh
    _rtmp=$(mktemp)
    chmod 600 "$_rtmp"
    sudo cat /root/.ssh/config 2>/dev/null > "$_rtmp" || true
    if _apply_ssh "$_rtmp" "/root/.ssh/config"; then
        sudo cp "$_rtmp" /root/.ssh/config
        sudo chmod 600 /root/.ssh/config
    fi
    rm -f "$_rtmp"
fi
rm -f "$_ssh_py"

_hdr "misc"
cp_file "$REPO/hushlogin" "$HOME/.hushlogin"

_hdr "shell history for all users"
# The dotfiles above set this for this account. The drop-in covers every other
# account, so the two rules hold system wide rather than only for one user.
_hist_drop=/etc/profile.d/99-history.sh
if [ "$HAS_SUDO" != true ]; then
    _skip "history drop-in needs sudo"
else
    sudo tee "$_hist_drop" >/dev/null <<'HISTCONF'
# Command history rules for every account.
#
# ignorespace (the second half of ignoreboth) keeps a command typed with a
# leading space out of the history file. Use it for anything carrying a
# password or a token.
#
# history -a on every prompt appends new lines as they are entered, so a shell
# that is killed rather than exited — a closed tmux pane, for one — has already
# written its history.
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=100000
HISTFILESIZE=200000
shopt -s histappend
case "$PROMPT_COMMAND" in
    *'history -a'*) ;;
    *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
esac
HISTCONF
    sudo chmod 0644 "$_hist_drop"
    _ok "$_hist_drop — leading space ignored, history written each prompt"
fi

_hdr "SSH server"
# Root by key only; ordinary users unchanged; port 22 left at the default.
# A broken sshd_config locks you out of the machine, so this validates before
# reloading and puts the file back if sshd rejects it.
_sshd_drop=/etc/ssh/sshd_config.d/99-local.conf
if [ "$HAS_SUDO" != true ]; then
    _skip "SSH server needs sudo"
elif [ ! -d /etc/ssh/sshd_config.d ]; then
    _skip "no /etc/ssh/sshd_config.d — openssh-server not installed?"
elif ! sudo grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    _warn "/etc/ssh/sshd_config has no Include for sshd_config.d — a drop-in would be ignored"
else
    _sshd_had=false
    [ -e "$_sshd_drop" ] && _sshd_had=true
    sudo cp -a "$_sshd_drop" "$_sshd_drop.bak" 2>/dev/null || true
    sudo tee "$_sshd_drop" >/dev/null <<'SSHDCONF'
# Root may connect with a key, never with a password.
PermitRootLogin prohibit-password
SSHDCONF
    if sudo sshd -t 2>/dev/null; then
        sudo rm -f "$_sshd_drop.bak"
        sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
        _ok "PermitRootLogin prohibit-password, port 22 unchanged"
    else
        if [ "$_sshd_had" = true ]; then
            sudo mv "$_sshd_drop.bak" "$_sshd_drop"
        else
            sudo rm -f "$_sshd_drop" "$_sshd_drop.bak"
        fi
        _warn "sshd rejected the configuration — reverted, nothing changed"
    fi
fi

_hdr "tmux bash completion"
# Debian packages no tmux completion, so it comes from upstream. Fetched to a
# temporary file first, so a failed download cannot truncate a working copy.
mkdir -p "$HOME/.local/share/bash-completion/completions"
_tc_dst="$HOME/.local/share/bash-completion/completions/tmux"
_tc_url=https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux
if command -v curl >/dev/null 2>&1; then
    _tc_tmp=$(mktemp)
    if curl -fsSL "$_tc_url" -o "$_tc_tmp" && [ -s "$_tc_tmp" ]; then
        mv "$_tc_tmp" "$_tc_dst"
        _ok "applied: $_tc_dst"
    else
        rm -f "$_tc_tmp"
        if [ -r "$_tc_dst" ]; then
            _skip "download failed — keeping the copy already installed"
        else
            _warn "could not fetch the tmux completion"
        fi
    fi
else
    _warn "curl not found — tmux completion skipped"
fi

_hdr "default shell → bash"
BASH_BIN="$(command -v bash)"
CURRENT_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"

if [ -z "$BASH_BIN" ]; then
    _warn "bash not found in PATH — install it first"
elif [ "$CURRENT_SHELL" = "$BASH_BIN" ]; then
    _skip "$USER already uses $BASH_BIN"
else
    # chsh requires the shell to be listed in /etc/shells
    if ! grep -qxF "$BASH_BIN" /etc/shells 2>/dev/null; then
        if [ "$HAS_SUDO" = true ]; then
            echo "$BASH_BIN" | sudo tee -a /etc/shells > /dev/null
            _ok "registered $BASH_BIN in /etc/shells"
        else
            _warn "$BASH_BIN not in /etc/shells — set it manually with sudo"
        fi
    fi
    # usermod via sudo is non-interactive. Plain chsh prompts for a password,
    # so it is only used when sudo was declined, and its prompt is left visible.
    if [ "$HAS_SUDO" = true ]; then
        sudo usermod -s "$BASH_BIN" "$USER" && _ok "$USER: shell → $BASH_BIN"
    else
        _warn "changing the login shell needs your password"
        chsh -s "$BASH_BIN" && _ok "$USER: shell → $BASH_BIN" || \
            _warn "could not set shell — run manually: chsh -s $BASH_BIN"
    fi
fi

if [ "$HAS_SUDO" = true ] && [ -n "$BASH_BIN" ]; then
    if [ "$(getent passwd root | cut -d: -f7)" = "$BASH_BIN" ]; then
        _skip "root already uses $BASH_BIN"
    else
        sudo usermod -s "$BASH_BIN" root && _ok "root: shell → $BASH_BIN"
    fi
fi

printf '\n\033[38;2;184;187;38m✔ Done.\033[0m Log out and back in for the shell change to take effect.\n'
printf '  Reload now: exec bash\n'
