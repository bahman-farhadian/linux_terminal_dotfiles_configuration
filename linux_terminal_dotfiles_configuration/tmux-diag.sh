#!/usr/bin/env bash
# tmux-diag.sh — one shot report on the two problems this config has had:
#   * a blank band at the bottom, from the window and client disagreeing on size
#   * panes not returning to equal height after one is closed
# Run it inside the terminal window, not over SSH: it measures the client you
# are looking at.

hr() { printf '\n--- %s ---\n' "$1"; }

echo "=== environment ==="
[ -n "$SSH_CONNECTION" ] && echo "  over ssh   : YES  <-- run this in the terminal window instead" \
                         || echo "  over ssh   : no"
[ -z "$TMUX" ] && { echo "  inside tmux: NO — nothing to measure"; exit 0; }
echo "  inside tmux: yes"
echo "  tmux       : $(tmux -V | sed 's/tmux //')"
echo "  TERM       : $TERM"

hr "is the running server using the current config"
SPID=$(tmux display-message -p '#{pid}')
ETIME=$(ps -o etimes= -p "$SPID" 2>/dev/null | tr -d ' ')
case "$ETIME" in ''|*[!0-9]*) ETIME="" ;; esac
CFGM=$(stat -c %Y "$HOME/.tmux.conf" 2>/dev/null); case "$CFGM" in ''|*[!0-9]*) CFGM="" ;; esac
echo "  server pid : $SPID"
if [ -n "$ETIME" ] && [ -n "$CFGM" ]; then
  SSTART=$(( $(date +%s) - ETIME ))
  echo "  server up  : $(( ETIME / 60 )) min, started $(date -d "@$SSTART" '+%H:%M:%S' 2>/dev/null)"
  echo "  conf saved : $(date -d "@$CFGM" '+%H:%M:%S' 2>/dev/null)"
  [ "$CFGM" -gt "$SSTART" ] \
    && echo "  STALE — ~/.tmux.conf changed after the server started. Run: tmux kill-server" \
    || echo "  OK — server started after the last change to ~/.tmux.conf"
else
  echo "  (could not compare times on this system)"
fi

hr "sizes"
CW=$(tmux display-message -p '#{client_width}');  CH=$(tmux display-message -p '#{client_height}')
WW=$(tmux display-message -p '#{window_width}');  WH=$(tmux display-message -p '#{window_height}')
if [ -z "$CW" ] || [ -z "$CH" ]; then
  echo "  no client attached — run this in the terminal window itself"
else
  echo "  client $CW x $CH   (the terminal window)"
  echo "  window $WW x $WH   (what tmux paints)"
  GAP=$(( CH - 1 - WH )); WGAP=$(( CW - WW ))
  if   [ "$GAP" -gt 0 ]; then echo "  HEIGHT: $GAP UNPAINTED ROWS — the blank band. Run: tmux resize-window -A"
  elif [ "$GAP" -lt 0 ]; then echo "  HEIGHT: window is $(( -GAP )) rows TALLER than this client — cropped view, another client is bigger"
  else                        echo "  HEIGHT: OK — $WH pane rows + 1 status row = $CH"; fi
  if   [ "$WGAP" -gt 0 ]; then echo "  WIDTH : $WGAP unpainted columns. Run: tmux resize-window -A"
  elif [ "$WGAP" -lt 0 ]; then echo "  WIDTH : window is $(( -WGAP )) cols WIDER than this client — cropped view"
  else                         echo "  WIDTH : OK — $WW"; fi
fi

hr "clients (two on one session is the usual cause of a band)"
tmux list-clients -F '  #{client_tty}  session=#{client_session}  #{client_width}x#{client_height}'

hr "panes in this window"
tmux list-panes -F '  pane #{pane_index}  #{pane_height} rows  #{pane_current_command}'
HS=$(tmux list-panes -F '#{pane_height}')
N=$(printf '%s\n' "$HS" | wc -l | tr -d ' ')
MAX=$(printf '%s\n' "$HS" | sort -n | tail -1); MIN=$(printf '%s\n' "$HS" | sort -n | head -1)
if   [ "$N" -le 1 ];             then echo "  single pane — split with Ctrl+b \" to test realignment"
elif [ $(( MAX - MIN )) -le 1 ]; then echo "  BALANCED — $N panes, $MIN to $MAX rows"
else echo "  UNBALANCED — $N panes, $MIN to $MAX rows. Run: tmux select-layout even-vertical"; fi

hr "options"
tmux show-options -g window-size | sed 's/^/  /'
tmux show-options -g base-index  | sed 's/^/  /'

hr "hooks the server reports"
tmux show-hooks -g | grep -E 'client-attached|client-resized|session-created' | sed 's/^/  /'
echo "  note: pane-exited fires but tmux does not list it in show-hooks, so it is"
echo "        read from the config file below instead."

hr "hooks in ~/.tmux.conf"
grep -n 'set-hook' "$HOME/.tmux.conf" 2>/dev/null | cut -c1-110 | sed 's/^/  /' \
  || echo "  no set-hook lines found"

hr "bindings that must realign panes"
tmux list-keys -T prefix | grep -E 'kill-pane|split-window' | grep -v 'display-menu' | cut -c1-160 | sed 's/^/  /'
echo
echo "  Ctrl+b x must contain BOTH kill-pane and select-layout."
echo "  Ctrl+d is handled by the pane-exited hook, not by a binding."
