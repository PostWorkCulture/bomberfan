from pathlib import Path
import re

p = Path('index.html')
s = p.read_text(encoding='utf-8')
marker = '/* BOMBER FAN COMBAT CHARACTER POLISH V1 */'
if marker in s:
    print('Character polish already applied')
    raise SystemExit(0)

# 1) Darken the existing body finish without changing geometry/collision.
needle = "    const bodyMat = mat(def.color, styled('body'));\n"
replacement = """    const bodyMat = mat(def.color, styled('body'));
    /* BOMBER FAN COMBAT CHARACTER POLISH V1
       Keep the seat colour, but drag the shell toward blackened gunmetal so
       the luminous trim does the identification instead of a toy-bright body. */
    if (bodyMat.color) bodyMat.color.lerp(new THREE.Color(0x080a0f), 0.68);
    bodyMat.roughness = Math.min(bodyMat.roughness ?? 0.5, 0.46);
    bodyMat.metalness = Math.max(bodyMat.metalness ?? 0.0, 0.36);
    const combatGunMat = mat(0x11151c, { roughness: 0.34, metalness: 0.72 });
    const combatBlackMat = mat(0x05070a, { roughness: 0.28, metalness: 0.58 });
    const combatGlowMat = mat(def.color, {
      roughness: 0.18, metalness: 0.42,
      emissive: def.color, emissiveIntensity: 0.72
    });
    const combatHotMat = mat(0xff4b18, {
      roughness: 0.2, metalness: 0.2,
      emissive: 0xff2600, emissiveIntensity: 1.8
    });
"""
if needle not in s:
    raise RuntimeError('body material anchor not found')
s = s.replace(needle, replacement, 1)

# 2) Armour overlays. These are children of the visual group only; no gameplay
# radius, tile position, collision or movement values are changed.
belly_anchor = """    belly.position.set(0, BODY_Y - 0.01, 0.2);
    g.add(belly);

    const HEAD_Y = 0.7, HEAD_R = 0.265;
"""
armour = """    belly.position.set(0, BODY_Y - 0.01, 0.2);
    g.add(belly);

    // --- Combat armour ------------------------------------------------------
    // A faceted chest plate over the original torso. The old rounded body stays
    // underneath so animation and silhouette remain familiar at game scale.
    const chestPlate = new THREE.Mesh(new THREE.BoxGeometry(0.43, 0.29, 0.105), combatGunMat);
    chestPlate.position.set(0, BODY_Y + 0.02, 0.31);
    chestPlate.rotation.x = -0.08;
    chestPlate.castShadow = true;
    g.add(chestPlate);

    const chestCore = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.035, 0.025), combatGlowMat);
    chestCore.position.set(0, BODY_Y + 0.05, 0.372);
    g.add(chestCore);

    // Shoulder armour widens the upper silhouette without moving the animated arms.
    [-1, 1].forEach(side => {
      const shoulder = new THREE.Mesh(new THREE.BoxGeometry(0.19, 0.13, 0.23), combatGunMat);
      shoulder.position.set(side * 0.405, BODY_Y + 0.13, 0.02);
      shoulder.rotation.z = side * -0.20;
      shoulder.rotation.y = side * 0.08;
      shoulder.castShadow = true;
      g.add(shoulder);

      const shoulderMark = new THREE.Mesh(new THREE.BoxGeometry(0.025, 0.065, 0.15), combatGlowMat);
      shoulderMark.position.set(side * 0.502, BODY_Y + 0.14, 0.035);
      shoulderMark.rotation.z = side * -0.20;
      g.add(shoulderMark);

      // Reinforced shin/boot armour: intentionally compact to keep feet readable.
      const shin = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.16, 0.19), combatBlackMat);
      shin.position.set(side * 0.19, 0.17, 0.045);
      shin.castShadow = true;
      g.add(shin);
    });

    const HEAD_Y = 0.7, HEAD_R = 0.265;
"""
if belly_anchor not in s:
    raise RuntimeError('belly/head anchor not found')
s = s.replace(belly_anchor, armour, 1)

# 3) Replace the friendly white cartoon eyes with a dark visor and hostile glow.
face_pattern = re.compile(
    r"    // --- Face -+\n"
    r"    const whiteMat = mat\(0xf8fbff, \{ roughness: 0\.25 \}\);\n"
    r"    const eyeMat = mat\(0x18202e, \{ roughness: 0\.2 \}\);\n"
    r"    \[-1, 1\]\.forEach\(side => \{.*?"
    r"    \}\);\n\n"
    r"    // Cheek flashes in the accent colour, so the face is not just eyes",
    re.S,
)
face_replacement = """    // --- Face: hostile combat visor ----------------------------------------
    // The old white eyes made the characters friendly mascots. A single smoked
    // visor with narrow emissive slits reads much darker from both arena and locker.
    const visor = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.135, 0.055), combatBlackMat);
    visor.position.set(0, HEAD_Y + 0.015, 0.248);
    visor.rotation.x = -0.035;
    g.add(visor);

    [-1, 1].forEach(side => {
      const eye = new THREE.Mesh(new THREE.BoxGeometry(0.105, 0.026, 0.018), combatHotMat);
      eye.position.set(side * 0.09, HEAD_Y + 0.022, 0.282);
      eye.rotation.z = side * -0.16;
      g.add(eye);
    });

    // Heavy brow and central helmet ridge make the face look armoured rather than cute.
    [-1, 1].forEach(side => {
      const brow = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.035, 0.055), combatGunMat);
      brow.position.set(side * 0.085, HEAD_Y + 0.095, 0.237);
      brow.rotation.z = side * 0.18;
      g.add(brow);
    });
    const helmRidge = new THREE.Mesh(new THREE.BoxGeometry(0.055, 0.23, 0.055), combatGunMat);
    helmRidge.position.set(0, HEAD_Y + 0.105, 0.055);
    helmRidge.rotation.x = -0.16;
    g.add(helmRidge);

    // Cheek flashes in the accent colour, so the face is not just eyes"""
s, n = face_pattern.subn(face_replacement, s, count=1)
if n != 1:
    raise RuntimeError(f'face block replacement failed ({n})')

# 4) Add a few battle-wear marks as geometry, avoiding texture downloads/assets.
head_anchor = """    head.castShadow = true;
    g.add(head);

    // --- Face: hostile combat visor"""
wear = """    head.castShadow = true;
    g.add(head);

    // Scorched slash marks: tiny raised strips so they catch light without textures.
    const scarMat = mat(0x020304, { roughness: 0.8, metalness: 0.05 });
    [-1, 1].forEach((side, i) => {
      const scar = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.12 - i * 0.02, 0.012), scarMat);
      scar.position.set(side * 0.17, HEAD_Y + 0.10 - i * 0.03, 0.225);
      scar.rotation.z = side * 0.48;
      g.add(scar);
    });

    // --- Face: hostile combat visor"""
if head_anchor not in s:
    raise RuntimeError('head face anchor not found')
s = s.replace(head_anchor, wear, 1)

p.write_text(s, encoding='utf-8')
print('Applied Bomber Fan combat character polish')
