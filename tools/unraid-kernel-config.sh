#!/bin/bash
# unraid-kernel-config.sh (UNRAID_VERSION | --bzfirmware FILE) OUTDIR
#
# Extracts the Unraid kernel .config and writes OUTDIR/<kernelrelease>.config, printing the kernel
# release. Unraid ships it as /usr/src/linux-<ver>-Unraid/.config; /usr is the bzfirmware squashfs,
# so the file is src/linux-<ver>-Unraid/.config inside bzfirmware.
#   UNRAID_VERSION     e.g. 7.3.3 - downloads the release zip listed at https://releases.unraid.net/json
#   --bzfirmware FILE  use a local bzfirmware (e.g. /boot/bzfirmware copied from a server)
# Needs: curl, unzip, python3, unsquashfs (squashfs-tools).
set -euo pipefail
OUT=${@: -1}; mkdir -p "$OUT"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if [ "$1" = --bzfirmware ]; then
  FW=$(readlink -f "$2")
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
  unzip -q -o "$TMP/unraid.zip" bzfirmware -d "$TMP"
  rm -f "$TMP/unraid.zip"
  FW=$TMP/bzfirmware
fi
unsquashfs -q -n -d "$TMP/usr" "$FW" src >/dev/null
CFG=$(ls "$TMP"/usr/src/linux-*/.config 2>/dev/null | head -1)
[ -n "$CFG" ] || { echo "no src/linux-*/.config inside bzfirmware" >&2; exit 1; }
KR=$(basename "$(dirname "$CFG")"); KR=${KR#linux-}
cp "$CFG" "$OUT/$KR.config"
echo "$KR"
