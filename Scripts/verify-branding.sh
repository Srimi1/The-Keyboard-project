#!/usr/bin/env bash
# Deterministic branding validation for the monochrome production pipeline.
# Uses only built-in macOS/shell tools (bash, sips, cmp, and python3 stdlib).
# No network, no signing identity, no third-party runtime dependency.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APPICONSET="Sources/HostApp/Assets.xcassets/AppIcon.appiconset"
CONTENTS="$APPICONSET/Contents.json"
BRANDING="assets/branding"
MANIFEST="$BRANDING/manifest.json"
RENDERER="Scripts/render-brand-assets.swift"

fail() { echo "BRANDING CHECK FAILED: $1" >&2; exit 1; }

# 1. Catalog must exist and be valid JSON.
python3 -E - "$CONTENTS" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
images = doc.get("images")
assert isinstance(images, list) and len(images) >= 1, "Contents.json must list at least one image"
for entry in images:
    assert isinstance(entry.get("filename"), str) and entry["filename"], "each image needs a filename"
    assert entry.get("idiom") == "universal", "app icon idiom must be universal"
    assert entry.get("size") == "1024x1024", "app icon size must be 1024x1024"
PY

# 2. Every catalog entry must reference an existing opaque 1024x1024 PNG.
# 3. No stale PNG may linger in the appiconset unreferenced.
python3 -E - "$ROOT" "$APPICONSET" "$CONTENTS" <<'PY'
import json, subprocess, sys
from pathlib import Path
root, iconset, contents = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
doc = json.loads((root / contents).read_text(encoding="utf-8"))
listed = [e["filename"] for e in doc["images"]]

