# ThinkPad T14 Gen 4 (Intel) — Debian 13 "trixie" Setup

## Part 1 — OS installation

### Step 1 — BIOS: allow the Microsoft 3rd party CA

| # | Step | How |
|---|------|-----|
| 1 | Enter BIOS | Power off fully, power on, tap **F1** at the Lenovo splash |
| 2 | Note BIOS version | `Main` tab — write it down |
| 3 | Open Secure Boot | `Security → Secure Boot` |
| 4 | Allow the 3rd party CA | `Allow Microsoft 3rd Party UEFI CA` = **On** |
| 5 | Check the other lines | `Secure Boot` = **On**, `Secure Boot Mode` = **User Mode**, `Secure Boot Key State` = **Standard** |
| 6 | Save and exit | **F10** → **Yes** |

**Notes**

- Debian's bootloader is signed by Microsoft's 3rd party UEFI CA. If this is **Off**, the machine fails to boot with `Invalid signature detected`.
- Leave `Secure Boot` **On** for the whole install. Debian handles it.
- Do not touch `Reset to Setup Mode` or `Clear All Secure Boot Keys`. Debian does not need them, and they cause the failure above.
- Boot the installer with **F12** and pick the USB device. This is a one-time choice and does not change the boot order.

### Step 2 — Disk partitioning

Choose **Manual** partitioning. The installer counts in decimal, so `MB` means
1,000,000 bytes. Type the **Enter as** value. The installer will then display
the **Shows as** value.

| # | Partition | Size | Enter as | Shows as | Format | Mount |
|---|-----------|------|----------|----------|--------|-------|
| 1 | EFI | 1 GiB | `1075 MB` | 1.1 GB | EFI System Partition | `/boot/efi` |
| 2 | Boot | 2 GiB | `2147 MB` | 2.1 GB | ext4 | `/boot` |
| 3 | Root | 888 GiB | `953483 MB` | 953.5 GB | xfs | `/` |

**Notes**

- Leave the rest of the disk unpartitioned. That free space is SSD over-provisioning: 953.87 GiB disk, minus 3 GiB for EFI and boot, minus 888 GiB for root, leaves 62.87 GiB free, or 6.6%.
- The drive uses that space for wear levelling, which keeps write speed up as the disk fills. Samsung suggests about 10%.
- To reach 10%, use a root of 855 GiB (`918049 MB`) instead. That leaves 95.87 GiB free, or 10.1%.
- The installer counts in GB. `df -h` counts in GiB. Root shows as `953.5 GB` now and `888G` later. Same partition.
- The first partition starts 1 MiB into the disk, so it ends up 1 MiB smaller than asked. `1075 MB` accounts for that and gives a full 1 GiB. If yours still shows `1023M`, it is harmless.
- For any other size: type `GiB x 1073.741824` MB, rounded.
- No swap partition. Hibernation needs swap, and hibernation does not work while Secure Boot is on. See the note in Step 3.
- The installer warns that no swap space is selected. Continue anyway.
- XFS handles big files well, like a 200 GiB qcow2 image.
- Docker runs on XFS. It can also cap container size with `--storage-opt size=`, which needs the `prjquota` mount option.

### Step 3 — After install: repositories, quota, checks

#### 1. Become root

Everything in this step is run as root.

```bash
su -
```

#### 2. Install vim

```bash
apt update
```

```bash
apt install vim
```

Make it the default editor for `visudo` and friends:

```bash
update-alternatives --config editor
```

#### 3. Add your user to sudoers

The installer only grants `sudo` when the root password is left empty. If you
set a root password, the user has none.

```bash
visudo
```

Find this line:

```
root    ALL=(ALL:ALL) ALL
```

Add your own user underneath it, replacing `username` with your login name:

```
username    ALL=(ALL:ALL) ALL
```

Save and exit. `visudo` checks the syntax before writing and refuses to save a
broken file, which is why it is used instead of editing the file directly.

Check it:

```bash
sudo -l -U username
```

#### 4. Add contrib and non-free

The installer writes the classic file, not a `.sources` file:

```bash
vim /etc/apt/sources.list
```

Make the file read exactly this:

```
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
```

Only `contrib` and `non-free` are new. Keep the suite name — `trixie`,
`trixie-security`, `trixie-updates` — between the URL and the components. If
you drop it, `apt update` fails with a 404 on the Release file.

Check the result:

```bash
grep ^deb /etc/apt/sources.list
```

#### 5. Update the system

```bash
apt update
```

```bash
apt full-upgrade
```

#### 6. Install the tools used for checking

```bash
apt install mokutil dmidecode efibootmgr
```

#### 7. Edit GRUB: quota and boot timeout

Docker can only cap a container's disk size (`--storage-opt size=`) when root
is mounted with project quota. Root is mounted before `/etc/fstab` is read, so
this goes on the kernel command line.

```bash
vim /etc/default/grub
```

Change these two lines so they read:

```
GRUB_TIMEOUT=10
GRUB_CMDLINE_LINUX="rootflags=uquota,pquota"
```

