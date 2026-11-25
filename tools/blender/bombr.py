"""Bombr — Bomber Fan's own bomber hero (an original character).

Three takes on the same chibi kid, modelled with the helpers in
bomber_bots.py and rendered in its studio:

  A. Hard Hat   — demolition kid: orange hard hat with a headlamp, goggles,
                  teal overalls, a belt of little bombs, red neckerchief.
  B. Aviator    — "bomber" as in pilot: leather flying cap with ear flaps,
                  brass goggles up on the forehead, fleece-collar jacket,
                  a long scarf, a bomb tucked under one arm.
  C. Blast Suit — padded bomb-disposal suit, round helmet with a tinted
                  visor and the face peeking out behind it.

Run inside Blender (Blender 5.x):
    blender --background --python tools/blender/bombr.py -- <out-dir>
Renders bombr-a.png, bombr-b.png, bombr-c.png and saves bombr_concepts.blend.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
_bb = {'__name__': 'bomber_bots'}
exec(compile(open(os.path.join(HERE, 'bomber_bots.py'), encoding='utf-8').read(), 'bomber_bots.py', 'exec'), _bb)
globals().update({k: v for k, v in _bb.items() if not k.startswith('__') and k not in ('main', 'BOTS', 'OUT')})

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else os.path.join(os.getcwd(), 'bombr')
os.makedirs(OUT, exist_ok=True)


# ---- shared pieces ---------------------------------------------------------------

def face(p, skin, z=1.0, y_front=-0.245, eye_col='#3a2a1e'):
    """A friendly round face: big eyes with glints, small nose, smile, blush."""
    sphere('Head', 0.27, skin, p, (0, 0, z), scale=(1.0, 0.96, 0.98))
    white = mat('eye_white', C('#fbfbf6'), 0.25, 0.0, 0.8)
    iris = mat('iris', C(eye_col), 0.2, 0.0, 1.0)
    for s in (-1, 1):
        sphere('EyeWhite', 0.062, white, p, (0.095 * s, y_front + 0.02, z + 0.02), scale=(0.85, 0.45, 1.12))
        sphere('Iris', 0.036, iris, p, (0.093 * s, y_front - 0.006, z + 0.012), scale=(0.9, 0.4, 1.12))
        sphere('Glint', 0.011, glow('#ffffff', 5), p, (0.082 * s, y_front - 0.022, z + 0.045))
        sphere('Blush', 0.03, mat('blush', C('#ff8f86'), 0.6), p, (0.16 * s, y_front + 0.035, z - 0.06), scale=(1.2, 0.3, 0.7))
    sphere('Nose', 0.026, skin, p, (0, y_front - 0.012, z - 0.03))
    torus('Smile', 0.05, 0.011, mat('mouth', C('#4a1f1a'), 0.4), p, (0, y_front + 0.004, z - 0.075),
          rot=(math.pi / 2, math.pi, 0), arc=0.5, major=20, minor=8)


def mini_bomb(p, at, r=0.055):
    body = mat('mini_bomb', C('#15161b'), 0.2, 0.2, 1.0)
    sphere('MiniBomb', r, body, p, at)
    cyl('MiniCap', r * 0.4, r * 0.45, r * 0.4, BRASS, p, (at[0], at[1], at[2] + r * 0.95), bev=0.004)
    sphere('MiniEmber', r * 0.22, glow('#ff8a2a', 10), p, (at[0], at[1], at[2] + r * 1.35))


def gloved_arms(p, sleeve, glove, shoulder_z=0.66, reach=0.3, hand_z=0.42):
    for s in (-1, 1):
        hose('Arm', [(0.17 * s, 0, shoulder_z), (0.25 * s, -0.03, shoulder_z - 0.1), (reach * s, -0.06, hand_z + 0.05)], 0.045, sleeve, p)
        sphere('Glove', 0.068, glove, p, (reach * s, -0.07, hand_z), scale=(1, 1.05, 0.95))
        sphere('Thumb', 0.028, glove, p, ((reach - 0.05) * s, -0.11, hand_z + 0.03))


def boots(p, leather, sole):
    for s in (-1, 1):
        cyl('Leg', 0.055, 0.05, 0.16, leather, p, (0.09 * s, 0, 0.2), bev=0.01)
        box('Boot', (0.15, 0.24, 0.12), leather, p, (0.095 * s, -0.035, 0.07), r=0.05)
        box('Sole', (0.155, 0.245, 0.035), sole, p, (0.095 * s, -0.035, 0.015), r=0.012)


# ---- A. Hard Hat -------------------------------------------------------------------

def bombr_hardhat():
    p = root('Bombr_A')
    skin = mat('skin_a', C('#f2c49b'), 0.55, 0.0, 0.2)
    teal = plastic('#1fa3a0')
    orange = paint('#ff8a1e')
    face(p, skin)
    # hard hat: dome, brim, ridge, headlamp
    sphere('Hat', 0.29, orange, p, (0, 0.03, 1.15), scale=(1.02, 1.04, 0.72))
    cyl('Brim', 0.33, 0.35, 0.03, orange, p, (0, 0.0, 1.13), rot=(-0.12, 0, 0), bev=0.012)
    box('Ridge', (0.06, 0.46, 0.05), orange, p, (0, 0.04, 1.35), r=0.022)
    cyl('Lamp', 0.05, 0.055, 0.07, DARK, p, (0, -0.26, 1.25), rot=(math.pi / 2 - 0.35, 0, 0), bev=0.01)
    cyl('LampLens', 0.038, 0.038, 0.012, glow('#fff3c4', 10), p, (0, -0.295, 1.237), rot=(math.pi / 2 - 0.35, 0, 0), bev=0)
    # goggles pushed up on the hat band
    for s in (-1, 1):
        torus('GoggleRim', 0.048, 0.013, CHROME, p, (0.11 * s, -0.255, 1.17), rot=(math.pi / 2 - 0.45, 0, 0))
        sphere('GoggleGlass', 0.043, mat('goggle_glass', C('#5fd3ff'), 0.05, 0.0, 1.0), p,
               (0.11 * s, -0.25, 1.17), scale=(1, 0.35, 1), rot=(-0.45, 0, 0))
    # body: overalls with a bib, neckerchief, belt of bombs
    cyl('Neck', 0.07, 0.08, 0.08, skin, p, (0, 0, 0.74))
    torus('Kerchief', 0.11, 0.035, plastic('#e8473c'), p, (0, 0, 0.71))
    sphere('KerchiefTip', 0.055, plastic('#e8473c'), p, (0.03, -0.1, 0.66), scale=(1.0, 0.5, 1.2))
    box('Torso', (0.36, 0.27, 0.32), teal, p, (0, 0, 0.53), r=0.1)
    box('Bib', (0.2, 0.03, 0.14), teal, p, (0, -0.14, 0.58), r=0.03)
    box('Pocket', (0.09, 0.02, 0.06), plastic('#178583'), p, (0, -0.158, 0.57), r=0.012)
    for s in (-1, 1):
        cyl('Button', 0.018, 0.018, 0.012, BRASS, p, (0.07 * s, -0.16, 0.64), rot=(math.pi / 2, 0, 0), bev=0)
    torus('Belt', 0.185, 0.03, mat('belt', C('#6a4524'), 0.6), p, (0, 0, 0.43), scale=(1.0, 0.78, 1.0))
    box('Buckle', (0.07, 0.02, 0.05), BRASS, p, (0, -0.15, 0.43), r=0.01)
    for a in (-0.9, -0.35, 0.35, 0.9):
        mini_bomb(p, (0.19 * math.sin(a) * 1.0, -0.15 * math.cos(a), 0.43), 0.045)
    gloved_arms(p, teal, plastic('#ffd23f'))
    boots(p, mat('boot_a', C('#3b2a20'), 0.55), plastic('#ff8a1e'))
    return p


# ---- B. Aviator ---------------------------------------------------------------------

def bombr_aviator():
    p = root('Bombr_B')
    skin = mat('skin_b', C('#e9b48a'), 0.55, 0.0, 0.2)
    leather = mat('leather', C('#7a4a2a'), 0.45, 0.0, 0.4)
    fleece = mat('fleece', C('#f2e6cf'), 0.95)
    face(p, skin, eye_col='#2d4a7a')
    # flying cap over the top and back of the head, ear flaps, fleece edge
    sphere('Cap', 0.288, leather, p, (0, 0.03, 1.04), scale=(1.0, 1.0, 0.92))
    for s in (-1, 1):
        box('EarFlap', (0.05, 0.16, 0.2), leather, p, (0.27 * s, 0.0, 0.93), rot=(0, 0.12 * s, 0), r=0.04)
        torus('FlapEdge', 0.085, 0.014, fleece, p, (0.29 * s, 0.0, 0.92), rot=(0, math.pi / 2, 0), scale=(1.0, 0.9, 1.15))
    torus('CapEdge', 0.27, 0.025, fleece, p, (0, -0.07, 1.08), rot=(math.pi / 2 - 0.55, 0, 0), arc=0.5, major=28)
    # brass goggles pushed up on the forehead
    for s in (-1, 1):
        torus('GoggleRim', 0.06, 0.018, BRASS, p, (0.075 * s, -0.215, 1.19), rot=(math.pi / 2 - 0.75, 0, 0))
        sphere('GoggleGlass', 0.055, mat('amber_glass', C('#ffb347'), 0.05, 0.0, 1.0), p,
               (0.075 * s, -0.21, 1.19), scale=(1, 0.35, 1), rot=(-0.75, 0, 0))
    torus('GoggleStrap', 0.262, 0.013, mat('strap', C('#3a2416'), 0.6), p, (0, 0.03, 1.17), rot=(-0.45, 0, 0), scale=(1.06, 1.0, 1.0))
    # jacket with a fleece collar and zip, long flowing scarf
    cyl('Neck', 0.07, 0.08, 0.08, skin, p, (0, 0, 0.74))
    box('Jacket', (0.38, 0.28, 0.32), leather, p, (0, 0, 0.53), r=0.1)
    torus('Collar', 0.13, 0.045, fleece, p, (0, 0, 0.69))
    box('Zip', (0.02, 0.02, 0.26), CHROME, p, (0, -0.14, 0.53), r=0.008)
    for s in (-1, 1):
        box('Pocket', (0.09, 0.02, 0.07), mat('leather_dark', C('#5e3820'), 0.5), p, (0.1 * s, -0.142, 0.47), r=0.015)
    red = plastic('#d93a32')
    torus('Scarf', 0.12, 0.04, red, p, (0, 0, 0.72))
    hose('ScarfTail', [(0.08, 0.09, 0.72), (0.2, 0.2, 0.68), (0.32, 0.28, 0.74), (0.42, 0.33, 0.7)], 0.035, red, p)
    box('ScarfEnd', (0.08, 0.02, 0.1), red, p, (0.44, 0.34, 0.69), rot=(0, 0.3, 0.4), r=0.015)
    box('Trousers', (0.32, 0.24, 0.12), mat('olive', C('#5d6b3a'), 0.7), p, (0, 0, 0.33), r=0.05)
    gloved_arms(p, leather, mat('glove_b', C('#3a2416'), 0.55))
    # a bomb tucked under the right arm
    body = mat('bomb_black', C('#0b0c10'), 0.18, 0.2, 1.0)
    sphere('Bomb', 0.11, body, p, (0.27, -0.12, 0.5))
    cyl('BombCap', 0.045, 0.05, 0.04, BRASS, p, (0.27, -0.12, 0.62), bev=0.005)
    hose('Fuse', [(0.27, -0.12, 0.64), (0.29, -0.13, 0.7), (0.33, -0.14, 0.72)], 0.008, mat('fuse', C('#b99a6a'), 0.9), p)
    sphere('Ember', 0.016, glow('#ff8a2a', 12), p, (0.335, -0.14, 0.725))
    boots(p, mat('boot_b', C('#2b1d14'), 0.5), RUBBER)
    return p


# ---- C. Blast Suit --------------------------------------------------------------------

def bombr_blastsuit():
    p = root('Bombr_C')
    skin = mat('skin_c', C('#c98d64'), 0.55, 0.0, 0.2)
    suit = plastic('#5f7a3a')
    pad = plastic('#4a6230')
    face(p, skin, z=0.98, y_front=-0.235, eye_col='#3a2a1e')
    # helmet shell sits back over the head; the face shows through a tinted visor
    sphere('Helmet', 0.33, suit, p, (0, 0.17, 1.01), scale=(1.0, 1.0, 1.02))
    sphere('Visor', 0.3, mat('visor_tint', C('#bfe8ff'), 0.02, 0.0, 1.0, None, 0.0, 0.0, 0.16), p,
           (0, -0.03, 0.99), scale=(0.95, 0.95, 0.9))
    torus('VisorRim', 0.29, 0.024, DARK, p, (0, -0.1, 0.99), rot=(math.pi / 2, 0, 0), scale=(1.0, 0.93, 1.0))
    box('HelmetTop', (0.18, 0.12, 0.05), pad, p, (0, 0.05, 1.34), r=0.02)
    for s in (-1, 1):
        cyl('Vent', 0.04, 0.04, 0.03, DARK, p, (0.32 * s, 0.05, 1.03), rot=(0, math.pi / 2, 0), bev=0.006)
    cyl('Light', 0.03, 0.03, 0.04, glow('#ffe066', 8), p, (0.18, 0.02, 1.3), rot=(0, 0, 0.5), bev=0)
    # big padded suit: chest plate, collar ring, padded limbs
    torus('Collar', 0.2, 0.06, pad, p, (0, 0, 0.74))
    box('Torso', (0.44, 0.34, 0.36), suit, p, (0, 0, 0.53), r=0.13)
    box('ChestPlate', (0.3, 0.04, 0.22), pad, p, (0, -0.17, 0.56), r=0.05)
    box('Badge', (0.09, 0.015, 0.09), plastic('#ffcc1a'), p, (0, -0.193, 0.58), rot=(0, math.pi / 4, 0), r=0.01)
    sphere('BadgeBomb', 0.022, mat('badge_bomb', C('#15161b'), 0.3), p, (0, -0.2, 0.578))
    for s in (-1, 1):
        sphere('Shoulder', 0.11, pad, p, (0.25 * s, 0, 0.66), scale=(1, 1, 0.9))
        cyl('Arm', 0.075, 0.07, 0.2, suit, p, (0.29 * s, -0.02, 0.5), bev=0.03)
        sphere('Mitt', 0.08, mat('mitt', C('#2f2f33'), 0.6), p, (0.3 * s, -0.05, 0.37))
        cyl('LegPad', 0.09, 0.085, 0.18, suit, p, (0.1 * s, 0, 0.24), bev=0.03)
        box('Boot', (0.17, 0.26, 0.12), mat('boot_c', C('#2a2a2e'), 0.5), p, (0.105 * s, -0.035, 0.07), r=0.05)
    box('Backpack', (0.3, 0.14, 0.3), pad, p, (0, 0.22, 0.56), r=0.06)
    cyl('Antenna', 0.008, 0.006, 0.3, GUNMETAL, p, (0.1, 0.25, 0.85), bev=0)
    sphere('AntennaTip', 0.02, glow('#ff4b3e', 10), p, (0.1, 0.25, 1.0))
    return p


BOMBRS = [
    ('bombr-a', 'A  Hard Hat', bombr_hardhat),
    ('bombr-b', 'B  Aviator', bombr_aviator),
    ('bombr-c', 'C  Blast Suit', bombr_blastsuit),
]


def main():
    reset()
    base_mats()
    studio()
    roots = []
    for key, label, fn in BOMBRS:
        roots.append((key, fn()))
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
        r.location = ((i - 1) * 1.3, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'bombr_concepts.blend'))


if __name__ == '__main__':
    main()
