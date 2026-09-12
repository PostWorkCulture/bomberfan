# Bomber Fan

Browser-based 3D bomber arena game.

## Play

https://postworkculture.github.io/bomberfan/

## Hosting

The game is hosted with GitHub Pages from the `main` branch. `index.html` is the game. The manifest, service worker, and icon files provide installable/offline PWA support for the hosted version.

## Pirate tides and front screen (12 September 2026)

Haunted House now places its four former bottom-edge props behind the arena. Pirate Fleet keeps both full-size ships on a wider 21×13 grid with three nine-tile bridges. Red marked tiles warn for 1.8 seconds, collapse for three seconds, then return. Grounded fighters fall through gaps; airborne fighters fall on landing. Unsupported bombs and pickups are removed and bots avoid the gaps.

Pirate water uses animated physical-material waves, layered cyan ripples and caustic highlights inspired by the supplied reference. Balanced mode halves mesh subdivisions in both directions. The wider arena has rebuilt lighting maps and shadow coverage. GPU appearance and physical-device frame rates still require hardware verification.

The front screen keeps the original wordmark and adds ice shards, embers, arena colours, animated menu glints, a pulsing skull and a raised orange/red Start button. Keyboard focus and reduced-motion behaviour are supported. `menu-review.html` is a GPU-independent review generated from production markup, CSS and menu handlers with `node tools/build-menu-review.mjs`.

The current simulation matrix covers 24 groups across eight environment profiles, twice (384 group checks). These are simulated input/viewport profiles, not native OS browser or hardware runs. Water shader structure is checked by `node tests/pirate-water-regression.mjs`; actual GPU compilation is not covered by that test.

## Character assets

The 20 animated fighters use the [Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) pack by Quaternius under CC0 1.0. Bomber Fan ships colour-enhanced texture variants, individually lit portraits, signature-move Loadout previews, five character-specific head-acting profiles, and a lazy-loaded animated glTF runtime. Full provenance is recorded in `assets/characters/LICENSE.txt`.

Abyss has narrowed luminous cyan eyes, heavy angled brows, a small fanged snarl, and teal/indigo shading with violet horn tips. His face follows the existing Head bone. The custom geometry is owned by each instance; all 43 joints and 14 source animations remain intact. Four batched facial meshes add 974 triangles, with no extra lights or animation-loop code.

The other 18 monster fighters now have individual eye designs: glossy beads, coloured irises, oversized pupils, asymmetric lids, reptile slits and recessed embers. BomberOG and Abyss are excluded from this pass. Eye surfaces use one baked atlas and cached sphere geometry, with two extra meshes per fighter and no added lights or animation-loop work. Seventeen fighters add 144 triangles; Skullcrusher adds 880 because his source skull had empty sockets. The source models, textures and animation clips are unchanged. Rotcrown's misplaced forehead growth has been moved onto his cap.

The [roster review sheet](docs/roster-eyes-review.png) shows the actual posed geometry under offline studio lighting. Updated portraits accompany all 18 designs. The CPU renderer is a visual inspection tool, not a WebGL screenshot or device-performance benchmark.

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

`node tests/roster-eyes-regression.mjs` checks all 18 eye designs, the production bootstrap/atlas gate, 228 original clips at 684 pose samples, clone and material isolation, cached geometry/texture lifetime, source preservation and both excluded fighters. Pass `--export /tmp/roster-qa` to export geometry for `python3 tools/render-character.py /tmp/roster-qa --out /tmp/roster-renders`. The Python tools require NumPy and Pillow. `node tools/generate-eye-atlas.mjs` deterministically regenerates the eye atlas from the authored surface rules and `EYE_STYLES` definitions.

### All-level lighting and smaller fighters

The main game now uses the approved Forest lighting approach across all seven
arenas, with per-theme light/reflection palettes, map-specific permanent-wall
ambient bakes, bevelled instanced geometry and adaptive HDR effects. Fighter
sizes are reduced 25%; BomberOG receives an additional 20% reduction (40% total).
See `docs/arena-lighting-rollout.md` for implementation and verification limits.

The current playable roster contains 16 fighters. Winged Maw, Abyss, Thornz and Death Totem were retired at Pete's request on 10 September 2026.

## Arena and presentation update, 10 September 2026

Victory and Loadout cameras now frame the animated character, with a large preview and centred winner. The red/black countdown announces the level and fades out after 1. Kicked bombs detonate on fighter contact, using swept collision while retaining normal blast protection rules.

Glacier has four ice platforms with connecting bridges. Haunted House gains reapers and winged gargoyles; all active throwers face their landing targets through wind-up and release. Factory replaces its old perimeter props with two moving forklifts and two rotating cranes that take turns throwing warned bombs. Haunted Train is removed, leaving seven playable levels.

`node tests/showcase-framing-regression.mjs` checks actual character vertices across showcase poses and viewport ratios. These projection checks supplement the repeated platform matrix, not GPU rendering or real-device FPS measurements.
