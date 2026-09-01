# Hephaestus — Intel Core i5-12400, Debian 13 "trixie" headless KVM host

Hostname `Hephaestus`. Purely headless: base system and `openssh-server` only, no
desktop environment, administered over SSH. The other hosts are
[Dionysus.md](../Dionysus/Dionysus.md), the Ryzen 9 3900X KVM host, and
[Silenus.md](../Silenus/Silenus.md), the ThinkPad workstation.

ASUS PRIME H610M-A WIFI, Intel Core i5-12400 (6c/12t), 31 GiB RAM, no discrete
GPU to hand to a guest — the one step this build drops against Dionysus — and
two network interfaces, onboard WiFi and onboard ethernet. Two disks, sizes as
`lsblk` reports them:

| Role | Device | Model | Size |
|---|---|---|---|
| OS and Docker `data-root` | `nvme0n1` | Samsung SSD 970 EVO Plus 250GB | 232.9 GiB |
| `lssd` — VM disks and Docker volumes | `sda` | Samsung SSD 870 EVO 2TB | 1.8 TiB |

No swap partition and no swapfile anywhere in this build.

> **A personal build record, published for ideas.** This is how one specific
> machine was actually built — its hardware, its disks, its addresses. It is not
> a general Debian guide, and the values in it are not defaults to copy: they
> are what this box needed on the day. The reasoning in the Notes blocks travels
> to other hardware; the numbers do not, so check each one against your own
> before you run the block. [The master README](../README.md) covers what all
> three hosts share.

Every step here can be run again without harm. Files are written whole rather
than appended to, package installs skip what is present, and group membership
is unchanged when it is already granted. The single exception is `visudo` in
Step 3, which is a manual edit and is noted there.

**When something needs changing, change it here and re-run the step — never
patch the machine by hand.** A `sed` against a file this document writes leaves
the machine and the document disagreeing, and nothing will tell you which is
right. Every block is written to be run again.

## Part 1 — OS installation

### Step 1 — BIOS: Secure Boot and virtualization

ASUS PRIME H610M-A WIFI.

The same settings as Dionysus, including the ones passthrough would need. Every
host in this estate leaves the BIOS in the same state, so a machine that later
gains a card needs no trip back into firmware.

| # | Step | How |
|---|------|-----|
| 1 | Enter BIOS | Power off fully, power on, tap **Del** at the ASUS splash |
| 2 | Leave EZ Mode | **F7** switches to Advanced Mode, where everything below lives |
| 3 | Note BIOS version | `Main` tab — write it down before changing anything |
| 4 | Secure Boot | `Boot → Secure Boot → OS Type` = **Windows UEFI mode** |
| 5 | Enable VT-x | `Advanced → CPU Configuration → Intel (VMX) Virtualization Technology` = **Enabled** |
| 6 | Enable VT-d | `Advanced → System Agent (SA) Configuration → VT-d` = **Enabled** |
| 7 | Above 4G Decoding | `Advanced → PCI Subsystem Settings → Above 4G Decoding` = **Enabled**, if the board exposes it |
| 8 | Resizable BAR | Same menu, `Re-Size BAR Support` = **Auto**, if present |
| 9 | Save and exit | **F10** → **Yes** |
| 10 | Boot the installer | **F8** at the splash, pick the USB device |

**Notes**

- The menu paths are ASUS's LGA1700 convention. Confirm each on screen rather than trusting the path: a BIOS update can move a setting between `Advanced` and a chipset submenu without renaming it.
- **H610 is a budget chipset, and rows 7 and 8 may simply not exist on it.** Above 4G Decoding and Re-Size BAR are commonly cut from H610 firmware. Neither is used by this build — there is no card to pass through — so a board that does not offer them is not a fault and needs no workaround. Set them if they are there and move on if they are not.
- VT-x and VT-d can be read back from the running system instead of a reboot: `grep -c vmx /proc/cpuinfo` above 0 means VT-x is on, and `ls /sys/class/iommu/` listing anything means VT-d is on and the kernel picked it up.
- Debian's bootloader is signed by Microsoft's 3rd party UEFI CA. The key set has to include it or the machine will not boot and shows `Invalid signature detected`. On ASUS boards the switch is `OS Type` = **Windows UEFI mode**; other vendors name it after the CA directly.
- **The IOMMU lines are set even though nothing here uses them.** They cost nothing when idle, and the alternative is a trip back into firmware — on a machine at another site — the day this host is given a card. What is absent is the *operating system* side of passthrough: no `amd_iommu=on` on the kernel command line, no `vfio-pci` binding, no driver blacklist, no `vfio` in the initramfs. Dionysus.md Step 9 is where that lives if it is ever wanted here.
- Turning the 3rd party CA on may switch `Secure Boot Mode` from `Standard` to `Custom`. That is expected. Custom only means the key set is no longer the factory default; Secure Boot still checks every signature.
- Never use `Reset to Setup Mode` or `Clear All Secure Boot Keys`. They cause the boot failure above and Debian does not need them.
- There is no swap anywhere in this build, so the hibernation caveat that applies to Silenus does not arise.

### Step 2 — Disk partitioning

Choose **Manual** partitioning. `partman` supports XFS natively, so the layout
is created at install time rather than rebuilt afterwards. The installer counts
in decimal, so `MB` means 1,000,000 bytes. Type the **Enter as** value. The
installer will then display the **Shows as** value.

**NVMe 250 GB (`nvme0n1`) — 232.9 GiB**

| # | Partition | Size | Enter as | Shows as | Format | Mount |
|---|-----------|------|----------|----------|--------|-------|
| 1 | EFI | 1 GiB | `1075 MB` | 1.1 GB | EFI System Partition | `/boot/efi` |
| 2 | Boot | 2 GiB | `2147 MB` | 2.1 GB | ext4 | `/boot` |
| 3 | Root | 32 GiB | `34360 MB` | 34.4 GB | ext4 | `/` |
| 4 | Data | 192 GiB | `206158 MB` | 206.2 GB | xfs | `/data-root` |

**SATA 2 TB (`sda`) — 1.8 TiB**

| # | Partition | Size | Enter as | Shows as | Format | Mount |
|---|-----------|------|----------|----------|--------|-------|
| 1 | lssd | whole disk | `max` | about 2.0 TB | xfs | `/data-root/lssd` |

