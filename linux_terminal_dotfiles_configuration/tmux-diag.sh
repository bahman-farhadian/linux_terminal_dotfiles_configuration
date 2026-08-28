#!/usr/bin/env bash
# tmux-diag.sh — why is there a blank band at the bottom of the terminal?
#
# tmux draws the pane at the window size and the status bar at the bottom of the
# client. When the two disagree it never paints the rows between them and the
# GTK background shows through. Run this in the terminal window itself, not
# over SSH, since it measures the client you are looking at.

[ -n "$SSH_CONNECTION" ] && echo "over ssh   : YES  <-- run this in the terminal window instead" \
                         || echo "over ssh   : no"
[ -z "$TMUX" ] && { echo "inside tmux: NO — nothing to measure"; exit 0; }
echo "tmux       : $(tmux -V | sed 's/tmux //')   TERM: $TERM"

CW=$(tmux display-message -p '#{client_width}');  CH=$(tmux display-message -p '#{client_height}')
WW=$(tmux display-message -p '#{window_width}');  WH=$(tmux display-message -p '#{window_height}')

echo
echo "--- sizes ---"
echo "  client $CW x $CH   (the terminal window)"
echo "  window $WW x $WH   (what tmux paints)"
echo
echo "--- clients (two on one session is the usual cause) ---"
tmux list-clients -F '  #{client_tty}  session=#{client_session}  #{client_width}x#{client_height}'
echo
echo "--- options and hooks ---"
tmux show-options -g window-size | sed 's/^/  /'
tmux show-hooks   -g | grep -E 'client-attached|client-resized' | sed 's/^/  /'
echo
echo "--- verdict ---"
GAP=$(( CH - 1 - WH )); WGAP=$(( CW - WW ))
if   [ "$GAP" -gt 0 ]; then echo "  HEIGHT: $GAP UNPAINTED ROWS — this is the blank band -> tmux resize-window -A"
elif [ "$GAP" -lt 0 ]; then echo "  HEIGHT: window is $(( -GAP )) rows TALLER than this client — cropped view, another client is bigger"
else                        echo "  HEIGHT: OK — $WH pane rows + 1 status row = $CH"; fi
if   [ "$WGAP" -gt 0 ]; then echo "  WIDTH : $WGAP unpainted columns -> tmux resize-window -A"
elif [ "$WGAP" -lt 0 ]; then echo "  WIDTH : window is $(( -WGAP )) cols WIDER than this client — cropped view"
else                         echo "  WIDTH : OK — $WW"; fi
