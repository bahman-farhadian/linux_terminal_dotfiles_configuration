# Dionysus — AMD Ryzen 9 3900X, Debian 13 "trixie" headless KVM host

Hostname `Dionysus`. Purely headless: base system and `openssh-server` only, no
desktop environment, administered over SSH. The GNOME workstation is
[Silenus.md](../Silenus/Silenus.md).

AMD Ryzen 9 3900X (12c/24t), 128 GB RAM, single GbE NIC (Intel I211), NVIDIA GPU
reserved for guest passthrough. Three disks:

| Role | Interface | Size |
|---|---|---|
| OS and Docker `data-root` | SATA SSD | 233 GB |
| `sssd` — VM system disks, Docker volumes | NVMe | 250 GB |
| `lssd` — VM data disks, Docker volumes | NVMe | 1 TB |

No swap partition and no swapfile anywhere in this build.

Every step here can be run again without harm. Files are written whole rather
than appended to, package installs skip what is present, and group membership
is unchanged when it is already granted. The single exception is `visudo` in
Step 3, which is a manual edit and is noted there.

## Part 1 — OS installation

### Step 1 — BIOS: virtualization and PCIe addressing

| # | Step | How |
|---|------|-----|
| 1 | Enter BIOS | Power off fully, power on, tap the setup key at the vendor splash |
| 2 | Note BIOS version | Write it down before changing anything |
| 3 | Enable SVM | `SVM Mode` = **Enabled** |
| 4 | Enable IOMMU | `IOMMU` = **Enabled** |
| 5 | Above 4G Decoding | **Enabled** |
| 6 | Resizable BAR | **Auto**, or **Enabled** |
| 7 | Save and exit | Save changes and reboot |

**Notes**

- The setup key differs by motherboard — commonly **Del** or **F2**. This build does not name one because the board model is not fixed by this document.
- `SVM` is AMD's name for the virtualization extensions. Without it KVM cannot start a guest at all, and `/proc/cpuinfo` shows no `svm` flag.
- `IOMMU`, `Above 4G Decoding` and `Resizable BAR` are what make the VFIO groups in Step 8 usable. All three must be set before the OS can see the groups, which is why they are here rather than alongside the passthrough work.
- Secure Boot is not part of this build. Silenus needs it for a laptop that travels; a headless host in a rack does not gain the same thing from it, and it complicates the out-of-tree module path that passthrough sometimes needs.

### Step 2 — Disk partitioning

Choose **Manual** partitioning. `partman` supports XFS natively, so the layout
is created at install time rather than rebuilt afterwards.

**SATA SSD (`sda`)**

| # | Partition | Size | Format | Mount |
|---|-----------|------|--------|-------|
| 1 | EFI | 1 GB | EFI System Partition | `/boot/efi` |
| 2 | Boot | 2 GB | ext4 | `/boot` |
| 3 | Root | 30 GB | ext4 | `/` |
| 4 | Data | remainder, about 199.9 GB | xfs | `/data-root` |

**NVMe 250 GB (`nvme0n1`)** — single partition, xfs, mounted at `/data-root/sssd`

**NVMe 1 TB (`nvme1n1`)** — single partition, xfs, mounted at `/data-root/lssd`

Package selection: base system and `openssh-server` only. Deselect the desktop
environment task; this host stays headless.

**Verify after first boot**

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

```bash
swapon --show
```

Expect no output from the second command.

**Notes**

- `sda4` mounts at `/data-root` first and the two NVMe partitions mount as nested points beneath it. The installer creates the parent directory and orders the mounts itself, so no separate top-level mountpoints are needed.
- OS install ISOs live on the SATA SSD under `/data-root/isos`, referenced by the functional tests in Step 11.
- No swap partition. Omit it from the table entirely rather than adding one and disabling it later.
- The installer warns that no swap space is selected. Continue.
- XFS project quota (`pquota`/`prjquota`) is the one thing `partman`'s mount-options list does not expose. It is added to `/etc/fstab` after first boot, in Step 3. Formatting and mounting are handled by the installer.

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
apt install -y vim
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

This is the one step that is not safe to repeat blindly: running it again adds
a second identical line. `sudo` tolerates the duplicate, but check whether your
user is already there before adding it.

Check it:

```bash
sudo -l -U username
```

#### 4. Add contrib and non-free

