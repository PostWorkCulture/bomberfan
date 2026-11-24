#!/usr/bin/env python3
"""Render in-round music options for Bomber Fan.

    python3 tools/render_music.py preview   # 16-bar previews -> build/music-options/*.mp3
    python3 tools/render_music.py <name>    # seamless 8-bar loop -> godot/assets/audio/music_<name>.wav

Four styles, all in A minor: dark_trap, arcade_drive, forest_stomp, tension_pulse.
Everything is synthesised (808s, claps, hats, FM bells, Karplus-Strong plucks,
detuned-saw pads) with kick side-chain ducking, a stereo room and a soft limiter.
Deterministic: fixed seeds.
"""
import os
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, lfilter, sosfilt

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), '..')
NOTE = {'C': -9, 'C#': -8, 'D': -7, 'D#': -6, 'E': -5, 'F': -4, 'F#': -3, 'G': -2, 'G#': -1, 'A': 0, 'A#': 1, 'B': 2}


def hz(name):
    n, octv = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[n] + (octv - 4) * 12) / 12)


def t_(n):
    return np.arange(n) / SR


def env(n, a, d=None, curve=4.0, sustain=0.0):
    a = max(1, int(a * SR))
    e = np.zeros(n)
    e[:a] = np.linspace(0, 1, min(a, n))[:min(a, n)]
    rest = n - a
    if rest > 0:
        x = np.arange(rest) / rest
        e[a:] = sustain + (1 - sustain) * (1 - x) ** curve
    return e


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, min(hi, SR * 0.45)], btype='band', fs=SR, output='sos'), x)


def lp(x, fc, order=2):
    return sosfilt(butter(order, min(fc, SR * 0.45), btype='low', fs=SR, output='sos'), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype='high', fs=SR, output='sos'), x)


def sweep_lp(x, f0, f1):
    """Lowpass whose cutoff moves exponentially from f0 to f1 across the signal."""
    y = np.zeros_like(x)
    zi = None
    blk = 128
    n = len(x)
    for i in range(0, n, blk):
        fc = f0 * (f1 / f0) ** (i / max(1, n))
        b, a = butter(2, min(fc, SR * 0.45), btype='low', fs=SR)
        if zi is None:
            zi = np.zeros(2)
        y[i:i + blk], zi = lfilter(b, a, x[i:i + blk], zi=zi)
    return y


def sat(x, d=2.0):
    return np.tanh(d * x) / np.tanh(d)


def saw(freq, n, det=0.0):
    f = freq * 2 ** (det / 1200)
    ph = np.cumsum(np.full(n, f) / SR)
    return 2 * (ph % 1.0) - 1


# ---- instruments --------------------------------------------------------------

def kick808(dur=0.5, f0=150, f1=46, click=True, rng=None):
    n = int(dur * SR)
    f = f1 + (f0 - f1) * np.exp(-t_(n) / 0.045)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, curve=2.6)
    if click and rng is not None:
        c = hp(rng.standard_normal(int(0.006 * SR)), 2000) * 0.25
        s[:len(c)] += c
    return sat(s * 1.2, 1.6)


def bass808(freq, dur, glide_from=None, rng=None):
    n = int(dur * SR)
    f = np.full(n, freq)
    if glide_from:
        k = min(n, int(0.09 * SR))
        f[:k] = glide_from * (freq / glide_from) ** (np.arange(k) / k)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) + 0.18 * np.sin(2 * ph)
    return sat(s * env(n, 0.004, curve=1.3) * 1.4, 2.2) * 0.8


def clap(rng):
    n = int(0.35 * SR)
    s = np.zeros(n)
    for k, off in enumerate([0, 0.011, 0.022]):
        i = int(off * SR)
        ln = int(0.02 * SR)
        s[i:i + ln] += rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * 0.3))
    tail = rng.standard_normal(n) * np.exp(-t_(n) / 0.09)
    s += tail * 0.6
    return bp(s, 900, 5000) * 0.9


def snare(rng):
    n = int(0.3 * SR)
    tone = np.sin(2 * np.pi * 190 * t_(n)) * np.exp(-t_(n) / 0.05)
    noise = bp(rng.standard_normal(n), 1500, 9000) * np.exp(-t_(n) / 0.08)
    return (tone * 0.5 + noise) * 0.8


def hat(rng, open_=False):
    dur = 0.28 if open_ else 0.045
    n = int(dur * SR)
    return hp(rng.standard_normal(n), 7500) * np.exp(-t_(n) / (0.09 if open_ else 0.012)) * 0.45


