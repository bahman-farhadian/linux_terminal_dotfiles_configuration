# linux dotfiles

Debian dotfiles for **bash**, **tmux**, and **SSH** — Gruvbox dark theme
throughout. Adapted from the macOS set, with every macOS-only assumption
removed.

The repository also carries a Debian 13 build guide per machine, named for the
host: [Silenus/Silenus.md](Silenus/Silenus.md), the Lenovo ThinkPad T14 Gen 4
(Intel) GNOME workstation these dotfiles were built on, and
[Dionysus/Dionysus.md](Dionysus/Dionysus.md), a headless AMD Ryzen 9 3900X KVM
and Docker host with no desktop environment.

Each host has its own directory holding a complete, self-contained copy of what
it installs. Deploy by running the installer inside the directory for that
machine.

## Layout

```
linux_terminal_dotfiles_configuration/
├── README.md              this file, covering both hosts
├── Silenus/               ThinkPad T14 Gen 4 (Intel) workstation
│   ├── bash/
│   │   ├── bash_profile   → ~/.bash_profile
│   │   ├── bashrc         → ~/.bashrc
│   │   └── bash_aliases   → ~/.bash_aliases
│   ├── tmux/
│   │   └── tmux.conf      → ~/.tmux.conf
│   ├── ssh/
│   │   └── config         → managed block in ~/.ssh/config
│   ├── hushlogin          → ~/.hushlogin
│   ├── install.sh         bash, tmux, ssh, and the GNOME parts
│   ├── check.sh
│   ├── gnome-app-folders.py
│   └── Silenus.md
└── Dionysus/              headless Ryzen 9 3900X KVM host
    ├── bash/              same three files, without the DE/EN/kbd aliases
    ├── tmux/
    ├── ssh/
    ├── hushlogin
    ├── install.sh         bash, tmux, ssh only — no GNOME
    └── Dionysus.md
```

## Prerequisites

```bash
sudo apt install tmux vim git curl jq tree python3 openssl bash-completion xclip htop
```

## Deploy

```bash
cd Silenus     # or: cd Dionysus
./install.sh
```

```bash
exec bash
```

The script is idempotent, and idempotent for both accounts. It asks once whether
to configure `root` as well — answer `y` to get the same prompt, aliases, and
tmux settings under `su`. The answer is recorded in `/etc/dotfiles-root-configured`,
so every later run refreshes `/root` too rather than leaving it on whatever an
earlier run happened to install. `--root` and `--no-root` answer the question for
an unattended run; deleting the stamp stops root being managed.

Run it as your own user, never as root. It installs into `$HOME`, so running it
as root configures `/root` and leaves your account untouched.

### What it overwrites, and what it leaves alone

`.bashrc`, `.bash_profile`, `.bash_aliases`, `.tmux.conf` and `.hushlogin` are
replaced outright on every run, for both accounts. They are this repository's
files; whatever is in them came from here, and anything added to them by hand is
lost on the next run. Put personal additions in a file this repository does not
name.

`~/.ssh/config` is the exception, because it holds Host entries that have nothing
to do with these dotfiles. Only the marked block is rewritten:

```
# >>> dotfiles managed block >>>
Host *
    StrictHostKeyChecking no
    ...
# <<< dotfiles managed block <<<
```

Everything outside the markers is kept byte for byte, and the block is written at
the **end** of the file. That position matters: `ssh` uses the first value it
finds for each keyword, so a `Host *` section sitting above the specific hosts
overrides all of them — `Port 22` in the defaults quietly defeats the `Port 443`
written for a host that has to reach the outside on 443. An install from before
the markers existed wrote the block at the top and had exactly that effect; the
first run of the current script moves it to the end and repairs those hosts.

## Differences from the macOS set

- No Homebrew, no `pbcopy`/`pbpaste`, no `gnubin` coreutils shim.
- `cpy` uses `xclip` when a display is present, and falls back to plain `tee` on
  a headless machine.
- `privip` lists every private address by interface. `ports` uses `ss -tunlp`.
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

The status bar uses Gruvbox's background ramp only, no accents. It is chrome, so
it stays out of the way and lets the prompt carry the colour. Blocks are told
apart by stepping up that ramp rather than by hue.

| Element | Block | Text |
|---|---|---|
| inactive window | bg1 `#3c3836` | fg1 `#ebdbb2` |
| session name | bg2 `#504945` | bright yellow `#fabd2f` |
| active window | bg3 `#665c54` | fg0 `#fbf1c7` |
| zoomed marker | bg0_h `#1d2021` | bright red `#fb4934` |

