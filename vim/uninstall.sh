#!/usr/bin/env bash
# vim/uninstall.sh — reverses vim/install.sh. Removes only the two files it
# deployed, /etc/vim/vimrc.local and
# /usr/share/vim/vimfiles/colors/gruvbox.vim, after backing both up.
#
# Does not touch vim itself: install.sh installs the package only if it was
# missing, and this project's other dotfiles set EDITOR=vim regardless of
# whether this config is in use, so removing the package is out of scope here.
# Does not touch /etc/vim/vimrc, the package's own file — install.sh never
# wrote to it, only to vimrc.local alongside it. Needs root, same as
# install.sh: both paths are outside any one user's home.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo — install.sh wrote these files as root." >&2
    exit 1
fi

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_backup="/etc/vim-config-backup-$(date +%Y%m%d%H%M%S)-uninstall"
_did_something=false

_take() { # 1 path being removed, 2 repository original
    [ -e "$1" ] || return 0
    mkdir -p "$_backup"
    cp -a "$1" "$_backup/"
    if cmp -s "$2" "$1" 2>/dev/null; then
        echo "==> removing $1 (matched the repository)"
    else
        echo "==> removing $1 (differed from the repository — your changes are in the backup)"
    fi
    rm -f "$1"
    _did_something=true
}

_take "/etc/vim/vimrc.local" "$_here/vimrc"
_take "/usr/share/vim/vimfiles/colors/gruvbox.vim" "$_here/colors/gruvbox.vim"

# Only clears the one directory this project creates, and only if nothing
# else is left in it — never rm -rf, since another tool could put its own
# files one level up in /usr/share/vim/vimfiles.
rmdir /usr/share/vim/vimfiles/colors 2>/dev/null || true

if [ "$_did_something" = true ]; then
    echo "==> done. Previous files saved to $_backup"
else
    echo "==> nothing to remove — vim/install.sh does not appear to have run here"
fi
