#!/usr/bin/env python3
"""
Generate assets/cover.png — the Susurro repo cover image.

Source:   design/susurro-logo.png  (2000x2000, black line-art ear glyph +
          wordmark on white background)
Output:   assets/cover.png  (1400x1400)

Palette sampled from the original cover.png:
  DARK_CORNER  = (11, 8, 35)   — darkest background (bottom-right corner)
  DARK_EDGE    = (22, 18, 50)  — dark edges / top-right corner
  MID_PURPLE   = (44, 35, 78)  — centre-ish background (upper-left quadrant)
  LAVENDER     = (215, 203, 246) — icon fill colour from old waveform bars
  NEAR_WHITE   = (245, 243, 250) — wordmark colour (cool white, fits purple bg)

The gradient is a diagonal linear blend matching the original: lighter purple
in the upper-left, darkening toward the lower-right, with a subtle "lift" in
the upper-left quadrant.
"""

from pathlib import Path
from PIL import Image
import numpy as np

# ── Tuneable constants ─────────────────────────────────────────────────────────

CANVAS_SIZE = 1400

# Gradient corners (sampled from old cover.png)
GRAD_TOP_LEFT     = (54, 44, 90)   # slightly lighter, upper-left area
GRAD_TOP_RIGHT    = (22, 18, 50)   # dark edge, upper-right
GRAD_BOTTOM_LEFT  = (22, 18, 50)   # dark edge, lower-left
GRAD_BOTTOM_RIGHT = (11, 8,  35)   # darkest, lower-right corner

# Element colours
LAVENDER    = (215, 203, 246)  # ear glyph fill — sampled from old waveform
NEAR_WHITE  = (245, 243, 250)  # wordmark colour — cool white to match purple bg

# Layout — fractions of CANVAS_SIZE
EAR_HEIGHT_FRACTION  = 0.285   # ear height as fraction of canvas (≈400 px on 1400)
EAR_CENTER_Y_FRAC    = 0.400   # vertical centre of ear (fraction of canvas)

WORD_WIDTH_FRACTION  = 0.440   # wordmark width as fraction of canvas (≈616 px)
WORD_CENTER_Y_FRAC   = 0.660   # vertical centre of wordmark (fraction of canvas)

# ── Paths ──────────────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC_LOGO  = REPO_ROOT / "design" / "susurro-logo.png"
OUT_COVER = REPO_ROOT / "assets" / "cover.png"

# ── 1. Build diagonal gradient background ─────────────────────────────────────

def make_gradient(size: int) -> Image.Image:
    """Bilinear blend of four corner colours, matching the old cover palette."""
    c = CANVAS_SIZE
    tl = np.array(GRAD_TOP_LEFT,     dtype=np.float32)
    tr = np.array(GRAD_TOP_RIGHT,    dtype=np.float32)
    bl = np.array(GRAD_BOTTOM_LEFT,  dtype=np.float32)
    br = np.array(GRAD_BOTTOM_RIGHT, dtype=np.float32)

    xs = np.linspace(0.0, 1.0, c, dtype=np.float32)
    ys = np.linspace(0.0, 1.0, c, dtype=np.float32)
    xv, yv = np.meshgrid(xs, ys)  # shape (c, c)

    # Bilinear interpolation
    top    = tl[np.newaxis, np.newaxis, :] * (1 - xv[:, :, np.newaxis]) + \
             tr[np.newaxis, np.newaxis, :] *      xv[:, :, np.newaxis]
    bottom = bl[np.newaxis, np.newaxis, :] * (1 - xv[:, :, np.newaxis]) + \
             br[np.newaxis, np.newaxis, :] *      xv[:, :, np.newaxis]
    blended = top * (1 - yv[:, :, np.newaxis]) + bottom * yv[:, :, np.newaxis]

    arr = np.clip(blended, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGB")

print("Building gradient background…")
background = make_gradient(CANVAS_SIZE)
print(f"  Background: {background.size}")

# ── 2. Extract ear glyph from logo ────────────────────────────────────────────

def extract_glyph(src, crop_top_frac, crop_bottom_frac, color, label):
    """
    Crop a horizontal band [crop_top_frac, crop_bottom_frac] of `src`,
    auto-crop to the dark-pixel bounding box, recolour to `color` with
    alpha = 255 - luminance (preserves anti-aliasing), and return RGBA.
    """
    w, h = src.size
    y0 = int(h * crop_top_frac)
    y1 = int(h * crop_bottom_frac)
    band = src.crop((0, y0, w, y1))

    arr = np.array(band).astype(np.float32)
    lum = (0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2])
    dark_mask = lum < 250

    rows = np.any(dark_mask, axis=1)
    cols = np.any(dark_mask, axis=0)
    if not rows.any():
        raise ValueError(f"No dark pixels found in {label} band — check crop fractions")

    row_min = int(np.argmax(rows))
    row_max = int(len(rows) - 1 - np.argmax(rows[::-1]))
    col_min = int(np.argmax(cols))
    col_max = int(len(cols) - 1 - np.argmax(cols[::-1]))

    # 2 % padding to preserve anti-aliased edges
    pad_r = max(4, int((row_max - row_min) * 0.02))
    pad_c = max(4, int((col_max - col_min) * 0.02))
    row_min = max(0, row_min - pad_r)
    row_max = min(band.height - 1, row_max + pad_r)
    col_min = max(0, col_min - pad_c)
    col_max = min(w - 1, col_max + pad_c)

    tight = band.crop((col_min, row_min, col_max + 1, row_max + 1))
    tight_arr = np.array(tight).astype(np.float32)
    lum_tight = (0.299 * tight_arr[:, :, 0] +
                 0.587 * tight_arr[:, :, 1] +
                 0.114 * tight_arr[:, :, 2])

    alpha = np.clip(255.0 - lum_tight, 0, 255).astype(np.uint8)

    rgba = np.zeros((*tight_arr.shape[:2], 4), dtype=np.uint8)
    rgba[:, :, 0] = color[0]
    rgba[:, :, 1] = color[1]
    rgba[:, :, 2] = color[2]
    rgba[:, :, 3] = alpha

    result = Image.fromarray(rgba, "RGBA")
    print(f"  {label} tight crop: {result.size}")
    return result


