# Hephaestus — Debian 13 "trixie" headless host

Hostname `Hephaestus`. Headless: base system and `openssh-server` only, no
desktop environment, administered over SSH. The other hosts are
[Dionysus.md](../Dionysus/Dionysus.md), the Ryzen 9 3900X KVM host, and
[Silenus.md](../Silenus/Silenus.md), the ThinkPad workstation.

> **This document is an outline, not a build yet.** Every step below is present
> with its shape, its purpose and its verification, so the order is fixed and
> nothing is discovered halfway through. What is missing is this machine's own
> facts — hardware, disks, addresses, role. They are marked **TBD** throughout
> and collected in the table directly below. Fill that table first; the steps
> then follow from it.

## Facts this machine still has to supply

| # | Fact | Decides |
|---|------|---------|
| 1 | CPU vendor and model | Intel or AMD changes the nested-virtualization module (`kvm_intel` / `kvm_amd`) and the IOMMU kernel argument (`intel_iommu=on` / `amd_iommu=on`) in Steps 7 and 9 |
| 2 | RAM | Whether the open-file and hugepage limits in Step 7 need raising past the defaults |
| 3 | Disks: how many, interface, size | The whole of Step 2, and whether Step 3 manages one XFS filesystem or several |
| 4 | Role: KVM host, container host, or both | Whether Steps 7, 8 and 9 exist at all |
| 5 | ~~GPU~~ — **answered: no GPU on this host** | Step 9 does not exist here. Dionysus keeps it; this machine has nothing to pass through |
| 6 | NIC names | **Partly answered: two interfaces, one Wi-Fi and one RJ45.** Which carries management, and what the second is for, is open |
| 7 | Addresses | Your `~/.ssh/config` has `Hephaestus` at `192.168.48.2` and `Hephaestus_Outside` at `192.168.88.212`. Confirm which is the management address on this box, and whether both are on it or one is a NAT translation done elsewhere |
| 8 | Guest subnet | Silenus uses `192.168.24.0/24` and Dionysus `192.168.32.0/24`, both as libvirt networks. This host needs a third overlapping neither, or none if it runs no guests |
| 9 | Motherboard | The BIOS setup key and the exact names of the virtualization and PCIe settings in Step 1 |
| 10 | Secure Boot | Both other hosts keep it on. Expect the same here unless this board makes it awkward |

## Part 1 — OS installation

### Step 1 — BIOS

Set the firmware options the OS cannot set for itself, and record the starting
BIOS version so a later firmware update can be told apart from a BIOS reset.

- Virtualization extensions on — **TBD**: `SVM Mode` on AMD, `Intel VT-x` on Intel.
- IOMMU, `Above 4G Decoding` and `Resizable BAR` are not needed: fact 5 is answered and there is no card to pass through.
- Secure Boot per fact 10.
- **TBD**: the setup key, per fact 9.

*Verification:* none here. The kernel confirms all of it in Step 12.

### Step 2 — Disk partitioning

Manual partitioning in the installer. `partman` handles XFS natively, so the
layout is created at install time rather than rebuilt afterwards.

- **TBD**: the partition table, per fact 3. One table per physical disk, in the same shape Dionysus uses — number, partition, size, format, mount.
- No swap partition and no swapfile, matching both other hosts.
- Package selection: base system and `openssh-server` only. Deselect the desktop task.

*Verification:* `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS` shows the layout,
`swapon --show` prints nothing.

### Step 3 — After install: repositories, quota, checks

Settled and identical on every host in this repository, except where the disk
layout of fact 3 changes which filesystems are involved:

1. Become root.
2. Install `vim`, make it the default editor.
3. Add your user to sudoers with `visudo` — the one step that is not safe to repeat blindly.
4. Add `contrib` and `non-free`, handling DEB822 or the classic `sources.list`, whichever the installer wrote.
5. `apt full-upgrade`.
6. Confirm `ftype=1` on every XFS filesystem — a hard requirement for `overlay2` and project quota alike. `xfs_info: cannot open <path>: Is a directory` means that path is not XFS at all, usually a filesystem type picked wrongly in the installer.
7. Confirm what the installer actually mounted.
8. Add `,pquota` to the XFS entries in `/etc/fstab`. **TBD**: which entries, per fact 3.
9. Edit GRUB if this host needs anything on the kernel command line, then reboot. The reboot is what makes the quota live: XFS initializes project quota on a real mount and refuses on a remount, so no unmount sequence is needed.
10. `xfs_quota -x -c 'state'` on each — `Accounting: ON`, `Enforcement: ON`.

