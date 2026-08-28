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
| 1 | EFI | 1 GiB | `1074 MB` | 1.1 GB | FAT32, `esp` flag | `/boot/efi` |
| 2 | Boot | 2 GiB | `2147 MB` | 2.1 GB | ext4 | `/boot` |
| 3 | Root | 800 GiB | `858993 MB` | 859.0 GB | xfs | `/` |
| 4 | Swap | 40 GiB | `42950 MB` | 42.9 GB | swap | — |
| 5 | Free space | ~111 GiB | leave unused | — | — | — |

**Notes**

- The installer counts in GB. `df -h` counts in GiB. Root shows as `859.0 GB`
  now and `800G` later. Same partition.
- For any other size: type `GiB x 1073.741824` MB, rounded.
- Leave the 111 GiB free. Samsung suggests about 10% for over-provisioning.
  The drive uses it to keep write speed up as the disk fills.
- XFS handles big files well, like a 200 GiB qcow2 image.
- Docker runs on XFS. It can also cap container size with
  `--storage-opt size=`, which needs the `prjquota` mount option.
- 40 GiB swap covers hibernation up to 32 GB RAM.

## Step 3 — After install: repositories, packages, checks

Remove the USB stick before the first boot. If it is still plugged in, the
machine may start the installer again.

### 1. Add contrib and non-free

```bash
sudo nano /etc/apt/sources.list.d/debian.sources
```

Set every `Components:` line to:

```
Components: main contrib non-free non-free-firmware
```

Or do it in one command:

```bash
sudo sed -i -E 's/^Components:.*/Components: main contrib non-free non-free-firmware/' \
  /etc/apt/sources.list.d/debian.sources
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

### 4. Check Secure Boot

```bash
mokutil --sb-state
dmesg | grep -i "secure boot"
```

Expect `SecureBoot enabled` and `secureboot: Secure boot enabled`.

### 5. Check the machine booted through shim

```bash
sudo efibootmgr -v | grep -i shim
```

Expect `\EFI\debian\shimx64.efi`.

### 6. Check the disk

```bash
lsblk
findmnt -no FSTYPE /
swapon --show
```

Expect `1023M`, `2G`, `800G`, `40G`, root `xfs`, and swap active.

### 7. Check the BIOS version

```bash
sudo dmidecode -s bios-version
```

Compare with what you wrote down in Step 1.

### 8. Reboot

```bash
sudo systemctl reboot
```

**Notes**

- `efi-readvar -v PK` reports `no entries` on this machine. That is normal
  while `Secure Boot Key State` is `Standard`. The firmware keeps its keys
  internal.
- If Secure Boot is off, go back to Step 1 and check the 3rd party CA.

The installation is done. Configuration starts below.

## Step 4 — Firmware updates

### 1. Install fwupd

```bash
sudo apt install fwupd fwupd-amd64-signed
```

### 2. Refresh the firmware list

```bash
sudo fwupdmgr refresh --force
```

### 3. See what is available

```bash
sudo fwupdmgr get-devices
sudo fwupdmgr get-updates
```

### 4. Apply

```bash
sudo fwupdmgr update
```

### 5. Check Secure Boot again

```bash
mokutil --sb-state
```

**Notes**

- Keep the charger plugged in. Never power off during a firmware update.
- Step 4 may reboot the machine more than once. This is normal.
- A BIOS update can reset BIOS settings. If Secure Boot came back off, redo
  Step 1.
- `fwupd-amd64-signed` holds the signed EFI file. Without it, firmware updates
  stop working while Secure Boot is on.

## Step 5 — XFS project quota for Docker

Docker can only cap a container's disk size (`--storage-opt size=`) when root
is mounted with project quota. Root is mounted before `/etc/fstab` is read, so
this goes on the kernel command line.

### 1. Edit the GRUB defaults

```bash
sudo nano /etc/default/grub
```

Add `rootflags=uquota,pquota` inside `GRUB_CMDLINE_LINUX`:

```
GRUB_CMDLINE_LINUX="rootflags=uquota,pquota"
```

### 2. Apply and reboot

```bash
sudo update-grub
sudo systemctl reboot
```

### 3. Verify

```bash
findmnt -no OPTIONS /
sudo xfs_quota -x -c state /
```

Expect `prjquota` in the mount options, and project quota `ON`.

**Notes**

- `/etc/fstab` does not work for this. XFS cannot turn quota on at remount,
  and root is already mounted by then.
- Docker only needs `pquota`. `uquota` is user quota and is optional.
- The kernel reports `pquota` as `prjquota`. Same thing.
- Do this before installing Docker.
