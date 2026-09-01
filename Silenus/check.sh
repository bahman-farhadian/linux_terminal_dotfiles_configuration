#!/usr/bin/env bash
# check.sh — verify this machine matches Silenus.md. Silenus only: the disk
# layout, GNOME and desktop-session checks do not apply to Dionysus.
#
# Reads only, never writes. Run as your own user from a desktop session
# terminal. Exits 0 when every check passes and 1 when any fails.

if [ "$(id -u)" -eq 0 ]; then
  echo "STOP: run as your normal user, not root. Dotfiles, GNOME settings, user units and group membership all live in your account."; exit 1
fi
case "$XDG_SESSION_TYPE" in wayland|x11) ;; *)
  echo "STOP: run from a desktop session terminal. XDG_SESSION_TYPE is '$XDG_SESSION_TYPE'; GNOME checks need the session bus."; exit 1 ;;
esac
pass=0; fail=0; skip=0; failed=""; skipped=""
_note(){ failed="$failed  - $1\n"; }
# na() is for a check that cannot be run here rather than one that failed —
# something the document makes conditional, or that depends on hardware being
# attached. It says so, says what to do about it, and does not count as a
# failure, because a script that cries wolf gets ignored.
na(){ printf '  N/A   %-32s %s\n' "$1" "$2"; skip=$((skip+1)); skipped="$skipped  - $1: $2\n"; }
ck(){ if [ "$2" = "$3" ]; then printf '  PASS  %-32s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-32s got[%s] want[%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); _note "$1: got [$2], wanted [$3]"; fi; }
ok(){ if [ -n "$2" ]; then printf '  PASS  %-32s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-32s (empty)\n' "$1"; fail=$((fail+1)); _note "$1: returned nothing"; fi; }
hf(){ [ -f "$2" ] && { printf '  PASS  %-32s\n' "$1"; pass=$((pass+1)); } \
                  || { printf '  FAIL  %-32s missing %s\n' "$1" "$2"; fail=$((fail+1)); _note "$1: $2 is missing"; }; }

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
ck "quiet in grub"  "$(grep -c '^GRUB_CMDLINE_LINUX_DEFAULT=.*quiet' /etc/default/grub)" "1"
ck "quiet live"     "$(grep -c 'quiet' /proc/cmdline)" "1"
ok "xfs quota"    "$(sudo xfs_quota -x -c state / 2>/dev/null|grep -i 'project quota state'|head -1)"
ck "secure boot"  "$(mokutil --sb-state 2>/dev/null)" "SecureBoot enabled"
_efi=$(sudo efibootmgr -v 2>/dev/null); _cur=$(printf '%s' "$_efi"|awk '/^BootCurrent:/{print $2}')
ok "booted from"  "$(printf '%s' "$_efi"|grep -i "^Boot$_cur"|head -1|cut -c1-58)"
ck "shim in use"  "$(printf '%s' "$_efi"|grep -ci shim|awk '{print ($1>0)?"yes":"no"}')" "yes"
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
  iperf3 jq keepassxc lshw make nano ncdu net-tools network-manager-openvpn-gnome nmap obs-studio \
  openssh-server openssl openvpn3-client progress pwgen python3 python3.13-venv remmina remmina-plugin-rdp rsync sshuttle \
  sudo tmux traceroute tree unrar virt-top vlc wget xclip yt-dlp \
  flatpak gnome-software-plugin-flatpak claude-code \
  qemu-system-x86 qemu-utils ovmf virtinst virt-manager libvirt-daemon-system libvirt-clients \
  libosinfo-bin osinfo-db osinfo-db-tools libguestfs-tools cloud-image-utils acl util-linux \
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
# Answering ARP for the guest subnet is what lets a peer route here over WiFi
# with no gateway, so neither end has to know this laptop's current address.
ck "proxy_arp"       "$(sysctl -n net.ipv4.conf.wlp0s20f3.proxy_arp 2>/dev/null)" "1"
ck "proxy_arp conf"  "$(grep -c 'net.ipv4.conf.wlp0s20f3.proxy_arp = 1' /etc/sysctl.d/99-kvm.conf 2>/dev/null)" "1"
ck "nofile soft"     "$(grep -c 'soft.*nofile.*65536' /etc/security/limits.d/99-kvm.conf 2>/dev/null)" "1"
ck "nofile hard"     "$(grep -c 'hard.*nofile.*1048576' /etc/security/limits.d/99-kvm.conf 2>/dev/null)" "1"
ck "no default net"  "$(virsh -c qemu:///system net-list --all --name 2>/dev/null|grep -cx default)" "0"
ck "static_network_24" "$(virsh -c qemu:///system net-list --name 2>/dev/null|grep -cx static_network_24)" "1"
ck "net autostart"   "$(virsh -c qemu:///system net-info static_network_24 2>/dev/null|awk '/^Autostart/{print $2}')" "yes"
ck "virbr1 address"  "$(ip -4 -br addr show virbr1 2>/dev/null|awk '{print $3}')" "192.168.24.1/24"

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
if [ -e /etc/dotfiles-root-configured ]; then
  ck "tmux completion (root)" "$(sudo test -r /root/.local/share/bash-completion/completions/tmux && echo yes || echo no)" "yes"
else
  na "tmux completion (root)" "root is not managed on this host; ./install.sh --root adds it"
fi
hf "keyboard script" "$HOME/.local/bin/lock-keyboard-en.sh"
ck "script executable" "$([ -x "$HOME/.local/bin/lock-keyboard-en.sh" ] && echo yes || echo no)" "yes"
ck "functions" "$(bash -ic 'type -t update upgrade ports _asroot' 2>/dev/null|grep -c function)" "4"
ck "aliases"   "$(bash -ic 'alias DE EN kbd' 2>/dev/null|grep -c ^alias)" "3"
ck "window-size" "$(tmux show-options -g window-size 2>/dev/null|awk '{print $2}')" "smallest"
ck "gtk3 prefers dark" "$(grep -c '^gtk-application-prefer-dark-theme=1' "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null)" "1"
ck "hist ignorespace"  "$(bash -ic 'echo $HISTCONTROL' 2>/dev/null|grep -c 'ignoreboth\|ignorespace')" "1"
ck "hist append prompt" "$(bash -ic 'echo $PROMPT_COMMAND' 2>/dev/null|grep -c 'history -a')" "1"
ck "histappend shopt"  "$(bash -ic 'shopt histappend' 2>/dev/null|awk '{print $2}')" "on"
hf "history drop-in"   /etc/profile.d/99-history.sh
hf "banner file"     /etc/ssh/banner.txt
ck "banner content"  "$(grep -c 'B A H M A N' /etc/ssh/banner.txt 2>/dev/null)" "1"
# What matters is that sshd serves it, not that the file exists. sshd -T prints
# the effective configuration, so this catches a drop-in that was written but
# never reloaded.
ck "sshd serves banner" "$(sudo sshd -T 2>/dev/null|awk '/^banner /{print $2}')" "/etc/ssh/banner.txt"
ck "motd emptied"    "$(wc -c < /etc/motd 2>/dev/null|tr -d ' ')" "0"
ck "no kernel line"  "$([ -x /etc/update-motd.d/10-uname ] && echo executable || echo off)" "off"

