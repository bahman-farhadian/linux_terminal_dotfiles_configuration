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
| 7 | Boot the installer | **F12** at the splash, pick the USB device |

**Notes**

- Debian's bootloader is signed by Microsoft's 3rd party UEFI CA. With this **Off** the machine will not boot and shows `Invalid signature detected`.
- Leave `Secure Boot` **On** for the whole install.
- Never use `Reset to Setup Mode` or `Clear All Secure Boot Keys`. They cause the failure above and Debian does not need them.

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

- Leave the rest of the disk unpartitioned. That free space is SSD over-provisioning: 953.87 GiB disk, minus 3 GiB for EFI and boot, minus 888 GiB for root, leaves 62.87 GiB. The drive uses it for wear levelling, which keeps write speed up as the disk fills.
- The installer counts in GB, `df -h` counts in GiB. Root shows as `953.5 GB` here and `888G` later. Same partition.
- For any other size: type `GiB x 1073.741824` MB, rounded.
- The EFI partition may still come out as `1023M`. That is harmless.
- No swap partition. Only hibernation needs one, and hibernation does not work while Secure Boot is on.
- The installer warns that no swap space is selected. Continue.

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

- If step 9 says `SecureBoot disabled`, the `Secure Boot` toggle is Off in the BIOS. Turn it back on.
- Hibernation does not work while Secure Boot is on. The kernel refuses to write the resume image because it cannot verify the swap on resume. Suspend works normally.
- The quota cannot go in `/etc/fstab`. XFS cannot enable quota at remount, and root is already mounted by then.
- `rootflags` goes in `GRUB_CMDLINE_LINUX`, not `GRUB_CMDLINE_LINUX_DEFAULT`, so it applies to the recovery entries too.
- The kernel renames the options. `pquota` shows as `prjquota` and `uquota` as `usrquota`.

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
apt install -y qt6-wayland qgnomeplatform-qt6 qtwayland5 qgnomeplatform-qt5
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

- Both Qt 5 and Qt 6 are covered. `qgnomeplatform-qt5` and `qgnomeplatform-qt6` supply the GNOME theme, `qtwayland5` and `qt6-wayland` supply the Wayland platform plugin.
- `/etc/environment` is not a shell script. Write `KEY=value`, with no `export` and no quotes.
- `wayland;xcb` tries Wayland and falls back to X11. Plain `wayland` breaks any application whose bundled Qt has no Wayland plugin.
- Set `LD_LIBRARY_PATH` to the application's own library directory first, or `ldd` reports its bundled libraries as missing too.
- An application that exits printing nothing is usually a missing library or a missing graphical session, not a broken application.

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

- Plug the charger in first. On battery every device reports `Device requires AC power to be connected` and is skipped without failing, so the update looks like it worked when nothing happened.
- Never power off during a firmware update.
- Firmware is written during the reboot, not by `fwupdmgr update`. Steps 5 to 7 are one round. Repeat until step 7 is clean.
- `Devices with no available firmware updates` and `Devices with the latest available firmware version` both mean nothing to do. Only the last line decides.
- `fwupd-amd64-signed` holds the Debian-signed EFI file. Without it firmware updates stop working once Secure Boot is on.
- A BIOS update can reset BIOS settings. If step 9 says `SecureBoot disabled`, redo Step 1.

### Step 6 — Packages

#### 1. Install the packages

```bash
apt install -y bash-completion bridge-utils btop curl ffmpeg git gnome-shell-extension-manager gnome-shell-extensions gnome-tweaks htop ipcalc jq keepassxc lshw nano network-manager-openvpn-gnome openssl openvpn3-client progress pwgen python3 python3.13-venv rsync sshuttle sudo tmux tree unrar vim virt-top vlc wget xclip
```

#### 2. Install flatpak

```bash
apt install -y flatpak gnome-software-plugin-flatpak
```

#### 3. Add the flathub remote

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

**Notes**

- Log out and back in before flatpak applications appear in GNOME Software.
- `fonts-jetbrains-mono` installs JetBrains Mono from the Debian archive, so the download at jetbrains.com/lp/mono is not needed. Select it in `Terminal → Preferences → Profile → Text → Custom font`.
- Font size changes the terminal cell height. A window whose height is not an exact multiple of that leaves a thin unpainted strip under the last row, so the size is worth tuning.
- `virt-top` reads from libvirt. Until libvirt is installed and running it shows nothing.