`GRUB_TIMEOUT` is `5` by default and `GRUB_CMDLINE_LINUX` is empty. Leave
every other line in the file as it is.

Apply it:

```bash
update-grub
```

#### 8. Reboot

```bash
systemctl reboot
```

Log back in and become root again before the checks:

```bash
su -
```

#### 9. Check Secure Boot

```bash
mokutil --sb-state
```

Expect `SecureBoot enabled`.

```bash
dmesg | grep -i "secure boot"
```

Expect `secureboot: Secure boot enabled`.

#### 10. Check the machine booted through shim

```bash
efibootmgr -v | grep -i shim
```

Expect `\EFI\debian\shimx64.efi`.

#### 11. Check the disk

```bash
lsblk
```

Expect `1G`, `2G`, and `888G`.

```bash
findmnt -no FSTYPE /
```

Expect `xfs`.

#### 12. Check the quota

```bash
findmnt -no OPTIONS /
```

Expect `usrquota` and `prjquota` in the list.

```bash
xfs_quota -x -c state /
```

Expect `Project quota state` with `Accounting: ON` and `Enforcement: ON`.

#### 13. Check the BIOS version

```bash
dmidecode -s bios-version
```

Compare with what you wrote down in Step 1.

**Notes**

- `efi-readvar -v PK` (package `efitools`) reports `no entries` on this machine. That is normal while `Secure Boot Key State` is `Standard`. The firmware keeps its keys internal.
- If step 9 says `SecureBoot disabled`, the `Secure Boot` toggle is Off in the BIOS. Turn it back on under `Security → Secure Boot`.
- The 3rd party CA is a different problem. It does not turn Secure Boot off — it stops the machine booting at all, with `Invalid signature detected`.
- Hibernation does not work while Secure Boot is on. The kernel locks itself down and refuses to write the resume image, because it cannot check that the swap was not modified while the machine was off. Suspend works normally. Turning hibernation on means turning Secure Boot off.
- `/etc/fstab` does not work for the quota. XFS cannot turn quota on at remount, and root is already mounted by then.
- `rootflags` goes in `GRUB_CMDLINE_LINUX`, not `GRUB_CMDLINE_LINUX_DEFAULT`. The plain one applies to every menu entry, including recovery, so the quota stays on there too.
- Docker only needs `pquota`. `uquota` is user quota and is optional.
- The kernel renames both options. `pquota` shows as `prjquota` and `uquota` shows as `usrquota`. Same things.

The installation is done.

## Part 2 — Configuration

### Step 4 — Runtime libraries and Qt applications

Prebuilt applications that ship their own Qt still link against a few system
libraries, and Qt applications need help to match the GNOME theme.

#### 1. Install the missing libraries

```bash
apt install libpcre2-16-0 libdouble-conversion3
```

#### 2. Install the GNOME theme and the Wayland plugin

```bash
apt install qgnomeplatform-qt5 qtwayland5
```

#### 3. Set the Qt environment variables

```bash
nano /etc/environment
```

Add these two lines:

```
QT_QPA_PLATFORM=wayland;xcb
QT_QPA_PLATFORMTHEME=gnome
```

#### 4. Log out and log back in

#### 5. Check the session type

```bash
echo $XDG_SESSION_TYPE
```

Expect `wayland`.

#### 6. Check the variables took effect

```bash
env | grep QT_QPA
```

Expect both lines.

#### 7. Check a prebuilt binary for anything still missing

```bash
LD_LIBRARY_PATH=/path/to/app/usr/lib ldd /path/to/app/binary | grep "not found"
```

No output means nothing is missing.

**Notes**

- The variable is `QT_QPA_PLATFORMTHEME`. `QT_QPA_QPLATFORMTHEME` is not a real variable and is ignored without any error.
- `/etc/environment` is not a shell script. Write `KEY=value` with no `export` and no quotes.
- `wayland;xcb` tries Wayland first and falls back to X11. Plain `wayland` breaks Qt applications in an X11 session, and any application whose bundled Qt has no Wayland plugin.
- Variables set in `/etc/environment` apply at the next login, not to the shell you are in now.
- For Qt 6 applications, also install `qgnomeplatform-qt6`.
- `libpcre2-16-0` provides `libpcre2-16.so.0` and `libdouble-conversion3` provides `libdouble-conversion.so.3`.
- Set `LD_LIBRARY_PATH` to the application's own library directory first, or `ldd` reports the bundled libraries as missing too.
- A program that exits with no message is usually a missing library or a missing graphical session, not a broken program.

### Step 5 — Firmware updates

Lenovo publishes firmware to LVFS, so the BIOS, embedded controller, and
Thunderbolt can all be updated from Linux. No Windows and no USB needed.

#### 1. Install fwupd

```bash
apt install fwupd fwupd-amd64-signed
```

#### 2. Refresh the firmware list

```bash
fwupdmgr refresh --force
```

#### 3. See what the machine has

```bash
fwupdmgr get-devices
```

#### 4. See what is available

```bash
fwupdmgr get-updates
```

#### 5. Apply

```bash
fwupdmgr update
```

#### 6. Reboot to apply

