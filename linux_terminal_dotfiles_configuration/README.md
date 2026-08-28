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
| `Ctrl+b` + `Space` | Cycle layouts |
| `Ctrl+b` + `@` | Toggle synchronize-panes — borders turn red |
| `PgUp` / `PgDn` | Enter / scroll copy-mode |
| `q` / `Esc` | Exit copy-mode |
| `F12` | Toggle nested-tmux passthrough |

## Prompt

```
─ [bash]  venv:name  user@host  k8s:cluster  branch*⇡1  ~/path  Local ...  UTC ...
$
```

Git badge suffixes: `*` unstaged · `+` staged · `⇡N` ahead · `⇣N` behind ·
`{N}` stashes. The prompt needs a terminal with true colour and Unicode.

## SSH

`ssh/config` is appended to `~/.ssh/config`, replacing any stale block on
re-run. It sets `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null`
for every host, which disables host key verification. Remove those two lines if
you connect to machines where a changed host key should be an error.
