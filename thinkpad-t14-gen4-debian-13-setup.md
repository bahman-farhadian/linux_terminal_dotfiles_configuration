# ThinkPad T14 Gen 4 (Intel) — Debian 13 "trixie" Setup

## Step 1 — BIOS: put Secure Boot into Setup Mode

| # | Step | How |
|---|------|-----|
| 1 | Enter BIOS | Power off fully, power on, tap **F1** at the Lenovo splash |
| 2 | Note BIOS version | `Main` tab — write it down |
| 3 | Reset to Setup Mode | `Security → Secure Boot → Reset to Setup Mode` → **Yes** |
| 4 | Verify | Same screen: `Platform Mode` = **Setup Mode** |
| 5 | Save and exit | **F10** → **Yes** |

### Notes

**What step 3 does.** It erases the Platform Key (PK) and the KEK, `db`, and
`dbx` key databases. With no PK present, the firmware stops enforcing Secure
Boot and allows the key variables to be written from the operating system.
That is what makes it possible to enroll your own keys in a later step.

**This is a temporary state.** Setup Mode means Secure Boot is not enforcing
and anything can write to the key store. Do not leave the machine like this.

**If step 3 is greyed out.** Check that `Secure Boot` is set to `Enabled` on
the same screen — on some BIOS versions the key operations are only selectable
while it is on. I have not confirmed this for this specific model.

**To abort and go back to stock.** `Security → Secure Boot → Restore Factory
Keys` reinstalls the Lenovo and Microsoft keys and returns the machine to its
shipped configuration.

**Menu wording.** Labels vary between BIOS versions. Everything in this step is
on the `Security → Secure Boot` screen.