Both tabs stay light, so the active one is told apart by its lighter block
rather than by dimmer text. The session name carries bright yellow, since it
names the session and is worth picking out at a glance. bright red is the only accent left and appears only where
it means something — the zoomed marker and the synchronised-panes borders.

The bar itself uses `bg=default` so it takes the terminal's own background. A
terminal window whose height is not an exact multiple of the character cell
leaves a strip below the last row; any fixed background colour on the bar shows
up as a seam against it.

## Prompt

```
bahman @ Silenus ~/project main*⇡1 venv:api k8s:prod $
```

One line, plain colour, no badges and no background blocks. The accents are Gruvbox dark, used
exactly as published. The bright variants carry the prompt because the normal
ones sit too dark on `bg0`: blue is 3.48:1 normal against 5.48:1 bright, purple
the same. The colour lives here; the tmux bar stays neutral. No clock — use
`date` when you want one. Only the user name changes colour, so root is obvious at a glance
while the host name stays put.

| Segment | Colour | Shown when |
|---|---|---|
| user | bright green `#b8bb26`, bright red `#fb4934` for root | always |
| `@` | gray `#928374` | always |
| host | bright yellow `#fabd2f` | always |
| path | bright blue `#83a598` | always |
| branch | orange `#fe8019` | inside a git repository |
| `venv:` | bright purple `#d3869b` | a virtualenv is active |
| `k8s:` | bright aqua `#8ec07c` | `kubectl` has a current context |

Branch suffixes carry their own colour: `*` unstaged is Red, `+` staged is
Green, `⇡N` ahead and `⇣N` behind are Sky, `{N}` stashes is Flamingo.
The `$` turns red when the last command failed, and becomes `#` for root.

For the full effect set the terminal profile to Gruvbox dark too, so the
background is `#282828` and the ANSI colours match. The contrast figures above
are measured against that background.

`install.sh` uses the same palette for its own output: bright green for a step
that succeeded, bright yellow for a warning, gray for one that was skipped.

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
| `DE` | keyboard: German only |
| `EN` | keyboard: US English and Persian |
| `kbd` | show the current input sources |
| `pubkey` | print the first SSH public key |
| `password` | random base64-48 string |
| `pubip` / `privip` | external IP / every private address, by interface |
| `ports` | listening TCP and UDP sockets, with the process holding each |
| `cpy` | pipe filter — `cmd 2>&1 \| cpy` prints and copies |

`ports`, `update` and `upgrade` are functions, not aliases, because they decide
whether `sudo` is needed: as root they run the commands directly, otherwise through
`sudo`. `update` changes nothing beyond refreshing the package lists.

`privip` is a function for a different reason. On a machine running a VPN, Docker
and libvirt there is no single private address to report — this one holds five:

```
$ privip
wlp0s20f3   192.168.8.2  ← default route
tun0        10.11.12.21
tun1        192.168.80.53
virbr0      192.168.122.1
docker0     172.17.0.1
```

`hostname -I` prints those same five as one unlabelled line, in whatever order the
interfaces happened to appear, so it cannot tell you which is which. `privip`
names the interface behind each one and puts them in a useful order: the address
the kernel would actually route out with first, the local bridges last, since
docker0 and virbr0 are this host talking to its own containers and guests rather
than addresses anything else reaches it on. Marking the default route is a routing
table lookup: nothing is sent over the network.

`DE` and `EN` replace the GNOME input source list outright rather than adding
to it, so only the named layouts remain. They take effect immediately, with no
log out.

`install.sh` writes `~/.local/bin/lock-keyboard-en.sh` and runs it two ways.

`lock-keyboard-en.service` watches for the screen locking. On lock it makes
English the only layout in the list, so nothing else can be active while the
password is typed. On unlock it puts Persian back.

`keyboard-en-tick.timer` runs every 10 minutes and does the same drop and
restore.

Both act only when the list is already the English pair. A deliberate switch to
German with `DE` — or any other list set by hand — is left exactly as it is, on
the lock as much as on the timer, and the unlock does not drag it back to the
pair. The trade-off is deliberate: with German active, the password prompt is on
the German layout too, because overruling that choice is the thing being avoided.
Run `EN` before locking if you would rather type the password in English.

Only the layout list is written. GNOME ignores writes to the selected index,
and that key reads `0` even while Persian is the live layout, so removing the
unwanted layouts is the only method that reliably changes what is active.

Both are per-user: the settings, the services and the session bus all belong to
your login, so none of it applies to a root shell.

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
