#!/usr/bin/env bash
# check.sh — verify this machine matches Hephaestus.md. Hephaestus only: the
# disk layout, the two interfaces and the guest network are specific to this
# host. There is no GPU here, so no passthrough section.
#
# Reads only, never writes. Run as your own user over SSH. Exits 0 when every
# check passes and 1 when any fails.

if [ "$(id -u)" -eq 0 ]; then
  echo "STOP: run as your normal user, not root. Dotfiles, user units and group membership all live in your account."; exit 1
fi
pass=0; fail=0; failed=""
_note(){ failed="$failed  - $1\n"; }
ck(){ if [ "$2" = "$3" ]; then printf '  PASS  %-32s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-32s got[%s] want[%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); _note "$1: got [$2], wanted [$3]"; fi; }
ok(){ if [ -n "$2" ]; then printf '  PASS  %-32s %s\n' "$1" "$2"; pass=$((pass+1));
      else printf '  FAIL  %-32s (empty)\n' "$1"; fail=$((fail+1)); _note "$1: returned nothing"; fi; }
hf(){ [ -f "$2" ] && { printf '  PASS  %-32s\n' "$1"; pass=$((pass+1)); } \
                  || { printf '  FAIL  %-32s missing %s\n' "$1" "$2"; fail=$((fail+1)); _note "$1: $2 is missing"; }; }

printf '\n--- Step 1/2/3: disk, quota, secure boot ---\n'
# lsblk rounds in powers of 1024, and 1075 decimal MB lands either side of the
# 1 GiB boundary depending on where the installer aligns it, so this is a range
# rather than a string. Every other partition is large enough to round stably.
ck "efi size ~1GiB" "$(lsblk -bno SIZE /dev/nvme0n1p1 2>/dev/null|awk '{print ($1>=1000000000 && $1<=1200000000)?"ok":"out of range: "$1}')" "ok"
ck "boot size"     "$(lsblk -no SIZE /dev/nvme0n1p2|tr -d ' ')" "2G"
ck "root size"     "$(lsblk -no SIZE /dev/nvme0n1p3|tr -d ' ')" "32G"
ck "data size"     "$(lsblk -no SIZE /dev/nvme0n1p4|tr -d ' ')" "192G"
ck "lssd size"     "$(lsblk -no SIZE /dev/sda1|tr -d ' ')" "1.8T"
ck "root fstype"   "$(findmnt -no FSTYPE /)" "ext4"
ck "data fstype"   "$(findmnt -no FSTYPE /data-root)" "xfs"
ck "lssd fstype"   "$(findmnt -no FSTYPE /data-root/lssd)" "xfs"
ck "no swap"       "$(swapon --show --noheadings|wc -l|tr -d ' ')" "0"
for m in /data-root /data-root/lssd; do
  ck "ftype=1 $m"  "$(sudo xfs_info "$m" 2>/dev/null|grep -c 'ftype=1')" "1"
  ck "prjquota $m" "$(findmnt -no OPTIONS "$m"|tr ',' '\n'|grep -c prjquota)" "1"
  ok "quota state $m" "$(sudo xfs_quota -x -c state "$m" 2>/dev/null|grep -i 'project quota state'|head -1)"
done
ck "secure boot"   "$(mokutil --sb-state 2>/dev/null)" "SecureBoot enabled"
_efi=$(sudo efibootmgr -v 2>/dev/null); _cur=$(printf '%s' "$_efi"|awk '/^BootCurrent:/{print $2}')
ok "booted from"   "$(printf '%s' "$_efi"|grep -i "^Boot$_cur"|head -1|cut -c1-58)"
ck "shim in use"   "$(printf '%s' "$_efi"|grep -ci shim|awk '{print ($1>0)?"yes":"no"}')" "yes"
ok "bios version"  "$(sudo dmidecode -s bios-version 2>/dev/null)"

printf '\n--- Step 3/8: repositories ---\n'
for s in "trixie" "trixie-security" "trixie-updates"; do
  ck "sources.list $s" "$(grep -c "^deb .* $s main contrib non-free non-free-firmware\$" /etc/apt/sources.list)" "1"
done
hf "docker.sources"      /etc/apt/sources.list.d/docker.sources
hf "docker key"          /etc/apt/keyrings/docker.asc
ck "docker suite"     "$(grep -c '^Suites: trixie$' /etc/apt/sources.list.d/docker.sources)" "1"
u=$(sudo apt update 2>&1)
ck "apt update errors"   "$(printf '%s' "$u"|grep -c '^Err:')" "0"
ck "apt duplicate warns" "$(printf '%s' "$u"|grep -ci 'configured multiple times')" "0"

printf '\n--- Step 4: firmware ---\n'
ck "no pending firmware" "$(sudo fwupdmgr get-updates 2>&1|grep -qi 'No updates available\|no available firmware\|Devices with no available' && echo none || echo pending)" "none"

printf '\n--- Step 5: every package the document installs ---\n'
miss=""
for p in bash-completion bridge-utils btop curl git iptables iputils-ping jq lshw make openssl pciutils progress \
  pwgen python3 rsync sshuttle sudo tmux tree unrar vim wget \
  openssh-server mokutil dmidecode efibootmgr network-manager fwupd fwupd-amd64-signed \
  qemu-system-x86 qemu-utils ovmf virtinst libosinfo-bin osinfo-db osinfo-db-tools \
  libvirt-daemon-system libvirt-clients libguestfs-tools \
  ca-certificates docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"
done
ck "all packages present" "${miss:-none missing}" "none missing"
ck "editor is vim" "$(readlink -f /etc/alternatives/editor|grep -c vim)" "1"
ck "no claude-code"  "$(dpkg -l claude-code 2>/dev/null|grep -c '^ii')" "0"
ck "no desktop"    "$(dpkg -l 2>/dev/null|grep -cE '^ii +(gnome-shell|xserver-xorg-core) ')" "0"

printf '\n--- Step 6: dotfiles ---\n'
for f in .bashrc .bash_aliases .bash_profile .tmux.conf .hushlogin; do hf "$f" "$HOME/$f"; done
hf "tmux completion" "$HOME/.local/share/bash-completion/completions/tmux"
ck "functions" "$(bash -ic 'type -t update upgrade ports _asroot privip' 2>/dev/null|grep -c function)" "5"
ck "no GNOME aliases" "$(bash -ic 'alias DE EN kbd' 2>&1|grep -c '^alias')" "0"
ck "hist ignorespace"   "$(bash -ic 'echo $HISTCONTROL' 2>/dev/null|grep -c 'ignoreboth\|ignorespace')" "1"
ck "hist append prompt" "$(bash -ic 'echo $PROMPT_COMMAND' 2>/dev/null|grep -c 'history -a')" "1"
hf "history drop-in" /etc/profile.d/99-history.sh
hf "banner file"     /etc/ssh/banner.txt
ck "banner content"  "$(grep -c 'B A H M A N' /etc/ssh/banner.txt 2>/dev/null)" "1"
# What matters is that sshd serves it, not that the file exists. sshd -T prints
# the effective configuration, so this catches a drop-in that was written but
# never reloaded.
ck "sshd serves banner" "$(sudo sshd -T 2>/dev/null|awk '/^banner /{print $2}')" "/etc/ssh/banner.txt"
ck "motd emptied"    "$(wc -c < /etc/motd 2>/dev/null|tr -d ' ')" "0"
ck "no kernel line"  "$([ -x /etc/update-motd.d/10-uname ] && echo executable || echo off)" "off"
sc="$HOME/.ssh/config"
ck "ssh managed block" "$(grep -c '^# >>> dotfiles managed block >>>$' "$sc" 2>/dev/null)" "1"
ck "block is last"     "$(awk '/^# >>> dotfiles managed block >>>/{s=NR} /^Host /{l=NR} END{print (s&&l>s)?"yes":"no"}' "$sc" 2>/dev/null)" "yes"
hf "sshd drop-in" /etc/ssh/sshd_config.d/99-local.conf
r=$(sudo sshd -T 2>/dev/null|grep '^permitrootlogin'|awk '{print $2}')
case "$r" in without-password|prohibit-password) ck "root key only" "$r" "$r";; *) ck "root key only" "$r" "without-password";; esac
ck "sshd active" "$(systemctl is-active ssh)" "active"

