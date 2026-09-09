#!/usr/bin/env bash
# vim/check.sh — verifies vim/install.sh actually took, and that vim starts
# clean under it. Reads only, never writes.
#
# The system-wide checks below run vim with HOME pointed at an empty,
# throwaway directory and no -u override — the same as any real user with no
# ~/.vimrc of their own gets: vim's normal startup, through the real, unedited
# /etc/vim/vimrc, into vimrc.local, and (since that throwaway HOME has
# nothing of its own) into $VIMRUNTIME/defaults.vim too. That last step
# matters: defaults.vim turns the mouse back on for anyone without a personal
# vimrc, unless vimrc.local says not to — confirmed directly against the real
# defaults.vim on this host, not assumed. Passing -u /etc/vim/vimrc instead
# would not have caught that: naming a vimrc with -u makes vim skip
# defaults.vim regardless, whether or not the guard actually works.

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
same_dir(){ # 1 label  2 repo dir  3 deployed path
  if [ ! -d "$3" ]; then
    printf '  FAIL  %-28s missing %s\n' "$1" "$3"; fail=$((fail+1)); _note "$1: $3 is missing"
  elif diff -rq "$_here/$2" "$3" >/dev/null 2>&1; then
    printf '  PASS  %-28s matches the repository\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-28s differs from the repository\n' "$1"; fail=$((fail+1))
    _note "$1: $3 differs from $_here/$2"
  fi
}

_home="$(mktemp -d)"
trap 'rm -rf "$_home"' EXIT
# Plain headless mode, not -es (Ex mode, silent): -es skips /etc/vim/vimrc
# entirely, confirmed directly (&compatible came back 1, meaning debian.vim
# never even ran, under -es; 0, correctly, in a real terminal and under
# plain --not-a-term) — an earlier version of this script used -es and every
# check below was silently testing nothing, not a real deployment failure.
_vim() { env -i HOME="$_home" TERM="$TERM" vim --not-a-term "$@"; }

printf '\n--- Deployed files ---\n'
ck "vim installed" "$(command -v vim >/dev/null && echo yes || echo no)" "yes"
same "vimrc"    vimrc              "/etc/vim/vimrc.local"
same "gruvbox"  colors/gruvbox.vim "/usr/share/vim/vimfiles/colors/gruvbox.vim"
same_dir "nerdtree"  pack/dist/start/nerdtree  "/usr/share/vim/vimfiles/pack/dist/start/nerdtree"
same_dir "lightline" pack/dist/start/lightline "/usr/share/vim/vimfiles/pack/dist/start/lightline"

printf '\n--- Your own account does not have a personal vimrc shadowing this ---\n'
# Every check below runs with a throwaway, empty $HOME, on purpose — it is
# the fair way to test "every user gets this," including one with no config
# of their own. But it means those checks cannot see this: vim always
# sources a personal vimrc, if this account happens to have one, AFTER the
# system one just installed — so it silently wins, overriding anything
# installed here. That is not hypothetical: a leftover ~/.vimrc from testing
# this project's own earlier, per-user design, dated before a real bugfix
# even existed, did exactly this — every check here passed while the actual
# bug it was fixing was still fully reproducible in a real terminal, because
# nothing here was checking the one account actually being used interactively.
_shadow=""
for f in "$HOME/.vimrc" "$HOME/.vim/vimrc"; do
  [ -e "$f" ] && _shadow="$_shadow $f"
done
[ -n "${VIMINIT:-}" ] && _shadow="$_shadow \$VIMINIT"
if [ -n "$_shadow" ]; then
  printf '  FAIL  %-28s found:%s\n' "no shadowing vimrc" "$_shadow"
  fail=$((fail+1))
  _note "no shadowing vimrc: found$_shadow — sourced after /etc/vim/vimrc.local, so it wins; move it aside if this account should actually get the system-wide config"
else
  printf '  PASS  %-28s none found\n' "no shadowing vimrc"
  pass=$((pass+1))
fi