**Hostname and network, during the install**

| Field | Value |
|---|---|
| Interface | the onboard WiFi, `wlp2s0` — the installer asks for the network and its key |
| Addressing | DHCP. The work network hands out addresses; `192.168.88.212` is what it has been giving this machine |
| Hostname | `hephaestus` |
| Domain | leave empty |

Package selection: base system and `openssh-server` only. Deselect the desktop
environment task; this host stays headless.

**Notes**

- The OS disk here is the NVMe and the bulk disk is the SATA drive, which is the reverse of Dionysus. The four sizes on `nvme0n1` are identical to Dionysus's `sda` because the two disks are the same size, so the same numbers apply unchanged.
- The four partitions on `nvme0n1` come to 227 GiB of the 232.9 the disk reports, leaving about 5.9 GiB unpartitioned as SSD over-provisioning — the drive uses it for wear levelling, which keeps write speed up as it fills.
- `sda` takes the whole disk with `max` and keeps no such margin, which is the one deliberate difference from how Dionysus treats its bulk disks. It **is** an SSD — a Samsung 870 EVO 2TB, `lsblk -d -o NAME,ROTA` reports `0` — so the same over-provisioning argument that reserves 5.9 GiB on `nvme0n1` applies to it in principle. It was not applied: the disk is bulk storage for VM images and Docker volumes, 2 TB is far more than this host will fill, and an SSD kept well below capacity has enough unwritten blocks to wear-level with regardless. If it ever does run close to full, reclaiming 4% is worth more than the capacity, and that means reformatting — see the Notes in Step 3 for what a reformat has to fix in `/etc/fstab`.
- There is one bulk disk here where Dionysus has two, so there is one pool rather than two. `sssd` does not exist on this host; anything Dionysus would put there goes on `lssd`.
- The installer counts in GB, `df -h` counts in GiB. The root partition is entered as `34360 MB`, shows as `34.4 GB`, and reports as `32G` once installed. Same partition.
- For any other size: type `GiB x 1073.741824` MB, rounded. The EFI partition is entered as `1075 MB` rather than the 1074 the formula gives; that is the number the other two hosts use for the same partition, and one megabyte over makes no difference.
- Installing over WiFi means the installer needs the network name and key. If it cannot see the adapter at all, the firmware is missing: use the Debian installer image that includes non-free firmware.
- Without a working network the installer cannot reach the mirror, and Steps 3 to 8 have nothing to install from.
- No swap partition. Omit it from the table entirely rather than adding one and disabling it later. The installer warns that no swap space is selected; continue.
- XFS project quota (`pquota`/`prjquota`) is the one thing `partman`'s mount-options list does not expose. It is added to `/etc/fstab` after first boot, in Step 3.

### Step 3 — After install: repositories, quota, checks

#### 1. Become root

Everything in this step is run as root.

```bash
su -
```

#### 2. Install vim and sudo

```bash
apt update
```

```bash
apt install -y vim sudo
```

`visudo`, used in the next sub-step, comes from the `sudo` package rather than
from vim. The installer only installs `sudo` when the root password is left
empty; setting one leaves the package out altogether, and `visudo` reports
`command not found`.

Make vim the default editor for `visudo` and friends:

```bash
update-alternatives --config editor
```

#### 3. Add your user to sudoers

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

```bash
grep ^deb /etc/apt/sources.list
```

#### 5. Update the system

```bash
apt full-upgrade
```

#### 6. Install the tools used for checking

```bash
apt install -y mokutil dmidecode efibootmgr
```

#### 7. Confirm ftype on both XFS filesystems

A hard requirement for both `overlay2` and project quotas. `partman`'s defaults
are not guaranteed to match a manual `mkfs.xfs`, so check rather than assume:

```bash
xfs_info /data-root      | grep ftype
```

```bash
xfs_info /data-root/lssd | grep ftype
```

Expect `ftype=1` on both.

`xfs_info: cannot open /data-root/...: Is a directory` does not mean the path is
missing. It means that path is not an XFS mount, so `xfs_info` fell through to
treating the argument as a device file. The usual cause is the wrong filesystem
type being picked for that partition in the installer — the next sub-step names
it outright.

#### 8. Confirm what the installer mounted

```bash
findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS /data-root /data-root/lssd
```

Both must read `xfs`. Anything else has to be reformatted before going on: the
project quota this build rests on is an XFS feature, and Docker's
`--storage-opt size=` rests on the quota.

#### 9. Add project quota to fstab

```bash
vim /etc/fstab
```

Append `,pquota` immediately after `defaults` in the options field of those two
XFS entries. Leave every other line alone.

#### 10. Edit GRUB: the boot console

```bash
vim /etc/default/grub
```

These five lines are the whole active configuration. Make the uncommented lines
in the file read exactly this, and leave every commented line below them alone:

```
GRUB_DEFAULT=0
GRUB_TIMEOUT=9
GRUB_DISTRIBUTOR=`( . /etc/os-release && echo ${NAME} )`
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 systemd.show_status=auto udev.log_level=3"
GRUB_CMDLINE_LINUX=""
```

```bash
update-grub
```

#### 11. Reboot

```bash
systemctl reboot
```

This reboot is what makes the quota live. XFS initializes project quota on an
actual mount and refuses to do it on a remount, and every filesystem is mounted
fresh here — so no unmount and remount sequence is needed.

Log back in and become root again before the checks:

```bash
sudo -i
```

#### 12. Check Secure Boot

```bash
mokutil --sb-state
```

Expect `SecureBoot enabled`.

#### 13. Check the machine booted through shim

```bash
efibootmgr -v | grep -i shim
```

#### 14. Check the disks

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

Expect `1023M`, `2G`, `32G` and `192G` on `nvme0n1`, and one XFS partition
filling `sda`.

```bash
swapon --show
```

Expect no output.

#### 15. Check the quota is active

```bash
xfs_quota -x -c 'state' /data-root
```

```bash
xfs_quota -x -c 'state' /data-root/lssd
```

Expect `Accounting: ON` and `Enforcement: ON` on both.

#### 16. Check the BIOS version

```bash
dmidecode -s bios-version
```

Compare with what you wrote down in Step 1.

**Notes**

