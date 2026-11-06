# Patched NVIDIA Open Driver for Hybrid Laptops (D3cold Wakeup Fix)

Fixes discrete NVIDIA GPUs (RTX 30/40/50 series) waking up from deep `D3cold` sleep whenever:
* AC charger is plugged or unplugged
* Power profiles (Quiet, Balanced, Performance) are switched
* Battery percentage ticks down

---

## Files in this Directory

* [`nvidia-d3cold-wakeups.patch`](./nvidia-d3cold-wakeups.patch) — The clean unified source patch for NVIDIA open-gpu-kernel-modules.
* [`build-and-install.sh`](./build-and-install.sh) — 1-click automated build script that downloads the official source, applies the patch, compiles with Clang/LLD, and creates the `.pkg.tar.zst` package.
* [`linux-cachyos-nvidia-open-7.3.1-1.2-x86_64.pkg.tar.zst`](./linux-cachyos-nvidia-open-7.3.1-1.2-x86_64.pkg.tar.zst) — The compiled Arch package for kernel `7.3.1-1-cachyos`.

---

## 1. How to Prevent `pacman -Syu` from Overwriting It

During regular system updates, pacman might try to replace this package with the official repo version. To pin your patched version:

1. Edit `/etc/pacman.conf`:
   ```bash
   sudo nano /etc/pacman.conf
   ```
2. Find `#IgnorePkg =` and change it to:
   ```ini
   IgnorePkg = linux-cachyos-nvidia-open
   ```
3. Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

Now `pacman -Syu` will safely keep your patched driver.

---

## 2. Rebuilding for a New Kernel Version or Fresh Install

If you format or update to a new kernel release:

1. Clone or copy this folder to your machine.
2. Ensure kernel headers and build tools are installed:
   ```bash
   sudo pacman -S --needed base-devel clang lld llvm linux-cachyos-headers
   ```
3. Run the automated script:
   ```bash
   ./build-and-install.sh
   ```
4. Install the newly created package:
   ```bash
   sudo pacman -U pkg/linux-cachyos-nvidia-open-*.pkg.tar.zst
   ```
5. Reboot.
