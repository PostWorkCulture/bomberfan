#!/usr/bin/env python3
"""Render Bomber Fan's sound effects to WAV files for the Godot build.

Mostly a faithful offline port of the browser build's WebAudio synth (SECTION 10 —
AUDIO in ../index.html): the same voice / hiss / thump recipes, the same small
synthesised room (convolver send 0.16 through a 3.2 kHz lowpass), the same
-6 dB high shelf at 7 kHz and tanh soft clipper on the master.

    python3 tools/render_sfx.py            # writes godot/assets/audio/*.wav

Version-2 sounds (V2 below) replace the browser recipes where those sounded
cheap: GO, countdown, explosions, round/match win, plus the sudden-death cues.

Deterministic: fixed seeds, so re-running produces identical files.
"""
import os
import sys
import wave

import numpy as np
from scipy.signal import lfilter, fftconvolve

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'godot', 'assets', 'audio')
BLOCK = 64


# ---- building blocks -------------------------------------------------------

def exp_ramp(v0, v1, n):
    if n <= 0:
        return np.zeros(0)
    v0, v1 = max(v0, 1e-6), max(v1, 1e-6)
    return v0 * (v1 / v0) ** (np.arange(n) / n)


def param_curve(n, v0, v1=None, ramp=None):
    """A WebAudio param: set to v0, optionally exponentially ramped to v1 over `ramp` seconds."""
    out = np.full(n, float(v0))
    if v1 is not None:
        k = min(n, int(ramp * SR))
        out[:k] = exp_ramp(v0, v1, k)
        out[k:] = v1
    return out


def biquad_coeffs(kind, fc, q):
    fc = min(max(fc, 10.0), SR * 0.45)
    w0 = 2 * np.pi * fc / SR
    c, s = np.cos(w0), np.sin(w0)
    if kind == 'lowpass':
        qlin = 10 ** (q / 20.0)          # WebAudio lowpass Q is in dB
        a = s / (2 * qlin)
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    else:                                 # bandpass, 0 dB peak
        a = s / (2 * q)
        b = [a, 0.0, -a]
    a_ = [1 + a, -2 * c, 1 - a]
    return np.array(b) / a_[0], np.array(a_) / a_[0]


def biquad_tv(x, kind, cutoff, q):
    """Time-varying biquad: coefficients updated every BLOCK samples."""
    y = np.zeros_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), BLOCK):
        b, a = biquad_coeffs(kind, cutoff[i], q)
        y[i:i + BLOCK], zi = lfilter(b, a, x[i:i + BLOCK], zi=zi)
    return y


def highshelf(x, fc=7000.0, gain_db=-6.0):
    A = 10 ** (gain_db / 40.0)
    w0 = 2 * np.pi * fc / SR
    c, s = np.cos(w0), np.sin(w0)
    alpha = s / 2 * np.sqrt(2)
    sa = 2 * np.sqrt(A) * alpha
    b = [A * ((A + 1) + (A - 1) * c + sa), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sa)]
    a = [(A + 1) - (A - 1) * c + sa, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sa]
    return lfilter(np.array(b) / a[0], np.array(a) / a[0], x)


def osc(kind, freq, n, detune=0.0):
    f = freq * (2 ** (detune / 1200.0))
    ph = np.cumsum(2 * np.pi * f / SR)
    if kind == 'sine':
        return np.sin(ph)
    if kind == 'triangle':
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == 'sawtooth':
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    raise ValueError(kind)


class Mix:
    """Dry bus plus reverb send, like out.sfx / out.send in the browser."""

    def __init__(self, secs):
        n = int(SR * secs)
        self.dry = np.zeros(n)
        self.send = np.zeros(n)

    def add(self, t0, sig, room):
        i = int(t0 * SR)
        j = min(len(self.dry), i + len(sig))
        self.dry[i:j] += sig[:j - i]
        if room:
            self.send[i:j] += sig[:j - i] * room


def voice(m, t0, freq, dur, vol=0.2, type='triangle', attack=0.008, hold=None, cut=2200,
          cutTo=None, q=0.9, to=None, glide=None, detune=0, room=None):
    n = int((dur + 0.08) * SR)
    fcurve = param_curve(n, freq, to, glide or dur) if to else np.full(n, float(freq))
    sig = osc(type, fcurve, n)
    if detune:
        sig = sig + osc(type, fcurve, n, detune)
    cutc = param_curve(n, cut, max(cutTo, 60) if cutTo else None, dur)
    sig = biquad_tv(sig, 'lowpass', cutc, q)
    h = min(dur * 0.18 if hold is None else hold, dur * 0.5)
    env = np.full(n, 1e-4)
    a = int(attack * SR)
    hk = int((attack + h) * SR)
    d = int(dur * SR)
    env[:a] = exp_ramp(1e-4, max(vol, 2e-4), a)
    env[a:hk] = max(vol, 2e-4)
    env[hk:d] = exp_ramp(max(vol, 2e-4), 1e-4, d - hk)
    m.add(t0, sig * env, 1.0 if room is None else room)


