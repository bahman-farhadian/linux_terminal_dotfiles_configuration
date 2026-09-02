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
pass=0; fail=0; skip=0; failed=""; skipped=""
# Where this script lives, which is also where the files it deploys come from.
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# same() is stronger than hf(). hf asks whether a file exists; this asks whether
# it is still the repository's copy. install.sh deploys these with a plain cp,
# so anything that differs was edited on the machine and will be overwritten by
# the next run — better to hear about it now than to lose it silently.
same(){
  if [ ! -f "$3" ]; then
    printf '  FAIL  %-32s missing %s\n' "$1" "$3"; fail=$((fail+1)); _note "$1: $3 is missing"
  elif cmp -s "$REPO/$2" "$3"; then
    printf '  PASS  %-32s matches the repository\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-32s differs from the repository\n' "$1"; fail=$((fail+1))
    _note "$1: $3 differs from $REPO/$2 — diff them, then either commit the change or re-run install.sh"
  fi
}
# same_root() is same() for the copies install.sh puts in /root. Those were
# deployed and never verified, so a hand-edit there was invisible.
same_root(){ # 1 label  2 repo-relative  3 path under /root
  if ! sudo test -e "$3"; then
    na "$1" "$3 does not exist. install.sh writes it when it has sudo; ./install.sh --root manages /root fully"
  elif sudo cmp -s "$REPO/$2" "$3"; then
    ck "$1" "matches" "matches"
  else
    ck "$1" "differs" "matches"
  fi
}
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
  libvirt-daemon-system libvirt-clients libguestfs-tools cloud-image-utils acl util-linux \
  ca-certificates docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"
done
ck "all packages present" "${miss:-none missing}" "none missing"
ck "editor is vim" "$(readlink -f /etc/alternatives/editor|grep -c vim)" "1"
ck "no claude-code"  "$(dpkg -l claude-code 2>/dev/null|grep -c '^ii')" "0"
ck "no desktop"    "$(dpkg -l 2>/dev/null|grep -cE '^ii +(gnome-shell|xserver-xorg-core) ')" "0"

printf '\n--- Step 6: dotfiles ---\n'
same ".bashrc"       bash/bashrc       "$HOME/.bashrc"
same ".bash_aliases" bash/bash_aliases "$HOME/.bash_aliases"
same ".bash_profile" bash/bash_profile "$HOME/.bash_profile"
same ".tmux.conf"    tmux/tmux.conf    "$HOME/.tmux.conf"
same ".hushlogin"    hushlogin         "$HOME/.hushlogin"
if [ -e /etc/dotfiles-root-configured ]; then
  same_root "root .bashrc"       bash/bashrc       /root/.bashrc
  same_root "root .bash_profile" bash/bash_profile /root/.bash_profile
  same_root "root .bash_aliases" bash/bash_aliases /root/.bash_aliases
else
  na "root bash dotfiles" "root is not managed on this host; ./install.sh --root adds it"
fi
same_root "root .tmux.conf" tmux/tmux.conf /root/.tmux.conf
hf "tmux completion" "$HOME/.local/share/bash-completion/completions/tmux"
if [ -e /etc/dotfiles-root-configured ]; then
  ck "tmux completion (root)" "$(sudo test -r /root/.local/share/bash-completion/completions/tmux && echo yes || echo no)" "yes"
else
  na "tmux completion (root)" "root is not managed on this host; ./install.sh --root adds it"
fi
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
# Active is not the same as coming back. pool-list without --all shows only
# running pools, so a pool started by hand passes that check while autostart is
# off and the next boot has no pool at all.
ck "pool autostart"  "$(virsh -c qemu:///system pool-info lssd-pool 2>/dev/null|awk '/^Autostart/{print $2}')" "yes"
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
ck "wan autoconnect" "$(nmcli -g connection.autoconnect connection show wan 2>/dev/null)" "yes"
ck "wan mac pinned"  "$(nmcli -g 802-11-wireless.cloned-mac-address connection show wan 2>/dev/null)" "permanent"
# Named rather than left to show up as a symptom. Installing over WiFi leaves a
# wlp2s0 stanza in /etc/network/interfaces; the wpa_supplicant ifupdown starts
# for it holds the interface, so NetworkManager reports the device unavailable
# while still calling it managed, and every activation fails with "No suitable
# device found". Step 9 sub-step 4 removes the stanza and kills that supplicant.
ck "no ifupdown wifi" "$(cat /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null|grep -cE '^[[:space:]]*(iface|allow-hotplug|auto)[[:space:]]+wlp2s0')" "0"
# The profile, not the live link. The cable to Silenus is connected only while
# that machine is on site, and a check that failed whenever it was unplugged
# would be noise rather than signal.
ck "p2p profile"     "$(nmcli -g connection.id connection show Hephaestus 2>/dev/null)" "Hephaestus"
ck "p2p interface"   "$(nmcli -g connection.interface-name connection show Hephaestus 2>/dev/null)" "eno1"
ck "p2p address"     "$(nmcli -g ipv4.addresses connection show Hephaestus 2>/dev/null)" "192.168.124.5/30"
ck "p2p never-default" "$(nmcli -g ipv4.never-default connection show Hephaestus 2>/dev/null)" "yes"
# The far end of a link Silenus deliberately does not autoconnect. This one
# must: it is the second way into a host at another site with no console.
ck "p2p autoconnect" "$(nmcli -g connection.autoconnect connection show Hephaestus 2>/dev/null)" "yes"
# Half of a pair: this route lets a guest here answer one on Silenus, and
# Silenus.md Step 14 lets a connection started here in past libvirt's REJECT.
ck "route to silenus guests" "$(nmcli -g ipv4.routes connection show Hephaestus 2>/dev/null|grep -c '192.168.24.0/24 192.168.124.6 100')" "1"
# Written against whatever Silenus holds on the work WiFi, which is a lease
# rather than a reservation. Absent, it is unconfigured rather than wrong.
# Gatewayless, so there is no leased address to go stale and this is a fact
# about our own configuration rather than about Silenus's current lease.
ck "silenus guests fallback" "$(nmcli -g ipv4.routes connection show wan 2>/dev/null|grep -c '192.168.24.0/24')" "1"
if [ "$(cat /sys/class/net/eno1/carrier 2>/dev/null)" = "1" ]; then
  ck "p2p link up" "$(ip -4 -br addr show eno1 2>/dev/null|awk '{print $3}')" "192.168.124.5/30"
