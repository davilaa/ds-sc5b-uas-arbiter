# Investigation notes: DS-SC5B UAS stalls

All tests were **read-only** (raw `dd`/`fio --readonly` on the disks, or Unraid non-correcting parity checks) unless stated otherwise.

## Setup

* Host: AMD Ryzen 7 8845HS mini PC, Proxmox VE. Unraid 7.2.2 runs in a VM with the USB controller passed through by **PCIe** (xHCI `1022:15c1`), not per-device USB passthrough.
* An Ubuntu 26.04 VM (kernel 7.0.0) was given the same controller for experiments: usbmon, fio, building modules.
* Enclosure: Sabrent DS-SC5B on one USB-C 10 Gbps cable. Drives: 28 TB parity, 18/16/14/14 TB data (Seagate Exos, WD Ultrastar, refurbished Seagate).
* The enclosure reports as `2109:0822` (×2 hubs, bcdDevice 90.13 as shipped) and `174c:55aa` "ASMT ASM235CM" (×5, firmware `200416d13c81` as shipped).

## 1. Characterising the failure

* Log signature: `uas_eh_abort_handler … inflight: CMD IN` → `uas_eh_device_reset_handler` → `reset SuperSpeed Plus Gen 2x1 USB device`.
* Failing ports: always the bays **behind hub 2** (`x-1.3.N`). The bay on hub 1 (`x-1.2`) was never the one reset.
* Hub **link error counts** (USB 3 `GetPortErrorCount`, `bmRequestType 0xA3`, `bRequest 0x0D`):
  * 0 on all 8 hub ports, polled every 0.5 s through 18+ resets.
  * The hub1→hub2 link is never reset, so its counter can't have been cleared, and it stayed at 0.
  * So it isn't bit errors or signal integrity.

## 2. usbmon (Ubuntu VM, kernel 7.0)

Stall onset, one affected bay:

```
2.010375 sdi CMD-OUT  'S' len=32                 # READ(16) command IU submitted
2.010397 sdi CMD-OUT  'C' st=0                   # ...acknowledged by the bridge after 22 µs
2.010348 sdi STATUS   'S' len=112 (stream tag 1) # status pipe armed
2.010369 sdi DATA-IN  'S' len=524288 (tag 1)     # data pipe armed
   ... other bays complete reads every few ms ...
32.04    sdi DATA-IN  'C' st=-2 (killed after 30 s timeout)
```

* The command reaches the bridge, but no DATA-IN or STATUS ever completes for that tag.
* xHCI debugfs (`/sys/kernel/debug/usb/xhci/*/devices/NN/ep-context`) shows the stream endpoints in state **running** for the whole 30 s, i.e. the host is waiting for the device's ERDY.
* After the abort the endpoint goes **stopped** and is not restarted until the device reset, which makes each event cost 30-60 s. That's a secondary Linux issue.
* Stalls cluster at moments when several bays start transfers at once: test start, and right after each reset.

## 3. Which combinations fail (fio, `--rw=read --bs=512k --direct=1`, 60 s)

| Busy bays | QD | resets | aborts | MB/s per bay |
|---|---|---|---|---|
| bay1 + 2 behind hub2 | 8 | 0 | 0 | 251 / 269 / 257 |
| 3 behind hub2 | 8 | 0 | 0 | 268 / 257 / 235 |
| 4 behind hub2 | 1 | 0 | 0 | 262 / 256 / 234 / 250 |
| 4 behind hub2 | 8 | 0 | 0 | 262 / 256 / 236 / 252 |
| bay1 + 3 behind hub2 | 8 | 14 | 74 | 256 / 215 / 50 / 149 |
| all 5 | 1 | 24 | 22 | 263 / 69 / 109 / 121 / 82 |
| all 5 | 2 | 25 | 33 | — |
| all 5 | 4 | 23 | 68 | — |
| all 5 | 8 | 25 | 118 | 253 / 128 / 69 / 59 / 145 |

The stall *rate* is independent of queue depth; only the number of aborted commands per stall grows. It depends on the set of busy bays: **bay 1 plus 3 or more bays behind hub 2**.

## 4. Things tried that did not help

* **UAS off** (`usb-storage.quirks=174c:55aa:u`): reset storm (port reset every ~0.5 s) and md read errors. Worse than UAS.
* **Queue limits:** `queue_depth` is read-only on uas. `nr_requests=4` and `max_sectors_kb=128` changed nothing.
* **No LPM:** `usbcore.quirks=2109:0822:k,174c:55aa:k` changed nothing.
* **SCSI timeout 5 s** (udev rule, [`unraid/99-usb-das-timeout.rules`](../unraid/99-usb-das-timeout.rules)):

  | Load | timeout | Result |
  |---|---|---|
  | `dd` (QD ~2) | 3 s | no starvation, 37 resets/min |
  | `dd` (QD ~2) | 5 s | no starvation, 22 resets/min |
  | `dd` (QD ~2) | 10 s | one bay starved |
  | Unraid parity check | 5 s | 173 aborts / 4 min, 50 MB checked |

