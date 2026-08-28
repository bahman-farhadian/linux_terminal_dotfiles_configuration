# Step 1 — BIOS: Restore Factory Keys, then enter Setup Mode

**Machine:** ThinkPad T14 Gen 4, Intel 13th gen (Raptor Lake-P)
**Goal of this step:** reset the Secure Boot key store to a known factory
state, then clear it so the OS can enroll its own keys later.

Nothing is installed in this step. This is BIOS only.

---

## Before you start

- Plug in the AC adapter. Do not do this on battery.
- Nothing on the internal disk is touched, but there is no reason to have
  unsaved work open.

---

## 1. Enter the BIOS

1. Shut the laptop down completely (not sleep, not hibernate).
2. Power on and press **F1** repeatedly at the Lenovo splash screen.

You are in BIOS Setup when you see the tab bar: `Main`, `Config`, `Date/Time`,
`Security`, `Startup`, `Restart`.

Write down the BIOS version from the `Main` tab before going further.

---

## 2. Restore Factory Keys

Navigate to:

```
Security → Secure Boot
```

Select **Restore Factory Keys** and confirm **Yes**.

This reinstalls Lenovo's Platform Key (PK) and the stock Microsoft KEK, `db`,
and `dbx` databases.

*Why do this first:* it guarantees you are starting from a clean, complete,
factory key set rather than whatever partial state the machine shipped or
drifted into. It makes the next step predictable.

After this completes, `Platform Mode` should read **User Mode**.

> Some BIOS versions apply this immediately and reboot on their own. If the
> machine restarts, press **F1** again and return to `Security → Secure Boot`.

---

## 3. Reset to Setup Mode

Still under:

```
Security → Secure Boot
```

Select **Reset to Setup Mode** and confirm **Yes**.

This erases the PK and the KEK/`db`/`dbx` databases you just restored. With no
PK present, the firmware stops enforcing Secure Boot and allows key variables
to be written from the operating system. That is the precondition for
enrolling your own keys in a later step.

> If **Reset to Setup Mode** is greyed out, press **F10** to save and exit,
> let the machine reboot, press **F1** to re-enter BIOS, and try again. Some
> firmware versions will not perform both key operations in a single session.

---

## 4. Verify before leaving BIOS

On the `Security → Secure Boot` screen, confirm:

| Field | Expected value |
|---|---|
| `Platform Mode` | Setup Mode |
| `Secure Boot` | Disabled (or shown as not enforcing) |

If `Platform Mode` still says `User Mode`, step 3 did not take effect. Repeat
it before continuing.

---

## 5. Save and exit

Press **F10**, confirm **Yes**.

The machine reboots. Step 1 is complete.

---

## Record these

| Item | Value |
|---|---|
| BIOS version (`Main` tab) | |
| `Platform Mode` after step 3 | |
| Date completed | |

---

## Important — do not stop here

Setup Mode means Secure Boot is **not** enforcing and the key variables are
writable from userspace. This is a temporary state that exists only so keys
can be enrolled. Do not leave the machine like this permanently.

If you need to abandon this process, return to `Security → Secure Boot` and
select **Restore Factory Keys** to go back to the stock configuration.

---

## Note on menu labels

The exact wording and placement of these entries varies between ThinkPad BIOS
versions. If a label does not match, look for the equivalent under
`Security → Secure Boot` — the operations are always on that one screen.
