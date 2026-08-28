# ThinkPad T14 Gen 4 (Intel) — Debian 13 "trixie"

## Step 1 — BIOS: Secure Boot into Setup Mode

| # | Step | How |
|---|------|-----|
| 1 | Enter BIOS | Power off fully, power on, tap **F1** at the Lenovo splash |
| 2 | Note BIOS version | `Main` tab — write it down |
| 3 | Restore Factory Keys | `Security → Secure Boot → Restore Factory Keys` → **Yes** |
| 4 | Reset to Setup Mode | `Security → Secure Boot → Reset to Setup Mode` → **Yes** |
| 5 | Verify | Same screen: `Platform Mode` = **Setup Mode** |
| 6 | Save and exit | **F10** → **Yes** |

**Notes**

- Step 3 restores the stock Lenovo/Microsoft keys; step 4 wipes them. Order is
  deliberate — it guarantees a clean baseline before clearing.
- If step 4 is greyed out: **F10**, reboot, **F1**, retry. Some BIOS versions
  won't do both key operations in one session.
- Setup Mode means Secure Boot is **not** enforcing. Temporary state — own keys
  get enrolled in a later step. Don't leave it here.
- To abort and return to stock: `Restore Factory Keys`.
- Menu wording varies by BIOS version; both entries live on the
  `Security → Secure Boot` screen.
