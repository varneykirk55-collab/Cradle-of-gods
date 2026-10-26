# Generates the original, tileable terrain / water detail textures used by
# scripts/terrain.gd and the water shader in scripts/main.gd.
#   python3 tools/make_terrain_textures.py assets/textures
# Needs numpy + Pillow. Everything is synthesised from seeded noise (FFT-filtered,
# so every texture tiles seamlessly); no external images are used.
#
#   terrain_detail.png  RGBA, 512x512
#     R  fine ground grain (grass tufts / soil crumbs)
#     G  clump / patch noise (mid-scale tonal variation)
#     B  rock: ridged cracks + strata, used triplanar on slopes
#     A  sand grain + soft ripples
#   terrain_macro.png   RGBA, 256x256, large-scale variation sampled at ~1/180 m
#     R  dry-grass patches   G  dirt / bare-soil patches   B  flower / clover speckle   A  broad tone
#   water_normal.png    RGB normal map, 256x256 (soft wave ripples)
import sys, os
import numpy as np
from PIL import Image

out = sys.argv[1] if len(sys.argv) > 1 else "assets/textures"
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(20261026)


def band(n, lo, hi, beta=1.0, aniso=(1.0, 1.0)):
    """Periodic noise: white noise filtered to frequencies [lo, hi] (cycles per tile)."""
    w = rng.standard_normal((n, n))
    f = np.fft.fftfreq(n) * n
    fx, fy = np.meshgrid(f * aniso[0], f * aniso[1])
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    filt = np.where((r >= lo) & (r <= hi), 1.0 / r ** beta, 0.0)
    # soft roll-off at the band edges
    filt *= np.clip((r - lo * 0.7) / (lo * 0.3 + 1e-6), 0, 1) * np.clip((hi * 1.3 - r) / (hi * 0.3 + 1e-6), 0, 1)
    out_ = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    out_ -= out_.mean()
    return out_ / (out_.std() + 1e-9)


def norm01(a, lo_pct=1, hi_pct=99):
    lo, hi = np.percentile(a, lo_pct), np.percentile(a, hi_pct)
    return np.clip((a - lo) / (hi - lo + 1e-9), 0, 1)


def fbm(n, base, octaves, gain=0.55):
    acc = np.zeros((n, n))
    amp = 1.0
    f = base
    for _ in range(octaves):
        acc += band(n, f, f * 2.0, 0.5) * amp
        amp *= gain
        f *= 2
    return acc


N = 512
# R: fine grain -- many tiny tufts: high-frequency noise, sharpened
grain = fbm(N, 48, 3, 0.6)
tufts = np.maximum(band(N, 90, 200, 0.2), 0) ** 1.5
r = norm01(grain * 0.7 + tufts * 0.6)
# G: clumps
g = norm01(fbm(N, 6, 4, 0.55))
# B: rock -- layered, weathered stone: domain-warped strata, broad fbm
# shading and thin dark fissures (kept free of round cell shapes, which read as spots)
warp = band(N, 2, 6, 1.0) * 0.012
yy = (np.arange(N)[:, None] / N + warp) * 2 * np.pi
strata = np.sin(yy * 14 + band(N, 3, 10, 1.0) * 0.5) * 0.5 + np.sin(yy * 37) * 0.2
broad = fbm(N, 3, 5, 0.6)
fiss = np.abs(band(N, 6, 20, 0.6, aniso=(1.0, 0.35)))
fiss = np.clip(1.0 - fiss * 6.0, 0, 1) ** 4
b = norm01(broad * 0.45 + strata * 0.9 + fbm(N, 48, 2, 0.6) * 0.18 - fiss * 1.1)
# A: sand -- very fine grain + soft ripples
ripple = np.sin(np.linspace(0, 2 * np.pi * 22, N, endpoint=False)[None, :] + band(N, 3, 8, 1.0) * 1.6)
a = norm01(fbm(N, 100, 2, 0.6) * 0.8 + ripple * 0.12 + fbm(N, 8, 3) * 0.3)
detail = np.stack([r, g, b, a], -1)
Image.fromarray((detail * 255).astype(np.uint8), "RGBA").save(os.path.join(out, "terrain_detail.png"))

M = 256
dry = norm01(fbm(M, 3, 4, 0.6))
dirt = norm01(fbm(M, 4, 4, 0.55))
flowers = norm01(np.maximum(band(M, 40, 110, 0.1), 0) ** 2 * (norm01(fbm(M, 3, 2)) > 0.55))
tone = norm01(fbm(M, 2, 3, 0.5))
macro = np.stack([dry, dirt, flowers, tone], -1)
Image.fromarray((macro * 255).astype(np.uint8), "RGBA").save(os.path.join(out, "terrain_macro.png"))

W = 256
h = fbm(W, 4, 4, 0.5) + band(W, 10, 24, 0.5, aniso=(1.0, 0.6)) * 0.5
gy, gx = np.gradient(h)
s = 0.9
nx, ny = -gx * s, -gy * s
nz = np.ones_like(nx)
l = np.sqrt(nx * nx + ny * ny + nz * nz)
nrm = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
Image.fromarray((nrm * 255).astype(np.uint8), "RGB").save(os.path.join(out, "water_normal.png"))
print("wrote", out)