def hiss(m, t0, dur, vol=0.25, cut=900, cutTo=None, band=False, q=None, attack=0.006, room=None, rng=None):
    n = int(dur * SR)
    noise = (rng.random(n) * 2 - 1) * (1 - np.arange(n) / n)
    cutc = param_curve(n, cut, max(cutTo, 40) if cutTo else None, dur)
    sig = biquad_tv(noise, 'bandpass' if band else 'lowpass', cutc,
                    (1.1 if band else 0.7) if q is None else q)
    env = np.empty(n)
    a = int(attack * SR)
    env[:a] = exp_ramp(1e-4, max(vol, 2e-4), a)
    env[a:] = exp_ramp(max(vol, 2e-4), 1e-4, n - a)
    m.add(t0, sig * env, 0.7 if room is None else room)


def thump(m, t0, frm=150, to=40, glide=0.13, dur=0.4, vol=0.35, room=0.4):
    voice(m, t0, frm, dur, vol=vol, type='sine', to=to, glide=glide, cut=400, cutTo=90,
          attack=0.006, hold=0.02, room=room)


def room_impulse(rng, secs=0.9, decay=2.6):
    n = int(SR * secs)
    t = np.arange(n) / n
    d = (rng.random(n) * 2 - 1) * (1 - t) ** decay * (0.35 + 0.65 * (1 - t) ** 1.6)
    rms = max(np.sqrt(np.mean(d ** 2)), 0.000125)
    return d * (0.00125 / rms) * 0.5        # Chromium ConvolverNode normalisation, stereo IR


def master(m, ir):
    send = biquad_tv(m.send * 0.16, 'lowpass', np.full(len(m.send), 3200.0), 0.0)
    wet = fftconvolve(send, ir)[:len(m.send)]
    x = highshelf(m.dry + wet)
    return np.tanh(1.6 * x) / np.tanh(1.6) * 0.5


def master_music(sig):
    x = highshelf(sig)
    return np.tanh(1.6 * x) / np.tanh(1.6) * 0.5