def shaker(rng):
    n = int(0.09 * SR)
    return bp(rng.standard_normal(n), 4500, 11000) * env(n, 0.02, curve=3) * 0.35


def tom(freq, rng, dur=0.45):
    n = int(dur * SR)
    f = freq * (1 + 0.6 * np.exp(-t_(n) / 0.03))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t_(n) / 0.16)
    s += lp(rng.standard_normal(n), 1800) * np.exp(-t_(n) / 0.02) * 0.3
    return sat(s, 1.4) * 0.8


def fm_bell(freq, dur, ratio=3.5, index=2.6):
    n = int(dur * SR)
    tt = t_(n)
    mod = np.sin(2 * np.pi * freq * ratio * tt) * index * np.exp(-tt / 0.35)
    return np.sin(2 * np.pi * freq * tt + mod) * env(n, 0.003, curve=2.2)


def pluck(freq, dur, rng, bright=0.5):
    n = int(dur * SR)
    N = int(SR / freq)
    x = np.zeros(n)
    burst = rng.standard_normal(N)
    x[:N] = lp(burst, 800 + 4000 * bright)
    a = np.zeros(N + 2)
    a[0] = 1.0
    a[N] = -0.4985
    a[N + 1] = -0.4985
    return lfilter([1.0], a, x) * env(n, 0.001, curve=1.2) * 0.6


def pad(freqs, dur, cutoff=1100, attack=0.6):
    n = int(dur * SR)
    s = np.zeros(n)
    for f in freqs:
        for det in (-11, -4, 0, 5, 12):
            s += saw(f, n, det)
    s = lp(s / (len(freqs) * 5), cutoff)
    e = np.minimum(1.0, t_(n) / attack) * np.minimum(1.0, (dur - t_(n)) / 0.4).clip(0, 1)
    return s * e


def lead(freq, dur, cutoff=2400):
    n = int(dur * SR)
    s = saw(freq, n, -6) + saw(freq, n, 6) * 0.8
    s = sweep_lp(s, cutoff, 400) * env(n, 0.004, curve=2.0)
    return s * 0.35


# ---- mixing ------------------------------------------------------------------------

class Track:
    def __init__(self, bpm, bars, tail=4.0):
        self.bpm = bpm
        self.bars = bars
        self.step = 60.0 / bpm / 4          # a 16th
        self.length = self.step * 16 * bars
        n = int((self.length + tail) * SR)
        self.buses = {k: np.zeros((n, 2)) for k in ('drums', 'bass', 'music')}
        self.send = np.zeros((n, 2))
        self.kicks = []

    def at(self, bar, step):
        return (bar * 16 + step) * self.step

    def add(self, t0, sig, bus='music', vol=1.0, pan=0.0, send=0.0):
        i = int(t0 * SR)
        n = len(self.buses[bus])
        j = min(n, i + len(sig))
        if j <= i:
            return
        a = (pan + 1) * np.pi / 4
        s = sig[:j - i] * vol
        self.buses[bus][i:j, 0] += s * np.cos(a) * np.sqrt(2)
        self.buses[bus][i:j, 1] += s * np.sin(a) * np.sqrt(2)
        if send:
            self.send[i:j, 0] += s * send * np.cos(a)
            self.send[i:j, 1] += s * send * np.sin(a)

    def kick(self, t0, sig, vol=1.0):
        self.kicks.append(t0)
        self.add(t0, sig, 'drums', vol)

    def render(self, duck=0.5):
        n = len(self.buses['drums'])
        g = np.ones(n)
        for k in self.kicks:
            i = int(k * SR)
            ln = min(n - i, int(0.22 * SR))
            g[i:i + ln] = np.minimum(g[i:i + ln], 1 - duck * (1 - np.arange(ln) / ln) ** 1.5)
        rng = np.random.default_rng(3)
        ir_n = int(2.0 * SR)
        tt = np.arange(ir_n) / ir_n
        irs = [rng.standard_normal(ir_n) * (1 - tt) ** 3.5 for _ in range(2)]
        wet = np.stack([fftconvolve(lp(self.send[:, c], 5000), irs[c])[:n] for c in range(2)], axis=1) * 0.012
        mix = self.buses['drums'] + (self.buses['bass'] + self.buses['music']) * g[:, None] + wet
        return mix


