# Changelog

Versions are dated (`YYYY.MM.DD[.n]`) and apply to the Unraid plugin; the driver carries its own
`MODULE_VERSION` (shown by `modinfo uas_arb.ko` and in the plugin's status page).

## 2026.10.19 — driver 3.1 (code-review fixes), plugin 2026.10.19

### Driver `uas_arb` 3.1

A full read-through of the arbiter and of every place it hooks into the stock UAS driver.
**No correctness or safety bugs were found.** Verified in particular:

* lock ordering is `host_lock → devinfo->lock → arb_lock` everywhere; the wake-up worker drops
  `arb_lock` before touching SCSI hosts (no deadlock path);
* devices are unlisted before `scsi_remove_host`; the wake-up worker takes host references under
  `arb_lock`; module exit cancels the worker after deregistering (no use-after-free);
* the slot token and `arb_weight_held` are always set/cleared together, so `arb_weight_used` cannot
  drift or go negative;
* every path that drops a command releases the slot: completion, abort, device reset, disconnect,
  the three error returns in `queuecommand`, and pre-reset/suspend (which wait for commands);
* runtime parameter changes (`arb_max=0` while slots are held, weight or limit changes) resolve as
  holders release; a heavy waiter at the head of the line is admitted within two drain cycles.

Four minor items were fixed:

1. **Fairness glitch.** After a drive ended its turn for a waiter, re-acquiring a slot within 5 ms
   (possible when capacity was free) kept the old turn start under the "short idle gaps continue the
   same turn" rule, so the drive was judged over its slice at once and drained again after a single
   command, for up to four slices (400 ms at the default 100 ms). A draining release now flags
   `arb_new_turn`, and the next acquisition starts a fresh turn.
2. **Hardening.** `arb_slice_ms` ≤ 0 written directly to sysfs (the plugin validates, sysfs does not)
   produced zero-length slices. Clamped to 1 jiffy.
3. **Unlocked read made explicit.** `arb_maybe_release()` peeks at the token outside `arb_lock`. The
   race is benign (the only other writer is `arb_unlist()` on disconnect and the locked path
   re-checks), but `arb_token` is now a `bool` with its own storage and is read with `READ_ONCE()`,
   with a comment. (It was a bit-field, which `READ_ONCE()` cannot be applied to.)
4. **Dead field removed.** `arb_cool_until` was a leftover from the v1 arbiter.

Also: `MODULE_VERSION("3.1")`, and a comment in the abort handler noting that the slot is freed a few
microseconds before the stalled data URBs finish being killed (error recovery of an already stalled
device; cannot provoke a stall).

Behaviour is otherwise unchanged. Compile-tested with `W=1` (no warnings in `uas_arb.c`) against
6.12.54-Unraid and 7.0.0-38-generic; the patch applies unchanged to upstream 6.6.78, 6.12.54,
6.18.54 and 7.0. At release time the author's server was mid-way through a parity check on
driver 3.0, so 3.1 had not yet run on hardware; it is picked up automatically at the next boot.

### Plugin 2026.10.19

* Status page shows the driver version (`/sys/module/uas_arb/version`).
* Added this changelog and a release workflow (a `v*` tag creates a GitHub Release from it).

### Upgrading

* Plugins → Check for Updates → update. The plugin never moves drives while Unraid is running;
  the new module is downloaded, verified and loaded at the **next boot** (`uas-arb: a newer uas_arb
  build … is available` in syslog). Nothing else to do.

## 2026.10.18.6

* `md_sync_limit` documented as a trade-off instead of a requirement: at 80 the check ran ~150 MB/s
  but NFS clients (Frigate, Plex) became too slow; at 5 with 32768 stripes it still ran ~63 MB/s.
  The plugin now warns only when `md_num_stripes` < 8192.

## 2026.10.18.5

* Recommend `md_num_stripes=32768` (v3 parity check 162 MB/s vs 149 MB/s on v2; ~600 MB RAM
  while a check runs). Measurements in the README.

## 2026.10.18.4

* **Fix:** never move drives between drivers once Unraid's `emhttpd` is running. Moving a bridge
  re-creates its disk under a new device name; the array then failed to start ("Start error",
  `md: lock_bdev error: -2`) until reboot. Drives are now only moved at boot, before `emhttpd`.

## 2026.10.18.3 — driver 3.0

* Driver 3.0: **weighted arbiter**. Bay 1 (on the first hub) weighs `arb_upstream_weight` (2), the
  bays behind the cascaded hub weigh 1, limit `arb_max` (4). All four cascaded bays may now run
  together, bay 1 + three cascaded bays never. fio: slowest bay 145 → 161-171 MB/s, 10-minute soak
  0 resets. Optional larger commands (`arb_max_sectors`, plugin default 2 MB).
* Plugin: new settings (limit, bay-1 weight, turn length, command size); refreshes the cached module
  when a newer build is published; passes only the parameters the cached build supports.
* Modules are built from each kernel's own `uas.c` plus the patch; Unraid 7.3 supported (kernel
  config is read from `bzmodules`); new Unraid releases are picked up weekly by the build workflow.

## 2026.10.18.2

* **Fix:** re-connected bridges are moved to `uas_arb` (udev `add` rule + detached rebind; Unraid's
  udev does not deliver `bind` events to rules).

## 2026.10.18.1

* **Fix:** plugin updates now replace the previous version's files (the plugin manager skips files
  that already exist).
* Recognise the DS-SC5B when it falls back to USB 2; warn when the enclosure is not on a USB 3 link.

## 2026.10.18 — driver 2.0

* Initial plugin release. Driver 2.0: "any 3 devices" arbiter with FIFO turns and immediate wake-up
  of waiting devices; `max_device_blocked = 1`.
