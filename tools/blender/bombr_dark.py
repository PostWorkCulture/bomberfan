"""Bombr, round two: six darker, more detailed bomber characters (all original).

  1. Miasma      — plague-doctor bomber: beak mask with green-glowing lenses,
                   wide hat, long waxed coat, a bandolier of poison-flask bombs.
  2. Rattlefuse  — skeleton grenadier: grinning skull under a tricorne, a
                   tattered officer's coat and a live bomb glowing in his ribs.
  3. Blackdamp   — undead coal miner: gas mask with amber eyes and twin filters,
                   red head lamp, dynamite bandolier, a lantern in hand.
  4. Candlemass  — hooded wick-wraith: a cracked bomb for a head with a candle
                   burning on top, eyes glowing in the hood, chains, a blue lamp.
  5. Tick        — clockwork saboteur: cracked porcelain face, red monocle, top
                   hat, a clock-bomb ticking in his chest, detonator in hand.
  6. Fathom      — deep-sea mine diver: brass helmet with glowing portholes,
                   a spiked naval mine on his back, lead boots, chains.

Run inside Blender 5.x:
    blender --background --python tools/blender/bombr_dark.py -- <out-dir>
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
_bb = {'__name__': 'bomber_bots'}
exec(compile(open(os.path.join(HERE, 'bomber_bots.py'), encoding='utf-8').read(), 'bomber_bots.py', 'exec'), _bb)
globals().update({k: v for k, v in _bb.items() if not k.startswith('__') and k not in ('main', 'BOTS', 'OUT')})

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else os.path.join(os.getcwd(), 'bombr-dark')
os.makedirs(OUT, exist_ok=True)
PI = math.pi


# ---- extra helpers ------------------------------------------------------------------

def cone(name, r, h, material, parent, loc=(0, 0, 0), rot=(0, 0, 0), seg=24):
    return cyl(name, r, 0.002, h, material, parent, loc, rot, seg=seg, bev=0)


def ring_of(n, radius, z, fn, start=0.0, sweep=2 * PI, center=(0, 0)):
    for i in range(n):
        a = start + sweep * (i / n if sweep >= 2 * PI else i / max(1, n - 1))
        fn(i, center[0] + radius * math.cos(a), center[1] + radius * math.sin(a), z, a)


def bomb(p, at, r, shell=None, cap=None, ember='#ff7a1a', fuse=True):
    shell = shell or mat('bomb_iron', C('#121318'), 0.22, 0.35, 0.8)
    sphere('Bomb', r, shell, p, at)
    cyl('BombCap', r * 0.38, r * 0.44, r * 0.32, cap or BRASS, p, (at[0], at[1], at[2] + r * 0.95), bev=0.004)
    if fuse:
        hose('BombFuse', [(at[0], at[1], at[2] + r * 1.05), (at[0] + r * 0.25, at[1], at[2] + r * 1.45),
                          (at[0] + r * 0.55, at[1] - r * 0.1, at[2] + r * 1.6)], r * 0.09, mat('fuse', C('#a8895a'), 0.9), p)
        sphere('BombSpark', r * 0.2, glow(ember, 14), p, (at[0] + r * 0.58, at[1] - r * 0.1, at[2] + r * 1.62))


def strap(name, a, b, width, thick, material, parent):
    """A flat strap from point a to point b."""
    a, b = Vector(a), Vector(b)
    mid = (a + b) / 2
    d = b - a
    ob = box(name, (width, thick, d.length), material, parent, mid, r=thick * 0.4, seg=2)
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = d.normalized().to_track_quat('Z', 'Y')
    return ob


def bone_hand(p, at, material, curl=0.4, s=1.0):
    sphere('Palm', 0.035 * s, material, p, at, scale=(1.1, 0.8, 1.0))
    for i in range(4):
        x = at[0] + (i - 1.5) * 0.017 * s
        cyl('Finger', 0.008 * s, 0.006 * s, 0.06 * s, material, p, (x, at[1] - 0.02 * s, at[2] - 0.045 * s), rot=(curl, 0, 0), bev=0)
    cyl('Thumb', 0.009 * s, 0.007 * s, 0.045 * s, material, p, (at[0] + 0.04 * s, at[1] - 0.015 * s, at[2] - 0.01 * s), rot=(0.3, 0.9, 0), bev=0)


def dark_studio():
    """Moodier lighting than the concept studio: darker cyclorama, a low warm
    key, coloured rim lights and a faint fill so the glows carry the read."""
    for m in bpy.data.materials:
        if m.name.startswith('cyc'):
            set_input(m.node_tree.nodes.get('Principled BSDF'), 'Base Color', (*C('#0e1014'), 1))
            set_input(m.node_tree.nodes.get('Principled BSDF'), 'Roughness', 0.45)
    for ob in bpy.context.scene.objects:
        if ob.type == 'LIGHT':
            ob.data.energy *= {'Key': 0.7, 'Rim': 1.2, 'Fill': 0.3, 'Top': 0.25}.get(ob.name, 1.0)

    def light(name, loc, energy, color, size=1.6, target=(0, 0, 0.7)):
        ld = bpy.data.lights.new(name, 'AREA')
        ld.energy = energy
        ld.color = color
        ld.size = size
        ob = bpy.data.objects.new(name, ld)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()

    light('RimWarm', (2.8, 2.2, 2.0), 520, (1.0, 0.55, 0.25))
    light('RimCool', (-2.6, 1.6, 1.4), 380, (0.35, 0.7, 1.0))
    bpy.context.scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.012, 0.013, 0.017, 1)


# ---- 1. Miasma, the plague-doctor bomber ---------------------------------------------

def miasma():
    p = root('Miasma')
    coat = mat('waxed_coat', C('#1c1a1d'), 0.38, 0.0, 0.6)
    coat_hi = mat('waxed_coat_hi', C('#2b272c'), 0.42, 0.0, 0.5)
    leather = mat('mask_leather', C('#7a6a52'), 0.5, 0.0, 0.3)
    brass = BRASS
    poison = glow('#7dff6a', 9)
    # long flared coat, split at the front, with a short shoulder cape
    cyl('Coat', 0.33, 0.17, 0.66, coat, p, (0, 0.02, 0.4), bev=0.02)
    box('CoatSplit', (0.04, 0.02, 0.5), mat('coat_lining', C('#3b0f16'), 0.6), p, (0, -0.29, 0.3), rot=(-0.38, 0, 0), r=0.01)
    cyl('Cape', 0.27, 0.13, 0.24, coat_hi, p, (0, 0.02, 0.7), bev=0.02)
    torus('Collar', 0.13, 0.04, coat_hi, p, (0, 0.0, 0.82), scale=(1, 1, 1.4))
    for i in range(5):
        sphere('CoatButton', 0.016, brass, p, (0.06, -0.205 - i * 0.012, 0.66 - i * 0.1))
    # boots peeking out
    for s in (-1, 1):
        box('Boot', (0.13, 0.22, 0.1), mat('boot_black', C('#0e0e10'), 0.35, 0, 0.6), p, (0.1 * s, -0.08, 0.05), r=0.045)
    # hood and the beaked mask
    sphere('Hood', 0.21, coat, p, (0, 0.02, 0.97), scale=(1.0, 1.05, 1.08))
    sphere('Mask', 0.18, leather, p, (0, -0.06, 0.96), scale=(0.95, 0.9, 1.0))
    cyl('Beak', 0.085, 0.006, 0.42, leather, p, (0, -0.33, 0.9), rot=(1.78, 0, 0), seg=28, bev=0)
    for k in range(4):
        torus('BeakStitch', 0.07 - k * 0.014, 0.005, mat('stitch', C('#3a2c1c'), 0.8), p,
              (0, -0.2 - k * 0.065, 0.925 - k * 0.012), rot=(1.78, 0, 0))
    for s in (-1, 1):
        torus('LensRim', 0.045, 0.013, brass, p, (0.075 * s, -0.205, 1.0), rot=(PI / 2 - 0.15, 0, 0))
        sphere('Lens', 0.04, poison, p, (0.075 * s, -0.2, 1.0), scale=(1, 0.35, 1))
        sphere('LensGlint', 0.008, glow('#ffffff', 6), p, (0.065 * s, -0.215, 1.015))
    # wide-brimmed hat
    cyl('Brim', 0.34, 0.34, 0.022, coat, p, (0, 0.02, 1.14), rot=(0.06, 0, 0), bev=0.008)
    cyl('Crown', 0.15, 0.17, 0.2, coat, p, (0, 0.03, 1.25), bev=0.015)
    torus('HatBand', 0.165, 0.014, mat('band', C('#3b0f16'), 0.5), p, (0, 0.03, 1.17))
    box('Buckle', (0.05, 0.02, 0.04), brass, p, (0, -0.135, 1.17), r=0.006)
    # bandolier of poison-flask bombs
    strap('Bandolier', (-0.18, -0.2, 0.78), (0.2, -0.22, 0.36), 0.05, 0.02, mat('strap', C('#3a2416'), 0.6), p)
    for i in range(4):
        t = (i + 0.5) / 4
        x, z = -0.18 + 0.38 * t, 0.78 - 0.42 * t
        sphere('Flask', 0.034, mat('flask_glass', C('#9dff8a'), 0.05, 0, 1.0, C('#5cff4a'), 3.0), p, (x, -0.245, z))
        cyl('Cork', 0.012, 0.014, 0.02, mat('cork', C('#8a6a44'), 0.9), p, (x, -0.245, z + 0.04), bev=0)
    # gloved arms; one hand holds a smoking flask bomb out front
    for s in (-1, 1):
        hose('Sleeve', [(0.22 * s, 0, 0.72), (0.31 * s, -0.04, 0.6), (0.33 * s, -0.1, 0.48)], 0.055, coat_hi, p)
        sphere('Glove', 0.058, mat('glove', C('#0e0e10'), 0.4, 0, 0.5), p, (0.33 * s, -0.12, 0.44))
    sphere('BigFlask', 0.09, mat('bigflask', C('#9dff8a'), 0.05, 0, 1.0, C('#3cff3a'), 4.0), p, (0.35, -0.2, 0.47))
    cyl('BigNeck', 0.03, 0.035, 0.07, mat('bigflask_neck', C('#cfe9c9'), 0.1, 0, 1.0), p, (0.35, -0.2, 0.57), bev=0)
    sphere('Smoke1', 0.05, mat('smoke', C('#9cc79a'), 0.9, 0, 0, C('#6ad46a'), 0.6, 0, 0.35), p, (0.37, -0.21, 0.66))
    sphere('Smoke2', 0.07, mat('smoke', C('#9cc79a'), 0.9, 0, 0, C('#6ad46a'), 0.6, 0, 0.35), p, (0.41, -0.2, 0.76))
    return p


# ---- 2. Rattlefuse, the skeleton grenadier -------------------------------------------

def rattlefuse():
    p = root('Rattlefuse')
    bone = mat('bone', C('#d9cfb4'), 0.55, 0.0, 0.2)
    bone_dark = mat('bone_dark', C('#9c907a'), 0.65)
    redcoat = mat('redcoat', C('#5e1616'), 0.6, 0.0, 0.2)
    gold = BRASS
    hollow = mat('hollow', C('#050404'), 0.9)
    # skull: cranium, cheekbones, sockets with red embers, nose, jaw with teeth
    sphere('Cranium', 0.2, bone, p, (0, 0.02, 1.02), scale=(1.0, 1.08, 1.0))
    sphere('Face', 0.16, bone, p, (0, -0.06, 0.95), scale=(1.0, 0.9, 0.95))
    for s in (-1, 1):
        sphere('Socket', 0.055, hollow, p, (0.07 * s, -0.175, 0.99), scale=(1.0, 0.5, 1.1))
        sphere('Ember', 0.018, glow('#ff3b2a', 14), p, (0.07 * s, -0.2, 0.985))
        sphere('Cheek', 0.04, bone, p, (0.1 * s, -0.15, 0.92), scale=(1.2, 0.8, 0.7))
    cone('NoseHole', 0.025, 0.05, hollow, p, (0, -0.205, 0.925), rot=(PI / 2, 0, 0), seg=3)
    box('Jaw', (0.2, 0.12, 0.07), bone, p, (0, -0.1, 0.84), r=0.03)
    for i in range(7):
        box('Tooth', (0.022, 0.012, 0.03), mat('tooth', C('#efe6cf'), 0.4), p, (-0.066 + i * 0.022, -0.2, 0.875), r=0.004)
    for i in range(4):
        box('Crack', (0.006, 0.005, 0.05), hollow, p, (0.11 + i * 0.012, -0.12 + i * 0.02, 1.12 - i * 0.03), rot=(0, 0.5 + i * 0.3, 0), r=0)
    # bicorne worn side to side, gold-edged
    felt = mat('felt', C('#141214'), 0.85)
    cyl('Bicorne', 0.27, 0.27, 0.07, felt, p, (0, 0.04, 1.16), rot=(PI / 2, 0, 0), bev=0.02)
    torus('BicorneTrim', 0.265, 0.012, gold, p, (0, 0.0, 1.16), rot=(PI / 2, 0, 0), arc=0.5, major=32, minor=8)
    sphere('BicorneCap', 0.19, felt, p, (0, 0.04, 1.12), scale=(1.0, 1.0, 0.55))
    sphere('Cockade', 0.04, mat('cockade', C('#a01818'), 0.6), p, (0.1, -0.02, 1.3), scale=(1, 0.4, 1))
    box('Plume', (0.03, 0.02, 0.14), mat('plume', C('#c81a1a'), 0.8), p, (0.12, 0.0, 1.38), rot=(0, 0.3, 0), r=0.012)
    # coat open over a rib cage with a live bomb inside
    cyl('Spine', 0.025, 0.025, 0.42, bone_dark, p, (0, 0.06, 0.52), bev=0)
    for i in range(5):
        torus('Rib', 0.14 - i * 0.008, 0.012, bone, p, (0, -0.01, 0.68 - i * 0.055), rot=(0.1, 0, 0), scale=(1.0, 0.75, 1.0))
    sphere('Sternum', 0.03, bone, p, (0, -0.12, 0.62), scale=(0.7, 0.5, 2.0))
    bomb(p, (0, -0.02, 0.55), 0.085, ember='#ff6a1a')
    sphere('BombGlow', 0.13, mat('heart_glow', C('#ff5a1a'), 0.9, 0, 0, C('#ff5a1a'), 2.5, 0, 0.18), p, (0, -0.02, 0.55))
    for s in (-1, 1):
        box('CoatSide', (0.12, 0.26, 0.5), redcoat, p, (0.15 * s, 0.03, 0.5), rot=(0, 0.08 * s, 0), r=0.04)
        box('Lapel', (0.05, 0.02, 0.24), mat('lapel', C('#b38a2e'), 0.5, 0.4), p, (0.11 * s, -0.11, 0.62), rot=(0, 0.2 * s, 0), r=0.01)
        for k in range(3):
            sphere('Button', 0.014, gold, p, (0.14 * s, -0.115, 0.56 - k * 0.07))
        # epaulette with fringe
        cyl('Epaulette', 0.08, 0.09, 0.03, gold, p, (0.22 * s, 0.0, 0.76), rot=(0, 0.35 * s, 0), bev=0.008)
        for k in range(7):
            a = PI * k / 6
            cyl('Fringe', 0.006, 0.006, 0.07, gold, p, (0.22 * s + 0.08 * math.cos(a) * s, 0.08 * math.sin(a) - 0.04, 0.72), bev=0)
        # torn coat tails
        box('CoatTail', (0.13, 0.04, 0.3), redcoat, p, (0.1 * s, 0.14, 0.28), rot=(0.2, 0, 0.1 * s), r=0.02)
        for k in range(3):
            cone('Tatter', 0.025, 0.06, redcoat, p, (0.1 * s - 0.045 + k * 0.045, 0.16, 0.11), rot=(PI, 0, 0), seg=4)
        # bone limbs and boots
        hose('UpperArm', [(0.23 * s, 0, 0.72), (0.28 * s, -0.04, 0.58), (0.3 * s, -0.08, 0.47)], 0.022, bone, p)
        cyl('Leg', 0.022, 0.02, 0.2, bone, p, (0.08 * s, 0.02, 0.27), bev=0)
        cyl('BootShaft', 0.065, 0.06, 0.16, mat('boot_black', C('#0e0e10'), 0.35, 0, 0.6), p, (0.09 * s, -0.01, 0.12), bev=0.01)
        box('BootFoot', (0.12, 0.2, 0.07), mat('boot_black', C('#0e0e10'), 0.35, 0, 0.6), p, (0.09 * s, -0.06, 0.035), r=0.03)
        torus('BootCuff', 0.07, 0.015, mat('boot_black', C('#0e0e10'), 0.35, 0, 0.6), p, (0.09 * s, -0.01, 0.2))
    bone_hand(p, (-0.3, -0.09, 0.44), bone)
    bone_hand(p, (0.3, -0.1, 0.44), bone, curl=0.9)
    bomb(p, (0.3, -0.18, 0.42), 0.06)
    return p


# ---- 3. Blackdamp, the undead miner --------------------------------------------------

def blackdamp():
    p = root('Blackdamp')
    soot = mat('soot_cloth', C('#26262a'), 0.85)
    soot_lt = mat('soot_cloth_lt', C('#3a3a40'), 0.85)
    rubber = mat('mask_rubber', C('#15161a'), 0.45, 0, 0.3)
    iron = GUNMETAL
    amber = glow('#ffb02e', 10)
    red = paint('#a0181a')
    # heavy coat and trousers
    box('Torso', (0.4, 0.3, 0.36), soot, p, (0, 0, 0.55), r=0.12)
    box('CoatSkirt', (0.42, 0.32, 0.16), soot_lt, p, (0, 0, 0.36), r=0.06)
    for s in (-1, 1):
        cyl('Leg', 0.07, 0.065, 0.2, soot, p, (0.1 * s, 0, 0.21), bev=0.02)
        box('Boot', (0.15, 0.25, 0.11), mat('boot_worn', C('#2b1d14'), 0.6), p, (0.1 * s, -0.04, 0.06), r=0.045)
        box('Patch', (0.07, 0.01, 0.07), mat('patch', C('#4a3a2a'), 0.9), p, (0.11 * s, -0.16, 0.42), rot=(0, 0.3 * s, 0), r=0.01)
    # dynamite bandolier across the chest
    strap('Bandolier', (-0.2, -0.17, 0.72), (0.2, -0.18, 0.38), 0.06, 0.02, mat('strap', C('#3a2416'), 0.6), p)
    for i in range(5):
        t = (i + 0.5) / 5
        x, z = -0.2 + 0.4 * t, 0.72 - 0.34 * t
        stick = cyl('Dynamite', 0.022, 0.022, 0.13, red, p, (x, -0.2, z), rot=(0, 0, 0), bev=0.004)
        stick.rotation_euler = (0, -0.7, 0)
        hose('Wick', [(x - 0.04, -0.2, z + 0.05), (x - 0.06, -0.21, z + 0.08)], 0.004, mat('fuse', C('#a8895a'), 0.9), p)
    sphere('LitWick', 0.012, glow('#ff8a2a', 14), p, (0.12, -0.215, 0.56))
    # helmet with red head lamp
    sphere('Helmet', 0.25, mat('helmet_iron', C('#2e3034'), 0.4, 0.6), p, (0, 0.02, 1.06), scale=(1.03, 1.08, 0.8))
    cyl('HelmetBrim', 0.27, 0.29, 0.025, mat('helmet_iron', C('#2e3034'), 0.4, 0.6), p, (0, 0.0, 1.01), bev=0.008)
    cyl('Lamp', 0.05, 0.055, 0.07, iron, p, (0, -0.24, 1.1), rot=(PI / 2 - 0.2, 0, 0), bev=0.008)
    cyl('LampLens', 0.04, 0.04, 0.012, glow('#ff2a1a', 12), p, (0, -0.275, 1.093), rot=(PI / 2 - 0.2, 0, 0), bev=0)
    # gas mask: face plate, two amber eyes, snout and twin filter canisters
    sphere('MaskFace', 0.2, rubber, p, (0, -0.04, 0.92), scale=(1.0, 0.95, 0.95))
    for s in (-1, 1):
        torus('EyeRim', 0.05, 0.014, iron, p, (0.075 * s, -0.215, 0.96), rot=(PI / 2 - 0.15, 0, 0))
        sphere('Eye', 0.045, amber, p, (0.075 * s, -0.205, 0.96), scale=(1, 0.35, 1))
        cyl('Filter', 0.045, 0.05, 0.09, mat('filter', C('#4a4a3a'), 0.6, 0.3), p, (0.11 * s, -0.22, 0.83), rot=(PI / 2 - 0.3, 0, -0.5 * s), bev=0.01)
        for k in range(3):
            torus('FilterRib', 0.048, 0.006, iron, p, (0.11 * s + 0.012 * s * (k - 1), -0.22 - 0.012 * (k - 1), 0.83), rot=(PI / 2 - 0.3, 0, -0.5 * s))
    cyl('Snout', 0.05, 0.06, 0.08, rubber, p, (0, -0.235, 0.84), rot=(PI / 2 - 0.25, 0, 0), bev=0.01)
    hose('AirHose', [(0, -0.27, 0.82), (0.05, -0.3, 0.7), (0.18, -0.1, 0.62), (0.2, 0.15, 0.62)], 0.022, rubber, p)
    for k in range(8):
        t = k / 7
        torus('HoseRib', 0.024, 0.004, iron, p, (0.03 + 0.17 * t, -0.28 + 0.4 * t, 0.76 - 0.14 * min(1, t * 1.5)))
    cyl('Tank', 0.09, 0.09, 0.36, iron, p, (0.0, 0.21, 0.58), bev=0.03)
    # arms; a lantern in the left hand
    for s in (-1, 1):
        hose('Arm', [(0.2 * s, 0, 0.7), (0.29 * s, -0.04, 0.58), (0.31 * s, -0.08, 0.46)], 0.055, soot_lt, p)
        sphere('Glove', 0.065, mat('glove_worn', C('#3a2a1e'), 0.7), p, (0.31 * s, -0.09, 0.42))
    cyl('LanternBase', 0.07, 0.07, 0.03, iron, p, (-0.32, -0.12, 0.23), bev=0.006)
    cyl('LanternGlass', 0.055, 0.055, 0.13, mat('lantern_glass', C('#ffd28a'), 0.05, 0, 0, C('#ffb347'), 5.0, 0, 0.9), p, (-0.32, -0.12, 0.31), bev=0)
    cone('LanternTop', 0.075, 0.06, iron, p, (-0.32, -0.12, 0.4))
    torus('LanternHandle', 0.05, 0.006, iron, p, (-0.32, -0.12, 0.42), rot=(PI / 2, 0, 0), arc=0.5)
    for k in range(4):
        a = k * PI / 2
        cyl('LanternBar', 0.005, 0.005, 0.13, iron, p, (-0.32 + 0.056 * math.cos(a), -0.12 + 0.056 * math.sin(a), 0.31), bev=0)
    return p


# ---- 4. Candlemass, the hooded wick-wraith ------------------------------------------

def candlemass():
    p = root('Candlemass')
    cloth = mat('wraith_cloth', C('#1c1424'), 0.8)
    cloth_in = mat('wraith_inner', C('#08060a'), 0.95)
    chain = mat('chain', C('#55585e'), 0.35, 0.9)
    wax = mat('wax', C('#efe6d2'), 0.45, 0, 0.3)
    # long cloak with a ragged hem
    cyl('Cloak', 0.3, 0.14, 0.82, cloth, p, (0, 0.03, 0.43), bev=0.02)
    ring_of(14, 0.27, 0.03, lambda i, x, y, z, a: cone('Rag', 0.05, 0.09 + 0.05 * (i % 3) / 2, cloth, p, (x, y + 0.03, z + 0.02), rot=(PI, 0, 0), seg=5))
    torus('ChainBelt', 0.22, 0.014, chain, p, (0, 0.02, 0.5), scale=(1.0, 0.85, 1.0))
    for k in range(10):
        a = 2 * PI * k / 10
        torus('Link', 0.018, 0.006, chain, p, (0.22 * math.cos(a), 0.02 + 0.187 * math.sin(a), 0.5), rot=(0, PI / 2 if k % 2 else 0, a))
    box('Padlock', (0.06, 0.03, 0.07), mat('lock_iron', C('#3a3d42'), 0.35, 0.8), p, (0.05, -0.19, 0.45), r=0.012)
    torus('Shackle', 0.022, 0.006, chain, p, (0.05, -0.19, 0.49), rot=(PI / 2, 0, 0), arc=0.5)
    # hood: an outer shell open at the front, dark inside
    sphere('Hood', 0.25, cloth, p, (0, 0.16, 0.99), scale=(1.0, 1.05, 1.12))
    torus('HoodRim', 0.2, 0.035, cloth, p, (0, -0.05, 0.97), rot=(PI / 2 - 0.15, 0, 0), scale=(0.95, 1.12, 1.0))
    sphere('HoodInside', 0.21, cloth_in, p, (0, 0.06, 0.97), scale=(0.95, 0.9, 1.0))
    cone('HoodPeak', 0.12, 0.22, cloth, p, (0, 0.24, 1.22), rot=(-0.7, 0, 0), seg=12)
    # the head: a cracked bomb with a burning candle stuck in the top
    sphere('BombHead', 0.15, mat('bomb_iron', C('#121318'), 0.22, 0.35, 0.8), p, (0, -0.07, 0.96))
    for i in range(5):
        a = -0.6 + i * 0.3
        box('Crack', (0.008, 0.006, 0.07), glow('#ff6a1a', 6), p, (0.12 * math.sin(a), -0.07 - 0.12 * math.cos(a) * 0.9, 1.0 - (i % 2) * 0.05),
            rot=(0, 0.4 * (i - 2), a), r=0)
    for s in (-1, 1):
        sphere('Eye', 0.03, glow('#bfe8ff', 14), p, (0.055 * s, -0.215, 0.98), scale=(1.4, 0.4, 0.6))
    cyl('Candle', 0.045, 0.045, 0.16, wax, p, (0.02, -0.08, 1.17), bev=0.006)
    for k in range(5):
        a = k * 1.3
        sphere('Drip', 0.016, wax, p, (0.02 + 0.045 * math.cos(a), -0.08 + 0.045 * math.sin(a), 1.13 - (k % 3) * 0.02), scale=(1, 1, 2.2))
    cyl('Wick', 0.004, 0.004, 0.03, mat('wick', C('#111111'), 0.9), p, (0.02, -0.08, 1.265), bev=0)
    sphere('Flame', 0.03, glow('#ffb347', 16), p, (0.02, -0.08, 1.305), scale=(0.8, 0.8, 1.7))
    sphere('FlameCore', 0.014, glow('#ffffff', 10), p, (0.02, -0.08, 1.29), scale=(0.8, 0.8, 1.5))
    # pale bony hands from long sleeves; a blue-flame lamp on a chain
    skin = mat('wraith_skin', C('#b9b6c4'), 0.6)
    for s in (-1, 1):
        hose('Sleeve', [(0.15 * s, 0.0, 0.76), (0.26 * s, -0.05, 0.64), (0.31 * s, -0.12, 0.53)], 0.065, cloth, p)
        cyl('Cuff', 0.08, 0.06, 0.08, cloth, p, (0.31 * s, -0.13, 0.52), rot=(0.5, 0.3 * s, 0), bev=0.01)
    bone_hand(p, (-0.31, -0.14, 0.47), skin, curl=0.6, s=1.2)
    bone_hand(p, (0.31, -0.14, 0.47), skin, curl=1.0, s=1.2)
    for k in range(5):
        torus('LampChain', 0.014, 0.005, chain, p, (0.31, -0.15, 0.42 - k * 0.025), rot=(0, PI / 2 if k % 2 else 0, 0))
    cyl('LampCage', 0.05, 0.045, 0.1, chain, p, (0.31, -0.15, 0.25), bev=0.006)
    sphere('BlueFlame', 0.035, glow('#4fb6ff', 14), p, (0.31, -0.15, 0.25), scale=(0.9, 0.9, 1.4))
    return p


# ---- 5. Tick, the clockwork saboteur -------------------------------------------------

def tick():
    p = root('Tick')
    porcelain = mat('porcelain', C('#ece6dc'), 0.2, 0, 1.0)
    black = mat('silk_black', C('#121114'), 0.4, 0, 0.6)
    plum = mat('waistcoat', C('#3a1530'), 0.6)
    shirt = mat('shirt', C('#d9d2c4'), 0.7)
    brass = BRASS
    copper = mat('copper', C('#b8683a'), 0.3, 1.0)
    crack = mat('crack', C('#1a1416'), 0.8)
    hollow = mat('eye_black', C('#08080a'), 0.2, 0, 1.0)
    HZ = 0.95   # head centre: low enough to sit on the neck

    # ---- neck: a brass column with gear rings, wrapped by a stiff collar and cravat
    cyl('NeckColumn', 0.05, 0.06, 0.16, copper, p, (0, 0.0, 0.79), bev=0.008)
    for z in (0.75, 0.81):
        cyl('NeckGear', 0.075, 0.075, 0.018, brass, p, (0, 0.0, z), bev=0.004)
        ring_of(10, 0.078, z, lambda i, x, y, zz, ang: box('Cog', (0.02, 0.02, 0.018), brass, p, (x, y, zz), rot=(0, 0, ang), r=0.003))
    for side in (-1, 1):
        box('WingCollar', (0.11, 0.025, 0.09), shirt, p, (0.07 * side, -0.07, 0.79), rot=(0.25, 0, -0.5 * side), r=0.012)
    sphere('CravatKnot', 0.035, mat('cravat', C('#6a1a1a'), 0.55, 0, 0.3), p, (0, -0.1, 0.77), scale=(1.2, 0.7, 0.9))
    for side in (-1, 1):
        box('CravatTail', (0.05, 0.015, 0.09), mat('cravat', C('#6a1a1a'), 0.55, 0, 0.3), p, (0.018 * side, -0.112, 0.71), rot=(0, 0.25 * side, 0), r=0.01)
    sphere('Pin', 0.012, glow('#ff2a2a', 6), p, (0, -0.125, 0.775))

    # ---- porcelain head, seated on the column, with a brass jaw hinge each side
    sphere('Head', 0.2, porcelain, p, (0, -0.01, HZ), scale=(0.95, 0.95, 1.05))
    cyl('HeadSocket', 0.07, 0.06, 0.05, brass, p, (0, 0.0, HZ - 0.19), bev=0.008)
    for side in (-1, 1):
        cyl('JawHinge', 0.03, 0.03, 0.03, brass, p, (0.185 * side, 0.0, HZ - 0.04), rot=(0, PI / 2, 0), bev=0.005)
        sphere('HingeScrew', 0.01, crack, p, (0.2 * side, 0.0, HZ - 0.04))
    for i, (x, z, r) in enumerate([(0.05, 0.1, 0.6), (0.08, 0.06, -0.3), (0.11, 0.01, 0.9), (0.04, 0.14, -0.5), (-0.12, 0.08, 0.4)]):
        box('Crack', (0.006, 0.006, 0.06), crack, p, (x, -0.185 + abs(x) * 0.25, HZ + z), rot=(0, r, 0), r=0)
    # a chip knocked out of the cheek, showing the gears behind
    sphere('Chip', 0.04, mat('chip_dark', C('#1e1410'), 0.6), p, (-0.12, -0.14, HZ - 0.03), scale=(1, 0.4, 0.8))
    cyl('ChipGear', 0.028, 0.028, 0.01, brass, p, (-0.12, -0.152, HZ - 0.03), rot=(PI / 2 - 0.4, 0, 0.6), bev=0)
    # eyes: one hollow with a red ember and a drip, one behind a red monocle
    sphere('EyeL', 0.038, hollow, p, (-0.065, -0.165, HZ + 0.03), scale=(1, 0.45, 1.3))
    sphere('EyeLEmber', 0.01, glow('#ff2a2a', 12), p, (-0.065, -0.185, HZ + 0.02))
    box('Tear', (0.012, 0.006, 0.07), hollow, p, (-0.07, -0.178, HZ - 0.03), r=0.004)
    torus('Monocle', 0.045, 0.01, brass, p, (0.07, -0.175, HZ + 0.03), rot=(PI / 2, 0, 0))
    sphere('MonocleGlow', 0.04, glow('#ff2a2a', 10), p, (0.07, -0.17, HZ + 0.03), scale=(1, 0.3, 1))
    hose('MonocleChain', [(0.11, -0.16, HZ + 0.02), (0.15, -0.13, HZ - 0.09), (0.11, -0.13, 0.74)], 0.004, brass, p)
    torus('Grin', 0.1, 0.012, crack, p, (0, -0.155, HZ - 0.05), rot=(PI / 2 - 0.2, PI, 0), arc=0.5, major=28, minor=8)
    for i in range(6):
        box('GrinTick', (0.005, 0.008, 0.035), crack, p, (-0.075 + i * 0.03, -0.17, HZ - 0.095 + abs(i - 2.5) * 0.008), r=0)

    # ---- top hat, tipped, with a gear on the band and a wind-up key through it
    cyl('HatBrim', 0.24, 0.24, 0.02, black, p, (0, -0.01, HZ + 0.19), rot=(0.08, 0, 0.08), bev=0.008)
    cyl('HatCrown', 0.15, 0.14, 0.3, black, p, (0.008, -0.005, HZ + 0.35), rot=(0.05, 0, 0.08), bev=0.015)
    torus('HatBand', 0.146, 0.018, mat('hatband', C('#6a1a1a'), 0.5), p, (0.002, -0.01, HZ + 0.23), rot=(0.05, 0, 0.08))
    cyl('HatGear', 0.05, 0.05, 0.015, brass, p, (0.1, -0.12, HZ + 0.24), rot=(PI / 2 - 0.4, 0, 0.6), bev=0.003)
    cyl('KeyShaft', 0.012, 0.012, 0.16, brass, p, (0.0, 0.17, HZ + 0.33), rot=(PI / 2, 0, 0), bev=0)
    for side in (-1, 1):
        torus('KeyLobe', 0.035, 0.01, brass, p, (0.035 * side, 0.26, HZ + 0.33), rot=(PI / 2, 0, 0))

    # ---- body: tail coat, plum waistcoat, a clock-bomb ticking in the chest
    box('Torso', (0.36, 0.26, 0.36), black, p, (0, 0.01, 0.56), r=0.1)
    box('Waistcoat', (0.24, 0.03, 0.3), plum, p, (0, -0.125, 0.55), r=0.04)
    for side in (-1, 1):
        box('Lapel', (0.06, 0.02, 0.2), black, p, (0.12 * side, -0.13, 0.63), rot=(0, 0.25 * side, 0), r=0.01)
        box('Tail', (0.1, 0.03, 0.34), black, p, (0.08 * side, 0.13, 0.32), rot=(0.25, 0, 0.08 * side), r=0.02)
        cyl('Epaulet', 0.07, 0.07, 0.02, brass, p, (0.19 * side, 0.0, 0.74), rot=(0, 0.3 * side, 0), bev=0.005)
    for k in range(3):
        sphere('VestButton', 0.012, brass, p, (0.0, -0.145, 0.44 - k * 0.04))
    cyl('ClockRim', 0.1, 0.1, 0.04, brass, p, (0, -0.15, 0.57), rot=(PI / 2, 0, 0), bev=0.008)
    cyl('ClockFace', 0.085, 0.085, 0.01, mat('clock_face', C('#f4ecd8'), 0.4), p, (0, -0.172, 0.57), rot=(PI / 2, 0, 0), bev=0)
    for i in range(12):
        ang = 2 * PI * i / 12
        box('Hour', (0.006, 0.004, 0.016 if i % 3 else 0.026), crack, p, (0.07 * math.sin(ang), -0.179, 0.57 + 0.07 * math.cos(ang)), rot=(0, ang, 0), r=0)
    box('HourHand', (0.008, 0.004, 0.045), crack, p, (0.012, -0.181, 0.59), rot=(0, 0.5, 0), r=0)
    box('MinuteHand', (0.006, 0.004, 0.065), mat('red_hand', C('#c81a1a'), 0.4), p, (-0.02, -0.182, 0.6), rot=(0, -0.6, 0), r=0)
    sphere('ClockCore', 0.05, glow('#ff3a1a', 4), p, (0, -0.13, 0.57), scale=(1, 0.4, 1))
    hose('WireRed', [(0.08, -0.15, 0.52), (0.16, -0.1, 0.44), (0.2, 0.05, 0.4)], 0.008, mat('wire_red', C('#c81a1a'), 0.4), p)
    hose('WireBlue', [(-0.08, -0.15, 0.53), (-0.17, -0.1, 0.46), (-0.2, 0.05, 0.42)], 0.008, mat('wire_blue', C('#1a4ac8'), 0.4), p)

    # ---- jointed brass limbs, white gloves, spats
    for side in (-1, 1):
        sphere('Shoulder', 0.05, brass, p, (0.21 * side, 0, 0.7))
        cyl('UpperArm', 0.03, 0.028, 0.14, copper, p, (0.24 * side, -0.01, 0.62), rot=(0, 0.25 * side, 0), bev=0.005)
        sphere('Elbow', 0.035, brass, p, (0.27 * side, -0.03, 0.54))
        cyl('Forearm', 0.028, 0.025, 0.12, copper, p, (0.28 * side, -0.06, 0.47), rot=(0.35, 0.1 * side, 0), bev=0.005)
        sphere('Hand', 0.042, mat('glove_white', C('#e8e4da'), 0.6), p, (0.29 * side, -0.09, 0.4))
        cyl('Leg', 0.03, 0.028, 0.24, copper, p, (0.08 * side, 0, 0.25), bev=0.005)
        sphere('Knee', 0.036, brass, p, (0.08 * side, -0.01, 0.25))
        box('Shoe', (0.11, 0.22, 0.07), black, p, (0.08 * side, -0.05, 0.035), r=0.03)
        box('Spat', (0.12, 0.13, 0.06), shirt, p, (0.08 * side, -0.02, 0.09), r=0.02)
    # detonator plunger in the right hand
    box('Detonator', (0.13, 0.1, 0.09), mat('det_wood', C('#5a3a20'), 0.6), p, (0.3, -0.14, 0.33), r=0.012)
    cyl('Plunger', 0.01, 0.01, 0.12, GUNMETAL, p, (0.3, -0.14, 0.42), bev=0)
    box('PlungerBar', (0.1, 0.02, 0.02), GUNMETAL, p, (0.3, -0.14, 0.48), r=0.006)
    return p


# ---- 6. Fathom, the deep-sea mine diver ----------------------------------------------

def fathom():
    p = root('Fathom')
    brass = mat('dive_brass', C('#b8873a'), 0.3, 1.0)
    brass_dark = mat('dive_brass_dark', C('#6a4a22'), 0.45, 1.0)
    canvas = mat('canvas', C('#3d4239'), 0.85)
    rust = mat('rust', C('#6a3418'), 0.9)
    iron = mat('mine_iron', C('#1c1f22'), 0.35, 0.7)
    chain = mat('chain', C('#55585e'), 0.35, 0.9)
    teal = glow('#3df2d0', 8)
    # bulky canvas suit, corselet, lead boots
    box('Suit', (0.44, 0.34, 0.4), canvas, p, (0, 0, 0.5), r=0.15)
    cyl('Corselet', 0.25, 0.2, 0.1, brass, p, (0, 0, 0.74), bev=0.02)
    ring_of(10, 0.235, 0.705, lambda i, x, y, z, a: sphere('Bolt', 0.016, brass_dark, p, (x, y, z)))
    for s in (-1, 1):
        cyl('Leg', 0.085, 0.08, 0.2, canvas, p, (0.11 * s, 0, 0.22), bev=0.03)
        box('LeadBoot', (0.17, 0.27, 0.13), brass_dark, p, (0.11 * s, -0.04, 0.065), r=0.04)
        box('BootStrap', (0.175, 0.04, 0.03), mat('strap', C('#3a2416'), 0.6), p, (0.11 * s, -0.04, 0.1), r=0.008)
        hose('Arm', [(0.24 * s, 0, 0.66), (0.31 * s, -0.04, 0.54), (0.32 * s, -0.08, 0.42)], 0.07, canvas, p)
        cyl('Cuff', 0.07, 0.07, 0.05, brass, p, (0.32 * s, -0.09, 0.4), rot=(0.3, 0, 0), bev=0.01)
        sphere('Mitt', 0.07, mat('mitt_rubber', C('#2a2a2c'), 0.6), p, (0.32 * s, -0.11, 0.35))
    for i in range(6):
        sphere('Barnacle', 0.018 + 0.006 * (i % 3), rust, p, (0.18 - i * 0.06, -0.165, 0.38 + (i % 2) * 0.05), scale=(1, 0.5, 1))
    # helmet: brass dome, glowing front porthole with a face shape inside, side ports
    sphere('Helmet', 0.26, brass, p, (0, 0.0, 1.0))
    cyl('FrontPortRim', 0.12, 0.12, 0.06, brass_dark, p, (0, -0.24, 0.98), rot=(PI / 2, 0, 0), bev=0.012)
    cyl('FrontGlass', 0.1, 0.1, 0.02, mat('port_glass', C('#3df2d0'), 0.05, 0, 1.0, C('#1fb89a'), 1.6), p, (0, -0.265, 0.98), rot=(PI / 2, 0, 0), bev=0)
    for s in (-1, 1):
        sphere('Eye', 0.022, glow('#eafffb', 12), p, (0.04 * s, -0.27, 0.99), scale=(1.3, 0.3, 0.8))
        cyl('SidePort', 0.07, 0.07, 0.05, brass_dark, p, (0.23 * s, -0.05, 1.0), rot=(0, PI / 2, 0), bev=0.01)
        cyl('SideGlass', 0.055, 0.055, 0.02, teal, p, (0.25 * s, -0.05, 1.0), rot=(0, PI / 2, 0), bev=0)
    for a in (0.0, PI / 2):
        cyl('Grille', 0.007, 0.007, 0.2, brass_dark, p, (0, -0.278, 0.98), rot=(0, a, 0), bev=0)
    cyl('TopValve', 0.04, 0.05, 0.06, brass_dark, p, (0, 0.0, 1.27), bev=0.008)
    hose('AirLine', [(0.0, 0.2, 1.1), (0.0, 0.32, 0.95), (0.0, 0.3, 0.75)], 0.025, mat('hose_rubber', C('#202022'), 0.6), p)
    # a spiked naval mine strapped on the back
    sphere('Mine', 0.2, iron, p, (0, 0.28, 0.6))
    for k in range(10):
        a = 2 * PI * k / 10
        z = 0.6 + (0.07 if k % 2 else -0.07)
        cone('Horn', 0.025, 0.09, iron, p, (0.225 * math.cos(a), 0.28 + 0.225 * math.sin(a), z),
             rot=(0, PI / 2, a), seg=10)
    for k in range(3):
        cone('TopHorn', 0.025, 0.09, iron, p, (0.08 * math.cos(k * 2.1), 0.28 + 0.08 * math.sin(k * 2.1), 0.8), seg=10)
    for k in range(4):
        sphere('RustSpot', 0.04, rust, p, (0.15 * math.cos(k * 1.7), 0.42, 0.55 + 0.08 * math.sin(k * 2.3)), scale=(1, 0.3, 1))
    sphere('MineLight', 0.025, glow('#ff2a1a', 12), p, (0.0, 0.47, 0.66))
    strap('MineStrapL', (-0.2, -0.12, 0.72), (-0.17, 0.2, 0.45), 0.04, 0.02, mat('strap', C('#3a2416'), 0.6), p)
    strap('MineStrapR', (0.2, -0.12, 0.72), (0.17, 0.2, 0.45), 0.04, 0.02, mat('strap', C('#3a2416'), 0.6), p)
    # chain from the right hand down to a small mine
    for k in range(6):
        torus('Link', 0.02, 0.007, chain, p, (0.34, -0.12, 0.3 - k * 0.032), rot=(0, PI / 2 if k % 2 else 0, 0))
    sphere('SmallMine', 0.07, iron, p, (0.34, -0.13, 0.07))
    for k in range(6):
        a = 2 * PI * k / 6
        cone('SmallHorn', 0.012, 0.04, iron, p, (0.34 + 0.085 * math.cos(a), -0.13 + 0.085 * math.sin(a), 0.07),
             rot=(0, PI / 2, a), seg=8)
    return p


CHARACTERS = [
    ('1-miasma', 'Miasma', miasma),
    ('2-rattlefuse', 'Rattlefuse', rattlefuse),
    ('3-blackdamp', 'Blackdamp', blackdamp),
    ('4-candlemass', 'Candlemass', candlemass),
    ('5-tick', 'Tick', tick),
    ('6-fathom', 'Fathom', fathom),
]


def build_all():
    reset()
    base_mats()
    studio()
    dark_studio()
    return [(key, fn()) for key, label, fn in CHARACTERS]


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
        r.location = ((i - 2.5) * 1.3, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'bombr_dark_concepts.blend'))


if __name__ == '__main__':
    main()