### Step 7 — Bash, tmux, and SSH configuration

The bash, tmux, and SSH configuration is in this repository, which you already
have. Everything it needs was installed in Step 6.

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

- Run it from the repository directory as your own user. As root it configures `/root` and leaves your account untouched.
- It asks whether to configure `root` as well. Answer `y` for the same prompt, aliases, and tmux settings under `su`.
- Safe to re-run. The SSH block is replaced, not duplicated.
- Keep the repository. The installer needs it to re-run.
- `README.md` covers the prompt, the tmux keys, and what changes.

### Step 8 — KVM and libvirt

#### 1. Check the CPU exposes virtualization

```bash
grep -Ec '(vmx|svm)' /proc/cpuinfo
```

Expect a number above 0. This machine is Intel, so the flag is `vmx`.

#### 2. Install the packages

```bash
apt install -y qemu-system-x86 qemu-utils ovmf virtinst virt-manager libvirt-daemon-system libvirt-clients libosinfo-bin osinfo-db osinfo-db-tools libguestfs-tools
```

#### 3. Start the daemon

```bash
systemctl enable --now libvirtd
```

```bash
systemctl is-active libvirtd
```

Expect `active`.

#### 4. Turn on nested virtualization

```bash
cat /sys/module/kvm_intel/parameters/nested
```

If it prints `Y` or `1`, skip the rest of this sub-step. Otherwise:

```bash
echo 'options kvm_intel nested=1' > /etc/modprobe.d/kvm-intel.conf
```

```bash
modprobe -r kvm_intel
```

```bash
modprobe kvm_intel
```

```bash
cat /sys/module/kvm_intel/parameters/nested
```

Expect `Y`.

#### 5. Enable IP forwarding

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

#### 6. Raise the open file limit

```bash
vim /etc/security/limits.d/99-kvm.conf
```

Put this in it:

```
*    soft    nofile    65536
*    hard    nofile    1048576
```

#### 7. Leave the root shell

```bash
exit
```

#### 8. Add your user to the libvirt and kvm groups

```bash
sudo usermod -aG libvirt,kvm $USER
```

Log out and log back in, then check:

```bash
groups
```

Expect `libvirt` and `kvm` in the list.

#### 9. Verify as your own user

```bash
virsh list --all
```

```bash
virsh net-list --all
```

Both must run without a permission error, and `default` must be listed and
active.

#### 10. Make virt-manager follow the dark theme

virt-manager does not follow the GNOME dark preference by itself. From a
terminal the `virt` alias handles it. For the application grid, override its
desktop entry:

```bash
cp /usr/share/applications/virt-manager.desktop ~/.local/share/applications/
```

Find the line to change. The file starts with a few hundred translated
`Name[xx]=` lines, so do not go looking for it by eye:

```bash
grep -n '^Exec=' ~/.local/share/applications/virt-manager.desktop
```

```bash
vim ~/.local/share/applications/virt-manager.desktop
```

Go to that line number and make it read:

```
Exec=env GTK_THEME=Adwaita:dark virt-manager --no-fork
```

```bash
update-desktop-database ~/.local/share/applications
```

**Notes**

- There is no `qemu-kvm` package in trixie. `qemu-system-x86` is the one that provides the emulator, and KVM itself is a kernel module that is already present.
- Step 8 has to run as your own user, not root. Under `sudo` as root, `$USER` is `root`, so the groups would be added to the wrong account.
- Group membership only applies at the next login. `newgrp libvirt` works for one shell if you do not want to log out.
- `modprobe -r kvm_intel` fails if a virtual machine is running. Shut them down first.
- Nested virtualization is only needed to run a hypervisor inside a guest. Ordinary guests do not use it.
- `osinfo-db` comes from the Debian archive and is refreshed by `apt upgrade`. Do not use `osinfo-db-import --latest`; it fetches from a third-party host.
- `/etc/security/limits.d` applies to login sessions, not to systemd services. If libvirtd itself needs a higher limit, add a `LimitNOFILE` drop-in under `/etc/systemd/system/libvirtd.service.d/`.
- The copy in `~/.local/share/applications` takes priority over the one in `/usr/share/applications`, and survives package upgrades.
- libvirt raises `net.ipv4.ip_forward` itself for its NAT network, but setting it here makes it explicit and survives for bridged or routed setups.
