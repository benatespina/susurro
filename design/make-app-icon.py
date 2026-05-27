#!/usr/bin/env python3
"""
Generates app/Susurro/Resources/AppIcon.icns from design/susurro-logo.png.

Source: design/susurro-logo.png  (2000×2000, black ear glyph + "SUSURRO"
        wordmark below, on white background)

The wordmark is stripped — only the ear glyph is kept, then composed
centered on a 1024×1024 white square tile and exported to the full
macOS iconset (10 slots).

Run from any directory:
    python3 design/make-app-icon.py
"""

import subprocess
import shutil
from pathlib import Path

from PIL import Image
import numpy as np

# ── Tunables ──────────────────────────────────────────────────────────────────

# Fraction of the logo height to keep before auto-cropping (removes wordmark).
# The ear glyph lives in the top ~62% of the source.
WORDMARK_CROP_FRACTION = 0.62

# Fraction of the 1024px canvas height that the ear occupies (~10% margin
# top/bottom).
EAR_HEIGHT_FRACTION = 0.80

# Background color of the icon tile (white).
BACKGROUND_COLOR = (255, 255, 255)

# Master size (px).
MASTER_SIZE = 1024

# ── Paths ─────────────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC = REPO_ROOT / "design" / "susurro-logo.png"
OUT_ICNS = REPO_ROOT / "app" / "Susurro" / "Resources" / "AppIcon.icns"
ICONSET_DIR = REPO_ROOT / "design" / "AppIcon.iconset"

PREVIEW_PATH = Path("/tmp/appicon-earonly-preview.png")

# ── Iconset slots (name → side length px) ─────────────────────────────────────

ICONSET_SIZES = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

# ── 1. Load source ─────────────────────────────────────────────────────────────

img = Image.open(SRC).convert("RGB")
w, h = img.size
print(f"Source: {w}×{h}")

# ── 2. Crop wordmark — keep top WORDMARK_CROP_FRACTION of the image ───────────

crop_h = int(h * WORDMARK_CROP_FRACTION)
img_cropped = img.crop((0, 0, w, crop_h))
print(f"After wordmark crop: {img_cropped.size}")

# ── 3. Auto-crop to bounding box of dark (non-white) pixels ───────────────────

arr = np.array(img_cropped)
lum = (0.299 * arr[:, :, 0].astype(np.float32)
     + 0.587 * arr[:, :, 1].astype(np.float32)
     + 0.114 * arr[:, :, 2].astype(np.float32))

dark_mask = lum < 250  # keeps anti-aliased edges
rows = np.any(dark_mask, axis=1)
cols = np.any(dark_mask, axis=0)
if not rows.any():
    raise ValueError("No dark pixels found after wordmark crop — check WORDMARK_CROP_FRACTION")

row_min = int(np.argmax(rows))
row_max = int(len(rows) - 1 - np.argmax(rows[::-1]))
col_min = int(np.argmax(cols))
col_max = int(len(cols) - 1 - np.argmax(cols[::-1]))

# Small padding (2% of crop dimension) to avoid clipping AA edges.
pad_r = max(4, int((row_max - row_min) * 0.02))
pad_c = max(4, int((col_max - col_min) * 0.02))
row_min = max(0, row_min - pad_r)
row_max = min(crop_h - 1, row_max + pad_r)
col_min = max(0, col_min - pad_c)
col_max = min(w - 1, col_max + pad_c)

img_tight = img_cropped.crop((col_min, row_min, col_max + 1, row_max + 1))
ear_w, ear_h = img_tight.size
print(f"Ear bounding box: {ear_w}×{ear_h}  (aspect {ear_w/ear_h:.3f})")

# ── 4. Build 1024×1024 white-background master ───────────────────────────────

# Scale ear so its height = EAR_HEIGHT_FRACTION × MASTER_SIZE.
target_ear_h = round(MASTER_SIZE * EAR_HEIGHT_FRACTION)
aspect = ear_w / ear_h
target_ear_w = max(1, round(target_ear_h * aspect))

ear_resized = img_tight.resize((target_ear_w, target_ear_h), Image.LANCZOS)
print(f"Ear scaled to: {target_ear_w}×{target_ear_h}")

master = Image.new("RGB", (MASTER_SIZE, MASTER_SIZE), BACKGROUND_COLOR)
paste_x = (MASTER_SIZE - target_ear_w) // 2
paste_y = (MASTER_SIZE - target_ear_h) // 2
master.paste(ear_resized, (paste_x, paste_y))
print(f"Master canvas: {master.size}  ear pasted at ({paste_x}, {paste_y})")

# ── 5. Save preview ───────────────────────────────────────────────────────────

preview = master.resize((512, 512), Image.LANCZOS)
preview.save(PREVIEW_PATH, "PNG")
print(f"Preview saved: {PREVIEW_PATH}")

# ── 6. Build iconset ──────────────────────────────────────────────────────────

if ICONSET_DIR.exists():
    shutil.rmtree(ICONSET_DIR)
ICONSET_DIR.mkdir(parents=True)

for filename, size in ICONSET_SIZES:
    slot = master.resize((size, size), Image.LANCZOS)
    out_path = ICONSET_DIR / filename
    slot.save(out_path, "PNG")
    print(f"  {filename:30s}  {size}×{size}")

print(f"\nIconset written to: {ICONSET_DIR}")

# ── 7. Run iconutil ───────────────────────────────────────────────────────────

OUT_ICNS.parent.mkdir(parents=True, exist_ok=True)
result = subprocess.run(
    ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(OUT_ICNS)],
    capture_output=True, text=True,
)
if result.returncode != 0:
    raise RuntimeError(f"iconutil failed:\n{result.stderr}")
print(f"\nAppIcon.icns written: {OUT_ICNS}")

# ── 8. Cleanup iconset directory ─────────────────────────────────────────────

shutil.rmtree(ICONSET_DIR)
print("Iconset directory cleaned up.")

# ── 9. Summary ────────────────────────────────────────────────────────────────

import os
icns_size = os.path.getsize(OUT_ICNS)
print(f"\nDone. EAR_HEIGHT_FRACTION={EAR_HEIGHT_FRACTION}  icns size={icns_size:,} bytes")
