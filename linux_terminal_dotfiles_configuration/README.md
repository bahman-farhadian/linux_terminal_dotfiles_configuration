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
├── check.sh
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
 bahman@Silenus  ~/project  main*⇡1  venv:api  k8s:prod
$
```

Two lines. Every segment draws Text `#cdd6f4` on its own dark block, so all of
it reads equally well and the block colour alone says which segment you are
looking at. Same approach as the tmux status bar. No clock — use `date` when you
want one. Only the `user@host` block changes colour, so root is obvious at a
glance.

| Segment | Block | Shown when |
|---|---|---|
| `user@host` | Green `#455a4a`, Red `#77485a` for root | always |
| path | Blue `#45577b` | always |
| branch | Peach `#6c5045` | inside a git repository |
| `venv:` | Mauve `#5f5077` | a virtualenv is active |
| `k8s:` | Sapphire `#395a6f` | `kubectl` has a current context |

Each block is its Catppuccin Mocha accent blended into Crust as far as it goes
while still holding the white text near 5:1, which is the darkest that hue gets
before it turns grey.

Branch suffixes keep their own bright accent, because the colour is the whole
point of them: `*` unstaged is Red, `+` staged is Green, `⇡N` ahead and `⇣N`
behind are Sky, `{N}` stashes is Flamingo.

The `$` sits on its own line, turns Red when the last command failed, and
becomes `#` for root.

No powerline separators, so no patched font is needed. Needs a true-colour
terminal. GNOME Terminal qualifies.

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
| `DE` | keyboard: German only |
| `EN` | keyboard: US English and Persian |
| `kbd` | show the current input sources |
| `pubkey` | print the first SSH public key |
| `password` | random base64-48 string |
| `pubip` / `privip` | external / private IP |
| `ports` | listening TCP and UDP sockets, with the process holding each |
| `cpy` | pipe filter — `cmd 2>&1 \| cpy` prints and copies |

`ports`, `update` and `upgrade` are functions, not aliases, because they decide
whether `sudo` is needed: as root they run the commands directly, otherwise through
`sudo`. `update` changes nothing beyond refreshing the package lists.

`DE` and `EN` replace the GNOME input source list outright rather than adding
to it, so only the named layouts remain. They take effect immediately, with no
log out.

`install.sh` writes `~/.local/bin/lock-keyboard-en.sh` and runs it two ways.

`lock-keyboard-en.service` watches for the screen locking. On lock it makes
English the only layout in the list, so nothing else can be active while the
password is typed. On unlock it puts Persian back.

`keyboard-en-tick.timer` runs every 10 minutes and does the same drop and
restore, but only when the list is already the English pair, so a deliberate
switch to German is left alone.

Only the layout list is written. GNOME ignores writes to the selected index,
and that key reads `0` even while Persian is the live layout, so removing the
unwanted layouts is the only method that reliably changes what is active.

Both are per-user: the settings, the services and the session bus all belong to
your login, so none of it applies to a root shell.

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