```bash
systemctl reboot
```

#### 7. Check nothing is left

```bash
fwupdmgr get-updates
```

The last line must read `No updates available`. If it does not, repeat from
step 5.

#### 8. Check the new BIOS version

```bash
dmidecode -s bios-version
```

#### 9. Check Secure Boot survived

```bash
mokutil --sb-state
```

Expect `SecureBoot enabled`.

**Notes**

- Plug the charger in before step 5. On battery every device reports `Device requires AC power to be connected` and is skipped without failing, so the update looks like it worked when nothing happened.
- Never power off during a firmware update.
- Firmware is written during the reboot, not by `fwupdmgr update`. Steps 5 to 7 are one round. Repeat the round until step 7 comes back clean.
- `System Firmware` is the BIOS. The other entries are the management engine, the SSD, the camera, the fingerprint reader, and the UEFI revocation list.
- Two headings mean the same thing. `Devices with no available firmware updates` and `Devices with the latest available firmware version` are both fine. Only the last line decides.
- `UEFI dbx` is Microsoft's revocation list. It is a normal update, but step 9 exists to confirm the machine still boots with Secure Boot on afterwards.
- `fwupd-amd64-signed` holds the Debian-signed EFI file. Without it, firmware updates stop working while Secure Boot is on.
- A BIOS update can reset BIOS settings. If step 9 says `SecureBoot disabled`, redo Step 1.
- If step 4 reports nothing to do, the firmware is already current. This machine shipped with `N3QET52W (1.52)`, dated 2026-04-23.

## Part 3 — Terminal configuration

### Step 6 — Bash, tmux, and SSH configuration

Everything is written from scratch. Nothing is cloned or downloaded.

Run step 1 as root. Run every step after it as your own user, not root, or the
configuration lands in `/root` instead of your home directory.

#### 1. Install what the configuration needs

```bash
apt install tmux vim git curl jq tree python3 openssl bash-completion xclip htop
```

#### 2. Create the directories

```bash
mkdir -p ~/linux/bash ~/linux/ssh ~/linux/tmux
```

#### 3. Create `~/linux/bash/bash_profile`

```bash
cat > ~/linux/bash/bash_profile <<'EOF'
# ~/.bash_profile — Linux login shell entry point

if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
```

#### 4. Create `~/linux/bash/bashrc`

