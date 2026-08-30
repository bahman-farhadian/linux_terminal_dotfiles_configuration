# Dionysus — Debian 13 Headless KVM + Docker Host

Hostname `Dionysus`. Purely headless: base system and `openssh-server` only, no
desktop environment, administered over SSH. The GNOME workstation is
[Silenus.md](Silenus.md).

Build target: AMD Ryzen 9 3900X (12c/24t), 128GB RAM, single GbE NIC (Intel I211), NVIDIA GPU reserved for guest passthrough.

Disks, referenced by interface + size:

|Role|Interface|Size|
|---|---|---|
|OS / Docker `data-root`|SATA SSD|233GB|
|`sssd` - VM system disks + Docker large volumes|NVMe|250GB|
|`lssd` - VM data disks + Docker large volumes|NVMe|1TB|

No swap partition or swapfile anywhere in this build.

---

## 1. BIOS Prerequisites

> BIOS Settings:
> - **Above 4G Decoding**: Enabled
> - **Resizable BAR**: Auto (or Enabled)
> - **SVM / SR-IOV**: Enabled

Required before the OS can see the VFIO groups used for GPU passthrough in section 6.

---

## 2. Base Debian 13 Install

Manual partitioning in the installer, across all three disks — `partman` supports XFS natively, so this happens at install time, not after:

**SATA SSD (`sda`):**

|Partition|Size|FS|Mount|
|---|---|---|---|
|`sda1`|1GB|vfat|`/boot/efi`|
|`sda2`|2GB|ext4|`/boot`|
|`sda3`|30GB|ext4|`/`|
|`sda4`|remainder (~199.9GB)|xfs|`/data-root`|

**NVMe 250GB (`nvme0n1`):** single partition, xfs, `/data-root/sssd`

**NVMe 1TB (`nvme1n1`):** single partition, xfs, `/data-root/lssd`

`sda4` mounts at `/data-root` first; the two NVMe partitions mount as nested points under it (`/data-root/sssd`, `/data-root/lssd`) — the installer creates the parent directory and handles the mount order automatically, no separate top-level mountpoints needed.

OS install ISOs also live on the SATA SSD, under `/data-root/isos` — referenced later in section 9 for VM installs.

One thing `partman`'s mount-options list doesn't expose is XFS project quota (`pquota`/`prjquota`) — that gets added to `/etc/fstab`after first boot, in section 3. Everything else (formatting, mounting) is handled by the installer itself.

No swap partition — omit it from the table entirely, don't just disable it later.

Package selection: base system + `openssh-server` only. Deselect the desktop environment task; this host stays headless.

**Verify after first boot:**

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
swapon --show   # expect no output
```

---

## 3. Post-Install Filesystem Finalization

Confirm what the installer actually created before editing anything:

```bash
findmnt -no SOURCE,TARGET,OPTIONS /data-root /data-root/sssd /data-root/lssd
```

Confirm `ftype=1` on all three — this is a hard requirement for both overlay2 and project quotas, and `partman`'s defaults aren't guaranteed to match a manual `mkfs.xfs`:

```bash
xfs_info /data-root       | grep ftype
xfs_info /data-root/sssd  | grep ftype
xfs_info /data-root/lssd  | grep ftype
# expect: ftype=1 on all three
```

Edit `/etc/fstab` and append `,pquota` right after `defaults` in the options field of those three XFS entries. XFS project quota can't be toggled with `mount -o remount` — it only initializes on an actual mount, not a remount — so unmount and remount fresh instead. Children before the parent, since `sssd`/`lssd` nest inside `/data-root`:

```bash
systemctl daemon-reload
umount /data-root/sssd
umount /data-root/lssd
umount /data-root
mount -a
```

**Verify quota accounting is active** — use `state`, not `report -p`: with no projects assigned yet, `report -p` silently shows nothing whether quota is on or off, which hides exactly this failure:

```bash
xfs_quota -x -c 'state' /data-root
xfs_quota -x -c 'state' /data-root/sssd
xfs_quota -x -c 'state' /data-root/lssd
# expect: Accounting: ON, Enforcement: ON
```

---

## 4. System Utilities & KVM/libvirt Install

Debian 13 defaults to the DEB822 source format (`/etc/apt/sources.list.d/debian.sources`) instead of the classic `sources.list` — packages like `unrar` live in `non-free`, which isn't enabled by default in either format. Handle whichever one is actually present:

```bash
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i -E 's/^Components:.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
  sed -i -E 's/^(deb(-src)? .* trixie[a-zA-Z-]*) main.*/\1 main contrib non-free non-free-firmware/' /etc/apt/sources.list
