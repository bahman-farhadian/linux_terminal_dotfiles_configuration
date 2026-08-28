# linux dotfiles

Debian dotfiles for **bash**, **tmux**, and **SSH** — Catppuccin Mocha theme
throughout. Adapted from the macOS set, with every macOS-only assumption
removed.

The repository also carries
[thinkpad-t14-gen4-debian-13-setup.md](thinkpad-t14-gen4-debian-13-setup.md),
the Debian 13 install and configuration guide for the machine these dotfiles
were built on.

## Layout

```
linux_terminal_dotfiles_configuration/
├── bash/
│   ├── bash_profile   → ~/.bash_profile
│   ├── bashrc         → ~/.bashrc
│   └── bash_aliases   → ~/.bash_aliases
├── tmux/
│   └── tmux.conf      → ~/.tmux.conf
├── ssh/
│   └── config         → appended to ~/.ssh/config
├── install.sh
├── gnome-app-folders.py
├── hushlogin          → ~/.hushlogin
└── thinkpad-t14-gen4-debian-13-setup.md
```

## Prerequisites

```bash
sudo apt install tmux vim git curl jq tree python3 openssl bash-completion xclip htop
```

## Deploy

```bash
./install.sh
```

```bash
exec bash
```

The script is idempotent. It asks whether to configure `root` as well — answer
`y` to get the same prompt, aliases, and tmux settings under `su`.

Run it as your own user, never as root. It installs into `$HOME`, so running it
as root configures `/root` and leaves your account untouched.

## Differences from the macOS set

- No Homebrew, no `pbcopy`/`pbpaste`, no `gnubin` coreutils shim.
- `cpy` uses `xclip` when a display is present, and falls back to plain `tee` on
  a headless machine.
- `privip` uses `hostname -I`. `ports` uses `ss -tunlp`.
- `b` prefers `btop` and falls back to `htop`.
- Plain colour prompt, not the macOS badge/powerline style, and segments are hidden rather than showing `disconnected` or `inactive`.
- No Option-key bindings. Ghostty on macOS sent `M-w/a/s/d` and `M-1`–`M-7`;
  on Linux those collide with terminal and window-manager shortcuts, so pane
  navigation is prefix-only.

## tmux

| Keys | Action |
|---|---|
| `Shift+←` / `Shift+→` | Previous / next window |
| `Ctrl+b` + `h/j/k/l` | Pane focus |
| `Ctrl+b` + arrows | Pane focus |
| `Ctrl+b` + `"` | Stacked pane, heights equalized |
| `Ctrl+b` + `x` | Close pane, heights equalized |
| `Ctrl+d` | Exit the shell, heights equalized |
| `Ctrl+b` + `Space` | Cycle layouts |
| `Ctrl+b` + `@` | Toggle synchronize-panes — borders turn red |
| `PgUp` / `PgDn` | Enter / scroll copy-mode |
| `q` / `Esc` | Exit copy-mode |
| `F12` | Toggle nested-tmux passthrough |

Windows and panes count from 1. tmux has no `session-base-index` option, so a
`session-created` hook renames unnamed sessions to `tmux01`, `tmux02`, and so
on. A session created with an explicit name keeps it.

Stacked panes stay equal height when one is closed, whether with `Ctrl+b x` or
`Ctrl+d`. The two paths fire different hooks — `after-kill-pane` and
`pane-exited` — so both are set.

`./gnome-app-folders.py` sorts the GNOME application grid into alphabetical
folders. `--list` previews, `--apply` does it, `--clear-dock` does it and also
empties the pinned dock, `--status` reads back what is set. With no arguments
it prints the options and changes nothing. It is idempotent, so re-run it after
installing anything.

`.bashrc` starts tmux for every interactive terminal. It attaches to the first
detached session if there is one, so closing a terminal window and opening a
new one puts you back where you were. With no detached session it starts a new
one. Opening several terminals therefore gives you `tmux01`, `tmux02`, and so
on rather than mirrored views of one session.

`window-size` is set to `smallest`, so the session fits the smallest attached
client and a larger one fills the leftover area with dots. The tmux default,
`latest`, resizes the session every time you use a different client, which makes
the pane sizes move around as you switch between the terminal and SSH.

Over SSH it attaches to a session named `ssh` instead, creating it if needed,
and a local shell never picks that session up. Each session then follows its
own terminal size. Sharing one session between a remote and a local client
makes tmux size the windows for both, which crops the smaller one and leaves an
unpainted band in the larger.

It also skips when `$TERM` is already `tmux-*` or `screen-*`. `sudo -i` and
`su -` scrub `$TMUX` but keep `$TERM`, so without that check they would start a
second tmux inside the pane you are already in.

To open a terminal without tmux:

```bash
NO_AUTO_TMUX=1 bash
```

tmux is run rather than `exec`'d, so a broken `~/.tmux.conf` leaves you at a
working shell instead of a terminal that closes the moment it opens.

The status bar is coloured text rather than badges, matching the prompt, and
uses `bg=default` so it takes the terminal's own background. A terminal window
whose height is not an exact multiple of the character cell leaves a strip
below the last row; any fixed background colour on the bar shows up as a seam
against it.

## Prompt

```
bahman @ Silenus ~/project main*⇡1 venv:api k8s:prod $
```