print("Loading source logo…")
logo = Image.open(SRC_LOGO).convert("RGB")
print(f"  Logo: {logo.size}")

# Ear glyph lives in the top ~62 % of the logo (rows 520–1205 in a 2000 h image)
print("Extracting ear glyph…")
ear_glyph = extract_glyph(logo, crop_top_frac=0.0, crop_bottom_frac=0.62,
                           color=LAVENDER, label="ear")

# Wordmark lives in roughly the bottom 28 % (rows 1319–1480 out of 2000)
print("Extracting wordmark…")
wordmark = extract_glyph(logo, crop_top_frac=0.65, crop_bottom_frac=1.0,
                         color=NEAR_WHITE, label="wordmark")

# ── 3. Scale elements ──────────────────────────────────────────────────────────

C = CANVAS_SIZE

# Ear: target height = EAR_HEIGHT_FRACTION * C
ear_target_h = round(EAR_HEIGHT_FRACTION * C)
ear_aspect    = ear_glyph.width / ear_glyph.height
ear_target_w  = max(1, round(ear_target_h * ear_aspect))
ear_scaled    = ear_glyph.resize((ear_target_w, ear_target_h), Image.LANCZOS)
print(f"Ear scaled: {ear_scaled.size}")

# Wordmark: target width = WORD_WIDTH_FRACTION * C
word_target_w = round(WORD_WIDTH_FRACTION * C)
word_aspect   = wordmark.width / wordmark.height
word_target_h = max(1, round(word_target_w / word_aspect))
word_scaled   = wordmark.resize((word_target_w, word_target_h), Image.LANCZOS)
print(f"Wordmark scaled: {word_scaled.size}")

# ── 4. Compose ─────────────────────────────────────────────────────────────────

canvas = background.convert("RGBA")

# Ear: horizontally centred, vertical centre at EAR_CENTER_Y_FRAC
ear_x = (C - ear_scaled.width)  // 2
ear_y = round(EAR_CENTER_Y_FRAC * C) - ear_scaled.height // 2
canvas.paste(ear_scaled, (ear_x, ear_y), mask=ear_scaled)
print(f"Ear pasted at ({ear_x}, {ear_y})")

# Wordmark: horizontally centred, vertical centre at WORD_CENTER_Y_FRAC
word_x = (C - word_scaled.width)  // 2
word_y = round(WORD_CENTER_Y_FRAC * C) - word_scaled.height // 2
canvas.paste(word_scaled, (word_x, word_y), mask=word_scaled)
print(f"Wordmark pasted at ({word_x}, {word_y})")

# ── 5. Save ────────────────────────────────────────────────────────────────────

final = canvas.convert("RGB")
OUT_COVER.parent.mkdir(parents=True, exist_ok=True)
final.save(OUT_COVER, "PNG")
print(f"\nSaved: {OUT_COVER.relative_to(REPO_ROOT)}  →  {final.size[0]}×{final.size[1]} px")
print("\nPalette summary:")
print(f"  Gradient TL (upper-left):    RGB{GRAD_TOP_LEFT}")
print(f"  Gradient TR (upper-right):   RGB{GRAD_TOP_RIGHT}")
print(f"  Gradient BL (lower-left):    RGB{GRAD_BOTTOM_LEFT}")
print(f"  Gradient BR (lower-right):   RGB{GRAD_BOTTOM_RIGHT}")
print(f"  Ear lavender:                RGB{LAVENDER}")
print(f"  Wordmark near-white:         RGB{NEAR_WHITE}")
print("Done.")