printf '\n--- Starts clean, for a user with no vimrc of their own ---\n'
# A real smoke test, not a guess: start vim exactly as a fresh account would,
# ask it what settings actually took, and check its own message log for
# anything vim itself considers an error.
# Merged into one -c with | rather than one -c per echo: vim refuses more
# than about ten -c/--cmd arguments total ("Too many -c command... arguments")
# and this file already hit that limit once, silently — every value in this
# block came back empty, not just the two just-added ones, because vim
# never even started once the count was over.
# Plain (non-Ex) mode echoes each :echo to its own message area as well as
# into the redir file, unlike -es — captured separately so that leak doesn't
# duplicate every setting below. messages runs after redir END, so it was
# never in the file to begin with; it needs the raw output, discarded here.
_msgs=$(_vim \
  -c "redir! > /tmp/vimcheck.$$" \
  -c "echo 'colors_name=' . get(g:, 'colors_name', 'UNSET') | echo 'background=' . &background | echo 'tabstop=' . &tabstop | echo 'expandtab=' . &expandtab | echo 'hlsearch=' . &hlsearch | echo 'normal_bg=' . (has_key(hlget('Normal')[0], 'guibg') ? 'set' : 'inherits') | echo 'signcol_bg=' . (has_key(hlget('SignColumn')[0], 'guibg') ? 'set' : 'inherits') | echo 'shortmess_I=' . (&shortmess =~# 'I' ? 'yes' : 'no') | echo 'vimenter_autocmd=' . exists('#VimEnter') | echo 'mouse=[' . &mouse . ']' | echo 'skip_defaults=' . get(g:, 'skip_defaults_vim', 'UNSET') | echo 'laststatus=' . &laststatus | echo 'showmode=' . &showmode | echo 'lightline_scheme=' . get(get(g:, 'lightline', {}), 'colorscheme', 'UNSET') | echo 'lightline_bg=' . synIDattr(hlID('LightlineLeft_normal_0'), 'bg')" \
  -c "redir END" -c "messages" -c "qa!" /dev/null 2>&1)
_out=$(cat "/tmp/vimcheck.$$" 2>/dev/null); rm -f "/tmp/vimcheck.$$"

ck "no startup errors" "$(printf '%s' "$_msgs" | grep -Ec '^E[0-9]+:')" "0"
ck "colorscheme loaded" "$(printf '%s' "$_out" | sed -n 's/^colors_name=//p')" "gruvbox"
ck "background dark"    "$(printf '%s' "$_out" | sed -n 's/^background=//p')" "dark"
ck "tabstop 4"           "$(printf '%s' "$_out" | sed -n 's/^tabstop=//p')" "4"
# Normal and SignColumn must inherit the terminal's own background, not force
# a fixed hex — the same bg=default approach this project's tmux.conf already
# uses. hi clear restores vim's own compiled-in defaults for some groups
# rather than blanking them (SignColumn among them), which silently defeated
# an earlier version of this check's own intent; asserted directly against
# hlget() rather than assumed from the colorscheme source reading correctly.
ck "vim background inherits terminal" "$(printf '%s' "$_out" | sed -n 's/^normal_bg=//p')" "inherits"
ck "sign column inherits terminal"    "$(printf '%s' "$_out" | sed -n 's/^signcol_bg=//p')" "inherits"
ck "expandtab on"        "$(printf '%s' "$_out" | sed -n 's/^expandtab=//p')" "1"
ck "hlsearch on"         "$(printf '%s' "$_out" | sed -n 's/^hlsearch=//p')" "1"
ck "no splash screen"    "$(printf '%s' "$_out" | sed -n 's/^shortmess_I=//p')" "yes"
# defaults.vim turns the mouse back on for a user with no vimrc of their own,
# unless g:skip_defaults_vim is set first — confirmed directly against the
# real defaults.vim on this host. Both asserted here, on the real chain, not
# just on vim/vimrc read in isolation.
ck "defaults.vim guarded" "$(printf '%s' "$_out" | sed -n 's/^skip_defaults=//p')" "1"
ck "mouse stays off, even without a personal vimrc" "$(printf '%s' "$_out" | sed -n 's/^mouse=\[\(.*\)\]/\1/p')" ""
# laststatus 2, not vim's own default (1, hidden with a single window) -
# lightline needs it shown always. showmode 0: lightline shows the mode
# itself, so vim's own "-- INSERT --" message would just repeat it.
ck "statusline always shown"    "$(printf '%s' "$_out" | sed -n 's/^laststatus=//p')" "2"
ck "vim's own mode message off" "$(printf '%s' "$_out" | sed -n 's/^showmode=//p')" "0"
ck "lightline colorscheme set"  "$(printf '%s' "$_out" | sed -n 's/^lightline_scheme=//p')" "gruvbox"
# #b8bb26 is this project's own green, hand-written into lightline's own
# colorscheme format at pack/dist/start/lightline/.../colorscheme/gruvbox.vim
# - checked against the live highlight group lightline actually defined,
# not just that a colorscheme name string was set.
ck "lightline uses this project's palette" "$(printf '%s' "$_out" | sed -n 's/^lightline_bg=//p')" "#b8bb26"
# Confirms the autocmd is registered, not that startinsert actually landed in
# Insert mode — :help :startinsert states plainly that it only takes effect
# once the calling script has finished, so nothing running inside this
# script's own -c chain can observe that transition happening. Checked the
# opposite way first, got exactly the documented behaviour, and trusted the
# documentation over trying to force a synchronous answer out of it.
ck "auto-insert on empty start registered" "$(printf '%s' "$_out" | sed -n 's/^vimenter_autocmd=//p')" "1"

