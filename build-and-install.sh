#!/usr/bin/env bash
# ==============================================================================
# Automated Builder & Installer for Patched NVIDIA Open Kernel Modules
# Fixes D3cold wakeups on AC/Battery transitions and Power Mode switches.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${SCRIPT_DIR}/nvidia-d3cold-wakeups.patch"

if [[ ! -f "$PATCH_FILE" ]]; then
    echo "[-] Error: Patch file not found at ${PATCH_FILE}" >&2
    exit 1
fi

KERNEL_UNAME="$(uname -r)"
echo "[+] Detected running kernel: ${KERNEL_UNAME}"

if ! command -v pacman &>/dev/null; then
    echo "[-] Error: pacman not found. This script requires an Arch/CachyOS system." >&2
    exit 1
fi

NV_VER="$(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}' | cut -d'-' -f1 || true)"
if [[ -z "$NV_VER" ]]; then
    NV_VER="615.78.08"
    echo "[!] Could not detect nvidia-utils version, defaulting to ${NV_VER}"
else
    echo "[+] Detected nvidia-utils version: ${NV_VER}"
fi

BUILD_DIR="${SCRIPT_DIR}/build_tmp"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

TARBALL="NVIDIA-kernel-module-source-${NV_VER}.tar.xz"
TARBALL_URL="https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/${TARBALL}"

if [[ ! -f "$TARBALL" ]]; then
    echo "[+] Downloading NVIDIA source tarball (${NV_VER})..."
    curl -fL -o "$TARBALL" "$TARBALL_URL"
fi

SOURCE_DIR="NVIDIA-kernel-module-source-${NV_VER}"
rm -rf "$SOURCE_DIR"
echo "[+] Extracting source..."
tar -xf "$TARBALL"

cd "$SOURCE_DIR"

# Apply CachyOS kernel compatibility patches if kernel >= 7.3
KERNEL_MAJOR_MINOR="$(uname -r | cut -d'.' -f1-2)"
if [[ -d "/usr/lib/modules/${KERNEL_UNAME}/build" ]]; then
    echo "[+] Fetching kernel 7.3 compatibility patches from CachyOS..."
    curl -sL "https://raw.githubusercontent.com/cachyos/kernel-patches/master/7.3/misc/nvidia/0001-fix-dsc-correct-RC-parameter-tables-to-match-VESA-DS.patch" | patch -p1 -N || true
    curl -sL "https://raw.githubusercontent.com/cachyos/kernel-patches/master/7.3/misc/nvidia/0002-fix-dp-add-Bigscreen-Beyond-VR-headset-to-WAR-databa.patch" | patch -p1 -N || true
    curl -sL "https://raw.githubusercontent.com/cachyos/kernel-patches/master/7.3/misc/nvidia/0004-Open-sysfs-config-from-the-userspace-root-on-7.3.patch" | patch -p1 -N || true
fi

echo "[+] Applying D3cold AC/Battery & Power Mode wakeup fix patch..."
patch -p1 < "$PATCH_FILE"

echo "[+] Compiling kernel modules using $(nproc) threads..."
BUILD_FLAGS=(
    CC=clang
    LD=ld.lld
    LLVM=1
    LLVM_IAS=1
)
MODULE_FLAGS=(
    KERNEL_UNAME="${KERNEL_UNAME}"
    IGNORE_PREEMPT_RT_PRESENCE=1
    SYSSRC="/usr/lib/modules/${KERNEL_UNAME}/build"
    SYSOUT="/usr/lib/modules/${KERNEL_UNAME}/build"
    IGNORE_CC_MISMATCH=yes
)

CFLAGS= CXXFLAGS= LDFLAGS= make "${BUILD_FLAGS[@]}" "${MODULE_FLAGS[@]}" -j"$(nproc)" modules

echo "[+] Building Arch/CachyOS package..."
PKG_DEST="${SCRIPT_DIR}/pkg"
rm -rf "$PKG_DEST"
mkdir -p "$PKG_DEST"
cd "$PKG_DEST"

PKGVER="${KERNEL_UNAME%%-*}"
PKGREL="1.2"

cat << EOF > PKGBUILD
pkgname=linux-cachyos-nvidia-open
pkgver=${PKGVER}
pkgrel=${PKGREL}
pkgdesc="nvidia open modules of ${NV_VER} driver for linux-cachyos (with D3cold AC/Battery and Power Profile wakeups fix)"
arch=('x86_64' 'x86_64_v3')
url="https://github.com/NVIDIA/open-gpu-kernel-modules"
depends=('linux-cachyos' "nvidia-utils=${NV_VER}" 'libglvnd')
provides=('NVIDIA-MODULE' "linux-cachyos-nvidia-open=${PKGVER}")
conflicts=('linux-cachyos-nvidia')
license=('MIT AND GPL-2.0-only')
options=('!strip' '!debug')

package() {
    local modulesdir="\${pkgdir}/usr/lib/modules/${KERNEL_UNAME}/extramodules"
    local builddir="${BUILD_DIR}/${SOURCE_DIR}"

    install -dm755 "\${modulesdir}"
    install -m644 "\${builddir}"/kernel-open/*.ko "\${modulesdir}/"
    find "\${pkgdir}" -name '*.ko' -exec zstd --rm -19 -T0 {} +

    install -dm755 "\${pkgdir}/usr/share/licenses/\${pkgname}"
    install -m644 "\${builddir}/COPYING" "\${pkgdir}/usr/share/licenses/\${pkgname}/COPYING"
}
EOF

makepkg -f -d

PACKAGE_FILE="$(ls -1 *.pkg.tar.zst | head -n 1)"
echo "[+] Package built: ${PKG_DEST}/${PACKAGE_FILE}"

echo ""
echo "===================================================================="
echo "To install the patched driver, run:"
echo "    sudo pacman -U ${PKG_DEST}/${PACKAGE_FILE}"
echo "===================================================================="