- `GRUB_CMDLINE_LINUX_DEFAULT` carries only the boot-console settings here. Dionysus adds `amd_iommu=on iommu=pt vfio-pci.disable_idle_d3=1` for passthrough. The BIOS has the IOMMU on either way — Step 1 sets the same firmware state on every host — but the kernel is not told to use it, because nothing here does.
- `GRUB_CMDLINE_LINUX` is empty, as on Dionysus and unlike Silenus. Silenus needs `rootflags=uquota,pquota` because its root filesystem is XFS with quota and root is mounted before `/etc/fstab` is read. Here root is ext4 and the quota is on ordinary fstab mounts, so fstab is the right place.
- A partition created as the wrong type is worth catching here rather than by its symptoms later. `lost+found` in the root of a mount is a good tell: ext4 creates it, XFS never does. So is a gap between `Size` and `Avail` in `df` on an almost-empty filesystem — ext4 reserves 5% of its blocks for root, XFS reserves none.
- Reformatting one of these is cheap while they are empty: `umount`, `mkfs.xfs -f <device>`, then fix `/etc/fstab`. `mkfs.xfs` writes a **new UUID**, so the `UUID=` in fstab has to be replaced with `blkid -s UUID -o value <device>` — left stale, the next boot waits for a device that no longer exists. Set the type to `xfs` and the fsck pass to `0` in the same edit: XFS has no boot-time fsck, and a pass of `2` makes it fail on every boot.
- Use `state`, not `report -p`. With no projects assigned yet, `report -p` prints nothing whether quota is on or off, which hides exactly the failure this check exists to catch.
- The kernel renames the options: `pquota` shows as `prjquota` in `findmnt`.
- If a `umount` reports the target is busy, `fuser -m /data-root` names the process holding it.

The installation is done.

## Part 2 — Configuration

### Step 4 — Firmware updates

Everything on this machine that publishes firmware to LVFS can be updated from
Linux. The motherboard is the exception and is handled separately, in the notes.

#### 1. Become root

```bash
sudo -i
```

#### 2. Install fwupd

```bash
apt install -y fwupd fwupd-amd64-signed
```

#### 3. Refresh the firmware list

```bash
fwupdmgr refresh --force
```

#### 4. See what the machine has

```bash
fwupdmgr get-devices
```

#### 5. See what is available

```bash
fwupdmgr get-updates
```

#### 6. Apply

```bash
fwupdmgr update
```

#### 7. Reboot to apply

```bash
systemctl reboot
```

Log back in and become root again before continuing:

```bash
sudo -i
```

#### 8. Check nothing is left

```bash
fwupdmgr get-updates
```

The last line must read `No updates available`. If it does not, repeat from the
Apply sub-step.

#### 9. Check Secure Boot survived

```bash
mokutil --sb-state
```

Expect `SecureBoot enabled`.

**Notes**

- `fwupd-amd64-signed` holds the Debian-signed EFI file. Without it firmware updates stop working once Secure Boot is on, which it is on this host.
- Never power off during a firmware update.
- Firmware is written during the reboot, not by `fwupdmgr update`. Apply, reboot and re-check are one round. Repeat until the check is clean.
- `Devices with no available firmware updates` and `Devices with the latest available firmware version` both mean nothing to do. Only the last line decides.
- **This is a desktop board, not a Lenovo laptop, and that changes what to expect.** Lenovo publishes to LVFS, which is why Silenus updates its BIOS this way. ASUS does not generally publish consumer motherboard firmware there, so do not be surprised if the PRIME H610M-A WIFI itself never appears in `get-devices`. Its BIOS is updated from the firmware's own **EZ Flash** utility, with the `.CAP` file on a FAT32 USB stick. Verify against ASUS's own support page rather than assuming either way.
- The NVMe and SATA disks may or may not appear. Samsung consumer drives are largely absent from LVFS; `fwupdmgr get-devices` is the honest answer for this machine, not a list written in advance.
- The AC-power caveat that applies to Silenus does not apply here. This machine has no battery, so nothing is skipped for want of mains power.
- A BIOS update resets BIOS settings on many boards, `Intel VT-x` and `VT-d` included. After one, redo Step 1 and re-run the checks in Step 3.

### Step 5 — Packages

#### 1. Become root

```bash
sudo -i
```

#### 2. Install the packages

```bash
apt install -y bash-completion bridge-utils btop curl git iptables iputils-ping jq lshw make network-manager openssl pciutils progress pwgen python3 rsync sshuttle sudo tmux tree unrar vim wget
```

#### 3. Check the CPU exposes virtualization

```bash
grep -Ec '(vmx|svm)' /proc/cpuinfo
```

Expect a number above 0.

**Notes**

- This is Silenus's package list with everything desktop-only removed: no GNOME, no flatpak, no fonts, no media applications, none of which has anything to talk to on a headless host. It is identical to Dionysus's.
- Claude Code is not installed here, though Silenus has it. It is a developer tool for the machine you work at; a server has no use for it, and its repository and signing key are two more things to keep trusted for no return.
- `bash-completion`, `python3` and `openssl` are here because `install.sh` in Step 6 checks for them and warns if they are missing.
- `network-manager` is here because a headless Debian install does not have it. It arrives on a desktop machine as a dependency of `gnome-core`; no task a base install selects pulls it in. Step 9 needs `nmcli`, so it is installed with everything else rather than in the middle of reconfiguring the network.
- `iptables` makes libvirt's choice deterministic. `/etc/libvirt/network.conf` documents the default as the first available of `[iptables, nftables]`, and `libvirt-daemon-system` depends on neither, so the backend would otherwise be decided by whatever else happened to pull one in. Step 10 reads libvirt's `LIBVIRT_FWI` chain with `iptables`; under the nftables backend that chain does not exist.
- `pciutils` supplies `lspci`. There is no passthrough here, but it is what identifies the WiFi and ethernet controllers when firmware is missing.

### Step 6 — Bash, tmux, and SSH configuration

#### 1. Leave the root shell

Step 5 ended as root. Everything in this step runs as your own user, the clone
included — a repository cloned by root lands in `/root`, which is mode `0700`,
so your account could not even read it afterwards.

```bash
exit
```

#### 2. Get the repository onto this machine

```bash
git clone https://github.com/bahman-farhadian/linux_terminal_dotfiles_configuration.git ~/dotfiles
```

```bash
cd ~/dotfiles/Hephaestus
```

Keep it. `install.sh` needs the directory to re-run, and Step 7 reads
`kvm/static_network_40.xml` from it.