def trim(x, floor_db=-70):
    thr = 10 ** (floor_db / 20) * max(np.max(np.abs(x)), 1e-9)
    idx = np.nonzero(np.abs(x) > thr)[0]
    end = idx[-1] + int(0.02 * SR) if len(idx) else len(x)
    x = x[:end].copy()
    fade = min(len(x), int(0.01 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


# ---- the sounds (SFX in index.html) -----------------------------------------

def place_bomb(m, r):
    voice(m, 0, 180, 0.16, vol=0.22, type='sine', to=120, glide=0.06, cut=700, cutTo=260, attack=0.006, hold=0.01, room=0.4)
    hiss(m, 0, 0.06, vol=0.05, cut=1400, band=True, q=0.9, room=0.3, rng=r)


def explode(m, r):
    thump(m, 0, frm=190, to=34, glide=0.16, dur=0.62, vol=0.42, room=0.5)
    hiss(m, 0, 0.5, vol=0.30, cut=1500, cutTo=180, q=0.6, room=0.9, rng=r)
    voice(m, 0.012, 110, 0.42, vol=0.16, type='triangle', to=44, glide=0.2, cut=900, cutTo=160, attack=0.008, hold=0.02)


def break_block(m, r):
    hiss(m, 0, 0.16, vol=0.20, cut=760, cutTo=380, band=True, q=1.4, room=0.6, rng=r)
    voice(m, 0, 150, 0.14, vol=0.10, type='triangle', to=80, glide=0.09, cut=900, cutTo=300, attack=0.005, hold=0.008, room=0.3)


def pickup(m, r):
    voice(m, 0, 360, 0.14, vol=0.06, type='sine', to=285, glide=0.09, cut=750, cutTo=350, attack=0.012, hold=0.012, room=0.25)


def death(m, r):
    voice(m, 0, 330, 0.62, vol=0.24, type='triangle', to=70, glide=0.5, cut=1600, cutTo=220, attack=0.012, hold=0.04, room=1.1)
    hiss(m, 0, 0.45, vol=0.14, cut=700, cutTo=140, q=0.6, room=0.9, rng=r)


def countdown(hi):
    def f(m, r):
        fr = 587.33 if hi else 392
        voice(m, 0, fr, 0.5 if hi else 0.34, vol=0.2 if hi else 0.16, type='sine', cut=2000, cutTo=600, attack=0.008, hold=0.03, room=1.3)
        voice(m, 0, fr * 2, 0.09, vol=0.045, type='triangle', cut=2600, cutTo=1200, attack=0.006, hold=0.005, room=0.6)
        thump(m, 0, frm=fr * 0.5, to=fr * 0.34, dur=0.16, vol=0.10, glide=0.06)
    return f


def go(m, r):
    thump(m, 0, frm=115, to=28, glide=0.22, dur=0.72, vol=0.46, room=0.8)
    voice(m, 0, 82.41, 0.78, vol=0.22, type='sawtooth', to=46.25, glide=0.55, cut=820, cutTo=130, q=0.65, detune=-19, attack=0.018, hold=0.2, room=1.15)
    voice(m, 0.025, 116.54, 0.64, vol=0.15, type='triangle', to=55, glide=0.46, cut=980, cutTo=180, detune=13, attack=0.02, hold=0.16, room=0.9)
    hiss(m, 0.015, 0.46, vol=0.10, cut=360, cutTo=150, band=True, q=0.75, attack=0.025, room=0.75, rng=r)


def victory(final):
    def f(m, r):
        gain = 1.0                       # MUSIC_STEPS 'mid' (0.7) / 0.6, capped at 1
        notes = [110, 164.81, 220, 130.81, 164.81, 130.81, 110, 82.41]
        for i in range(16):
            at, fade = i * 0.15, 1 - i / 24
            voice(m, at, notes[i % 8], 0.30, vol=0.085 * gain * fade, type='sawtooth', cut=850, cutTo=240, attack=0.012, hold=0.025, room=0.7)
            if i % 4 == 0:
                thump(m, at, frm=100, to=38, dur=0.25, vol=0.16 * gain * fade, room=0.3)
        voice(m, 0, 55, 2.75, vol=0.12 * gain, type='triangle', cut=450, cutTo=120, attack=0.08, hold=0.2, room=1.0)
        if final:
            voice(m, 0.3, 82.41, 2.3, vol=0.07 * gain, type='triangle', cut=600, cutTo=160, attack=0.06, hold=0.1, room=0.8)
    return f


SOUNDS = {
    'place_bomb': place_bomb,
    'explode_1': explode, 'explode_2': explode, 'explode_3': explode,
    'break_block_1': break_block, 'break_block_2': break_block,
    'pickup': pickup,
    'death': death,
    'countdown_lo': countdown(False),
    'countdown_hi': countdown(True),
    'go': go,
    'round_win': victory(False),
    'match_win': victory(True),
}


# ---- the round's bass (BASS.forest) and a forest wind bed --------------------

def bass_forest():
    root, pattern, beat, cut = 49.0, [1, 0, 0, 0, 0.6, 0, 0, 0], 0.42, 260
    loop = beat * len(pattern)
    total = loop * 3
    sig = np.zeros(int(SR * (total + 1)))
    for k in range(len(pattern) * 3):
        v = pattern[k % len(pattern)]
        if not v:
            continue
        t0 = k * beat
        n = int(0.75 * SR)
        fc = param_curve(n, root * 1.6, root, 0.09)
        s = osc('sine', fc, n)
        s = biquad_tv(s, 'lowpass', param_curve(n, cut, max(cut * 0.45, 60), 0.5), 0.8)
        env = np.full(n, 1e-4)
        a, d = int(0.02 * SR), int(0.62 * SR)
        vol = 0.55 * v
        env[:a] = exp_ramp(1e-4, vol, a)
        env[a:d] = exp_ramp(vol, 1e-4, d - a)
        i = int(t0 * SR)
        sig[i:i + n] += s * env * 0.5 * 0.7      # BASS_LEVEL x music 'mid'
    a, b = int(loop * SR), int(2 * loop * SR)
    return master_music(sig[a:b])                # middle cycle: tails wrap seamlessly


def ambience_forest(rng, secs=12.0, xfade=1.5):
    n = int(SR * (secs + xfade))
    brown = np.cumsum(rng.standard_normal(n))
    brown -= lfilter([1], [1, -0.999], brown) * 0.001
    brown = lfilter([1, -1], [1, -0.995], brown)
    t = np.arange(n) / SR
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 6.0) * np.sin(2 * np.pi * t / 2.7 + 1.0)
    cutc = 260 + 340 * gust
    wind = biquad_tv(brown / np.max(np.abs(brown)), 'lowpass', cutc, 0.0) * gust
    rustle = biquad_tv(rng.random(n) * 2 - 1, 'bandpass', np.full(n, 1800.0), 0.7) * (gust ** 3) * 0.04
    x = wind + rustle
    k = int(xfade * SR)
    body = x[:n - k].copy()
    ramp = np.linspace(0, 1, k)
    body[:k] = body[:k] * ramp + x[n - k:] * (1 - ramp)   # seamless loop
    return body / np.max(np.abs(body)) * 0.12


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())



