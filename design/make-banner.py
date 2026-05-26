#!/usr/bin/env python3
"""
Generate ear-only logo mark for the Susurro README.

Source:  design/susurro-logo.png  (2000×2000, black line-art on white)
Outputs: assets/logo-light.png   — near-black art, transparent bg (light theme)
         assets/logo-dark.png    — near-white/lavender art, transparent bg (dark theme)

Layout: ear glyph only (no wordmark).  The README heading provides the name.
"""

from pathlib import Path
from PIL import Image
import numpy as np

# ── Tuneable constants ──────────────────────────────────────────────────────────

# Color variants
COLOR_LIGHT = (26,  26,  30)   # near-black — for light (white) README backgrounds
COLOR_DARK  = (235, 233, 245)  # near-white/lavender — for dark README backgrounds

# Transparent padding added uniformly on all sides, as a fraction of glyph height.
# ~5% gives a small breathing margin while keeping the asset compact.
PADDING_FRACTION = 0.05

# Target glyph height in pixels before padding.  The output will be slightly
# taller once padding is applied.  ~280 px produces a crisp asset that
# renders well at the ~120-140 px README display size.
TARGET_HEIGHT_PX = 280

# ── Crop fractions for extracting the ear glyph from the 2000×2000 source ──────
EAR_CROP_TOP    = 0.00   # ear glyph lives in the top 62% of the image
EAR_CROP_BOTTOM = 0.62

# ── Paths ───────────────────────────────────────────────────────────────────────

REPO_ROOT  = Path(__file__).resolve().parent.parent
SRC_LOGO   = REPO_ROOT / "design" / "susurro-logo.png"
OUT_LIGHT  = REPO_ROOT / "assets" / "logo-light.png"
OUT_DARK   = REPO_ROOT / "assets" / "logo-dark.png"


# ── Helpers ─────────────────────────────────────────────────────────────────────

def extract_ear_alpha_mask(src_rgb: Image.Image) -> Image.Image:
    """
    Crop the ear-glyph band from `src_rgb`, auto-crop to the dark-pixel
    bounding box, and return an RGBA image whose alpha = 255 − luminance
    (black line-art → fully opaque, white background → fully transparent).
    RGB channels are set to 0 (replaced by the caller via colorize()).
    """
    w, h = src_rgb.size
    y0, y1 = int(h * EAR_CROP_TOP), int(h * EAR_CROP_BOTTOM)
    band = src_rgb.crop((0, y0, w, y1))

    arr = np.array(band).astype(np.float32)
    lum = (0.299 * arr[:, :, 0]
         + 0.587 * arr[:, :, 1]
         + 0.114 * arr[:, :, 2])
    dark_mask = lum < 250

    rows = np.any(dark_mask, axis=1)
    cols = np.any(dark_mask, axis=0)
    if not rows.any():
        raise ValueError("No dark pixels found in ear band — "
                         "check EAR_CROP_TOP / EAR_CROP_BOTTOM")

    row_min = int(np.argmax(rows))
    row_max = int(len(rows) - 1 - np.argmax(rows[::-1]))
    col_min = int(np.argmax(cols))
    col_max = int(len(cols) - 1 - np.argmax(cols[::-1]))

    # 2% inner padding to preserve anti-aliased edges
    pad_r = max(4, int((row_max - row_min) * 0.02))
    pad_c = max(4, int((col_max - col_min) * 0.02))
    row_min = max(0, row_min - pad_r)
    row_max = min(band.height - 1, row_max + pad_r)
    col_min = max(0, col_min - pad_c)
    col_max = min(w - 1, col_max + pad_c)

    tight = band.crop((col_min, row_min, col_max + 1, row_max + 1))
    tight_arr = np.array(tight).astype(np.float32)
    lum_tight = (0.299 * tight_arr[:, :, 0]
               + 0.587 * tight_arr[:, :, 1]
               + 0.114 * tight_arr[:, :, 2])

    alpha = np.clip(255.0 - lum_tight, 0, 255).astype(np.uint8)
    rgba = np.zeros((*tight_arr.shape[:2], 4), dtype=np.uint8)
    rgba[:, :, 3] = alpha
    result = Image.fromarray(rgba, "RGBA")
    print(f"  Ear tight crop: {result.size[0]}×{result.size[1]} px")
    return result