```bash
cat > ~/linux/bash/bashrc <<'EOF'
# ~/.bashrc (Linux)

# If not running interactively, bail
case $- in
    *i*) ;;
      *) return;;
esac

# History — full deduplication (ignoredups + erasedups)
HISTCONTROL=ignoredups:erasedups
HISTSIZE=100000
HISTFILESIZE=200000
shopt -s histappend
shopt -s checkwinsize

# PATH extras
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# Editor
export EDITOR=vim
export VISUAL=vim

# Prevent venv from overwriting our custom prompt
export VIRTUAL_ENV_DISABLE_PROMPT=1

# Catppuccin Mocha — badge backgrounds = accent blended 30% into Base #1e1e2e
_OVERLAY='108;112;134'
_TEXT='205;214;244'
_GREEN='166;227;161'
_GREEN_BG='71;89;80'
_RED='243;139;168'
_RED_BG='94;63;83'
_BLUE='137;180;250'
_BLUE_BG='62;75;107'
_MAUVE='203;166;247'
_MAUVE_BG='82;71;106'
_PEACH='250;179;135'
_PEACH_BG='96;75;73'
_LAVENDER='180;190;254'
_LAVENDER_BG='75;78;108'
_TEAL='148;226;213'
_TEAL_BG='65;89;96'
_SKY='137;220;235'
_SKY_BG='62;87;103'
_OVERLAY_BG='53;55;72'
_RST='\[\e[0m\]'

# ▶ is standard Unicode (U+25B6) — no Nerd Font needed, renders in any modern terminal.
_SEP='▶'
_BRANCH=''

_set_prompt() {
    local exit_code=$?
    local sym sym_col local_time utc_time kctx kctx_bg
    local git_branch git_bg git_text user_bg user_fg venv_name
    local git_dirty git_ab git_stash ab_counts ahead behind stash_count
    local line1 prev_bg i
    local -a seg_bg seg_fg seg_text

    local_time=$(date '+%Y-%m-%d %H:%M:%S')
    utc_time=$(date -u '+%Y-%m-%d %H:%M:%S')

    if git -C "$PWD" rev-parse --is-inside-work-tree &>/dev/null; then
        git_branch=$(git -C "$PWD" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$PWD" rev-parse --short HEAD 2>/dev/null)
        git_bg="$_PEACH_BG"

        git_dirty=""
        git -C "$PWD" diff --quiet 2>/dev/null || git_dirty+="*"
        git -C "$PWD" diff --staged --quiet 2>/dev/null || git_dirty+="+"

        git_ab=""
        ab_counts=$(git -C "$PWD" rev-list --left-right --count "HEAD...@{upstream}" 2>/dev/null | awk '{print $1, $2}')
        if [ -n "$ab_counts" ]; then
            ahead="${ab_counts%% *}"
            behind="${ab_counts##* }"
            [ "$ahead" -gt 0 ] && git_ab+=" ⇡${ahead}"
            [ "$behind" -gt 0 ] && git_ab+=" ⇣${behind}"
        fi

        git_stash=""
        stash_count=$(git -C "$PWD" stash list 2>/dev/null | wc -l | awk '{print $1}')
        [ "$stash_count" -gt 0 ] && git_stash=" {${stash_count}}"

        git_text="${_BRANCH:+${_BRANCH} }${git_branch}${git_dirty}${git_ab}${git_stash}"
    else
        git_bg="$_OVERLAY_BG"
        git_text="not git repo"
    fi

    if [ "$(id -u)" -eq 0 ]; then
        sym='#'
        user_bg="$_RED_BG"
        user_fg="$_RED"
    else
        sym='$'
        user_bg="$_GREEN_BG"
        user_fg="$_GREEN"
    fi

    if command -v kubectl &>/dev/null; then
        kctx=$(kubectl config current-context 2>/dev/null)
        if [ -n "$kctx" ]; then
            kctx_bg="$_SKY_BG"
        else
            kctx="disconnected"
            kctx_bg="$_RED_BG"
        fi
    else
        kctx="disconnected"
        kctx_bg="$_RED_BG"
    fi

    if [ $exit_code -eq 0 ]; then
        sym_col="$_GREEN"
    else
        sym_col="$_RED"
    fi

    seg_bg=() seg_fg=() seg_text=()

    if [ -n "$VIRTUAL_ENV" ]; then
        venv_name="${VIRTUAL_ENV_PROMPT:-$(basename "$VIRTUAL_ENV")}"
        seg_bg+=("$_MAUVE_BG");   seg_fg+=("$_TEXT"); seg_text+=(" venv:${venv_name} ")
    else
        seg_bg+=("$_OVERLAY_BG"); seg_fg+=("$_TEXT"); seg_text+=(" venv:inactive ")
    fi
    seg_bg+=("$user_bg");      seg_fg+=("$_TEXT");   seg_text+=(" \u@\h ")
    seg_bg+=("$kctx_bg");      seg_fg+=("$_TEXT");   seg_text+=(" k8s:${kctx} ")
    seg_bg+=("$git_bg");       seg_fg+=("$_TEXT");    seg_text+=(" ${git_text} ")
    seg_bg+=("$_BLUE_BG");     seg_fg+=("$_TEXT");     seg_text+=(" \w ")
    seg_bg+=("$_LAVENDER_BG"); seg_fg+=("$_TEXT"); seg_text+=(" Local ${local_time} ")
    seg_bg+=("$_TEAL_BG");     seg_fg+=("$_TEXT");     seg_text+=(" UTC ${utc_time} ")

    line1="\[\e[38;2;${_OVERLAY}m\]─${_RST} \[\e[38;2;${user_fg}m\][bash]${_RST} "

    prev_bg=""
    for i in "${!seg_bg[@]}"; do
        if [ -n "$prev_bg" ]; then
            line1+="\[\e[48;2;${seg_bg[$i]}m\]\[\e[38;2;${prev_bg}m\]${_SEP}"
        else
            line1+="\[\e[48;2;${seg_bg[$i]}m\]"
        fi
        line1+="\[\e[38;2;${seg_fg[$i]}m\]${seg_text[$i]}"
        prev_bg="${seg_bg[$i]}"
    done
    line1+="\[\e[49m\]\[\e[38;2;${prev_bg}m\]${_SEP}${_RST}"

    PS1="${line1}\n\[\e[38;2;${sym_col}m\]${sym}${_RST} "
}
PROMPT_COMMAND='_set_prompt'

# ls colours — Linux uses --color=auto and LS_COLORS (set by dircolors)
alias ls='ls --color=auto'
command -v dircolors &>/dev/null && eval "$(dircolors -b)"

# bash-completion — package name varies by distro:
#   Debian/Ubuntu: bash-completion   Fedora/RHEL: bash-completion
_bc=""
for _p in /usr/share/bash-completion/bash_completion \
           /etc/bash_completion; do
    [ -r "$_p" ] && { _bc="$_p"; break; }
done
[ -n "$_bc" ] && . "$_bc"
unset _bc _p

# Strip tab-separated descriptions from COMPREPLY (cobra/kubectl/docker output)
_strip_comp_descriptions() {
    local i
    for i in "${!COMPREPLY[@]}"; do
        COMPREPLY[$i]="${COMPREPLY[$i]%%$'\t'*}"
    done
}

# CLI tool completions
_bash_load_completions() {
    type _get_comp_words_by_ref &>/dev/null || return 0

    local tool output comp_fn wrapper_fn
    for tool in kubectl helm flux kind k3d docker; do
        if command -v "$tool" &>/dev/null; then
            output=$("$tool" completion bash 2>/dev/null)
            if [ -n "$output" ]; then
                eval "$output"
                comp_fn=$(complete -p "$tool" 2>/dev/null | sed -n 's/.*-F \([^ ]*\).*/\1/p')
                if [ -n "$comp_fn" ]; then
                    wrapper_fn="_nodesc_${tool}"
                    eval "
${wrapper_fn}() {
    { ${comp_fn} \"\$@\"; } > /dev/null
    _strip_comp_descriptions
}
"
                    complete -F "$wrapper_fn" "$tool"
                fi
            fi
        fi
    done
    command -v kubectl &>/dev/null && complete -o default -F __start_kubectl k
    type _nodesc_docker &>/dev/null && complete -F _nodesc_docker d || true

    local _bcd="/usr/share/bash-completion/completions"
    if [ -r "$_bcd/git" ]; then
        . "$_bcd/git"
        type __git_complete &>/dev/null && __git_complete g __git_main || true
    fi
    [ -r "$_bcd/tmux"    ] && . "$_bcd/tmux"    && complete -F _comp_cmd_tmux  t  2>/dev/null || true
    [ -r "$_bcd/python3" ] && . "$_bcd/python3" && complete -F _comp_cmd_python py 2>/dev/null || true
}
_bash_load_completions
unset -f _bash_load_completions

# Ollama completion
if command -v ollama &>/dev/null; then
    _ollama_bash() {
        local cur prev
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        local subcmds="serve create show run pull push list ps cp rm help"
        if [ "$COMP_CWORD" -eq 1 ]; then
            COMPREPLY=($(compgen -W "$subcmds" -- "$cur"))
            return
        fi
        case "$prev" in
            run|show|cp|rm|push)
                local models
                models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
                COMPREPLY=($(compgen -W "$models" -- "$cur"))
                ;;
        esac
    }
    complete -F _ollama_bash ollama
fi

# Aliases
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# tmux shortcut
alias t='tmux'

# readline — set AFTER all completion loading so nothing can override these
bind 'TAB: menu-complete'
bind '"\e[Z": menu-complete-backward'
bind 'set completion-ignore-case on'
bind 'set mark-symlinked-directories on'
bind 'set colored-stats on'
bind 'set colored-completion-prefix on'
EOF
```