# ---- Version 2 sounds: richer stereo designs for the cues that sounded cheap ----
# (GO, countdown, explosions, wins, and the new sudden-death cues). Built from
# the same voices plus impacts, metallic partials, debris crackle and a wider
# stereo room. Target peak levels keep them balanced against the rest.

class StereoMix:
    def __init__(self, secs):
        n = int(SR * secs)
        self.l = np.zeros(n)
        self.r = np.zeros(n)
        self.send = np.zeros(n)

    def add(self, t0, sig, room=0.6, pan=0.0):
        i = int(t0 * SR)
        j = min(len(self.l), i + len(sig))
        a = (pan + 1) * np.pi / 4
        self.l[i:j] += sig[:j - i] * np.cos(a) * np.sqrt(2)
        self.r[i:j] += sig[:j - i] * np.sin(a) * np.sqrt(2)
        self.send[i:j] += sig[:j - i] * room


def env_ad(n, attack, decay_curve=4.0):
    a = max(1, int(attack * SR))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    t = np.arange(n - a) / max(1, n - a)
    e[a:] = (1 - t) ** decay_curve
    return e


def sweep_tone(f0, f1, dur, glide, kind='sine'):
    n = int(dur * SR)
    return osc(kind, param_curve(n, f0, f1, glide), n)


def noise_band(rng, dur, lo, hi, order=2):
    from scipy.signal import butter, sosfilt
    n = int(dur * SR)
    sos = butter(order, [lo, min(hi, SR * 0.45)], btype='band', fs=SR, output='sos')
    return sosfilt(sos, rng.standard_normal(n))


def lowpass_sweep(x, f0, f1, dur, q=0.0):
    return biquad_tv(x, 'lowpass', param_curve(len(x), f0, f1, dur), q)


def sat(x, drive=2.0):
    return np.tanh(drive * x) / np.tanh(drive)


def metal_ping(m, t0, base, dur, vol, partials=(1.0, 2.76, 5.4, 8.93), pan=0.0, room=0.9):
    n = int(dur * SR)
    sig = np.zeros(n)
    for k, ratio in enumerate(partials):
        sig += osc('sine', np.full(n, base * ratio), n) * (0.6 ** k) * env_ad(n, 0.002, 3 + k * 1.5)
    m.add(t0, sig * vol, room, pan)


def crackle(m, rng, t0, dur, density, vol, lo=1500, hi=6000, room=0.7):
    n = int(dur * SR)
    sig = np.zeros(n)
    count = int(density * dur)
    for _ in range(count):
        at = int(rng.random() ** 1.6 * (n - 600))
        ln = rng.integers(60, 500)
        burst = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * 0.25))
        sig[at:at + ln] += burst * rng.uniform(0.3, 1.0) * (1 - at / n)
    from scipy.signal import butter, sosfilt
    sig = sosfilt(butter(2, [lo, hi], btype='band', fs=SR, output='sos'), sig)
    for pan in (-0.6, 0.6):
        m.add(t0, sig * vol * rng.uniform(0.7, 1.0), room, pan)


def v2_go(m, r):
    # A big "GO": sub impact, a bright snap, a metallic clang and a rising
    # power-chord stab that opens up, over a wide room.
    n = int(1.4 * SR)
    sub = sweep_tone(95, 32, 1.4, 0.25) * env_ad(n, 0.004, 2.2)
    m.add(0, sat(sub * 1.2, 1.6) * 0.55, 0.3)
    snap = noise_band(r, 0.03, 2500, 12000) * env_ad(int(0.03 * SR), 0.0005, 3)
    m.add(0, snap * 0.35, 0.5)
    metal_ping(m, 0.0, 196, 1.1, 0.12, pan=-0.25)
    metal_ping(m, 0.004, 293.7, 1.0, 0.09, pan=0.3)
    stab_n = int(0.9 * SR)
    stab = np.zeros(stab_n)
    for f, det in [(110, 0), (110, 9), (110, -9), (164.81, 4), (164.81, -6), (220, 3)]:
        stab += osc('sawtooth', np.full(stab_n, f), stab_n, det)
    stab = lowpass_sweep(stab / 6, 500, 3200, 0.12)
    stab = lowpass_sweep(stab, 3200, 400, 0.9)
    stab *= env_ad(stab_n, 0.012, 2.4)
    m.add(0.015, sat(stab, 1.8) * 0.32, 1.0, -0.15)
    m.add(0.025, sat(stab, 1.8) * 0.32, 1.0, 0.15)
    boom = lowpass_sweep(r.standard_normal(int(0.9 * SR)), 900, 90, 0.8) * env_ad(int(0.9 * SR), 0.003, 3)
    m.add(0, boom * 0.4, 1.1)