def colorize(alpha_mask: Image.Image, color) -> Image.Image:
    """Fill RGB channels with `color`, keeping alpha unchanged."""
    arr = np.array(alpha_mask)
    arr[:, :, 0] = color[0]
    arr[:, :, 1] = color[1]
    arr[:, :, 2] = color[2]
    return Image.fromarray(arr, "RGBA")


# ── 1. Load source logo ─────────────────────────────────────────────────────────

print("Loading source logo…")
logo = Image.open(SRC_LOGO).convert("RGB")
print(f"  Logo: {logo.size[0]}×{logo.size[1]} px")

# ── 2. Extract ear glyph as alpha mask ─────────────────────────────────────────

print("Extracting ear glyph…")
ear_mask = extract_ear_alpha_mask(logo)

# ── 3. Scale to target height (LANCZOS) ────────────────────────────────────────

ear_h = TARGET_HEIGHT_PX
ear_w = max(1, round(ear_h * ear_mask.width / ear_mask.height))
ear_scaled = ear_mask.resize((ear_w, ear_h), Image.LANCZOS)
print(f"  Ear scaled: {ear_scaled.size[0]}×{ear_scaled.size[1]} px")

# ── 4. Add uniform transparent padding ─────────────────────────────────────────

pad_px  = max(2, round(PADDING_FRACTION * ear_h))
padded_w = ear_w + 2 * pad_px
padded_h = ear_h + 2 * pad_px
final_mask = Image.new("RGBA", (padded_w, padded_h), (0, 0, 0, 0))
final_mask.paste(ear_scaled, (pad_px, pad_px), mask=ear_scaled)

print(f"\nFinal glyph (with padding): {final_mask.size[0]}×{final_mask.size[1]} px")

# ── 5. Verify background is transparent ────────────────────────────────────────

fm_arr = np.array(final_mask)
corner_pixels = [
    fm_arr[0,   0,   3],
    fm_arr[0,   -1,  3],
    fm_arr[-1,  0,   3],
    fm_arr[-1,  -1,  3],
]
assert all(p == 0 for p in corner_pixels), \
    f"Background corners are not fully transparent: {corner_pixels}"
print("Background transparency verified (all four corners alpha = 0).")

# ── 6. Produce two color variants and save ─────────────────────────────────────

OUT_LIGHT.parent.mkdir(parents=True, exist_ok=True)

light_img = colorize(final_mask, COLOR_LIGHT)
light_img.save(OUT_LIGHT, "PNG")
print(f"\nSaved: {OUT_LIGHT.relative_to(REPO_ROOT)}")
print(f"  Size : {light_img.size[0]}×{light_img.size[1]} px")
print(f"  Color: RGB{COLOR_LIGHT}")

dark_img = colorize(final_mask, COLOR_DARK)
dark_img.save(OUT_DARK, "PNG")
print(f"\nSaved: {OUT_DARK.relative_to(REPO_ROOT)}")
print(f"  Size : {dark_img.size[0]}×{dark_img.size[1]} px")
print(f"  Color: RGB{COLOR_DARK}")

# ── Summary ─────────────────────────────────────────────────────────────────────

print("\n── Summary ──────────────────────────────────────────────────────────────────")
print(f"  TARGET_HEIGHT_PX   : {TARGET_HEIGHT_PX}  (glyph, before padding)")
print(f"  PADDING_FRACTION   : {PADDING_FRACTION}  ({pad_px} px each side)")
print(f"  Final dimensions   : {light_img.size[0]}×{light_img.size[1]} px (both variants)")
print("Done.")
