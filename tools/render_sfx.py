#!/usr/bin/env python3
"""Render Bomber Fan's sound effects to WAV files for the Godot build.

A faithful offline port of the browser build's WebAudio synth (SECTION 10 —
AUDIO in ../index.html): the same voice / hiss / thump recipes, the same small
synthesised room (convolver send 0.16 through a 3.2 kHz lowpass), the same
-6 dB high shelf at 7 kHz and tanh soft clipper on the master.

    python3 tools/render_sfx.py            # writes godot/assets/audio/*.wav

Deterministic: fixed seeds, so re-running produces identical files.
"""
import os
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


def main():
    os.makedirs(OUT, exist_ok=True)
    ir = room_impulse(np.random.default_rng(1))
    rendered = {}
    for i, (name, fn) in enumerate(SOUNDS.items()):
        m = Mix(4.5)
        fn(m, np.random.default_rng(100 + i))
        rendered[name] = trim(master(m, ir))
    rendered['bass_forest'] = bass_forest()
    # One gain for everything, so the browser's balance between sounds is kept:
    # the loudest effect peaks at -1 dBFS.
    peak = max(np.max(np.abs(v)) for k, v in rendered.items())
    gain = 0.89 / peak
    for name, x in rendered.items():
        write_wav(os.path.join(OUT, name + '.wav'), x * gain)
        print(f'{name:14s} {len(x) / SR:5.2f}s  peak {20 * np.log10(np.max(np.abs(x * gain)) + 1e-9):6.1f} dBFS')
    amb = ambience_forest(np.random.default_rng(9))
    write_wav(os.path.join(OUT, 'ambience_forest.wav'), amb)
    print(f'{"ambience_forest":14s} {len(amb) / SR:5.2f}s  (wind bed, own level)')


if __name__ == '__main__':
    main()