#### 3. Run the installer

```bash
./install.sh
```

#### 4. Reload the shell

```bash
exec bash
```

**Notes**

- Cloned over HTTPS, not SSH. A freshly installed machine has no key registered with GitHub yet, and the SSH URL would fail at exactly this step — the one that installs the SSH configuration. HTTPS needs no credentials to read a public repository. If the repository is private, either clone it once over HTTPS with a personal access token or add this host's key to GitHub first.
- `Hephaestus/install.sh` is byte-identical to `Dionysus/install.sh` apart from its header comment, and `bash/`, `tmux/`, `ssh/` and `hushlogin` are byte-identical copies. It carries no keyboard-lock service, no GNOME shortcuts and no GTK3 dark setting, because none of them has a session to act on here.
- It asks once whether to configure `root` as well. Answer `y`. The answer is recorded in `/etc/dotfiles-root-configured`, so every later run keeps `/root` in step.
- Safe to re-run. The SSH block is replaced between its markers, not duplicated, and your own `Host` entries outside the markers are untouched.
- It writes `/etc/ssh/banner.txt` and points sshd at it with `Banner`, so the notice is shown **before authentication** and to **every account**. That is the only place that works, because `~/.hushlogin` — which these dotfiles also install — suppresses the motd for any account that has one.
- `/etc/motd` is emptied and `/etc/update-motd.d/10-uname` has its execute bit dropped, which removes Debian's licence paragraphs and the kernel line.
- It writes `/etc/ssh/sshd_config.d/99-local.conf` so root can only reach SSH with a key, never a password. **On this host, open a second session and confirm it works before closing the first.** It is at another site and reached over WiFi; there is no console to fall back on.
- Every SSH login is offered a tmux session of its own, `ssh1`, `ssh2` and so on, for whichever account is connecting. It asks the way `apt` does — `Start tmux session ssh1? [Y/n]`, Enter for yes, `n` for a plain shell — because tmux repaints the screen as it starts and would wipe the pre-authentication banner before it could be read. There is no timeout on the prompt, so the banner stays up until you answer. Two windows onto this host do not mirror each other. Reconnecting after a dropped link attaches to the session left behind rather than opening another, so work survives the drop — which matters on a host reached only over the network.
- `.bashrc` adds `/usr/local/sbin`, `/usr/sbin` and `/sbin` to your PATH, so `sysctl`, `swapon` and `iptables` resolve for a non-root user.
- Check it with `command -v sysctl`. It must print `/usr/sbin/sysctl`. If it prints nothing, the shell has not been reloaded yet.
- A command typed with a leading space is not written to the history file. Use it for anything carrying a password or a token. One space is enough.
- History is written at every prompt, not only when the shell exits. A tmux pane that is killed rather than closed keeps everything typed in it.
- It also writes `/etc/profile.d/99-history.sh` so both rules apply to every account, not only yours.
- `cpy` falls back to plain `tee` when there is no display, so it prints and copies nothing here rather than failing.
- `Hephaestus/bash/bash_aliases` drops the `DE`, `EN` and `kbd` aliases. They call `gsettings` against the GNOME input-source schema, which does not exist on this host.
- Debian packages no bash completion for `tmux`, so `install.sh` fetches one from upstream into `~/.local/share/bash-completion/completions/tmux`, and gives `/root` the same file when root is managed. It downloads to a temporary file first, so a failed fetch leaves a working copy alone instead of truncating it to nothing. Tab-completion for subcommands, session names and window names works in the next shell you open.
- `README.md` at the top of the repository covers the prompt, the tmux keys, and what changes.

### Step 7 — KVM and libvirt

#### 1. Become root

```bash
sudo -i
```

#### 2. Install the packages

```bash
apt install -y qemu-system-x86 qemu-utils ovmf virtinst libosinfo-bin osinfo-db osinfo-db-tools libvirt-daemon-system libvirt-clients libguestfs-tools cloud-image-utils acl util-linux
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

Required only for running a hypervisor inside a guest. The module is `kvm_intel`
or `kvm_amd` depending on the CPU, so read it from the machine rather than
choosing:

```bash
KVM_MOD=$(ls /sys/module | grep -E '^kvm_(intel|amd)$'); echo "$KVM_MOD"
```

```bash
cat /sys/module/$KVM_MOD/parameters/nested
```

`Y` on Intel or `1` on AMD means it is already on — skip the rest of this
sub-step. Otherwise:

```bash
echo "options $KVM_MOD nested=1" > /etc/modprobe.d/$KVM_MOD.conf
```

```bash
modprobe -r $KVM_MOD && modprobe $KVM_MOD
```

```bash
cat /sys/module/$KVM_MOD/parameters/nested
```

#### 5. Raise the open file limit

```bash
vim /etc/security/limits.d/99-kvm.conf
```

Put this in it:

```
*    soft    nofile    65536
*    hard    nofile    1048576
```

#### 6. Define the storage pool

One bulk disk here, so one pool:

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

Expect `lssd-pool` active with autostart `yes`.

#### 7. Remove the default NAT network

`libvirtd` creates a `default` NAT network on install, typically
`192.168.122.0/24`, with its own DHCP server. This host uses one network only,
so it is removed rather than left stopped:

```bash
virsh net-destroy default
```

```bash
virsh net-undefine default
```

#### 8. Define the one network this host uses

`sudo -i` in sub-step 1 left you in `/root`, so go back to the host directory
first — this path is relative to it:

```bash
cd ~<your-user>/dotfiles/Hephaestus
```

```bash
virsh net-define kvm/static_network_40.xml
```

```bash
virsh net-start static_network_40
```

```bash
virsh net-autostart static_network_40
```

```bash
virsh net-list --all
```

Expect `static_network_40` active with `Autostart yes`, and no `default`.

```bash
ip -br addr show virbr1
```

Expect `192.168.40.1/24`.

#### 9. Leave the root shell

```bash
exit
```

#### 10. Add your user to the libvirt and kvm groups

```bash
sudo usermod -aG libvirt,kvm $USER
```

Log out and log back in, then check:

```bash
groups
```

**Notes**

- There is no `qemu-kvm` package in trixie. `qemu-system-x86` provides the emulator, and KVM itself is a kernel module already present. An install line naming `qemu-kvm` fails outright with no candidate.
- `cloud-image-utils` supplies `cloud-localds`, which builds the small seed ISO a cloud image reads its `user-data` and `meta-data` from. A distribution cloud image booted without one comes up with no account you can log into, since the image ships no password and expects cloud-init to create the user.
- `acl` supplies `setfacl` and `getfacl`, for granting the `libvirt-qemu` user access to a pool directory without changing the ownership of what is inside it. That applies to every pool in this build, since none of them lives under `/var/lib/libvirt`.
- `util-linux` is Essential on Debian and is therefore already installed. It is named anyway so the dependency on `lsblk`, `blkid` and `mount` is written down rather than assumed — naming it costs nothing and `apt` treats it as satisfied.
- `virt-manager` is not installed. Drive this host from Silenus with `virt-manager -c qemu+ssh://hephaestus/system`, or use `virsh`.
- **Always name a pool when creating a guest.** libvirt keeps a `default` storage pool pointing at `/var/lib/libvirt/images`, on the 32 GiB root filesystem, and `virt-install` uses it silently when `--disk` names no pool. It is not removed here because `virt-manager` recreates it on connect; `--disk vol=lssd-pool/<name>.qcow2` is the habit that avoids it.
- The `usermod` sub-step has to run as your own user. Under `sudo` as root, `$USER` is `root`, so the groups would go to the wrong account.
- Run as an ordinary user, `virsh` defaults to `qemu:///session`, a per-user hypervisor with no networks and no machines. The system VMs are on `qemu:///system`. Set `LIBVIRT_DEFAULT_URI=qemu:///system` if you would rather not type it.
- `modprobe -r` fails if a virtual machine is running. Shut them down first.
- The packaged `osinfo-db` is the maintained source, refreshed by `apt upgrade`. Do not use `osinfo-db-import --latest`: it fetches from a third-party host libosinfo's own maintainers have flagged as unreliable.
- `net-define` reads the file at define time and stores a copy of its own, so editing the repository file later means running `net-define` again.

