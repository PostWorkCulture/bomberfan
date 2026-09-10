# All-arena lighting and fighter sizing, 10 September 2026

Pete approved the Forest look and requested the same effects across the rest of
the game, plus a further Bomberman reduction followed by 25% off every fighter.

## Changes

- Promote the approved Forest rendering integration into the main entry.
- Add profiles for Forest, Beach, Glacier, Haunted House, Haunted Train, Factory,
  Circuit and Pirate. Warm coastal sun, cool ice/moonlight and balanced industrial
  lighting preserve their distinct palettes. HDR reflection environments are
  prefiltered once per theme and cached; glow strength is restrained per map.
- All arenas use bevelled instanced walls/crates, tuned shadows, surface normals,
  roughness and optional HDR bloom/colour grading. Remove painted floor-grid lines;
  gameplay markers such as conveyors and teleport pads remain visible.
- Bake separate ambient visibility and reflected colour maps from the actual
  immutable wall instances. Rotating maze walls and destructibles are excluded.
  Each offset island/deck receives board-coordinate bake UVs independently of
  its diffuse UV tiling or menu-root rotation.
- Reuse the approved Forest textures and light settings. Retain Auto/Balanced/High
  behaviour, existing adaptive resolution and original Loadout/victory exposure.
- Reduce shared character scale by 25% on all axes. BomberOG receives an additional
  20%, making his final size 60% of the former version. Apply the same factor in
  movement, Loadout, victory, death and held-bomb height. Source artwork, skeletons,
  collision radius, movement speed and bomb timing are not edited.
- Add lighting resources to service-worker asset coverage.

## Verification

The eight-profile production simulation matrix passes twice (256 groups),
including assertions for normal/BomberOG scale in display, movement and death.
Additional checks exercise all eight lighting profiles through three map cycles,
bake selection, offset-deck coordinates under a rotated root, bevel geometry,
HDR render-target sizing and restoration after a failed draw. HUD, asset integrity,
module/HTML syntax and the retained Forest regression pass.

These Node checks do not execute WebGL shaders or measure actual device FPS.
Public browser checks and publication details are recorded in the build status.
The previous local-browser URL restrictions must not be bypassed.

## Reproduce the bake

1. `BF_EXPORT_LAYOUTS=assets/lighting/layouts.json node tests/simulation-regression.mjs`
2. `python3 tools/bake-arena-lighting.py`
3. `node tests/arena-lighting-regression.mjs`
4. `node tests/platform-regression.mjs`

The Python bake uses NumPy/Pillow. It is not a Blender/Cycles export.
