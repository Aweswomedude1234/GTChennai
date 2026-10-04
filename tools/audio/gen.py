#!/usr/bin/env python3
"""Procedural sound effects for GTIndian (numpy only; CC0 by construction):

    python3 tools/audio/gen.py

Synthesises the Chennai street soundscape building blocks into godot/audio/*.wav (mono, 22.05 kHz):
  horn_bike, horn_scooter, horn_auto, horn_car, horn_bus — electric/air horns with the right pitch
      pairs, attack and slight wobble (two-wheelers beep, buses blare)
  engine_auto (two-stroke putter), engine_bike (single-cylinder thump), engine_car, engine_bus —
      seamless loops; the game pitches them with speed
  amb_traffic — 30 s loop: road rumble, tyre hiss, distant horns, two-stroke drones
  amb_crowd — 20 s loop: murmur (formant-filtered noise bursts), footsteps, distant calls
  temple_bell, crow — one-shots
Real recordings can replace any of these later (same names).
"""
import os, wave
import numpy as np

SR = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "audio")
rng = np.random.default_rng(20261004)


def save(name, x, peak=0.85):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(f"[audio] {name}: {len(x) / SR:.2f}s")


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def lowpass(x, fc):
    # one-pole low-pass, applied twice
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x)
    for _ in range(2):
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y.copy()
    return y


def lp_fast(x, fc):
    """FFT brick-ish low-pass with a soft roll-off (fast for long buffers)"""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / (1 + (f / fc) ** 4)
    return np.fft.irfft(X, len(x))


def bp_fast(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= (1 / (1 + (lo / np.maximum(f, 1)) ** 4)) * (1 / (1 + (f / hi) ** 4))
    return np.fft.irfft(X, len(x))


def env(n, a, r, sustain=1.0):
    e = np.ones(n) * sustain
    na, nr = int(a * SR), int(r * SR)
    e[:na] = np.linspace(0, sustain, na)
    if nr > 0: e[-nr:] = np.linspace(sustain, 0, nr)
    return e


def horn(freqs, dur, buzz=0.6, wobble=3.0):
    t = t_(dur)
    x = np.zeros_like(t)
    for f in freqs:
        ph = 2 * np.pi * f * t + 0.02 * np.sin(2 * np.pi * wobble * t)
        # electric horns are rich square-ish tones: odd harmonics plus a little buzz
        for k, amp in ((1, 1.0), (2, 0.35 * buzz), (3, 0.5), (4, 0.15 * buzz), (5, 0.3), (7, 0.18), (9, 0.1)):
            x += amp * np.sin(k * ph)
    x = np.tanh(x * 0.8)
    x = bp_fast(x, 200, 4500)
    return x * env(len(t), 0.012, 0.05)


def engine_loop(fire_hz, dur, harsh, noise, lp, jitter=0.03, cyl_pattern=None):
    """pulse-train engine: each firing is a damped resonant thump; integer number of cycles per loop"""
    n = int(dur * SR)
    x = np.zeros(n)
    period = SR / fire_hz
    k = 0
    pos = 0.0
    while pos < n:
        i = int(pos)
        L = min(int(period * 1.6), n - i)
        tt = np.arange(L) / SR
        amp = 1.0 if cyl_pattern is None else cyl_pattern[k % len(cyl_pattern)]
        pulse = amp * np.exp(-tt * fire_hz * 3.0) * (np.sin(2 * np.pi * fire_hz * 2.2 * tt) + harsh * np.sign(np.sin(2 * np.pi * fire_hz * 5.3 * tt)))
        x[i:i + L] += pulse
        pos += period * (1 + rng.normal(0, jitter))
        k += 1
    x += noise * rng.normal(0, 1, n) * (0.6 + 0.4 * np.abs(np.sin(np.pi * fire_hz * np.arange(n) / SR)))
    x = lp_fast(x, lp)
    # crossfade the loop seam
    fade = int(0.08 * SR)
    w = np.linspace(0, 1, fade)
    x[:fade] = x[:fade] * w + x[-fade:] * (1 - w)
    return x[:-fade]


def amb_traffic(dur=30.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    # rumble: brown-ish noise, slowly breathing as waves of traffic pass
    rumble = np.cumsum(rng.normal(0, 1, n)); rumble -= lp_fast(rumble, 0.5)
    rumble = lp_fast(rumble, 300) * (0.7 + 0.3 * np.sin(2 * np.pi * t / 7.3) * np.sin(2 * np.pi * t / 3.1))
    hiss = bp_fast(rng.normal(0, 1, n), 1500, 6000) * 0.08 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 5.7) ** 2)
    x = rumble / np.max(np.abs(rumble)) + hiss
    # two-stroke drones drifting past
    for k in range(6):
        f = rng.uniform(22, 30)
        s = engine_loop(f, 6.0, 0.6, 0.15, 1800)
        s *= np.hanning(len(s))
        st = int(rng.uniform(0, dur - 6) * SR)
        x[st:st + len(s)] += s / np.max(np.abs(s)) * 0.25
    # distant horns (filtered, quiet), Chennai-dense
    hs = [([430], 0.25), ([520], 0.18), ([400, 500], 0.4), ([300, 370], 0.6), ([610], 0.15), ([470, 590], 0.3)]
    for k in range(int(dur * 1.3)):
        fr, d = hs[rng.integers(len(hs))]
        h = horn([f * rng.uniform(0.92, 1.08) for f in fr], d * rng.uniform(0.6, 1.8))
        if rng.random() < 0.35:   # double beep
            h = np.concatenate([h, np.zeros(int(0.08 * SR)), h])
        h = lp_fast(h, rng.uniform(1200, 2600)) * rng.uniform(0.05, 0.22)
        st = int(rng.uniform(0, dur - 2) * SR)
        x[st:st + len(h)] += h
    fade = int(1.0 * SR)
    w = np.linspace(0, 1, fade)
    x[:fade] = x[:fade] * w + x[-fade:] * (1 - w)
    return x[:-fade]