**Note carried from Dionysus:** use `state`, never `report -p`. With no projects
assigned, `report -p` prints nothing whether quota is on or off, hiding the exact
failure the check exists to catch.

**Decision recorded in Step 3, not here:** if this host puts the quota on `/`
rather than a separate data filesystem, it moves to `GRUB_CMDLINE_LINUX` as on
Silenus, because root is mounted before `/etc/fstab` is read.

The installation is done.

## Part 2 — Configuration

### Step 4 — Firmware updates

Anything on this machine that publishes to LVFS, updated from Linux with
`fwupd`. Same shape as the other two hosts: install `fwupd` and
`fwupd-amd64-signed`, `refresh --force`, `get-devices`, `get-updates`, `update`,
reboot, then re-check until `get-updates` is clean.

- `fwupd-amd64-signed` is required once Secure Boot is on, which fact 10 expects.
- Firmware is written during the reboot, not by `fwupdmgr update`, so apply and reboot are one round.
- **TBD**, per fact 9: whether this machine's board publishes to LVFS at all. Lenovo does, which is why Silenus updates its BIOS this way; ASUS largely does not, which is why Dionysus updates its board from EZ Flash instead. Check the vendor before assuming `fwupdmgr` covers it.

### Step 5 — Packages

The headless list: Silenus's with every desktop package removed. Starting point
is Dionysus's line, which is already the right shape:

```
bash-completion bridge-utils btop curl git jq lshw make network-manager openssl progress pwgen python3 rsync sshuttle sudo tmux tree unrar vim wget
```

- `bash-completion`, `python3` and `openssl` are here because `install.sh` checks for them in Step 6.
- `network-manager` is here because a headless Debian install does not have it — it arrives on a desktop as a dependency of `gnome-core`. Step 10 needs `nmcli`, so it goes in with everything else rather than in the middle of reconfiguring the network.
- `openssh-server` came from the installer and is what you are connected over.
- **TBD**: anything this machine's role adds, per fact 4.

*Verification:* `grep -Ec '(vmx|svm)' /proc/cpuinfo` above 0, if this host
virtualizes anything.

### Step 6 — Bash, tmux, and SSH configuration

**Fully settled — nothing TBD.** `Hephaestus/install.sh` is byte-identical to
`Dionysus/install.sh` apart from its header comment, and `bash/`, `tmux/`,
`ssh/` and `hushlogin` are byte-identical copies.

1. Leave the root shell.
2. `./install.sh` from `Hephaestus/`, as your own user.
3. `exec bash`.

Everything the Dionysus notes say applies unchanged: the root question is asked
once and recorded in `/etc/dotfiles-root-configured`; the SSH block is replaced
between its markers with your own `Host` entries untouched; `sysctl` and
`iptables` reach the PATH; a leading space keeps a command out of history.

**The one thing to do carefully on a host reached only over SSH:** `install.sh`
writes `/etc/ssh/sshd_config.d/99-local.conf`. Open a second session and confirm
it works before closing the first.

### Step 7 — KVM and libvirt

**Exists only if fact 4 says so.** Shape, if it does:

1. Install `qemu-system-x86 qemu-utils ovmf virtinst libosinfo-bin osinfo-db osinfo-db-tools libvirt-daemon-system libvirt-clients libguestfs-tools`. Not `qemu-kvm` — it has no candidate in trixie and the install fails outright.
2. `systemctl enable --now libvirtd.socket`. The `.service` stays inactive until something connects; that is correct, not a fault.
3. Nested virtualization — **TBD**, `kvm_intel` or `kvm_amd` per fact 1. Only needed to run a hypervisor inside a guest.
4. Open-file limits in `/etc/security/limits.d/99-kvm.conf`.
5. Storage pools — **TBD**, per fact 3.
6. Remove the `default` NAT network if this host defines its own bridge, so two NAT and DHCP setups do not compete.
7. `usermod -aG libvirt,kvm $USER`, as your own user, not under `sudo`.