printf '\n--- Step 7: ssh client config ---\n'
# The block has to exist and has to be last: ssh takes the first value it finds
# for each keyword, so a Host * section above the specific hosts overrides them.
sc="$HOME/.ssh/config"
ck "ssh managed block" "$(grep -c '^# >>> dotfiles managed block >>>$' "$sc" 2>/dev/null)" "1"
ck "block is last"     "$(awk '/^# >>> dotfiles managed block >>>/{s=NR} /^Host /{l=NR} END{print (s&&l>s)?"yes":"no"}' "$sc" 2>/dev/null)" "yes"

printf '\n--- Step 13: point-to-point link to Dionysus ---\n'
# Configuration, not live state: this is a laptop and the cable is often out.
ck "p2p profile"      "$(nmcli -g connection.id connection show Dionysus 2>/dev/null)" "Dionysus"
ck "p2p interface"    "$(nmcli -g connection.interface-name connection show Dionysus 2>/dev/null)" "enp0s31f6"
ck "p2p address"      "$(nmcli -g ipv4.addresses connection show Dionysus 2>/dev/null)" "192.168.124.2/30"
ck "p2p never-default" "$(nmcli -g ipv4.never-default connection show Dionysus 2>/dev/null)" "yes"
ck "guest route cable" "$(nmcli -g ipv4.routes connection show Dionysus 2>/dev/null|grep -c '192.168.32.0/24 192.168.124.1 100')" "1"
# Everything above reads the stored profile, which proves the configuration
# survives. This asks the kernel what it would actually do, which is a
# different question and the one a reboot answers.
if [ "$(cat /sys/class/net/enp0s31f6/carrier 2>/dev/null)" = "1" ]; then
  ck "kernel routes via cable" "$(ip -4 route get 192.168.32.10 2>/dev/null|grep -c 'via 192.168.124.1 dev enp0s31f6')" "1"
  ck "p2p installs no default" "$(ip -4 route show default|grep -c 'dev enp0s31f6')" "0"
