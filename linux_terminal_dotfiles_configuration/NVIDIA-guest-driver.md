# NVIDIA driver in a Debian 13 guest

For a Debian 13 "trixie" virtual machine that has a GPU passed through to it.
This document is about the **guest**, not the host: the card is already bound to
`vfio-pci` and handed over before any of this applies. Nothing here refers to
Silenus, Dionysus or Hephaestus, and nothing there refers to this.

Every step can be run again without harm. Files are written whole rather than
appended to, and package installs skip what is present.

## Before starting

The card has to be visible inside the guest. If it is not, this is a host
problem and no amount of work in here will fix it.

```bash
lspci -nn | grep -i nvidia
```

Two lines for most cards — the VGA controller and its HDMI audio function. If
`lspci` prints nothing, the device was never attached to the domain; if only one
line appears, only one PCI function was handed over and the card is split
between the host and the guest.

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
guest actually renders something.

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

- This is the same `sources.list` the host documents write. A guest installed from the same media starts with only `main`, so the components have to be added here too.
- Debian 13 may write `/etc/apt/sources.list.d/debian.sources` in DEB822 format instead, depending on how the installer ran. If that file exists and `/etc/apt/sources.list` does not, edit its `Components:` line to read `main contrib non-free non-free-firmware` rather than creating the classic file alongside it. Two sources for the same suite makes `apt` warn about being configured multiple times.

## Step 2 — Check Secure Boot before installing anything

The NVIDIA driver is an out-of-tree kernel module built by DKMS. With Secure
Boot enforcing, the kernel refuses to load a module it cannot verify, and the
result is a driver that installs without error and then does nothing.

```bash
mokutil --sb-state
```

`SecureBoot disabled` — nothing to do, go to Step 3.

`SecureBoot enabled` — pick one:

- **Turn it off in the guest's firmware.** A VM behind a host that already enforces its own boot chain gains little from a second one, and this is the shorter path.
- **Enrol a Machine Owner Key** and let DKMS sign each build with it. `mokutil --import` registers the key and the next boot presents a blue MOK-manager screen to confirm it — which needs console access to the guest, so do this before you are relying on SSH alone.

**Notes**

- `mokutil` comes from the `mokutil` package: `sudo apt install -y mokutil`.
- This check is first because the failure it prevents is silent and confusing. `nvidia-smi` reports `couldn't communicate with the NVIDIA driver` and `dmesg` records the module being rejected, which reads as a broken driver rather than a policy decision.
- A guest booting on BIOS/SeaBIOS rather than UEFI has no Secure Boot at all and `mokutil` says so.

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

- `nvidia-smi` is a separate package from the driver and is what reports the card, its memory, its temperature and the processes using it. It is worth installing on a headless guest even though nothing else from the X stack is.
- `nvtop` is in `main`, needs nothing non-free, and gives a live per-process view of GPU use — `htop` for the card. It reads from the driver, so install it after, not instead.
- `nvidia-detect` names the driver branch a given card needs, which is worth running when the card is older than the packaged driver: `sudo apt install -y nvidia-detect && nvidia-detect`.
- The packaged driver blacklists `nouveau` for you — Debian's NVIDIA packages drop a file under `/etc/modprobe.d/` that does it, so there is nothing to write by hand. Confirm rather than assume, after the install: `grep -rl nouveau /etc/modprobe.d/`. This is the opposite of the host side, where `nouveau` is blacklisted so that `vfio-pci` can claim the card instead.
- Trixie carries the 550 branch. That covers Maxwell onwards; a card older than that needs one of the legacy branches, which `nvidia-detect` will say.

## Step 4 — Reboot

The running kernel still has `nouveau` loaded, and the blacklist only takes
effect on a fresh boot.

```bash
sudo systemctl reboot
```

## Step 5 — Verify

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

- `nvidia-smi` reporting `No devices were found` with the module loaded means the card is not reaching the guest. Check on the **host** that both PCI functions are bound to `vfio-pci` and both are attached to this domain.
- `couldn't communicate with the NVIDIA driver` is the Secure Boot failure from Step 2, or a DKMS build that did not finish. `sudo dkms status` and `dmesg | grep -i nvidia` separate the two.
- `nvidia-smi` after a kernel upgrade can fail because DKMS has not rebuilt for the new kernel. `sudo dkms autoinstall` then reboot. Keeping `linux-headers-amd64` installed rather than a version-pinned headers package is what makes that automatic.
- On a headless guest `nvidia-persistenced` keeps the driver initialised between jobs, which removes a start-up delay on the first CUDA call: `sudo apt install -y nvidia-persistenced && sudo systemctl enable --now nvidia-persistenced`. It is in `contrib`.

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
- The container route avoids the question. If the workload runs in Docker, install only Debian's driver on the guest and let the NVIDIA Container Toolkit pass the device into containers that carry their own CUDA userspace. The driver on the host of the container has to be new enough for the CUDA inside it, which is the one version rule that still applies.
