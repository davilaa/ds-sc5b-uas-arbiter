# --- Add to /boot/config/go, ABOVE the "/usr/local/sbin/emhttp" line ---
# Loads uas_arb (patched UAS driver with device arbiter) and moves the DS-SC5B bridges onto it
# before the array starts. If the module does not match the running kernel (e.g. after an Unraid
# upgrade) it is skipped and the stock uas driver keeps the drives.
K=/boot/config/uas_arb/uas_arb.ko
if [ -f $K ] && [ "$(modinfo -F vermagic $K | cut -d" " -f1)" = "$(uname -r)" ]; then cp $K /tmp/uas_arb.ko && insmod /tmp/uas_arb.ko arb_max=3 arb_slice_ms=100 && cp /boot/config/uas_arb/99-uas-arb.rules /etc/udev/rules.d/ && udevadm control --reload && bash /boot/config/uas_arb/rebind.sh && logger -t uas_arb loaded; else logger -t uas_arb "skipped: module does not match kernel $(uname -r), using stock uas"; fi
# Do NOT shorten the SCSI timeout for these drives: spun-down disks need ~15 s to spin up.
