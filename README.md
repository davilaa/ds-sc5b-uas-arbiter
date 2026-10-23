# DS-SC5B UAS Arbiter: Unraid plugin

<a href="https://sabrent.com/products/ds-sc5b"><img align="right" width="240" src="https://cdn.shopify.com/s/files/1/0604/2461/8241/products/DS-SC5B-Main.jpg?v=1635797126&width=480" alt="Sabrent DS-SC5B 5-bay 3.5-inch SATA USB-C docking station: black aluminium case with five lockable bays and a power button per bay"></a>

**An Unraid plugin that lets you run all five bays of a Sabrent DS-SC5B USB enclosure as array drives, without the UAS resets and stalls that break parity checks and rebuilds, and without disabling UAS.**

If your Unraid syslog fills with `uas_eh_abort_handler` / `reset SuperSpeed Plus Gen 2x1 USB device` during a parity check, disk temperatures disappear, or the check crawls along at a few MB/s, this is for you.

> [!IMPORTANT]
> **Install in 3 steps:** add the plugin, reboot, raise two disk settings. That's it.

## ⚡ Install on Unraid

### Step 1: install the plugin

In the Unraid web UI go to **Plugins → Install Plugin**, paste this URL and click **Install**:

```
https://raw.githubusercontent.com/davilaa/ds-sc5b-uas-arbiter/main/plugin/uas-arb.plg
```

### Step 2: reboot

The plugin only switches drives over while the array is stopped, so it takes effect at the next boot. After the reboot, check **Settings → User Utilities → DS-SC5B UAS Arbiter**: it should show the arbiter loaded and all five bays attached.

### Step 3: raise Unraid's parity tunables

In **Settings → Disk Settings**, set **`md_num_stripes` = 32768** and choose **`md_sync_limit`**: keep **5** if the array is busy while checks run (cameras, Plex), or use **80** if it's idle. Without this, parity checks stay slow (~30 MB/s) even though the resets are gone.

<details><summary>Why, and measured speeds</summary>

Unraid's parity engine keeps only a few reads queued per disk by default, so every turn handoff costs time. With the arbiter, tune **Settings → Disk Settings**:

| Tunable | Default | Recommended | Parity speed (with arbiter, `arb_slice_ms=100`) |
|---|---|---|---|
| `md_sync_limit` | 5 | **5-80, see below** | 31 MB/s → 77 MB/s (with 1280 → 8192 stripes) |
| `md_num_stripes` | 1280 | **32768** (~600 MB RAM while a check runs; 8192 = ~130 MB) | → 127 MB/s with 8192 (149 idle); v3 + 32768: 162 MB/s idle |

**`md_sync_limit` is a trade-off.** It is the share of the stripe pool a parity check may use, so a high value gives the check priority over normal array I/O. With all five bays behind one USB link that is noticeable: on my server, at 80 the check ran at ~150 MB/s but NFS clients on the array (Frigate recording 24/7, Plex) became too slow. At **5** (the Unraid default) with **32768 stripes** the check still ran at **~63 MB/s** and the shares stayed usable, because 5% of 32768 stripes is more than the whole default pool.

* Server busy while checks run (cameras, media): keep `md_sync_limit=5`, raise `md_num_stripes` to 32768.
* Server idle (or checks run overnight with the Parity Check Tuning plugin): `md_sync_limit=80` for ~2.4× the speed.
* Note: after changing these, verify Settings → Disk Settings shows the value you saved before pressing Apply again; the form is filled from emhttp's in-memory value.

</details>

### What the plugin does