Debian 13 defaults to the DEB822 source format
(`/etc/apt/sources.list.d/debian.sources`) rather than the classic
`sources.list`, and which one the installer wrote depends on how it was run.
Handle whichever is actually present:

```bash
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i -E 's/^Components:.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
  sed -i -E 's/^(deb(-src)? .* trixie[a-zA-Z-]*) main.*/\1 main contrib non-free non-free-firmware/' /etc/apt/sources.list
fi
```

```bash
apt update
```

Check the result:

```bash
apt-cache policy | grep -i non-free
```

Expect `non-free` and `non-free-firmware` component lines.

#### 5. Update the system

```bash
apt full-upgrade
```

#### 6. Confirm ftype on all three XFS filesystems

A hard requirement for both `overlay2` and project quotas. `partman`'s defaults
are not guaranteed to match a manual `mkfs.xfs`, so check rather than assume:

```bash
xfs_info /data-root      | grep ftype
```

```bash
xfs_info /data-root/sssd | grep ftype
```

```bash
xfs_info /data-root/lssd | grep ftype
```

Expect `ftype=1` on all three.

#### 7. Confirm what the installer mounted

```bash
findmnt -no SOURCE,TARGET,OPTIONS /data-root /data-root/sssd /data-root/lssd
```

#### 8. Add project quota to fstab

```bash
vim /etc/fstab
```

Append `,pquota` immediately after `defaults` in the options field of those
three XFS entries. Leave every other line alone.

#### 9. Remount so the quota initializes

XFS project quota cannot be toggled with `mount -o remount`: it only
initializes on an actual mount. Unmount and mount fresh instead, children
before the parent, since `sssd` and `lssd` nest inside `/data-root`:

```bash
systemctl daemon-reload
```

```bash
umount /data-root/sssd
```

```bash
umount /data-root/lssd
```

```bash
umount /data-root
```

```bash
mount -a
```

#### 10. Check the quota is active

```bash
xfs_quota -x -c 'state' /data-root
```

```bash
xfs_quota -x -c 'state' /data-root/sssd
```

```bash
xfs_quota -x -c 'state' /data-root/lssd
```

Expect `Accounting: ON` and `Enforcement: ON` on all three.

**Notes**

- Use `state`, not `report -p`. With no projects assigned yet, `report -p` prints nothing whether quota is on or off, which hides exactly the failure this check exists to catch.
- The quota goes in `/etc/fstab` here, not on the kernel command line. That is the opposite of Silenus, where the quota is on `/` — root is mounted before `/etc/fstab` is read, so it has to go in `GRUB_CMDLINE_LINUX` there. On this host the quota is on `/data-root`, an ordinary fstab mount, so fstab is the right place.
- The kernel renames the options: `pquota` shows as `prjquota` in `findmnt`.
- If a `umount` reports the target is busy, something is holding it open. `fuser -m /data-root` names the process.

The installation is done.

## Part 2 — Configuration

### Step 4 — Packages

#### 1. Become root

The rest of this step is run as root.

```bash
sudo -i
```

#### 2. Install the packages

```bash
apt install -y bash-completion bridge-utils btop curl git jq lshw make openssl progress pwgen python3 rsync sshuttle sudo tmux tree unrar vim wget
```

#### 3. Check the CPU exposes virtualization

```bash
grep -Ec '(vmx|svm)' /proc/cpuinfo
```

Expect a number above 0. This machine is AMD, so the flag is `svm`.

**Notes**

- This is Silenus's package list with everything desktop-only removed: no GNOME, no flatpak, no fonts, no media applications, none of which has anything to talk to on a headless host.
- `bash-completion`, `python3` and `openssl` are here because `install.sh` in Step 5 checks for them and warns if they are missing. `tmux`, `vim`, `git`, `curl`, `jq` and `tree` are on the same list and already above.
- `openssh-server` was installed by the Debian installer in Step 2 and is what you are connected over. It is not repeated here.
- `net-tools` provides `netstat`, `ifconfig` and `route`. They are superseded by `ss` and `ip` from `iproute2`, which is already installed. Add it if the old names are what your muscle memory reaches for.
- `bridge-utils` supplies `brctl`, used by the verification in Step 9. `ip link` shows the same information; `brctl show` is kept because it prints the bridge-to-member mapping more compactly.

### Step 5 — Bash, tmux, and SSH configuration

