import sys
from PIL import Image
import numpy as np
from collections import deque

def cutout(path):
    a = np.array(Image.open(path).convert('RGB')).astype(int)
    h, w, _ = a.shape
    bg = np.array([63.5, 63.5, 63.5])
    d = np.abs(a - bg).max(2)
    # flood fill the background from the border (tolerance 6)
    isbg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        q.append((0, x)); q.append((h - 1, x))
    for y in range(h):
        q.append((y, 0)); q.append((y, w - 1))
    while q:
        y, x = q.popleft()
        if y < 0 or y >= h or x < 0 or x >= w or isbg[y, x] or d[y, x] > 6:
            continue
        isbg[y, x] = True
        q.extend(((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)))
    # seal small gaps in the outline (the head shows through under the
    # headband in the same grey as the background), then only keep as
    # background what is still connected to the image border
    from scipy import ndimage
    solid = ndimage.binary_closing(~isbg, structure=np.ones((3, 3)), iterations=6)
    solid = ndimage.binary_fill_holes(solid)
    isbg = isbg & ~solid
    alpha = np.where(isbg, 0, 255).astype(np.uint8)
    # soften the rim a little: pixels next to the background fade by how close they are to it
    rim = (~isbg) & (np.roll(isbg, 1, 0) | np.roll(isbg, -1, 0) | np.roll(isbg, 1, 1) | np.roll(isbg, -1, 1))
    alpha[rim] = np.clip(d[rim] * 255 / 24, 90, 255).astype(np.uint8)
    rgba = np.dstack([a.astype(np.uint8), alpha])
    img = Image.fromarray(rgba, 'RGBA')
    return img.crop(img.getbbox())

def cell_bbox(sheet, col, row):
    c = sheet.crop((col * 128, row * 128, col * 128 + 128, row * 128 + 128))
    return c.getbbox()

sheet = Image.open('/home/claude/roblox-game/assets/chess-pieces.png').convert('RGBA')
for row, path, name in ((0, sys.argv[1], 'white'), (1, sys.argv[2], 'black')):
    pawn = cutout(path)
    pawn.save(f'/tmp/pawn/pawn_{name}_full.png')
    old = cell_bbox(sheet, 5, row)
    print(name, 'cutout', pawn.size, 'old pawn bbox in cell', old)
    # same height as the old pawn, standing on the same baseline, centred
    target_h = old[3] - old[1]
    scale = target_h / pawn.size[1]
    nw, nh = max(1, round(pawn.size[0] * scale)), target_h
    small = pawn.resize((nw, nh), Image.LANCZOS)
    cell = Image.new('RGBA', (128, 128), (0, 0, 0, 0))
    cell.paste(small, ((128 - nw) // 2, old[3] - nh), small)
    sheet.paste(Image.new('RGBA', (128, 128), (0, 0, 0, 0)), (5 * 128, row * 128))
    sheet.paste(cell, (5 * 128, row * 128))
sheet.save('/tmp/pawn/chess-pieces.png')
