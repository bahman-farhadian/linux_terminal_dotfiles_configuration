#!/usr/bin/env bash
# vim/uninstall.sh — reverses vim/install.sh. Removes only the two files it
# deployed, ~/.vimrc and ~/.vim/colors/gruvbox.vim, after backing both up.
#
# Does not touch vim itself: install.sh installs the package only if it was
# missing, and this project's other dotfiles set EDITOR=vim regardless of
# whether this config is in use, so removing the package is out of scope here.
# Does not touch anything else under ~/.vim — that directory can hold a
# user's own plugins or history unrelated to this config, and only the one
# file this project ever wrote there is this script's business.
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_backup="$HOME/.vim-config-backup-$(date +%Y%m%d%H%M%S)-uninstall"
_did_something=false

_take() { # 1 path being removed, 2 label
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

_take "$HOME/.vimrc" "$_here/vimrc"
_take "$HOME/.vim/colors/gruvbox.vim" "$_here/colors/gruvbox.vim"

# The three plugins install.sh clones live under their own pack name,
# "minimal", chosen for exactly this: it is safe to remove that one
# subdirectory outright, because nothing but this project's install.sh ever
# writes there, while ~/.vim/pack itself is left alone — a different pack
# name a user or another tool created is not this script's business, and
# never touched.
#
# Not backed up like the two files above: this is an unmodified upstream git
# clone with nothing of the user's in it, re-created by running install.sh
# again if it is ever wanted back, network permitting.
if [ -d "$HOME/.vim/pack/minimal" ]; then
    echo "==> removing $HOME/.vim/pack/minimal (the three plugins install.sh fetched)"
    rm -rf "$HOME/.vim/pack/minimal"
    _did_something=true
fi

# Only clears directories this project creates, and only if nothing else is
# left in them — never rm -rf beyond the one directory above, since a plugin
# manager under a different pack name, or the user's own files, could live
# anywhere else under ~/.vim.
rmdir "$HOME/.vim/pack" 2>/dev/null || true
rmdir "$HOME/.vim/colors" 2>/dev/null || true
rmdir "$HOME/.vim" 2>/dev/null || true

if [ "$_did_something" = true ]; then
    echo "==> done. Previous files saved to $_backup"
else
    echo "==> nothing to remove — vim/install.sh does not appear to have run here"
fi
