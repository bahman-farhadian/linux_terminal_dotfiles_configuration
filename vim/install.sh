#!/usr/bin/env bash
# vim/install.sh — deploys vim/vimrc, vim/colors/gruvbox.vim, and a small set
# of vim-8-native packages (no plugin manager). Optional, and apart from every
# host's own install.sh on purpose: nothing in the rest of this repository
# runs this, and no host's install.sh calls it either. Run it by hand only if
# you want vim configured.
#
# Idempotent. Backs up any ~/.vimrc or ~/.vim/colors/gruvbox.vim already
# present, timestamped, before overwriting; re-running pulls each plugin's
# latest commit rather than re-cloning.
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

# Three plugins, curated from amix/vimrc's own "awesome" list rather than its
# full bundle: a fuzzy file finder, git integration, and comment toggling —
# the gaps netrw and vim's own builtins do not cover, and nothing more.
# Vim 8's native package loading needs no plugin manager: anything under
# ~/.vim/pack/*/start/*/ loads on its own at startup. "minimal" is this
# project's own pack name, chosen so uninstall.sh can remove exactly this
# directory and nothing a user put under ~/.vim/pack themselves.
#
# This is the one network dependency in vim/, and it fails soft: no network,
# no clone, vimrc still loads clean without the plugin, same as the ripgrep
# check elsewhere in this config. Re-running pulls each plugin's latest
# commit rather than re-cloning, so this is safe to run again later.
echo "==> installing plugins (fuzzy find, git, comment toggling)"
_pack="$HOME/.vim/pack/minimal/start"
mkdir -p "$_pack"
for repo in ctrlpvim/ctrlp.vim tpope/vim-fugitive tpope/vim-commentary; do
    _name="${repo#*/}"
    if [ -d "$_pack/$_name/.git" ]; then
        git -C "$_pack/$_name" pull --ff-only -q 2>/dev/null \
            && echo "    updated: $_name" \
            || echo "    could not update $_name — keeping the copy already there"
    elif git clone --depth 1 -q "https://github.com/$repo.git" "$_pack/$_name" 2>/dev/null; then
        echo "    installed: $_name"
    else
        echo "    could not fetch $_name — no network reaches github.com from here"
    fi
done

echo "==> done."
echo "    Ctrl-v e   toggle the file tree"
echo "    Ctrl-v f   project-wide search (uses ripgrep if installed)"
echo "    Ctrl-p     fuzzy file finder"
echo "    gcc        comment / uncomment the current line"
echo "    :Git       git status, staged from the same window"
echo "    gt / gT    next / previous tab"
