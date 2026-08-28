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

Choose **Manual** partitioning in the installer. The installer counts in
decimal: `MB` means 1,000,000 bytes. Type the exact numbers below to get the
sizes in the Size column.

| # | Partition | Size | Enter as | Format | Mount |
|---|-----------|------|----------|--------|-------|
| 1 | EFI | 1 GiB | `1074 MB` | FAT32, `esp` flag | `/boot/efi` |
| 2 | Boot | 2 GiB | `2147 MB` | ext4 | `/boot` |
| 3 | Root | 800 GiB | `858993 MB` | xfs | `/` |
| 4 | Swap | 40 GiB | `42950 MB` | swap | — |
| 5 | Free space | ~88 GiB | leave unused | — | — |

**Notes**

- A "1 TB" disk is 931 GiB, not 1024. Check yours first with
  `lsblk -b -d -o NAME,SIZE` (`Ctrl+Alt+F2` for a shell).
- The installer displays decimal GB, but `df -h` in the installed system
  displays GiB. Root shows as `859.0 GB` while partitioning and as `800G` in
  `df -h`. Same partition, two labels. This is correct.
- To size any other partition: type `GiB x 1073.741824` MB, rounded to the
  nearest whole number.
- Leave the 88 GiB unpartitioned. This is over-provisioning, which Samsung
  recommends at about 10% on their SSDs. The drive uses the space for wear
  levelling, which keeps write speed up as the disk fills.
- Root is XFS. It handles very large files well, such as a 200 GiB qcow2 VM
  image. Docker runs on it too.
- 40 GiB swap covers hibernation up to 32 GB RAM. Below that, RAM size plus a
  few GiB is enough.