#### 5. Create `~/linux/bash/bash_aliases`

```bash
cat > ~/linux/bash/bash_aliases <<'EOF'
# aliases — sourced by .bashrc
# Linux · DevOps + Data Engineering/Science

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

# Listing — ls --color=auto is set in bashrc; extend it here
alias ll='ls -AlhiF'
alias l='ls -A'
alias la='ls -A'

# General
alias c='clear'
command -v btop &>/dev/null && alias b='btop' || { command -v htop &>/dev/null && alias b='htop'; }
alias reload='exec $SHELL -l'
alias path='echo $PATH | tr ":" "\n"'
alias pubip='curl -s https://ipwho.is/ | jq .'
alias privip="hostname -I | awk '{print \$1}'"
pubkey() {
    local key
    for key in ~/.ssh/id_ed25519.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_rsa.pub; do
        [ -f "$key" ] || continue
        cat "$key"
        echo "[key: $(basename "$key")]" >&2
        return
    done
    echo "No public key found (~/.ssh/id_ed25519.pub, id_ecdsa.pub, id_rsa.pub)" >&2
    return 1
}
alias pubkeys='ls ~/.ssh/*.pub 2>/dev/null | xargs -I{} sh -c "echo \"=== {} ===\"; cat {}"'
alias password='openssl rand -base64 48'

# Editors
alias nano='vim'
alias v='vim'

# Pipe filter — prints output and copies to clipboard if xclip is available;
# on headless servers without X11/xclip it just prints (tee with no sink).
cpy() {
    if command -v xclip &>/dev/null && [ -n "$DISPLAY" ]; then
        tee >(xclip -selection clipboard)
    else
        tee
    fi
}

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -m'
alias gca='git commit --amend --no-edit'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbD='git branch -D'
alias gl='git log --oneline --graph --decorate --all'
alias gll='git log --stat'
alias gd='git diff'
alias gds='git diff --staged'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull'
alias gpr='git pull --rebase'
alias gst='git stash'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gf='git fetch --all --prune'
alias grb='git rebase'
alias grbi='git rebase -i'
alias gcp='git cherry-pick'
alias gtag='git tag'
alias gclean='git clean -fd'
alias gwip='git add -A && git commit -m "wip: checkpoint"'

# Python / venv
alias py='python3'
alias pip='pip3'
alias piv='python3 -m venv .venv'
alias va='source .venv/bin/activate'
alias vd='deactivate'
alias pipi='pip3 install'
alias pipu='pip3 install --upgrade'
alias pipf='pip3 freeze'
alias pipff='pip3 freeze > requirements.txt'
alias pipr='pip3 install -r requirements.txt'
alias pipuu='pip3 list --outdated | awk "NR>2 {print \$1}" | xargs pip3 install --upgrade'

# Jupyter
alias jn='jupyter notebook'
alias jl='jupyter lab'
alias jnb='jupyter nbconvert'

# Docker
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drm='docker rm'
alias drmi='docker rmi'
alias drmf='docker rm -f'
alias dex='docker exec -it'
alias dlogs='docker logs -f'
alias dstop='docker stop'
alias dstart='docker start'
alias dprune='docker system prune -af --volumes'
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dcr='docker compose restart'
alias dcb='docker compose build'

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deployments'
alias kdes='kubectl describe'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdn='kubectl describe node'
alias klogs='kubectl logs -f'
alias kex='kubectl exec -it'
alias kap='kubectl apply -f'
alias kdel='kubectl delete -f'
alias kctx='kubectl config get-contexts'
alias kuse='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'
alias krun='kubectl run --rm -it --image=busybox debug -- sh'

# Network
alias ports='ss -tlnp'

# Filesystem / safety
alias cp='cp -iv'
alias mv='mv -iv'
alias mkdir='mkdir -pv'
alias df='df -h'
alias du='du -sh'
alias dud='du -sh -- *'

# Directory stack
alias pd='pushd'
alias pp='popd'
alias ds='dirs -v'

# Find
alias fd='find . -type d -name'
alias ff='find . -type f -name'

# Size and tree
alias dsize='du -sh -- */ | sort -h'
alias count='ls -1 | wc -l'
alias t2='tree -L 2'
alias t3='tree -L 3'
alias th='tree -L 2 -a -I ".git|.venv|__pycache__|node_modules|*.pyc"'
EOF
```

