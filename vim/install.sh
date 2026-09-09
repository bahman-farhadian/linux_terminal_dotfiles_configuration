#!/usr/bin/env bash
# vim/install.sh — deploys this vim config for every user on the machine, not
# just whoever runs the script. Optional, and apart from every host's own
# install.sh on purpose: nothing else in this repository runs this.
#
# System-wide, using Debian's own extension points rather than overwriting a
# package-owned file:
#   /etc/vim/vimrc.local             Debian's own /etc/vim/vimrc sources this
#                                     if it exists — every user gets it, with
#                                     no per-user setup of their own.
#   /usr/share/vim/vimfiles/colors/  vim's own site-wide colour directory,
#                                     already on every user's runtimepath.
#
# Idempotent. Backs up anything already at either path, timestamped, before
# overwriting. Needs root: it writes outside any one user's home.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo — this installs vim for every user on the machine, not just you." >&2
    exit 1
fi

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> installing vim, if it is not already"
if ! command -v vim &>/dev/null; then
    apt-get update -qq
    apt-get install -y vim
fi

echo "==> backing up any existing system-wide vim config"
_backup="/etc/vim-config-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$_backup"
[ -e /etc/vim/vimrc.local ] && cp -a /etc/vim/vimrc.local "$_backup/"
[ -e /usr/share/vim/vimfiles/colors/gruvbox.vim ] && cp -a /usr/share/vim/vimfiles/colors/gruvbox.vim "$_backup/"
echo "    saved to $_backup (only if anything existed)"

echo "==> writing /etc/vim/vimrc.local"
cp "$_here/vimrc" /etc/vim/vimrc.local

echo "==> writing /usr/share/vim/vimfiles/colors/gruvbox.vim"
mkdir -p /usr/share/vim/vimfiles/colors
cp "$_here/colors/gruvbox.vim" /usr/share/vim/vimfiles/colors/gruvbox.vim

echo "==> done. Every user gets this from their next vim start, no setup of their own needed."
echo "    <leader>e   toggle the file tree"
echo "    <leader>f   search the project"
echo "    <leader>q   close this file, not vim"
echo "    gt / gT     switch tabs"
