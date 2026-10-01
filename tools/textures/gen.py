#!/usr/bin/env python3
"""Procedural, tileable material textures for GTIndian (CC0, generated here; no external images).

Writes godot/textures/<name>_c.png (sRGB albedo) and <name>_n.png (linear: RG = normal xy,
B = roughness, A = height) plus noise.png (4 independent tileable noise channels).
Every texture tiles seamlessly because all noise is built in the frequency domain (periodic)
or with wrapped distances. Scale comments give the real-world size one tile represents.

Usage: python3 tools/textures/gen.py [--only name,name] [--size 1024]
"""
import argparse, os
import numpy as np
from PIL import Image

OUT = "godot/textures"
rng = np.random.default_rng(20261001)


# ------------------------------------------------------------------------------------ noise basics
def band(n, f0, f1, seed=None):
    """periodic band-limited noise with energy between f0 and f1 cycles per tile, unit std"""
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((n, n))
    F = np.fft.fft2(w)
    fx = np.fft.fftfreq(n) * n
    fr = np.sqrt(fx[None, :] ** 2 + fx[:, None] ** 2)
    filt = ((fr >= f0) & (fr < f1)).astype(float)
    out = np.real(np.fft.ifft2(F * filt))
    return out / (out.std() + 1e-9)


def fbm(n, base=2, octaves=6, gain=0.55, seed=None):
    out = np.zeros((n, n)); amp = 1.0; f = base; tot = 0
    for o in range(octaves):
        out += amp * band(n, f, f * 2, None if seed is None else seed + o)
        tot += amp; amp *= gain; f *= 2
        if f >= n / 2: break
    out /= tot
    return norm(out)


def norm(a):
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.5)
    return np.clip((a - lo) / (hi - lo + 1e-9), 0, 1)


def worley(n, cells, seed=None, f2=False):
    """periodic Worley F1 (and optionally F2-F1) distance, normalised by cell size"""
    r = np.random.default_rng(seed) if seed is not None else rng
    pts = (np.arange(cells)[:, None, None] * 0 + 0)  # placeholder for shape
    jit = r.random((cells, cells, 2))
    yy, xx = np.mgrid[0:n, 0:n] / n * cells
    cx, cy = np.floor(xx).astype(int), np.floor(yy).astype(int)
    d1 = np.full((n, n), 9.0); d2 = np.full((n, n), 9.0); idv = np.zeros((n, n))
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            gx, gy = cx + ox, cy + oy
            p = jit[gy % cells, gx % cells]
            px, py = gx + p[..., 0], gy + p[..., 1]
            d = np.hypot(xx - px, yy - py)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            idv = np.where(closer, ((gx % cells) * 7919 + (gy % cells) * 104729) % 1000 / 1000.0, idv)
            d1 = np.minimum(d1, d)
    return (d2 - d1 if f2 else d1), idv


def normal_from_height(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = 1.0 / np.sqrt(gx ** 2 + gy ** 2 + 1)
    return -gx * nz, gy * nz  # OpenGL-style (green up), Godot convention


def save(name, color, height, rough, strength=4.0):
    os.makedirs(OUT, exist_ok=True)
    c = (np.clip(color, 0, 1) ** (1 / 2.2) * 255 + 0.5).astype(np.uint8)  # color given in linear
    Image.fromarray(c, "RGB").save(f"{OUT}/{name}_c.png", optimize=True)
    nx, ny = normal_from_height(height, strength)
    n = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, np.clip(np.broadcast_to(rough, height.shape), 0, 1), np.clip(height, 0, 1)], -1)
    Image.fromarray((n * 255 + 0.5).astype(np.uint8), "RGBA").save(f"{OUT}/{name}_n.png", optimize=True)
    print("wrote", name)


def lin(hexs):
    h = hexs.lstrip("#")
    c = np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def tint(mask, a, b):
    return lin(a)[None, None, :] * (1 - mask[..., None]) + lin(b)[None, None, :] * mask[..., None]


# ------------------------------------------------------------------------------------- materials
def t_noise(n):
    r = fbm(n, 2, 6); g = fbm(n, 8, 5); b, _ = worley(n, 8); a = fbm(n, 48, 3)
    img = np.stack([r, g, norm(b), a], -1)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(f"{OUT}/noise.png", optimize=True)
    print("wrote noise")


def t_asphalt(n):  # tile = 4 m
    stones = band(n, 120, 260) ; grit = band(n, 260, 512)
    big = fbm(n, 2, 5)
    w, _ = worley(n, 90)
    agg = np.clip(1 - w * 2.2, 0, 1) ** 2  # aggregate pebbles exposed by wear
    h = 0.45 + 0.12 * stones + 0.06 * grit + 0.25 * agg
    lum = 0.11 + 0.05 * big + 0.025 * stones + 0.05 * agg * (band(n, 200, 400) > 0.6)
    col = np.stack([lum * 1.0, lum * 0.98, lum * 0.95], -1)
    # light grey aggregate flecks
    fl = (band(n, 200, 512) > 2.2).astype(float)
    col = col * (1 - fl[..., None] * 0.6) + fl[..., None] * lin("#8a8680")
    rough = 0.82 + 0.1 * norm(grit) - 0.15 * agg
    save("asphalt", col, norm(h), rough, 3.0)