else
  na "p2p link up" "no cable in eno1. The link comes up when Silenus is on site; the profile above is what persists"
fi
ck "one default route" "$(ip -4 route show default|wc -l|tr -d ' ')" "1"
ck "default via wan" "$(ip -4 route show default|grep -c 'dev wlp2s0')" "1"
ck "p2p installs no default" "$(ip -4 route show default|grep -c 'dev eno1')" "0"
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


# ---------------------------------------------------------------------------
# Reachability. This block reports, it does not judge, so nothing here counts
# toward PASS or FAIL. Which peer is reachable depends on where this machine is
# and which cable is in; "not routed from here" is the correct answer for a
# host at the other site, not a fault. Reads only, like everything above.
# ---------------------------------------------------------------------------
printf '\n--- Connectivity matrix ---\n\n'
_defgw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')
# Configured: the route is written on a profile and survives a reboot.
# Live: the kernel is using it now. They differ whenever a profile is down,
# which is the normal state for a link to a machine that is not on site.
_cfg(){ nmcli -t -g NAME connection show 2>/dev/null | while IFS= read -r c; do
          nmcli -g ipv4.routes connection show "$c" 2>/dev/null; done \
        | grep -qF "$1" && echo yes || echo NO; }
_live(){ local r gw dev
  r=$(ip -4 route show "$1" 2>/dev/null | head -1)
  [ -z "$r" ] && { echo "-"; return; }
  gw=$(printf '%s\n' "$r" | sed -n 's/.*via \([0-9.]*\).*/\1/p')
  dev=$(printf '%s\n' "$r" | sed -n 's/.*dev \([a-zA-Z0-9]*\).*/\1/p')
  [ -n "$gw" ] && echo "$gw on $dev" || echo "on-link $dev"; }
_ans(){ ping -c1 -W2 "$1" >/dev/null 2>&1 && echo yes || echo no; }

printf '  %-17s %-9s %-9s %-27s %s\n' "guest network" "tier 100" "tier 200" "live path" "bridge answers"
printf '  %-17s %-9s %-9s %-27s %s\n' "-----------------" "--------" "--------" "---------------------------" "--------------"
printf '  %-17s %-9s %-9s %-27s %s\n' "192.168.24.0/24" \
  "$(_cfg '192.168.24.0/24 192.168.124.6 100')" $(nmcli -g ipv4.routes connection show wan 2>/dev/null|grep -q '192.168.24.0/24' && echo yes || echo NO) \
  "$(_live 192.168.24.0/24)" "$(_ans 192.168.24.1)"
printf '\n  %-17s %-18s %s\n' "peer host" "address" "answers"
printf '  %-17s %-18s %s\n' "-----------------" "------------------" "-------"
printf '  %-17s %-18s %s\n' "Silenus" "192.168.124.6" "$(_ans 192.168.124.6)"
printf '\n'

# --- and now judge it -------------------------------------------------------
# Whether Silenus is reachable depends on where that laptop is, which this host
# cannot know. So the route is asserted — it is configuration and must always
# hold — while reachability is only asserted when the laptop is actually
# answering. Absent, it is untestable rather than broken.
_routed(){ # 1 subnet -> yes/no. A route for this exact prefix, or none.
  [ -n "$(ip -4 route show "$1" 2>/dev/null)" ] && echo yes || echo no
}
ck "Silenus guests routed" "$(_routed 192.168.24.0/24)" "yes"
_peer=""
for a in 192.168.124.6; do
  ping -c1 -W2 "$a" >/dev/null 2>&1 && { _peer=$a; break; }
done
if [ -n "$_peer" ]; then
  printf '  Silenus is answering on %s\n' "$_peer"
  if ping -c1 -W2 192.168.24.1 >/dev/null 2>&1; then
    ck "Silenus guests reachable" "yes" "yes"
  else
    # The host answers and its guest bridge does not. Traffic to that bridge
    # address ends on Silenus itself and never meets a firewall rule, so this is
    # not a filtering problem. The usual cause is that this host is routing over
    # the cable to an address Silenus has not brought up: its point-to-point
    # profiles do not autoconnect, so a plugged cable is not a configured one.
    ck "Silenus guests reachable" "no" "yes"
  fi
else
  na "Silenus guests reachable" "Silenus is not answering on 192.168.124.6, the far end of the cable, so it is at the other site or switched off"
fi
printf '\n'
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