The bash, tmux, and SSH configuration is in this repository, in this host's own
directory. Everything it needs was installed in Step 4.

#### 1. Leave the root shell

```bash
exit
```

#### 2. Run the installer

```bash
./install.sh
```

#### 3. Reload the shell

```bash
exec bash
```

**Notes**

- Run it from `Dionysus/` in this repository, as your own user. As root it configures `/root` and leaves your account untouched.
- It asks once whether to configure `root` as well. Answer `y` for the same prompt, aliases, and tmux settings under `su`. The answer is recorded in `/etc/dotfiles-root-configured`, so every later run keeps `/root` in step rather than leaving it on whatever an earlier run installed.
- Safe to re-run. The SSH block is replaced between its markers, not duplicated, and your own `Host` entries outside the markers are untouched.
- Keep the repository. The installer needs it to re-run.
- This is `Dionysus/install.sh`, not Silenus's. It carries no keyboard-lock service, no GNOME shortcuts and no GTK3 dark setting, because none of them has a session to act on here. The bash, tmux and SSH halves are identical to Silenus.
- `Dionysus/bash/bash_aliases` also drops the `DE`, `EN` and `kbd` aliases. They call `gsettings` against the GNOME input-source schema, which does not exist on this host.
- `.bashrc` adds `/usr/local/sbin`, `/usr/sbin` and `/sbin` to your PATH. Debian leaves these out for non-root users, so `sysctl`, `swapon` and `iptables` report `command not found` even though `sudo` runs them.
- Check it with `command -v sysctl`. It must print `/usr/sbin/sysctl`. If it prints nothing, the shell has not been reloaded yet.
- It writes `/etc/ssh/sshd_config.d/99-local.conf` so root can only reach SSH with a key, never a password. Ordinary users and port 22 are unchanged. This needs sudo, so answer `y` at the root prompt. On a host reached only over SSH, confirm you can still open a second session before closing the first.
- A command typed with a leading space is not written to the history file. Use it for anything carrying a password or a token. One space is enough.
- History is written at every prompt, not only when the shell exits. A tmux pane that is killed rather than closed keeps everything typed in it.
- It also writes `/etc/profile.d/99-history.sh` so both rules apply to every account, not only yours.
- `cpy` falls back to plain `tee` when there is no display, so it prints and copies nothing here rather than failing.
- `README.md` at the top of the repository covers the prompt, the tmux keys, and what changes.

### Step 6 — KVM and libvirt

#### 1. Become root

The rest of this step is run as root.

```bash
sudo -i
```

#### 2. Install the packages

```bash
apt install -y qemu-system-x86 qemu-utils ovmf virtinst libosinfo-bin osinfo-db osinfo-db-tools libvirt-daemon-system libvirt-clients libguestfs-tools
```

#### 3. Start the daemon

```bash
systemctl enable --now libvirtd.socket
```

```bash
systemctl is-active libvirtd.socket
```

Expect `active`. `libvirtd.service` itself stays `inactive` until something
connects to the socket, which is normal and not a fault.

#### 4. Turn on nested virtualization

Required only for running a hypervisor — ESXi, OpenStack — inside a guest.
Ordinary guests do not use it. This is an AMD platform, so the module is
`kvm_amd`, not `kvm_intel`.

```bash
cat /sys/module/kvm_amd/parameters/nested
```

If it prints `Y` or `1`, skip the rest of this sub-step. Otherwise:

```bash
echo 'options kvm_amd nested=1' > /etc/modprobe.d/kvm-amd.conf
```

```bash
modprobe -r kvm_amd
```

```bash
modprobe kvm_amd
```

```bash
cat /sys/module/kvm_amd/parameters/nested
```

Expect `Y`.

#### 5. Raise the open file limit

```bash
vim /etc/security/limits.d/99-kvm.conf
```

Put this in it:

```
*    soft    nofile    65536
*    hard    nofile    1048576
```

#### 6. Define the storage pools

On the two NVMe disks from Step 2:

```bash
virsh pool-define-as sssd-pool dir --target /data-root/sssd
```

```bash
virsh pool-build sssd-pool
```

```bash
virsh pool-start sssd-pool
```

```bash
virsh pool-autostart sssd-pool
```

```bash
virsh pool-define-as lssd-pool dir --target /data-root/lssd
```

```bash
virsh pool-build lssd-pool
```