One line, plain colour, no badges and no background blocks. No clock — use
`date` when you want one. Only the user name changes colour, so root is obvious at a glance
while the host name stays put.

| Segment | Colour | Shown when |
|---|---|---|
| user | Green `#a6e3a1`, Red `#f38ba8` for root | always |
| `@` | Overlay0 `#6c7086` | always |
| host | Yellow `#f9e2af` | always |
| path | Blue `#89b4fa` | always |
| branch | Peach `#fab387` | inside a git repository |
| `venv:` | Mauve `#cba6f7` | a virtualenv is active |
| `k8s:` | Sky `#89dceb` | `kubectl` has a current context |

Branch suffixes carry their own colour: `*` unstaged is Red, `+` staged is
Green, `⇡N` ahead and `⇣N` behind are Sky, `{N}` stashes is Flamingo.
The `$` turns red when the last command failed, and becomes `#` for root.

Needs a true-colour terminal. GNOME Terminal qualifies.

## Aliases

| Alias | Action |
|---|---|
| `update` | refresh apt sources, list what apt and flatpak would upgrade |
| `upgrade` | upgrade apt and flatpak, then autoremove, purge and drop unused runtimes |
| `c` / `reload` | clear / restart the shell |
| `t` | tmux |
| `v` | vim |
| `b` | btop, or htop if btop is missing |
| `ll` / `l` / `la` | listings |
| `nekoray` | root only — starts nekoray with its icon |
| `DE` | keyboard: German only |
| `EN` | keyboard: US English and Persian |
| `kbd` | show the current input sources |
| `pubkey` | print the first SSH public key |
| `password` | random base64-48 string |
| `pubip` / `privip` | external / private IP |
| `ports` | listening TCP and UDP sockets, with the process holding each |
| `cpy` | pipe filter — `cmd 2>&1 \| cpy` prints and copies |

`nekoray` is defined only when the shell is root and the binary is present, so
it never appears for an ordinary user where it would start and then fail on the
tunnel. It runs from `/nekoray`, because the binary loads `geoip.dat`,
`geosite.dat` and `config/` by relative path, and backgrounds itself the way the
bundled launcher does. It passes no icon: the application sets an
empty one itself after Qt reads the command line, so `_NET_WM_ICON` is empty
whatever is given. Only a `.desktop` file can supply an icon for it.

`ports`, `update` and `upgrade` are functions, not aliases, because they decide
whether `sudo` is needed: as root they run the commands directly, otherwise through
`sudo`. `update` changes nothing beyond refreshing the package lists.

`DE` and `EN` replace the GNOME input source list outright rather than adding
to it, so only the named layouts remain. They take effect immediately, with no
log out.

`install.sh` also writes `~/.local/bin/lock-keyboard-en.sh` and a matching
systemd user service that watches for the screen locking and switches to English the moment it
happens, whatever layout was active. The unlock prompt is then never left on a
keyboard that cannot type the password. It does nothing while the session is
unlocked.

It watches the lock signal rather than polling. A timer only notices the lock on
its next tick, which is too late to be any use.

It sets both the input source list and the selected index. Setting the list
alone is not enough: German disappears from it and the selection falls back on
its own, but Persian stays in the list and stays active unless the index is
moved.

**Git:** `g gs ga gaa gc gca gco gcob gb gl gd gds gp gpf gpl gpr gst gstp gstl gf grb gcp gwip`

**Python:** `py pip piv va vd pipi pipr pipff jn jl`

**Docker:** `d dps dpsa di dex dlogs dstop dstart dprune dc dcu dcd dcl dcr dcb`

**Kubernetes:** `k kgp kgpa kgs kgn kgd kdes kdp kds kdn klogs kex kap kdel kctx kuse kns krun`

`install.sh` fetches a tmux bash completion into
`~/.local/share/bash-completion/completions/`. Debian packages none, so tab
completion for `tmux` and the `t` alias does not work without it.

## GNOME shortcuts

`install.sh` sets these:

| Keys | Action |
|---|---|
| `Ctrl+Alt+T` | GNOME Terminal |
| `Super+E` | Files |
| `Super+I` | Settings |
| `Alt+Tab` | switch windows |
| `Shift+Alt+Tab` | switch windows, backwards |

`Alt+Tab` normally switches *applications*, grouping every window of one
program behind a single icon. Moving it to `switch-windows` gives one entry per
window. The application switcher has to be cleared first, or it keeps the key.

Both schemas are reset to GNOME's defaults before these are applied, so the
result never depends on what was bound previously. Anything you bound by hand
is reset too.

## SSH

### Server

`install.sh` writes `/etc/ssh/sshd_config.d/99-local.conf` with
`PermitRootLogin prohibit-password`, so root can connect with a key but never
with a password. Ordinary users are unchanged and the port stays at 22.

It validates with `sshd -t` before reloading and restores the previous file if
sshd rejects it, because a bad `sshd_config` locks you out of the machine. It
also checks that `/etc/ssh/sshd_config` actually has the `Include` line for
`sshd_config.d`, since without it a drop-in is silently ignored.

### Client

`ssh/config` is appended to `~/.ssh/config`, replacing any stale block on
re-run. It sets `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null`
for every host, which disables host key verification. Remove those two lines if
you connect to machines where a changed host key should be an error.
