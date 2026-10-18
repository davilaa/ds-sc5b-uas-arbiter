# Unraid kernel configs

One file per Unraid kernel, named `<uname -r>.config`, e.g. `6.12.54-Unraid.config`.
Copy it from a running server: `cp /usr/src/linux-*-Unraid/.config /boot/<uname -r>.config`.

Pushing a new config here makes the `build-modules` workflow build `uas_arb-<kernel>.ko` and attach it
(plus a `.sha256`) to the `modules` release, where the Unraid plugin downloads it automatically.