else
  na "kernel routes via cable" "no cable in enp0s31f6. With it plugged in, ip -4 route get 192.168.32.10 must answer via 192.168.124.1"
  ck "kernel routes via LAN"  "$(ip -4 route get 192.168.32.10 2>/dev/null|grep -c 'via 192.168.8.3')" "1"
fi
ck "guest route fallback" "$(nmcli -t -g NAME connection show|while IFS= read -r c; do nmcli -g ipv4.routes connection show "$c" 2>/dev/null; done|grep -c '192.168.32.0/24 192.168.8.3 200')" "1"
if nmcli -g connection.id connection show Hephaestus >/dev/null 2>&1; then
  ck "hephaestus profile" "$(nmcli -g connection.id connection show Hephaestus 2>/dev/null)" "Hephaestus"
  ck "hephaestus address" "$(nmcli -g ipv4.addresses connection show Hephaestus 2>/dev/null)" "192.168.124.6/30"
  ck "hephaestus route"   "$(nmcli -g ipv4.routes connection show Hephaestus 2>/dev/null|grep -c '192.168.40.0/24 192.168.124.5 100')" "1"
else
  na "hephaestus link" "profile not created. Silenus.md Step 13 sub-step 4 adds it; it is only needed once that host is built"
fi
# The fallback route lives on the work WiFi profile, which exists only once that
# network has been joined. Absent, it is untestable rather than wrong.
_hepfb=$(nmcli -t -g NAME connection show 2>/dev/null|while IFS= read -r c; do nmcli -g ipv4.routes connection show "$c" 2>/dev/null; done|grep -c '192.168.40.0/24 192.168.88.212 200')
if [ "${_hepfb:-0}" -gt 0 ]; then
  ck "hephaestus fallback" "$_hepfb" "1"
else
  na "hephaestus fallback" "no work WiFi profile here yet. Join that network, then: nmcli con mod <work-wifi-profile> +ipv4.routes \"192.168.40.0/24 192.168.88.212 200\""
fi
# Neither point-to-point profile may autoconnect. A /30 carries nothing that
# says which peer is on the far end, so a profile coming up on its own would be
# guessing, and guessing wrong looks connected while reaching nothing.
ck "neither link autoconnects" "$(for c in Dionysus Hephaestus; do nmcli -g connection.autoconnect connection show "$c" 2>/dev/null; done|grep -c '^yes$')" "0"

printf '\n--- Step 14: firewall ---\n'
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  ck "guests reachable from $net" "$(sudo iptables -C FORWARD -s "$net" -d 192.168.24.0/24 -o virbr1 -j ACCEPT 2>/dev/null && echo yes || echo no)" "yes"
done
# Existence is not enough: a rule below the jump to LIBVIRT_FWI, whose last rule
# rejects anything inbound to virbr1, is never reached and still passes -C.
_ours=$(sudo iptables -S FORWARD 2>/dev/null | grep -n 'd 192.168.24.0/24 -o virbr1 -j ACCEPT' | tail -1 | cut -d: -f1)
_libv=$(sudo iptables -S FORWARD 2>/dev/null | grep -n -- '-j LIBVIRT_FWI' | cut -d: -f1)
ck "rules precede LIBVIRT_FWI" "$([ -n "$_ours" ] && [ -n "$_libv" ] && [ "$_ours" -lt "$_libv" ] && echo yes || echo no)" "yes"
ck "guest-net-access enabled" "$(systemctl is-enabled guest-net-access.service 2>/dev/null)" "enabled"
ck "guest-net-access active"  "$(systemctl is-active guest-net-access.service 2>/dev/null)" "active"
hf "guest-net-access script"  /usr/local/sbin/guest-net-access
hf "guest-net-access unit"    /etc/systemd/system/guest-net-access.service
ck "unit follows libvirtd"    "$(systemctl show -p PartOf --value guest-net-access.service 2>/dev/null|grep -c libvirtd)" "1"

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
ck "volume step"   "$(gsettings get org.gnome.settings-daemon.plugins.media-keys volume-step)" "1"
ok "app folders"   "$(gsettings get org.gnome.desktop.app-folders folder-children 2>/dev/null|cut -c1-40)"

