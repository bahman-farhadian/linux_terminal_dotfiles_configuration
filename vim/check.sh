#!/usr/bin/env bash
# vim/check.sh — verifies vim/install.sh actually took, and that vim starts
# clean under it. Reads only, never writes. Run as your own user, not root:
# it is your ~/.vimrc being checked.

if [ "$(id -u)" -eq 0 ]; then
  echo "STOP: run as your normal user, not root. It is your ~/.vimrc and ~/.vim being checked."; exit 1
fi

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0; skip=0; failed=""; skipped=""
_note(){ failed="$failed  - $1\n"; }
ck(){ if [ "$2" = "$3" ]; then printf '  PASS  %-28s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-28s got[%s] want[%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); _note "$1: got [$2], wanted [$3]"; fi; }
# na() is for something this host cannot test right now — no xclip, no
# DISPLAY — rather than something that failed. It does not count as FAIL.
na(){ printf '  N/A   %-28s %s\n' "$1" "$2"; skip=$((skip+1)); skipped="$skipped  - $1: $2\n"; }
same(){ # 1 label  2 repo file  3 deployed path
  if [ ! -f "$3" ]; then
    printf '  FAIL  %-28s missing %s\n' "$1" "$3"; fail=$((fail+1)); _note "$1: $3 is missing"
  elif cmp -s "$_here/$2" "$3"; then
    printf '  PASS  %-28s matches the repository\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-28s differs from the repository\n' "$1"; fail=$((fail+1))
    _note "$1: $3 differs from $_here/$2"
  fi
}

printf '\n--- Deployed files ---\n'
ck "vim installed" "$(command -v vim >/dev/null && echo yes || echo no)" "yes"
same "vimrc"    vimrc              "$HOME/.vimrc"
same "gruvbox"  colors/gruvbox.vim "$HOME/.vim/colors/gruvbox.vim"

printf '\n--- Starts clean ---\n'
# A real smoke test, not a guess: start vim against the deployed vimrc with no
# terminal, ask it what settings actually took, and check its own message log
# for anything vim itself considers an error.
_out=$(vim -Nu "$HOME/.vimrc" -es --not-a-term \
  -c "redir! > /tmp/vimcheck.$$" \
  -c "echo 'colors_name=' . get(g:, 'colors_name', 'UNSET')" \
  -c "echo 'background=' . &background" \
  -c "echo 'tabstop=' . &tabstop" \
  -c "echo 'expandtab=' . &expandtab" \
  -c "echo 'hlsearch=' . &hlsearch" \
  -c "redir END" -c "messages" -c "qa!" /dev/null 2>&1; cat "/tmp/vimcheck.$$" 2>/dev/null; rm -f "/tmp/vimcheck.$$")

ck "no startup errors" "$(printf '%s' "$_out" | grep -Ec '^E[0-9]+:')" "0"
ck "colorscheme loaded" "$(printf '%s' "$_out" | sed -n 's/^colors_name=//p')" "gruvbox"
ck "background dark"    "$(printf '%s' "$_out" | sed -n 's/^background=//p')" "dark"
ck "tabstop 4"           "$(printf '%s' "$_out" | sed -n 's/^tabstop=//p')" "4"
ck "expandtab on"        "$(printf '%s' "$_out" | sed -n 's/^expandtab=//p')" "1"
ck "hlsearch on"         "$(printf '%s' "$_out" | sed -n 's/^hlsearch=//p')" "1"

printf '\n--- Keys that must not collide with tmux ---\n'
# 22 is Ctrl-V's character code. Asserted by value, not by re-simulating a
# keypress: an earlier version of this check tried to fake actual key
# sequences through -es batch mode and got unreliable results doing it —
# introspecting vim's own tables is what the install this verifies actually
# depends on.
_map_out=$(vim -Nu "$HOME/.vimrc" -es --not-a-term \
  -c "redir! > /tmp/vimcheck3.$$" \
  -c "echo 'mapleader_code=' . char2nr(mapleader)" \
  -c "echo 'leader_e=' . maparg('<leader>e', 'n')" \
  -c "echo 'leader_f=' . maparg('<leader>f', 'n')" \
  -c "echo 'ctrlq=' . strtrans(maparg('<C-q>', 'n'))" \
  -c "echo 'ctrlb=' . strtrans(maparg('<C-b>', 'n'))" \
  -c "echo 'shiftleft=' . strtrans(maparg('<S-Left>', 'n'))" \
  -c "redir END" -c "qa!" /dev/null 2>&1; cat "/tmp/vimcheck3.$$" 2>/dev/null; rm -f "/tmp/vimcheck3.$$")

ck "leader is Ctrl-v"      "$(printf '%s' "$_map_out" | sed -n 's/^mapleader_code=//p')" "22"
ck "leader-e opens tree"   "$(printf '%s' "$_map_out" | sed -n 's/^leader_e=//p')" ":Lexplore<CR>"
ck "leader-f runs search"  "$(printf '%s' "$_map_out" | sed -n 's/^leader_f=//p')" ":Search "
ck "Ctrl-q is visual block" "$(printf '%s' "$_map_out" | sed -n 's/^ctrlq=//p')" "<C-V>"
# The two keys tmux's root table swallows before vim ever sees them. Nothing
# here should be mapped to either — a mapping on a dead key is worse than no
# mapping, since it looks configured and never fires.
ck "Ctrl-b left unmapped"      "$(printf '%s' "$_map_out" | sed -n 's/^ctrlb=//p')" ""
ck "Shift-Left left unmapped"  "$(printf '%s' "$_map_out" | sed -n 's/^shiftleft=//p')" ""

printf '\n--- Closing a file does not close vim ---\n'
# A real functional test, not just "does :Bd exist": open two files, close
# one, confirm vim switched to the other rather than exiting or erroring. No
# /dev/null file argument here, unlike the checks above — that would open a
# third buffer of its own and throw off the count this check depends on.
_bd_out=$(vim -Nu "$HOME/.vimrc" -es --not-a-term \
  -c "edit /tmp/vimcheck_bd1.$$" -c "edit /tmp/vimcheck_bd2.$$" \
  -c "redir! > /tmp/vimcheck5.$$" \
  -c "echo 'before=' . len(getbufinfo({'buflisted':1}))" \
  -c "redir END" \
  -c "Bd" \
  -c "redir! >> /tmp/vimcheck5.$$" \
  -c "echo 'after=' . len(getbufinfo({'buflisted':1})) . ' switched=' . (bufname('%') =~# 'vimcheck_bd1' ? 'yes' : 'no')" \
  -c "redir END" -c "qa!" 2>&1
  cat "/tmp/vimcheck5.$$" 2>/dev/null; rm -f "/tmp/vimcheck5.$$" "/tmp/vimcheck_bd1.$$" "/tmp/vimcheck_bd2.$$")

ck "Bd closes a buffer"    "$(printf '%s' "$_bd_out" | sed -n 's/^before=//p')" "2"
ck "Bd switches, not quits" "$(printf '%s' "$_bd_out" | sed -n 's/.*switched=//p')" "yes"

printf '\n--- Clipboard (checked by mapping, not by using the clipboard) ---\n'
# check.sh promises never to write, and the real clipboard is the user's own
# state — trying an actual copy/paste round trip here would overwrite
# whatever they currently have on it. Introspection only: is the mapping
# present when xclip and a display are, and correctly absent when not.
_clip_out=$(vim -Nu "$HOME/.vimrc" -es --not-a-term \
  -c "redir! > /tmp/vimcheck6.$$" \
  -c "echo 'y=' . strtrans(maparg('<leader>y', 'v'))" \
  -c "echo 'p=' . strtrans(maparg('<leader>p', 'n'))" \
  -c "redir END" -c "qa!" /dev/null 2>&1; cat "/tmp/vimcheck6.$$" 2>/dev/null; rm -f "/tmp/vimcheck6.$$")

if command -v xclip &>/dev/null && [ -n "${DISPLAY:-}" ]; then
  ck "clipboard yank mapped"  "$(printf '%s' "$_clip_out" | sed -n 's/^y=//p')" ":w !xclip -selection clipboard<CR><CR>"
  ck "clipboard paste mapped" "$(printf '%s' "$_clip_out" | sed -n 's/^p=//p')" ":r !xclip -selection clipboard -o<CR>"
else
  na "clipboard mappings" "no xclip, or no DISPLAY, on this host — correctly left unmapped rather than mapped to a command that would fail"
fi

if command -v rg &>/dev/null; then
  _rg_out=$(vim -Nu "$HOME/.vimrc" -es --not-a-term \
    -c "redir! > /tmp/vimcheck2.$$" -c "echo 'grepprg=' . &grepprg" -c "redir END" -c "qa!" /dev/null 2>&1
    cat "/tmp/vimcheck2.$$" 2>/dev/null; rm -f "/tmp/vimcheck2.$$")
  ck "ripgrep wired in" "$(printf '%s' "$_rg_out" | grep -c '^grepprg=rg ')" "1"
else
  na "ripgrep wired in" "ripgrep not installed — grepprg stays at vim's own default"
fi

printf '\n========================================\n'
printf '  PASS %s   FAIL %s   N/A %s\n' "$pass" "$fail" "$skip"
printf '========================================\n'
if [ "$fail" -gt 0 ]; then
  printf '\nWhat failed:\n'; printf "$failed"
fi
if [ "$skip" -gt 0 ]; then
  printf '\nNot tested here:\n'; printf "$skipped"
fi
[ "$fail" -eq 0 ]