```bash
virsh pool-start lssd-pool
```

```bash
virsh pool-autostart lssd-pool
```

```bash
virsh pool-list --all
```

Expect `sssd-pool` and `lssd-pool` both active, with autostart `yes`.

#### 7. Remove the default NAT network

`libvirtd` creates a `default` NAT network on install, typically
`192.168.122.0/24`. `br-kvm` from Step 9 replaces it, and leaving both active
means two competing NAT and DHCP setups on one host:

```bash
virsh net-destroy default
```

```bash
virsh net-undefine default
```

```bash
virsh net-list --all
```

Expect no `default` network listed.

#### 8. Leave the root shell

```bash
exit
```

#### 9. Add your user to the libvirt and kvm groups

```bash
sudo usermod -aG libvirt,kvm $USER
```

Log out and log back in, then check:

```bash
groups
```

Expect `libvirt` and `kvm` in the list.

**Notes**

- There is no `qemu-kvm` package in trixie. `qemu-system-x86` is the one that provides the emulator, and KVM itself is a kernel module that is already present. An install line naming `qemu-kvm` fails outright with no candidate.
- `virt-manager` is not installed. It is a GTK3 desktop application with nothing to display on here. Manage this host from Silenus over SSH with `virt-manager -c qemu+ssh://dionysus/system`, or from the command line with `virsh`.
- The `usermod` sub-step has to run as your own user, not root. Under `sudo` as root, `$USER` is `root`, so the groups would be added to the wrong account.
- The connection URI matters. Run as an ordinary user, `virsh` defaults to `qemu:///session`, a per-user hypervisor with no networks and no machines. The system VMs are on `qemu:///system`. Set `LIBVIRT_DEFAULT_URI=qemu:///system` if you would rather not type it each time.
- Group membership only applies at the next login. `newgrp libvirt` works for one shell if you do not want to log out.
- `modprobe -r kvm_amd` fails if a virtual machine is running. Shut them down first.
- The packaged `osinfo-db` is the maintained source, refreshed by `apt upgrade`. Do not use `osinfo-db-import --latest`: it fetches from `releases.pagure.org`, a third-party host libosinfo's own maintainers have flagged as unreliable. It is what makes `virt-install --os-variant` resolve rather than guess.
- `/etc/security/limits.d` applies to login sessions, not to systemd services. If `libvirtd` itself needs a higher limit, add a `LimitNOFILE` drop-in under `/etc/systemd/system/libvirtd.service.d/`.
- IP forwarding is set in Step 9 alongside the bridges, since that is what needs it.

### Step 7 — Docker

Docker Engine from Docker's own repository, not Debian's `docker.io`.

#### 1. Become root

The rest of this step is run as root.

```bash
sudo -i
```

#### 2. Install what the repository setup needs

```bash
apt install -y ca-certificates curl gnupg
```

#### 3. Create the keyring directory

```bash
install -m 0755 -d /etc/apt/keyrings
```

#### 4. Fetch Docker's signing key

```bash
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
```

```bash
chmod a+r /etc/apt/keyrings/docker.asc
```

#### 5. Add the repository

```bash
vim /etc/apt/sources.list.d/docker.sources
```

Put this in it:

```
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
```

```bash
apt update
```

#### 6. Install the engine