printf '\n--- Step 7: KVM ---\n'
ck "virtualisation"  "$(grep -Ec '(vmx|svm)' /proc/cpuinfo|awk '{print ($1>0)?"yes":"no"}')" "yes"
ck "libvirtd.socket" "$(systemctl is-active libvirtd.socket)" "active"
_kvm=$(ls /sys/module 2>/dev/null | grep -E '^kvm_(intel|amd)$')
ck "nested"          "$(cat /sys/module/$_kvm/parameters/nested 2>/dev/null|sed 's/^1$/Y/')" "Y"
ck "nofile soft"     "$(grep -c 'soft.*nofile.*65536' /etc/security/limits.d/99-kvm.conf 2>/dev/null)" "1"
ck "nofile hard"     "$(grep -c 'hard.*nofile.*1048576' /etc/security/limits.d/99-kvm.conf 2>/dev/null)" "1"
ck "lssd-pool"       "$(virsh -c qemu:///system pool-list --name 2>/dev/null|grep -cx lssd-pool)" "1"
ck "no default net"  "$(virsh -c qemu:///system net-list --all --name 2>/dev/null|grep -cx default)" "0"
ck "static_network_40" "$(virsh -c qemu:///system net-list --name 2>/dev/null|grep -cx static_network_40)" "1"
ck "net autostart"   "$(virsh -c qemu:///system net-info static_network_40 2>/dev/null|awk '/^Autostart/{print $2}')" "yes"
ck "virbr1 address"  "$(ip -4 -br addr show virbr1 2>/dev/null|awk '{print $3}')" "192.168.40.1/24"
ck "libvirt fw backend" "$(sudo iptables -t nat -L LIBVIRT_PRT -n 2>/dev/null|grep -c MASQUERADE|awk '{print ($1>0)?"iptables":"not iptables"}')" "iptables"
ck "groups"          "$(id -nG|tr ' ' '\n'|grep -cE '^(libvirt|kvm|docker)$')" "3"

