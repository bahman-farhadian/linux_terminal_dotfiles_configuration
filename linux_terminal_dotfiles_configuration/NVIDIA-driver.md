# NVIDIA driver on Debian 13

For any Debian 13 "trixie" machine with an NVIDIA card — a bare-metal server, or
a virtual machine with one passed through to it. The steps are the same; the two
places they differ are called out where they arise, and both are about Secure
Boot, which a server ships with enabled and a VM usually does not.

This document stands alone. Nothing here refers to Silenus, Dionysus or
Hephaestus, and nothing there refers to this.

Every step can be run again without harm. Files are written whole rather than
appended to, and package installs skip what is present.

## Before starting

The card has to be visible to the operating system.

```bash
lspci -nn | grep -i nvidia
```

Two lines for most cards — the VGA controller and its HDMI audio function.

- **Bare metal**: nothing printed means the card is not seated, not powered, or disabled in firmware. Nothing below will help until `lspci` sees it.
- **Virtual machine**: nothing printed means the device was never attached to the domain. One line rather than two means only one PCI function was handed over, and the card is split between the host and the guest — fix that on the host first.

```bash
lspci -nnk | grep -i nvidia -A3
```

`Kernel driver in use:` should read `nouveau`, or nothing at all. That is the
expected state before the proprietary driver is installed, and it is what the
next steps replace.

## Which set of packages

Two different builds, and the choice is about what the guest is for.

| | Headless — compute, containers, CUDA | With a desktop |
|---|---|---|
| Install | `nvidia-kernel-dkms`, `nvidia-smi` | `nvidia-driver` |
| Pulls in an X server driver | no | yes, `xserver-xorg-video-nvidia` |
| `nvidia-smi` works | yes | yes |
| CUDA userspace | add `nvidia-driver-libs` | included |

`nvidia-driver` is the meta-package most guides name, and on a headless machine
it drags in the X stack for nothing. Start from the headless column unless the
machine actually renders something — a server almost never does.

## Step 1 — Enable contrib, non-free and non-free-firmware

The driver is not in `main` and never will be: `nvidia-kernel-dkms` is in
`non-free`, and the firmware blobs are in `non-free-firmware`.

```bash
sudo vim /etc/apt/sources.list
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

```bash
sudo apt update
```

```bash
apt-cache policy | grep -i non-free
```

Expect `non-free` and `non-free-firmware` component lines.

**Notes**

- A Debian install from the standard media starts with only `main`, whether it is on metal or in a VM, so the components have to be added either way.
- Debian 13 may write `/etc/apt/sources.list.d/debian.sources` in DEB822 format instead, depending on how the installer ran. If that file exists and `/etc/apt/sources.list` does not, edit its `Components:` line to read `main contrib non-free non-free-firmware` rather than creating the classic file alongside it. Two sources for the same suite makes `apt` warn about being configured multiple times.

## Step 2 — Secure Boot: decide now, act in Step 4

The NVIDIA driver is an out-of-tree kernel module built by DKMS. With Secure
Boot enforcing, the kernel refuses to load a module it cannot verify, and the
result is a driver that installs without a single error and then does nothing.

```bash
sudo apt install -y mokutil
```

```bash
mokutil --sb-state
```

**`SecureBoot disabled`** — common on a virtual machine. Nothing to do. Skip
Step 4 entirely.

**`SecureBoot enabled`** — usual on a bare-metal server, and on a VM given a
secure-boot firmware. Two ways forward:

| | Turn Secure Boot off | Enrol a key |
|---|---|---|
| Where it fits | a VM, whose host already enforces its own boot chain | bare metal, where Secure Boot is protecting a machine that boots on its own |
| Effort | one firmware setting | a key, a reboot, and a blue screen at the console |
| Needs console access | to change the firmware setting | **yes, unavoidably** — see Step 4 |
| Survives kernel upgrades | n/a | yes, DKMS re-signs with the same key |

Decide here, install the driver in Step 3, and act on the decision in Step 4.
The order matters: DKMS generates its signing key during the first module build,
so there is nothing to enrol until the driver is installed.

**Notes**

- The failure this prevents is silent, which is why it is decided before anything is installed rather than diagnosed afterwards. `nvidia-smi` reports `couldn't communicate with the NVIDIA driver` — indistinguishable, at a glance, from a driver that failed to build.
- A machine booting on BIOS or SeaBIOS rather than UEFI has no Secure Boot at all, and `mokutil` says so.
- Turning Secure Boot off on bare metal is a real reduction in what the machine verifies at boot. On a server that reboots unattended in a rack, enrolling a key is the answer; disabling it because enrolment is inconvenient is trading a property of the machine for ten minutes.

