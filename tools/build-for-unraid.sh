#!/bin/bash
# build-for-unraid.sh UNRAID_CONFIG [KERNEL_VERSION]
#
# Builds src/uas_arb.ko for an Unraid kernel on any x86_64 Linux build host
# (tested on Ubuntu 26.04; needs: build-essential flex bison libelf-dev libssl-dev bc curl xz-utils).
#
#   UNRAID_CONFIG   copy of /usr/src/linux-<ver>-Unraid/.config from the Unraid server
#   KERNEL_VERSION  upstream version, e.g. 6.12.54 (default: read from the config header)
#
# Unraid builds with CONFIG_MODVERSIONS and CONFIG_MODULE_SIG off, so a module built from the same
# upstream source + Unraid's .config loads fine. modpost cannot see the kernel's exported symbols
# without a full kernel build, hence KBUILD_MODPOST_WARN=1 (the symbols resolve at insmod time).
#
# NOTE: src/uas_arb.c is based on upstream v6.12.54 drivers/usb/storage/uas.c. For a much newer or
# older kernel, re-apply patches/uas-arbiter-v6.12.54.patch to that kernel's uas.c/uas-detect.h first.
set -euo pipefail
CFG=$(readlink -f "$1")
VER=${2:-$(sed -n 's/^# Linux\/x86 \([0-9.]*\)\(-Unraid\)\{0,1\} Kernel Configuration/\1/p' "$CFG")}
[ -n "$VER" ] || { echo "cannot determine kernel version, pass it as 2nd arg"; exit 1; }
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HOME/uas_arb-build}
mkdir -p "$WORK" && cd "$WORK"
[ -f linux-$VER.tar.xz ] || curl -fL -o linux-$VER.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v${VER%%.*}.x/linux-$VER.tar.xz"
[ -d linux-$VER ] || tar xf linux-$VER.tar.xz
cd linux-$VER
cp "$CFG" .config
make olddefconfig >/dev/null
make modules_prepare -j"$(nproc)" >/dev/null
echo "kernel release: $(make -s kernelrelease)"
rm -rf "$WORK/mod" && cp -r "$HERE/src" "$WORK/mod"
make -C "$WORK/linux-$VER" M="$WORK/mod" KBUILD_MODPOST_WARN=1 modules 2>&1 | grep -v "undefined!" || true
modinfo "$WORK/mod/uas_arb.ko" | grep -E '^(vermagic|name)'
sha256sum "$WORK/mod/uas_arb.ko"
echo "built: $WORK/mod/uas_arb.ko  (vermagic must equal \`uname -r\` on the Unraid server)"