fi
apt update
```

**Verify:**

```bash
apt-cache policy | grep -i non-free
# expect: non-free and non-free-firmware component lines present
```

Base toolkit:

```bash
apt install -y sudo btop curl git jq lshw progress rsync tmux tree unrar vim wget sshuttle pwgen bridge-utils
```

Confirm the CPU actually exposes virtualization extensions before installing anything KVM-related:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
# expect: >0
```

KVM/libvirt — includes `libosinfo`/`osinfo-db` so `virt-install --os-variant` (section 9) resolves correctly instead of guessing:

KVM/libvirt — includes `libosinfo`/`osinfo-db` so `virt-install --os-variant` (section 9) resolves correctly instead of guessing:

```bash
apt install -y qemu-kvm ovmf virtinst virt-manager libosinfo-bin osinfo-db osinfo-db-tools \
  libvirt-daemon-system libvirt-clients qemu-utils libguestfs-tools
usermod -aG libvirt,kvm $USER
systemctl enable --now libvirtd
```

The packaged `osinfo-db` is the actively-maintained source here — libosinfo's own docs recommend installing it via the distro package rather than fetching it manually, and Debian keeps it current through normal mirror infrastructure. Skip `osinfo-db-import --latest`: it pulls from `releases.pagure.org`, a third-party host even libosinfo's own maintainers have flagged as unreliable, and it's not needed — `apt update && apt upgrade osinfo-db` is the correct way to refresh it going forward.

**Verify:**

```bash
systemctl is-active libvirtd
# expect: active
```

**Nested virtualization** — required for running ESXi/OpenStack as guests on top of this host's VMs. AMD platform, so this targets `kvm_amd`, not `kvm_intel`. Check current state first, only touch the module config if it's not already on:

```bash
cat /sys/module/kvm_amd/parameters/nested
# if 0 or N:
cat > /etc/modprobe.d/kvm-amd.conf <<'EOF'
options kvm_amd nested=1
EOF
modprobe -r kvm_amd
modprobe kvm_amd
```

**Verify:**

```bash
cat /sys/module/kvm_amd/parameters/nested
# expect: 1 (or Y)
```

Storage pools on the disks from section 3:

```bash
virsh pool-define-as sssd-pool dir --target /data-root/sssd
virsh pool-build sssd-pool
virsh pool-start sssd-pool
virsh pool-autostart sssd-pool

virsh pool-define-as lssd-pool dir --target /data-root/lssd
virsh pool-build lssd-pool
virsh pool-start lssd-pool
virsh pool-autostart lssd-pool
```

**Verify:**

```bash
virsh pool-list --all
# expect: sssd-pool and lssd-pool both active, autostart yes
```

`libvirtd` auto-creates a `default` NAT network on install (typically `192.168.122.0/24`) — remove it, since `br-kvm` (section 7) replaces it and having both active means two competing NAT/DHCP setups:

```bash
virsh net-destroy default
virsh net-undefine default
```

**Verify:**

```bash
virsh net-list --all
# expect: no "default" network listed
```

---

## 5. Docker Install & Storage Quotas

From Docker's official repository:

```bash
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" \
  > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/data-root",
  "storage-driver": "overlay2"
}
EOF
systemctl enable --now docker
systemctl restart docker
```

**Verify:**

```bash
docker info | grep -i "docker root dir\|storage driver"
# expect: Docker Root Dir: /data-root
#         Storage Driver: overlay2
```

Two storage tiers by design:

- **Capped, on `sda4`** — image layers and small containers (e.g. Nexus) sit on `/data-root` directly, bounded per-container via `--storage-opt size=`. Works because the quota is XFS-project-based and `sda4` has `pquota` enabled.
- **Uncapped, bind-mounted** — anything needing real bulk (databases, local models) mounts explicitly into `/data-root/sssd` or `/data-root/lssd`, on the NVMe disks, not subject to the `data-root` size cap.

```bash
# capped tier
docker run --rm --storage-opt size=10G alpine df -h /

# uncapped tier — example only, adjust path/image per workload
docker run -d --name <container-name> \
  -v /data-root/lssd/<volume-name>:/data \
  <image>
```

