#!/usr/bin/env python3
# ana.py CAPTURE.pcapng : per-URB latency from a usbmon capture (tshark required).
# Prints the longest-latency URBs; a stalled UAS command shows as ~timeout-long DATA-IN/STATUS URBs.
import subprocess,collections,sys
f=sys.argv[1]
out=subprocess.run(['tshark','-r',f,'-T','fields','-E','separator=\t','-e','frame.time_relative','-e','usb.urb_id','-e','usb.urb_type','-e','usb.device_address','-e','usb.endpoint_address','-e','usb.urb_len','-e','usb.data_len','-e','usb.urb_status','-e','usb.transfer_type'],capture_output=True,text=True).stdout
S={}; lat=[]; last=collections.defaultdict(float); cnt=collections.Counter()
rows=[l.split('\t') for l in out.splitlines() if l]
print('urb events',len(rows))
open_at_end={}
for t,uid,typ,dev,ep,ulen,dlen,st,tt in rows:
    t=float(t); k=(dev,ep)
    if typ in ('83','S',"'S'"): S[uid]=(t,dev,ep,ulen)
    else:
        if uid in S:
            t0,d,e,ul=S.pop(uid); lat.append((t-t0,t0,t,d,e,ul,st)); cnt[(d,e)]+=1; last[(d,e)]=t
print('types seen', collections.Counter(r[2] for r in rows))
print('completions per dev/ep:', sorted(cnt.items()))
print('\nlongest latencies:')
for x in sorted(lat,reverse=True)[:25]: print('lat %.3fs  submit@%.3f done@%.3f dev %s ep %s len %s status %s'%x)
print('\nnever completed:', [(round(v[0],3),v[1],v[2],v[3]) for v in S.values()][:20])
