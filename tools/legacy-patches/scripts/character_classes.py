from pathlib import Path

p = Path('index.html')
s = p.read_text(encoding='utf-8')
marker = '/* BOMBER FAN COMBAT CLASSES V2 */'
if marker in s:
    print('Combat classes already applied')
    raise SystemExit(0)

if '/* BOMBER FAN COMBAT CHARACTER POLISH V1 */' not in s:
    raise RuntimeError('Combat trooper V1 must be present before class differentiation')

anchor = """    const helmRidge = new THREE.Mesh(new THREE.BoxGeometry(0.055, 0.23, 0.055), combatGunMat);
    helmRidge.position.set(0, HEAD_Y + 0.105, 0.055);
    helmRidge.rotation.x = -0.16;
    g.add(helmRidge);

    // Cheek flashes in the accent colour, so the face is not just eyes"""

insert = """    const helmRidge = new THREE.Mesh(new THREE.BoxGeometry(0.055, 0.23, 0.055), combatGunMat);
    helmRidge.position.set(0, HEAD_Y + 0.105, 0.055);
    helmRidge.rotation.x = -0.16;
    g.add(helmRidge);

    /* BOMBER FAN COMBAT CLASSES V2
       Four seat identities now have four unmistakable combat silhouettes.
       Visual only: no speed, radius, bomb count, collision or damage values change. */
    const combatClass =
      def.color === 0xff3b30 ? 'heavy' :
      def.color === 0x2f7bff ? 'reaper' :
      def.color === 0x33cc55 ? 'assault' : 'stealth';
    g.userData.combatClass = combatClass;

    if (combatClass === 'heavy') {
      // HEAVY — broadest silhouette, slab armour and reinforced jaw.
      [-1, 1].forEach(side => {
        const pauldron = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.18, 0.28), combatGunMat);
        pauldron.position.set(side * 0.43, BODY_Y + 0.16, -0.005);
        pauldron.rotation.z = side * -0.28;
        pauldron.castShadow = true;
        g.add(pauldron);
        const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.028, 0.11, 0.20), combatGlowMat);
        stripe.position.set(side * 0.55, BODY_Y + 0.17, 0.015);
        stripe.rotation.z = side * -0.28;
        g.add(stripe);
      });
      const jaw = new THREE.Mesh(new THREE.BoxGeometry(0.29, 0.09, 0.075), combatGunMat);
      jaw.position.set(0, HEAD_Y - 0.105, 0.225);
      g.add(jaw);
      const chestSlab = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.15, 0.055), combatBlackMat);
      chestSlab.position.set(0, BODY_Y + 0.07, 0.38);
      g.add(chestSlab);
    } else if (combatClass === 'reaper') {
      // REAPER — skull-mask cues, swept crown blades and colder, narrower silhouette.
      const skullMat = mat(0x69717b, { roughness: 0.46, metalness: 0.62 });
      const mask = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.17, 0.048), skullMat);
      mask.position.set(0, HEAD_Y - 0.015, 0.287);
      mask.scale.set(0.92, 1, 1);
      g.add(mask);
      [-1, 1].forEach(side => {
        const fang = new THREE.Mesh(new THREE.BoxGeometry(0.045, 0.10, 0.04), skullMat);
        fang.position.set(side * 0.07, HEAD_Y - 0.115, 0.284);
        fang.rotation.z = side * 0.16;
        g.add(fang);
        const horn = new THREE.Mesh(new THREE.ConeGeometry(0.045, 0.25, 5), combatGunMat);
        horn.position.set(side * 0.16, HEAD_Y + 0.27, -0.01);
        horn.rotation.z = side * -0.34;
        g.add(horn);
      });
      const spine = new THREE.Mesh(new THREE.BoxGeometry(0.055, 0.31, 0.10), combatBlackMat);
      spine.position.set(0, BODY_Y + 0.09, -0.29);
      spine.rotation.x = -0.08;
      g.add(spine);
    } else if (combatClass === 'assault') {
      // ASSAULT — tactical plates, antenna and readable equipment rails.
      [-1, 1].forEach(side => {
        const rail = new THREE.Mesh(new THREE.BoxGeometry(0.075, 0.22, 0.06), combatGlowMat);
        rail.position.set(side * 0.135, BODY_Y + 0.025, 0.405);
        g.add(rail);
      });
      const antenna = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.018, 0.31, 6), combatGunMat);
      antenna.position.set(0.19, HEAD_Y + 0.25, -0.02);
      antenna.rotation.z = -0.14;
      g.add(antenna);
      const beacon = new THREE.Mesh(new THREE.SphereGeometry(0.03, 8, 6), combatGlowMat);
      beacon.position.set(0.22, HEAD_Y + 0.405, -0.02);
      g.add(beacon);
      const chin = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.055, 0.06), combatGunMat);
      chin.position.set(0, HEAD_Y - 0.11, 0.24);
      g.add(chin);
    } else {
      // STEALTH — angular hood/fins and minimal exposed luminous area.
      const stealthMat = mat(0x030407, { roughness: 0.20, metalness: 0.70 });
      [-1, 1].forEach(side => {
        const hood = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.28, 0.16), stealthMat);
        hood.position.set(side * 0.19, HEAD_Y + 0.03, 0.02);
        hood.rotation.z = side * 0.24;
        hood.rotation.y = side * -0.12;
        g.add(hood);
        const blade = new THREE.Mesh(new THREE.ConeGeometry(0.038, 0.25, 4), stealthMat);
        blade.position.set(side * 0.39, BODY_Y + 0.20, -0.02);
        blade.rotation.z = side * -0.58;
        g.add(blade);
      });
      const browBlade = new THREE.Mesh(new THREE.BoxGeometry(0.31, 0.038, 0.055), stealthMat);
      browBlade.position.set(0, HEAD_Y + 0.105, 0.268);
      browBlade.rotation.x = -0.03;
      g.add(browBlade);
      const stealthCore = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.02, 0.022), combatGlowMat);
      stealthCore.position.set(0, BODY_Y + 0.04, 0.414);
      g.add(stealthCore);
    }

    // Cheek flashes in the accent colour, so the face is not just eyes"""

if anchor not in s:
    raise RuntimeError('combat class anchor not found')
s = s.replace(anchor, insert, 1)
p.write_text(s, encoding='utf-8')
print('Applied Bomber Fan four-class character differentiation')
