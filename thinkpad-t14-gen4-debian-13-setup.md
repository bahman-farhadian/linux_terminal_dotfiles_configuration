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

#### 1. Add contrib and non-free

The installer writes the classic file, not a `.sources` file:

```bash
sudo nano /etc/apt/sources.list
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

#### 2. Update the system

```bash
sudo apt update
```

```bash
sudo apt full-upgrade
```

#### 3. Install the tools used for checking

```bash
sudo apt install mokutil dmidecode efibootmgr
```

#### 4. Edit GRUB: quota and boot timeout

Docker can only cap a container's disk size (`--storage-opt size=`) when root
is mounted with project quota. Root is mounted before `/etc/fstab` is read, so
this goes on the kernel command line.

```bash
sudo nano /etc/default/grub
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
sudo update-grub
```

#### 5. Reboot

```bash
sudo systemctl reboot
```

#### 6. Check Secure Boot

```bash
mokutil --sb-state
```

Expect `SecureBoot enabled`.

```bash
dmesg | grep -i "secure boot"
```

Expect `secureboot: Secure boot enabled`.

#### 7. Check the machine booted through shim

```bash
sudo efibootmgr -v | grep -i shim
```

Expect `\EFI\debian\shimx64.efi`.

#### 8. Check the disk

```bash
lsblk
```

Expect `1G`, `2G`, and `888G`.

```bash
findmnt -no FSTYPE /
```

Expect `xfs`.

#### 9. Check the quota

```bash
findmnt -no OPTIONS /
```

Expect `usrquota` and `prjquota` in the list.

```bash
sudo xfs_quota -x -c state /
```

Expect `Project quota state` with `Accounting: ON` and `Enforcement: ON`.

#### 10. Check the BIOS version

```bash
sudo dmidecode -s bios-version
```

Compare with what you wrote down in Step 1.

**Notes**

- `efi-readvar -v PK` (package `efitools`) reports `no entries` on this machine. That is normal while `Secure Boot Key State` is `Standard`. The firmware keeps its keys internal.
- If step 6 says `SecureBoot disabled`, the `Secure Boot` toggle is Off in the BIOS. Turn it back on under `Security → Secure Boot`.
- The 3rd party CA is a different problem. It does not turn Secure Boot off — it stops the machine booting at all, with `Invalid signature detected`.
- Hibernation does not work while Secure Boot is on. The kernel locks itself down and refuses to write the resume image, because it cannot check that the swap was not modified while the machine was off. Suspend works normally. Turning hibernation on means turning Secure Boot off.
- `/etc/fstab` does not work for the quota. XFS cannot turn quota on at remount, and root is already mounted by then.
- `rootflags` goes in `GRUB_CMDLINE_LINUX`, not `GRUB_CMDLINE_LINUX_DEFAULT`. The plain one applies to every menu entry, including recovery, so the quota stays on there too.
- Docker only needs `pquota`. `uquota` is user quota and is optional.
- The kernel renames both options. `pquota` shows as `prjquota` and `uquota` shows as `usrquota`. Same things.

The installation is done.

## Part 2 — Configuration

### Step 4 — Firmware updates

Lenovo publishes firmware to LVFS, so the BIOS, embedded controller, and
Thunderbolt can all be updated from Linux. No Windows and no USB needed.

#### 1. Install fwupd

```bash
sudo apt install fwupd fwupd-amd64-signed
```

#### 2. Refresh the firmware list

```bash
sudo fwupdmgr refresh --force
```

#### 3. See what the machine has

```bash
sudo fwupdmgr get-devices
```

#### 4. See what is available

```bash
sudo fwupdmgr get-updates
```

#### 5. Apply

```bash
sudo fwupdmgr update
```

#### 6. Check the new BIOS version

```bash
sudo dmidecode -s bios-version
```

#### 7. Check Secure Boot survived

```bash
mokutil --sb-state
```

Expect `SecureBoot enabled`.

**Notes**

- Keep the charger plugged in. Never power off during a firmware update.
- Step 5 may reboot the machine more than once. This is normal.
- `fwupd-amd64-signed` holds the Debian-signed EFI file. Without it, firmware updates stop working while Secure Boot is on.
- A BIOS update can reset BIOS settings. If step 7 says `SecureBoot disabled`, redo Step 1.
- If step 4 reports nothing to do, the firmware is already current. This machine shipped with `N3QET52W (1.52)`, dated 2026-04-23.
