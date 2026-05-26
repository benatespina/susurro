#!/usr/bin/env python3
"""
One-time script to produce macOS template-image PNGs for the Susurro menu bar icon.

Source: design/susurro-logo.png  (2000x2000, black line-art ear glyph + wordmark, white bg)

Outputs:
  app/Susurro/Resources/MenuBarIcon@2x.png  — 44 px tall  (Retina)
  app/Susurro/Resources/MenuBarIcon.png     — 22 px tall  (1x)

Template-image rules:
  - RGB must be all black  (macOS ignores RGB; only alpha is used as mask)
  - Alpha = 255 − luminance  (black strokes → opaque, white bg → transparent)
  - isTemplate is set at runtime in SusurroIcon.swift
"""

from pathlib import Path
from PIL import Image
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC = REPO_ROOT / "design" / "susurro-logo.png"
OUT_DIR = REPO_ROOT / "app" / "Susurro" / "Resources"

# ── 1. Load source ─────────────────────────────────────────────────────────────
img = Image.open(SRC).convert("RGB")
w, h = img.size
print(f"Source: {w}×{h}")

# ── 2. Crop wordmark — keep top 62 % of the image ─────────────────────────────
crop_h = int(h * 0.62)
img_cropped = img.crop((0, 0, w, crop_h))
print(f"After wordmark crop: {img_cropped.size}")

# ── 3. Auto-crop to bounding box of dark (non-white) pixels ───────────────────
arr = np.array(img_cropped)
# Luminance (BT.601 weights, uint16 to avoid overflow)
lum = (0.299 * arr[:, :, 0].astype(np.float32)
     + 0.587 * arr[:, :, 1].astype(np.float32)
     + 0.114 * arr[:, :, 2].astype(np.float32))

# A pixel is "dark" when luminance < 250 (keeps anti-aliased edges)
dark_mask = lum < 250
rows = np.any(dark_mask, axis=1)
cols = np.any(dark_mask, axis=0)
if not rows.any():
    raise ValueError("No dark pixels found after wordmark crop — check crop ratio")

row_min, row_max = int(np.argmax(rows)), int(len(rows) - 1 - np.argmax(rows[::-1]))
col_min, col_max = int(np.argmax(cols)), int(len(cols) - 1 - np.argmax(cols[::-1]))

# Add a small padding (2 % of the cropped dimension) to avoid clipping AA edges
pad_r = max(4, int((row_max - row_min) * 0.02))
pad_c = max(4, int((col_max - col_min) * 0.02))
row_min = max(0, row_min - pad_r)
row_max = min(crop_h - 1, row_max + pad_r)
col_min = max(0, col_min - pad_c)
col_max = min(w - 1, col_max + pad_c)

img_tight = img_cropped.crop((col_min, row_min, col_max + 1, row_max + 1))
print(f"After auto-crop to ear bounding box: {img_tight.size}")

# ── 4. Build RGBA template image ──────────────────────────────────────────────
rgb = np.array(img_tight).astype(np.float32)
lum_tight = (0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2])
alpha = np.clip(255.0 - lum_tight, 0, 255).astype(np.uint8)

rgba = np.zeros((*rgb.shape[:2], 4), dtype=np.uint8)
# RGB = black  (macOS template mask ignores RGB)
rgba[:, :, 3] = alpha

template_img = Image.fromarray(rgba, "RGBA")
print(f"Template image size (before resize): {template_img.size}")

# ── 5. Resize and export ───────────────────────────────────────────────────────
def export(src_img: Image.Image, target_height: int, path: Path) -> None:
    tw, th = src_img.size
    aspect = tw / th
    out_h = target_height
    out_w = max(1, round(out_h * aspect))
    resized = src_img.resize((out_w, out_h), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    resized.save(path, "PNG")
    print(f"Saved {path.relative_to(REPO_ROOT)}  →  {resized.size[0]}×{resized.size[1]} px")

export(template_img, 44, OUT_DIR / "MenuBarIcon@2x.png")
export(template_img, 22, OUT_DIR / "MenuBarIcon.png")
print("Done.")