* **Hub firmware** (VIA `HUBIspTool`, run on Windows): 9013 → 9043 "Phantom" Q7; then Tier1 `0984` on hub 1 + Tier2 `09C4` on hub 2. All flashed fine; no behaviour change.
* **Bridge firmware** (ASMedia MPTool 3.6.3.0, `Format: UnChanged` so the IDs are kept): `200416d13c81` → `230830d17d80` on all 5. No change. The new firmware passes the drive's model string through in INQUIRY.
* **VIA "switch to 5 Gbps"** (`HUBIspTool /SFG`): reports success, but it's a volatile register and lost on re-enumeration, so it couldn't be tested on the target host.

## 5. VL822 firmware notes (for anyone who wants to dig further)

* **Image layout:**
  * 2-byte target header (`05 18` = Q7), code length at offset 6, padding to `0x2000`.
  * Plain **8051** code from file offset `0x2000` (address 0), standard vector table.
  * Trailer: checksum and `date "` + BCD date.
* **Register map:**
  * `0x90xx` is per-port USB3 PHY/link registers: page `0x90` upstream, `0x91`-`0x94` downstream ports 1-4.
  * Init writes the same analog table to every port: `+88=34 +9E=06 +8B=10 +8F=11 +91=87 +92=C1 +A0=90 +A2=45 +A6=9F +AF=6F +B4=04`, `+9A[5:3]=3`, `+AB[5:0]=+AC[5:0]=0x3F`. Global: `9886=18 9884=2C 988D=1F`.
  * The table is identical in every VIA image examined (Q5/Q7/Q8, Phantom/Hybrid, 9013, 9043, 0984, 09C4, 06B3, 08B3). Only a "Hybrid Tier2" image adds port-1 trims (`A2&=3F`, `A5[1:0]=2`, `A6[3:1]=3`).
* **Host access:** vendor control requests read/write XDATA (`bRequest = addr>>8`, `wValue = addr&0xff`, IN `0xC0` read, OUT `0x40` with `wIndex = value`), but only pages **`0xF0`-`0xFF`** are exposed (`tools/vlreg.pl`). Avoid `bRequest 0xC0`-`0xDF`: those are SPI flash commands (`0xC1`/`0xC4` read, `0xD1`/`0xD4` write/erase).
* The USB 3 data path (packet forwarding, ERDY routing) is not in the 8051 firmware; it's hardware. That's why no firmware or PHY change could fix this.
* **Flashing:**
  * `HUBIspTool` is headless. Switches: `/FWC` read chip version, `/FWB` read bin version, `/DUD` update only.
  * It needs `[Module_VL820_VL822_FW] VL822_FW1=/VL822_FW2=` naming bins in `.\Binfile`, and VIA's `vl810filter` upper filter on the hubs.

## 6. The arbiter

* Development (Ubuntu VM, fio QD8, all 5 bays):

  | Variant | resets | MB/s per bay | Notes |
  |---|---|---|---|
  | stock | 25 | 59-253 | |
  | `arb_max=3`, 100 ms, first-grab | 0 | 113-156 | |
  | `arb_max=3`, 20 ms, first-grab | 0 | 145-204 | |
  | `arb_max=3`, 10/5 ms, first-grab | 0 | one bay **starved** | fairness bug |
  | `arb_max=3`, FIFO, 10/20/50 ms | 0 | 128-194 | |
  | `arb_max=4` | 13 | — | 4 is unsafe |
  | 10-minute soak, FIFO, 20 ms | 0 | 133-195 | 1.28 M grants |

* **Unraid** (kernel 6.12.54, module built from upstream source and Unraid's `.config`), 4 parallel readers per disk: arbiter off **52 aborts / 8 resets / 1 I/O error**; on: **0 / 0 / 0**.
* **Unraid parity check** (0 aborts / 0 resets throughout):

  | Settings | MB/s |
  |---|---|
  | defaults (`md_sync_limit=5`, `md_num_stripes=1280`) | 31 |
  | `md_sync_limit=50` | 63 |
  | `md_sync_limit=80` | 77 |
  | + `md_num_stripes=4096` | 102 |
  | + `arb_slice_ms=50` | 113 |
  | + `arb_slice_ms=100` | 119 |
  | + `md_num_stripes=8192` | 127 |
  | `arb_slice_ms=200` | 121 |
  | idle system (no containers), recommended settings | **149** |

* v1 → v2: v2 wakes waiting devices immediately on release and sets `max_device_blocked=1`. On its own that didn't raise parity speed (Unraid's shallow sync pipeline was the limit), but it makes handoffs cheap once the tunables are raised.

## 7. v3 (weighted arbiter) on a real Unraid parity check

Unraid 7.2.2, non-correcting check, measured over 60-90 s windows near the start of the disks, nothing else
using the array, `md_sync_limit=80`, `arb_max=4 arb_upstream_weight=2 arb_max_sectors=4096`:

| Setting | MB/s |
|---|---|
| v2 for reference (`arb_max=3`, stripes 8192, slice 100) | 149 |
| v3, stripes 8192, slice 100 | 157 / 154 / 152 / 153 / 158 / 154 |
| v3, slice 50 | 155 |
| v3, slice 200 | 154 |
| v3, stripes 16384 | 158 |
| v3, stripes 32768 | 162 (+~600 MB RAM used) |

Turn length doesn't matter for the lockstep parity engine. A deeper stripe pool helps a little. 0 aborts/resets.