def t_plaster(n):  # tile = 2 m; grey-scale detail multiplied onto paint
    trowel = fbm(n, 3, 6)
    pits = (band(n, 180, 512) > 2.4).astype(float)
    grain = band(n, 120, 400)
    h = 0.55 + 0.25 * (trowel - 0.5) + 0.04 * grain - 0.25 * pits
    v = 0.85 + 0.12 * trowel + 0.03 * grain - 0.1 * pits
    col = np.stack([v, v, v], -1)
    save("plaster", col, norm(h), 0.88 + 0.06 * norm(grain), 2.0)


def t_concrete(n):  # tile = 3 m
    big = fbm(n, 2, 6); fine = band(n, 150, 512)
    w, _ = worley(n, 40)
    voids = (np.clip(0.08 - w, 0, 1) > 0).astype(float) * (band(n, 20, 40) > 0.5)
    h = 0.55 + 0.2 * (big - 0.5) + 0.05 * fine - 0.3 * voids
    v = 0.42 + 0.12 * big + 0.03 * fine - 0.12 * voids
    col = np.stack([v, v * 0.98, v * 0.95], -1)
    save("concrete", col, norm(h), 0.9, 2.5)


def t_sand(n):  # tile = 6 m; wind ripples + grains
    yy, xx = np.mgrid[0:n, 0:n] / n
    warp = fbm(n, 2, 4) * 0.6
    rip = np.sin((xx * 22 + yy * 9 + warp * 3) * 2 * np.pi) * 0.5 + 0.5
    grains = band(n, 250, 512)
    big = fbm(n, 2, 5)
    h = 0.5 + 0.18 * (rip - 0.5) * (0.4 + big) + 0.05 * grains
    m = norm(big + 0.15 * grains)
    col = tint(m, "#c9b48a", "#e1cfa6")
    shell = (band(n, 200, 512) > 2.6).astype(float)
    col = col * (1 - shell[..., None]) + shell[..., None] * lin("#f2ece0")
    save("sand", col, norm(h), 0.95, 2.0)


def t_grass(n):  # tile = 4 m; dry patchy Chennai lawn / maidan with bare earth
    patches = fbm(n, 2, 6)
    blades = band(n, 200, 512)
    bare = np.clip((patches - 0.62) * 5, 0, 1)
    gcol = tint(norm(fbm(n, 6, 4)), "#4f6a2a", "#8a8a3e")
    ecol = tint(norm(blades), "#7a6448", "#9a8160")
    col = gcol * (1 - bare[..., None]) + ecol * bare[..., None]
    col *= (0.85 + 0.15 * norm(blades))[..., None]
    h = 0.5 + 0.3 * norm(blades) * (1 - bare) - 0.1 * bare
    save("grass", col, h, 0.95, 3.0)


def t_earth(n):  # tile = 4 m; compacted roadside earth with pebbles and dust
    big = fbm(n, 2, 6); fine = band(n, 120, 512)
    w, idv = worley(n, 70)
    peb = np.clip(1 - w * 3, 0, 1) * (idv > 0.55)
    h = 0.45 + 0.2 * (big - 0.5) + 0.05 * fine + 0.35 * peb
    col = tint(norm(big + 0.3 * fine), "#6e5a44", "#9c8668")
    col = col * (1 - peb[..., None] * 0.7) + peb[..., None] * 0.7 * tint(idv, "#5a554e", "#a39a8c")
    save("earth", col, norm(h), 0.95, 3.0)


def t_granite(n):  # tile = 3.6 m; temple-courtyard flagstones, 1.2 x 0.9 m slabs, staggered
    yy, xx = np.mgrid[0:n, 0:n] / n
    rows = 4; cols = 3
    ry = yy * rows; row = np.floor(ry)
    rx = xx * cols + (row % 2) * 0.5
    sx, sy = rx - np.floor(rx), ry - row
    joint = np.minimum(np.minimum(sx, 1 - sx) * (n / cols), np.minimum(sy, 1 - sy) * (n / rows))
    jm = np.clip(1 - joint / 3.0, 0, 1)
    slab = (np.floor(rx) * 13 + row * 7) % 5 / 5.0
    speck = band(n, 220, 512); spk2 = (band(n, 150, 400) > 1.8).astype(float)
    base = 0.33 + 0.06 * slab + 0.05 * fbm(n, 3, 5)
    v = base + 0.04 * speck - 0.15 * spk2 * 0.5
    col = np.stack([v * 1.02, v, v * 0.97], -1) * (1 - jm[..., None] * 0.55)
    h = 0.6 + 0.04 * speck - 0.5 * jm + 0.08 * slab
    save("granite", col, norm(h), 0.6 + 0.15 * norm(speck) + 0.2 * jm, 3.0)