printf '\n--- Step 7: ssh server ---\n'
hf "sshd drop-in" /etc/ssh/sshd_config.d/99-local.conf
r=$(sudo sshd -T 2>/dev/null|grep '^permitrootlogin'|awk '{print $2}')
case "$r" in without-password|prohibit-password) ck "root key only" "$r" "$r";; *) ck "root key only" "$r" "without-password";; esac
ck "sshd port"   "$(sudo sshd -T 2>/dev/null|grep '^port'|awk '{print $2}')" "22"
ck "sshd active" "$(systemctl is-active ssh)" "active"


# ---------------------------------------------------------------------------
# Reachability. This block reports, it does not judge, so nothing here counts
# toward PASS or FAIL. Which peer is reachable depends on where this machine is
# and which cable is in; "not routed from here" is the correct answer for a
# host at the other site, not a fault. Reads only, like everything above.
# ---------------------------------------------------------------------------
printf '\n--- Reachability from here, right now ---\n\n'
_defgw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')
_reach() {   # 1 peer  2 subnet  3 probe address  4 its bridge  5 its host address
  local r gw dev
  r=$(ip -4 route get "$3" 2>/dev/null | head -1)
  gw=$(printf '%s\n' "$r" | sed -n 's/.* via \([0-9.]*\).*/\1/p')
  dev=$(printf '%s\n' "$r" | sed -n 's/.* dev \([a-zA-Z0-9]*\).*/\1/p')
  printf '  %s\n' "$1"
  if [ -z "$dev" ]; then
    printf '    guest network %-16s no route at all\n' "$2"
  elif [ -n "$gw" ] && [ "$gw" = "$_defgw" ]; then
    printf '    guest network %-16s NOT routed from here, leaving by the default gateway\n' "$2"
  elif [ -n "$gw" ]; then
    printf '    guest network %-16s routed via %s on %s\n' "$2" "$gw" "$dev"
  else
    printf '    guest network %-16s on-link on %s\n' "$2" "$dev"
  fi
  ping -c1 -W2 "$4" >/dev/null 2>&1 \
    && printf '    its bridge %-19s answers, so the route works end to end\n' "$4" \
    || printf '    its bridge %-19s no reply\n' "$4"
  ping -c1 -W2 "$5" >/dev/null 2>&1 \
    && printf '    the host itself %-14s answers\n' "$5" \
    || printf '    the host itself %-14s no reply\n' "$5"
  printf '\n'
}
_reach "Dionysus"   "192.168.32.0/24" 192.168.32.10 192.168.32.1 192.168.8.3
_reach "Hephaestus" "192.168.40.0/24" 192.168.40.10 192.168.40.1 192.168.88.212
printf '  A guest network answering on its bridge proves the routing. It does not\n'
printf '  prove the firewall: traffic to the bridge address stops on that host and\n'
printf '  never reaches the FORWARD chain. Only traffic to a real guest does, which\n'
printf '  is what the reachability drill in the guide covers.\n'

printf '\n========================================\n'
printf '  PASS %s   FAIL %s   N/A %s\n' "$pass" "$fail" "$skip"
printf '========================================\n'

if [ "$fail" -gt 0 ]; then
  printf '\nWhat failed:\n'
  printf "$failed"
  printf '\nEach line names the check, what the machine returned, and what the\ndocument says it should be. The step to redo is the section heading the\ncheck appeared under.\n'
fi

if [ "$skip" -gt 0 ]; then
  printf '\nNot tested here:\n'
  printf "$skipped"
  printf '\nThese are not failures. Each one needs something that is not true of\nthis machine right now — a profile not yet created, hardware not\nattached — and each line says what would make it testable.\n'
fi

[ "$fail" -eq 0 ]