printf '\n--- Keys that must not collide with tmux ---\n'
# 22 is Ctrl-V's character code. Asserted by value, not by re-simulating a
# keypress: an earlier version of this check tried to fake actual key
# sequences through -es batch mode and got unreliable results doing it —
# introspecting vim's own tables is what the install this verifies actually
# depends on.
_map_out=$(_vim \
  -c "redir! > /tmp/vimcheck3.$$" \
  -c "echo 'mapleader_code=' . char2nr(mapleader)" \
  -c "echo 'leader_e=' . (maparg('<leader>e', 'n') =~# 'NERDTreeToggle' ? 'wired' : 'MISSING')" \
  -c "echo 'leader_f=' . maparg('<leader>f', 'n')" \
  -c "echo 'ctrlq=' . strtrans(maparg('<C-q>', 'n'))" \
  -c "echo 'ctrlb=' . strtrans(maparg('<C-b>', 'n'))" \
  -c "echo 'shiftleft=' . strtrans(maparg('<S-Left>', 'n'))" \
  -c "redir END" -c "qa!" /dev/null >/dev/null 2>&1
cat "/tmp/vimcheck3.$$" 2>/dev/null; rm -f "/tmp/vimcheck3.$$")

ck "leader is Ctrl-v"      "$(printf '%s' "$_map_out" | sed -n 's/^mapleader_code=//p')" "22"
ck "leader-e opens tree"   "$(printf '%s' "$_map_out" | sed -n 's/^leader_e=//p')" "wired"
ck "leader-f runs search"  "$(printf '%s' "$_map_out" | sed -n 's/^leader_f=//p')" ":Search "
ck "Ctrl-q is visual block" "$(printf '%s' "$_map_out" | sed -n 's/^ctrlq=//p')" "<C-V>"
# The two keys tmux's root table swallows before vim ever sees them. Nothing
# here should be mapped to either — a mapping on a dead key is worse than no
# mapping, since it looks configured and never fires.
ck "Ctrl-b left unmapped"      "$(printf '%s' "$_map_out" | sed -n 's/^ctrlb=//p')" ""
ck "Shift-Left left unmapped"  "$(printf '%s' "$_map_out" | sed -n 's/^shiftleft=//p')" ""

