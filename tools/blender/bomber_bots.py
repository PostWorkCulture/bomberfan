"""Bomber Fan — eight bomber-bot character concepts, modelled in Blender.

Run in a background Blender (5.x):
    blender --background --python tools/blender/bomber_bots.py -- <out_dir>

Builds every concept from scratch (subdivision surfaces, bevels, Principled
materials, emissive eyes), lights a small studio, renders each bot on its own
(3/4 front) and saves the .blend next to the renders. Bots face -Y, stand on
Z=0 and are about 1.1 units tall. Every bot is parented to an empty
"Bot_<name>" so it can be exported to glTF for Godot later.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else os.path.join(os.getcwd(), 'bots')
os.makedirs(OUT, exist_ok=True)


# ---- scene -------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = 1100
    sc.render.resolution_y = 1100
    sc.render.film_transparent = False
    try:
        sc.eevee.use_raytracing = True
        sc.eevee.taa_render_samples = 96
        sc.eevee.use_shadows = True
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = 'AgX'
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except Exception:
        pass
    world = bpy.data.worlds.new('Studio')
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.045, 0.05, 0.06, 1)
    bg.inputs['Strength'].default_value = 1.0
    return sc


def set_input(node, names, value):
    for n in names if isinstance(names, (list, tuple)) else [names]:
        if n in node.inputs:
            node.inputs[n].default_value = value
            return


_mats = {}


def mat(name, color, rough=0.35, metal=0.0, coat=0.0, emit=None, emit_strength=0.0, transmission=0.0, alpha=1.0):
    key = (name, tuple(round(c, 3) for c in color), rough, metal, coat, emit, emit_strength, transmission, alpha)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    set_input(b, 'Base Color', (*color, 1))
    set_input(b, 'Roughness', rough)
    set_input(b, 'Metallic', metal)
    set_input(b, ['Coat Weight', 'Clearcoat'], coat)
    set_input(b, ['Coat Roughness', 'Clearcoat Roughness'], 0.08)
    if emit is not None:
        set_input(b, ['Emission Color', 'Emission'], (*emit, 1))
        set_input(b, 'Emission Strength', emit_strength)
    if transmission:
        set_input(b, ['Transmission Weight', 'Transmission'], transmission)
        set_input(b, 'IOR', 1.45)
    if alpha < 1.0:
        set_input(b, 'Alpha', alpha)
        try:
            m.surface_render_method = 'BLENDED'
            m.use_transparency_overlap = True
        except Exception:
            m.blend_method = 'BLEND'
    _mats[key] = m
    return m


def stripes_mat(name, a, b, scale=9.0, rough=0.4):
    """Diagonal hazard stripes."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    set_input(bsdf, 'Roughness', rough)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'DIAGONAL'
    wave.inputs['Scale'].default_value = scale
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'CONSTANT'
    ramp.color_ramp.elements[0].color = (*a, 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (*b, 1)
    nt.links.new(tc.outputs['Object'], wave.inputs['Vector'])
    nt.links.new(wave.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    return m


# ---- modelling helpers ---------------------------------------------------------

def _obj(name, bm, material, parent, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material:
        me.materials.append(material)
    if parent:
        ob.parent = parent
    return ob


def place(ob, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    ob.location = loc
    ob.rotation_euler = Euler(rot)
    ob.scale = scale
    return ob


def subsurf(ob, levels=2):
    m = ob.modifiers.new('Subsurf', 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    return ob


def bevel(ob, width, segments=4):
    m = ob.modifiers.new('Bevel', 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.harden_normals = False
    return ob


def box(name, size, material, parent, loc=(0, 0, 0), rot=(0, 0, 0), r=0.04, seg=4):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    ob = _obj(name, bm, material, parent, smooth=True)
    if r > 0:
        bevel(ob, r, seg)
    return place(ob, loc, rot)


def squircle(name, size, material, parent, loc=(0, 0, 0), rot=(0, 0, 0), crease=0.55):
    """A soft rounded cube: subdivided cube with edge creases (toy-like)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    ob = _obj(name, bm, material, parent)
    me = ob.data
    if hasattr(me, 'edges') and 'crease_edge' not in me.attributes:
        try:
            attr = me.attributes.new('crease_edge', 'FLOAT', 'EDGE')
            attr.data.foreach_set('value', [crease] * len(me.edges))
        except Exception:
            pass
    subsurf(ob, 3)
    return place(ob, loc, rot)


def sphere(name, r, material, parent, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), seg=40, rings=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    ob = _obj(name, bm, material, parent)
    return place(ob, loc, rot, scale)


def cyl(name, r1, r2, h, material, parent, loc=(0, 0, 0), rot=(0, 0, 0), seg=40, bev=0.01, caps=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=h)
    ob = _obj(name, bm, material, parent)
    if bev > 0:
        bevel(ob, bev, 3)
    return place(ob, loc, rot)


def torus(name, R, r, material, parent, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), major=48, minor=16, arc=1.0):
    """Built with bmesh rather than an operator, so it needs no UI context.
    `arc` < 1 makes an open bend (a headband, a smile) starting at +X."""
    bm = bmesh.new()
    rings = []
    closed = arc >= 1.0
    n = major if closed else major + 1
    for i in range(n):
        a = 2 * math.pi * arc * i / major
        ring = []
        for j in range(minor):
            b = 2 * math.pi * j / minor
            d = R + r * math.cos(b)
            ring.append(bm.verts.new((d * math.cos(a), d * math.sin(a), r * math.sin(b))))
        rings.append(ring)
    for i in range(major if closed else major):
        for j in range(minor):
            a0, a1 = rings[i], rings[(i + 1) % n]
            bm.faces.new((a0[j], a1[j], a1[(j + 1) % minor], a0[(j + 1) % minor]))
    if not closed:
        for ring in (rings[0], rings[-1]):
            bm.faces.new(ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = _obj(name, bm, material, parent)
    return place(ob, loc, rot, scale)


def hose(name, points, radius, material, parent, res=24):
    """A rubber-hose limb: a smooth bezier tube through the given points."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = radius
    cu.bevel_resolution = 6
    cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = Vector(p)
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    cu.materials.append(material)
    ob.parent = parent
    return ob


def root(name):
    e = bpy.data.objects.new('Bot_' + name, None)
    bpy.context.scene.collection.objects.link(e)
    return e


def mirror(fn):
    for s in (-1, 1):
        fn(s)


# ---- palette -------------------------------------------------------------------

def C(hexstr):
    h = hexstr.lstrip('#')
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


DARK = None
GUNMETAL = None
RUBBER = None
CHROME = None
WHITE = None
BRASS = None
SCREEN = None


def base_mats():
    global DARK, GUNMETAL, RUBBER, CHROME, WHITE, BRASS, SCREEN
    DARK = mat('dark', C('#1c1f26'), 0.35, 0.6)
    GUNMETAL = mat('gunmetal', C('#3a4150'), 0.3, 0.85)
    RUBBER = mat('rubber', C('#202226'), 0.75)
    CHROME = mat('chrome', C('#d7dbe2'), 0.12, 1.0)
    WHITE = mat('white_plastic', C('#f2f2ee'), 0.3, 0.0, 0.6)
    BRASS = mat('brass', C('#d6a24a'), 0.25, 1.0)
    SCREEN = mat('screen_glass', C('#05080c'), 0.05, 0.0, 1.0)


def plastic(hexc, name=None):
    return mat(name or 'plastic_' + hexc, C(hexc), 0.32, 0.0, 0.7)


def paint(hexc, name=None):
    return mat(name or 'paint_' + hexc, C(hexc), 0.3, 0.45, 0.5)


def glow(hexc, strength=8.0):
    c = C(hexc)
    return mat('glow_' + hexc, c, 0.4, 0.0, 0.0, c, strength)


def bomb_on_back(p, at, r=0.13):
    body = mat('bomb_black', C('#0b0c10'), 0.18, 0.2, 1.0)
    sphere('Bomb', r, body, p, at)
    cyl('BombCap', r * 0.42, r * 0.46, r * 0.35, BRASS, p, (at[0], at[1], at[2] + r * 0.98))
    hose('Fuse', [(at[0], at[1], at[2] + r * 1.1), (at[0] + 0.04, at[1] + 0.02, at[2] + r * 1.55),
                  (at[0] + 0.1, at[1] + 0.01, at[2] + r * 1.75)], 0.012, mat('fuse', C('#b99a6a'), 0.9), p)
    sphere('Ember', 0.018, glow('#ff8a2a', 12), p, (at[0] + 0.1, at[1] + 0.01, at[2] + r * 1.78))


# ---- the eight bots ------------------------------------------------------------------

def bot_sparky():
    p = root('Sparky')
    yellow = plastic('#ffc21a')
    trim = plastic('#2b2f3a')
    eye = glow('#7dfcff', 9)
    # CRT head
    box('Head', (0.64, 0.5, 0.48), yellow, p, (0, 0, 0.98), r=0.11)
    box('Bezel', (0.54, 0.06, 0.38), trim, p, (0, -0.24, 0.98), r=0.06)
    sphere('Screen', 0.3, SCREEN, p, (0, -0.205, 0.98), scale=(0.82, 0.16, 0.56))
    mirror(lambda s: sphere('Eye', 0.068, eye, p, (s * 0.105, -0.262, 1.03), scale=(0.75, 0.25, 1.1)))
    mirror(lambda s: sphere('EyeShine', 0.014, glow('#ffffff', 12), p, (s * 0.105 - 0.016, -0.28, 1.07)))
    torus('Smile', 0.075, 0.014, eye, p, (0, -0.264, 0.95), rot=(math.pi / 2, math.pi, 0), arc=0.5, major=24, minor=10)
    mirror(lambda s: sphere('Cheek', 0.024, glow('#ff7aa8', 3), p, (s * 0.17, -0.252, 0.95), scale=(1.2, 0.3, 0.7)))
    mirror(lambda s: cyl('Knob', 0.035, 0.035, 0.04, CHROME, p, (0.33 * s, -0.12, 0.88), rot=(0, math.pi / 2, 0)))
    # headphones
    torus('Band', 0.37, 0.028, trim, p, (0, 0.02, 0.98), rot=(math.pi / 2, 0, 0), arc=0.5)
    mirror(lambda s: cyl('Cup', 0.11, 0.11, 0.08, trim, p, (0.36 * s, 0.02, 0.98), rot=(0, math.pi / 2, 0), bev=0.025))
    mirror(lambda s: cyl('CupPad', 0.075, 0.075, 0.02, yellow, p, (0.405 * s, 0.02, 0.98), rot=(0, math.pi / 2, 0)))
    # antennae
    hose('AntennaL', [(-0.12, 0.05, 1.22), (-0.16, 0.06, 1.34), (-0.2, 0.08, 1.42)], 0.01, DARK, p)
    hose('AntennaR', [(0.12, 0.05, 1.22), (0.16, 0.06, 1.32), (0.22, 0.1, 1.38)], 0.01, DARK, p)
    sphere('TipL', 0.03, glow('#ff4b3e', 10), p, (-0.2, 0.08, 1.43))
    sphere('TipR', 0.025, yellow, p, (0.22, 0.1, 1.39))
    # body
    cyl('Neck', 0.06, 0.07, 0.08, DARK, p, (0, 0, 0.72))
    box('Body', (0.36, 0.26, 0.3), yellow, p, (0, 0, 0.55), r=0.08)
    box('ChestPanel', (0.22, 0.03, 0.14), trim, p, (0, -0.13, 0.57), r=0.025)
    for i, c in enumerate(['#ff5145', '#5cff8a', '#4fb6ff']):
        sphere('Btn%d' % i, 0.018, glow(c, 6), p, (-0.06 + i * 0.06, -0.15, 0.57))
    bomb_on_back(p, (0, 0.2, 0.6), 0.12)
    # rubber-hose limbs, white gloves, chunky shoes
    mirror(lambda s: hose('Arm', [(0.17 * s, 0, 0.64), (0.27 * s, -0.03, 0.55), (0.3 * s, -0.08, 0.42)], 0.03, trim, p))
    mirror(lambda s: sphere('Glove', 0.065, WHITE, p, (0.3 * s, -0.09, 0.38), scale=(1, 1.1, 0.9)))
    mirror(lambda s: sphere('Thumb', 0.028, WHITE, p, (0.25 * s, -0.12, 0.41)))
    mirror(lambda s: hose('Leg', [(0.09 * s, 0, 0.42), (0.1 * s, -0.01, 0.25), (0.11 * s, 0, 0.1)], 0.032, trim, p))
    mirror(lambda s: box('Shoe', (0.15, 0.24, 0.09), WHITE, p, (0.11 * s, -0.04, 0.05), r=0.04))
    mirror(lambda s: box('Sole', (0.155, 0.245, 0.03), RUBBER, p, (0.11 * s, -0.04, 0.012), r=0.012))
    return p


def bot_fuse():
    p = root('Fuse')
    red = plastic('#e8473c')
    body = mat('bomb_body', C('#101218'), 0.16, 0.25, 1.0)
    sphere('Body', 0.4, body, p, (0, 0, 0.66))
    torus('Band', 0.395, 0.03, red, p, (0, 0, 0.58))
    cyl('Cap', 0.13, 0.15, 0.12, BRASS, p, (0, 0, 1.07), bev=0.02)
    torus('CapRing', 0.15, 0.018, BRASS, p, (0, 0, 1.02))
    hose('Fuse', [(0, 0, 1.13), (0.04, 0.0, 1.25), (0.13, 0.03, 1.32), (0.2, 0.05, 1.3)], 0.025, mat('rope', C('#c9a46c'), 0.95), p)
    sphere('Ember', 0.04, glow('#ff7a1a', 14), p, (0.21, 0.05, 1.3))
    for s in (-1, 1):
        sphere('EyeWhite', 0.11, WHITE, p, (0.14 * s, -0.32, 0.78), scale=(1, 0.55, 1.2))
        sphere('Pupil', 0.05, mat('pupil', C('#07080b'), 0.1, 0, 1.0), p, (0.13 * s, -0.385, 0.76), scale=(1, 0.5, 1.15))
        sphere('Glint', 0.014, glow('#ffffff', 4), p, (0.11 * s, -0.405, 0.8))
        box('Brow', (0.17, 0.05, 0.045), red, p, (0.14 * s, -0.36, 0.93), rot=(0, 0.35 * s, 0), r=0.02)
    torus('Mouth', 0.07, 0.014, mat('mouth', C('#07080b'), 0.3), p, (0, -0.38, 0.6), rot=(math.pi / 2 - 0.25, 0, 0))
    for s in (-1, 1):
        cyl('Leg', 0.045, 0.05, 0.22, GUNMETAL, p, (0.15 * s, 0, 0.17))
        box('Boot', (0.17, 0.26, 0.11), red, p, (0.15 * s, -0.04, 0.06), r=0.045)
        hose('Arm', [(0.36 * s, 0, 0.7), (0.47 * s, -0.04, 0.6), (0.5 * s, -0.1, 0.5)], 0.03, GUNMETAL, p)
        sphere('Glove', 0.085, red, p, (0.5 * s, -0.11, 0.45), scale=(1, 1.05, 0.95))
        torus('Cuff', 0.06, 0.02, WHITE, p, (0.5 * s, -0.09, 0.52), rot=(0.3, 0, 0))
    return p


def bot_boomer():
    p = root('Boomer')
    orange = paint('#f2832a')
    hazard = stripes_mat('hazard', C('#ffcc1a'), C('#16171a'), 14)
    cyl('Drum', 0.32, 0.32, 0.56, orange, p, (0, 0, 0.62), bev=0.03)
    for z in (0.44, 0.8):
        torus('Rib', 0.322, 0.018, orange, p, (0, 0, z))
    cyl('Hazard', 0.326, 0.326, 0.1, hazard, p, (0, 0, 0.62), bev=0.0)
    cyl('Lid', 0.3, 0.26, 0.06, GUNMETAL, p, (0, 0, 0.93))
    sphere('Head', 0.17, DARK, p, (0, 0, 1.0), scale=(1, 1, 0.8))
    for s in (-1, 1):
        cyl('Lens', 0.05, 0.05, 0.06, CHROME, p, (0.065 * s, -0.15, 1.02), rot=(math.pi / 2, 0, 0))
        cyl('LensGlow', 0.035, 0.035, 0.01, glow('#3df2ff', 9), p, (0.065 * s, -0.18, 1.02), rot=(math.pi / 2, 0, 0), bev=0)
    hose('Whip', [(0.1, 0.06, 1.1), (0.14, 0.08, 1.3), (0.12, 0.12, 1.45)], 0.007, DARK, p)
    sphere('WhipTip', 0.022, glow('#ff4b3e', 10), p, (0.12, 0.12, 1.46))
    for s in (-1, 1):
        box('Shoulder', (0.2, 0.26, 0.16), orange, p, (0.4 * s, 0, 0.86), r=0.06)
        cyl('Piston', 0.05, 0.05, 0.28, CHROME, p, (0.43 * s, -0.02, 0.62), bev=0.008)
        cyl('Sleeve', 0.075, 0.075, 0.14, GUNMETAL, p, (0.43 * s, -0.02, 0.74))
        box('Wrist', (0.13, 0.13, 0.08), DARK, p, (0.43 * s, -0.03, 0.46), r=0.025)
        for k in (-1, 1):
            cyl('Claw', 0.02, 0.008, 0.14, CHROME, p, (0.43 * s + 0.035 * k, -0.06, 0.37), rot=(0.25, 0.3 * k, 0), bev=0)
        box('Tread', (0.18, 0.5, 0.22), RUBBER, p, (0.2 * s, -0.02, 0.12), r=0.09)
        for i in range(7):
            box('Lug', (0.19, 0.03, 0.02), RUBBER, p, (0.2 * s, -0.24 + i * 0.07, 0.235), r=0.006)
        for i in range(3):
            cyl('Hub', 0.065, 0.065, 0.02, orange, p, (0.2 * s + 0.095 * s, -0.17 + i * 0.15, 0.12), rot=(0, math.pi / 2, 0), bev=0.006)
    return p


def bot_volt():
    p = root('Volt')
    cyan = plastic('#1fc7e8')
    visor_glass = mat('visor', C('#04070c'), 0.04, 0.0, 1.0)
    sphere('Helmet', 0.27, WHITE, p, (0, 0, 1.0), scale=(0.92, 1.0, 1.05))
    sphere('Visor', 0.272, visor_glass, p, (0, -0.04, 0.98), scale=(0.92, 0.92, 0.62))
    mirror(lambda s: box('EyeLED', (0.075, 0.02, 0.045), glow('#5ff3ff', 10), p, (0.075 * s, -0.285, 1.0), rot=(0, 0, -0.18 * s), r=0.018))
    box('Fin', (0.035, 0.24, 0.1), cyan, p, (0, 0.04, 1.27), r=0.015)
    mirror(lambda s: cyl('EarPod', 0.06, 0.06, 0.05, cyan, p, (0.245 * s, 0, 1.0), rot=(0, math.pi / 2, 0), bev=0.015))
    cyl('Neck', 0.05, 0.06, 0.08, DARK, p, (0, 0, 0.76))
    sphere('Torso', 0.21, WHITE, p, (0, 0, 0.58), scale=(1.0, 0.8, 1.15))
    box('Stripe', (0.06, 0.34, 0.5), cyan, p, (0, 0, 0.58), r=0.025).scale = (1, 1, 1)
    sphere('Core', 0.04, glow('#5ff3ff', 10), p, (0, -0.17, 0.62), scale=(1, 0.5, 1))
    for s in (-1, 1):
        sphere('Shoulder', 0.07, cyan, p, (0.23 * s, 0, 0.7))
        cyl('UpperArm', 0.035, 0.035, 0.16, DARK, p, (0.25 * s, 0, 0.6), rot=(0, 0.15 * s, 0))
        cyl('Forearm', 0.05, 0.04, 0.16, cyan, p, (0.27 * s, -0.02, 0.46), rot=(0.1, 0.1 * s, 0), bev=0.012)
        sphere('Hand', 0.05, WHITE, p, (0.28 * s, -0.03, 0.37))
        cyl('Thigh', 0.045, 0.04, 0.16, DARK, p, (0.08 * s, 0, 0.32))
        cyl('Boot', 0.07, 0.09, 0.2, WHITE, p, (0.09 * s, -0.01, 0.13), bev=0.02)
        torus('BootRing', 0.075, 0.012, cyan, p, (0.09 * s, -0.01, 0.2))
        torus('Thruster', 0.06, 0.012, glow('#5ff3ff', 12), p, (0.09 * s, -0.01, 0.025))
    return p


def bot_rivet():
    p = root('Rivet')
    red = paint('#d33a2c')
    tin = mat('tin', C('#b8bec8'), 0.22, 0.95)
    box('Head', (0.48, 0.42, 0.4), tin, p, (0, 0, 1.0), r=0.03)
    for x in (-0.2, -0.07, 0.07, 0.2):
        for z in (0.83, 1.17):
            sphere('Rivet', 0.016, CHROME, p, (x, -0.212, z), seg=12, rings=8)
    for s in (-1, 1):
        torus('Porthole', 0.075, 0.018, BRASS, p, (0.11 * s, -0.21, 1.03), rot=(math.pi / 2, 0, 0))
        sphere('EyeGlass', 0.07, mat('eye_glass', C('#0c0f14'), 0.05, 0, 1.0), p, (0.11 * s, -0.2, 1.03), scale=(1, 0.35, 1))
        sphere('Pupil', 0.03, glow('#ffd23f', 10), p, (0.11 * s, -0.222, 1.03), scale=(1, 0.4, 1))
        cyl('Ear', 0.05, 0.06, 0.05, red, p, (0.26 * s, 0, 1.0), rot=(0, math.pi / 2, 0))
    for i in range(5):
        box('Grill', (0.022, 0.02, 0.07), DARK, p, (-0.08 + i * 0.04, -0.215, 0.89), r=0.006)
    pts = [(0.0, 0.0, 1.2 + k * 0.012) for k in range(1)]
    coil = [(0.03 * math.cos(t * 0.9), 0.03 * math.sin(t * 0.9), 1.2 + t * 0.012) for t in range(16)]
    hose('Spring', coil, 0.006, CHROME, p)
    sphere('Bulb', 0.04, glow('#ff4b3e', 10), p, (0, 0, 1.42))
    box('Body', (0.44, 0.32, 0.36), red, p, (0, 0, 0.6), r=0.03)
    box('Panel', (0.3, 0.03, 0.2), tin, p, (0, -0.165, 0.62), r=0.012)
    for i, x in enumerate((-0.08, 0.08)):
        cyl('Dial', 0.045, 0.045, 0.02, WHITE, p, (x, -0.185, 0.64), rot=(math.pi / 2, 0, 0), bev=0.005)
        box('Needle', (0.006, 0.006, 0.035), red, p, (x + 0.01, -0.197, 0.65), rot=(0, 0.6 - i, 0), r=0)
    cyl('KeyShaft', 0.02, 0.02, 0.12, BRASS, p, (0, 0.21, 0.62), rot=(math.pi / 2, 0, 0))
    mirror(lambda s: torus('KeyLobe', 0.06, 0.018, BRASS, p, (0.06 * s, 0.28, 0.62), rot=(math.pi / 2, 0, 0)))
    for s in (-1, 1):
        for k in range(5):
            torus('Accordion', 0.045, 0.016, tin, p, (0.27 * s + 0.012 * k * s, -0.01 * k, 0.68 - k * 0.045))
        box('Pincer', (0.09, 0.1, 0.06), red, p, (0.33 * s, -0.06, 0.43), r=0.02)
        box('Foot', (0.16, 0.26, 0.12), tin, p, (0.12 * s, -0.02, 0.07), r=0.025)
        cyl('Leg', 0.05, 0.05, 0.22, DARK, p, (0.12 * s, 0, 0.26))
        for k in (-1, 1):
            cyl('Wheel', 0.04, 0.04, 0.03, RUBBER, p, (0.12 * s + 0.09 * s, 0.09 * k, 0.04), rot=(0, math.pi / 2, 0))
    return p


def bot_pixel():
    p = root('Pixel')
    green = plastic('#4cd964')
    eye = glow('#f6fffb', 7)
    box('Head', (0.62, 0.54, 0.52), green, p, (0, 0, 0.9), r=0.16, seg=8)
    box('Screen', (0.48, 0.05, 0.34), SCREEN, p, (0, -0.255, 0.9), r=0.07, seg=6)
    for s in (-1, 1):
        box('Eye', (0.085, 0.02, 0.13), eye, p, (0.11 * s, -0.284, 0.93), r=0.035, seg=4)
        sphere('Blush', 0.028, glow('#ff7aa8', 3), p, (0.18 * s, -0.282, 0.83), scale=(1.3, 0.25, 0.6))
        cyl('Ear', 0.055, 0.055, 0.08, DARK, p, (0.33 * s, 0, 0.95), rot=(0, math.pi / 2, 0), bev=0.015)
        cyl('EarNub', 0.018, 0.012, 0.12, CHROME, p, (0.33 * s, 0, 1.06), bev=0)
        sphere('EarLight', 0.024, glow('#ffe15a', 8), p, (0.33 * s, 0, 1.13))
    torus('Mouth', 0.045, 0.011, eye, p, (0, -0.282, 0.83), rot=(math.pi / 2, math.pi, 0), arc=0.5, major=24, minor=10)
    box('Neck', (0.14, 0.12, 0.08), DARK, p, (0, 0, 0.62), r=0.03)
    box('Body', (0.32, 0.24, 0.26), DARK, p, (0, 0, 0.46), r=0.09, seg=6)
    box('Belly', (0.18, 0.02, 0.11), green, p, (0, -0.122, 0.46), r=0.03)
    sphere('BellyLight', 0.022, glow('#ffe15a', 6), p, (0, -0.135, 0.46))
    for s in (-1, 1):
        sphere('Hand', 0.065, green, p, (0.24 * s, -0.02, 0.42))
        cyl('Arm', 0.026, 0.026, 0.1, GUNMETAL, p, (0.18 * s, 0, 0.46), rot=(0, math.pi / 2, 0), bev=0)
        cyl('Leg', 0.035, 0.035, 0.16, GUNMETAL, p, (0.08 * s, 0, 0.25), bev=0)
        box('Foot', (0.17, 0.25, 0.12), green, p, (0.09 * s, -0.04, 0.07), r=0.05, seg=5)
    return p


def bot_mortar():
    p = root('Mortar')
    purple = paint('#8a5cf5')
    cyl('Turret', 0.34, 0.37, 0.3, purple, p, (0, 0, 0.5), bev=0.04)
    torus('Rim', 0.345, 0.025, GUNMETAL, p, (0, 0, 0.65))
    cyl('Skirt', 0.38, 0.4, 0.06, GUNMETAL, p, (0, 0, 0.36))
    cyl('Barrel', 0.13, 0.15, 0.36, purple, p, (0, 0.05, 0.82), rot=(-0.45, 0, 0), bev=0.02)
    cyl('Muzzle', 0.15, 0.15, 0.05, GUNMETAL, p, (0, -0.03, 0.98), rot=(-0.45, 0, 0), bev=0.01)
    cyl('Bore', 0.1, 0.1, 0.02, mat('bore', C('#020203'), 0.9), p, (0, -0.042, 1.005), rot=(-0.45, 0, 0), bev=0)
    hose('Stalk', [(0.2, -0.1, 0.62), (0.24, -0.14, 0.8), (0.22, -0.2, 0.92)], 0.022, GUNMETAL, p)
    sphere('Periscope', 0.075, purple, p, (0.22, -0.22, 0.95), scale=(1, 1.2, 1))
    cyl('Lens', 0.045, 0.045, 0.02, glow('#ff3b4f', 10), p, (0.22, -0.3, 0.95), rot=(math.pi / 2, 0, 0), bev=0)
    box('FacePlate', (0.36, 0.05, 0.12), GUNMETAL, p, (0, -0.33, 0.48), rot=(0.2, 0, 0), r=0.03)
    mirror(lambda s: sphere('Headlight', 0.035, glow('#fff2c2', 6), p, (0.11 * s, -0.36, 0.49)))
    for i, ang in enumerate([0.75, 2.39, 3.89, 5.53]):
        x, y = math.cos(ang), math.sin(ang)
        hip = (0.3 * x, 0.3 * y, 0.42)
        knee = (0.5 * x, 0.5 * y, 0.38)
        foot = (0.56 * x, 0.56 * y, 0.02)
        hose('Thigh%d' % i, [hip, ((hip[0] + knee[0]) / 2, (hip[1] + knee[1]) / 2, 0.47), knee], 0.035, GUNMETAL, p)
        sphere('Knee%d' % i, 0.05, purple, p, knee)
        hose('Shin%d' % i, [knee, (0.55 * x, 0.55 * y, 0.2), foot], 0.028, GUNMETAL, p)
        sphere('Toe%d' % i, 0.04, RUBBER, p, foot, scale=(1, 1, 0.6))
    return p


def bot_nova():
    p = root('Nova')
    orange = plastic('#ff8a00')
    glass = mat('bowl_glass', C('#dff2ff'), 0.02, 0.0, 1.0, None, 0.0, 0.0, 0.16)
    sphere('Bowl', 0.27, glass, p, (0, 0, 1.0))
    # a little round robot head floating inside the bowl
    sphere('InnerHead', 0.16, mat('inner_head', C('#2a2f3a'), 0.25, 0.6), p, (0, 0.0, 0.98), scale=(1.05, 1.0, 0.95))
    box('FaceBar', (0.22, 0.03, 0.09), mat('faceplate', C('#0b0d12'), 0.1, 0.2, 1.0), p, (0, -0.14, 0.99), r=0.035)
    mirror(lambda s: sphere('Eye', 0.026, glow('#7dfcff', 10), p, (0.055 * s, -0.158, 0.995), scale=(1, 0.5, 1.2)))
    cyl('Antenna', 0.01, 0.006, 0.12, GUNMETAL, p, (0.0, 0.0, 1.17), bev=0)
    sphere('AntennaTip', 0.022, glow('#ff9a2a', 9), p, (0, 0, 1.23))
    sphere('Core', 0.05, glow('#ff9a2a', 9), p, (0, -0.16, 0.66), scale=(1, 0.4, 1))
    torus('Collar', 0.22, 0.05, WHITE, p, (0, 0, 0.77))
    torus('CollarTrim', 0.25, 0.015, orange, p, (0, 0, 0.75))
    box('Torso', (0.42, 0.32, 0.36), WHITE, p, (0, 0, 0.56), r=0.12)
    cyl('Emblem', 0.06, 0.06, 0.02, orange, p, (0, -0.165, 0.6), rot=(math.pi / 2, 0, 0), bev=0.005)
    box('Pack', (0.34, 0.16, 0.36), WHITE, p, (0, 0.22, 0.6), r=0.06)
    for s in (-1, 1):
        cyl('Nozzle', 0.05, 0.075, 0.1, GUNMETAL, p, (0.09 * s, 0.25, 0.38), bev=0.01)
        cyl('Flame', 0.045, 0.0, 0.08, glow('#ffb45a', 8), p, (0.09 * s, 0.25, 0.3), rot=(math.pi, 0, 0), bev=0)
        sphere('Shoulder', 0.09, WHITE, p, (0.27 * s, 0, 0.68))
        torus('ShoulderRing', 0.075, 0.016, orange, p, (0.27 * s, 0, 0.62))
        cyl('Arm', 0.06, 0.055, 0.2, WHITE, p, (0.29 * s, -0.01, 0.5), bev=0.02)
        torus('Elbow', 0.058, 0.014, orange, p, (0.29 * s, -0.01, 0.42))
        sphere('Glove', 0.07, orange, p, (0.29 * s, -0.03, 0.35))
        cyl('LegTop', 0.08, 0.075, 0.14, WHITE, p, (0.11 * s, 0, 0.3), bev=0.02)
        torus('Knee', 0.07, 0.015, orange, p, (0.11 * s, 0, 0.22))
        box('Boot', (0.17, 0.25, 0.14), WHITE, p, (0.11 * s, -0.03, 0.08), r=0.05)
        box('BootSole', (0.175, 0.255, 0.035), orange, p, (0.11 * s, -0.03, 0.015), r=0.012)
    return p


BOTS = [
    ('1-sparky', 'Sparky Mk II', bot_sparky),
    ('2-fuse', 'Fuse', bot_fuse),
    ('3-boomer', 'Boomer', bot_boomer),
    ('4-volt', 'Volt', bot_volt),
    ('5-rivet', 'Rivet', bot_rivet),
    ('6-pixel', 'Pixel', bot_pixel),
    ('7-mortar', 'Mortar', bot_mortar),
    ('8-nova', 'Nova', bot_nova),
]


# ---- studio and renders ---------------------------------------------------------------

def studio():
    sc = bpy.context.scene
    # one seamless cyclorama: floor that bends up into the back wall, so
    # there is no horizon line behind the model
    cyc_m = mat('cyc', C('#3a404b'), 0.6)
    bm = bmesh.new()
    prof = [(-9.0, 0.0), (1.0, 0.0)]
    for i in range(1, 13):
        a = (math.pi / 2) * i / 12
        prof.append((1.0 + 3.0 * math.sin(a), 3.0 - 3.0 * math.cos(a)))
    prof.append((4.0, 10.0))
    rows = []
    for x in (-12.0, 12.0):
        rows.append([bm.verts.new((x, y, z)) for y, z in prof])
    for i in range(len(prof) - 1):
        bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    if bm.faces[0].normal.z < 0:   # floor must face up, the wall towards the camera
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    _obj('Cyclorama', bm, cyc_m, None)

    def light(name, kind, loc, energy, color, size=2.0, target=(0, 0, 0.6)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == 'AREA':
            ld.size = size
        ob = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(ob)
        ob.location = loc
        d = Vector(target) - Vector(loc)
        ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        return ob

    light('Key', 'AREA', (2.4, -3.0, 3.2), 900, (1.0, 0.95, 0.88), 2.5)
    light('Rim', 'AREA', (-2.6, 2.4, 2.8), 700, (0.65, 0.8, 1.0), 2.0)
    light('Fill', 'AREA', (-3.0, -2.2, 1.2), 220, (0.85, 0.9, 1.0), 3.0)
    light('Top', 'AREA', (0, 0, 4.5), 250, (1, 1, 1), 3.0)
    cam_d = bpy.data.cameras.new('Cam')
    cam_d.lens = 70
    cam = bpy.data.objects.new('Cam', cam_d)
    sc.collection.objects.link(cam)
    cam.location = (2.3, -4.2, 1.75)
    d = Vector((0, 0, 0.66)) - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam


def descendants(ob):
    out = [ob]
    for c in ob.children:
        out += descendants(c)
    return out


def main():
    reset()
    base_mats()
    studio()
    roots = []
    for key, label, fn in BOTS:
        r = fn()
        r['label'] = label
        roots.append((key, r))
    for key, r in roots:
        for _, other in roots:
            for ob in descendants(other):
                ob.hide_render = other is not r
        bpy.context.scene.render.filepath = os.path.join(OUT, key + '.png')
        bpy.ops.render.render(write_still=True)
    for _, other in roots:
        for ob in descendants(other):
            ob.hide_render = False
    # spread them out for browsing in the .blend
    for i, (_, r) in enumerate(roots):
        r.location = ((i - 3.5) * 1.3, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'bomber_bots_concepts.blend'))
    return [os.path.join(OUT, k + '.png') for k, _ in roots]


if __name__ == '__main__':
    main()