def master(x, target_db=-1.0):
    x = hp(x.T, 28).T
    x = np.tanh(x / np.max(np.abs(x)) * 1.6)
    return x / np.max(np.abs(x)) * 10 ** (target_db / 20)


# ---- the four options --------------------------------------------------------------

CHORDS = [['A2', 'C3', 'E3'], ['F2', 'A2', 'C3'], ['D2', 'F2', 'A2'], ['E2', 'G#2', 'B2']]


def dark_trap(tr, rng):
    """140 bpm half-time: 808s with glides, crisp hats with rolls, clap on 3, FM bell motif."""
    bell = ['A4', 'C5', 'E5', 'D5', 'C5', 'B4', 'G#4', 'E4']
    roots = ['A1', 'F1', 'D1', 'E1']
    for bar in range(tr.bars):
        root = roots[(bar // 2) % 4]
        kicks = [0, 10] if bar % 2 == 0 else [0, 7, 10]
        for st in kicks:
            tr.kick(tr.at(bar, st), kick808(rng=rng), 0.9)
            glide = hz(roots[((bar // 2) + 1) % 4]) if (st == 10 and bar % 2 == 1) else None
            tr.add(tr.at(bar, st), bass808(hz(root), tr.step * (6 if st == 0 else 4), glide), 'bass', 0.8)
        tr.add(tr.at(bar, 8), clap(rng), 'drums', 0.7, 0.0, 0.25)
        for st in range(0, 16, 2):
            tr.add(tr.at(bar, st), hat(rng), 'drums', 0.55 if st % 4 == 0 else 0.4, 0.3)
        if bar % 2 == 1:
            for k in range(6):
                tr.add(tr.at(bar, 12) + k * tr.step / 2, hat(rng), 'drums', 0.25 + k * 0.05, 0.3)
        if bar % 4 == 3:
            tr.add(tr.at(bar, 14), hat(rng, True), 'drums', 0.4, -0.3)
        if bar % 2 == 0:
            tr.add(tr.at(bar, 0), pad([hz(n) for n in CHORDS[(bar // 2) % 4]], tr.step * 32, 900, 1.2), 'music', 0.32, 0.0, 0.5)
        for k in range(4):
            note = bell[(bar * 4 + k) % len(bell)]
            if (bar + k) % 3 != 2:
                tr.add(tr.at(bar, k * 4 + (2 if k % 2 else 0)), fm_bell(hz(note), 0.9), 'music', 0.16, -0.4 + 0.25 * k, 0.9)


def arcade_drive(tr, rng):
    """128 bpm: four-on-the-floor, pulsing octave bass, 16th arpeggio lead, wide pad."""
    for bar in range(tr.bars):
        chord = CHORDS[(bar // 2) % 4]
        for beat in range(4):
            tr.kick(tr.at(bar, beat * 4), kick808(0.32, 140, 52, rng=rng), 0.85)
            tr.add(tr.at(bar, beat * 4 + 2), hat(rng), 'drums', 0.45, 0.35)
        tr.add(tr.at(bar, 4), snare(rng), 'drums', 0.7, 0.0, 0.3)
        tr.add(tr.at(bar, 12), snare(rng), 'drums', 0.7, 0.0, 0.3)
        root = hz(chord[0]) / 2
        for st in range(0, 16, 2):
            f = root * (2 if st % 4 == 2 else 1)
            tr.add(tr.at(bar, st), sat(lead(f, tr.step * 1.8, 900) * 2.5, 1.5), 'bass', 0.45)
        arp = [hz(n) * 2 for n in chord] + [hz(chord[0]) * 4]
        bright = 1200 + 2600 * (0.5 + 0.5 * np.sin(bar * 0.7))
        for st in range(16):
            f = arp[[0, 1, 2, 3, 2, 1][st % 6]]
            tr.add(tr.at(bar, st), lead(f, tr.step * 1.5, bright), 'music', 0.2, 0.35 * np.sin(st), 0.4)
        if bar % 2 == 0:
            tr.add(tr.at(bar, 0), pad([hz(n) for n in chord], tr.step * 32, 1600, 0.3), 'music', 0.22, 0.0, 0.5)


def forest_stomp(tr, rng):
    """112 bpm: toms and frame drum, shakers, Karplus-Strong kalimba motif over a drone."""
    motif = ['A4', 'C5', 'E5', 'G4', 'A4', 'D5', 'C5', 'E4']
    for bar in range(tr.bars):
        for st in (0, 6, 10):
            tr.kick(tr.at(bar, st), kick808(0.4, 110, 55, rng=rng), 0.8)
        tr.add(tr.at(bar, 4), tom(150, rng), 'drums', 0.55, -0.4, 0.3)
        tr.add(tr.at(bar, 12), tom(120, rng), 'drums', 0.55, 0.4, 0.3)
        if bar % 2 == 1:
            tr.add(tr.at(bar, 14), tom(175, rng, 0.3), 'drums', 0.4, -0.2, 0.3)
            tr.add(tr.at(bar, 15), tom(160, rng, 0.3), 'drums', 0.4, 0.2, 0.3)
        for st in range(16):
            tr.add(tr.at(bar, st), shaker(rng), 'drums', 0.5 if st % 4 == 2 else 0.25, 0.5)
        for k in range(8):
            if (bar * 8 + k) % 5 == 4:
                continue
            note = motif[(bar * 3 + k) % len(motif)]
            tr.add(tr.at(bar, k * 2), pluck(hz(note), 1.2, rng, 0.6), 'music', 0.4, -0.3 + 0.08 * k, 0.6)
        tr.add(tr.at(bar, 0), pluck(hz('A2'), 1.6, rng, 0.3), 'bass', 0.6)
        tr.add(tr.at(bar, 8), pluck(hz('E2'), 1.6, rng, 0.3), 'bass', 0.5)
        if bar % 4 == 0:
            tr.add(tr.at(bar, 0), pad([hz('A1'), hz('E2'), hz('A2')], tr.step * 64, 600, 2.0), 'music', 0.25, 0.0, 0.4)


def tension_pulse(tr, rng):
    """100 bpm: the current deep pulse, grown up — ticking hats, low string swells, metal pings."""
    for bar in range(tr.bars):
        tr.kick(tr.at(bar, 0), kick808(0.6, 120, 42, rng=rng), 0.9)
        tr.kick(tr.at(bar, 8), kick808(0.6, 110, 40, rng=rng), 0.6)
        tr.add(tr.at(bar, 0), bass808(hz('A1'), tr.step * 7), 'bass', 0.6)
        tr.add(tr.at(bar, 8), bass808(hz('A1') if bar % 4 < 3 else hz('G#1'), tr.step * 7), 'bass', 0.45)
        for st in range(16):
            tr.add(tr.at(bar, st), hat(rng), 'drums', 0.35 if st % 4 == 0 else 0.15, 0.4 if st % 2 else -0.4)
        if bar % 2 == 0:
            ch = [['A2', 'C3', 'E3'], ['A2', 'C3', 'D#3'], ['G#2', 'B2', 'E3'], ['A2', 'C3', 'F3']][(bar // 2) % 4]
            tr.add(tr.at(bar, 0), pad([hz(n) for n in ch], tr.step * 32, 700, 2.5), 'music', 0.3, 0.0, 0.6)
        if bar % 2 == 1:
            tr.add(tr.at(bar, 6), fm_bell(hz('E5'), 1.4, 2.76, 3.0), 'music', 0.1, 0.5, 1.0)


OPTIONS = {
    'dark_trap': (140, dark_trap),
    'arcade_drive': (128, arcade_drive),
    'forest_stomp': (112, forest_stomp),
    'tension_pulse': (100, tension_pulse),
}


def render(name, bars, loop):
    bpm, fn = OPTIONS[name]
    tr = Track(bpm, bars)
    fn(tr, np.random.default_rng(42))
    x = tr.render()
    n_loop = int(tr.length * SR)
    if loop:
        out = x[:n_loop].copy()
        out[:len(x) - n_loop] += x[n_loop:]       # wrap the tail round: seamless
        return master(out)
    out = master(x[:n_loop + int(2.0 * SR)])
    fade = int(2.0 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return out


def write_wav(path, x):
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    if what == 'preview':
        out = os.path.join(ROOT, 'build', 'music-options')
        os.makedirs(out, exist_ok=True)
        for i, name in enumerate(OPTIONS, 1):
            wav = os.path.join(out, f'{i}-{name}.wav')
            write_wav(wav, render(name, 16, False))
            mp3 = wav[:-4] + '.mp3'
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-b:a', '192k', mp3], check=True)
            os.remove(wav)
            print(mp3)
    else:
        path = os.path.join(ROOT, 'godot', 'assets', 'audio', f'music_{what}.wav')
        write_wav(path, render(what, 8, True))
        print(path)


if __name__ == '__main__':
    main()
