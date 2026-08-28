# ThinkPad T14 Gen 4 (Intel) — Debian 13 "trixie" Setup

## Step 1 — BIOS: put Secure Boot into Setup Mode

| # | Step | How |
|---|------|-----|
| 1 | Enter BIOS | Power off fully, power on, tap **F1** at the Lenovo splash |
| 2 | Note BIOS version | `Main` tab — write it down |
| 3 | Reset to Setup Mode | `Security → Secure Boot → Reset to Setup Mode` → **Yes** |
| 4 | Verify | Same screen: `Platform Mode` = **Setup Mode** |
| 5 | Save and exit | **F10** → **Yes** |

**Notes**

- Step 3 deletes all Secure Boot keys. Secure Boot is now off.
- Step 3 greyed out? Set `Secure Boot` to `Enabled` first, then retry.
- To undo: `Restore Factory Keys` puts the stock keys back.

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

## Step 3 — After install: repositories, firmware, Secure Boot

**Remove the USB stick before the first boot.** If it is still plugged in, the
machine may start the installer again.

Do these in order. Steps 10 and 11 must come last.

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
| 10 | Restore the keys | BIOS **F1** → `Security → Secure Boot → Restore Factory Keys` → **Yes** |
| 11 | Confirm and save | Same screen: `Secure Boot` = **Enabled** → **F10** |
| 12 | Verify | `mokutil --sb-state` → `SecureBoot enabled` |

**Notes**

- Keep the charger plugged in. Never power off during a firmware update.
- Do the firmware update before step 10. A BIOS update can reset BIOS settings.
- Step 8 may reboot the machine more than once. This is normal.
- Step 1 as a one-liner:
  `sudo sed -i -E 's/^Components:.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources`
- `fwupd-amd64-signed` holds the signed EFI file. Without it, firmware updates
  stop working once Secure Boot is on.
- Step 1 of this guide only deleted the keys. `Secure Boot` itself stayed
  **Enabled**, so restoring the keys makes it enforce again.
- Debian's boot files are signed by Microsoft's key. The factory keys are all
  you need.