def v2_countdown(hi):
    def f(m, r):
        # A taiko-style drum: pitched skin with a stick click and a short ring.
        base = 150 if hi else 112
        dur = 0.7 if hi else 0.55
        n = int(dur * SR)
        body = sweep_tone(base * 1.9, base, dur, 0.05) * env_ad(n, 0.002, 3.2)
        m.add(0, sat(body, 1.5) * 0.5, 0.8)
        skin = lowpass_sweep(r.standard_normal(int(0.12 * SR)), 2600, 300, 0.12) * env_ad(int(0.12 * SR), 0.001, 4)
        m.add(0, skin * 0.22, 0.7)
        click = noise_band(r, 0.008, 3000, 9000) * env_ad(int(0.008 * SR), 0.0003, 2)
        m.add(0, click * 0.2, 0.3)
        metal_ping(m, 0.0, base * (4.0 if hi else 3.0), 0.5 if hi else 0.35, 0.05 if hi else 0.035)
    return f


def v2_explode(m, r):
    # Body, crack, roar and falling debris.
    n = int(1.1 * SR)
    sub = sweep_tone(120, 30, 1.1, 0.3) * env_ad(n, 0.003, 2.5)
    m.add(0, sat(sub, 1.8) * 0.6, 0.3)
    crack = noise_band(r, 0.04, 1200, 9000) * env_ad(int(0.04 * SR), 0.0005, 2.5)
    m.add(0, crack * 0.45, 0.6)
    roar_n = int(0.8 * SR)
    roar = lowpass_sweep(r.standard_normal(roar_n), 2200, 160, 0.7) * env_ad(roar_n, 0.006, 2.2)
    m.add(0.005, sat(roar * 0.9, 1.4) * 0.42, 1.0, -0.2)
    roar2 = lowpass_sweep(r.standard_normal(roar_n), 1900, 140, 0.75) * env_ad(roar_n, 0.008, 2.4)
    m.add(0.012, sat(roar2 * 0.9, 1.4) * 0.42, 1.0, 0.2)
    crackle(m, r, 0.06, 0.9, 70, 0.07)


def v2_wall_slam(m, r):
    n = int(0.6 * SR)
    m.add(0, sat(sweep_tone(85, 38, 0.6, 0.12) * env_ad(n, 0.002, 3), 2.0) * 0.55, 0.4)
    crunch = lowpass_sweep(r.standard_normal(int(0.25 * SR)), 1800, 250, 0.2) * env_ad(int(0.25 * SR), 0.001, 3)
    m.add(0, crunch * 0.35, 0.6)
    crackle(m, r, 0.02, 0.4, 50, 0.05, 800, 4000)


def v2_sd_warning(m, r):
    # Ominous two-note horn with a tremolo: the walls are about to move.
    dur = 1.9
    n = int(dur * SR)
    t = np.arange(n) / SR
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 7 * t)
    for start, f in [(0.0, 73.42), (0.85, 69.3)]:
        k = int((dur - start) * SR)
        horn = np.zeros(k)
        for det in (-8, 0, 7):
            horn += osc('sawtooth', np.full(k, f), k, det) + 0.5 * osc('sawtooth', np.full(k, f * 2), k, det)
        horn = lowpass_sweep(horn / 4.5, 300, 1400, 0.5)
        horn = lowpass_sweep(horn, 1400, 500, dur - start)
        horn *= env_ad(k, 0.08, 1.4) * trem[:k]
        m.add(start, sat(horn, 1.5) * 0.26, 1.0)
    m.add(0, sweep_tone(55, 50, dur, dur) * env_ad(n, 0.1, 1.2) * 0.3, 0.2)


def v2_sd_start(m, r):
    v2_wall_slam(m, r)
    n = int(1.6 * SR)
    chord = np.zeros(n)
    for f, det in [(55, 0), (55, 12), (82.41, -7), (110, 5), (116.54, -4)]:
        chord += osc('sawtooth', np.full(n, f), n, det)
    chord = lowpass_sweep(chord / 5, 1600, 200, 1.5) * env_ad(n, 0.01, 1.8)
    m.add(0.01, sat(chord, 2.0) * 0.3, 1.0, -0.2)
    m.add(0.02, sat(chord, 2.0) * 0.3, 1.0, 0.2)
    metal_ping(m, 0.0, 130.8, 1.4, 0.1)


