#!/usr/bin/env bash
# Generate a THOR app icon from the Jetson Thor image or a solid color fallback.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ICONSET_DIR="$ROOT/.build/THOR.iconset"
ICNS_OUTPUT="$ROOT/Icon.icns"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Check if we have sips (macOS built-in image tool)
if ! command -v sips &>/dev/null; then
    echo "ERROR: sips not found (macOS only)"
    exit 1
fi

# Source image: use Jetson Thor photo or generate a solid icon
SOURCE="$ROOT/Assets/jetson-thor.png"

if [[ ! -f "$SOURCE" ]]; then
    echo "No source image found. Creating programmatic icon..."
    # Create a simple 1024x1024 icon using Python
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
import sys

size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Background: dark rounded rect
margin = 80
draw.rounded_rectangle(
    [margin, margin, size-margin, size-margin],
    radius=120,
    fill=(30, 30, 35, 255)
)

# Green accent bar
draw.rounded_rectangle(
    [margin+40, margin+40, size-margin-40, margin+120],
    radius=20,
    fill=(0, 200, 100, 255)
)

# Text
try:
    font = ImageFont.truetype('/System/Library/Fonts/SFNSMono.ttf', 280)
except:
    font = ImageFont.load_default()
draw.text((size//2, size//2 + 40), 'T', fill=(255, 255, 255, 255), font=font, anchor='mm')

# Subtitle
try:
    small = ImageFont.truetype('/System/Library/Fonts/SFNSMono.ttf', 80)
except:
    small = font
draw.text((size//2, size//2 + 220), 'THOR', fill=(180, 180, 190, 255), font=small, anchor='mm')

img.save('$SOURCE')
print('Generated source icon')
" 2>/dev/null || echo "WARN: Pillow not available, using source image crop"
fi

if [[ ! -f "$SOURCE" ]]; then
    echo "No source image available. Skipping icon generation."
    exit 0
fi

# Generate all required sizes
SIZES=(16 32 64 128 256 512 1024)

for sz in "${SIZES[@]}"; do
    sips -z "$sz" "$sz" "$SOURCE" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null 2>&1
done

# Also create @2x variants
sips -z 32 32 "$SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
sips -z 64 64 "$SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
sips -z 256 256 "$SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
sips -z 512 512 "$SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
sips -z 1024 1024 "$SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1

# Convert to icns
iconutil -c icns -o "$ICNS_OUTPUT" "$ICONSET_DIR"

echo "Icon generated: $ICNS_OUTPUT"
ls -lh "$ICNS_OUTPUT"
