#!/usr/bin/env bash
# vim/install.sh — deploys vim/vimrc and vim/colors/gruvbox.vim. Optional, and
# apart from every host's own install.sh on purpose: nothing in the rest of
# this repository runs this, and no host's install.sh calls it either. Run it
# by hand only if you want vim configured.
#
# Idempotent. Backs up any ~/.vimrc or ~/.vim/colors/gruvbox.vim already
# present, timestamped, before overwriting.
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_run() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

echo "==> installing vim, if it is not already"
if ! command -v vim &>/dev/null; then
    _run apt-get update -qq
    _run apt-get install -y vim
fi

echo "==> backing up any existing vim config"
_backup="$HOME/.vim-config-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$_backup"
[ -e "$HOME/.vimrc" ] && cp -a "$HOME/.vimrc" "$_backup/"
[ -e "$HOME/.vim/colors/gruvbox.vim" ] && cp -a "$HOME/.vim/colors/gruvbox.vim" "$_backup/"
echo "    saved to $_backup (only if anything existed)"

echo "==> writing ~/.vimrc"
cp "$_here/vimrc" "$HOME/.vimrc"

echo "==> writing ~/.vim/colors/gruvbox.vim"
mkdir -p "$HOME/.vim/colors"
cp "$_here/colors/gruvbox.vim" "$HOME/.vim/colors/gruvbox.vim"

echo "==> done."
echo "    Ctrl-b   toggle the file tree"
echo "    <leader>f<pattern>  project-wide search (uses ripgrep if installed)"
echo "    Shift-Left/Right    switch tabs"