#### 6. Create `~/linux/ssh/config`

```bash
cat > ~/linux/ssh/config <<'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile ~/.ssh/id_ed25519
    AddKeysToAgent 5m
    Port 22
EOF
```

#### 7. Create `~/linux/tmux/tmux.conf`

```bash
cat > ~/linux/tmux/tmux.conf <<'EOF'
# ~/.tmux.conf

# Windows and panes index from 1
set -g base-index 1
setw -g pane-base-index 1

# Large scrollback (1 MiB lines)
set -g history-limit 1048576

# No mouse
set -g mouse off

# Status bar — Catppuccin Mocha
set -g status-style          "bg=#181825,fg=#a6adc8"
set -g status-position       bottom
set -g status-interval       5
set -g status-left-length    30
set -g status-right-length   40

# Session name badge
set -g status-left  "#[bg=#4e4364,fg=#cdd6f4,bold] #S #[bg=#181825,fg=#4e4364] "

# Right: hostname only — prompt already shows time
set -g status-right "#[fg=#89b4fa] #H "

# Inactive window tab
setw -g window-status-style          "bg=#181825,fg=#7f849c"
setw -g window-status-format         " #I:#W "

# Active window tab — shows Z in Red when pane is zoomed
setw -g window-status-current-style  "bg=#43554a,fg=#cdd6f4,bold"
setw -g window-status-current-format " #I:#W#{?window_zoomed_flag, #[fg=#f38ba8]Z#[fg=#cdd6f4],} "

# No gap between window tabs
setw -g window-status-separator ""

# Pane borders
set -g pane-border-style        "fg=#313244"
set -g pane-active-border-style "fg=#cba6f7"

# Command/message bar — exactly match the Mantle status-bar background and
# fill its entire width, so confirmation prompts (for example Ctrl+b x) are
# a full-width lower bar rather than a small overlay.
set -g message-style         "bg=#181825,fg=#f9e2af,bold,fill=#181825,width=100%,align=left"
set -g message-command-style "bg=#181825,fg=#89b4fa,bold,fill=#181825,width=100%,align=left"

# Copy mode highlight
setw -g mode-style "bg=#45475a,fg=#cdd6f4"

# Window navigation — Shift+Left/Right, no prefix
bind-key -n S-Left  previous-window
bind-key -n S-Right next-window

# Pane navigation — Alt+WASD, no prefix
bind-key -n M-w select-pane -U
bind-key -n M-a select-pane -L
bind-key -n M-s select-pane -D
bind-key -n M-d select-pane -R

# Pane navigation — Ctrl+b prefix fallback (vim style + arrows)
bind-key h select-pane -L
bind-key j select-pane -D
bind-key k select-pane -U
bind-key l select-pane -R
bind-key Left  select-pane -L
bind-key Right select-pane -R
bind-key Up    select-pane -U
bind-key Down  select-pane -D

# Pane creation — Ctrl+b " creates a stacked pane, then equalizes all pane
# heights in the window. This keeps repeated horizontal splits aligned.
bind-key '"' split-window -v \; select-layout even-vertical

# Pane removal — keep the remaining stacked panes at equal heights after a
# confirmed Ctrl+b x action.
bind-key x confirm-before -p "kill-pane #P? (y/n)" "kill-pane \; select-layout even-vertical"

# Synchronize all panes — borders turn Red while sync is on
bind-key @ if -F '#{pane_synchronized}' \
    'setw synchronize-panes off; set-window-option pane-border-style "fg=#313244"; set-window-option pane-active-border-style "fg=#cba6f7"' \
    'setw synchronize-panes on; set-window-option pane-border-style "fg=#f38ba8"; set-window-option pane-active-border-style "fg=#f38ba8"'

# Scrollback — PgUp/PgDown enters copy-mode
bind-key -n PPage copy-mode -u
bind-key    PPage copy-mode -u
bind-key -T copy-mode PPage  send -X page-up
bind-key -T copy-mode NPage  send -X page-down
bind-key -T copy-mode Escape send -X cancel
bind-key -T copy-mode q      send -X cancel

# Layout shortcuts — Alt+1–7
bind-key -n M-1 select-layout even-horizontal
bind-key -n M-2 select-layout even-vertical
bind-key -n M-3 select-layout main-horizontal
bind-key -n M-4 select-layout main-vertical
bind-key -n M-5 select-layout tiled
bind-key -n M-6 next-layout
bind-key -n M-7 previous-layout

# Nested tmux (SSH → remote tmux) — F12 toggles passthrough mode
# ON  → local tmux handles all keys normally
# OFF → local tmux ignores all keys; everything goes to the remote tmux
#       status bar dims to grey so you always know which mode you're in
bind-key -n F12 \
    set prefix None \;\
    set key-table off \;\
    set status-style "bg=#181825,fg=#585b70" \;\
    set status-left "#[fg=#585b70] #S [passthrough]  " \;\
    refresh-client -S

bind-key -T off F12 \
    set -u prefix \;\
    set -u key-table \;\
    set -u status-style \;\
    set -u status-left \;\
    refresh-client -S

# Forward Meta shortcuts explicitly while in passthrough mode. This lets a
# further nested tmux receive its own Alt+W/A/S/D and Alt+1–7 bindings.
bind-key -T off M-w send-keys M-w
bind-key -T off M-a send-keys M-a
bind-key -T off M-s send-keys M-s
bind-key -T off M-d send-keys M-d
bind-key -T off M-1 send-keys M-1
bind-key -T off M-2 send-keys M-2
bind-key -T off M-3 send-keys M-3
bind-key -T off M-4 send-keys M-4
bind-key -T off M-5 send-keys M-5
bind-key -T off M-6 send-keys M-6
bind-key -T off M-7 send-keys M-7
EOF
```

