#!/usr/bin/env python3
"""
Clean, Natural Tactical Audio Generator for SECTOR 09 // BODYCAM
Produces warm, balanced, non-clipping 44.1kHz 16-bit WAV audio using proper
multi-pole pink/brown noise filtering and realistic physical envelopes.
"""

import math
import os
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
os.makedirs(AUDIO_DIR, exist_ok=True)
SR = 44100


def write_wav(samples: np.ndarray, filename: str, target_peak: float = 0.85):
    samples = samples.astype(np.float64)
    samples -= np.mean(samples)
    peak = np.max(np.abs(samples))
    if peak > 1e-6:
        samples = samples / peak * target_peak
    # Soft fade-in/out 3ms to eliminate any click
    fade = min(int(SR * 0.003), len(samples) // 4)
    if fade > 0:
        ramp = np.linspace(0.0, 1.0, fade)
        samples[:fade] *= ramp
        samples[-fade:] *= ramp[::-1]
    data = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(os.path.join(AUDIO_DIR, filename), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(data.tobytes())


def fft_filter(x: np.ndarray, low_hz: float = 0.0, high_hz: float = 20000.0, slope: float = 2.0) -> np.ndarray:
    """Clean zero-phase frequency-domain filter (no digital ringing or aliasing)."""
    freqs = np.fft.rfftfreq(len(x), d=1.0 / SR)
    spec = np.fft.rfft(x)
    gain = np.ones_like(freqs)
    if low_hz > 0.0:
        gain *= 1.0 / np.sqrt(1.0 + (low_hz / np.maximum(freqs, 1e-3)) ** (2.0 * slope))
    if high_hz < SR * 0.49:
        gain *= 1.0 / np.sqrt(1.0 + (freqs / max(high_hz, 1.0)) ** (2.0 * slope))
    gain[0] = 0.0
    return np.fft.irfft(spec * gain, n=len(x))


def pink_noise(n: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(n)
    freqs = np.fft.rfftfreq(n, d=1.0 / SR)
    spec = np.fft.rfft(white)
    scale = 1.0 / np.sqrt(np.maximum(freqs, 20.0))
    scale[0] = 0.0
    return np.fft.irfft(spec * scale, n=n)


def gen_gunshot(filename: str, indoor: bool = False):
    dur = 0.95 if indoor else 0.78
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    p = pink_noise(n, 501 if indoor else 502)

    # 1. Punchy sub-bass muzzle thump (clean sine pitch drop 135Hz -> 42Hz)
    f_sweep = 42.0 + 95.0 * np.exp(-t * 48.0)
    thump = np.sin(2.0 * math.pi * np.cumsum(f_sweep) / SR) * np.exp(-t * 26.0) * 1.1

    # 2. Crisp short transient crack (first 18ms)
    crack = fft_filter(p, 700.0, 4800.0, 2.0) * np.exp(-t * 95.0) * 1.4

    # 3. Warm mid-body boom (0 - 110ms)
    body = fft_filter(p, 110.0, 1400.0, 2.0) * np.exp(-t * 16.0) * 1.15

    # 4. Subtle natural tail (no harsh metallic resonance)
    tail_decay = 4.8 if indoor else 6.2
    tail_hi = 1350.0 if indoor else 850.0
    tail = fft_filter(p, 120.0, tail_hi, 2.0) * np.exp(-t * tail_decay) * (0.36 if indoor else 0.22)

    raw = thump + crack + body + tail
    if indoor:
        # Subtle warm room reflection
        for ms, g in [(38, 0.20), (82, 0.12)]:
            d = int(SR * ms / 1000.0)
            raw[d:] += fft_filter(raw[:-d], 100.0, 1400.0) * g

    # Gentle warm saturation without harsh clipping
    out = np.tanh(raw * 1.15)
    write_wav(out, filename, 0.90)


def gen_footstep(filename: str, surface: str, seed: int):
    dur = 0.24
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    p = pink_noise(n, seed)

    heel = np.exp(-t * 42.0)
    toe = (t > 0.048) * np.exp(-np.maximum(t - 0.048, 0.0) * 36.0)

    if surface == "puddle":
        out = fft_filter(p, 450.0, 3200.0) * np.exp(-t * 15.0) * 0.8 + fft_filter(p, 60.0, 280.0) * heel * 0.7
    elif surface == "metal":
        out = fft_filter(p, 180.0, 1800.0) * heel * 0.85 + fft_filter(p, 350.0, 2200.0) * toe * 0.45
    elif surface == "wood":
        out = fft_filter(p, 80.0, 520.0) * heel * 1.0 + fft_filter(p, 300.0, 1600.0) * toe * 0.4
    else:  # concrete
        out = fft_filter(p, 70.0, 420.0) * heel * 1.0 + fft_filter(p, 400.0, 2100.0) * (heel * 0.35 + toe * 0.45)

    write_wav(out, filename, 0.78)


def gen_shell_casing():
    dur = 0.45
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    out = np.zeros(n)
    for bt0, amp in [(0.01, 0.85), (0.14, 0.45), (0.25, 0.22)]:
        bt = np.maximum(t - bt0, 0.0)
        m = (t >= bt0).astype(np.float64)
        env = np.exp(-bt * 45.0) * m
        sig = np.sin(2 * math.pi * 3850 * bt) * 0.5 + np.sin(2 * math.pi * 5920 * bt) * 0.3
        out += sig * env * amp
    write_wav(out, "shell_casing.wav", 0.55)


def gen_click(filename: str, lo: float, hi: float, dur: float = 0.09):
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    p = pink_noise(n, int(lo + hi))
    sig = fft_filter(p, lo, hi) * np.exp(-t * 140.0)
    write_wav(sig, filename, 0.72)


def gen_reload():
    dur = 1.55
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    p = pink_noise(n, 777)
    out = np.zeros(n)
    events = [
        (0.06, 900, 2800, 90.0, 0.55),   # Mag catch
        (0.22, 220, 1200, 32.0, 0.50),   # Mag slide out
        (0.75, 160, 900, 42.0, 0.85),    # Fresh mag seated
        (0.88, 1000, 3400, 110.0, 0.85), # Mag lock click
        (1.18, 450, 2200, 40.0, 0.65),   # Charging handle pull
        (1.34, 800, 3200, 85.0, 0.95),   # Bolt slam forward
    ]
    for s0, lo, hi, dec, amp in events:
        et = np.maximum(t - s0, 0.0)
        m = (t >= s0).astype(np.float64)
        out += fft_filter(p, lo, hi) * np.exp(-et * dec) * m * amp
    write_wav(out, "weapon_reload.wav", 0.82)


def gen_impact(filename: str, kind: str):
    dur = 0.26
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    p = pink_noise(n, abs(hash(filename)) % 9999 + 1)
    if kind == "metal":
        out = fft_filter(p, 900.0, 4200.0) * np.exp(-t * 55.0) + np.sin(2 * math.pi * 1420 * t) * np.exp(-t * 24.0) * 0.25
    elif kind == "flesh":
        out = fft_filter(p, 70.0, 520.0) * np.exp(-t * 38.0)
    else:
        out = fft_filter(p, 260.0, 2600.0) * np.exp(-t * 48.0)
    write_wav(out, filename, 0.80)


def gen_rain_loop():
    """Soft, natural rainfall — pure warm filtered pink noise, ZERO synthetic beeps!"""
    dur = 6.0
    n = int(SR * dur)
    p = pink_noise(n, 3011)
    # Warm natural rain bed (220Hz - 2600Hz, gentle roll-off)
    out = fft_filter(p, 220.0, 2600.0, 2.0) * 0.65 + fft_filter(p, 80.0, 350.0, 2.0) * 0.35
    # Seamless loop crossfade
    fade = int(SR * 0.5)
    w = np.linspace(0.0, 1.0, fade)
    out[:fade] = out[:fade] * w + out[-fade:] * (1.0 - w)
    out = out[:-fade]
    write_wav(out, "ambience_rain.wav", 0.42)


def gen_wind_loop():
    """Gentle natural night breeze — soft low-passed pink noise, ZERO hum!"""
    dur = 7.0
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    p = pink_noise(n, 3012)
    mod = 0.72 + 0.28 * np.sin(2.0 * math.pi * t / 6.5)
    out = fft_filter(p, 65.0, 420.0, 2.0) * mod
    fade = int(SR * 0.5)
    w = np.linspace(0.0, 1.0, fade)
    out[:fade] = out[:fade] * w + out[-fade:] * (1.0 - w)
    out = out[:-fade]
    write_wav(out, "ambience_wind.wav", 0.36)


def gen_thunder():
    dur = 3.2
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    p = pink_noise(n, 3013)
    env = (1.0 - np.exp(-t * 5.0)) * np.exp(-t * 0.95) * (0.75 + 0.25 * np.sin(t * 7.5))
    out = fft_filter(p, 38.0, 260.0, 2.0) * env
    write_wav(out, "thunder.wav", 0.82)


def gen_radio_tone(filename: str, freqs: list, dur: float = 0.28):
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    out = np.zeros(n)
    for s0, s1, f in freqs:
        m = ((t >= s0) & (t <= s1)).astype(np.float64)
        # Smooth bell envelope per tone
        seg_len = max(s1 - s0, 1e-4)
        u = np.clip((t - s0) / seg_len, 0.0, 1.0)
        env = np.sin(math.pi * u) * m
        out += np.sin(2.0 * math.pi * f * t) * env * 0.45
    write_wav(out, filename, 0.55)


def gen_heartbeat():
    dur = 0.80
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n)
    b1 = np.sin(2 * math.pi * 55 * t) * np.exp(-t * 20.0)
    t2 = np.maximum(t - 0.22, 0.0)
    b2 = (t >= 0.22) * np.sin(2 * math.pi * 48 * t2) * np.exp(-t2 * 24.0) * 0.7
    write_wav(b1 + b2, "heartbeat.wav", 0.65)


def main():
    gen_gunshot("shot_outdoor.wav", indoor=False)
    gen_gunshot("shot_indoor.wav", indoor=True)
    for i in range(1, 4):
        gen_footstep(f"step_concrete_{i}.wav", "concrete", 100 + i)
    for i in range(1, 3):
        gen_footstep(f"step_puddle_{i}.wav", "puddle", 200 + i)
        gen_footstep(f"step_metal_{i}.wav", "metal", 300 + i)
        gen_footstep(f"step_wood_{i}.wav", "wood", 400 + i)
    gen_shell_casing()
    gen_click("dry_fire.wav", 1200.0, 3200.0, 0.08)
    gen_click("flashlight_click.wav", 1800.0, 4200.0, 0.07)
    gen_click("hitmarker.wav", 2400.0, 5200.0, 0.055)
    gen_click("ui_hover.wav", 1600.0, 3200.0, 0.04)
    gen_click("ui_click.wav", 900.0, 2600.0, 0.07)
    gen_reload()
    gen_impact("impact_concrete.wav", "concrete")
    gen_impact("impact_metal.wav", "metal")
    gen_impact("impact_flesh.wav", "flesh")
    gen_rain_loop()
    gen_wind_loop()
    gen_thunder()
    gen_radio_tone("radio_squelch.wav", [(0.02, 0.09, 980.0), (0.11, 0.18, 1280.0)])
    gen_radio_tone("ai_alert.wav", [(0.02, 0.11, 760.0), (0.13, 0.23, 620.0)])
    gen_radio_tone("bodycam_beep.wav", [(0.02, 0.09, 1650.0)])
    gen_heartbeat()
    print("Clean tactical audio generated OK!")


if __name__ == "__main__":
    main()