## Step 3 — Install the driver

#### 1. Kernel headers, so DKMS can build

```bash
sudo apt install -y linux-headers-amd64
```

#### 2. The driver

Headless — compute, containers, CUDA:

```bash
sudo apt install -y nvidia-kernel-dkms nvidia-smi nvtop
```

With a desktop:

```bash
sudo apt install -y nvidia-driver nvidia-smi nvtop
```

#### 3. Watch the build finish

DKMS compiles the module during the install. It is the slowest part and the part
that fails if the headers are missing:

```bash
sudo dkms status
```

Expect a line for `nvidia` against your running kernel, ending `installed`.

**Notes**

- `nvidia-smi` is a separate package from the driver and is what reports the card, its memory, its temperature and the processes using it. It is worth installing on a headless machine even though nothing else from the X stack is.
- `nvtop` is in `main`, needs nothing non-free, and gives a live per-process view of GPU use — `htop` for the card. It reads from the driver, so install it after, not instead.
- With Secure Boot enabled, the install finishes and the module will still not load until Step 4. That is expected at this point, not a failure.
- `nvidia-detect` names the driver branch a given card needs, which is worth running when the card is older than the packaged driver: `sudo apt install -y nvidia-detect && nvidia-detect`.
- The packaged driver blacklists `nouveau` for you — Debian's NVIDIA packages drop a file under `/etc/modprobe.d/` that does it, so there is nothing to write by hand. Confirm rather than assume, after the install: `grep -rl nouveau /etc/modprobe.d/`. This is the opposite of the host side, where `nouveau` is blacklisted so that `vfio-pci` can claim the card instead.
- Trixie carries the 550 branch. That covers Maxwell onwards; a card older than that needs one of the legacy branches, which `nvidia-detect` will say.

## Step 4 — Enrol the signing key

**Only if `mokutil --sb-state` said `SecureBoot enabled` and you chose to keep
it.** Otherwise go to Step 5.

#### 1. Find the key DKMS built

Debian's DKMS signs the modules it builds and keeps a key pair for the purpose,
generated during the first build:

```bash
sudo ls -l /var/lib/dkms/mok.pub /var/lib/dkms/mok.key
```

Both present means Step 3 generated them. If they are not there, check where
this system's DKMS is configured to look, and use those paths for the rest of
this step:

```bash
sudo grep -rhE 'mok_(signing_key|certificate)' /etc/dkms/ 2>/dev/null
```

#### 2. Confirm the module was actually signed

```bash
sudo modinfo -F signer nvidia
```

A signer name — DKMS's own — means there is a signature to trust. Nothing
printed means the module is unsigned, and enrolling a key will not help; the
build did not sign it, and `/etc/dkms/framework.conf` is where to look.

#### 3. Stage the key for enrolment

```bash
sudo mokutil --import /var/lib/dkms/mok.pub
```

It asks for a password **twice**. This is a one-time password used once, at the
next boot, to confirm the enrolment — not a password for anything afterwards.
Choose something you can type on a console keyboard whose layout you may not
control, and keep it to hand for the next ten minutes.

```bash
sudo mokutil --list-new
```

The key you just staged. It is queued, not yet trusted.

#### 4. Reboot to the console — not over SSH

```bash
sudo systemctl reboot
```

**Be at the console for this boot.** Physically, or on the server's out-of-band
console — iDRAC, iLO, IPMI, or `virsh console` for a VM. Shim stops at a blue
**MOK Manager** screen and waits for a person. Nothing is listening on the
network yet, and the machine will sit there until someone answers.

At that screen:

1. **Enroll MOK**
2. **Continue**
3. **Yes** to confirm
4. Type the password from sub-step 3
5. **Reboot**

