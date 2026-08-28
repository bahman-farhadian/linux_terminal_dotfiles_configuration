#!/usr/bin/env bash
# linux/install.sh — idempotent dotfiles installer (Linux only)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(uname -s)" = "Linux" ] || { echo "Linux only." >&2; exit 1; }

_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }
_warn() { printf '\033[33m⚠ %s\033[0m\n' "$*"; }
_skip() { printf '\033[90m⊘ %s\033[0m\n' "$*"; }
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

printf '\nConfigure root user as well? [y/N]: '
read -r _ans
HAS_SUDO=false
if [[ "$_ans" =~ ^[Yy] ]]; then
    if sudo -v; then HAS_SUDO=true; _ok "sudo granted"
    else _warn "sudo failed — root skipped"
    fi
else
    _skip "root configuration"
fi

_hdr "bash"
cp_file "$REPO/bash/bash_profile" "$HOME/.bash_profile"
cp_file "$REPO/bash/bashrc"       "$HOME/.bashrc"
cp_file "$REPO/bash/bash_aliases" "$HOME/.bash_aliases"
if [ "$HAS_SUDO" = true ]; then
    sudo_cp "$REPO/bash/bash_profile" /root/.bash_profile
    sudo_cp "$REPO/bash/bashrc"       /root/.bashrc
    sudo_cp "$REPO/bash/bash_aliases" /root/.bash_aliases
fi

_hdr "tmux"
cp_file "$REPO/tmux/tmux.conf" "$HOME/.tmux.conf"
[ "$HAS_SUDO" = true ] && sudo_cp "$REPO/tmux/tmux.conf" /root/.tmux.conf || true

_hdr "ssh"
_upsert_ssh() {
    local config="$1"
    grep -qF 'AddKeysToAgent 5m' "$config" 2>/dev/null && return 0
    if grep -qF 'StrictHostKeyChecking no' "$config" 2>/dev/null; then
        if command -v python3 &>/dev/null; then
            local py
            py=$(mktemp)
            cat > "$py" << 'PYEOF'
import sys, re
path = sys.argv[1]
try: text = open(path).read()
except FileNotFoundError: text = ''
text = re.sub(r'\nHost \*\n(?:[ \t][^\n]*\n?)*', '', '\n' + text).strip()
open(path, 'w').write(text + '\n' if text else '')
PYEOF
            python3 "$py" "$config"
            rm -f "$py"
        else
            _warn "python3 not found — skipping SSH dedup (stale Host * block left in place)"
        fi
    fi
    printf '\n' >> "$config"
    cat "$REPO/ssh/config" >> "$config"
    return 1
}

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
if _upsert_ssh "$HOME/.ssh/config"; then
    _ok "SSH already present in ~/.ssh/config"
else
    chmod 600 "$HOME/.ssh/config"
    _ok "SSH applied to ~/.ssh/config"
fi

if [ "$HAS_SUDO" = true ]; then
    sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh
    _rtmp=$(mktemp)
    sudo cat /root/.ssh/config 2>/dev/null > "$_rtmp" || true
    chmod 600 "$_rtmp"
    if _upsert_ssh "$_rtmp"; then
        _ok "SSH already present in /root/.ssh/config"
    else
        sudo cp "$_rtmp" /root/.ssh/config
        sudo chmod 600 /root/.ssh/config
        _ok "SSH applied to /root/.ssh/config"
    fi
    rm -f "$_rtmp"
fi

_hdr "misc"
cp_file "$REPO/hushlogin" "$HOME/.hushlogin"

_hdr "English keyboard on the lock screen"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"

# Written here rather than kept as separate files in the repository: they are
# generated artefacts, not dotfiles anyone edits. Rewritten on every run, so
# this stays idempotent.
cat > "$HOME/.local/bin/lock-keyboard-en.sh" << 'LOCKSH'
#!/bin/sh
# Put the keyboard back to English the moment the screen locks.
#
# Locking while the German or Persian layout is active leaves the unlock prompt
# on that layout, which can make the password impossible to type. Whatever is
# active at the time, locking returns to English.
#
# This watches for the lock signal rather than polling: a poll only notices the
# lock on its next tick, which is far too late to be useful.

DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DBUS_SESSION_BUS_ADDRESS

EN_SOURCES="[('xkb', 'us'), ('xkb', 'ir')]"