def t_pavers(n):  # tile = 1.2 m; interlocking concrete pavers (footpaths), red & grey
    yy, xx = np.mgrid[0:n, 0:n] / n
    k = 6
    ry = yy * k; row = np.floor(ry)
    rx = xx * k / 2 + (row % 2) * 0.5
    sx, sy = rx - np.floor(rx), ry - row
    j = np.minimum(np.minimum(sx, 1 - sx) * (n * 2 / k), np.minimum(sy, 1 - sy) * (n / k))
    jm = np.clip(1 - j / 2.5, 0, 1)
    pid = ((np.floor(rx) * 31 + row * 17) % 11) / 11.0
    v = 0.75 + 0.2 * pid + 0.06 * fbm(n, 8, 4)
    col = np.stack([v, v, v], -1) * (1 - 0.6 * jm[..., None])
    h = 0.7 + 0.1 * pid - 0.6 * jm + 0.04 * band(n, 200, 512)
    save("pavers", col, norm(h), 0.85, 4.0)


def t_brick(n):  # tile = 1.2 m; exposed red bricks (230x75 mm) with cement mortar
    yy, xx = np.mgrid[0:n, 0:n] / n
    rows = 15; cols = 5
    ry = yy * rows; row = np.floor(ry)
    rx = xx * cols + (row % 2) * 0.5
    sx, sy = rx - np.floor(rx), ry - row
    j = np.minimum(np.minimum(sx, 1 - sx) * (n / cols), np.minimum(sy, 1 - sy) * (n / rows))
    jm = np.clip(1 - j / 2.2, 0, 1)
    bid = ((np.floor(rx) * 31 + row * 17) % 13) / 13.0
    bcol = tint(np.clip(bid * 0.7 + 0.3 * fbm(n, 12, 4), 0, 1), "#7a3420", "#b0603e")
    mcol = lin("#9a948a")[None, None, :] * (0.9 + 0.2 * fbm(n, 30, 3))[..., None]
    col = bcol * (1 - jm[..., None]) + mcol * jm[..., None]
    h = 0.7 + 0.08 * band(n, 150, 512) - 0.5 * jm
    save("brick", col, norm(h), 0.9, 4.0)


def t_rooftile(n):  # tile = 1.5 m; Mangalore pattern clay tiles
    yy, xx = np.mgrid[0:n, 0:n] / n
    cols, rows = 4, 4
    rx, ry = xx * cols, yy * rows
    sx, sy = rx - np.floor(rx), ry - np.floor(ry)
    ridge = np.cos((sx - 0.5) * np.pi * 2) * 0.5 + 0.5
    lap = np.clip((sy - 0.85) * 8, 0, 1)
    tid = ((np.floor(rx) * 7 + np.floor(ry) * 3) % 7) / 7.0
    h = 0.3 + 0.4 * (1 - ridge) * 0.6 + 0.3 * sy - 0.4 * lap
    col = tint(np.clip(0.5 * tid + 0.5 * fbm(n, 6, 4), 0, 1), "#7c3a1e", "#b25a32")
    lich = np.clip((fbm(n, 4, 5) - 0.6) * 3, 0, 1)  # dark weathering / moss
    col = col * (1 - 0.6 * lich[..., None]) + lich[..., None] * 0.6 * lin("#3c3a2a")
    col *= (0.7 + 0.3 * (1 - lap))[..., None]
    save("rooftile", col, norm(h), 0.85, 6.0)


def t_cloth(n):  # tile = 0.25 m; woven fabric detail (multiply)
    yy, xx = np.mgrid[0:n, 0:n] / n
    k = 64
    wx = np.sin(xx * k * 2 * np.pi) * 0.5 + 0.5; wy = np.sin(yy * k * 2 * np.pi) * 0.5 + 0.5
    over = (np.floor(xx * k) + np.floor(yy * k)) % 2
    h = np.where(over > 0, wx, wy) * 0.6 + 0.2 * band(n, 30, 100)
    v = 0.88 + 0.12 * h
    save("cloth", np.stack([v, v, v], -1), norm(h), 0.95, 2.0)


ALL = {"noise": t_noise, "asphalt": t_asphalt, "plaster": t_plaster, "concrete": t_concrete, "sand": t_sand,
       "grass": t_grass, "earth": t_earth, "granite": t_granite, "pavers": t_pavers, "brick": t_brick,
       "rooftile": t_rooftile, "cloth": t_cloth}

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for k, f in ALL.items():
        if a.only and k not in a.only.split(","): continue
        f(a.size)
