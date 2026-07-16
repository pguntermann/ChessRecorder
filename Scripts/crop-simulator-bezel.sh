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
from collections import deque
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
    # Keep metal frame (colored) and sufficiently opaque dark bezel; drop shadow fringe.
    if a < 128:
        return False
    if r + g + b >= 80:
        return True
    return a >= 200

def is_significant(r, g, b, a):
    if a < 128:
        return False
    if r + g + b >= 80:
        return True
    return a >= 200

def finalize_pixel(r, g, b, a):
    # Keep dark-mode UI grays intact; only fully opaque-ify stable pixels.
    # (Previously crushed r+g+b < 40 to black, which turned sheet scrims into
    # hard black and made drop shadows look like a shade band on the content.)
    if a >= 240:
        return (r, g, b, 255)
    return (r, g, b, a)

def solidify_interior_blacks(image, mask, source, min_dist=4, max_dist=48):
    """Fill near-black holes in the hardware bezel ring only — not app UI."""
    px = image.load()
    src = source.load()
    dist = [[10**9] * ww for _ in range(wh)]
    q = deque()
    for y in range(wh):
        for x in range(ww):
            if not mask.getpixel((x, y)) or px[x, y][3] == 0:
                dist[y][x] = 0
                q.append((x, y))
    while q:
        x, y = q.popleft()
        d = dist[y][x]
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < ww and 0 <= ny < wh and dist[ny][nx] > d + 1:
                dist[ny][nx] = d + 1
                q.append((nx, ny))
    for y in range(wh):
        for x in range(ww):
            r, g, b, a = px[x, y]
            d = dist[y][x]
            # Only touch nearly pure black pixels in the outer bezel band.
            if (
                a
                and r + g + b < 8
                and min_dist <= d <= max_dist
                and src[x, y][3] >= 200
            ):
                px[x, y] = (0, 0, 0, 255)

def clear_boundary_dark(image, mask, source, max_dist=6):
    px = image.load()
    src = source.load()
    dist = [[10**9] * ww for _ in range(wh)]
    q = deque()
    for y in range(wh):
        for x in range(ww):
            if not mask.getpixel((x, y)) or px[x, y][3] == 0:
                dist[y][x] = 0
                q.append((x, y))
    while q:
        x, y = q.popleft()
        d = dist[y][x]
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < ww and 0 <= ny < wh and dist[ny][nx] > d + 1:
                dist[ny][nx] = d + 1
                q.append((nx, ny))
    for y in range(wh):
        for x in range(ww):
            r, g, b, a = px[x, y]
            if not a:
                continue
            sr, sg, sb, sa = src[x, y]
            if sr + sg + sb < 80 and (dist[y][x] <= max_dist or sa < 200):
                px[x, y] = (0, 0, 0, 0)

def fill_interior_gaps(image, mask, passes=3):
    px = image.load()
    for _ in range(passes):
        pending = []
        for y in range(1, wh - 1):
            for x in range(1, ww - 1):
                if not mask.getpixel((x, y)) or px[x, y][3] > 0:
                    continue
                if all(px[x + dx, y + dy][3] > 200 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                    pending.append((x, y))
        if not pending:
            break
        for x, y in pending:
            px[x, y] = (0, 0, 0, 255)

result = Image.new("RGBA", (ww, wh), (0, 0, 0, 0))
for y in range(wh):
    for x in range(ww):
        if not mask.getpixel((x, y)):
            continue
        r, g, b, a = data[x, y]
        if keep_pixel(r, g, b, a):
            result.putpixel((x, y), finalize_pixel(r, g, b, a))

solidify_interior_blacks(result, mask, work)
fill_interior_gaps(result, mask)
clear_boundary_dark(result, mask, work)

min_x, min_y, max_x, max_y = ww, wh, 0, 0
for y in range(wh):
    for x in range(ww):
        r, g, b, a = result.getpixel((x, y))
        if is_significant(r, g, b, a):
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)

result.crop((min_x, min_y, max_x + 1, max_y + 1)).save(out, "PNG")
print(f"Saved {out} ({max_x - min_x + 1}x{max_y - min_y + 1})")
PY
