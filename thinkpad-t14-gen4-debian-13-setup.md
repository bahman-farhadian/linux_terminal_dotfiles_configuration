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

- Step 3 deletes all Secure Boot keys. With no keys, the firmware stops
  checking, so you can add your own later.
- Secure Boot is off in Setup Mode. Do not stay here — a later step fixes it.
- Step 3 greyed out? Set `Secure Boot` to `Enabled` first. Not confirmed on
  this model.
- To undo: `Restore Factory Keys` puts the stock keys back.
- Labels differ between BIOS versions. Everything is on the same
  `Security → Secure Boot` screen.