### Step 8 — Docker

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

#### 7. Point data-root at the NVMe data partition

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

- Two storage tiers by design. **Capped**, on `nvme0n1p4`: image layers and small containers sit on `/data-root` directly, bounded per container with `--storage-opt size=`. **Uncapped**, bind-mounted: anything needing real bulk — databases, local models — mounts explicitly into `/data-root/lssd` on the SATA SSD and is not subject to the `data-root` cap.
- An uncapped container looks like `docker run -d --name <name> -v /data-root/lssd/<volume>:/data <image>`.
- Docker now defaults to the containerd snapshotter, which reports itself as `overlayfs` and does not implement `--storage-opt size=`. It accepts the flag and ignores it, so a container silently gets the whole disk. Turning the snapshotter off is what makes the XFS project quota from Step 3 apply.
- `--storage-opt size=` works only on `overlay2` over XFS with project quota. It is not supported on ext4, and not by the containerd snapshotter.
- Switching the driver hides images pulled under the previous one. They are not deleted, but they live in a separate store. Pull them again if anything is missing.
- Debian's `docker.io` and `podman-docker` conflict with Docker Engine. If either was installed earlier, remove it before installing the engine.
- Adding your user to the `docker` group must run as your own user, not root.
- Membership in the `docker` group is equivalent to root. Any member can start a container that mounts the whole filesystem. Treat it as an admin privilege, not a convenience.
- `Suites: trixie` is written out rather than derived from `/etc/os-release`, so the file says which release it is pinned to. Change it when the machine is upgraded.
- `--rm` deletes the container when it exits, so these checks leave nothing behind.

### Step 9 — Networking

Two interfaces. Guests are on neither: they live on the libvirt network defined
in Step 7, and libvirt owns that bridge.

| Interface | Kind | Address | Purpose |
|---|---|---|---|
| `wlp2s0` | onboard WiFi | `192.168.88.212/24` | `wan` — the way out |
| `eno1` | onboard ethernet | `192.168.124.5/30` | point-to-point to Silenus |

Persisted through NetworkManager's own connection profiles with `nmcli`, not
`/etc/network/interfaces`.

```mermaid
graph TB
    INET(("Internet"))
    AP["WiFi network<br/>192.168.88.0/24"]
    INET --- AP

    subgraph HEP ["Hephaestus"]
        HW["wlp2s0 &middot; WiFi<br/>connection: wan<br/>192.168.88.212/24"]
        HE["eno1 &middot; onboard ethernet<br/>connection: Hephaestus<br/>192.168.124.5/30"]
        HB["virbr1 &middot; static_network_40<br/>192.168.40.1/24 &middot; NAT"]
        HG["guests<br/>192.168.40.2 &ndash; .254<br/>static, no DHCP"]
        HB --- HG
    end

    SIL["Silenus<br/>192.168.124.6/30"]
    AP -.-|WiFi| HW
    HE ===|ethernet cable| SIL

    classDef wan fill:#1f6feb,stroke:#0b4fc0,color:#ffffff
    classDef p2p fill:#8957e5,stroke:#6a3fbf,color:#ffffff
    classDef guest fill:#2da44e,stroke:#1a7f37,color:#ffffff
    classDef infra fill:#57606a,stroke:#424a53,color:#ffffff
    class HW wan
    class HE p2p
    class HB,HG guest
    class AP,INET infra
    class SIL p2p
```

Blue is this host's way out, purple the point-to-point link to Silenus, green
the guest network it NATs behind itself. The dotted line is wireless; the solid
one is the cable, which is only connected when Silenus is on site.

The guest subnet is `192.168.40.0/24` here, against `192.168.24.0/24` on Silenus
and `192.168.32.0/24` on Dionysus. All three differ on purpose: the hosts can
reach one another, so overlapping guest ranges would make a guest on one
indistinguishable from a guest on another.


#### 1. Become root

```bash
sudo -i
```

#### 2. Confirm NetworkManager is running

```bash
systemctl enable --now NetworkManager
```

```bash
systemctl is-active NetworkManager
```

#### 3. Confirm the interface names

```bash
ip -br link
```

Both `wlp2s0` and `eno1` are fixed by their hardware paths and need no renaming.
Dionysus renames its second interface only because a USB adapter arrives as
`enx` followed by its MAC address; both of these are onboard.

#### 4. Take WiFi back from ifupdown

