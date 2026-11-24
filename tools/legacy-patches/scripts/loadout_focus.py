from pathlib import Path

p = Path('index.html')
s = p.read_text(encoding='utf-8')
marker = '/* BOMBER FAN LOADOUT FOCUS V4 */'
if marker in s:
    print('Loadout focus already applied')
    raise SystemExit(0)

css = r'''
  /* BOMBER FAN LOADOUT FOCUS V4 */
  /* Chromebook / desktop: make the operative the hero and stop utility labels fighting for space. */
  #select { overflow: hidden; }
  #select .shead { flex: 0 0 auto; min-height: 46px; }
  #select .sbody { width: min(1100px, 96vw); max-width: 1100px; margin-left: auto; margin-right: auto; }
  #select .sbody::after { display: none !important; }
  #select .slist::before { white-space: nowrap; }
  #select .sitem { min-width: 0; }
  #select .sitem .sname2 { min-width: 0; }
  #select .sitem .snote {
    max-width: 42%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    font-size: clamp(8px, .82vw, 11px); letter-spacing: .9px;
  }

  /* The preview must remain transparent because Three.js is rendered underneath it.
     Bright framing and a lighter renderer do the work instead of painting over the model. */
  #spreview {
    border: 2px solid rgba(255,205,139,.96) !important;
    box-shadow:
      0 0 0 1px rgba(255,128,28,.82),
      0 0 24px rgba(255,173,76,.72),
      0 0 68px rgba(255,104,13,.44),
      inset 0 0 34px rgba(255,196,119,.11),
      0 28px 60px rgba(0,0,0,.56) !important;
  }
  #spreview::before {
    color: #fff1d7 !important;
    background: rgba(28,20,13,.90) !important;
    border-color: rgba(255,186,96,.78) !important;
    box-shadow: 0 0 18px rgba(255,118,20,.24);
  }
  #spreview .sname {
    color: #fff5e7 !important;
    text-shadow: 0 2px 4px #000, 0 0 16px rgba(255,141,36,.52);
  }

  @media (min-width: 720px) and (min-height: 520px) {
    #select { padding-left: clamp(18px, 3vw, 42px); padding-right: clamp(18px, 3vw, 42px); }
    #select .sbody {
      flex-direction: row !important;
      align-items: center !important;
      justify-content: center !important;
      gap: clamp(28px, 5vw, 76px) !important;
      padding: 18px clamp(18px, 3vw, 36px) 24px !important;
    }
    #select .scol { flex: 0 0 auto; gap: clamp(12px, 1.8vw, 22px); }
    #spreview {
      width: clamp(220px, 28vh, 330px) !important;
      min-width: 220px;
      flex: 0 0 auto !important;
    }
    #select .slist {
      width: clamp(330px, 36vw, 500px) !important;
      max-width: 500px !important;
      max-height: min(58vh, 520px);
      flex: 0 1 500px !important;
      padding: 18px 14px 14px !important;
    }
    #select .slist::before { top: -10px; }
    #select .sitem {
      min-height: 31px;
      max-height: 48px;
      padding: clamp(5px, .7vh, 9px) 12px;
      font-size: clamp(11px, 1.08vw, 14px);
      gap: 8px;
    }
  }

  /* Common Chromebook landscape sizes: reduce decorative copy before it can collide. */
  @media (min-width: 900px) and (max-width: 1400px) {
    #select h2 { font-size: clamp(24px, 3vw, 34px) !important; letter-spacing: 5px !important; }
    #select .slist::before { font-size: 7px; letter-spacing: 1.35px; }
    #select .shead::before, #select .shead::after { max-width: 130px; }
  }

  @media (max-height: 620px) and (min-width: 720px) {
    #select .shead { min-height: 34px; }
    #select .sbody { padding-top: 8px !important; padding-bottom: 14px !important; gap: 22px !important; }
    #spreview { width: clamp(170px, 27vh, 230px) !important; min-width: 170px; }
    #select .slist { max-height: 54vh; }
    #select .sitem { min-height: 25px; padding-top: 4px; padding-bottom: 4px; }
  }
'''
if '</style>' not in s:
    raise RuntimeError('style closing tag not found')
s = s.replace('</style>', css + '\n</style>', 1)

# Brighten the actual Three.js preview. CSS backgrounds cannot be used because the renderer sits beneath the UI hole.
repls = {
    "scene.add(new THREE.HemisphereLight(0xdfefff, 0x30405a, 1.5));": "scene.add(new THREE.HemisphereLight(0xffead1, 0x46505f, 2.25));",
    "const key = new THREE.DirectionalLight(0xfff2d8, 2.1);": "const key = new THREE.DirectionalLight(0xffe3b5, 3.45);",
    "const rim = new THREE.DirectionalLight(0x9fd0ff, 1.1);": "const rim = new THREE.DirectionalLight(0xffa24b, 1.75);",
    "const edge = new THREE.DirectionalLight(0xffffff, 2.6);": "const edge = new THREE.DirectionalLight(0xffffff, 3.25);",
    "new THREE.MeshStandardMaterial({ color: 0x2b3550, roughness: 0.85 })": "new THREE.MeshStandardMaterial({ color: 0x59606a, roughness: 0.72, metalness: 0.18 })",
}
for old, new in repls.items():
    if old not in s:
        raise RuntimeError(f'preview lighting anchor not found: {old}')
    s = s.replace(old, new, 1)

p.write_text(s, encoding='utf-8')
print('Applied Chromebook Loadout layout and preview focus fix')
