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
from PIL import Image, ImageFilter
import numpy as np

# Fraction of the final canvas that the visible ear glyph occupies (both
# dimensions).  1.0 = tight crop fills the whole canvas (too large on menu bar);
# 0.78 leaves ~11% transparent margin on each side, matching the internal
# padding of SF Symbols / emoji in the 22pt menu bar slot.  Tune to taste.
GLYPH_FRACTION = 0.78

# Extra stroke thickness, expressed in FINAL @2x pixels (tune to taste).
# Dilation is applied at source crop resolution before downscaling, so the
# LANCZOS step anti-aliases the result for smooth edges.
STROKE_WEIGHT_PX = 1.0

# @2x export height (px) — used to compute the source-resolution dilation kernel.
TARGET_2X_HEIGHT_PX = 44

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
print(f"Template image size (tight ear): {template_img.size}")

# ── 4b. Dilate alpha channel to thicken strokes ───────────────────────────────
# Scale STROKE_WEIGHT_PX (in @2x output pixels) up to source crop resolution.
_crop_h = template_img.size[1]
_scale_factor = _crop_h / TARGET_2X_HEIGHT_PX
_dilation_radius = max(1, round(STROKE_WEIGHT_PX * _scale_factor))
_kernel_size = 2 * _dilation_radius + 1   # must be odd; MinFilter/MaxFilter require odd size >= 3
print(f"Stroke dilation: STROKE_WEIGHT_PX={STROKE_WEIGHT_PX}, scale={_scale_factor:.1f}x, "
      f"source kernel size={_kernel_size}px (radius {_dilation_radius})")

alpha_channel = template_img.getchannel("A")
dilated_alpha = alpha_channel.filter(ImageFilter.MaxFilter(_kernel_size))

# Recombine: keep RGB=(0,0,0), replace alpha with dilated version.
r, g, b, _ = template_img.split()
template_img = Image.merge("RGBA", (r, g, b, dilated_alpha))
print(f"Template image size after dilation: {template_img.size}")

# ── 5. Add transparent padding so the ear fills only GLYPH_FRACTION of canvas ─
ew, eh = template_img.size
canvas_w = round(ew / GLYPH_FRACTION)
canvas_h = round(eh / GLYPH_FRACTION)
padded_img = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
paste_x = (canvas_w - ew) // 2
paste_y = (canvas_h - eh) // 2
# Use the ear's alpha channel as the paste mask so transparency is preserved.
padded_img.paste(template_img, (paste_x, paste_y), mask=template_img)
print(f"After padding ({GLYPH_FRACTION:.0%} glyph fraction): {padded_img.size}")

# ── 6. Resize and export ───────────────────────────────────────────────────────
def export(src_img: Image.Image, target_height: int, path: Path) -> None:
    tw, th = src_img.size
    aspect = tw / th
    out_h = target_height
    out_w = max(1, round(out_h * aspect))
    resized = src_img.resize((out_w, out_h), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    resized.save(path, "PNG")
    print(f"Saved {path.relative_to(REPO_ROOT)}  →  {resized.size[0]}×{resized.size[1]} px")

export(padded_img, 44, OUT_DIR / "MenuBarIcon@2x.png")
export(padded_img, 22, OUT_DIR / "MenuBarIcon.png")
print("Done.")
