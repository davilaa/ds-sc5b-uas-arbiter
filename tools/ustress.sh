#!/bin/bash
# ustress.sh [RUNTIME] [STREAMS_PER_DISK] : READ-ONLY parallel O_DIRECT dd load on every disk behind an
# ASMedia 174c:55aa bridge, then report MB/s per disk and UAS aborts/resets from dmesg. (No fio needed.)
RT=${1:-60}; N=${2:-4}
DEVS=$(for b in /sys/block/sd*; do d=$(readlink -f $b/device); u=$d; while [ "$u" != "/" ] && [ ! -f $u/idVendor ]; do u=$(dirname $u); done; [ "$(cat $u/idVendor 2>/dev/null):$(cat $u/idProduct 2>/dev/null)" = "174c:55aa" ] && basename $b; done)
echo "disks: $DEVS"; dmesg -C; declare -A S
for d in $DEVS; do S[$d]=$(awk -v d=$d '$3==d{print $6}' /proc/diskstats); done
for d in $DEVS; do for k in $(seq 1 $N); do timeout $RT dd if=/dev/$d of=/dev/null bs=1M iflag=direct skip=$(( (RANDOM*N+k)*40 )) 2>/dev/null & done; done
wait
for d in $DEVS; do e=$(awk -v d=$d '$3==d{print $6}' /proc/diskstats); echo -n "$d:$(( (e-S[$d])*512/RT/1000000 ))MB/s "; done; echo
P=/sys/module/uas_arb/parameters
echo "streams/disk=$N aborts=$(dmesg | grep -c uas_eh_abort) resets=$(dmesg | grep -c 'reset SuperSpeed') ioerr=$(dmesg | grep -c 'I/O error')" $( [ -d $P ] && echo "arb_max=$(cat $P/arb_max) grants=$(cat $P/arb_grants) denies=$(cat $P/arb_denies)")
