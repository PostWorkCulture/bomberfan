"""Eight more bomber-bots in the Sparky / Rivet / Pixel style: glossy toy
robots built from everyday objects, with rubber-hose limbs, white gloves and
chunky shoes. All original designs.

  1. Boiler   — little copper steam boiler: gauge eyes, chimney, furnace belly.
  2. Dial     — valve-radio head: tuning-dial eyes, speaker-grille grin, aerial.
  3. Gumball  — gumball machine: glass dome of sweets (and a few bombs).
  4. Crumb    — retro toaster: two bombs popping up like toast.
  5. Reel     — cassette-tape head: spool eyes, a ribbon of tape.
  6. Lumen    — light bulb head with a glowing filament face, battery chest.
  7. Snap     — box camera: one big lens eye, flash bulb, neck strap.
  8. Arcade   — arcade cabinet: pixel face on the screen, joystick chest.

Run inside Blender 5.x:
    blender --background --python tools/blender/bomber_bots_2.py -- <out-dir>
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
_bb = {'__name__': 'bomber_bots'}
exec(compile(open(os.path.join(HERE, 'bomber_bots.py'), encoding='utf-8').read(), 'bomber_bots.py', 'exec'), _bb)
globals().update({k: v for k, v in _bb.items() if not k.startswith('__') and k not in ('main', 'BOTS', 'OUT')})

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else os.path.join(os.getcwd(), 'bots-2')
os.makedirs(OUT, exist_ok=True)
PI = math.pi


# ---- shared toy parts ----------------------------------------------------------------

def limbs(p, arm, glove, leg, shoe, sole, shoulder=(0.2, 0.6), hand=(0.31, 0.4), hip=(0.09, 0.34)):
    """Rubber-hose arms with white cartoon gloves, short legs and chunky shoes."""
    sx, sz = shoulder
    hx, hz = hand
    for s in (-1, 1):
        hose('Arm', [(sx * s, 0, sz), ((sx + hx) / 2 * s + 0.03 * s, -0.03, (sz + hz) / 2), (hx * s, -0.08, hz + 0.05)], 0.03, arm, p)
        sphere('Glove', 0.065, glove, p, (hx * s, -0.09, hz), scale=(1, 1.1, 0.9))
        sphere('Thumb', 0.028, glove, p, ((hx - 0.05) * s, -0.12, hz + 0.03))
        torus('Cuff', 0.05, 0.018, glove, p, (hx * s, -0.08, hz + 0.07), rot=(0.3, 0, 0))
        hose('Leg', [(hip[0] * s, 0, hip[1]), (hip[0] * s + 0.01 * s, -0.01, hip[1] * 0.55), (hip[0] * s + 0.02 * s, 0, 0.1)], 0.032, leg, p)
        box('Shoe', (0.15, 0.24, 0.09), shoe, p, (hip[0] * s + 0.02 * s, -0.04, 0.05), r=0.04)
        box('Sole', (0.155, 0.245, 0.03), sole, p, (hip[0] * s + 0.02 * s, -0.04, 0.012), r=0.012)


def cartoon_eye(p, at, r=0.05, look=(0.0, 0.0)):
    white = mat('eye_white', C('#fbfbf6'), 0.2, 0, 0.8)
    pupil = mat('pupil', C('#07080b'), 0.1, 0, 1.0)
    sphere('EyeWhite', r, white, p, at, scale=(0.9, 0.45, 1.15))
    sphere('Pupil', r * 0.5, pupil, p, (at[0] + look[0], at[1] - r * 0.38, at[2] + look[1]), scale=(0.9, 0.4, 1.15))
    sphere('Glint', r * 0.16, glow('#ffffff', 5), p, (at[0] + look[0] - r * 0.15, at[1] - r * 0.47, at[2] + look[1] + r * 0.25))


def little_bomb(p, at, r=0.06, ember='#ff8a2a'):
    body = mat('bomb_black', C('#0b0c10'), 0.18, 0.2, 1.0)
    sphere('Bomb', r, body, p, at)
    cyl('BombCap', r * 0.42, r * 0.46, r * 0.35, BRASS, p, (at[0], at[1], at[2] + r * 0.98), bev=0.003)
    hose('Fuse', [(at[0], at[1], at[2] + r * 1.1), (at[0] + r * 0.3, at[1], at[2] + r * 1.55), (at[0] + r * 0.7, at[1], at[2] + r * 1.7)],
         r * 0.1, mat('fuse', C('#b99a6a'), 0.9), p)
    sphere('Ember', r * 0.2, glow(ember, 12), p, (at[0] + r * 0.72, at[1], at[2] + r * 1.72))


# ---- 1. Boiler ------------------------------------------------------------------------

def bot_boiler():
    p = root('Boiler')
    copper = mat('copper', C('#c8743a'), 0.28, 1.0)
    iron = mat('iron', C('#2b2e34'), 0.35, 0.7)
    cream = mat('gauge_face', C('#f4ecd8'), 0.35)
    red = plastic('#d93a32')
    cyl('Tank', 0.27, 0.27, 0.5, copper, p, (0, 0, 0.66), bev=0.03)
    sphere('Dome', 0.27, copper, p, (0, 0, 0.91), scale=(1, 1, 0.55))
    for z in (0.46, 0.66, 0.86):
        torus('Band', 0.272, 0.016, iron, p, (0, 0, z))
        for k in range(14):
            a = 2 * PI * k / 14
            sphere('Rivet', 0.011, iron, p, (0.285 * math.cos(a), 0.285 * math.sin(a), z + 0.025), seg=10, rings=6)
    # gauge eyes
    for s in (-1, 1):
        cyl('GaugeRim', 0.075, 0.075, 0.04, BRASS, p, (0.1 * s, -0.255, 0.76), rot=(PI / 2, 0, 0), bev=0.008)
        cyl('Gauge', 0.062, 0.062, 0.01, cream, p, (0.1 * s, -0.277, 0.76), rot=(PI / 2, 0, 0), bev=0)
        for k in range(7):
            a = PI * 0.2 + PI * 0.6 * k / 6
            box('Tick', (0.004, 0.003, 0.012), mat('ink', C('#1a1416'), 0.6), p,
                (0.1 * s + 0.048 * math.cos(a), -0.283, 0.76 + 0.048 * math.sin(a)), rot=(0, -a + PI / 2, 0), r=0)
        box('Needle', (0.006, 0.004, 0.05), red, p, (0.1 * s - 0.012 * s, -0.285, 0.778), rot=(0, 0.5 * s, 0), r=0)
        sphere('Pivot', 0.01, BRASS, p, (0.1 * s, -0.287, 0.76))
    # grinning furnace door with a glow behind the slats
    box('Furnace', (0.24, 0.04, 0.13), iron, p, (0, -0.26, 0.56), r=0.03)
    for k in range(4):
        box('FireSlat', (0.035, 0.02, 0.07), glow('#ff7a1a', 6), p, (-0.075 + k * 0.05, -0.276, 0.56), r=0.006)
    # chimney with a spark at the top, and a valve wheel on the side
    cyl('Chimney', 0.055, 0.065, 0.26, iron, p, (0.06, 0.04, 1.12), bev=0.01)
    cyl('ChimneyCap', 0.085, 0.06, 0.05, iron, p, (0.06, 0.04, 1.26), bev=0.01)
    sphere('Spark', 0.03, glow('#ffb347', 12), p, (0.06, 0.04, 1.31))
    for k, (dx, dz, r) in enumerate([(0.05, 1.38, 0.05), (0.11, 1.45, 0.065), (0.2, 1.5, 0.05)]):
        sphere('Steam', r, mat('steam', C('#f4f6f8'), 0.9, 0, 0, None, 0, 0, 0.6), p, (dx, 0.05, dz))
    torus('Valve', 0.07, 0.014, red, p, (0.29, -0.05, 0.72), rot=(0, PI / 2, 0))
    for k in range(4):
        cyl('Spoke', 0.008, 0.008, 0.13, red, p, (0.29, -0.05, 0.72), rot=(k * PI / 4, 0, 0), bev=0)
    limbs(p, iron, WHITE, iron, red, RUBBER, shoulder=(0.25, 0.68), hand=(0.36, 0.48), hip=(0.11, 0.42))
    return p


# ---- 2. Dial -------------------------------------------------------------------------

def bot_dial():
    p = root('Dial')
    wood = mat('walnut', C('#7a4a26'), 0.4, 0, 0.6)
    cream = mat('bakelite_cream', C('#efe3c4'), 0.3, 0, 0.7)
    mint = plastic('#7fd1b9')
    box('Cabinet', (0.62, 0.36, 0.46), wood, p, (0, 0, 0.98), r=0.1, seg=6)
    box('FrontPanel', (0.54, 0.03, 0.38), cream, p, (0, -0.175, 0.98), r=0.06)
    # tuning-dial eyes with pointer pupils
    for s in (-1, 1):
        cyl('DialRim', 0.085, 0.085, 0.03, CHROME, p, (0.13 * s, -0.19, 1.04), rot=(PI / 2, 0, 0), bev=0.01)
        cyl('DialFace', 0.07, 0.07, 0.01, mat('dial_face', C('#fff8e4'), 0.3), p, (0.13 * s, -0.207, 1.04), rot=(PI / 2, 0, 0), bev=0)
        for k in range(10):
            a = 2 * PI * k / 10
            box('DialMark', (0.004, 0.003, 0.012), mat('ink', C('#1a1416'), 0.6), p,
                (0.13 * s + 0.055 * math.sin(a), -0.213, 1.04 + 0.055 * math.cos(a)), rot=(0, a, 0), r=0)
        sphere('Pupil', 0.03, mat('pupil', C('#07080b'), 0.1, 0, 1.0), p, (0.13 * s - 0.01 * s, -0.214, 1.03), scale=(1, 0.35, 1))
        sphere('Glint', 0.008, glow('#ffffff', 5), p, (0.13 * s - 0.018 * s, -0.222, 1.045))
    # amber tuning window as a brow, speaker-grille grin
    box('TuneWindow', (0.28, 0.02, 0.04), glow('#ffb347', 3), p, (0, -0.19, 1.13), r=0.015)
    box('TuneNeedle', (0.006, 0.022, 0.05), mat('red_needle', C('#c81a1a'), 0.4), p, (0.04, -0.2, 1.13), r=0)
    box('Grille', (0.3, 0.02, 0.1), mat('grille_cloth', C('#6a4024'), 0.9), p, (0, -0.19, 0.88), r=0.04)
    for k in range(5):
        box('Slat', (0.3, 0.012, 0.01), BRASS, p, (0, -0.202, 0.85 + k * 0.016), r=0.004)
    # knobs as ears, telescopic aerial with a bomb on the tip
    for s in (-1, 1):
        cyl('Knob', 0.06, 0.06, 0.05, cream, p, (0.32 * s, 0, 0.98), rot=(0, PI / 2, 0), bev=0.012)
    cyl('Aerial1', 0.012, 0.012, 0.22, CHROME, p, (0.18, 0.06, 1.3), rot=(0, 0.35, 0), bev=0)
    cyl('Aerial2', 0.008, 0.008, 0.2, CHROME, p, (0.24, 0.06, 1.48), rot=(0, 0.35, 0), bev=0)
    little_bomb(p, (0.28, 0.06, 1.6), 0.045)
    # body
    cyl('Neck', 0.06, 0.07, 0.08, DARK, p, (0, 0, 0.72))
    box('Body', (0.34, 0.24, 0.28), mint, p, (0, 0, 0.55), r=0.08)
    box('Pocket', (0.12, 0.02, 0.08), cream, p, (0, -0.125, 0.57), r=0.02)
    limbs(p, DARK, WHITE, DARK, mint, RUBBER, shoulder=(0.17, 0.64), hand=(0.3, 0.4), hip=(0.09, 0.42))
    return p


# ---- 3. Gumball ----------------------------------------------------------------------

def bot_gumball():
    p = root('Gumball')
    red = paint('#d8262c')
    glass = mat('dome_glass', C('#e8f6ff'), 0.02, 0.0, 1.0, None, 0.0, 0.0, 0.14)
    # glass dome full of sweets, with a red lid
    sphere('Dome', 0.26, glass, p, (0, 0, 1.0), scale=(1, 1, 0.95))
    cols = ['#ff4d6d', '#ffd23f', '#3ec1ff', '#7cf07c', '#ff8a2a', '#b07cff', '#ffffff']
    k = 0
    for z in (0.86, 0.94, 1.02, 1.1):
        rad = 0.2 - abs(z - 0.96) * 0.5
        n = max(4, int(rad * 40))
        for i in range(n):
            a = 2 * PI * i / n + z * 3
            at = (rad * math.cos(a), rad * math.sin(a), z)
            if k % 9 == 4:
                little_bomb(p, at, 0.04)
            else:
                sphere('Gum', 0.042, plastic(cols[k % len(cols)]), p, at, seg=18, rings=10)
            k += 1
    cyl('Lid', 0.12, 0.17, 0.08, red, p, (0, 0, 1.25), bev=0.02)
    sphere('LidKnob', 0.05, CHROME, p, (0, 0, 1.31))
    cyl('Collar', 0.2, 0.2, 0.05, CHROME, p, (0, 0, 0.77), bev=0.01)
    # red cast base with the face, coin-plate mouth and crank
    cyl('Base', 0.2, 0.26, 0.34, red, p, (0, 0, 0.58), bev=0.03)
    for s in (-1, 1):
        cartoon_eye(p, (0.075 * s, -0.215, 0.66), 0.045, look=(0.0, -0.005))
    box('CoinPlate', (0.14, 0.03, 0.09), CHROME, p, (0, -0.235, 0.53), r=0.02)
    box('CoinSlot', (0.06, 0.01, 0.012), mat('slot', C('#111114'), 0.5), p, (0, -0.252, 0.55), r=0)
    torus('Smile', 0.04, 0.008, mat('slot', C('#111114'), 0.5), p, (0, -0.252, 0.525), rot=(PI / 2, PI, 0), arc=0.5, major=16, minor=6)
    cyl('Crank', 0.02, 0.02, 0.08, CHROME, p, (0.25, -0.1, 0.55), rot=(0, PI / 2, 0), bev=0)
    sphere('CrankKnob', 0.03, plastic('#ffd23f'), p, (0.3, -0.1, 0.55))
    limbs(p, DARK, WHITE, DARK, red, RUBBER, shoulder=(0.21, 0.6), hand=(0.33, 0.4), hip=(0.1, 0.42))
    little_bomb(p, (-0.33, -0.14, 0.47), 0.06)
    return p


# ---- 4. Crumb ------------------------------------------------------------------------

def bot_crumb():
    p = root('Crumb')
    teal = plastic('#5ec8c2')
    cream = plastic('#f4ead2')
    box('Toaster', (0.56, 0.34, 0.42), teal, p, (0, 0, 0.64), r=0.13, seg=6)
    box('ChromeBand', (0.57, 0.35, -0.14), CHROME, p, (0, 0, 0.5), r=0.03)
    for x in (-0.12, 0.12):
        box('Slot', (0.08, 0.26, -0.18), mat('slot_dark', C('#18191d'), 0.6), p, (x, 0, 0.79), r=0.01)
    little_bomb(p, (-0.12, 0, 0.89), 0.07)
    little_bomb(p, (0.12, 0, 0.86), 0.07, ember='#ffd23f')
    for s in (-1, 1):
        cartoon_eye(p, (0.1 * s, -0.17, 0.68), 0.06, look=(0.0, 0.005))
        sphere('Cheek', 0.03, glow('#ff8fa3', 2), p, (0.18 * s, -0.168, 0.6), scale=(1.2, 0.3, 0.7))
    torus('Smile', 0.05, 0.01, mat('slot_dark', C('#18191d'), 0.6), p, (0, -0.172, 0.6), rot=(PI / 2, PI, 0), arc=0.5, major=20, minor=8)
    cyl('Dial', 0.035, 0.035, 0.03, cream, p, (0.21, -0.17, 0.52), rot=(PI / 2, 0, 0), bev=0.006)
    box('Lever', (0.04, 0.06, -0.17), cream, p, (0.29, 0, 0.7), r=0.012)
    box('LeverTrack', (0.01, 0.02, 0.22), mat('slot_dark', C('#18191d'), 0.6), p, (0.282, 0, 0.68), r=0.004)
    for s in (-1, 1):
        for y in (-0.12, 0.12):
            sphere('Foot', 0.03, CHROME, p, (0.22 * s, y, 0.42))
    cyl('Cord', 0.012, 0.012, 0.2, mat('cord', C('#2a2a2e'), 0.6), p, (0, 0.2, 0.55), rot=(PI / 2.5, 0, 0), bev=0)
    box('Plug', (0.05, 0.04, -0.14), cream, p, (0, 0.29, 0.48), r=0.012)
    limbs(p, DARK, WHITE, DARK, cream, teal, shoulder=(0.27, 0.6), hand=(0.37, 0.36), hip=(0.11, 0.44))
    return p


# ---- 5. Reel -------------------------------------------------------------------------

def bot_reel():
    p = root('Reel')
    shell = plastic('#2c2f3a')
    label = plastic('#ff8a2a')
    box('Shell', (0.62, 0.3, 0.4), shell, p, (0, 0, 0.98), r=0.05)
    box('Label', (0.54, 0.02, 0.16), label, p, (0, -0.152, 1.08), r=0.02)
    for k in range(3):
        box('Stripe', (0.54, 0.021, 0.012), plastic(['#ffd23f', '#ff4d6d', '#3ec1ff'][k]), p, (0, -0.154, 1.03 - k * 0.02), r=0.003)
    box('Window', (0.36, 0.02, 0.12), mat('window', C('#a9c8d8'), 0.05, 0, 1.0, None, 0, 0, 0.4), p, (0, -0.15, 0.93), r=0.03)
    # spool eyes with sprocket teeth, tape between them
    for s in (-1, 1):
        cyl('Spool', 0.06, 0.06, 0.03, mat('spool_white', C('#f2f2ee'), 0.3), p, (0.11 * s, -0.14, 0.93), rot=(PI / 2, 0, 0), bev=0.006)
        for k in range(6):
            a = 2 * PI * k / 6
            box('Tooth', (0.012, 0.01, 0.018), shell, p, (0.11 * s + 0.028 * math.cos(a), -0.16, 0.93 + 0.028 * math.sin(a)), rot=(0, -a, 0), r=0)
        sphere('Pupil', 0.016, mat('pupil', C('#07080b'), 0.1, 0, 1.0), p, (0.11 * s, -0.16, 0.93))
        cyl('TapeRoll', 0.05, 0.05, 0.02, mat('tape', C('#3a2418'), 0.5), p, (0.11 * s, -0.12, 0.93), rot=(PI / 2, 0, 0), bev=0)
    box('TapeLine', (0.24, 0.01, 0.012), mat('tape', C('#3a2418'), 0.5), p, (0, -0.155, 0.875), r=0)
    for s in (-1, 1):
        for k in range(2):
            sphere('Screw', 0.012, CHROME, p, (0.27 * s, -0.15, 0.82 + k * 0.32))
    # a loose ribbon of tape spilling out like a scarf
    hose('TapeRibbon', [(0.05, -0.15, 0.8), (0.12, -0.18, 0.7), (0.24, 0.0, 0.66), (0.33, 0.12, 0.72)], 0.008, mat('tape', C('#3a2418'), 0.5), p)
    cyl('Neck', 0.05, 0.06, 0.08, DARK, p, (0, 0, 0.75))
    box('Body', (0.3, 0.22, 0.26), plastic('#e0e3ea'), p, (0, 0, 0.58), r=0.08)
    for k, c in enumerate(['#ff4d6d', '#ffd23f', '#3ec1ff', '#7cf07c']):
        box('Key', (0.05, 0.03, 0.03), plastic(c), p, (-0.09 + k * 0.06, -0.12, 0.6), r=0.008)
    little_bomb(p, (0, 0.17, 0.62), 0.09)
    limbs(p, DARK, WHITE, DARK, label, RUBBER, shoulder=(0.15, 0.66), hand=(0.29, 0.42), hip=(0.08, 0.46))
    return p


# ---- 6. Lumen ------------------------------------------------------------------------

def bot_lumen():
    p = root('Lumen')
    glass = mat('bulb_glass', C('#fff7df'), 0.02, 0.0, 1.0, None, 0.0, 0.0, 0.2)
    filament = glow('#ffb347', 10)
    sphere('Bulb', 0.25, glass, p, (0, 0, 1.06), scale=(1, 1, 1.05))
    cyl('BulbNeck', 0.11, 0.15, 0.12, glass, p, (0, 0, 0.84), bev=0)
    sphere('InnerGlow', 0.13, mat('inner_glow', C('#ffd28a'), 0.9, 0, 0, C('#ffb347'), 1.2, 0, 0.12), p, (0, 0, 1.05))
    # filament face: coiled eyes and a smile on two support wires
    for s in (-1, 1):
        torus('EyeCoil', 0.035, 0.008, filament, p, (0.075 * s, -0.12, 1.1), rot=(PI / 2, 0, 0), major=24, minor=6)
        sphere('EyeDot', 0.012, filament, p, (0.075 * s, -0.12, 1.1))
        cyl('Support', 0.003, 0.003, 0.3, mat('wire', C('#9aa0a8'), 0.3, 1.0), p, (0.06 * s, -0.04, 0.93), rot=(0.2, 0, 0), bev=0)
    torus('Smile', 0.07, 0.007, filament, p, (0, -0.125, 1.02), rot=(PI / 2, PI, 0), arc=0.5, major=24, minor=6)
    # screw base as the neck
    for k in range(5):
        torus('Thread', 0.1, 0.014, CHROME, p, (0, 0, 0.76 - k * 0.025))
    cyl('BaseTip', 0.06, 0.04, 0.04, mat('base_tip', C('#2a2a2e'), 0.4), p, (0, 0, 0.63), bev=0.006)
    # battery body
    cyl('Battery', 0.17, 0.17, 0.3, plastic('#1d1f26'), p, (0, 0, 0.47), bev=0.02)
    cyl('BatteryBand', 0.172, 0.172, 0.11, mat('battery_copper', C('#d67a35'), 0.3, 0.8), p, (0, 0, 0.56), bev=0)
    for k in range(3):
        box('Charge', (0.035, 0.02, 0.05), glow('#7cf07c', 4), p, (-0.05 + k * 0.05, -0.17, 0.44), r=0.006)
    box('Plus', (0.05, 0.02, 0.012), WHITE, p, (0, -0.172, 0.53), r=0.003)
    box('PlusV', (0.012, 0.02, 0.05), WHITE, p, (0, -0.172, 0.53), r=0.003)
    limbs(p, DARK, WHITE, DARK, plastic('#ffd23f'), RUBBER, shoulder=(0.17, 0.56), hand=(0.3, 0.38), hip=(0.08, 0.33))
    little_bomb(p, (0.31, -0.15, 0.46), 0.06)
    return p


# ---- 7. Snap -------------------------------------------------------------------------

def bot_snap():
    p = root('Snap')
    leather = mat('camera_leather', C('#1e1f24'), 0.6)
    silver = CHROME
    box('CameraBody', (0.6, 0.3, 0.4), leather, p, (0, 0, 0.98), r=0.06)
    box('TopPlate', (0.6, 0.3, 0.08), silver, p, (0, 0, 1.2), r=0.03)
    box('BottomPlate', (0.6, 0.3, 0.04), silver, p, (0, 0, 0.77), r=0.015)
    # the big lens eye
    cyl('LensBarrel', 0.15, 0.16, 0.12, silver, p, (0, -0.2, 0.97), rot=(PI / 2, 0, 0), bev=0.01)
    cyl('LensRing', 0.13, 0.13, 0.04, leather, p, (0, -0.27, 0.97), rot=(PI / 2, 0, 0), bev=0.008)
    sphere('LensGlass', 0.11, mat('lens_glass', C('#1b3a5a'), 0.02, 0.2, 1.0), p, (0, -0.27, 0.97), scale=(1, 0.35, 1))
    sphere('Iris', 0.05, glow('#3ec1ff', 6), p, (0, -0.3, 0.97), scale=(1, 0.3, 1))
    sphere('LensGlint', 0.02, glow('#ffffff', 6), p, (-0.04, -0.31, 1.01))
    # viewfinder brow, shutter button, flash bulb
    box('Viewfinder', (0.12, 0.05, 0.06), silver, p, (-0.18, -0.13, 1.17), r=0.015)
    cyl('Shutter', 0.025, 0.025, 0.03, mat('shutter_red', C('#d93a32'), 0.3, 0, 0.6), p, (0.2, 0.0, 1.25), bev=0.005)
    cyl('FlashStem', 0.015, 0.015, 0.1, silver, p, (0.05, 0.03, 1.29), bev=0)
    cyl('FlashDish', 0.1, 0.03, 0.06, silver, p, (0.05, 0.03, 1.37), bev=0.005)
    sphere('FlashBulb', 0.04, glow('#fff3c4', 6), p, (0.05, 0.03, 1.37))
    sphere('Cheek', 0.03, glow('#ff8fa3', 2), p, (0.2, -0.15, 0.88), scale=(1.2, 0.3, 0.7))
    torus('Smile', 0.04, 0.008, silver, p, (0.19, -0.152, 0.84), rot=(PI / 2, PI, 0), arc=0.5, major=16, minor=6)
    hose('Strap', [(-0.3, 0, 1.1), (-0.36, -0.05, 0.85), (-0.15, -0.15, 0.68), (0.15, -0.15, 0.68), (0.36, -0.05, 0.85), (0.3, 0, 1.1)],
         0.014, mat('strap_red', C('#b8282c'), 0.6), p)
    cyl('Neck', 0.05, 0.06, 0.08, DARK, p, (0, 0, 0.72))
    box('Body', (0.3, 0.22, 0.26), plastic('#ffd23f'), p, (0, 0, 0.55), r=0.08)
    little_bomb(p, (0, 0.17, 0.58), 0.08)
    limbs(p, DARK, WHITE, DARK, leather, RUBBER, shoulder=(0.15, 0.62), hand=(0.29, 0.4), hip=(0.08, 0.42))
    return p


# ---- 8. Arcade -----------------------------------------------------------------------

def bot_arcade():
    p = root('Arcade')
    purple = plastic('#6b3fd4')
    neon = glow('#ff3fa4', 6)
    box('Cabinet', (0.5, 0.38, 0.86), purple, p, (0, 0.02, 0.83), r=0.05)
    for s in (-1, 1):
        box('TMold', (0.02, 0.4, 0.86), neon, p, (0.255 * s, 0.02, 0.83), r=0.008)
    box('Marquee', (0.46, 0.08, 0.12), glow('#ffd23f', 3), p, (0, -0.16, 1.18), r=0.02)
    for k in range(5):
        little_bomb(p, (-0.16 + k * 0.08, -0.205, 1.18), 0.025)
    # screen face: pixel eyes and a pixel grin
    box('Bezel', (0.42, 0.04, 0.3), DARK, p, (0, -0.175, 0.95), r=0.03)
    box('Screen', (0.36, 0.02, 0.24), mat('crt', C('#06120c'), 0.05, 0, 1.0), p, (0, -0.195, 0.95), r=0.02)
    px = glow('#5cff8a', 7)
    for s in (-1, 1):
        for (dx, dz) in ((0, 0), (0.025, 0), (0, 0.025), (0.025, 0.025)):
            box('PixEye', (0.022, 0.01, 0.022), px, p, (0.08 * s + dx - 0.0125, -0.207, 0.99 + dz - 0.0125), r=0.002)
    for i, (dx, dz) in enumerate([(-0.075, 0.03), (-0.05, 0.005), (-0.025, 0), (0, 0), (0.025, 0), (0.05, 0.005), (0.075, 0.03)]):
        box('PixGrin', (0.022, 0.01, 0.022), px, p, (dx, -0.207, 0.88 + dz), r=0.002)
    # control-panel chest with joystick and buttons
    box('Panel', (0.48, 0.18, 0.06), DARK, p, (0, -0.24, 0.74), rot=(0.25, 0, 0), r=0.02)
    cyl('Stick', 0.01, 0.01, 0.08, CHROME, p, (-0.12, -0.26, 0.8), bev=0)
    sphere('StickBall', 0.03, plastic('#d93a32'), p, (-0.12, -0.26, 0.85))
    for k, c in enumerate(['#3ec1ff', '#ffd23f', '#ff4d6d']):
        cyl('Button', 0.025, 0.025, 0.02, plastic(c), p, (0.04 + k * 0.065, -0.27, 0.775), rot=(0.25, 0, 0), bev=0.004)
    box('CoinDoor', (0.16, 0.02, 0.16), DARK, p, (0, -0.17, 0.5), r=0.015)
    for s in (-1, 1):
        box('CoinSlot', (0.035, 0.01, 0.01), glow('#ff3a2a', 4), p, (0.04 * s, -0.182, 0.53), r=0)
    limbs(p, DARK, WHITE, DARK, purple, RUBBER, shoulder=(0.25, 0.9), hand=(0.36, 0.64), hip=(0.12, 0.42))
    return p


BOTS2 = [
    ('1-boiler', 'Boiler', bot_boiler),
    ('2-dial', 'Dial', bot_dial),
    ('3-gumball', 'Gumball', bot_gumball),
    ('4-crumb', 'Crumb', bot_crumb),
    ('5-reel', 'Reel', bot_reel),
    ('6-lumen', 'Lumen', bot_lumen),
    ('7-snap', 'Snap', bot_snap),
    ('8-arcade', 'Arcade', bot_arcade),
]


def build_all():
    reset()
    base_mats()
    studio()
    return [(key, fn()) for key, label, fn in BOTS2]


def main():
    roots = build_all()
    for key, r in roots:
        for _, other in roots:
            for ob in descendants(other):
                ob.hide_render = other is not r
        bpy.context.scene.render.filepath = os.path.join(OUT, key + '.png')
        bpy.ops.render.render(write_still=True)
    for _, other in roots:
        for ob in descendants(other):
            ob.hide_render = False
    for i, (_, r) in enumerate(roots):
        r.location = ((i - 3.5) * 1.3, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'bomber_bots_2.blend'))


if __name__ == '__main__':
    main()