* At every boot, **before the array starts**, downloads (once, then cached on the flash) the `uas_arb` module built for your exact kernel from the [`modules` release](https://github.com/davilaa/ds-sc5b-uas-arbiter/releases/tag/modules), verifies its SHA-256 and loads it.
* Moves only the DS-SC5B bridges (ASM235CM behind a VIA VL822 hub) from `uas` to `uas_arb`.
* Adds **Settings → User Utilities → DS-SC5B UAS Arbiter**: on/off, `arb_max`, turn length, live status and counters, and a warning if the parity tunables above are still at their defaults.
* Never moves drives while the array is started. If you install it with the array running, it takes effect at the next boot.
* If there's no module for your kernel yet (e.g. right after an Unraid upgrade), it leaves the stock driver in place and shows a notification. To add a kernel, put `/usr/src/linux-*-Unraid/.config` into [`configs/`](configs/) as `<uname -r>.config` (pull request welcome). The [`build-modules`](.github/workflows/build-modules.yml) workflow then builds and publishes the module.

Supported Unraid versions: see [`configs/unraid-versions.txt`](configs/unraid-versions.txt) (Unraid version → kernel). The build workflow checks [releases.unraid.net](https://releases.unraid.net/json) **weekly**, extracts the kernel config of every new release ≥ 7.0.0 (from `bzfirmware`), and builds a module for it from that kernel's own `uas.c` plus [`patches/uas-arbiter.patch`](patches/uas-arbiter.patch). If the patch stops applying to a new kernel, that build fails and the plugin keeps the stock driver until it's ported.

**Tested on hardware:** Unraid 7.2.2 (6.12.54-Unraid). Other kernels are built automatically from the same patch but haven't been run on a DS-SC5B yet; please report results in an issue.

### Without the plugin (manual install)

1. Check your kernel: `uname -r` must print `6.12.54-Unraid`. For any other kernel, [build it](#building) first.
2. Copy the files to the flash drive:
   ```
   mkdir -p /boot/config/uas_arb
   cp prebuilt/6.12.54-Unraid/uas_arb.ko unraid/rebind.sh unraid/99-uas-arb.rules /boot/config/uas_arb/
   sha256sum /boot/config/uas_arb/uas_arb.ko   # compare with prebuilt/6.12.54-Unraid/SHA256SUMS
   ```
3. Back up `/boot/config/go`, then add the contents of [`unraid/go-snippet.sh`](unraid/go-snippet.sh) **above** the `/usr/local/sbin/emhttp` line.
4. In Settings → Disk Settings set `md_num_stripes=32768` (or 8192 if RAM is tight), and choose `md_sync_limit` (5 if the array is busy during checks, up to 80 if not; see [Step 3](#step-3-raise-unraids-parity-tunables)).
5. Reboot. Check:
   ```
   grep uas_arb /var/log/syslog          # "rebound … to uas_arb", "loaded"
   lsusb -t                              # the five Mass Storage interfaces show Driver=uas_arb
   cat /sys/module/uas_arb/parameters/arb_max   # 3
   ```
   Drive letters may change (e.g. sdb… → sdh…). That's harmless, because Unraid assigns array disks by serial.

**Live test without rebooting** (array **stopped**):
```
insmod uas_arb.ko arb_max=3 arb_slice_ms=100 && bash rebind.sh
```

**Disable:** `echo 0 > /sys/module/uas_arb/parameters/arb_max` (live), or remove the `go` lines and reboot.

**Unraid upgrades:** the module only loads if its vermagic matches the running kernel. After an upgrade the `go` snippet skips it (logged as `uas_arb: skipped …`) and the drives stay on the stock driver, so **rebuild** for the new kernel. The built-in `uas` is never disabled, so the drives always have a driver.

> [!NOTE]
> **Status: experimental, but working.** It runs on Unraid 7.2.2 (kernel 6.12.54-Unraid) with 5 array drives in a DS-SC5B. Parity checks run with **0 UAS aborts and 0 resets** at about **149 MB/s**. A full 27.3 TB parity check **completed with 0 sync errors and 0 UAS aborts/resets from the arbiter** (see [Validation](#validation)). Modules are built automatically for each new Unraid release (7.0 and later). Use at your own risk; this is an unofficial kernel module.

---

## The problem

With all five bays of a DS-SC5B busy (an Unraid parity check, a rebuild, or `dd` from every disk at once), Linux logs a stream of:

```
sd 9:0:0:0: [sdd] tag#5 uas_eh_abort_handler 0 uas-tag 2 inflight: CMD IN
scsi host9: uas_eh_device_reset_handler start
usb 12-1.3.1: reset SuperSpeed Plus Gen 2x1 USB device number 5 using xhci_hcd
scsi host9: uas_eh_device_reset_handler success
```

Each stall lasts ~30 s (the SCSI timeout), and the device is then reset. A parity check slows to almost nothing, and SMART queries hang, so Unraid's disk temperatures disappear. Retries usually hide the stalls from the array, but occasional I/O errors do get through.

Same enclosure, same symptom, unresolved:
[Sabrent forum: "Docking station on linux, random disconnects … unraid"](https://sabrent.com/community/xenforum/topic/106596/docking-station-on-linux-random-disconnects-with-hubextportstatus-failed-err-71-errors-unraid).

### Hardware inside the DS-SC5B

| Part | USB ID | Notes |
|---|---|---|
| 2 × VIA Labs VL822 (Q7) USB 3.2 Gen 2 hubs, **cascaded** | `2109:0822` (+ `2109:2822` USB 2 side) | hub 1 → bay 1 + hub 2; hub 2 → bays 2-5 |
| 5 × ASMedia **ASM235CM** USB-SATA bridges | `174c:55aa` | one per bay, UAS, 10 Gbps |

```
host xHCI ── hub1 (VL822) ─┬─ port 2: bridge ── bay 1  ("upstream bay")
                           └─ port 3: hub2 (VL822) ─┬─ port 1: bridge ── bay 2
                                                    ├─ port 2: bridge ── bay 3
                                                    ├─ port 3: bridge ── bay 4
                                                    └─ port 4: bridge ── bay 5
```

## Root cause (what the evidence shows)

* **It is not the cable or signal quality.** USB 3 hub *link error counters* (`GetPortErrorCount`) stay at **0 on every hub port** through dozens of resets ([`tools/perr.pl`](tools/perr.pl)).
* **The command is delivered; the data never comes back.** In a usbmon capture the READ command IU completes at the host in ~50 µs, but the DATA-IN and STATUS stream transfers for that tag **never complete** while the other bays keep working. xHCI debugfs shows the endpoint *running*, i.e. the host is waiting for the device's "data ready" (ERDY) notification, which never arrives.
* **It depends on which bays are busy, not on queue depth.** Sequential reads with fio, all read-only, 60 s each:

| Busy bays | Result |
|---|---|
| any **3** bays (including the upstream bay) | clean, ~250 MB/s each |
| the **4 bays behind hub 2** only (QD 1 and QD 8) | clean, ~1 GB/s total |
| **upstream bay + 3 bays behind hub 2** | 14 resets / 74 aborts |
| all **5** bays, QD 1 / 2 / 4 / 8 | ~24 resets per minute *regardless of queue depth* (aborts scale with QD) |

* It reproduces identically on Unraid's kernel 6.12.54 and on Ubuntu 26.04 / kernel 7.0, and with every hub/bridge firmware tried.

**Conclusion:** when hub 1 serves its own bay **and** 3+ busy bays through hub 2, data-ready notifications get lost in the hub cascade. This is a hardware data-path problem. Firmware doesn't touch it (see [what didn't work](#what-didnt-work)).

## The fix: a device arbiter in the UAS driver

`uas_arb` is the stock Linux `uas` driver plus a small arbiter:

* Each device has a **weight**: bay 1 (on the first hub, shallower in the USB tree than the others) weighs **`arb_upstream_weight` (2)**, the four bays behind the cascaded hub weigh 1. Devices may have commands in flight only while their total weight stays within **`arb_max` (4)**. That allows all four cascaded bays together (tested clean at ~1 GB/s), or bay 1 plus two cascaded bays, but never the stalling combination of bay 1 plus three cascaded bays. (v2 used a plain "any 3 devices" rule, which is `arb_upstream_weight=1 arb_max=3`.)
* A device that wants to issue while all slots are busy waits in a **FIFO line**. Its command is handed back to the SCSI layer as "busy" and retried; the device joins the line.
* A device keeps its slot until it goes idle, or until its turn (**`arb_slice_ms`**) expires while others are waiting. Then it stops taking new commands, drains, releases the slot and rejoins at the back of the line.
* When a slot frees, waiting devices are **woken immediately** (`blk_mq_run_hw_queues`), and `max_device_blocked = 1` keeps the SCSI retry delay to one cycle.
* Abort, reset and disconnect paths always release the slot, so a stuck device can't hold one.

It is built as a separate module **`uas_arb`** (USB driver name `uas_arb`), so it can run next to a kernel whose `uas` is built in (as on Unraid). A small script moves only the DS-SC5B bridges (`174c:55aa`) from `uas` to `uas_arb`. Everything else stays on the stock driver.

Module parameters (all writable at runtime under `/sys/module/uas_arb/parameters/`):

| Parameter | Default | Meaning |
|---|---|---|
| `arb_max` | 4 | max total weight of devices with commands in flight; **0 = arbiter off** (plain uas behaviour) |
| `arb_upstream_weight` | 2 | weight of a device that sits higher in the hub tree than the other managed devices (DS-SC5B bay 1); others weigh 1 |
| `arb_max_sectors` | 0 | max 512-byte sectors per command, applied at probe (0 = SCSI default 1024 = 512 KB; the plugin uses 4096 = 2 MB) |
| `arb_slice_ms` | 20 | turn length when others are waiting; **100 recommended** for Unraid parity checks (plugin default) |
| `arb_grants`, `arb_denies`, `arb_kicks` | — | read-only counters |

## Results

**Before (stock `uas`):**

* fio QD8 on all 5 bays: **118 aborts / 25 resets per minute**, one drive starved at 0 MB/s.
* Unraid parity check: **173 aborts in 4 minutes, 50 MB checked**, SMART hung (temperatures blank).

**After (`uas_arb`, `arb_max=3`):**

| Test | Aborts / resets | Throughput |
|---|---|---|
| fio QD8, all 5 bays, 10-minute soak (Ubuntu, kernel 7.0) | **0 / 0** | 133-195 MB/s per bay, ~840 MB/s total |
| Unraid, 4 parallel readers per disk: arbiter **off** (`arb_max=0`) vs **on** | off: 52 / 8 (+1 I/O error), on: **0 / 0** | — |
| Unraid parity check (non-correcting), containers running | **0 / 0** | 127 MB/s |
| Unraid parity check, idle system | **0 / 0** | **149 MB/s** |

**v3 (weighted rule), fio QD8 on all 5 bays (Ubuntu VM, 60 s each, 0 resets in every run):**

| Rule | slowest bay | total |
|---|---|---|
| v2: any 3 devices (`arb_upstream_weight=1 arb_max=3`) | 145 MB/s | 801 MB/s |
| v3: weighted (`arb_upstream_weight=2 arb_max=4`) | 161 MB/s | 882 MB/s |
| v3 + 2 MB commands (`arb_max_sectors=4096`) | 171 MB/s | 894 MB/s |
| v3 + 2 MB, **10-minute soak** | 158 MB/s | 859 MB/s, **0 resets** |

**v3 on a real Unraid parity check** (Unraid 7.2.2, non-correcting, start of the disks, nothing else using the array):

| Driver / setting | Parity speed |
|---|---|
| v2 (any 3 devices), `md_num_stripes=8192` | 149 MB/s |
| v3 (weighted + 2 MB commands), `md_num_stripes=8192` | 152-158 MB/s (+3-5%) |
| v3, `md_num_stripes=16384` | 158 MB/s |
| v3, `md_num_stripes=32768` | **162 MB/s (+9% vs v2)** |
| v3, `arb_slice_ms` 50 / 100 / 200 | no measurable difference |

0 aborts, 0 resets, 0 I/O errors throughout. The parity engine reads all disks in lockstep and waits for the slowest, so the fio gain (+11% for the slowest bay) only partly carries over; a deeper stripe pool recovers some of it.

## Building

* [`tools/build-for-unraid.sh`](tools/build-for-unraid.sh) `UNRAID_CONFIG [VERSION]` builds on any x86_64 Linux host. Copy `/usr/src/linux-<ver>-Unraid/.config` from the server.
* It downloads the matching upstream kernel source, runs `modules_prepare` with Unraid's config, and builds `src/` with `KBUILD_MODPOST_WARN=1`. Unraid has `CONFIG_MODVERSIONS` and module signing off.
* The build takes `drivers/usb/storage/uas.c` (and friends) from the target kernel's own source and applies [`patches/uas-arbiter.patch`](patches/uas-arbiter.patch), which adds the arbiter plus Unraid's own `uas-detect.h` tweak (Seagate `0bc2` enclosures never bind to uas). `src/` is a ready-patched reference copy for 6.12.54.
* The patch applies unchanged to v6.12.54 and v6.18.54 (`patch -p4` inside `drivers/usb/storage/`). The arbiter was first developed and tested on v7.0.

On a regular distro where `uas` is a module, you can also build the patch in-tree as `uas` and skip `rebind.sh`.

## What didn't work

| Attempt | Result |
|---|---|
| `usb-storage.quirks=174c:55aa:u` (UAS off, BOT) | **worse**: constant reset storm, md read errors |
| SCSI `queue_depth` | read-only on uas |
| `nr_requests=4`, `max_sectors_kb=128` | no change |
| `usbcore.quirks=2109:0822:k,174c:55aa:k` (no LPM) | no change |
| SCSI command timeout 5 s instead of 30 s | helps light `dd` loads, **fails a parity check** (173 aborts / 4 min), and breaks spin-down (every ~15 s spin-up times out). Keep the 30 s default. |
| VL822 hub firmware 9013 → 9043 (generic Q7) | no change |
| VL822 Tier1 `0984` (hub 1) + Tier2 `09C4` (hub 2) | no change |
| ASM235CM bridge firmware `200416d13c81` → `230830d17d80` (all 5) | no change |
| VIA hub "switch to 5 Gbps" register | volatile; lost on re-enumeration, not testable |
| Splitting drives (≤ 2 busy behind hub 2, e.g. 2 drives in another enclosure) | works, but you lose the bays |

More detail, raw numbers and the firmware notes are in [docs/investigation.md](docs/investigation.md).

## Limitations and notes

* **Heavy writes are not yet stress-tested.** Light concurrent writes (containers running during the parity check) were error-free. Rebuilds and parity *syncs* write heavily.
* The arbiter is **global**: it counts every device bound to `uas_arb`. Only bind the DS-SC5B bridges to it, as `rebind.sh` does. Binding other UAS disks would make them share the 3 slots.
* With all 5 bays busy, each bay gets about 3/5 of the time. Fewer than 4 busy bays never wait.
* **Disk spin-down works** with the plugin: Unraid spins idle DS-SC5B disks down normally (verified by the ~17 s spin-up delay on the next read), and a parity check carries on through a manual spin-down of all disks. The bay light goes dark while a disk is spun down.
* Tested only with the DS-SC5B (`2109:0822` + `174c:55aa`) behind an AMD xHCI. Other cascaded-hub enclosures may have the same problem, but the right `arb_max` may differ.

## Validation

* [x] fio read matrix and 10-minute soak (Ubuntu 26.04, kernel 7.0)
* [x] Unraid 6.12.54: arbiter on/off control test
* [x] Unraid parity check (non-correcting and correcting) under load: 0 aborts, 0 resets from the arbiter
* [x] Code review of the arbiter and all its hooks (lock order, lifetimes, slot accounting, every release path): no correctness or safety bugs; four minor items fixed in driver 3.1, see [CHANGELOG.md](CHANGELOG.md)
* [x] **Full 27.3 TB parity check to completion** (Unraid 7.2.2, finished 2026-10-22): **0 sync errors, 0 disk errors**. 54 h of running time (Unraid's average: 143.7 MB/s), 2 d 20 h elapsed including 6 manual pauses. Ran with the array in daily use (Frigate recording 24/7, Plex, backups), `md_sync_limit` 5-15, `md_num_stripes` 32768. Peak ~160 MB/s with an idle array. The only aborts/resets in the whole run came from a short SCSI timeout left over from earlier testing (spun-down disks need ~15 s to spin up); after restoring the 30 s default there were none. Disk spin-down worked throughout.
* [ ] Heavy write test (parity sync / rebuild)

## Repository layout

```
plugin/     uas-arb.plg (Unraid plugin, generated) and src/ (control script, settings page, defaults)
configs/    Unraid kernel configs + unraid-versions.txt; added/built automatically by .github/workflows/build-modules.yml
src/        uas_arb.c (patched uas.c, v6.12.54) + headers + Makefile
patches/    uas-arbiter.patch (against upstream drivers/usb/storage/, applied at build time)
prebuilt/   6.12.54-Unraid/uas_arb.ko + SHA256SUMS (for the manual install)
unraid/     go-snippet.sh, rebind.sh, 99-uas-arb.rules, 99-usb-das-timeout.rules (old experiment, don't use)
tools/      build-for-unraid.sh, unraid-kernel-config.sh (config from an Unraid release), ustress.sh, ft2.sh (fio matrix), perr.pl (hub link errors),
            vlreg.pl (VL82x vendor regs), ana.py/ana2.py (usbmon analysis), d51.py (8051 disasm),
            make-plg.py (assembles plugin/uas-arb.plg from plugin/src)
docs/       investigation.md
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Each `v<version>` tag is a GitHub Release with the same notes. The driver reports its own version (`modinfo uas_arb.ko`, `/sys/module/uas_arb/version`, and the plugin status page).

## License

GPL-2.0. `src/` is derived from the Linux kernel's `drivers/usb/storage/uas.c` (Hans de Goede, Matthew Wilcox, Sarah Sharp). The scripts are GPL-2.0 as well.