---

## 6. IOMMU / VFIO / GPU Passthrough

Grub cmdline — AMD platform:

```bash
nano /etc/default/grub
```

```ini
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 amd_iommu=on iommu=pt vfio-pci.disable_idle_d3=1"
```

```bash
update-grub
```

Derive the GPU's PCI vendor:device IDs at runtime rather than hardcoding — a reinstall doesn't guarantee identical enumeration. This works fine without IOMMU active, so no reboot needed yet:

```bash
GPU_PCI_IDS=$(lspci -nn | grep -i nvidia | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | paste -sd, -)
echo "$GPU_PCI_IDS"
```

Bind to `vfio-pci`:

```bash
cat > /etc/modprobe.d/vfio.conf <<EOF
options vfio-pci ids=${GPU_PCI_IDS}
softdep nouveau pre: vfio-pci
EOF
```

Blacklist every driver that could otherwise grab the card before `vfio-pci` does — not just `nouveau`. This is what actually prevents boot-time errors: a stray `nvidia`/`radeon`/`amdgpu` autoload racing `vfio-pci` for the device is the usual cause of passthrough silently failing:

```bash
cat > /etc/modprobe.d/blacklist-gpu.conf <<'EOF'
blacklist nouveau
blacklist nvidia
blacklist radeon
blacklist amdgpu
options nouveau modeset=0
EOF
```

Force `vfio` to load in the initramfs itself, ahead of any GPU driver — `softdep` alone only orders module _loading_, it doesn't guarantee `vfio-pci` gets first crack at the device during early boot:

```bash
cat >> /etc/initramfs-tools/modules <<'EOF'
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF

update-initramfs -u -k all
```

That's every change GPU passthrough needs — grub, `vfio.conf`, the blacklist, and initramfs all take effect on the same boot, so there's no need to reboot mid-section here. Verification (IOMMU active, GPU group, driver binding) happens together with everything else in section 9, after the one reboot that closes out section 8.

---

## 7. Networking

Persisted through NetworkManager's own connection profiles via `nmcli` — not `/etc/network/interfaces` files.

Install it first:

```bash
apt install -y network-manager
systemctl enable --now NetworkManager
```

Clear out whatever connection profiles the installer left behind before laying down the bridge configs:

```bash
nmcli connection show
nmcli connection delete <connection-name>   # repeat per existing profile
```

Loopback:

```bash
nmcli con add type loopback ifname lo con-name lo autoconnect yes
nmcli con up lo
```

Management bridge (`br0`) — static, `enp4s0` as the sole slave:

```bash
nmcli con add type bridge ifname br0 con-name br0 stp no \
  ipv4.method manual ipv4.addresses 192.168.8.3/24 ipv4.gateway 192.168.8.1 \
  ipv4.dns "8.8.8.8,1.1.1.1"
nmcli con mod br0 connection.autoconnect yes

nmcli con add type ethernet ifname enp4s0 con-name br0-slave master br0
nmcli con mod br0-slave connection.autoconnect yes

nmcli con up br0
nmcli con up br0-slave
```

**Verify:**

```bash
ip address        # br0: 192.168.8.3/24, enp4s0: no IP of its own
brctl show         # br0 with enp4s0 as a member
ping -c4 192.168.8.1
```

KVM guest bridge (`br-kvm`) — same pattern, no physical slave, no gateway/DNS since it isn't routed on its own; that's what section 8's NAT rules are for. Manually defined rather than libvirt's built-in NAT network type, since libvirt rewrites its own iptables chains on `libvirtd` restart, conflicting with the hand-maintained ruleset in section 8:

```bash
nmcli con add type bridge ifname br-kvm con-name br-kvm stp no \
  ipv4.method manual ipv4.addresses 192.168.24.1/24
nmcli con mod br-kvm connection.autoconnect yes
nmcli con up br-kvm
```

**Verify:**

```bash
ip address        # br-kvm: 192.168.24.1/24
brctl show
```

Attach guest domain XML NICs to `br-kvm`.

Persist IP forwarding:

```bash
cat > /etc/sysctl.d/99-kvm-forward.conf <<'EOF'
net.ipv4.ip_forward = 1
EOF
sysctl --system
```

**Verify:**

