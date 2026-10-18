#!/usr/bin/env python3
# ana2.py CAPTURE.pcapng START END : UAS pipe timeline (CMD-OUT/DATA-IN/STATUS) between START and END seconds.
# Edit `names` to map usbmon device addresses to disk names.
import subprocess,sys
out=subprocess.run(['tshark','-r',sys.argv[1],'-Y',f'frame.time_relative>={sys.argv[2]} && frame.time_relative<={sys.argv[3]}','-T','fields','-E','separator=\t','-e','frame.time_relative','-e','usb.urb_id','-e','usb.urb_type','-e','usb.device_address','-e','usb.endpoint_address','-e','usb.urb_len','-e','usb.data_len','-e','usb.urb_status'],capture_output=True,text=True).stdout
names={'3':'sdb(hub1)','5':'sdg','6':'sdh','7':'sdi','8':'sdj'}
epn={'0x04':'CMD-OUT','0x81':'DATA-IN','0x83':'STATUS','0x02':'DATA-OUT'}
for l in out.splitlines():
    t,u,ty,d,e,ul,dl,st=l.split('\t')
    if d in names and e in epn:
        print(f"{float(t):.6f} {names[d]:10s} {epn[e]:8s} {ty} len={ul:>6} got={dl:>6} st={st} id={u[-5:]}")
