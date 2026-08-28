# ThinkPad T14 Gen 4 (Intel) — Debian 13 "trixie" Setup

## Step 1 — BIOS: allow the Microsoft 3rd party CA

| # | Step | How |
|---|------|-----|
| 1 | Enter BIOS | Power off fully, power on, tap **F1** at the Lenovo splash |
| 2 | Note BIOS version | `Main` tab — write it down |
| 3 | Open Secure Boot | `Security → Secure Boot` |
| 4 | Allow the 3rd party CA | `Allow Microsoft 3rd Party UEFI CA` = **On** |
| 5 | Check the other lines | `Secure Boot` = **On**, `Secure Boot Mode` = **User Mode**, `Secure Boot Key State` = **Standard** |
| 6 | Save and exit | **F10** → **Yes** |

**Notes**

- Debian's bootloader is signed by Microsoft's 3rd party UEFI CA. If this is
  **Off**, the machine fails to boot with `Invalid signature detected`.
- Leave `Secure Boot` **On** for the whole install. Debian handles it.
- Do not touch `Reset to Setup Mode` or `Clear All Secure Boot Keys`. Debian
  does not need them, and they cause the failure above.

## Step 2 — Disk partitioning

Choose **Manual** partitioning. The installer counts in decimal, so `MB` means
1,000,000 bytes. Type the **Enter as** value. The installer will then display
the **Shows as** value.

| # | Partition | Size | Enter as | Shows as | Format | Mount |
|---|-----------|------|----------|----------|--------|-------|
| 1 | EFI | 1 GiB | `1075 MB` | 1.1 GB | FAT32, `esp` flag | `/boot/efi` |
| 2 | Boot | 2 GiB | `2147 MB` | 2.1 GB | ext4 | `/boot` |
| 3 | Root | 888 GiB | `953483 MB` | 953.5 GB | xfs | `/` |

Leave the rest of the disk unpartitioned.

**SSD over-provisioning**

```
Disk          953.87 GiB
Root          888.00 GiB
EFI + boot      3.00 GiB
------------------------
Free           62.87 GiB   6.6%
```

The drive uses that free space for wear levelling, which keeps write speed up
as the disk fills. Samsung suggests about 10%. To reach it, use a root of
855 GiB (`918049 MB`) instead, which leaves 95.87 GiB free.

**Notes**

- The installer counts in GB. `df -h` counts in GiB. Root shows as `953.5 GB`
  now and `888G` later. Same partition.
- The first partition starts 1 MiB into the disk, so it ends up 1 MiB smaller
  than asked. `1075 MB` accounts for that and gives a full 1 GiB. If yours
  still shows `1023M`, it is harmless.
- For any other size: type `GiB x 1073.741824` MB, rounded.
- No swap partition. Hibernation needs swap, and hibernation does not work
  while Secure Boot is on. See the note in Step 3.
- XFS handles big files well, like a 200 GiB qcow2 image.
- Docker runs on XFS. It can also cap container size with
  `--storage-opt size=`, which needs the `prjquota` mount option.

## Step 3 — After install: repositories, quota, checks

Remove the USB stick before the first boot. If it is still plugged in, the
machine may start the installer again.

### 1. Add contrib and non-free

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

### 2. Update the system

```bash
sudo apt update
sudo apt full-upgrade
```

### 3. Install the tools used for checking

```bash
sudo apt install mokutil dmidecode efibootmgr
```

### 4. Turn on XFS project quota

Docker can only cap a container's disk size (`--storage-opt size=`) when root
is mounted with project quota. Root is mounted before `/etc/fstab` is read, so
this goes on the kernel command line:

```bash
sudo nano /etc/default/grub
```

Add `rootflags=uquota,pquota` inside `GRUB_CMDLINE_LINUX`:

```
GRUB_CMDLINE_LINUX="rootflags=uquota,pquota"
```

Apply it:

```bash
sudo update-grub
```

### 5. Reboot

```bash
sudo systemctl reboot
```

### 6. Check Secure Boot

```bash
mokutil --sb-state
dmesg | grep -i "secure boot"
```

Expect `SecureBoot enabled` and `secureboot: Secure boot enabled`.

### 7. Check the machine booted through shim

```bash
sudo efibootmgr -v | grep -i shim
```

Expect `\EFI\debian\shimx64.efi`.

### 8. Check the disk

```bash
lsblk
findmnt -no FSTYPE /
```

Expect `1G`, `2G`, `888G`, and root `xfs`.

### 9. Check the quota

```bash
findmnt -no OPTIONS /
sudo xfs_quota -x -c state /
```

Expect `prjquota` in the mount options, and project quota `ON`.

### 10. Check the BIOS version

```bash
sudo dmidecode -s bios-version
```

Compare with what you wrote down in Step 1.

**Notes**

- `efi-readvar -v PK` reports `no entries` on this machine. That is normal
  while `Secure Boot Key State` is `Standard`. The firmware keeps its keys
  internal.
- If Secure Boot is off, go back to Step 1 and check the 3rd party CA.
- Hibernation does not work while Secure Boot is on. The kernel locks itself
  down and refuses to write the resume image, because it cannot check that the
  swap was not modified while the machine was off. Suspend works normally.
  Turning hibernation on means turning Secure Boot off.
- `/etc/fstab` does not work for the quota. XFS cannot turn quota on at
  remount, and root is already mounted by then.
- Docker only needs `pquota`. `uquota` is user quota and is optional.
- The kernel reports `pquota` as `prjquota`. Same thing.

The installation is done.
