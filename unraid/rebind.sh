#!/bin/bash
# Move DS-SC5B ASM235CM bridges (174c:55aa) from built-in uas to uas_arb, if uas_arb is loaded.
[ -d /sys/bus/usb/drivers/uas_arb ] || exit 0
for i in ${1:+/sys/bus/usb/devices/$1} ${1:-/sys/bus/usb/devices/*:1.0}; do
  [ -e "$i/driver" ] || continue
  d=$(dirname $(readlink -f $i)); [ "$(cat $d/idVendor 2>/dev/null):$(cat $d/idProduct 2>/dev/null)" = "174c:55aa" ] || continue
  [ "$(basename $(readlink -f $i/driver))" = "uas" ] || continue
  id=$(basename $i); echo $id > /sys/bus/usb/drivers/uas/unbind; echo $id > /sys/bus/usb/drivers/uas_arb/bind
  logger -t uas_arb "rebound $id to uas_arb"
done