def v2_victory(final):
    def f(m, r):
        # Drum fill into a bright power-chord stab and a rising bell motif.
        bpm = 132
        beat = 60 / bpm
        for i, (t, fr) in enumerate([(0, 140), (beat / 2, 120), (beat, 100), (beat * 1.5, 90)]):
            n = int(0.4 * SR)
            m.add(t, sat(sweep_tone(fr * 1.6, fr, 0.4, 0.05) * env_ad(n, 0.002, 3), 1.5) * 0.4, 0.8, -0.3 + i * 0.2)
        hit = beat * 2
        n = int(1.8 * SR)
        chord = np.zeros(n)
        notes = [110, 164.81, 220, 277.18] if final else [110, 164.81, 220]
        for fr in notes:
            for det in (-7, 0, 6):
                chord += osc('sawtooth', np.full(n, fr), n, det)
        chord = lowpass_sweep(chord / (len(notes) * 3), 3000, 600, 1.6) * env_ad(n, 0.01, 2.0)
        m.add(hit, sat(chord, 1.6) * 0.32, 1.0)
        m.add(hit, sweep_tone(110, 45, 0.8, 0.2) * env_ad(int(0.8 * SR), 0.003, 2.5) * 0.45, 0.3)
        cym = noise_band(r, 1.6, 4000, 14000) * env_ad(int(1.6 * SR), 0.002, 3.5)
        m.add(hit, cym * 0.08, 0.8, 0.3)
        bells = [440, 554.37, 659.25, 880] if final else [440, 554.37, 659.25]
        for i, fr in enumerate(bells):
            metal_ping(m, hit + 0.12 + i * beat / 2, fr, 0.9, 0.07, partials=(1.0, 2.0, 3.01, 4.2), pan=-0.3 + i * 0.2)
    return f


# ---- Arena sounds (2026-11-25 AAA pass): the mechanics and characters --------

def v2_tide(m, r):
    # Surf rolling in over sand: a swelling band of noise with a foamy top.
    dur = 2.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    swell = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    body = lowpass_sweep(noise_band(r, dur, 120, 3000), 600, 2400, dur * 0.6) * swell
    fizz = noise_band(r, dur, 3000, 9000) * swell ** 3 * 0.35
    m.add(0, body * 0.5, 0.7, -0.3)
    m.add(0.05, fizz, 0.8, 0.3)


def v2_fizz(m, r):
    n = int(0.7 * SR)
    hiss = noise_band(r, 0.7, 2500, 9000) * env_ad(n, 0.004, 2.2)
    m.add(0, hiss * 0.5, 0.4)
    m.add(0, sweep_tone(420, 180, 0.25, 0.2) * env_ad(int(0.25 * SR), 0.002, 3) * 0.12, 0.2)


def v2_press(m, r):
    # Hydraulic hiss, then a heavy steel stamp with a ring.
    n = int(0.25 * SR)
    m.add(0, noise_band(r, 0.25, 1500, 6000) * env_ad(n, 0.05, 1.0) * 0.12, 0.3)
    k = int(0.7 * SR)
    m.add(0.22, sat(sweep_tone(95, 36, 0.7, 0.1) * env_ad(k, 0.001, 3.5), 2.5) * 0.6, 0.5)
    m.add(0.22, lowpass_sweep(r.standard_normal(int(0.2 * SR)), 4000, 400, 0.15) * env_ad(int(0.2 * SR), 0.001, 3) * 0.3, 0.6)
    metal_ping(m, 0.22, 196.0, 1.0, 0.09, pan=0.2)


def v2_lever(m, r):
    for i, t0 in enumerate([0.0, 0.06, 0.12]):
        k = int(0.05 * SR)
        m.add(t0, noise_band(r, 0.05, 1500, 5000) * env_ad(k, 0.001, 4) * 0.25, 0.3, -0.2 + i * 0.2)
    metal_ping(m, 0.16, 330.0, 0.6, 0.12)
    k = int(0.3 * SR)
    m.add(0.16, sat(sweep_tone(140, 70, 0.3, 0.06) * env_ad(k, 0.001, 3), 2.0) * 0.35, 0.4)


def v2_shield_pop(m, r):
    # A glassy pop and a shimmer of bells: the shield soaks a blast.
    k = int(0.15 * SR)
    m.add(0, noise_band(r, 0.15, 2000, 10000) * env_ad(k, 0.001, 4) * 0.35, 0.6)
    for i, fr in enumerate([1046.5, 1318.5, 1568.0, 2093.0]):
        metal_ping(m, 0.02 + i * 0.035, fr, 0.7, 0.06, partials=(1.0, 2.0, 3.0), pan=-0.4 + i * 0.25)


