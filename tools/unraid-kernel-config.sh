#!/bin/bash
# unraid-kernel-config.sh (UNRAID_VERSION | IMAGE_DIR) OUTDIR
#
# Extracts the Unraid kernel .config and writes OUTDIR/<kernelrelease>.config, printing the kernel
# release. Up to 7.2 it is /usr/src/linux-<ver>-Unraid/.config inside bzfirmware (= /usr); from 7.3
# /usr is bzmodules and the file is named 'config'. bzfirmware, bzmodules and bzroot are all searched.
#   UNRAID_VERSION     e.g. 7.3.3 - downloads the release zip listed at https://releases.unraid.net/json
#   IMAGE_DIR          a local directory containing bzfirmware / bzmodules / bzroot (e.g. copied from /boot)
# Needs: curl, unzip, python3, unsquashfs (squashfs-tools).
set -euo pipefail
OUT=${@: -1}; mkdir -p "$OUT"
TMP=$(mktemp -d); [ -n "${KEEP:-}" ] || trap 'rm -rf "$TMP"' EXIT   # KEEP=1 keeps the downloaded images
if [ -d "$1" ]; then
  IMG=$(readlink -f "$1")                       # directory with bzfirmware/bzmodules/bzroot
else
  VER=$1
  URL=$(curl -fsSL https://releases.unraid.net/json | python3 -c "
import json,sys
v=sys.argv[1]
for r in json.load(sys.stdin):
    if r.get('version')==v: print(r['url']); break
" "$VER")
  [ -n "$URL" ] || { echo "Unraid $VER not found in releases.unraid.net/json" >&2; exit 1; }
  echo "downloading $URL" >&2
  curl -fsSL --retry 3 -o "$TMP/unraid.zip" "$URL"
  unzip -q -o "$TMP/unraid.zip" 'bzfirmware' 'bzmodules' 'bzroot' -d "$TMP/img"
  rm -f "$TMP/unraid.zip"
  IMG=$TMP/img
fi
CFG=""
# 1) squashfs images (Unraid <= 7.2: bzfirmware = /usr, so src/linux-*/.config; later layouts vary)
for f in bzfirmware bzmodules; do
  [ -f "$IMG/$f" ] || continue
  path=$(unsquashfs -l "$IMG/$f" 2>/dev/null | sed -n 's#^squashfs-root/##p' | grep -E '(^|/)linux-[^/]*-Unraid/\.?config$|/build/\.config$' | head -1 || true)
  if [ -n "$path" ]; then
    unsquashfs -q -n -d "$TMP/x" "$IMG/$f" "$path" >/dev/null && CFG="$TMP/x/$path" && echo "found $path in $f" >&2 && break
  fi
done
# 2) bzroot (early cpio + xz cpio)
if [ -z "$CFG" ] && [ -f "$IMG/bzroot" ]; then
  OFF=$(python3 -c "
import sys
d=open(sys.argv[1],'rb').read(); t=d.find(b'TRAILER!!!')
i=d.find(b'\xfd7zXZ\x00', t if t>=0 else 0); print(i if i>=0 else '')" "$IMG/bzroot" || true)
  if [ -n "$OFF" ]; then
    mkdir -p "$TMP/r"
    ( cd "$TMP/r" && tail -c +$((OFF+1)) "$IMG/bzroot" | xz -dc 2>/dev/null | cpio -idm --quiet '*linux-*-Unraid/.config' '*linux-*-Unraid/config' 2>/dev/null ) || true
    CFG=$(find "$TMP/r" -path '*linux-*-Unraid/.config' -o -path '*linux-*-Unraid/config' 2>/dev/null | head -1 || true)
    [ -n "$CFG" ] && echo "found ${CFG#$TMP/r/} in bzroot" >&2
  fi
fi
[ -n "$CFG" ] && [ -f "$CFG" ] || { echo "no Unraid kernel .config found in bzfirmware/bzmodules/bzroot" >&2; exit 1; }
# kernel release from the directory name, else from the config header + LOCALVERSION
KR=$(echo "$CFG" | grep -oE 'linux-[0-9][^/]*-Unraid' | head -1 | sed 's/^linux-//' || true)
if [ -z "$KR" ]; then
  KR=$(sed -n 's/^# Linux\/x86 \([0-9.]*\).*Kernel Configuration/\1/p' "$CFG")$(sed -n 's/^CONFIG_LOCALVERSION="\(.*\)"/\1/p' "$CFG")
fi
cp "$CFG" "$OUT/$KR.config"
echo "$KR"