def sips_prop(path, key):
    out = subprocess.run(["sips", "-g", key, str(path)],
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if key in line:
            return line.split(":", 1)[1].strip()
    raise AssertionError(f"sips missing {key} for {path}")

for filename in listed:
    p = root / iconset / filename
    assert p.is_file(), f"catalog references missing file {iconset}/{filename}"
    assert sips_prop(p, "pixelWidth") == "1024", f"{filename}: pixelWidth must be 1024"
    assert sips_prop(p, "pixelHeight") == "1024", f"{filename}: pixelHeight must be 1024"
    assert sips_prop(p, "format").lower() == "png", f"{filename}: format must be png"
    assert sips_prop(p, "hasAlpha") == "no", f"{filename}: app icon must be opaque (hasAlpha no)"

on_disk = sorted(p.name for p in (root / iconset).glob("*.png"))
assert sorted(listed) == on_disk, (
    f"stale active-icon files: catalog lists {sorted(listed)} but directory has {on_disk}")
assert not (root / iconset / "AppIcon-1024.png").exists(), (
    "stale legacy AppIcon-1024.png still present in appiconset")
PY

# 4. Manifest must be valid JSON with the monochrome palette and a resolvable renderer.
python3 -E - "$ROOT" "$MANIFEST" "$BRANDING" <<'PY'
import json, sys
from pathlib import Path
root, manifest_path, branding = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
doc = json.loads((root / manifest_path).read_text(encoding="utf-8"))
assert doc.get("schemaVersion") == 1, "manifest schemaVersion must be 1"
palette = doc.get("palette", {})
assert palette.get("black", "").upper() == "#000000", "palette black must be #000000"
assert palette.get("white", "").upper() == "#FFFFFF", "palette white must be #FFFFFF"
renderer = doc.get("renderer")
assert isinstance(renderer, str) and renderer, "manifest renderer must be a non-empty path"
resolved = (root / branding / renderer).resolve()
assert resolved.is_file(), f"manifest renderer missing: {renderer} -> {resolved}"
# Concepts are history and must be preserved.
concepts = sorted((root / branding / "concepts").glob("*.jpg"))
assert len(concepts) >= 1, "branding concepts must be preserved as history"
PY

# 5. Every manifest-referenced production file must exist.
python3 -E - "$ROOT" "$MANIFEST" "$BRANDING" <<'PY'
import json, sys
from pathlib import Path
root, manifest_path, branding = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
doc = json.loads((root / manifest_path).read_text(encoding="utf-8"))

PATH_KEYS = {"source", "export", "archivedExport", "renderer", "activeIcon"}
ARRAY_KEYS = {"productionSources", "previews", "previewExports", "rendererOutputs", "exports"}

def collect(node):
    refs = []
    if isinstance(node, dict):
        for key, value in node.items():
            if key in PATH_KEYS and isinstance(value, str):
                refs.append(value)
            elif key in ARRAY_KEYS and isinstance(value, list):
                refs.extend(x for x in value if isinstance(x, str))
            else:
                refs.extend(collect(value))
    elif isinstance(node, list):
        for item in node:
            refs.extend(collect(item))
    return refs

missing = []
for ref in collect(doc):
    candidate = (root / branding / ref)
    if not candidate.is_file():
        missing.append(f"{ref} (resolved to {candidate})")
assert not missing, "manifest references missing files:\n" + "\n".join(missing)
PY

# 6. Renderer-declared outputs must exactly match the manifest and exist.
python3 -E - "$ROOT" "$RENDERER" "$MANIFEST" "$BRANDING" <<'PY'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
source = (root / sys.argv[2]).read_text(encoding="utf-8")
outputs = re.findall(r'\(\s*"([^"]+)"\s*,\s*\d+\s*\)', source)
assert outputs, "renderer declares no outputs"
missing = [o for o in outputs if not (root / o).is_file()]
assert not missing, "renderer output missing:\n" + "\n".join(missing)

manifest_path, branding = Path(sys.argv[3]), Path(sys.argv[4])
manifest = json.loads((root / manifest_path).read_text(encoding="utf-8"))
entries = [item for item in manifest.get("generations", [])
           if item.get("role") == "monochrome-logo-direction"]
assert len(entries) == 1, "manifest must contain exactly one monochrome-logo-direction entry"
declared = entries[0].get("rendererOutputs")
assert isinstance(declared, list), "monochrome manifest entry needs rendererOutputs"
resolved = [str((branding / item).resolve()) for item in declared]
expected = [str((root / item).resolve()) for item in outputs]
assert sorted(resolved) == sorted(expected), (
    f"manifest rendererOutputs {declared} do not exactly match renderer outputs {outputs}")
PY

# 7. Production PNGs must be opaque (no alpha, no tRNS) and achromatic (R==G==B).
#    Full PNG unfiltering is implemented below with stdlib only so filtered
#    scanlines cannot hide a chromatic pixel.
python3 -E - "$ROOT" <<'PY'
import struct, sys, zlib
from pathlib import Path
root = Path(sys.argv[1])
targets = [
    "Sources/HostApp/Assets.xcassets/AppIcon.appiconset/AppIcon-Monochrome-1024.png",
    "assets/branding/exports/app-icon-1024.png",
    "assets/branding/exports/app-icon-preview-256.png",
    "assets/branding/exports/app-icon-preview-64.png",
]

def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

def unfilter(raw, w, h, ch):
    stride = w * ch
    out = bytearray(len(raw) - h)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = raw[y * (stride + 1)]
        assert f in (0, 1, 2, 3, 4), f"unsupported PNG filter {f}"
        line = raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)]
        cur = bytearray(stride)
        for i in range(stride):
            a = cur[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            x = line[i]
            if f == 0:
                v = x
            elif f == 1:
                v = (x + a) & 0xFF
            elif f == 2:
                v = (x + b) & 0xFF
            elif f == 3:
                v = (x + ((a + b) >> 1)) & 0xFF
            else:
                v = (x + paeth(a, b, c)) & 0xFF
            cur[i] = v
        out[pos:pos + stride] = cur
        prev = cur
        pos += stride
    return bytes(out)

for rel in targets:
    data = (root / rel).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{rel}: not a PNG"
    off, width, height, bitdepth, colortype, interlace = 8, None, None, None, None, None
    idat = b""
    saw_trns = False
    while off < len(data):
        ln = struct.unpack(">I", data[off:off + 4])[0]
        typ = data[off + 4:off + 8]
        chunk = data[off + 8:off + 8 + ln]
        if typ == b"IHDR":
            width, height, bitdepth, colortype, comp, filt, interlace = struct.unpack(">IIBBBBB", chunk)
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"tRNS":
            saw_trns = True
        elif typ == b"IEND":
            break
        off += 12 + ln
    assert (width, height) == {"app-icon-1024.png": (1024, 1024),
                               "AppIcon-Monochrome-1024.png": (1024, 1024),
                               "app-icon-preview-256.png": (256, 256),
                               "app-icon-preview-64.png": (64, 64)}[Path(rel).name], f"{rel}: unexpected dimensions"
    assert bitdepth == 8, f"{rel}: bit depth must be 8"
    assert colortype == 2, f"{rel}: color type must be 2 (opaque RGB), got {colortype}"
    assert interlace == 0, f"{rel}: must be non-interlaced"
    assert not saw_trns, f"{rel}: tRNS transparency chunk is forbidden"
    channels = 3
    pixels = unfilter(zlib.decompress(idat), width, height, channels)
    bad = 0
    for i in range(0, len(pixels), channels):
        if not (pixels[i] == pixels[i + 1] == pixels[i + 2]):
            bad += 1
            assert bad <= 0, f"{rel}: chromatic pixel at index {i // channels}"
PY

# 8. Production SVGs must use only pure black and pure white, with no gradients or filters.
python3 -E - "$ROOT" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
svgs = sorted((root / "assets/branding/source").glob("*.svg"))
assert svgs, "no production SVGs found under assets/branding/source"
for path in svgs:
    text = path.read_text(encoding="utf-8")
    colors = re.findall(r"#([0-9a-fA-F]{3,8})\b", text)
    assert colors, f"{path.name}: no hex colors found"
    for raw in colors:
        normalized = raw.upper()
        if len(normalized) == 3:
            normalized = "".join(c * 2 for c in normalized)
        assert normalized in ("000000", "FFFFFF"), (
            f"{path.name}: forbidden color #{raw}; only #000000/#FFFFFF allowed")
    lowered = text.lower()
    for token in ("<lineargradient", "<radialgradient", "<filter", "rgb(", "hsl("):
        assert token not in lowered, f"{path.name}: forbidden SVG token {token!r}"
    assert not re.search(r"<fe[a-z]", lowered), f"{path.name}: SVG filter primitives are forbidden"
PY

# 9. The two 1024 production icons share one deterministic renderer output.
if ! cmp -s "assets/branding/exports/app-icon-1024.png" \
    "Sources/HostApp/Assets.xcassets/AppIcon.appiconset/AppIcon-Monochrome-1024.png"; then
    fail "1024 export and active catalog icon diverge; rerun the renderer"
fi

echo "Branding pipeline checks passed."