Miss the window and the boot carries on with the key unenrolled, which is not a
failure — `mokutil --import` again and take the next reboot.

#### 5. Confirm it took

```bash
mokutil --list-enrolled | grep -iA2 -m1 'DKMS\|Subject'
```

```bash
sudo mokutil --list-new
```

The first shows the key trusted; the second should now be empty.

**Notes**

- **This step cannot be done over SSH.** The MOK Manager runs from shim, before the kernel and before any network. On a remote server, arrange the out-of-band console before staging the key rather than after — a machine waiting at a blue screen is indistinguishable, from the network, from one that failed to boot.
- Enrolment is once per machine, not once per kernel. DKMS re-signs with the same key on every rebuild, so kernel upgrades keep working with no repeat of any of this.
- `mokutil --disable-validation` turns off signature checking from inside the running system instead. It uses the same blue screen and the same password, and it is a worse answer than enrolling: it disables the check for every module, permanently, rather than trusting one key.
- The key at `/var/lib/dkms/mok.key` is what can sign a module this machine will load. It is readable only by root; treat a backup of it the way you would treat a private key, because that is what it is.
- The same key signs anything else DKMS builds here — VirtualBox, ZFS, out-of-tree network drivers. Enrolling it once covers them all.

## Step 5 — Reboot

The running kernel still has `nouveau` loaded, and the blacklist only takes
effect on a fresh boot.

```bash
sudo systemctl reboot
```

## Step 6 — Verify

```bash
lsmod | grep nouveau
```

Expect no output.

```bash
lsmod | grep nvidia
```

Expect `nvidia`, `nvidia_modeset`, `nvidia_uvm` and `nvidia_drm` in some
combination.

```bash
nvidia-smi
```

The card, its driver version, its memory and its temperature. This is the test
that matters — everything before it is setup.

```bash
nvtop
```

A live view, one row per process using the card. `q` quits.

**Notes**

- `nvidia-smi` reporting `No devices were found` with the module loaded means the card is not reaching the operating system. On a VM, check on the host that both PCI functions are bound to `vfio-pci` and both are attached to this domain. On bare metal, check the card is seated and enabled in firmware — `lspci` from the section above answers it either way.
- `couldn't communicate with the NVIDIA driver` is one of two things: a signature the kernel would not accept, or a DKMS build that did not finish. `sudo dkms status` shows the build; `sudo dmesg | grep -iE "nvidia|taint|signature"` shows a module refused for its signature. If it is the signature, Step 4 was skipped or the enrolment did not take.
- `nvidia-smi` after a kernel upgrade can fail because DKMS has not rebuilt for the new kernel. `sudo dkms autoinstall` then reboot. Keeping `linux-headers-amd64` installed rather than a version-pinned headers package is what makes that automatic.
- On a headless machine `nvidia-persistenced` keeps the driver initialised between jobs, which removes a start-up delay on the first CUDA call: `sudo apt install -y nvidia-persistenced && sudo systemctl enable --now nvidia-persistenced`. It is in `contrib`.

## If CUDA is the point

Trixie packages CUDA as `nvidia-cuda-toolkit`, version 12.4, which is enough for
most things and needs no third-party repository:

```bash
sudo apt install -y nvidia-cuda-toolkit
```

```bash
nvcc --version
```

NVIDIA's own repository carries newer CUDA than Debian does, and is the route
when a framework needs a version trixie has not packaged. It is a third-party
archive with its own key and its own driver packages, so:

- **Do not mix it with Debian's driver.** Installing `cuda-drivers` from NVIDIA alongside `nvidia-driver` from Debian gives two sources for the same files and an unpredictable result. Pick one origin and pin the other out, or use only Debian's.
- **Confirm the repository path exists before trusting a copied command line.** NVIDIA publishes per-distribution paths under `developer.download.nvidia.com/compute/cuda/repos/`, and which Debian releases are present there changes over time. Open that URL and read the directory listing rather than assuming `debian13` is there because `debian12` was.
- The container route avoids the question. If the workload runs in Docker, install only Debian's driver on the machine and let the NVIDIA Container Toolkit pass the device into containers that carry their own CUDA userspace. The driver on the host of the container has to be new enough for the CUDA inside it, which is the one version rule that still applies.