`virt-manager` is not installed on a headless host. Drive it from Silenus with
`virt-manager -c qemu+ssh://hephaestus/system`, or use `virsh`.

### Step 8 — Docker

**Exists only if fact 4 says so.** Shape, if it does: Docker's own repository
rather than Debian's `docker.io`, `data-root` pointed at the data filesystem,
`overlay2` with the containerd snapshotter explicitly off, and the quota proved
by filling a container past its limit rather than by reading `df`.

- **TBD**: the `data-root` path, per fact 3.
- The snapshotter accepts `--storage-opt size=` and silently ignores it, so a container gets the whole disk. Turning it off is what makes the Step 3 quota apply.
- `docker` group membership is equivalent to root. Treat it as an admin privilege.

### Step 9 — GPU passthrough

**Exists only if fact 5 says so.** Shape, if it does: IOMMU on the kernel command
line, PCI IDs read at runtime rather than hardcoded, `vfio-pci` bound, every
competing driver blacklisted — `nouveau`, `nvidia`, `radeon`, `amdgpu`, not just
the first — and `vfio` forced into the initramfs.

- **TBD**: `intel_iommu=on` or `amd_iommu=on`, per fact 1.
- Staged only. Nothing here is verified until the reboot in Step 12.
- Appending to `/etc/initramfs-tools/modules` is not idempotent; check before repeating.

### Step 10 — Networking

NetworkManager connection profiles via `nmcli`, not `/etc/network/interfaces`.

- **TBD**: the whole address plan, per facts 6, 7 and 8.
- A management bridge with the physical NIC as its sole slave, so the host keeps one address and guests can be attached later.
- A guest bridge with no slave, no gateway and no DNS, if this host runs guests. Defined by hand rather than as a libvirt network, because libvirt rewrites its own iptables chains on restart and fights the Step 10 ruleset.
- `net.ipv4.ip_forward = 1` in `/etc/sysctl.d/`, if anything is being routed.

**Changing the address of the interface you are connected over will drop the
session.** Run it from a console or inside `tmux`, and know how to reach the box
physically first. This matters more here than on Dionysus if fact 7 turns out to
mean Hephaestus is reached from outside its own subnet.

### Step 11 — Firewall

`iptables-persistent`, only if Step 10 defined a guest subnet to NAT.

- MASQUERADE the guest subnet out through the management bridge; permit forwarding out, and back only for `RELATED,ESTABLISHED`.
- Inbound to a specific guest needs an explicit DNAT rule per exposed service; the base ruleset deliberately does not allow it.
- `iptables -A` appends, so running the step twice duplicates every rule.

### Step 12 — Reboot and final verification

One reboot, then everything staged in Steps 6, 8, 9 and 10 is confirmed
together — because each of those only takes effect on this boot, and checking
earlier reports the state before the change, which reads as a pass and is not
one.

- No swap.
- IOMMU active in `dmesg`; GPU alone in its group; `vfio-pci` bound to both card and audio function.
- Bridges up on their own via autoconnect, gateway reachable.
- Firewall ruleset survived, not merely saved without error.
- Nested virtualization and XFS quota both still on.
- Functional: a guest on a pool, a container against its size cap, cross-subnet reachability from inside a guest.

## Where this outline came from

Steps 1–3 and 6 are the same on every host here and are settled. Steps 4, 5, 7,
8, 10, 11 and 12 are the same in shape and differ only in this machine's
numbers. Step 9 is the only one that does not exist here at all, since this
machine has no GPU to hand over.

Silenus's steps that are deliberately absent: Qt and runtime libraries, the
laptop lid, VS Code extensions, and the GNOME application grid. None has
anything to act on without a desktop. Firmware is **not** in that list — it
applies to any machine and is Step 4 here, as on the other two.
`Hephaestus/bash/bash_aliases` drops the `DE`, `EN` and `kbd` aliases for the
desktop reason.

Still missing from this directory: a `check.sh`. Silenus has
one. Writing it needs the facts table above, since almost every assertion in it
is a number this machine has not supplied yet.