```bash
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

#### 7. Point data-root at the SATA data partition

```bash
mkdir -p /etc/docker
```

```bash
vim /etc/docker/daemon.json
```

Put this in it:

```
{
  "data-root": "/data-root",
  "storage-driver": "overlay2",
  "features": {
    "containerd-snapshotter": false
  }
}
```

#### 8. Start it

```bash
systemctl enable --now docker
```

```bash
systemctl restart docker
```

```bash
systemctl is-active docker
```

Expect `active`.

#### 9. Check the driver and backing filesystem

```bash
docker info --format '{{.Driver}}'
```

Expect `overlay2`. If it says `overlayfs`, the quota will not be enforced.

```bash
docker info --format '{{.DriverStatus}}'
```

Expect `Backing Filesystem` to read `xfs` and `Supports d_type` to read `true`.

```bash
docker info | grep -i "docker root dir"
```

Expect `/data-root`.

#### 10. Prove the quota is enforced

Reporting the right size is not proof. Fill the container past its limit and
watch it stop:

```bash
docker run --rm --storage-opt size=1G busybox sh -c 'df -h / | tail -1; dd if=/dev/zero of=/big bs=1M count=1200'
```

Expect `df` to report about `1.0G`, and `dd` to stop early with
`No space left on device`. If `dd` writes all 1200 MiB, the limit is not
active.

#### 11. Leave the root shell

```bash
exit
```

#### 12. Add your user to the docker group

```bash
sudo usermod -aG docker $USER
```

Log out and log back in, then check it works without `sudo`:

```bash
docker run --rm hello-world
```

**Notes**

- Two storage tiers by design. **Capped**, on `sda4`: image layers and small containers sit on `/data-root` directly, bounded per container with `--storage-opt size=`. **Uncapped**, bind-mounted: anything needing real bulk — databases, local models — mounts explicitly into `/data-root/sssd` or `/data-root/lssd` on the NVMe disks and is not subject to the `data-root` cap.
- An uncapped container looks like `docker run -d --name <name> -v /data-root/lssd/<volume>:/data <image>`.
- Docker now defaults to the containerd snapshotter, which reports itself as `overlayfs` and does not implement `--storage-opt size=`. It accepts the flag and ignores it, so a container silently gets the whole disk. Turning the snapshotter off is what makes the XFS project quota from Step 3 apply.
- `--storage-opt size=` works only on `overlay2` over XFS with project quota. It is not supported on ext4, and not by the containerd snapshotter.
- Switching the driver hides images pulled under the previous one. They are not deleted, but they live in a separate store. Pull them again if anything is missing.
- Debian's `docker.io` and `podman-docker` conflict with Docker Engine. If either was installed earlier, remove it before installing the engine.
- Adding your user to the `docker` group must run as your own user, not root.
- Membership in the `docker` group is equivalent to root. Any member can start a container that mounts the whole filesystem. Treat it as an admin privilege, not a convenience.
- `Suites: trixie` is written out rather than derived from `/etc/os-release`, so the file says which release it is pinned to. Change it when the machine is upgraded.
- `--rm` deletes the container when it exits, so these checks leave nothing behind.

### Step 8 — GPU passthrough

Everything here is staged and takes effect on the single reboot in Step 11.
Nothing in this step is verified until then.

#### 1. Become root

```bash
sudo -i
```

#### 2. Set the kernel command line

```bash
vim /etc/default/grub
```

Make the uncommented line read exactly this:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 amd_iommu=on iommu=pt vfio-pci.disable_idle_d3=1"
```

```bash
update-grub
```

#### 3. Read the GPU's PCI IDs

Derived at runtime rather than hardcoded: a reinstall does not guarantee
identical enumeration. This works without IOMMU active, so no reboot is needed
yet.

```bash
GPU_PCI_IDS=$(lspci -nn | grep -i nvidia | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | paste -sd, -)
```

```bash
echo "$GPU_PCI_IDS"
```

Expect two comma-separated `vendor:device` pairs — the GPU and its audio
function. If it prints nothing, the card is not NVIDIA or `lspci` names it
differently; read `lspci -nn` and set the variable by hand.

#### 4. Bind the card to vfio-pci

```bash
cat > /etc/modprobe.d/vfio.conf <<EOF
options vfio-pci ids=${GPU_PCI_IDS}
softdep nouveau pre: vfio-pci
EOF
```

#### 5. Blacklist every driver that could claim the card first

```bash
cat > /etc/modprobe.d/blacklist-gpu.conf <<'EOF'
blacklist nouveau
blacklist nvidia
blacklist radeon
blacklist amdgpu
options nouveau modeset=0
EOF
```

#### 6. Load vfio from the initramfs

```bash
cat >> /etc/initramfs-tools/modules <<'EOF'
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
```

```bash
update-initramfs -u -k all
```

**Notes**

- This heredoc is the one place the delimiter is unquoted — `<<EOF`, not `<<'EOF'` — because `${GPU_PCI_IDS}` has to expand. Every other heredoc in this document is quoted so its contents are written literally.
- Blacklisting only `nouveau` is the usual reason passthrough silently fails. A stray `nvidia`, `radeon` or `amdgpu` autoload racing `vfio-pci` for the device is what actually causes it, so all four are listed.
- `softdep` alone only orders module loading. It does not guarantee `vfio-pci` gets first claim on the device during early boot, which is why `vfio` also goes into the initramfs.
- Appending to `/etc/initramfs-tools/modules` is not idempotent: running Step 6 twice writes the four module names twice. Duplicates are harmless to boot, but check the file before repeating it.
- `iommu=pt` puts the IOMMU in passthrough mode for devices the host keeps, which avoids the translation cost on everything that is not being handed to a guest.

