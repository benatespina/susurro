#!/usr/bin/env bash
set -euo pipefail

# Generates app/Susurro/Resources/AppIcon.icns from design/susurro-logo.png.
# Run from any directory — paths are resolved relative to this script's location.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE="${SCRIPT_DIR}/susurro-logo.png"
ICONSET="${SCRIPT_DIR}/AppIcon.iconset"
OUTPUT="${REPO_ROOT}/app/Susurro/Resources/AppIcon.icns"

echo "Source : ${SOURCE}"
echo "Iconset: ${ICONSET}"
echo "Output : ${OUTPUT}"
echo ""

if [[ ! -f "${SOURCE}" ]]; then
    echo "ERROR: source file not found: ${SOURCE}" >&2
    exit 1
fi

# Clean slate
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

echo "Generating iconset sizes..."

sips -z 16   16   "${SOURCE}" --out "${ICONSET}/icon_16x16.png"      > /dev/null
echo "  icon_16x16.png       (16x16)"

sips -z 32   32   "${SOURCE}" --out "${ICONSET}/icon_16x16@2x.png"   > /dev/null
echo "  icon_16x16@2x.png    (32x32)"

sips -z 32   32   "${SOURCE}" --out "${ICONSET}/icon_32x32.png"      > /dev/null
echo "  icon_32x32.png       (32x32)"

sips -z 64   64   "${SOURCE}" --out "${ICONSET}/icon_32x32@2x.png"   > /dev/null
echo "  icon_32x32@2x.png    (64x64)"

sips -z 128  128  "${SOURCE}" --out "${ICONSET}/icon_128x128.png"    > /dev/null
echo "  icon_128x128.png     (128x128)"

sips -z 256  256  "${SOURCE}" --out "${ICONSET}/icon_128x128@2x.png" > /dev/null
echo "  icon_128x128@2x.png  (256x256)"

sips -z 256  256  "${SOURCE}" --out "${ICONSET}/icon_256x256.png"    > /dev/null
echo "  icon_256x256.png     (256x256)"

sips -z 512  512  "${SOURCE}" --out "${ICONSET}/icon_256x256@2x.png" > /dev/null
echo "  icon_256x256@2x.png  (512x512)"

sips -z 512  512  "${SOURCE}" --out "${ICONSET}/icon_512x512.png"    > /dev/null
echo "  icon_512x512.png     (512x512)"

sips -z 1024 1024 "${SOURCE}" --out "${ICONSET}/icon_512x512@2x.png" > /dev/null
echo "  icon_512x512@2x.png  (1024x1024)"

echo ""
echo "Running iconutil..."
iconutil -c icns "${ICONSET}" -o "${OUTPUT}"
echo "Done: ${OUTPUT}"

# Verify
echo ""
echo "Verifying output..."
file "${OUTPUT}"
ls -lh "${OUTPUT}"

# Cleanup
rm -rf "${ICONSET}"
echo "Cleaned up iconset directory."
