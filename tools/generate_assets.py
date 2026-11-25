#!/usr/bin/env python3
"""
Procedural PBR Texture & Realistic Audio Generator for SECTOR 09 // BODYCAM
Generates seamless 1024x1024 PBR texture sets (albedo, normal, roughness, ao)
and layered 44.1kHz 16-bit WAV audio assets using NumPy and Pillow.
"""

import math
import os
import random
import struct
import wave
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
os.makedirs(TEX_DIR, exist_ok=True)
os.makedirs(AUDIO_DIR, exist_ok=True)

TEX_SIZE = 512  # Fast generation, crisp detail with tiling & detail normal


# ============================================================================
# NOISE & TEXTURE HELPERS (Seamless periodic fBM)
# ============================================================================

def periodic_value_noise(size: int, freq: int, rng: np.random.Generator) -> np.ndarray:
    grid = rng.random((freq, freq), dtype=np.float32)
    coords = np.linspace(0, freq, size, endpoint=False, dtype=np.float32)
    x0 = np.floor(coords).astype(np.int32) % freq
    x1 = (x0 + 1) % freq
    fx = coords - np.floor(coords)
    # Quintic fade
    ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    uy = ux[:, None]
    ux = ux[None, :]

    v00 = grid[x0[:, None], x0[None, :]]
    v10 = grid[x0[:, None], x1[None, :]]
    v01 = grid[x1[:, None], x0[None, :]]
    v11 = grid[x1[:, None], x1[None, :]]

    top = v00 * (1.0 - ux) + v10 * ux
    bot = v01 * (1.0 - ux) + v11 * ux
    return top * (1.0 - uy) + bot * uy


def fbm(size: int, base_freq: int, octaves: int, seed: int, persistence: float = 0.5) -> np.ndarray:
    rng = np.random.default_rng(seed)
    total = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    amp_sum = 0.0
    freq = base_freq
    for _ in range(octaves):
        if freq >= size:
            break
        total += periodic_value_noise(size, freq, rng) * amp
        amp_sum += amp
        amp *= persistence
        freq *= 2
    return total / max(amp_sum, 1e-6)


def height_to_normal(height: np.ndarray, strength: float = 3.0) -> np.ndarray:
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    nz = np.ones_like(height)
    nx = -dx
    ny = -dy
    length = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    nx /= length
    ny /= length
    nz /= length
    normal = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5], axis=-1)
    return np.clip(normal * 255.0, 0, 255).astype(np.uint8)


def save_rgb(arr: np.ndarray, name: str):
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB")
    img.save(os.path.join(TEX_DIR, name), optimize=True)


def save_gray(arr: np.ndarray, name: str):
    img = Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="L")
    img.save(os.path.join(TEX_DIR, name), optimize=True)


def save_pbr_set(prefix: str, albedo: np.ndarray, height: np.ndarray, roughness: np.ndarray, normal_strength: float = 3.5):
    save_rgb(albedo, f"{prefix}_albedo.png")
    normal = height_to_normal(height, normal_strength)
    save_rgb(normal, f"{prefix}_normal.png")
    save_gray(np.clip(roughness, 0.04, 0.99), f"{prefix}_roughness.png")
    # AO derived from cavity/height
    ao = np.clip(0.55 + height * 0.55, 0.2, 1.0)
    save_gray(ao, f"{prefix}_ao.png")


# ============================================================================
# PBR TEXTURE GENERATORS
# ============================================================================

