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
| 5 | Free space | ~88 GiB | leave unused | — | — | — |

**Notes**

- A "1 TB" disk is 931 GiB, not 1024. Check yours with
  `lsblk -b -d -o NAME,SIZE` (`Ctrl+Alt+F2` for a shell).
- The installer counts in GB. `df -h` counts in GiB. Root shows as `859.0 GB`
  now and `800G` later. Same partition.
- For any other size: type `GiB x 1073.741824` MB, rounded.
- Leave the 88 GiB free. Samsung suggests about 10% for over-provisioning. The
  drive uses it to keep write speed up as the disk fills.
- XFS handles big files well, like a 200 GiB qcow2 image.
- Docker runs on XFS. It can also cap container size with
  `--storage-opt size=`, which needs the `prjquota` mount option.
- 40 GiB swap covers hibernation up to 32 GB RAM.

## Step 3 — After install: check everything

**Remove the USB stick before the first boot.** If it is still plugged in, the
machine may start the installer again.

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Secure Boot is on | `dmesg \| grep -i "secure boot"` | `Secure boot enabled` |
| 2 | Same, from the EFI variable | `od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c` | last number is `1` |
| 3 | It booted through shim | `sudo efibootmgr -v \| grep -i shim` | `\EFI\debian\shimx64.efi` |
| 4 | Partition sizes | `lsblk` | 1G, 2G, 800G, 40G |
| 5 | Root is XFS | `findmnt -no FSTYPE /` | `xfs` |
| 6 | Free space is untouched | `sudo sgdisk -p /dev/nvme0n1` | ~88 GiB unallocated |
| 7 | Swap is active | `swapon --show` | 40G partition listed |
| 8 | BIOS version | `sudo dmidecode -s bios-version` | matches Step 1 |

**Notes**

- `efi-readvar -v PK` reports `no entries` on this machine. That is normal
  while `Secure Boot Key State` is `Standard`. The firmware keeps its keys
  internal and does not publish them.
- Steps 1 to 8 need no extra packages except step 6.
- `mokutil --sb-state` answers step 1 too, after `sudo apt install mokutil`.

The installation is done. Configuration starts below.

## Step 4 — Repositories and firmware updates

| # | Step | How |
|---|------|-----|
| 1 | Add contrib and non-free | In `/etc/apt/sources.list.d/debian.sources`, set every `Components:` line to `main contrib non-free non-free-firmware` |
| 2 | Check the file | `cat /etc/apt/sources.list.d/debian.sources` |
| 3 | Update the system | `sudo apt update && sudo apt full-upgrade` |
| 4 | Reboot | `sudo systemctl reboot` |
| 5 | Install the updater | `sudo apt install fwupd fwupd-amd64-signed mokutil` |
| 6 | Refresh the firmware list | `sudo fwupdmgr refresh --force` |
| 7 | See what is available | `sudo fwupdmgr get-updates` |
| 8 | Apply, BIOS included | `sudo fwupdmgr update` |
| 9 | Check the new BIOS version | `hostnamectl` — compare with Step 1 |
| 10 | Re-check Secure Boot | `mokutil --sb-state` → `SecureBoot enabled` |

**Notes**

- Keep the charger plugged in. Never power off during a firmware update.
- Step 8 may reboot the machine more than once. This is normal.
- A BIOS update can reset BIOS settings. Step 10 is there to catch that. If
  Secure Boot came back off, redo Step 3.
- `fwupd-amd64-signed` holds the signed EFI file. Without it, firmware updates
  stop working while Secure Boot is on.
- Step 1 as a one-liner:
  `sudo sed -i -E 's/^Components:.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources`