def v2_ghost(m, r):
    # "Ooo-OOO": a breathy sine with vibrato, rising then sinking.
    dur = 1.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 330 + 140 * np.sin(np.pi * t / dur) + 9 * np.sin(2 * np.pi * 5.5 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = (np.sin(ph) + 0.3 * np.sin(2 * ph)) * np.sin(np.pi * t / dur) ** 2
    breath = noise_band(r, dur, 600, 2400) * np.sin(np.pi * t / dur) ** 2 * 0.25
    m.add(0, tone * 0.16 + breath * 0.2, 1.0)


def v2_thunder(m, r):
    dur = 3.2
    n = int(dur * SR)
    crack = noise_band(r, 0.3, 800, 7000) * env_ad(int(0.3 * SR), 0.002, 3)
    m.add(0, crack * 0.25, 0.8, 0.3)
    rumble = lowpass_sweep(noise_band(r, dur, 25, 400), 400, 80, dur)
    t = np.arange(n) / SR
    roll = (0.6 + 0.4 * np.sin(2 * np.pi * 1.3 * t) * np.sin(2 * np.pi * 0.7 * t)) * env_ad(n, 0.05, 1.6)
    m.add(0.05, sat(rumble * roll * 2.5, 1.5) * 0.5, 1.0, -0.2)


def v2_whoosh(m, r):
    dur = 1.8
    n = int(dur * SR)
    t = np.arange(n) / SR
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1) ** 0.7) ** 2
    w = biquad_tv(r.standard_normal(n), 'bandpass', param_curve(n, 300, 2200, dur), 1.2) * shape
    m.add(0, w * 0.4, 0.6, -0.4)
    m.add(0.03, w * 0.4, 0.6, 0.4)


def v2_build(m, r):
    # The beaver: two quick wooden knocks and a thud as the logs land.
    for i, t0 in enumerate([0.0, 0.12]):
        k = int(0.08 * SR)
        m.add(t0, noise_band(r, 0.08, 500, 2500) * env_ad(k, 0.001, 5) * 0.4, 0.3, -0.2 + 0.4 * i)
        m.add(t0, sweep_tone(420, 260, 0.08, 0.03) * env_ad(k, 0.001, 4) * 0.2, 0.3)
    k = int(0.3 * SR)
    m.add(0.25, sat(sweep_tone(120, 60, 0.3, 0.05) * env_ad(k, 0.001, 3), 1.5) * 0.4, 0.4)


V2_ARENA = {
    'tide': (v2_tide, -6.0),
    'fizz': (v2_fizz, -9.0),
    'press': (v2_press, -4.0),
    'lever': (v2_lever, -7.0),
    'shield_pop': (v2_shield_pop, -6.0),
    'ghost': (v2_ghost, -9.0),
    'thunder': (v2_thunder, -6.0),
    'whoosh': (v2_whoosh, -10.0),
    'build': (v2_build, -8.0),
}


def ambience_beach(rng, secs=12.0, xfade=1.5):
    # Waves breaking every few seconds on a bed of distant surf.
    n = int(SR * (secs + xfade))
    t = np.arange(n) / SR
    bed = biquad_tv(rng.standard_normal(n), 'lowpass', np.full(n, 700.0), 0.0) * 0.25
    waves = np.zeros(n)
    for c in np.arange(0.5, secs + xfade, 3.1):
        k = int(2.6 * SR)
        i = int(c * SR)
        j = min(n, i + k)
        tt = np.arange(j - i) / SR
        sh = np.sin(np.pi * np.clip(tt / 2.6, 0, 1)) ** 2
        waves[i:j] += biquad_tv(rng.standard_normal(j - i), 'lowpass', np.full(j - i, 1800.0), 0.0) * sh
    x = bed + waves * 0.6
    k = int(xfade * SR)
    body = x[:n - k].copy()
    ramp = np.linspace(0, 1, k)
    body[:k] = body[:k] * ramp + x[n - k:] * (1 - ramp)
    return body / np.max(np.abs(body)) * 0.12


def ambience_haunted(rng, secs=12.0, xfade=1.5):
    # A low moaning wind and the odd creak.
    x = ambience_forest(rng, secs, xfade) / 0.12
    n = len(x)
    t = np.arange(n) / SR
    moan = np.sin(2 * np.pi * (110 + 15 * np.sin(2 * np.pi * t / 5.0)) * t) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 6.0)) ** 3 * 0.12
    x = x + moan
    return x / np.max(np.abs(x)) * 0.12


def ambience_factory(rng, secs=12.0, xfade=1.5):
    # Mains hum, a thumping machine and air hissing from the vents.
    n = int(SR * (secs + xfade))
    t = np.arange(n) / SR
    hum = (np.sin(2 * np.pi * 50 * t) + 0.5 * np.sin(2 * np.pi * 100 * t) + 0.2 * np.sin(2 * np.pi * 150 * t)) * 0.15
    thump = np.zeros(n)
    for c in np.arange(0.0, secs + xfade, 0.75):
        i = int(c * SR)
        k = min(n - i, int(0.2 * SR))
        thump[i:i + k] += np.sin(2 * np.pi * 55 * np.arange(k) / SR) * np.exp(-np.arange(k) / SR * 22)
    air = biquad_tv(rng.standard_normal(n), 'bandpass', np.full(n, 3500.0), 0.6) * 0.05
    x = hum + thump * 0.35 + air
    k = int(xfade * SR)
    body = x[:n - k].copy()
    ramp = np.linspace(0, 1, k)
    body[:k] = body[:k] * ramp + x[n - k:] * (1 - ramp)
    return body / np.max(np.abs(body)) * 0.1