printf '\n--- Step 8: Docker ---\n'
ck "docker active"   "$(systemctl is-active docker)" "active"
ck "data-root"       "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)" "/data-root"
ck "driver"          "$(docker info --format '{{.Driver}}' 2>/dev/null)" "overlay2"
ck "backing xfs"     "$(docker info --format '{{.DriverStatus}}' 2>/dev/null|grep -c 'Backing Filesystem xfs')" "1"
ck "snapshotter off" "$(grep -c '"containerd-snapshotter": false' /etc/docker/daemon.json 2>/dev/null)" "1"
ck "quota enforced"  "$(docker run --rm --storage-opt size=1G busybox df -h / 2>/dev/null|awk 'NR==2{print $2}')" "1.0G"
ck "hello-world"     "$(docker run --rm hello-world 2>/dev/null|grep -c 'working correctly')" "1"

printf '\n--- Step 9: networking ---\n'
ck "wan profile"     "$(nmcli -g connection.id connection show wan 2>/dev/null)" "wan"
ck "wan interface"   "$(nmcli -g connection.interface-name connection show wan 2>/dev/null)" "wlp2s0"
ok "wan address"     "$(ip -4 -br addr show wlp2s0 2>/dev/null|awk '{print $3}')"
# The profile, not the live link. The cable to Silenus is connected only while
# that machine is on site, and a check that failed whenever it was unplugged
# would be noise rather than signal.
ck "p2p profile"     "$(nmcli -g connection.id connection show Hephaestus 2>/dev/null)" "Hephaestus"
ck "p2p interface"   "$(nmcli -g connection.interface-name connection show Hephaestus 2>/dev/null)" "eno1"
ck "p2p address"     "$(nmcli -g ipv4.addresses connection show Hephaestus 2>/dev/null)" "192.168.124.5/30"
ck "p2p never-default" "$(nmcli -g ipv4.never-default connection show Hephaestus 2>/dev/null)" "yes"
ck "one default route" "$(ip -4 route show default|wc -l|tr -d ' ')" "1"
ck "default via wan" "$(ip -4 route show default|grep -c 'dev wlp2s0')" "1"
ck "ip_forward"      "$(sysctl -n net.ipv4.ip_forward)" "1"
ck "ip_forward conf" "$(grep -c 'net.ipv4.ip_forward = 1' /etc/sysctl.d/99-kvm.conf 2>/dev/null)" "1"
ck "default gw reachable" "$(ip -4 route show default|awk '{print $3}'|head -1|xargs -r -I{} ping -c1 -W2 {} >/dev/null 2>&1 && echo yes || echo no)" "yes"

printf '\n--- Step 10: firewall ---\n' 
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  ck "guests reachable from $net" "$(sudo iptables -C FORWARD -s "$net" -d 192.168.40.0/24 -o virbr1 -j ACCEPT 2>/dev/null && echo yes || echo no)" "yes"
done
# Existence is not enough: a rule below the jump to LIBVIRT_FWI, whose last rule
# rejects anything inbound to virbr1, is never reached and still passes -C.
_ours=$(sudo iptables -S FORWARD 2>/dev/null | grep -n 'd 192.168.40.0/24 -o virbr1 -j ACCEPT' | tail -1 | cut -d: -f1)
_libv=$(sudo iptables -S FORWARD 2>/dev/null | grep -n -- '-j LIBVIRT_FWI' | cut -d: -f1)
ck "rules precede LIBVIRT_FWI" "$([ -n "$_ours" ] && [ -n "$_libv" ] && [ "$_ours" -lt "$_libv" ] && echo yes || echo no)" "yes"
ck "guest-net-access enabled" "$(systemctl is-enabled guest-net-access.service 2>/dev/null)" "enabled"
ck "guest-net-access active"  "$(systemctl is-active guest-net-access.service 2>/dev/null)" "active"
hf "guest-net-access script"  /usr/local/sbin/guest-net-access
hf "guest-net-access unit"    /etc/systemd/system/guest-net-access.service
ck "unit follows libvirtd"    "$(systemctl show -p PartOf --value guest-net-access.service 2>/dev/null|grep -c libvirtd)" "1"

printf '\n========================================\n'
printf '  PASS %s   FAIL %s\n' "$pass" "$fail"
printf '========================================\n'

if [ "$fail" -gt 0 ]; then
  printf '\nWhat failed:\n'
  printf "$failed"
  printf '\nEach line names the check, what the machine returned, and what the\ndocument says it should be. The step to redo is the section heading the\ncheck appeared under.\n'
fi

[ "$fail" -eq 0 ]
