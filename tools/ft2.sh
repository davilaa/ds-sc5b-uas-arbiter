#!/bin/bash
# ft2.sh "sdX sdY ..." [QD] [RUNTIME] : READ-ONLY fio sequential read on the listed disks at queue depth QD;
# reports MB/s per disk and UAS resets/aborts. Used to build the which-combination-fails test matrix.
# ft2.sh "DEVS" QD RUNTIME
DEVS=$1; QD=${2:-8}; RT=${3:-60}
for d in $DEVS; do echo 5 > /sys/block/$d/device/timeout; done
dmesg -C; args=""; for d in $DEVS; do args="$args --name=$d --filename=/dev/$d --offset=$((RANDOM%500+100))g"; done
fio --readonly --direct=1 --rw=read --bs=512k --iodepth=$QD --ioengine=libaio --time_based --runtime=$RT --output-format=terse --terse-version=3 $args 2>/dev/null | awk -F';' '{printf "%s:%dMB/s ", $3, $7/1024}'
echo; echo "devs=[$DEVS] QD=$QD resets=$(dmesg | grep -c 'reset SuperSpeed') aborts=$(dmesg | grep -c uas_eh_abort)"