#### 8. Create `~/linux/install.sh`

```bash
cat > ~/linux/install.sh <<'EOF'
#!/usr/bin/env bash
# linux/install.sh — idempotent dotfiles installer (Linux only)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(uname -s)" = "Linux" ] || { echo "Linux only." >&2; exit 1; }

_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }
_warn() { printf '\033[33m⚠ %s\033[0m\n' "$*"; }
_skip() { printf '\033[90m⊘ %s\033[0m\n' "$*"; }
_hdr()  { printf '\n%s\n' "$*"; }

cp_file() { mkdir -p "$(dirname "$2")"; cp "$1" "$2"; _ok "applied: $2"; }
sudo_cp() { sudo mkdir -p "$(dirname "$2")"; sudo cp "$1" "$2"; _ok "applied (root): $2"; }

# Detect package manager (Debian/Ubuntu or Red Hat/Fedora only)
_pkg_cmd() {
    local pkgs="$1"
    if command -v apt-get &>/dev/null; then
        echo "sudo apt-get install -y $pkgs"
    elif command -v dnf &>/dev/null; then
        echo "sudo dnf install -y $pkgs"
    elif command -v yum &>/dev/null; then
        echo "sudo yum install -y $pkgs"
    else
        _warn "unsupported distro — install manually: $pkgs"
        echo ""
    fi
}

_check_prereqs() {
    _hdr "prerequisites"
    local missing=() cmd

    for cmd in bash tmux vim git curl jq tree python3 openssl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    local bc_ok=false
    { [ -r /usr/share/bash-completion/bash_completion ] || \
      [ -r /etc/bash_completion ]; } && bc_ok=true

    if [ ${#missing[@]} -eq 0 ] && $bc_ok; then
        _ok "all required packages present"
        return
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        _warn "missing: ${missing[*]}"
        local cmd; cmd="$(_pkg_cmd "${missing[*]}")"
        [ -n "$cmd" ] && printf '  Run: %s\n' "$cmd"
    fi
    if ! $bc_ok; then
        _warn "bash-completion not found (Tab completions will not load)"
        local cmd; cmd="$(_pkg_cmd "bash-completion")"
        [ -n "$cmd" ] && printf '  Run: %s\n' "$cmd"
    fi
}

_check_prereqs

printf '\nConfigure root user as well? [y/N]: '
read -r _ans
HAS_SUDO=false
if [[ "$_ans" =~ ^[Yy] ]]; then
    if sudo -v; then HAS_SUDO=true; _ok "sudo granted"
    else _warn "sudo failed — root skipped"
    fi
else
    _skip "root configuration"
fi

_hdr "bash"
cp_file "$REPO/bash/bash_profile" "$HOME/.bash_profile"
cp_file "$REPO/bash/bashrc"       "$HOME/.bashrc"
cp_file "$REPO/bash/bash_aliases" "$HOME/.bash_aliases"
if [ "$HAS_SUDO" = true ]; then
    sudo_cp "$REPO/bash/bash_profile" /root/.bash_profile
    sudo_cp "$REPO/bash/bashrc"       /root/.bashrc
    sudo_cp "$REPO/bash/bash_aliases" /root/.bash_aliases
fi

_hdr "tmux"
cp_file "$REPO/tmux/tmux.conf" "$HOME/.tmux.conf"
[ "$HAS_SUDO" = true ] && sudo_cp "$REPO/tmux/tmux.conf" /root/.tmux.conf || true

_hdr "ssh"
_upsert_ssh() {
    local config="$1"
    grep -qF 'AddKeysToAgent 5m' "$config" 2>/dev/null && return 0
    if grep -qF 'StrictHostKeyChecking no' "$config" 2>/dev/null; then
        if command -v python3 &>/dev/null; then
            local py
            py=$(mktemp)
            cat > "$py" << 'PYEOF'
import sys, re
path = sys.argv[1]
try: text = open(path).read()
except FileNotFoundError: text = ''
text = re.sub(r'\nHost \*\n(?:[ \t][^\n]*\n?)*', '', '\n' + text).strip()
open(path, 'w').write(text + '\n' if text else '')
PYEOF
            python3 "$py" "$config"
            rm -f "$py"
        else
            _warn "python3 not found — skipping SSH dedup (stale Host * block left in place)"
        fi
    fi
    printf '\n' >> "$config"
    cat "$REPO/ssh/config" >> "$config"
    return 1
}

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
if _upsert_ssh "$HOME/.ssh/config"; then
    _ok "SSH already present in ~/.ssh/config"
else
    chmod 600 "$HOME/.ssh/config"
    _ok "SSH applied to ~/.ssh/config"
fi

if [ "$HAS_SUDO" = true ]; then
    sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh
    _rtmp=$(mktemp)
    sudo cat /root/.ssh/config 2>/dev/null > "$_rtmp" || true
    chmod 600 "$_rtmp"
    if _upsert_ssh "$_rtmp"; then
        _ok "SSH already present in /root/.ssh/config"
    else
        sudo cp "$_rtmp" /root/.ssh/config
        sudo chmod 600 /root/.ssh/config
        _ok "SSH applied to /root/.ssh/config"
    fi
    rm -f "$_rtmp"
fi

_hdr "misc"
cp_file "$REPO/hushlogin" "$HOME/.hushlogin"

_hdr "default shell → bash"
BASH_BIN="$(command -v bash)"
if [ -z "$BASH_BIN" ]; then
    _warn "bash not found in PATH — install it first"
else
    # chsh requires the shell to be listed in /etc/shells
    if ! grep -qxF "$BASH_BIN" /etc/shells 2>/dev/null; then
        if [ "$HAS_SUDO" = true ]; then
            echo "$BASH_BIN" | sudo tee -a /etc/shells > /dev/null
            _ok "registered $BASH_BIN in /etc/shells"
        else
            _warn "$BASH_BIN not in /etc/shells — chsh may fail (add it with sudo)"
        fi
    fi
    if chsh -s "$BASH_BIN" "$USER" 2>/dev/null; then
        _ok "$USER: shell → $BASH_BIN"
    elif command -v usermod &>/dev/null && [ "$HAS_SUDO" = true ]; then
        sudo usermod -s "$BASH_BIN" "$USER"
        _ok "$USER: shell → $BASH_BIN (via usermod)"
    else
        _warn "Could not set default shell — run manually: chsh -s $BASH_BIN"
    fi
    if [ "$HAS_SUDO" = true ]; then
        if chsh -s "$BASH_BIN" root 2>/dev/null || \
           { command -v usermod &>/dev/null && sudo usermod -s "$BASH_BIN" root; }; then
            _ok "root: shell → $BASH_BIN"
        else
            _warn "Could not set root shell"
        fi
    fi
fi

printf '\n\033[32m✔ Done.\033[0m Log out and back in for the shell change to take effect.\n'
printf '  Reload now: exec bash\n'
EOF
```

#### 9. Create `~/linux/hushlogin`

```bash
touch ~/linux/hushlogin
```

#### 10. Make the installer executable

```bash
chmod +x ~/linux/install.sh
```

#### 11. Run it

```bash
~/linux/install.sh
```

#### 12. Reload the shell

```bash
exec bash
```

**Notes**

- The `<<'EOF'` quoting matters. With the quotes the shell writes the file literally. Without them it would expand every `$` and backtick and destroy the prompt code.
- The installer asks whether to configure `root` as well. Answer `y` to get the same prompt, aliases, and tmux settings under `su`.
- The installer copies to `~/.bashrc`, `~/.bash_aliases`, `~/.bash_profile`, `~/.tmux.conf`, and `~/.hushlogin`, appends the SSH block to `~/.ssh/config`, and sets bash as the login shell.
- It is safe to run more than once. The SSH block is replaced rather than duplicated.
- `~/linux` is kept after the install. The installer reads from it, so keep it if you want to re-run it later.
- The SSH block sets `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null` for every host. This turns off host key checking, so a machine impersonating a server you connect to will not be detected. Remove those two lines from `~/linux/ssh/config` before step 6 if you do not want that.
- The prompt needs a terminal with true colour and Unicode. GNOME Terminal has both.