### Step 9 — Networking

Persisted through NetworkManager's own connection profiles with `nmcli`, not
`/etc/network/interfaces`.

#### 1. Become root

```bash
sudo -i
```

#### 2. Install NetworkManager

```bash
apt install -y network-manager
```

```bash
systemctl enable --now NetworkManager
```

#### 3. Clear the profiles the installer left

```bash
nmcli connection show
```

```bash
nmcli connection delete <connection-name>
```

Repeat the delete for each existing profile before laying down the bridges.

#### 4. Loopback

```bash
nmcli con add type loopback ifname lo con-name lo autoconnect yes
```

```bash
nmcli con up lo
```

#### 5. Management bridge

Static, with `enp4s0` as the sole slave:

```bash
nmcli con add type bridge ifname br0 con-name br0 stp no \
  ipv4.method manual ipv4.addresses 192.168.8.3/24 ipv4.gateway 192.168.8.1 \
  ipv4.dns "8.8.8.8,1.1.1.1"
```

```bash
nmcli con mod br0 connection.autoconnect yes
```

```bash
nmcli con add type ethernet ifname enp4s0 con-name br0-slave master br0
```

```bash
nmcli con mod br0-slave connection.autoconnect yes
```

```bash
nmcli con up br0
```

```bash
nmcli con up br0-slave
```

```bash
ip address
```

Expect `br0` holding `192.168.8.3/24` and `enp4s0` with no address of its own.

```bash
brctl show
```

Expect `br0` with `enp4s0` as a member.

```bash
ping -c4 192.168.8.1
```

#### 6. Guest bridge

Same pattern, with no physical slave and no gateway or DNS, since it is not
routed on its own. That is what Step 10's NAT rules are for.

```bash
nmcli con add type bridge ifname br-kvm con-name br-kvm stp no \
  ipv4.method manual ipv4.addresses 192.168.24.1/24
```

```bash
nmcli con mod br-kvm connection.autoconnect yes
```

```bash
nmcli con up br-kvm
```

```bash
ip address
```

Expect `br-kvm` holding `192.168.24.1/24`.

#### 7. Enable IP forwarding

```bash
vim /etc/sysctl.d/99-kvm-forward.conf
```

Put this in it:

```
net.ipv4.ip_forward = 1
```

```bash
sysctl --system
```

```bash
sysctl net.ipv4.ip_forward
```

Expect `net.ipv4.ip_forward = 1`.

**Notes**

- Changing the address of the interface you are connected over will drop your session. Run this from a console, or from `tmux` so the shell survives the disconnect, and know how to reach the machine physically before starting.
- `br-kvm` is defined by hand rather than as a libvirt NAT network because libvirt rewrites its own iptables chains whenever `libvirtd` restarts, which conflicts with the hand-maintained ruleset in Step 10. That is also why Step 6 removed the `default` network.
- Attach guest domain XML NICs to `br-kvm`.
- `enp4s0` is the interface name for this build's Intel I211. Confirm it with `ip -br link` before running the bridge commands; a different NIC enumerates differently.

### Step 10 — Firewall

#### 1. Become root

```bash
sudo -i
```

#### 2. Install iptables-persistent

```bash
apt install -y iptables-persistent
```

#### 3. Add the rules

NAT `192.168.24.0/24` out through `br0`, and permit forwarding between the two
bridges:

```bash
iptables -t nat -A POSTROUTING -s 192.168.24.0/24 ! -d 192.168.24.0/24 -o br0 -j MASQUERADE
```

```bash
iptables -A FORWARD -i br-kvm -o br0 -j ACCEPT
```

```bash
iptables -A FORWARD -i br0 -o br-kvm -m state --state RELATED,ESTABLISHED -j ACCEPT
```

```bash
netfilter-persistent save
```

#### 4. Read the rules back

```bash
iptables -t nat -L POSTROUTING -n -v
```

```bash
iptables -L FORWARD -n -v
```

```bash
cat /etc/iptables/rules.v4
```

**Notes**

