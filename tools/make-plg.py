#!/usr/bin/env python3
"""make-plg.py VERSION [CHANGES...] : assemble plugin/uas-arb.plg from plugin/src/*.

The .plg is self-contained (scripts and settings page are INLINE); only the kernel module is
downloaded at run time, per kernel, from the GitHub release named "modules".
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "plugin" / "src"
version = sys.argv[1]
changes = sys.argv[2:] or ["Release"]

def cdata(name):
    t = (SRC / name).read_text()
    assert "]]>" not in t, f"{name} contains ]]>"
    return f"<![CDATA[\n{t}]]>"

readme = """**DS-SC5B UAS Arbiter**

Loads a patched Linux UAS driver (`uas_arb`) that limits how many drives in a Sabrent DS-SC5B
(2x VIA VL822 + 5x ASMedia ASM235CM) may have commands in flight at once. Stops the
`uas_eh_abort_handler` / USB reset loops during parity checks. Settings: Settings > User Utilities.
"""

plg = f"""<?xml version='1.0' standalone='yes'?>
<!DOCTYPE PLUGIN [
<!ENTITY name      "uas-arb">
<!ENTITY author    "davilaa">
<!ENTITY version   "{version}">
<!ENTITY repo      "davilaa/ds-sc5b-uas-arbiter">
<!ENTITY gitURL    "https://raw.githubusercontent.com/&repo;/main">
<!ENTITY pluginURL "&gitURL;/plugin/&name;.plg">
<!ENTITY plugin    "/boot/config/plugins/&name;">
<!ENTITY emhttp    "/usr/local/emhttp/plugins/&name;">
]>

<PLUGIN name="&name;" author="&author;" version="&version;" pluginURL="&pluginURL;"
        launch="Settings/UASArb" icon="hdd-o" min="7.0.0"
        support="https://github.com/&repo;/issues">

<CHANGES>
###&version;
{chr(10).join("- " + c for c in changes)}
</CHANGES>

<!-- remove files of a previous version first: the plugin manager skips files that already exist -->
<FILE Run="/bin/bash">
<INLINE>
rm -rf &emhttp;
</INLINE>
</FILE>

<!-- settings defaults -->
<FILE Name="&emhttp;/default.cfg">
<INLINE>
{(SRC / "default.cfg").read_text()}</INLINE>
</FILE>

<!-- control script -->
<FILE Name="&emhttp;/scripts/uas-arb" Mode="0755">
<INLINE>{cdata("uas-arb")}</INLINE>
</FILE>

<!-- settings page -->
<FILE Name="&emhttp;/UASArb.page">
<INLINE>{cdata("UASArb.page")}</INLINE>
</FILE>

<FILE Name="&emhttp;/README.md">
<INLINE><![CDATA[
{readme}]]></INLINE>
</FILE>

<!-- install / every boot: load the module before the array starts -->
<FILE Run="/bin/bash">
<INLINE>
mkdir -p &plugin;/modules
# warn about a leftover manual setup from /boot/config/go
if grep -q "uas_arb.ko" /boot/config/go 2>/dev/null; then
  echo "NOTE: /boot/config/go still loads uas_arb manually; remove those lines, the plugin handles it now."
fi
&emhttp;/scripts/uas-arb start
echo ""
echo "DS-SC5B UAS Arbiter &version; installed. Settings > User Utilities > DS-SC5B UAS Arbiter"
</INLINE>
</FILE>

<!-- uninstall -->
<FILE Run="/bin/bash" Method="remove">
<INLINE>
&emhttp;/scripts/uas-arb stop
rm -rf &emhttp; &plugin;
rm -f /etc/udev/rules.d/99-uas-arb.rules
echo "DS-SC5B UAS Arbiter removed. If the array was started, reboot to return the drives to the stock uas driver."
</INLINE>
</FILE>

</PLUGIN>
"""
out = ROOT / "plugin" / "uas-arb.plg"
out.write_text(plg)
print(f"wrote {out} ({len(plg)} bytes)")
