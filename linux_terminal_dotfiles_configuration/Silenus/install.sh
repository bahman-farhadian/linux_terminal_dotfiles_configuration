#!/usr/bin/env bash
# Silenus/install.sh — idempotent dotfiles installer for the workstation.
#
# bash, tmux and SSH, plus the desktop-only parts: the keyboard-lock service,
# the GNOME shortcuts and the GTK3 dark setting. Dionysus/install.sh is the
# headless counterpart and carries none of those.
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

_hdr "English keyboard on the lock screen"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"

# Written here rather than kept as separate files in the repository: they are
# generated artefacts, not dotfiles anyone edits. Rewritten on every run, so
# this stays idempotent.
cat > "$HOME/.local/bin/lock-keyboard-en.sh" << 'LOCKSH'
#!/bin/sh
# Keep the keyboard on English.
#
#   watch   on lock, leave English as the only layout, so nothing else can be
#           active while the password is typed. On unlock, put Persian back.
#   tick    every few minutes, drop to English alone and restore the pair.
#
# Only the layout list is written. Writing `current` does nothing: GNOME ignores
# it, and the key reads 0 even while Persian is the live layout. Removing the
# other layouts is the one method that demonstrably changes what is active,
# which is why the German case worked when nothing else did.

DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DBUS_SESSION_BUS_ADDRESS

SCHEMA=org.gnome.desktop.input-sources
EN_ONLY="[('xkb', 'us')]"
EN_PAIR="[('xkb', 'us'), ('xkb', 'ir')]"

PREVIOUS="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/lock-keyboard-en.previous"

sources_now() { gsettings get "$SCHEMA" sources 2>/dev/null; }
set_sources()  { [ "$(sources_now)" = "$1" ] || gsettings set "$SCHEMA" sources "$1"; }

# The lock forces English unconditionally, German included: the password prompt
# has to be typable no matter what was in use a second earlier. What was in use
# is written to $PREVIOUS first so the unlock can put it back, which is how a
# deliberate German layout survives a lock cycle rather than being discarded by
# it. $PREVIOUS lives under the runtime directory, so it is cleared at logout
# and a stale layout is never restored across a reboot.
on_lock() {
    now=$(sources_now)
    [ -n "$now" ] || return 0
    # Guard against a second lock with no unlock between: without it, the
    # English the first lock wrote would be recorded as the thing to restore.
    [ "$now" = "$EN_ONLY" ] || printf '%s\n' "$now" > "$PREVIOUS"
    set_sources "$EN_ONLY"
}

# Exactly what the lock replaced, or the English pair when nothing was recorded
# — a first unlock after the service starts, for one.
#
# Restoring the pair has to leave English selected, never Persian. Rewriting the
# list is the only thing that resets the selection, so the pair is put back by
# way of English-only rather than written straight: from any state that is not
# already English-only, a direct write could hand the session back with Persian
# live. German and every other list are restored as they were, untouched.
on_unlock() {
    if [ -r "$PREVIOUS" ]; then
        want=$(cat "$PREVIOUS")
        rm -f "$PREVIOUS"
    else
        want="$EN_PAIR"
    fi
    [ "$want" = "$EN_PAIR" ] && set_sources "$EN_ONLY"
    set_sources "$want"
}

# The timer manages the English pair and nothing else: German, or any other
# list, is left alone.
#
# With the pair in use there is no way to read which of the two is selected.
# GNOME ignores writes to `current`, and it reads 0 even while Persian is the
# live layout, so "do nothing when English, switch when Persian" cannot be
# branched on. Dropping Persian and restoring it forces the selection back to
# English either way: English stays English, Persian becomes English. The only
# difference from doing nothing in the English case is two writes that leave
# the list exactly as it was.
on_tick() {
    [ "$(sources_now)" = "$EN_PAIR" ] || return 0
    set_sources "$EN_ONLY"
    set_sources "$EN_PAIR"
}

case "${1:-watch}" in
    tick)
        on_tick
        ;;
    watch)
        case "$(gdbus call --session --dest org.gnome.ScreenSaver \
                --object-path /org/gnome/ScreenSaver \
                --method org.gnome.ScreenSaver.GetActive 2>/dev/null)" in
            *true*) on_lock ;;
        esac
        gdbus monitor --session --dest org.gnome.ScreenSaver 2>/dev/null |
        while IFS= read -r line; do
            case "$line" in
                *ActiveChanged*true*)  on_lock ;;
                *ActiveChanged*false*) on_unlock ;;
            esac
        done
        ;;
esac
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
ExecStart=%h/.local/bin/lock-keyboard-en.sh watch
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
LOCKUNIT

cat > "$HOME/.config/systemd/user/keyboard-en-tick.service" << 'TICKUNIT'
[Unit]
Description=Select English when the English layout pair is active

[Service]
Type=oneshot
ExecStart=%h/.local/bin/lock-keyboard-en.sh tick
TICKUNIT

cat > "$HOME/.config/systemd/user/keyboard-en-tick.timer" << 'TICKTIMER'
[Unit]
Description=Check the keyboard layout every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Unit=keyboard-en-tick.service

[Install]
WantedBy=timers.target
TICKTIMER
_ok "applied: lock-keyboard-en.service, keyboard-en-tick.timer"

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
    systemctl --user enable --now keyboard-en-tick.timer >/dev/null 2>&1 \
        && _ok "keyboard-en-tick.timer enabled" \
        || _warn "could not enable keyboard-en-tick.timer"
else
    _warn "no systemd user session here — enable them from a desktop login with:"
    printf '  systemctl --user enable --now lock-keyboard-en.service keyboard-en-tick.timer\n'
fi

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

_hdr "GTK3 dark theme"
# GNOME's colour-scheme=prefer-dark is a libadwaita setting. A GTK3 application
# that never opted into it keeps the light theme regardless — virt-manager is
# one. This tells GTK3 itself to prefer dark, which is narrower than exporting
# GTK_THEME: GTK4 and libadwaita applications keep following GNOME on their own,
# rather than being forced onto the legacy Adwaita-dark.
_gtk3="$HOME/.config/gtk-3.0/settings.ini"
if grep -qs '^gtk-application-prefer-dark-theme=1' "$_gtk3"; then
    _ok "GTK3 already set to prefer dark"
else
    mkdir -p "$(dirname "$_gtk3")"
    printf '[Settings]\ngtk-application-prefer-dark-theme=1\n' > "$_gtk3"
    _ok "$_gtk3 — GTK3 applications follow dark"
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
    # Volume keys move in 1% steps rather than GNOME's default. This has to come
    # after the reset-recursively above, which puts every media-keys setting —
    # this one included — back to its default.
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
    _ok "volume keys step by 1%"

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

printf '\n\033[38;2;184;187;38m✔ Done.\033[0m Log out and back in for the shell change to take effect.\n'
printf '  Reload now: exec bash\n'
