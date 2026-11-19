"""Build the three-colour install icons from static/icons/crest.svg.

Run from the repo root:  python3 scripts/icons/build_icons.py
Needs: rsvg-convert (librsvg), numpy, scipy, Pillow.

Colours (school palette):
  purple-deep #3A1A5C  lines, text, shield field
  purple      #5B2D8E  ribbon folds
  cream       #F8F4EC  outer band, ribbon, book, halo
  green       #1E7A46  tile background
  flame       #34B36A  torch flame

How it works: the crest is a one-colour trace. It is rendered to a bitmap,
the scan background (the ragged block at the top-left) is removed, and every
enclosed white area is labelled. Each area gets a fill colour by role, and each
line pixel takes the colour that suits the area it borders. The result gets a
cream halo and sits on a green square.
"""
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage as nd

SRC = 'static/icons/crest.svg'
OUT = 'static/icons'
RENDER_W = 1600
VIEW_W = 312.517888  # crest.svg viewBox width

C = {
    'deep': (0x3A, 0x1A, 0x5C), 'purple': (0x5B, 0x2D, 0x8E),
    'cream': (0xF8, 0xF4, 0xEC), 'green': (0x1E, 0x7A, 0x46),
    'flame': (0x34, 0xB3, 0x6A),
}
REG_FILL = {'band': 'cream', 'field': 'deep', 'rib': 'cream', 'fold': 'purple', 'page': 'cream'}
INK_ON = {'out': 'deep', 'band': 'deep', 'field': 'cream', 'rib': 'deep', 'fold': 'deep', 'page': 'deep'}


def render():
    with tempfile.TemporaryDirectory() as d:
        png = os.path.join(d, 'c.png')
        subprocess.run(['rsvg-convert', '-w', str(RENDER_W), SRC, '-o', png], check=True)
        return np.array(Image.open(png).convert('RGBA'))[..., 3] > 127


def regions_by_role(lab, s):
    """Name the white areas by where they sit (viewBox units, so the
    labels survive a re-trace that renumbers paths)."""
    def at(x, y):
        return lab[int(y * s), int(x * s)]
    sizes = nd.sum(np.ones_like(lab), lab, range(1, lab.max() + 1))
    role = {1: 'out'}
    probes = {
        'band': (156, 68),    # outer band, between "GROUP OF" and the inner shield
        'field': (156, 85),   # shield field above the flame
    }
    for name, (x, y) in probes.items():
        role[at(x, y)] = name
    field = [k for k, v in role.items() if v == 'field'][0]
    band = [k for k, v in role.items() if v == 'band'][0]
    fx = nd.find_objects(lab)
    for k in range(2, lab.max() + 1):
        if k in role or sizes[k - 1] < 1500:
            continue
        ys, xs = fx[k - 1]
        cy = (ys.start + ys.stop) / 2 / s
        if cy > 240:   # below the shield: ribbon tails and folds
            role[k] = 'rib' if sizes[k - 1] > 15000 else 'fold'
        elif sizes[k - 1] > 8000:
            role[k] = 'page'
    return role


def paint():
    a = render()
    s = RENDER_W / VIEW_W
    lab, _ = nd.label(a)
    ink = a & (lab != lab[3, 3])           # drop the scan background block
    lab, _ = nd.label(~ink)
    il, _ = nd.label(ink)
    for i, sl in enumerate(nd.find_objects(il), 1):   # stray specks outside
        m = il == i
        if m[sl].sum() < 4000:
            ring = nd.binary_dilation(m, iterations=3) & ~ink
            if set(np.unique(lab[ring])) <= {lab[0, -1]}:
                ink[m] = False
    lab, _ = nd.label(~ink)
    lab[lab == lab[0, -1]] = -1
    lab[lab == 1] = lab.max() + 1
    lab[lab == -1] = 1
    role = regions_by_role(lab, s)

    named = np.zeros_like(lab)
    for k in role:
        named[lab == k] = k
    _, idx = nd.distance_transform_edt(named == 0, return_indices=True)
    reg = np.where(ink, 0, named[idx[0], idx[1]])
    _, idx = nd.distance_transform_edt(ink, return_indices=True)
    inkreg = reg[idx[0], idx[1]]

    H, W = ink.shape
    out = np.zeros((H, W, 4), np.uint8)
    for k, r in role.items():
        if r in REG_FILL:
            out[(reg == k) & ~ink] = C[REG_FILL[r]] + (255,)
        out[ink & (inkreg == k)] = C[INK_ON[r]] + (255,)
    flame = np.zeros_like(ink)
    flame[int(88 * s):int(128 * s), int(140 * s):int(170 * s)] = True
    field = [k for k, v in role.items() if v == 'field'][0]
    out[ink & flame & (inkreg == field)] = C['flame'] + (255,)

    sil = out[..., 3] > 0
    halo = nd.binary_dilation(sil, iterations=26)
    pad = 30
    base = np.zeros((H + 2 * pad, W + 2 * pad, 4), np.uint8)
    base[pad:pad + H, pad:pad + W][halo] = C['cream'] + (255,)
    crest = Image.fromarray(base)
    crest.alpha_composite(Image.fromarray(out), (pad, pad))
    return crest.crop(crest.getbbox())


def tile(crest, size, frac, name):
    t = Image.new('RGBA', (size * 4, size * 4), C['green'] + (255,))
    h = int(t.height * frac)
    w = int(crest.width * h / crest.height)
    t.alpha_composite(crest.resize((w, h), Image.LANCZOS), ((t.width - w) // 2, (t.height - h) // 2))
    t = t.resize((size, size), Image.LANCZOS).convert('RGB')
    t = t.quantize(64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    t.save(os.path.join(OUT, name), optimize=True)


if __name__ == '__main__':
    crest = paint()
    tile(crest, 192, 0.86, 'icon-192.png')
    tile(crest, 512, 0.86, 'icon-512.png')
    tile(crest, 512, 0.66, 'icon-maskable-512.png')   # crest inside the 80% safe circle
    tile(crest, 180, 0.82, 'apple-touch-icon.png')
    print('icons written to', OUT)
