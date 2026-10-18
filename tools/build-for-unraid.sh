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
# The module is built from THIS kernel's own drivers/usb/storage/uas.c with patches/uas-arbiter.patch
# applied (verified on 6.12.54 and 6.18.54). If the patch stops applying, the build fails.
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
# take uas.c and friends from THIS kernel's source and apply the arbiter patch to them
rm -rf "$WORK/mod" && mkdir -p "$WORK/mod"
for f in uas.c uas-detect.h unusual_uas.h usb.h scsiglue.h debug.h; do
  cp "$WORK/linux-$VER/drivers/usb/storage/$f" "$WORK/mod/"
done
( cd "$WORK/mod" && patch -p4 --no-backup-if-mismatch -s < "$HERE/patches/uas-arbiter.patch" ) \
  || { echo "patches/uas-arbiter.patch does not apply to $VER - needs porting"; exit 1; }
mv "$WORK/mod/uas.c" "$WORK/mod/uas_arb.c"
printf 'obj-m := uas_arb.o\n' > "$WORK/mod/Makefile"
make -C "$WORK/linux-$VER" M="$WORK/mod" KBUILD_MODPOST_WARN=1 modules 2>&1 | grep -v "undefined!" || true
modinfo "$WORK/mod/uas_arb.ko" | grep -E '^(vermagic|name)'
sha256sum "$WORK/mod/uas_arb.ko"
echo "built: $WORK/mod/uas_arb.ko  (vermagic must equal \`uname -r\` on the Unraid server)"
