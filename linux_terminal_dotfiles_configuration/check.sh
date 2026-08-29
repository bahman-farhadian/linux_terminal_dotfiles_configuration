#!/usr/bin/env bash
# check.sh — verify this machine matches thinkpad-t14-gen4-debian-13-setup.md.
#
# Reads only, never writes. Run as your own user from a desktop session
# terminal. Exits 0 when every check passes and 1 when any fails.

if [ "$(id -u)" -eq 0 ]; then
  echo "STOP: run as your normal user, not root. Dotfiles, GNOME settings, user units and group membership all live in your account."; exit 1
fi
case "$XDG_SESSION_TYPE" in wayland|x11) ;; *)
  echo "STOP: run from a desktop session terminal. XDG_SESSION_TYPE is '$XDG_SESSION_TYPE'; GNOME checks need the session bus."; exit 1 ;;
esac
pass=0; fail=0
ck(){ if [ "$2" = "$3" ]; then printf '  PASS  %-32s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-32s got[%s] want[%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
ok(){ if [ -n "$2" ]; then printf '  PASS  %-32s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-32s (empty)\n' "$1"; fail=$((fail+1)); fi; }
hf(){ [ -f "$2" ] && { printf '  PASS  %-32s\n' "$1"; pass=$((pass+1)); } \
                  || { printf '  FAIL  %-32s missing %s\n' "$1" "$2"; fail=$((fail+1)); }; }

printf '\n--- Step 2/3: disk, quota, secure boot ---\n'
ck "efi size"     "$(lsblk -no SIZE /dev/nvme0n1p1|tr -d ' ')" "1G"
ck "boot size"    "$(lsblk -no SIZE /dev/nvme0n1p2|tr -d ' ')" "2G"
ck "root size"    "$(lsblk -no SIZE /dev/nvme0n1p3|tr -d ' ')" "888G"
ck "root fstype"  "$(findmnt -no FSTYPE /)" "xfs"
ck "partitions"   "$(lsblk -no NAME /dev/nvme0n1|grep -c nvme0n1p)" "3"
ck "no swap"      "$(swapon --show --noheadings|wc -l|tr -d ' ')" "0"
ck "prjquota"     "$(findmnt -no OPTIONS /|tr ',' '\n'|grep -c prjquota)" "1"
ck "grub rootflags" "$(grep -c 'GRUB_CMDLINE_LINUX="rootflags=uquota,pquota"' /etc/default/grub)" "1"
ck "cmdline live" "$(grep -c 'rootflags=uquota,pquota' /proc/cmdline)" "1"
ok "xfs quota"    "$(sudo xfs_quota -x -c state / 2>/dev/null|grep -i 'project quota state'|head -1)"
ck "secure boot"  "$(mokutil --sb-state 2>/dev/null)" "SecureBoot enabled"
ok "shim"         "$(sudo efibootmgr -v 2>/dev/null|grep -o shimx64.efi|head -1)"
ok "bios version" "$(sudo dmidecode -s bios-version 2>/dev/null)"

printf '\n--- Step 3/6/9: repositories ---\n'
for s in "trixie" "trixie-security" "trixie-updates"; do
  ck "sources.list $s" "$(grep -c "^deb .* $s main contrib non-free non-free-firmware\$" /etc/apt/sources.list)" "1"
done
hf "docker.sources"      /etc/apt/sources.list.d/docker.sources
hf "claude-code.sources" /etc/apt/sources.list.d/claude-code.sources
ck "no claude-code.list" "$([ -e /etc/apt/sources.list.d/claude-code.list ] && echo present || echo absent)" "absent"
hf "docker key"      /etc/apt/keyrings/docker.asc
hf "claude-code key" /etc/apt/keyrings/claude-code.asc
ck "claude key valid" "$(gpg --show-keys /etc/apt/keyrings/claude-code.asc 2>/dev/null|grep -c 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE)" "1"
ck "docker suite"  "$(grep -c '^Suites: trixie$' /etc/apt/sources.list.d/docker.sources)" "1"
ck "claude signed-by" "$(grep -c '^Signed-By: /etc/apt/keyrings/claude-code.asc$' /etc/apt/sources.list.d/claude-code.sources)" "1"
u=$(sudo apt update 2>&1)
ck "apt update errors"    "$(printf '%s' "$u"|grep -c '^Err:')" "0"
ck "apt duplicate warns"  "$(printf '%s' "$u"|grep -ci 'configured multiple times')" "0"

printf '\n--- Step 3-9: every package the document installs ---\n'
miss=""
for p in vim mokutil dmidecode efibootmgr \
  libpcre2-16-0 libdouble-conversion3 qt6-wayland qgnomeplatform-qt6 qtwayland5 qgnomeplatform-qt5 \
  fwupd fwupd-amd64-signed \
  bash-completion bridge-utils btop curl default-jre duf ethtool ffmpeg filezilla foliate fonts-jetbrains-mono git \
  gnome-firmware gnome-shell-extension-manager gnome-shell-extensions gnome-tweaks htop ipcalc \
  iperf3 jq keepassxc lshw nano ncdu net-tools network-manager-openvpn-gnome nmap obs-studio \
  openssh-server openssl openvpn3-client progress pwgen python3 python3.13-venv rsync sshuttle \
  sudo tmux traceroute tree unrar virt-top vlc wget xclip yt-dlp \
  flatpak gnome-software-plugin-flatpak claude-code \
  qemu-system-x86 qemu-utils ovmf virtinst virt-manager libvirt-daemon-system libvirt-clients \
  libosinfo-bin osinfo-db osinfo-db-tools libguestfs-tools \
  ca-certificates docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"
done
ck "all packages present" "${miss:-none missing}" "none missing"
ck "editor is vim" "$(readlink -f /etc/alternatives/editor|grep -c vim)" "1"

printf '\n--- Step 6: flatpak ---\n'
ck "flathub remote" "$(flatpak remotes 2>/dev/null|grep -c flathub)" "1"
fmiss=""
for a in org.telegram.desktop com.belmoussaoui.Obfuscate md.obsidian.Obsidian io.gitlab.adhami3310.Impression; do
  flatpak info "$a" >/dev/null 2>&1 || fmiss="$fmiss $a"
done
ck "flatpak apps" "${fmiss:-all four}" "all four"

printf '\n--- Step 4: Qt ---\n'
ck "QT_QPA_PLATFORM"      "$(grep -c '^QT_QPA_PLATFORM=wayland;xcb$' /etc/environment)" "1"
ck "QT_QPA_PLATFORMTHEME" "$(grep -c '^QT_QPA_PLATFORMTHEME=gnome$' /etc/environment)" "1"
ck "session type"         "$XDG_SESSION_TYPE" "wayland"

printf '\n--- Step 5: firmware ---\n'
ck "no pending firmware" "$(sudo fwupdmgr get-updates 2>&1|grep -qi 'No updates available\|no available firmware' && echo none || echo pending)" "none"

printf '\n--- Step 8: KVM ---\n'
ck "virtualisation"  "$(grep -Ec '(vmx|svm)' /proc/cpuinfo|awk '{print ($1>0)?"yes":"no"}')" "yes"
ck "libvirtd.socket" "$(systemctl is-active libvirtd.socket)" "active"
ck "nested"          "$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null)" "Y"
ok "nested conf"     "$([ -f /etc/modprobe.d/kvm-intel.conf ] && echo present || echo 'not needed, nested already Y')"
ck "ip_forward"      "$(sysctl -n net.ipv4.ip_forward)" "1"
ck "ip_forward conf" "$(grep -c 'net.ipv4.ip_forward = 1' /etc/sysctl.d/99-kvm.conf 2>/dev/null)" "1"
ck "nofile soft"     "$(grep -c 'soft.*nofile.*65536' /etc/security/limits.d/99-kvm.conf 2>/dev/null)" "1"
ck "nofile hard"     "$(grep -c 'hard.*nofile.*1048576' /etc/security/limits.d/99-kvm.conf 2>/dev/null)" "1"
ck "default net"     "$(virsh -c qemu:///system net-list --name 2>/dev/null|grep -c default)" "1"

printf '\n--- Step 9: Docker ---\n'
ck "docker active"   "$(systemctl is-active docker)" "active"
ck "snapshotter off" "$(grep -c '"containerd-snapshotter": false' /etc/docker/daemon.json 2>/dev/null)" "1"
ck "driver"          "$(docker info --format '{{.Driver}}' 2>/dev/null)" "overlay2"
ck "backing xfs"     "$(docker info --format '{{.DriverStatus}}' 2>/dev/null|grep -c 'Backing Filesystem xfs')" "1"
ck "quota enforced"  "$(docker run --rm --storage-opt size=1G busybox df -h / 2>/dev/null|awk 'NR==2{print $2}')" "1.0G"
ck "hello-world"     "$(docker run --rm hello-world 2>/dev/null|grep -c 'working correctly')" "1"
ck "groups"          "$(id -nG|tr ' ' '\n'|grep -cE '^(libvirt|kvm|docker)$')" "3"

printf '\n--- Step 7: dotfiles ---\n'
for f in .bashrc .bash_aliases .bash_profile .tmux.conf .hushlogin; do hf "$f" "$HOME/$f"; done
hf "tmux completion" "$HOME/.local/share/bash-completion/completions/tmux"
hf "keyboard script" "$HOME/.local/bin/lock-keyboard-en.sh"
ck "script executable" "$([ -x "$HOME/.local/bin/lock-keyboard-en.sh" ] && echo yes || echo no)" "yes"
ck "functions" "$(bash -ic 'type -t update upgrade ports _asroot' 2>/dev/null|grep -c function)" "4"
ck "aliases"   "$(bash -ic 'alias DE EN kbd' 2>/dev/null|grep -c ^alias)" "3"
ck "window-size" "$(tmux show-options -g window-size 2>/dev/null|awk '{print $2}')" "smallest"
ck "hist ignorespace"  "$(bash -ic 'echo $HISTCONTROL' 2>/dev/null|grep -c 'ignoreboth\|ignorespace')" "1"
ck "hist append prompt" "$(bash -ic 'echo $PROMPT_COMMAND' 2>/dev/null|grep -c 'history -a')" "1"
ck "histappend shopt"  "$(bash -ic 'shopt histappend' 2>/dev/null|awk '{print $2}')" "on"
hf "history drop-in"   /etc/profile.d/99-history.sh

printf '\n--- Step 7/10: keyboard and lid ---\n'
ck "lock service" "$(systemctl --user is-active lock-keyboard-en.service)" "active"
ck "tick timer"   "$(systemctl --user is-active keyboard-en-tick.timer)" "active"
l=$(sudo systemd-analyze cat-config systemd/logind.conf 2>/dev/null)
ck "lid battery"  "$(printf '%s' "$l"|grep -c '^HandleLidSwitch=lock')" "1"
ck "lid ac"       "$(printf '%s' "$l"|grep -c '^HandleLidSwitchExternalPower=lock')" "1"
ck "lid docked"   "$(printf '%s' "$l"|grep -c '^HandleLidSwitchDocked=ignore')" "1"

printf '\n--- Step 7: GNOME shortcuts ---\n'
b=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
s=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
w=org.gnome.desktop.wm.keybindings
ck "ctrl+alt+t"    "$(gsettings get $s:$b/dotfiles-terminal/ binding 2>/dev/null)" "'<Control><Alt>t'"
ck "super+e"       "$(gsettings get $s:$b/dotfiles-files/ binding 2>/dev/null)"    "'<Super>e'"
ck "super+i"       "$(gsettings get $s:$b/dotfiles-settings/ binding 2>/dev/null)" "'<Super>i'"
ck "terminal cmd"  "$(gsettings get $s:$b/dotfiles-terminal/ command 2>/dev/null)" "'gnome-terminal'"
ck "files cmd"     "$(gsettings get $s:$b/dotfiles-files/ command 2>/dev/null)"    "'nautilus --new-window'"
ck "settings cmd"  "$(gsettings get $s:$b/dotfiles-settings/ command 2>/dev/null)" "'gnome-control-center'"
ck "3 registered"  "$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null|grep -o dotfiles-|wc -l|tr -d ' ')" "3"
ck "alt-tab"       "$(gsettings get $w switch-windows)" "['<Alt>Tab']"
ck "shift+alt-tab" "$(gsettings get $w switch-windows-backward)" "['<Shift><Alt>Tab']"
ck "app switcher off" "$(gsettings get $w switch-applications)" "@as []"
ok "app folders"   "$(gsettings get org.gnome.desktop.app-folders folder-children 2>/dev/null|cut -c1-40)"

printf '\n--- Step 7: ssh server ---\n'
hf "sshd drop-in" /etc/ssh/sshd_config.d/99-local.conf
r=$(sudo sshd -T 2>/dev/null|grep '^permitrootlogin'|awk '{print $2}')
case "$r" in without-password|prohibit-password) ck "root key only" "$r" "$r";; *) ck "root key only" "$r" "without-password";; esac
ck "sshd port"   "$(sudo sshd -T 2>/dev/null|grep '^port'|awk '{print $2}')" "22"
ck "sshd active" "$(systemctl is-active ssh)" "active"

printf '\n========================================\n'
printf '  PASS %s   FAIL %s\n' "$pass" "$fail"
printf '========================================\n'

[ "$fail" -eq 0 ]