printf '\n--- The file tree only ever has one tree, however it is opened ---\n'
# Reported directly, more than once: opening a directory and pressing
# leader-e produced two separate trees, not one - first with netrw's own
# :Lexplore, then again with NERDTreeHijackNetrw (its own default-on
# feature, which creates a different kind of tree from the one leader-e
# creates, and the two didn't recognise each other). The fix that held:
# both are disabled above, so leader-e is the *only* path that ever
# creates one - checked here from every angle, not just the one path each
# previous version of this check happened to cover. vim . itself is
# deliberately plain (no special-cased auto-open): a directory argument
# is just an ordinary, uneventful buffer, same as this project's own
# README says. Headless equivalents (-es batch mode, :normal, feedkeys())
# do not reliably reproduce directory-open or window-splitting behaviour,
# so this uses a real pty via tmux, same as the original bug was
# diagnosed with.
if command -v tmux &>/dev/null; then
  _winnr(){ tmux capture-pane -t "$1" -p | grep -oE '^[0-9]+' | tail -1; } # 1 session
  _dtmp="$(mktemp -d)"; touch "$_dtmp/a.txt"

  tmux kill-session -t vc_dir 2>/dev/null
  tmux new-session -d -s vc_dir -x 200 -y 50 "env HOME=$_home vim $_dtmp" 2>/dev/null
  sleep 1
  tmux send-keys -t vc_dir Escape
  tmux send-keys -t vc_dir ':echo winnr("$")' Enter; sleep 0.3
  ck "vim . opens no tree on its own" "$(_winnr vc_dir)" "1"

  tmux send-keys -t vc_dir C-v; sleep 0.2
  tmux send-keys -t vc_dir e; sleep 0.3
  tmux send-keys -t vc_dir Escape
  tmux send-keys -t vc_dir ':echo winnr("$")' Enter; sleep 0.3
  ck "leader-e opens exactly one" "$(_winnr vc_dir)" "2"

  tmux send-keys -t vc_dir C-v; sleep 0.2
  tmux send-keys -t vc_dir e; sleep 0.3
  tmux send-keys -t vc_dir Escape
  tmux send-keys -t vc_dir ':echo winnr("$")' Enter; sleep 0.3
  ck "leader-e again closes it" "$(_winnr vc_dir)" "1"

  tmux send-keys -t vc_dir ':qa!' Enter; sleep 0.3
  tmux kill-session -t vc_dir 2>/dev/null

  # Typing the raw command, bypassing our mapping entirely — the actual
  # path that exposed the NERDTreeHijackNetrw duplicate the first time.
  tmux new-session -d -s vc_raw -x 200 -y 50 "env HOME=$_home vim $_dtmp" 2>/dev/null
  sleep 1
  tmux send-keys -t vc_raw Escape
  tmux send-keys -t vc_raw ':NERDTreeToggle' Enter; sleep 0.3
  tmux send-keys -t vc_raw ':echo winnr("$")' Enter; sleep 0.3
  ck ":NERDTreeToggle opens exactly one" "$(_winnr vc_raw)" "2"
  tmux send-keys -t vc_raw ':NERDTreeToggle' Enter; sleep 0.3
  tmux send-keys -t vc_raw ':echo winnr("$")' Enter; sleep 0.3
  ck ":NERDTreeToggle again closes it" "$(_winnr vc_raw)" "1"
  tmux send-keys -t vc_raw ':qa!' Enter; sleep 0.3
  tmux kill-session -t vc_raw 2>/dev/null

  # Opening a plain file (no directory argument, nothing auto-opened) still
  # opens fresh, exactly once, on the first toggle — the case that always
  # worked, checked again so the fix above didn't quietly break it.
  tmux new-session -d -s vc_file -x 200 -y 50 "cd $_dtmp && env HOME=$_home vim a.txt" 2>/dev/null
  sleep 1
  tmux send-keys -t vc_file C-v; sleep 0.2
  tmux send-keys -t vc_file e; sleep 0.3
  tmux send-keys -t vc_file Escape
  tmux send-keys -t vc_file ':echo winnr("$")' Enter; sleep 0.3
  ck "leader-e on a plain file opens exactly one" "$(_winnr vc_file)" "2"
  tmux send-keys -t vc_file ':qa!' Enter; sleep 0.3
  tmux kill-session -t vc_file 2>/dev/null

  # Toggling from inside the sidebar itself, not just from the file window —
  # a different code path in NERDTree, checked separately rather than
  # assumed to behave the same as toggling from the file side.
  tmux new-session -d -s vc_inside -x 200 -y 50 "cd $_dtmp && env HOME=$_home vim a.txt" 2>/dev/null
  sleep 1
  tmux send-keys -t vc_inside C-v; sleep 0.2
  tmux send-keys -t vc_inside e; sleep 0.3
  tmux send-keys -t vc_inside Escape
  tmux send-keys -t vc_inside C-w; sleep 0.1
  tmux send-keys -t vc_inside h; sleep 0.2
  tmux send-keys -t vc_inside C-v; sleep 0.2
  tmux send-keys -t vc_inside e; sleep 0.3
  tmux send-keys -t vc_inside Escape
  tmux send-keys -t vc_inside ':echo winnr("$")' Enter; sleep 0.3
  ck "leader-e from inside the sidebar closes it" "$(_winnr vc_inside)" "1"
  tmux send-keys -t vc_inside ':qa!' Enter; sleep 0.3
  tmux kill-session -t vc_inside 2>/dev/null

  rm -rf "$_dtmp"