V2 = {
    'go': (v2_go, -2.0),
    'countdown_lo': (v2_countdown(False), -9.0),
    'countdown_hi': (v2_countdown(True), -7.0),
    'explode_1': (v2_explode, -2.5), 'explode_2': (v2_explode, -2.5), 'explode_3': (v2_explode, -2.5),
    'round_win': (v2_victory(False), -5.0),
    'match_win': (v2_victory(True), -4.0),
    'sd_warning': (v2_sd_warning, -5.0),
    'sd_start': (v2_sd_start, -3.0),
    'wall_slam': (v2_wall_slam, -8.0),
}


def render_v2(name, fn, peak_db, seed):
    m = StereoMix(4.0)
    r = np.random.default_rng(seed)
    fn(m, r)
    irl = room_impulse(np.random.default_rng(seed + 1), 1.4, 3.0)
    irr = room_impulse(np.random.default_rng(seed + 2), 1.4, 3.0)
    send = biquad_tv(m.send * 0.3, 'lowpass', np.full(len(m.send), 4500.0), 0.0)
    l = highshelf(m.l + fftconvolve(send, irl)[:len(send)] * 1.6)
    rr = highshelf(m.r + fftconvolve(send, irr)[:len(send)] * 1.6)
    x = np.stack([l, rr], axis=1)
    x = np.tanh(1.3 * x) / np.tanh(1.3)
    mono = np.max(np.abs(x), axis=1)
    thr = 10 ** (-70 / 20) * mono.max()
    end = np.nonzero(mono > thr)[0][-1] + int(0.02 * SR)
    x = x[:end]
    fade = int(0.015 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)


def write_wav_stereo(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())


def render_arena(names):
    """python3 tools/render_sfx.py arena [name ...]: only the arena sounds and
    ambience beds, leaving every other WAV untouched."""
    os.makedirs(OUT, exist_ok=True)
    for i, (name, (fn, peak)) in enumerate(V2_ARENA.items()):
        if names and name not in names:
            continue
        x = render_v2(name, fn, peak, 900 + i * 7)
        write_wav_stereo(os.path.join(OUT, name + '.wav'), x)
        print(f'{name:14s} {len(x) / SR:5.2f}s  peak {peak:6.1f} dBFS  (arena)')
    for name, fn in (('ambience_beach', ambience_beach), ('ambience_haunted', ambience_haunted), ('ambience_factory', ambience_factory)):
        if names and name not in names:
            continue
        amb = fn(np.random.default_rng(19))
        write_wav(os.path.join(OUT, name + '.wav'), amb)
        print(f'{name:14s} {len(amb) / SR:5.2f}s  (bed)')


def main():
    if len(sys.argv) > 1 and sys.argv[1] == 'arena':
        render_arena(sys.argv[2:])
        return
    os.makedirs(OUT, exist_ok=True)
    ir = room_impulse(np.random.default_rng(1))
    rendered = {}
    for i, (name, fn) in enumerate(SOUNDS.items()):
        m = Mix(4.5)
        fn(m, np.random.default_rng(100 + i))
        rendered[name] = trim(master(m, ir))
    # (bass_forest() is kept for reference; the round music is now tools/render_music.py)
    # One gain for everything, so the browser's balance between sounds is kept:
    # the loudest effect peaks at -1 dBFS.
    peak = max(np.max(np.abs(v)) for k, v in rendered.items())
    gain = 0.89 / peak
    for name, x in rendered.items():
        write_wav(os.path.join(OUT, name + '.wav'), x * gain)
        print(f'{name:14s} {len(x) / SR:5.2f}s  peak {20 * np.log10(np.max(np.abs(x * gain)) + 1e-9):6.1f} dBFS')
    for i, (name, (fn, peak)) in enumerate(V2.items()):
        x = render_v2(name, fn, peak, 500 + i * 7)
        write_wav_stereo(os.path.join(OUT, name + '.wav'), x)
        print(f'{name:14s} {len(x) / SR:5.2f}s  peak {peak:6.1f} dBFS  (v2 stereo)')
    amb = ambience_forest(np.random.default_rng(9))
    write_wav(os.path.join(OUT, 'ambience_forest.wav'), amb)
    print(f'{"ambience_forest":14s} {len(amb) / SR:5.2f}s  (wind bed, own level)')


if __name__ == '__main__':
    main()