```bash
ip -br addr show br0 br-kvm
sysctl net.ipv4.ip_forward
```

---

## 8. Firewall — iptables-persistent

```bash
apt install -y iptables-persistent
```

NAT `192.168.24.0/24` out through `br0`, and permit forwarding between the two bridges:

```bash
iptables -t nat -A POSTROUTING -s 192.168.24.0/24 ! -d 192.168.24.0/24 -o br0 -j MASQUERADE
iptables -A FORWARD -i br-kvm -o br0 -j ACCEPT
iptables -A FORWARD -i br0 -o br-kvm -m state --state RELATED,ESTABLISHED -j ACCEPT
netfilter-persistent save
```

**Verify:**

```bash
iptables -t nat -L POSTROUTING -n -v
iptables -L FORWARD -n -v
cat /etc/iptables/rules.v4
```

What this ruleset actually gives you: any connection a VM guest initiates outward reaches `192.168.8.0/24` and beyond, with return traffic flowing back automatically via connection tracking — no extra rule needed for that direction. It does **not** let a device on `192.168.8.0/24` open a _new_ connection directly into a specific VM's `192.168.24.x` address; that needs an explicit DNAT rule per exposed service:

```bash
# example: forward TCP 2222 on Nyx's LAN IP to SSH on a specific guest
iptables -t nat -A PREROUTING -i br0 -p tcp --dport 2222 -j DNAT --to-destination 192.168.24.10:22
iptables -A FORWARD -i br0 -o br-kvm -p tcp -d 192.168.24.10 --dport 22 -j ACCEPT
netfilter-persistent save
```

This is the last configuration step in the build — GPU passthrough (section 6) is also only staged, not yet rebooted into. Confirming the ruleset actually survives a reboot, rather than just that `netfilter-persistent save` exited cleanly, happens together with everything else in section 9.

---

## 9. Reboot & Final Verification Pass

Every pending change — quota's already live from section 3, but nested virt's module option, GPU passthrough's grub/vfio/blacklist/initramfs work, and the network bridges' autoconnect all need this one boot to actually take hold together:

```bash
reboot
```

**Boot fundamentals:**

```bash
swapon --show
# expect: no output
```

**GPU passthrough:**

```bash
dmesg | grep -iE "AMD-Vi|DMAR|IOMMU"

for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}; n=${n%%/*}
  printf 'IOMMU Group %s ' "$n"; lspci -nns "${d##*/}"
done | grep -i vga -A1

lsmod | grep nouveau
# expect: no output

lspci -nnk | grep -i nvidia -A3
# expect: "Kernel driver in use: vfio-pci" on the GPU and its audio function

dmesg | grep -i vfio
# expect: vfio-pci probe/bind messages for the GPU's PCI address
```

**Networking — bridges came up on their own via NetworkManager autoconnect:**

```bash
ip -br addr show br0 br-kvm
# expect: br0 192.168.8.3/24, br-kvm 192.168.24.1/24
ping -c4 192.168.8.1
```

**Firewall — ruleset actually survived the reboot, not just that `save` exited cleanly:**

```bash
iptables -t nat -L POSTROUTING -n -v
iptables -L FORWARD -n -v
```

**Nested virtualization and quota — reconfirm both persisted, not just that they were on right after you set them:**

```bash
cat /sys/module/kvm_amd/parameters/nested
# expect: 1 (or Y)

xfs_quota -x -c 'state' /data-root
xfs_quota -x -c 'state' /data-root/sssd
xfs_quota -x -c 'state' /data-root/lssd
# expect: Accounting: ON, Enforcement: ON
```

**Functional tests:**

```bash
# VM on sssd pool
virsh vol-create-as sssd-pool <vm-name>.qcow2 20G --format qcow2
virt-install --name <vm-name> --memory 4096 --vcpus 2 \
  --disk vol=sssd-pool/<vm-name>.qcow2 --network bridge=br-kvm \
  --os-variant debian13 --cdrom /data-root/isos/debian-13-netinst.iso

# Docker quota enforcement
docker run --rm --storage-opt size=5G alpine df -h /

# Cross-subnet reachability, run from inside a guest on br-kvm
ping -c3 192.168.8.3

# GPU passthrough — attach the GPU to a VM via its PCI address in the domain XML, then:
virsh start <gpu-vm-name>
virsh domdisplay <gpu-vm-name>
```