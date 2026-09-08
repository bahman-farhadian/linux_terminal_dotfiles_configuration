#!/usr/bin/env bash
# vim/check.sh — verifies vim/install.sh actually took, and that vim starts
# clean under it. Reads only, never writes. Run as your own user, not root:
# it is your ~/.vimrc being checked.

if [ "$(id -u)" -eq 0 ]; then
  echo "STOP: run as your normal user, not root. It is your ~/.vimrc and ~/.vim being checked."; exit 1
fi

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0; failed=""
_note(){ failed="$failed  - $1\n"; }
ck(){ if [ "$2" = "$3" ]; then printf '  PASS  %-28s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-28s got[%s] want[%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); _note "$1: got [$2], wanted [$3]"; fi; }
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

if command -v rg &>/dev/null; then
  _rg_out=$(vim -Nu "$HOME/.vimrc" -es --not-a-term \
    -c "redir! > /tmp/vimcheck2.$$" -c "echo 'grepprg=' . &grepprg" -c "redir END" -c "qa!" /dev/null 2>&1
    cat "/tmp/vimcheck2.$$" 2>/dev/null; rm -f "/tmp/vimcheck2.$$")
  ck "ripgrep wired in" "$(printf '%s' "$_rg_out" | grep -c '^grepprg=rg ')" "1"
else
  printf '  N/A   %-28s ripgrep not installed — grepprg stays at vim'"'"'s own default\n' "ripgrep wired in"
fi

printf '\n========================================\n'
printf '  PASS %s   FAIL %s\n' "$pass" "$fail"
printf '========================================\n'
if [ "$fail" -gt 0 ]; then
  printf '\nWhat failed:\n'; printf "$failed"
fi
[ "$fail" -eq 0 ]
