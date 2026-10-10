#!/usr/bin/env python3
"""Generate Haku/Resources/Colors.xcassets from colors.json. Do not hand-edit the catalog."""
import json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools/design-tokens/colors.json")
OUT = os.path.join(ROOT, "Haku/Resources/Colors.xcassets")
INFO = {"info": {"author": "xcode", "version": 1}}

def comps(value):
    hexpart, _, alpha = value.partition("@")
    h = hexpart.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return {"color-space": "srgb", "components": {
        "red": f"0x{r:02X}", "green": f"0x{g:02X}", "blue": f"0x{b:02X}",
        "alpha": f"{float(alpha) if alpha else 1.0:.3f}"}}

def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

def main():
    tokens = json.load(open(SRC))
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    write(os.path.join(OUT, "Contents.json"), INFO)
    for group, colors in tokens.items():
        if group.startswith("_"):
            continue
        gdir = os.path.join(OUT, group)
        write(os.path.join(gdir, "Contents.json"), {**INFO, "properties": {"provides-namespace": True}})
        for name, value in colors.items():
            if isinstance(value, list):
                entries = [
                    {"idiom": "universal", "color": comps(value[0])},
                    {"idiom": "universal", "color": comps(value[1]),
                     "appearances": [{"appearance": "luminosity", "value": "dark"}]},
                ]
            else:
                entries = [{"idiom": "universal", "color": comps(value)}]
            write(os.path.join(gdir, f"{name}.colorset", "Contents.json"), {**INFO, "colors": entries})
    print(f"wrote {OUT}")

if __name__ == "__main__":
    sys.exit(main())