def amb_crowd(dur=20.0):
    n = int(dur * SR)
    x = np.zeros(n)
    # murmur: many overlapping "syllables" of vowel-formant-filtered noise at speech rhythm
    formants = [(700, 1200), (400, 2000), (300, 900), (600, 1700), (500, 1500)]
    for k in range(int(dur * 22)):
        L = int(rng.uniform(0.08, 0.25) * SR)
        f1, f2 = formants[rng.integers(len(formants))]
        sy = rng.normal(0, 1, L)
        sy = bp_fast(sy, f1 * 0.8, f1 * 1.2) + 0.5 * bp_fast(sy, f2 * 0.85, f2 * 1.15)
        pitch = rng.uniform(110, 240)
        sy *= 0.6 + 0.4 * np.sin(2 * np.pi * pitch * np.arange(L) / SR)
        sy *= np.hanning(L) * rng.uniform(0.2, 1.0)
        st = int(rng.uniform(0, dur) * SR) % (n - L)
        x[st:st + L] += sy
    x = lp_fast(x, 2500)
    fade = int(1.0 * SR)
    w = np.linspace(0, 1, fade)
    x[:fade] = x[:fade] * w + x[-fade:] * (1 - w)
    return x[:-fade]


def temple_bell(dur=4.0):
    t = t_(dur)
    x = np.zeros_like(t)
    # bronze bell: inharmonic partials (hum, prime, tierce, quint, nominal…) with long decays
    base = 520.0
    for ratio, amp, dec in ((0.5, 0.6, 1.2), (1.0, 1.0, 1.6), (1.19, 0.6, 2.2), (1.5, 0.4, 2.6), (2.0, 0.5, 3.0), (2.51, 0.25, 4.0), (3.02, 0.15, 5.0), (4.07, 0.1, 6.0)):
        x += amp * np.sin(2 * np.pi * base * ratio * t + rng.uniform(0, 6)) * np.exp(-t * dec) * (1 + 0.15 * np.sin(2 * np.pi * 2.2 * t))
    x[:int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
    return x


def crow(dur=0.45):
    t = t_(dur)
    f = 900 + 250 * np.sin(np.pi * t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph + 3.0 * np.sin(ph * 0.5)) + 0.6 * rng.normal(0, 1, len(t))
    x = bp_fast(x, 600, 3500)
    return np.tanh(x * 2) * env(len(t), 0.02, 0.12) * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * t))


if __name__ == "__main__":
    save("horn_bike", horn([520], 0.35, buzz=0.8, wobble=5))
    save("horn_scooter", horn([610], 0.28, buzz=0.5, wobble=6))
    save("horn_auto", horn([420, 480], 0.4, buzz=1.0, wobble=4))
    save("horn_car", horn([400, 505], 0.55, buzz=0.4))
    save("horn_bus", lp_fast(horn([290, 365], 0.9, buzz=1.0, wobble=2), 2200))
    save("engine_auto", engine_loop(26.0, 2.08, 0.9, 0.25, 2200, jitter=0.05), 0.7)
    save("engine_bike", engine_loop(18.0, 2.08, 0.5, 0.15, 1400, jitter=0.03, cyl_pattern=[1.0]), 0.7)
    save("engine_scooter", engine_loop(30.0, 2.08, 0.2, 0.25, 2600, jitter=0.02), 0.6)
    save("engine_car", engine_loop(45.0, 2.08, 0.1, 0.2, 900, jitter=0.01, cyl_pattern=[1, 0.9, 1, 0.95]), 0.6)
    save("engine_bus", engine_loop(28.0, 2.08, 0.4, 0.3, 500, jitter=0.02, cyl_pattern=[1, 0.8, 0.95, 0.85, 1, 0.9]), 0.7)
    save("amb_traffic", amb_traffic(), 0.7)
    save("amb_crowd", amb_crowd(), 0.6)
    save("temple_bell", temple_bell())
    save("crow", crow())
