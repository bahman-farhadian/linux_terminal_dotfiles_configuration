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
├── tmux-diag.sh
├── gnome-app-folders.py
├── lock-keyboard-en.sh   → ~/.local/bin/ + cron
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

`./tmux-diag.sh` reports client and window sizes, every attached client, and
whether any rows are left unpainted at the bottom. Run it in the terminal
window, not over SSH.

`.bashrc` starts tmux for every interactive terminal. It attaches to the first
detached session if there is one, so closing a terminal window and opening a
new one puts you back where you were. With no detached session it starts a new
one. Opening several terminals therefore gives you `tmux01`, `tmux02`, and so
on rather than mirrored views of one session.

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
| `ports` | listening TCP and UDP sockets |
| `cpy` | pipe filter — `cmd 2>&1 \| cpy` prints and copies |

`DE` and `EN` replace the GNOME input source list outright rather than adding
to it, so only the named layouts remain. They take effect immediately, with no
log out.

`install.sh` also puts `lock-keyboard-en.sh` in `~/.local/bin` and adds a cron
entry that runs it every 10 minutes. While the screen is locked it restores the
English layout, so the unlock prompt is never left on a German or Persian
keyboard. While the session is unlocked it does nothing.

**Git:** `g gs ga gaa gc gca gco gcob gb gl gd gds gp gpf gpl gpr gst gstp gstl gf grb gcp gwip`

**Python:** `py pip piv va vd pipi pipr pipff jn jl`

**Docker:** `d dps dpsa di dex dlogs dstop dstart dprune dc dcu dcd dcl dcr dcb`

**Kubernetes:** `k kgp kgpa kgs kgn kgd kdes kdp kds kdn klogs kex kap kdel kctx kuse kns krun`

## SSH

`ssh/config` is appended to `~/.ssh/config`, replacing any stale block on
re-run. It sets `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null`
for every host, which disables host key verification. Remove those two lines if
you connect to machines where a changed host key should be an error.
