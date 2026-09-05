# Bomber Fan

Browser-based 3D bomber arena game.

## Play

https://postworkculture.github.io/bomberfan/

## Hosting

The game is hosted with GitHub Pages from the `main` branch. `index.html` is the game. The manifest, service worker, and icon files provide installable/offline PWA support for the hosted version.

## Character assets

The 20 animated fighters use the [Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) pack by Quaternius under CC0 1.0. Bomber Fan ships colour-enhanced texture variants, individually lit portraits, signature-move Loadout previews, five character-specific head-acting profiles, and a lazy-loaded animated glTF runtime. Full provenance is recorded in `assets/characters/LICENSE.txt`.

Abyss has narrowed luminous cyan eyes, heavy angled brows, a small fanged snarl, and teal/indigo shading with violet horn tips. His face follows the existing Head bone. The custom geometry is owned by each instance; all 43 joints and 14 source animations remain intact. Four batched facial meshes add 974 triangles, with no extra lights or animation-loop code.

## Performance update (5 September 2026)

- One instance batch for destructible crates, with unchanged collision and drops.
- Shared explosion geometry and four reusable lights to keep shader light counts stable.
- Render only the visible scene and update the HUD only when its state changes.
- Adaptive resolution up to 1.5 DPR / two million pixels, with 1024-pixel arena shadows.
- Dispose bomb and character instance resources while retaining cached model geometry and textures.
- Pause a live round when the page is hidden and discard hidden-time catch-up.

## Regression checks

`node tests/platform-regression.mjs` runs the simulation/resource suite twice across eight viewport, pixel-density and pointer profiles, including 4K, hybrid touchscreen laptops, tablets and phones. `node tests/simulation-regression.mjs` runs one detailed profile, `node tests/hud-regression.mjs` independently checks HUD update work, and `node tests/assets-regression.mjs` validates all fighter and runtime assets. The simulation harness uses Node, the bundled Three.js and `@napi-rs/canvas`, resolving runtime modules through `CODEX_PRIMARY_RUNTIME_NODE_MODULES` (or its standard installed path).

`tests/platform-harness.html` is the browser viewport harness for visual passes. Automated Node checks do not measure real WebGL FPS, browser-specific layout or physical-device input latency.

`node tests/abyss-regression.mjs` loads Abyss through the bundled glTF runtime, exercises all 14 animations, and verifies source preservation, clone isolation, geometry budgets and disposal. An optional second positional argument exports posed geometry for offline visual review; `--clip No --time 0.5` selects a pose. Offline model renders use studio lighting and do not substitute for a WebGL device check.