Installing over WiFi writes the SSID and key into `/etc/network/interfaces`, so
the installed system comes up on the network it was installed over. That stanza
starts a `wpa_supplicant` of ifupdown's own on `wlp2s0`, and that instance holds
the interface. NetworkManager's supplicant then cannot take it:

```
device (wlp2s0): Couldn't initialize supplicant interface:
    wpa_supplicant couldn't grab this interface
device (wlp2s0): supplicant interface keeps failing, giving up
```

Back the file up and cut it down to loopback:

```bash
cp -a /etc/network/interfaces /etc/network/interfaces.bak.$(date +%F-%H%M%S)
```

```bash
cat > /etc/network/interfaces <<'EOF'
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback
EOF
```

Removing the stanza is not enough on a running system — the supplicant it
started stays up until it is killed:

```bash
ifdown wlp2s0 2>/dev/null; pkill -f 'wpa_supplicant.*wlp2s0'
```

```bash
systemctl restart wpa_supplicant && systemctl restart NetworkManager
```

```bash
nmcli -f DEVICE,TYPE,STATE,CONNECTION device status
```

`wlp2s0` must read `disconnected`, not `unavailable`, before going on.

#### 5. Configure WiFi as the way out

Nothing usable survives sub-step 4 — what the installer left was an ifupdown
stanza, never a NetworkManager profile — so `wan` is created outright. The
network name and the key are both read into variables, so neither is typed into
a command and neither reaches the shell history or this file:

```bash
read -rp  'WiFi SSID: ' WIFI_SSID
read -rsp 'WiFi PSK:  ' WIFI_PSK; echo
```

The SSID is echoed back as you type it; the key is not, so the second prompt
looks as though it did nothing:

```
WiFi SSID: Example-AP-5G
WiFi PSK:
```

```bash
nmcli connection add type wifi ifname wlp2s0 con-name wan ssid "$WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PSK" 802-11-wireless.cloned-mac-address permanent connection.autoconnect yes connection.autoconnect-priority 10 ipv4.method auto ipv6.method disabled
```

```bash
unset WIFI_SSID WIFI_PSK
```

```bash
nmcli con up wan
```

```bash
ip -br addr show wlp2s0
```

Expect an address on `192.168.88.0/24`. It has been `192.168.88.212`; a DHCP
lease is not a guarantee, so anything that has to reach this host by address
either wants a reservation on the work DHCP server or should use the cable.

#### 6. The point-to-point link to Silenus

`eno1` carries a cable to Silenus, on its own `/30`. No gateway and no DNS, so
it cannot compete with WiFi for the default route:

```bash
nmcli con add type ethernet ifname eno1 con-name Hephaestus ipv4.method manual ipv4.addresses 192.168.124.5/30 ipv4.never-default yes ipv6.method disabled
```

```bash
nmcli con mod Hephaestus connection.autoconnect yes
```

Silenus's own guests live on `192.168.24.0/24`, behind Silenus at the other end
of this cable. A guest here needs a route to them, or its replies leave by the
default gateway and die on the work LAN:

```bash
nmcli con mod Hephaestus +ipv4.routes "192.168.24.0/24 192.168.124.6 100"
```

```bash
nmcli con up Hephaestus
```

```bash
ip -br addr show eno1
```

Expect `192.168.124.5/30`.

Silenus takes `192.168.124.6/30` at the other end — Silenus.md Step 13. With
both up:

```bash
ping -c4 192.168.124.6
```

#### 7. Confirm

```bash
nmcli device status
```

```bash
ip -br addr show | grep -E 'wlp2s0|eno1'
```

```bash
ip -4 route
```

Exactly one default route, on `wlp2s0`.

#### 8. Enable IP forwarding

