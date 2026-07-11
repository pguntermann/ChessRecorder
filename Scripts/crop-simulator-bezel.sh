#!/usr/bin/env bash
# Crop an iOS Simulator window capture to device-only PNG with transparent corners.
# Usage: ./Scripts/crop-simulator-bezel.sh [input.png] [output.png]
set -euo pipefail

INPUT="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$INPUT" || -z "$OUTPUT" ]]; then
  echo "Usage: $0 <input.png> <output.png>" >&2
  exit 1
fi

python3 - "$INPUT" "$OUTPUT" <<'PY'
import sys
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
w, h = img.size
px = img.load()

def opaque_frac(y, thresh=200):
    return sum(1 for x in range(w) if px[x, y][3] > thresh) / w

# Simulator window captures have a transparent canvas: find the toolbar, the shadow
# gap beneath it, then the device frame (works when the window does not span full width).
window_start = next((y for y in range(h) if opaque_frac(y) > 0.5), 0)

gap_start = None
for y in range(window_start, min(window_start + 250, h)):
    if opaque_frac(y) < 0.1:
        if all(opaque_frac(y + i) < 0.15 for i in range(8)):
            gap_start = y
            break

crop_top = None
if gap_start is not None:
    for y in range(gap_start, min(gap_start + 40, h)):
        if opaque_frac(y) > 0.5:
            crop_top = y
            break
if crop_top is None:
    crop_top = window_start + 29

col_score = [0] * w
row_score = [0] * h
for y in range(crop_top, h):
    for x in range(w):
        if px[x, y][3] > 220:
            col_score[x] += 1
            row_score[y] += 1

col_threshold = int((h - crop_top) * 0.55)
left = next(x for x in range(w) if col_score[x] > col_threshold)
right = next(x for x in range(w - 1, -1, -1) if col_score[x] > col_threshold)
row_threshold = int((right - left + 1) * 0.55)
top = next(y for y in range(crop_top, h) if row_score[y] > row_threshold)
bottom = next(y for y in range(h - 1, crop_top - 1, -1) if row_score[y] > row_threshold)

pad_x = 8
pad_top = 4
pad_bottom = 8
radius = max(36, int(min(w, h) * 0.035))
work = img.crop((max(0, left - pad_x), max(0, crop_top - pad_top), min(w, right + pad_x + 1), min(h, bottom + pad_bottom + 1)))
ww, wh = work.size
data = work.load()

mask = Image.new("L", (ww, wh), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, ww - 1, wh - 1), radius=radius, fill=255)

def keep_pixel(r, g, b, a):
    if a < 200:
        return False
    if a > 240:
        return True
    return r + g + b > 60

result = Image.new("RGBA", (ww, wh), (0, 0, 0, 0))
for y in range(wh):
    for x in range(ww):
        if not mask.getpixel((x, y)):
            continue
        r, g, b, a = data[x, y]
        if keep_pixel(r, g, b, a):
            result.putpixel((x, y), (r, g, b, 255 if a > 250 else a))

min_x, min_y, max_x, max_y = ww, wh, 0, 0
for y in range(wh):
    for x in range(ww):
        if result.getpixel((x, y))[3] > 0:
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)

result.crop((min_x, min_y, max_x + 1, max_y + 1)).save(out, "PNG")
print(f"Saved {out} ({max_x - min_x + 1}x{max_y - min_y + 1})")
PY