def gen_concrete_wall():
    s = TEX_SIZE
    n1 = fbm(s, 4, 6, 101, 0.55)
    n2 = fbm(s, 16, 4, 102, 0.5)
    fine = fbm(s, 64, 3, 103, 0.5)

    # Vertical water/grime streaks
    rng = np.random.default_rng(104)
    streak_x = periodic_value_noise(s, 24, rng)
    streak_y = periodic_value_noise(s, 4, rng)
    streaks = np.clip((streak_x * 0.7 + streak_y * 0.3) ** 2.2, 0, 1)

    # Formwork horizontal panel lines & tie-rod holes
    y = np.arange(s)[:, None]
    x = np.arange(s)[None, :]
    seam_h = ((y % (s // 2)) < 2).astype(np.float32)
    seam_v = ((x % (s // 2)) < 2).astype(np.float32)
    seams = np.clip(seam_h + seam_v, 0, 1)

    # Tie-rod dimples
    holes = np.zeros((s, s), dtype=np.float32)
    for hy in (s // 4, 3 * s // 4):
        for hx in (s // 4, 3 * s // 4):
            dist = np.sqrt((x - hx) ** 2 + (y - hy) ** 2)
            holes = np.maximum(holes, np.clip(1.0 - dist / 6.0, 0, 1))

    height = n1 * 0.45 + n2 * 0.35 + fine * 0.20 - seams * 0.35 - holes * 0.5
    height = np.clip(height, 0, 1)

    base = 0.44 + (n1 - 0.5) * 0.16 + (fine - 0.5) * 0.08 - streaks * 0.14 - seams * 0.12 - holes * 0.18
    albedo = np.stack([
        base * 238,
        base * 234,
        base * 224,
    ], axis=-1)
    # Subtle moss/dampness tint in streaks
    albedo[:, :, 1] += streaks * 6.0
    roughness = np.clip(0.78 + (1.0 - n2) * 0.18 - streaks * 0.22, 0.35, 0.96)
    save_pbr_set("concrete_wall", albedo, height, roughness, normal_strength=4.5)


def gen_asphalt_wet():
    s = TEX_SIZE
    macro = fbm(s, 4, 5, 201, 0.55)
    gravel = fbm(s, 48, 3, 202, 0.6)
    micro = fbm(s, 128, 2, 203, 0.6)
    puddle_noise = fbm(s, 3, 4, 204, 0.5)

    # Puddle mask where puddle_noise < 0.43
    puddle = np.clip((0.44 - puddle_noise) * 8.0, 0.0, 1.0)

    # Subtle cracks
    crack_f = np.abs(fbm(s, 6, 4, 205, 0.5) - 0.5)
    cracks = np.clip(1.0 - crack_f * 26.0, 0.0, 1.0)

    height = (gravel * 0.55 + micro * 0.35 + macro * 0.10) * (1.0 - puddle * 0.85) - cracks * 0.45
    height = np.clip(height, 0, 1)

    # Darker where wet/puddle
    val = (0.19 + gravel * 0.08 + micro * 0.04 - cracks * 0.08) * (1.0 - puddle * 0.42)
    albedo = np.stack([val * 235, val * 240, val * 250], axis=-1)

    # Puddles are mirror-smooth (roughness ~ 0.06), damp asphalt ~ 0.58-0.78
    roughness = (0.62 + (1.0 - gravel) * 0.24) * (1.0 - puddle) + puddle * 0.05
    save_pbr_set("asphalt_wet", albedo, height, roughness, normal_strength=5.5)


def gen_brick_industrial():
    s = TEX_SIZE
    rows = 16
    cols = 8
    y = np.arange(s)[:, None]
    x = np.arange(s)[None, :]
    row_h = s / rows
    col_w = s / cols

    row_idx = np.floor(y / row_h).astype(np.int32)
    x_shifted = (x + (row_idx % 2) * (col_w * 0.5)) % s
    col_idx = np.floor(x_shifted / col_w).astype(np.int32)

    ry = (y % row_h) / row_h
    rx = (x_shifted % col_w) / col_w

    mortar_y = ((ry < 0.11) | (ry > 0.89)).astype(np.float32)
    mortar_x = ((rx < 0.045) | (rx > 0.955)).astype(np.float32)
    mortar = np.clip(mortar_y + mortar_x, 0, 1)

    # Per-brick color variation
    rng = np.random.default_rng(301)
    brick_rand = rng.uniform(0.75, 1.18, (rows, cols))
    brick_tint = brick_rand[row_idx % rows, col_idx % cols]

    wear = fbm(s, 8, 5, 302, 0.55)
    grit = fbm(s, 32, 3, 303, 0.55)

    height = (1.0 - mortar) * (0.68 + grit * 0.25) + mortar * (0.18 + grit * 0.1)
    r = (1.0 - mortar) * (122 * brick_tint * (0.75 + wear * 0.4)) + mortar * (105 + grit * 25)
    g = (1.0 - mortar) * (66 * brick_tint * (0.75 + wear * 0.4)) + mortar * (102 + grit * 24)
    b = (1.0 - mortar) * (54 * brick_tint * (0.75 + wear * 0.4)) + mortar * (96 + grit * 22)

    # Industrial soot grime
    soot = np.clip((wear - 0.55) * 1.8, 0, 0.55)
    albedo = np.stack([r, g, b], axis=-1) * (1.0 - soot[:, :, None])
    roughness = np.clip(0.76 + mortar * 0.18 + (1.0 - wear) * 0.1, 0.5, 0.96)
    save_pbr_set("brick_industrial", albedo, height, roughness, normal_strength=6.0)


def gen_rusty_metal():
    s = TEX_SIZE
    n1 = fbm(s, 4, 6, 401, 0.55)
    n2 = fbm(s, 16, 4, 402, 0.55)
    fine = fbm(s, 64, 3, 403, 0.5)

    # Corrugated vertical ribs
    x = np.arange(s)[None, :]
    ribs = np.sin(x / s * 2.0 * math.pi * 16.0) * 0.5 + 0.5
    ribs = np.repeat(ribs, s, axis=0)

    rust_mask = np.clip((n1 * 0.7 + n2 * 0.3 - 0.48) * 3.8, 0.0, 1.0)

    # Painted dark teal-grey steel + oxidized rust patches
    paint_r = 56 + fine * 14
    paint_g = 68 + fine * 16
    paint_b = 74 + fine * 16

    rust_r = 128 + n2 * 48
    rust_g = 58 + n2 * 26
    rust_b = 30 + n2 * 14

    r = paint_r * (1.0 - rust_mask) + rust_r * rust_mask
    g = paint_g * (1.0 - rust_mask) + rust_g * rust_mask
    b = paint_b * (1.0 - rust_mask) + rust_b * rust_mask

    albedo = np.stack([r, g, b], axis=-1)
    height = ribs * 0.55 + (1.0 - rust_mask) * 0.2 + fine * 0.25
    roughness = (0.34 + fine * 0.16) * (1.0 - rust_mask) + (0.82 + n2 * 0.14) * rust_mask
    save_pbr_set("rusty_metal", albedo, height, roughness, normal_strength=5.0)


def gen_wood_crate():
    s = TEX_SIZE
    y = np.arange(s)[:, None]
    x = np.arange(s)[None, :]

    # Wood grain stretched horizontally
    grain_base = fbm(s, 8, 5, 501, 0.55)
    # Stretch via resampling
    grain_img = Image.fromarray((grain_base * 255).astype(np.uint8)).resize((s, s // 4)).resize((s, s))
    grain = np.asarray(grain_img, dtype=np.float32) / 255.0
    fine = fbm(s, 32, 3, 502, 0.5)

    # Horizontal planks (6 planks)
    plank_h = s // 6
    seam = ((y % plank_h) < 3).astype(np.float32)
    plank_id = (y // plank_h) % 6
    rng = np.random.default_rng(503)
    p_var = rng.uniform(0.84, 1.14, 6)[plank_id]

    height = (0.55 + grain * 0.3 + fine * 0.15) * (1.0 - seam * 0.75)
    base_r = 138 * p_var * (0.78 + grain * 0.35) * (1.0 - seam * 0.55)
    base_g = 104 * p_var * (0.78 + grain * 0.35) * (1.0 - seam * 0.55)
    base_b = 68 * p_var * (0.78 + grain * 0.35) * (1.0 - seam * 0.55)

    albedo = np.stack([base_r, base_g, base_b], axis=-1)
    roughness = np.clip(0.72 + (1.0 - grain) * 0.2 + seam * 0.2, 0.5, 0.96)
    save_pbr_set("wood_crate", albedo, height, roughness, normal_strength=4.5)


def gen_warehouse_floor():
    s = TEX_SIZE
    n1 = fbm(s, 4, 6, 601, 0.55)
    n2 = fbm(s, 24, 4, 602, 0.5)
    oil = np.clip((fbm(s, 3, 4, 603, 0.5) - 0.56) * 4.5, 0.0, 1.0)

    y = np.arange(s)[:, None]
    x = np.arange(s)[None, :]
    grid_line = (((x % (s // 2)) < 2) | ((y % (s // 2)) < 2)).astype(np.float32)

    height = 0.55 + n1 * 0.2 + n2 * 0.25 - grid_line * 0.35
    val = (0.34 + n1 * 0.1 + n2 * 0.06 - grid_line * 0.1) * (1.0 - oil * 0.52)
    albedo = np.stack([val * 225, val * 228, val * 232], axis=-1)
    # Oil slicks are glossy
    roughness = (0.52 + (1.0 - n2) * 0.25) * (1.0 - oil) + oil * 0.12
    save_pbr_set("warehouse_floor", albedo, height, roughness, normal_strength=3.5)


def gen_hazard_stripe():
    s = TEX_SIZE
    y = np.arange(s)[:, None]
    x = np.arange(s)[None, :]
    diag = ((x + y) // 32) % 2
    wear = fbm(s, 8, 5, 701, 0.55)
    grime = fbm(s, 32, 3, 702, 0.55)
    scratches = np.clip((wear - 0.58) * 3.5, 0.0, 0.8)

    r = np.where(diag == 0, 205.0, 32.0) * (1.0 - scratches * 0.5) + scratches * 90.0
    g = np.where(diag == 0, 158.0, 32.0) * (1.0 - scratches * 0.5) + scratches * 88.0
    b = np.where(diag == 0, 26.0, 34.0) * (1.0 - scratches * 0.5) + scratches * 84.0

    albedo = np.stack([r, g, b], axis=-1) * (0.85 + grime * 0.25)[:, :, None]
    height = 0.5 + grime * 0.25 - scratches * 0.25
    roughness = np.clip(0.55 + scratches * 0.35 + (1.0 - grime) * 0.15, 0.3, 0.95)
    save_pbr_set("hazard_stripe", albedo, height, roughness, normal_strength=3.0)


def gen_tactical_polymer():
    s = 256
    stipple = fbm(s, 32, 4, 801, 0.6)
    wear = fbm(s, 6, 4, 802, 0.5)
    val = 0.11 + stipple * 0.04 + wear * 0.03
    albedo = np.stack([val * 240, val * 245, val * 255], axis=-1)
    height = stipple * 0.7 + wear * 0.3
    roughness = np.clip(0.42 + (1.0 - wear) * 0.22, 0.25, 0.75)
    save_pbr_set("tactical_polymer", albedo, height, roughness, normal_strength=2.2)


# ============================================================================
# REALISTIC PROCEDURAL AUDIO GENERATOR (44.1kHz 16-bit WAV)
# ============================================================================

SR = 44100


def write_wav(samples: np.ndarray, filename: str):
    peak = np.max(np.abs(samples))
    if peak > 0.98:
        samples = samples / peak * 0.96
    data = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    path = os.path.join(AUDIO_DIR, filename)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(data.tobytes())


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    dt = 1.0 / SR
    rc = 1.0 / (2.0 * math.pi * max(cutoff, 20.0))
    alpha = dt / (rc + dt)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y += alpha * (x[i] - y)
        out[i] = y
    return out


def bandpass(x: np.ndarray, low_c: float, high_c: float) -> np.ndarray:
    lp = lowpass(x, high_c)
    hp = lp - lowpass(lp, low_c)
    return hp


def gen_gunshot(filename: str, indoor: bool = False):
    dur = 1.45 if indoor else 1.25
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(1001 if indoor else 1002)
    noise = rng.standard_normal(n).astype(np.float32)

    # 1. Supersonic transient crack (0 - 12ms)
    crack_env = np.exp(-t * 240.0)
    crack = bandpass(noise, 900.0, 9500.0) * crack_env * 2.2

    # 2. Low-end muzzle punch / sub-bass thump (0 - 90ms)
    freq_sweep = 165.0 * np.exp(-t * 32.0) + 42.0
    phase = 2.0 * math.pi * np.cumsum(freq_sweep) / SR
    thump = np.sin(phase) * np.exp(-t * 28.0) * 1.15

    # 3. Mechanical bolt/slide clack (~35ms)
    bolt_t = np.maximum(t - 0.032, 0.0)
    bolt_env = (t > 0.032) * np.exp(-bolt_t * 140.0)
    bolt = bandpass(noise, 2200.0, 6800.0) * bolt_env * 0.45

    # 4. Mid-body blast
    body = lowpass(noise, 1800.0) * np.exp(-t * 19.0) * 1.35

    # 5. Acoustic reflection / tail
    if indoor:
        # Slapback warehouse echoes + dense metallic tail
        tail = bandpass(noise, 220.0, 2600.0) * np.exp(-t * 4.2) * 0.58
        raw = crack + thump + body + bolt + tail
        # Early reflections
        for delay_ms, gain in [(42, 0.35), (89, 0.26), (147, 0.18), (215, 0.12)]:
            d = int(SR * delay_ms / 1000.0)
            raw[d:] += lowpass(raw[:-d], 2400.0) * gain
    else:
        # Open-air rolling distant decay
        tail = lowpass(noise, 950.0) * np.exp(-t * 3.8) * 0.42
        raw = crack + thump + body + bolt + tail
        for delay_ms, gain in [(110, 0.22), (240, 0.14)]:
            d = int(SR * delay_ms / 1000.0)
            raw[d:] += lowpass(raw[:-d], 1200.0) * gain

    # Soft clip for punchy realistic bodycam mic saturation!
    out = np.tanh(raw * 1.55) * 0.92
    write_wav(out, filename)


def gen_footstep(filename: str, surface: str, seed: int):
    dur = 0.28
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n).astype(np.float32)

    # Heel strike + toe roll
    heel_env = np.exp(-t * 48.0)
    toe_t = np.maximum(t - 0.055, 0.0)
    toe_env = (t > 0.055) * np.exp(-toe_t * 38.0)

    if surface == "concrete":
        heel = lowpass(noise, 550.0) * heel_env * 0.9 + bandpass(noise, 900.0, 3200.0) * heel_env * 0.45
        toe = bandpass(noise, 600.0, 2800.0) * toe_env * 0.5
        out = heel + toe
    elif surface == "puddle":
        splash = bandpass(noise, 1200.0, 7500.0) * np.exp(-t * 14.0) * 0.95
        thud = lowpass(noise, 400.0) * heel_env * 0.65
        out = splash + thud
    elif surface == "metal":
        ring = (np.sin(2 * math.pi * 310 * t) + 0.5 * np.sin(2 * math.pi * 645 * t)) * np.exp(-t * 24.0) * 0.35
        clang = bandpass(noise, 700.0, 4800.0) * heel_env * 0.85
        out = ring + clang + bandpass(noise, 900.0, 3500.0) * toe_env * 0.4
    else:  # wood / gravel
        grit = bandpass(noise, 1400.0, 6200.0) * (heel_env * 0.8 + toe_env * 0.65)
        thud = lowpass(noise, 320.0) * heel_env * 0.75
        out = grit + thud

    write_wav(np.tanh(out * 1.4) * 0.85, filename)


def gen_shell_casing():
    dur = 0.65
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    out = np.zeros(n, dtype=np.float32)
    # 3 decaying brass bounces
    for bounce_t, amp in [(0.01, 0.9), (0.16, 0.55), (0.29, 0.28), (0.39, 0.14)]:
        bt = np.maximum(t - bounce_t, 0.0)
        mask = (t >= bounce_t).astype(np.float32)
        env = np.exp(-bt * 42.0) * mask
        # High metallic brass harmonics
        sig = (
            np.sin(2 * math.pi * 4320 * bt) * 0.5
            + np.sin(2 * math.pi * 6890 * bt) * 0.35
            + np.sin(2 * math.pi * 9210 * bt) * 0.25
        )
        out += sig * env * amp
    write_wav(out * 0.8, "shell_casing.wav")


def gen_click(filename: str, freq1: float, freq2: float, dur: float = 0.12):
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(int(freq1))
    noise = rng.standard_normal(n).astype(np.float32)
    c1 = bandpass(noise, freq1 * 0.7, freq1 * 1.5) * np.exp(-t * 180.0)
    t2 = np.maximum(t - 0.025, 0.0)
    c2 = (t > 0.025) * bandpass(noise, freq2 * 0.7, freq2 * 1.5) * np.exp(-t2 * 160.0) * 0.7
    write_wav(np.tanh((c1 + c2) * 2.2) * 0.85, filename)


def gen_reload():
    dur = 1.65
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(2025)
    noise = rng.standard_normal(n).astype(np.float32)
    out = np.zeros(n, dtype=np.float32)

    events = [
        (0.08, 1800, 4200, 90.0, 0.65),   # Mag release click
        (0.24, 600, 2200, 35.0, 0.55),    # Mag slide out
        (0.78, 500, 1800, 45.0, 0.85),    # New mag insert thump
        (0.92, 1600, 5000, 120.0, 0.90),  # Mag lock click
        (1.24, 1200, 4800, 38.0, 0.75),   # Bolt pull back
        (1.40, 2000, 6200, 85.0, 1.0),    # Bolt release snap
    ]
    for start, lo, hi, dec, amp in events:
        et = np.maximum(t - start, 0.0)
        mask = (t >= start).astype(np.float32)
        out += bandpass(noise, lo, hi) * np.exp(-et * dec) * mask * amp

    write_wav(np.tanh(out * 1.6) * 0.88, "weapon_reload.wav")


def gen_impact(filename: str, kind: str):
    dur = 0.35
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(hash(filename) % 100000)
    noise = rng.standard_normal(n).astype(np.float32)

    if kind == "metal":
        ring = (np.sin(2 * math.pi * 1680 * t) + 0.6 * np.sin(2 * math.pi * 2940 * t)) * np.exp(-t * 18.0) * 0.55
        hit = bandpass(noise, 1800.0, 7500.0) * np.exp(-t * 65.0) * 0.9
        out = ring + hit
    elif kind == "flesh":
        thud = lowpass(noise, 480.0) * np.exp(-t * 42.0) * 1.1
        slap = bandpass(noise, 700.0, 2400.0) * np.exp(-t * 75.0) * 0.5
        out = thud + slap
    else:  # concrete / stone
        crack = bandpass(noise, 800.0, 5200.0) * np.exp(-t * 52.0) * 0.95
        debris = bandpass(noise, 2200.0, 7800.0) * np.exp(-t * 15.0) * 0.35
        out = crack + debris
    write_wav(np.tanh(out * 1.6) * 0.88, filename)


def gen_rain_loop():
    dur = 6.0
    n = int(SR * dur)
    rng = np.random.default_rng(3001)
    noise = rng.standard_normal(n).astype(np.float32)

    # Steady rain hiss + low rumble
    hiss = bandpass(noise, 1100.0, 7200.0) * 0.38
    rumble = lowpass(noise, 340.0) * 0.25
    # Individual close droplets
    drops = np.zeros(n, dtype=np.float32)
    for _ in range(180):
        idx = int(rng.integers(0, n - 400))
        dt = np.arange(400, dtype=np.float32) / SR
        f = rng.uniform(1800, 4800)
        drops[idx:idx + 400] += np.sin(2 * math.pi * f * dt) * np.exp(-dt * 120.0) * rng.uniform(0.05, 0.16)

    out = hiss + rumble + drops
    # Seamless crossfade loop ends (0.4s)
    fade = int(SR * 0.4)
    w = np.linspace(0, 1, fade, dtype=np.float32)
    out[:fade] = out[:fade] * w + out[-fade:] * (1.0 - w)
    out = out[:-fade]
    write_wav(out * 0.75, "ambience_rain.wav")


def gen_wind_loop():
    dur = 7.0
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(3002)
    noise = rng.standard_normal(n).astype(np.float32)

    mod = 0.65 + 0.35 * np.sin(2 * math.pi * t / 6.6)
    wind_low = lowpass(noise, 220.0) * 0.55 * mod
    wind_mid = bandpass(noise, 280.0, 780.0) * 0.22 * (0.5 + 0.5 * np.sin(2 * math.pi * t / 3.3 + 1.2))
    # Distant industrial hum
    hum = np.sin(2 * math.pi * 58.0 * t) * 0.04 + np.sin(2 * math.pi * 116.0 * t) * 0.02

    out = wind_low + wind_mid + hum
    fade = int(SR * 0.5)
    w = np.linspace(0, 1, fade, dtype=np.float32)
    out[:fade] = out[:fade] * w + out[-fade:] * (1.0 - w)
    out = out[:-fade]
    write_wav(out * 0.75, "ambience_wind.wav")


def gen_thunder():
    dur = 3.8
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(3003)
    noise = rng.standard_normal(n).astype(np.float32)
    env = (1.0 - np.exp(-t * 6.0)) * np.exp(-t * 0.85) * (0.7 + 0.3 * np.sin(t * 9.0))
    rumble = lowpass(noise, 180.0) * env * 1.4 + bandpass(noise, 180.0, 520.0) * np.exp(-t * 2.2) * 0.45
    write_wav(np.tanh(rumble * 1.4) * 0.9, "thunder.wav")


def gen_radio_beep(filename: str, tones: list):
    dur = 0.42
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    rng = np.random.default_rng(4001)
    noise = rng.standard_normal(n).astype(np.float32)
    out = bandpass(noise, 900.0, 3200.0) * np.exp(-t * 8.0) * 0.28
    for start, end, freq in tones:
        mask = ((t >= start) & (t <= end)).astype(np.float32)
        out += np.sin(2 * math.pi * freq * t) * mask * 0.42
    write_wav(np.tanh(out * 1.5) * 0.75, filename)


def gen_heartbeat():
    dur = 0.85
    n = int(SR * dur)
    t = np.linspace(0, dur, n, dtype=np.float32)
    b1 = np.sin(2 * math.pi * 52.0 * t) * np.exp(-t * 18.0) * 0.95
    t2 = np.maximum(t - 0.22, 0.0)
    b2 = (t >= 0.22) * np.sin(2 * math.pi * 46.0 * t2) * np.exp(-t2 * 22.0) * 0.72
    write_wav(b1 + b2, "heartbeat.wav")


def main():
    print("Generating PBR textures...")
    gen_concrete_wall()
    gen_asphalt_wet()
    gen_brick_industrial()
    gen_rusty_metal()
    gen_wood_crate()
    gen_warehouse_floor()
    gen_hazard_stripe()
    gen_tactical_polymer()

    print("Generating realistic audio assets...")
    gen_gunshot("shot_outdoor.wav", indoor=False)
    gen_gunshot("shot_indoor.wav", indoor=True)
    for i in range(1, 4):
        gen_footstep(f"step_concrete_{i}.wav", "concrete", 100 + i)
    for i in range(1, 3):
        gen_footstep(f"step_puddle_{i}.wav", "puddle", 200 + i)
        gen_footstep(f"step_metal_{i}.wav", "metal", 300 + i)
        gen_footstep(f"step_wood_{i}.wav", "wood", 400 + i)
    gen_shell_casing()
    gen_click("dry_fire.wav", 2400.0, 3800.0, 0.1)
    gen_click("flashlight_click.wav", 3100.0, 4600.0, 0.09)
    gen_reload()
    gen_impact("impact_concrete.wav", "concrete")
    gen_impact("impact_metal.wav", "metal")
    gen_impact("impact_flesh.wav", "flesh")
    gen_rain_loop()
    gen_wind_loop()
    gen_thunder()
    gen_radio_beep("radio_squelch.wav", [(0.02, 0.09, 1480.0), (0.11, 0.18, 1960.0)])
    gen_radio_beep("ai_alert.wav", [(0.02, 0.10, 1180.0), (0.12, 0.24, 920.0)])
    gen_radio_beep("bodycam_beep.wav", [(0.02, 0.08, 2400.0)])
    gen_heartbeat()

    print(f"Done! Textures in {TEX_DIR}, Audio in {AUDIO_DIR}")


if __name__ == "__main__":
    main()