set_english() {
    [ "$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null)" = "$EN_SOURCES" ] ||
        gsettings set org.gnome.desktop.input-sources sources "$EN_SOURCES"

    # Setting the list does not change which entry is selected. German drops out
    # of the list so the selection falls back on its own, but Persian is still
    # in it and stays active unless the index is moved to the first entry.
    [ "$(gsettings get org.gnome.desktop.input-sources current 2>/dev/null)" = "uint32 0" ] ||
        gsettings set org.gnome.desktop.input-sources current 0
}

# If the screen is already locked when this starts, act immediately.
case "$(gdbus call --session --dest org.gnome.ScreenSaver \
        --object-path /org/gnome/ScreenSaver \
        --method org.gnome.ScreenSaver.GetActive 2>/dev/null)" in
    *true*) set_english ;;
esac

# ActiveChanged carries true when the screen locks and false when it unlocks.
gdbus monitor --session --dest org.gnome.ScreenSaver 2>/dev/null |
while IFS= read -r line; do
    case "$line" in
        *ActiveChanged*true*) set_english ;;
    esac
done
LOCKSH
chmod +x "$HOME/.local/bin/lock-keyboard-en.sh"
_ok "applied: $HOME/.local/bin/lock-keyboard-en.sh"

cat > "$HOME/.config/systemd/user/lock-keyboard-en.service" << 'LOCKUNIT'
[Unit]
Description=Restore the English keyboard layout when the screen locks
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/lock-keyboard-en.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
LOCKUNIT
_ok "applied: $HOME/.config/systemd/user/lock-keyboard-en.service"

# Earlier versions installed this as a cron job. Polling cannot react to a lock
# in time, so drop any leftover entry.
if command -v crontab >/dev/null 2>&1; then
    _cron_now="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$_cron_now" | grep -qF 'lock-keyboard-en.sh'; then
        printf '%s\n' "$_cron_now" | grep -vF 'lock-keyboard-en.sh' | crontab -
        _ok "removed the old cron entry"
    fi
fi

if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable --now lock-keyboard-en.service >/dev/null 2>&1 \
        && _ok "lock-keyboard-en.service enabled" \
        || _warn "could not enable lock-keyboard-en.service"
else
    _warn "no systemd user session here — enable it from a desktop login with:"
    printf '  systemctl --user enable --now lock-keyboard-en.service\n'
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

_hdr "GNOME keyboard shortcuts"
if command -v gsettings >/dev/null 2>&1; then
    # Start from GNOME's defaults, so the result never depends on what happened
    # to be bound before, then lay ours on top. This also makes the whole block
    # idempotent without having to merge anything.
    gsettings reset-recursively org.gnome.settings-daemon.plugins.media-keys
    gsettings reset-recursively org.gnome.desktop.wm.keybindings
    _ok "reset to GNOME defaults"

    _kb_item=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
    _kb_base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
    _kb_add() {
        gsettings set "$_kb_item:$_kb_base/$1/" name    "$2"
        gsettings set "$_kb_item:$_kb_base/$1/" command "$3"
        gsettings set "$_kb_item:$_kb_base/$1/" binding "$4"
    }
    _kb_add dotfiles-terminal "Terminal" "gnome-terminal"        "<Control><Alt>t"
    _kb_add dotfiles-files    "Files"    "nautilus --new-window" "<Super>e"
    _kb_add dotfiles-settings "Settings" "gnome-control-center"  "<Super>i"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
        "['$_kb_base/dotfiles-terminal/', '$_kb_base/dotfiles-files/', '$_kb_base/dotfiles-settings/']"
    _ok "Ctrl+Alt+T terminal, Super+E files, Super+I settings"

    # Alt+Tab cycles windows rather than applications. The application switcher
    # holds Alt+Tab by default, so it has to be cleared or it wins.
    _wm=org.gnome.desktop.wm.keybindings
    gsettings set "$_wm" switch-applications          "[]"
    gsettings set "$_wm" switch-applications-backward "[]"
    gsettings set "$_wm" switch-windows               "['<Alt>Tab']"
    gsettings set "$_wm" switch-windows-backward      "['<Shift><Alt>Tab']"
    _ok "Alt+Tab and Shift+Alt+Tab switch windows"
else
    _skip "gsettings not found — GNOME shortcuts"
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

printf '\n\033[32m✔ Done.\033[0m Log out and back in for the shell change to take effect.\n'
printf '  Reload now: exec bash\n'
