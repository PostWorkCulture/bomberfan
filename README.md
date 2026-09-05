# Bomber Fan

Browser-based 3D bomber arena game.

## Play

https://postworkculture.github.io/bomberfan/

## Hosting

The game is hosted with GitHub Pages from the `main` branch. `index.html` is the game. The manifest, service worker, and icon files provide installable/offline PWA support for the hosted version.

## Character assets

The 20 animated fighters use the [Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) pack by Quaternius under CC0 1.0. Bomber Fan ships colour-enhanced texture variants, individually lit portraits, signature-move Loadout previews, five character-specific head-acting profiles, and a lazy-loaded animated glTF runtime. Full provenance is recorded in `assets/characters/LICENSE.txt`.

## Performance update (5 September 2026)

- One instance batch for destructible crates, with unchanged collision and drops.
- Shared explosion geometry and four reusable lights to keep shader light counts stable.
- Render only the visible scene and update the HUD only when its state changes.
- Adaptive resolution up to 1.5 DPR / two million pixels, with 1024-pixel arena shadows.
- Dispose bomb and character instance resources while retaining cached model geometry and textures.
- Pause a live round when the page is hidden and discard hidden-time catch-up.

## Regression checks

`node tests/simulation-regression.mjs` checks simulation and resource ownership using Node, the bundled Three.js and `@napi-rs/canvas`. It resolves the existing Codex runtime modules through `CODEX_PRIMARY_RUNTIME_NODE_MODULES` (or its standard installed path). `node tests/hud-regression.mjs` checks HUD update work with no extra dependencies. These checks do not measure browser layout, WebGL performance or device FPS.