```bash
vim /etc/sysctl.d/99-kvm.conf
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

- There is no bridge built by hand for guests. Defining the guest network in libvirt — the same choice the other two hosts made — means libvirt creates and owns `virbr1`.
- Nothing is renamed on this host. Both interfaces have stable hardware-derived names already, which is exactly why Dionysus renames its USB adapter and this machine renames nothing.
- **A WiFi install always leaves ifupdown holding the adapter**, and sub-step 4 is how it is taken back. This is not the handover Dionysus needed. There the ethernet stanza only made the interface unmanaged, and `[ifupdown] managed=false` settled it. Here the stanza carries `wpa-ssid` and `wpa-psk`, so it starts a second supplicant, and the symptom is not `unmanaged` but `unavailable` alongside `NM-MANAGED: yes` — a combination that reads like a driver or firmware fault and is neither.
- The failure names the wrong device, which is the confusing part. `No suitable device found for this connection (device docker0 not available because profile is not compatible with device (mismatching interface name))` is NetworkManager reporting the last device it happened to check. `wlp2s0` is missing from that message precisely because it was never a candidate to begin with.
- The SSID and the key go in through `read` rather than being typed into the `nmcli` line. What `read` consumes arrives on stdin and is never part of a command, so neither value is written to `~/.bash_history`, and `unset` clears both from the shell afterwards. Typed inline they would sit in the history file for every later reader. A leading space suppresses that one line — these dotfiles set `HISTCONTROL=ignoreboth`, which includes `ignorespace` — but relying on a shell setting to protect a credential is thinner than never putting it on the command line at all.
- `-rp` for the SSID echoes what is typed; `-rsp` for the key does not. `-r` on both stops a backslash in either value being read as an escape.
- `802-11-wireless.cloned-mac-address permanent` is what keeps the DHCP lease stable. NetworkManager randomizes the MAC by default, a new MAC draws a new lease, and `192.168.88.212` quietly stops being the address this host answers on. `ip link` shows the randomization while it is active: a `permaddr` next to a different current address.
- The adapter is a Realtek RTL8822CE driven by `rtw_8822ce`, on the PCIe bus at `02:00.0` rather than Intel's CNVi, which is why it enumerates as `wlp2s0` and not `wlo1`. Its firmware ships in `firmware-realtek`, from the `non-free-firmware` component Step 3 sub-step 4 enables.
- `rfkill` is not installed on this host. Read the blocks from sysfs instead: `for d in /sys/class/rfkill/*; do echo "$(cat $d/name) soft=$(cat $d/soft) hard=$(cat $d/hard)"; done`.
- **The route to `192.168.24.0/24` is half of a pair.** It lets a guest here answer one on Silenus; the other half is Silenus.md Step 14, whose rules let a connection *started* here reach into that network past libvirt's `REJECT`. Either alone gives a path that works one way and reads as a routing fault.
- Reaching Dionysus's guests from here is not possible and is not configured. That host is at another site with no network path to this one, and Silenus cannot bridge them: it has one spare ethernet port, its two point-to-point profiles are mutually exclusive, and it is never at both sites at once. Guest-to-guest across sites is an SSH hop, not a route.
- The two point-to-point links do not overlap. Silenus reaches Dionysus on `192.168.124.0/30` — hosts `.1` and `.2` — and this machine on `192.168.124.4/30` — hosts `.5` and `.6`. Adjacent `/30`s out of the same `/29`, deliberately, so one range covers every point-to-point link in the estate without any two colliding.
- `wan` takes its address by DHCP, which is the one place this host differs from the other two — both of those are static because their router hands out nothing. A lease can change, so the cable at `192.168.124.5` is the address to rely on, and Silenus reaches the guest network across it first for exactly that reason.
- The cable is the second way in when WiFi fails, which matters more here than on Dionysus: this machine is at another site and has no console you can walk to. Bring `Hephaestus` up before touching `wan`, and make any change to `wan` from a `tmux` session so a dropped connection does not leave a command half-done.
- Silenus has one spare ethernet port and two point-to-point links to make with it, so it carries a profile per peer on the same interface and only one is up at a time. Neither autoconnects: a `/30` says nothing about which peer is on the far end, so both are brought up by hand there.

### Step 10 — Firewall

`libvirt` writes the rules for `static_network_40` itself when the network
starts. This step adds the one thing libvirt deliberately does not do: letting a
machine outside the guest network open a connection into it.

#### 1. Read what libvirt installed

```bash
sudo iptables -L LIBVIRT_FWI -n -v
```

The last rule is `-o virbr1 -j REJECT`. A guest reaches the outside and the
replies come back through conntrack; a connection *started* from outside matches
neither `ACCEPT` and falls to that `REJECT`. That is the gap this step closes.

#### 2. What this step adds, and what is optional

| # | Rule | Required | Why |
|---|------|----------|-----|
| 1 | `FORWARD` accept, private ranges → `192.168.40.0/24` | **yes** | without it nothing on your network can reach a guest at all |
| 2 | `DNAT` on a port to one guest | no | only to publish a guest service |

#### 3. Add the required rules, as a service

The rules have to sit **above** the jump to `LIBVIRT_FWI`. Position cannot be
saved and restored: `libvirtd` inserts its jumps at the head of `FORWARD` every
time it starts, so a saved ruleset comes back permanently below the `REJECT`.

```bash
sudo tee /usr/local/sbin/guest-net-access >/dev/null <<'EOF'
#!/bin/sh
# Let private networks open connections into the libvirt guest network.
#
# These must precede the jump to LIBVIRT_FWI, whose final rule rejects anything
# inbound to virbr1 that conntrack does not already know. libvirtd re-inserts
# its own jumps at the head of FORWARD on every start, so this deletes and
# re-inserts rather than assuming a position it once had.
set -e
for net in 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8; do
    iptables -D FORWARD -s "$net" -d 192.168.40.0/24 -o virbr1 -j ACCEPT 2>/dev/null || true
done
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    iptables -I FORWARD 1 -s "$net" -d 192.168.40.0/24 -o virbr1 -j ACCEPT
done
EOF
sudo chmod +x /usr/local/sbin/guest-net-access
sudo tee /etc/systemd/system/guest-net-access.service >/dev/null <<'EOF'
[Unit]
Description=Allow private networks into the libvirt guest network
After=libvirtd.service docker.service
Wants=libvirtd.service
PartOf=libvirtd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/guest-net-access

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now guest-net-access.service
```

#### 4. Test the rules, and their position

```bash
sudo iptables -S FORWARD
```

The three `ACCEPT` rules must come out **before** `-j LIBVIRT_FWI`. Read it, then
have the shell decide:

```bash
ours=$(sudo iptables -S FORWARD | grep -n 'd 192.168.40.0/24 -o virbr1 -j ACCEPT' | tail -1 | cut -d: -f1); libv=$(sudo iptables -S FORWARD | grep -n -- '-j LIBVIRT_FWI' | cut -d: -f1); if [ -n "$ours" ] && [ -n "$libv" ] && [ "$ours" -lt "$libv" ]; then echo "  PASS  rules precede LIBVIRT_FWI ($ours < $libv)"; else echo "  FAIL  ours=$ours libvirt=$libv"; fi
```

```bash
systemctl is-enabled guest-net-access.service
```

Expect `enabled`, so it runs again on the next boot.

**Existence is not enough, and that is the whole point of this test.**
`iptables -C` finds a rule wherever it sits and reports success, including from
below the `REJECT` that stops the packet. Only the position tells you whether
the rule does anything.

**This still tests the rules, not reachability.** Pinging a guest address proves
nothing while no guest holds that address. Reachability is what the guest note
in Step 11 covers, for when the first one exists.

#### 5. Optional — publish a guest service to the LAN

```bash
sudo apt install -y iptables-persistent
```

```bash
sudo iptables -t nat -A PREROUTING -i wlp2s0 -p tcp --dport 2222 -j DNAT --to-destination 192.168.40.10:22
```

```bash
sudo iptables -A FORWARD -i wlp2s0 -o virbr1 -p tcp -d 192.168.40.10 --dport 22 -j ACCEPT
```

```bash
sudo netfilter-persistent save
```

**Notes**

- `PartOf=libvirtd.service` is what makes a `libvirtd` restart carry this unit with it. Without it the rules stay where they were while libvirt re-inserts its jumps on top, and the host silently stops accepting connections into the guest network until the next boot.
- `-I FORWARD 1` inserts at the head. Appended with `-A`, the rules end up after `LIBVIRT_FWI` has already rejected the packet, and every existence check still passes.
- A route is still needed at the other end. These rules permit the traffic; they do not tell any machine how to get here.
- `172.16.0.0/12` includes `172.17.0.0/16`, which is `docker0`, so containers can reach guests too. Drop that range if you would rather they could not.
- `iptables-persistent` is installed only for the optional rule. The required rules do not use it, and installing it regardless means a saved snapshot of libvirt's and Docker's chains being restored at boot next to the copies those daemons rebuild.

### Step 11 — Reboot and final verification

Nested virtualization's module option and the guest network's autostart need
this boot to take hold together. The quota from Step 3 is already live.

#### 1. Reboot

```bash
systemctl reboot
```

A logged-in `root` SSH session refuses the reboot rather than performing it:

```
User root is logged in on sshd.
Please retry operation after closing inhibitors and logging out other users.
```

Log that session out and repeat, or override it:

```bash
systemctl reboot -i
```

#### 2. Boot fundamentals

```bash
swapon --show
```

Expect no output.

#### 3. Both interfaces and the guest bridge

```bash
ip -br addr show | grep -E 'wlp2s0|eno1|virbr1'
```

```bash
ip -4 route
```

Exactly one default route, on `wlp2s0`.

#### 4. The guest network came back

```bash
virsh -c qemu:///system net-list --all
```

Expect `static_network_40` active with `Autostart yes`, and no `default`.

#### 5. The firewall order survived

```bash
systemctl is-active guest-net-access.service
```

```bash
ours=$(sudo iptables -S FORWARD | grep -n 'd 192.168.40.0/24 -o virbr1 -j ACCEPT' | tail -1 | cut -d: -f1); libv=$(sudo iptables -S FORWARD | grep -n -- '-j LIBVIRT_FWI' | cut -d: -f1); if [ -n "$ours" ] && [ -n "$libv" ] && [ "$ours" -lt "$libv" ]; then echo "  PASS  $ours < $libv"; else echo "  FAIL  ours=$ours libvirt=$libv"; fi
```

This boot is the only thing that proves the ordering holds. `libvirtd` inserts
its jumps at the head of `FORWARD` when it starts, and `guest-net-access` runs
after it to put the rules back in front.

#### 6. Nested virtualization and quota persisted

```bash
KVM_MOD=$(ls /sys/module | grep -E '^kvm_(intel|amd)$'); cat /sys/module/$KVM_MOD/parameters/nested
```

```bash
sudo xfs_quota -x -c 'state' /data-root
```

```bash
sudo xfs_quota -x -c 'state' /data-root/lssd
```

Expect `Accounting: ON` and `Enforcement: ON` on both, under **Project quota
state**. The user and group sections above it read `OFF`, which is correct —
only project quota is turned on, and it is the one `--storage-opt size=` uses.

#### 7. Functional tests

The pool takes a volume and gives the space back:

```bash
virsh -c qemu:///system vol-create-as lssd-pool verify.qcow2 1G --format qcow2
```

```bash
virsh -c qemu:///system vol-list lssd-pool
```

```bash
virsh -c qemu:///system vol-delete verify.qcow2 --pool lssd-pool
```

Docker quota enforcement:

```bash
docker run --rm --storage-opt size=5G alpine df -h /
```

Expect `/` inside the container to report 5G, not the size of `/data-root`.

These two prove the pool and the quota directly. Everything else this build
rests on is asserted by `check.sh` in Step 12, which is the verification pass
proper — run it next.

**Notes**

- **Confirm the machine actually rebooted before trusting anything below.** `systemctl reboot` refuses while another user — typically a `root` shell left open from an earlier step — holds a session, and it says so rather than failing silently. Every check here then runs against the old boot and passes for the wrong reason. `uptime -p` after logging back in is the cheap way to be sure.
- Verification is gathered here because the changes in Steps 9 and 10 only take effect on this boot. Checking them earlier reports the state before the change, which reads as a pass and is not one.
- **No guest is built here.** Nothing in this document creates an install ISO or a directory to keep one in, so a `virt-install` line naming one could not be run by anyone following this guide. A guest left behind by a verification step is also debris on a machine that is otherwise reproducible end to end. The volume test proves what this step can honestly prove: the pool is active, libvirt allocates on it, and the space comes back.
- When you do build the first guest, give it a static address on `192.168.40.0/24` with gateway `192.168.40.1` — nothing hands one out. Reachability is then tested outward with `ping -c3 192.168.88.212` from inside the guest, and inward with `ping -c3 <guest-address>` from a machine holding a route to that subnet. `virt-install --cdrom` expects a console this host does not have, so add `--noautoconsole` and attach afterwards with `virsh console <vm-name>`. Name the pool explicitly — `--disk vol=lssd-pool/<name>.qcow2` — or libvirt puts the disk in the `default` pool on the 32 GiB root filesystem.
- **Reaching a guest from off-site is an SSH hop, not a route.** Silenus routes `192.168.40.0/24` across the cable when it is here, and across the work LAN when it is on that WiFi. From anywhere else — over the office VPN, from home — the way in is `ssh hephaestus` and then `ssh <guest-address>`, or `ssh -J hephaestus <guest-address>` in one line. No route over the VPN is configured on either side, deliberately: it would need a change on the office router for a path this already covers.

### Step 12 — Check the whole setup

`check.sh` in this host's directory runs every check the steps above describe
and prints `PASS` or `FAIL` for each one.

#### 1. Run it

```bash
cd ~/dotfiles/Hephaestus
```

```bash
./check.sh
```

#### 2. Read the totals

The last line gives the counts, and any failure is listed again at the end with
what the machine returned and what was wanted.

**Notes**

- Run it as your own user over SSH. It refuses to start as root, because the dotfiles, group membership and `~/.ssh/config` all live in your account.
- It asks for your sudo password once. Some checks read files only root can see, and one reads libvirt's firewall chains.
- It needs network. It pulls the `busybox` and `hello-world` images to prove the Docker storage quota is really enforced.
- It only reads. Nothing on the machine is changed, so it is safe to run at any time.
- It exits `0` when everything passes and `1` otherwise.
- This is `Hephaestus/check.sh`, not Dionysus's. It asserts this host's disk sizes, both interfaces including the WiFi `wan` profile, `static_network_40`, and that no desktop and no Claude Code are installed. It carries no GPU section, because there is no card here. Dionysus's would fail on the disks, the network and the passthrough checks, and vice versa.
- Every step from 1 to 10 has at least one assertion here, under a heading naming it. Steps 11 and 12 have none by design: Step 11 is itself a verification pass, and Step 12 is this script.
- The `eno1` checks assert the profile and its address, not that the link is up. The cable is only connected when Silenus is on site, and a check that failed whenever it was unplugged would be noise rather than signal.