else
  na "file tree open paths" "tmux not installed — this check needs a real terminal, not just batch mode"
fi

printf '\n--- Closing a file does not close vim ---\n'
# A real functional test, not just "does :Bd exist": open two files, close
# one, confirm vim switched to the other rather than exiting or erroring. No
# /dev/null file argument here, unlike the checks above — that would open a
# third buffer of its own and throw off the count this check depends on.
_bd_out=$(_vim \
  -c "edit /tmp/vimcheck_bd1.$$" -c "edit /tmp/vimcheck_bd2.$$" \
  -c "redir! > /tmp/vimcheck5.$$" \
  -c "echo 'before=' . len(getbufinfo({'buflisted':1}))" \
  -c "redir END" \
  -c "Bd" \
  -c "redir! >> /tmp/vimcheck5.$$" \
  -c "echo 'after=' . len(getbufinfo({'buflisted':1})) . ' switched=' . (bufname('%') =~# 'vimcheck_bd1' ? 'yes' : 'no')" \
  -c "redir END" -c "qa!" >/dev/null 2>&1
  cat "/tmp/vimcheck5.$$" 2>/dev/null; rm -f "/tmp/vimcheck5.$$" "/tmp/vimcheck_bd1.$$" "/tmp/vimcheck_bd2.$$")

ck "Bd closes a buffer"    "$(printf '%s' "$_bd_out" | sed -n 's/^before=//p')" "2"
ck "Bd switches, not quits" "$(printf '%s' "$_bd_out" | sed -n 's/.*switched=//p')" "yes"

printf '\n--- Clipboard (checked by mapping, not by using the clipboard) ---\n'
# check.sh promises never to write, and the real clipboard is the user's own
# state — trying an actual copy/paste round trip here would overwrite
# whatever they currently have on it. Introspection only: is the mapping
# present when xclip and a display are, and correctly absent when not.
_clip_out=$(_vim \
  -c "redir! > /tmp/vimcheck6.$$" \
  -c "echo 'y=' . strtrans(maparg('<leader>y', 'v'))" \
  -c "echo 'p=' . strtrans(maparg('<leader>p', 'n'))" \
  -c "redir END" -c "qa!" /dev/null >/dev/null 2>&1
cat "/tmp/vimcheck6.$$" 2>/dev/null; rm -f "/tmp/vimcheck6.$$")

if command -v xclip &>/dev/null && [ -n "${DISPLAY:-}" ]; then
  ck "clipboard yank mapped"  "$(printf '%s' "$_clip_out" | sed -n 's/^y=//p')" ":w !xclip -selection clipboard<CR><CR>"
  ck "clipboard paste mapped" "$(printf '%s' "$_clip_out" | sed -n 's/^p=//p')" ":r !xclip -selection clipboard -o<CR>"
else
  na "clipboard mappings" "no xclip, or no DISPLAY, on this host — correctly left unmapped rather than mapped to a command that would fail"
fi

if command -v rg &>/dev/null; then
  _rg_out=$(_vim \
    -c "redir! > /tmp/vimcheck2.$$" -c "echo 'grepprg=' . &grepprg" -c "redir END" -c "qa!" /dev/null >/dev/null 2>&1
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