- What this gives you: any connection a guest starts outward reaches `192.168.8.0/24` and beyond, with return traffic flowing back through connection tracking. No extra rule is needed for that direction.
- What it does **not** give you: a device on `192.168.8.0/24` cannot open a new connection into a guest's `192.168.24.x` address. That needs an explicit DNAT rule per exposed service, for example forwarding TCP 2222 on this host's LAN address to SSH on one guest:

```bash
iptables -t nat -A PREROUTING -i br0 -p tcp --dport 2222 -j DNAT --to-destination 192.168.24.10:22
iptables -A FORWARD -i br0 -o br-kvm -p tcp -d 192.168.24.10 --dport 22 -j ACCEPT
netfilter-persistent save
```

- `iptables -A` appends. Running this step twice adds a second copy of each rule. They are harmless but confusing; `iptables -t nat -L POSTROUTING -n -v` shows the duplicates, and `netfilter-persistent save` then writes both.
- That `netfilter-persistent save` exited cleanly is not proof the rules survive a reboot. Step 11 checks them after the boot.

### Step 11 — Reboot and final verification

Nested virtualization's module option, the whole of Step 8's passthrough work,
and the bridges' autoconnect all need this one boot to take hold together. The
quota from Step 3 is already live.

#### 1. Reboot

```bash
systemctl reboot
```

#### 2. Boot fundamentals

```bash
swapon --show
```

Expect no output.

#### 3. IOMMU is active

```bash
dmesg | grep -iE "AMD-Vi|DMAR|IOMMU"
```

#### 4. The GPU is in its own group

```bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/}; n=${n%%/*}
  printf 'IOMMU Group %s ' "$n"; lspci -nns "${d##*/}"
done | grep -i vga -A1
```

#### 5. The GPU is bound to vfio-pci

```bash
lsmod | grep nouveau
```

Expect no output.

```bash
lspci -nnk | grep -i nvidia -A3
```

Expect `Kernel driver in use: vfio-pci` on the GPU and on its audio function.

```bash
dmesg | grep -i vfio
```

Expect probe and bind messages for the GPU's PCI address.

#### 6. The bridges came up on their own

```bash
ip -br addr show br0 br-kvm
```

Expect `br0` on `192.168.8.3/24` and `br-kvm` on `192.168.24.1/24`.

```bash
ping -c4 192.168.8.1
```

#### 7. The firewall survived the reboot

```bash
iptables -t nat -L POSTROUTING -n -v
```

```bash
iptables -L FORWARD -n -v
```

#### 8. Nested virtualization and quota persisted

```bash
cat /sys/module/kvm_amd/parameters/nested
```

Expect `1` or `Y`.

```bash
xfs_quota -x -c 'state' /data-root
```

```bash
xfs_quota -x -c 'state' /data-root/sssd
```

```bash
xfs_quota -x -c 'state' /data-root/lssd
```

Expect `Accounting: ON` and `Enforcement: ON` on all three.

#### 9. Functional tests

A guest on the `sssd` pool:

```bash
virsh vol-create-as sssd-pool <vm-name>.qcow2 20G --format qcow2
```

```bash
virt-install --name <vm-name> --memory 4096 --vcpus 2 \
  --disk vol=sssd-pool/<vm-name>.qcow2 --network bridge=br-kvm \
  --os-variant debian13 --cdrom /data-root/isos/debian-13-netinst.iso
```

Docker quota enforcement:

```bash
docker run --rm --storage-opt size=5G alpine df -h /
```

Cross-subnet reachability, run from inside a guest on `br-kvm`:

```bash
ping -c3 192.168.8.3
```

GPU passthrough — attach the card to a VM by its PCI address in the domain XML,
then:

```bash
virsh start <gpu-vm-name>
```

```bash
virsh domdisplay <gpu-vm-name>
```

**Notes**

- Verification is gathered here rather than spread through Steps 8 to 10 because every one of those changes only takes effect on this boot. Checking them earlier reports the state before the change, which reads as a pass and is not one.
- `virt-install` with `--cdrom` expects a console. Add `--noautoconsole` and connect afterwards with `virsh console <vm-name>`, or run it from a `tmux` session, since there is no display on this host.
- If `lspci -nnk` shows `nouveau` or `nvidia` in use rather than `vfio-pci`, the blacklist did not take. Check that `update-initramfs` ran after the file was written in Step 8.
