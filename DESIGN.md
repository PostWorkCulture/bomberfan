# DESIGN.md — Bomber Fan

The design spec and the running record of every design change. Read with `CLAUDE.md`. Values below are taken from the browser build (`index.html`) unless marked as a Godot decision.

## Core loop

- Top-down 3D grid arena. Players drop bombs that explode in a cross; blasts destroy crates, reveal power-ups and eliminate players. Last fighter standing wins the round.
- Up to **4 players** (human + bots), spawning in the four corners.
- Match length: **1, 2 or 3 rounds to win** (first-to-5/7 deliberately removed — too long).
- Bot difficulty: **easy / normal / hard**.

## Arena

- Standard arena: **15×13 tiles** (13×11 interior + border walls), odd dimensions for symmetric corner spawns and a connected pillar lattice.
- Crate density: **70%** of free interior tiles. Power-up chance per crate: **~26%**.
- Spawns: (1,1), (13,11), (13,1), (1,11).

### Levels

| id | Name | Layout |
|---|---|---|
| forest | Forest | standard |
| beach | Beach | standard |
| glacier | Glacier | twin-islands |
| haunted | Haunted House | clockwork-maze |
| haunted-train | Haunted Train | haunted-train |
| factory | Factory | standard (belts) |
| circuit | Circuit | standard |
| pirate | Pirate Fleet | pirate-fleet |

Random picks from all levels. Adding a level = one new object in `LEVELS`.

Ice tile rule exists in code but is **intentionally unused** — bots can't plan while sliding, so it shipped off.

## Player tuning

| Stat | Value |
|---|---|
| Base speed | 3.9 tiles/s |
| Speed Up | +3.9 (doubles), cap 9.0, lasts 4 s (refreshes on pickup) |
| Starting bombs / max | 1 / 8 |
| Starting fire range | 2 tiles; each Fire Up +1 |
| Collision radius | 0.36 tiles |
| Turn snap | 2.8 (lane re-centring speed) |

## Power-ups

Bomb Up, Fire Up, Full Fire, Speed, Kick, Punch, Glove (pick up & throw), Remote detonator, Pierce (blast through crates), Bomb Pass, Block Pass, Shield (absorbs one hit), Mine (contact-triggered bombs), Skull (curse).

## Characters

- Animated fighters from Quaternius *Ultimate Monsters* (CC0) — colour-enhanced textures, lit portraits, signature-move Loadout previews. Provenance: `assets/characters/LICENSE.txt`.
- Additional procedural "reference" fighters in `assets/characters/reference-fighters.js`.
- All fighters standardised to a uniform walking height.
- Cosmetics/unlocks live in the Prize Locker ("armoury"); Loadout screen shows the character preview.

## Front end & platform

- Single-page browser game, installable PWA, offline-capable.
- Settings persisted in localStorage: audio, locker, controls.

## Godot rebuild

- Target: **Godot 4.7.2** (matches the local install), project in `godot/`, main scene `scenes/main.tscn`.
- Principle: port behaviour and tuning 1:1 from the browser build first; improvements come after parity and are logged here.
- Renderer: **GL Compatibility** (required for web, best for phones).
- Web build: single-threaded export (GitHub Pages can't send the headers threads need), published to **/play/** — https://postworkculture.github.io/bomberfan/play/
- Tuning lives in `godot/scripts/config.gd`, copied from `CFG`.
- Controls: WASD/arrows + Space (R restarts), gamepad d-pad/stick + A; on touchscreens a floating thumbstick (left half) and BOMB button (right half).
- Fighters are normalised to one height (1.25 tiles, larger than the browser build so they read on a phone).

### Vertical slice (2026-11-24) — what's in
Forest arena (15×13, 70% crates), you vs 3 bots (Ninja, Orc, Bunny, Dino), bombs with chain reactions, Bomb Up / Fire Up / Speed (temporary) at the browser drop rates, rounds to first-to-3, round intro/outro, HUD, keyboard + gamepad + touch.

Bots: Normal-tier port of the browser AI — danger map with chain timing, never bomb without a timed escape (escape slack 0.52 s, +0.35 s on the opening bomb), greed 0.34 / range 4, hunt 0.48, bomb gap 0.6 s.

### Look and sound (Godot)
- **All art is generated in code** (`godot/scripts/art.gd`): noise textures, meshes and shaders, with no image files. CI can then build and check it, and the web download stays small. Fighters are the only imported models.
- **Forest arena:** grass floor with a subtle checker and tile lines. Pillars are bevelled cut stone with patchy moss on top; moss is kept light so the pillars read as grey stone from the top-down camera, not as green blocks. The border is chunky mossy boulders. Crates are **log piles** (three crossed layers, bark plus end-grain rings), drawn as one multimesh.
- **Woods around the arena:** forest floor, ~46 pines, ~16 broadleaf trees, bushes, rocks, red toadstools, swaying grass tufts and fallen logs. All multimeshed (about 10 draw calls).
- **Lighting:** one warm low sun with soft shadows (no second light; the Compatibility renderer draws each light as an extra pass, which costs phones). Sky-lit ambient, Filmic tonemap, depth fog for the far woods. Glow is tight and high-threshold, so only real hot spots bloom.
- **Bombs:** matte black shell, metal cap, lit fuse with small sparks. The shell glows red as the fuse runs down, and the bomb squashes in when laid.
- **Explosions:** orange fireballs down every arm (mixed blend, so they never sum to white), a small hot flash, smoke, sparks, a brief orange light (at most 2 at once), scorch marks that fade after 7 s, and camera shake that grows with the bomber's bomb count. Crates burst into splinters and sawdust. Effect shaders are compiled during the first countdown, so the first blast doesn't hitch.
- **Music:** Arcade Drive during rounds (from `tools/render_music.py arcade_drive`).
- **Sound** is rendered by `tools/render_sfx.py`. Most sounds are a direct port of the browser build's WebAudio synth (same recipes, room reverb, high shelf and soft clipper). Sounds: bomb drop, explosion (3 variants), wood break, pick-up, death, countdown, GO, round and match win, the and a quiet wind bed (new in Godot). Master bus has a hard limiter.
- Local check: `godot/autotest.json` (git-ignored) runs a bots-only demo on the PC, saves screenshots and FPS/draw-call stats to `godot/.godot/autotest/`, then quits.

### Pick-ups (Godot)
Real items, not lettered tiles. Each floats and spins over a soft glow in its colour and pops up out of the rubble:
- **Bomb Up:** a mini bomb with a lit fuse (blue glow).
- **Fire Up:** a flickering flame with a yellow core and two side tongues (orange glow).
- **Speed Up:** a green sneaker with white feathered wings, spread so they read from above (green glow).

### Arena edge (Godot)
The arena stands on a raised stone base, one step (0.34) above the woods. A contact shadow runs along the inside of the rock wall, and the forest floor outside is darker and browner. Together these show clearly what's inside the rocks and what's outside.

### Sudden death
Ported from the browser build (`updateEndgame`, tuning in `config.gd`):
- Once the last crate is gone, "WALLS CLOSING IN" counts down 5 seconds.
- The same happens if the round clock runs out; time-up no longer ends a round as a draw.
- Then rings of rock drop in from the outside, one ring every 4 s and at most 4 rings. Blocks fall one at a time, 0.035 s apart.
- A falling block crushes anything on its tile: fighters, bombs and pick-ups.
- If nobody has won 20 s after the last ring, the round is a draw.
- Sounds: an ominous horn for the warning, an impact chord when it starts, and a stone slam for each block landing.

### Fighters
No coloured circles under fighters. The human player keeps the "YOU" tag.

### Not yet ported
Kick (and the other power-ups), the other 7 levels and their rules, character select / Loadout / Prize Locker, menus and options (difficulty, rounds, music volume), menu music, the rest of the roster.

---

## Change log

Newest first. One dated heading per day; bullets say what changed, why, and where.

### 2026-11-24 (night)
- **Fuse made subtle** (Pete: still too big and bright): no spark particles any more, just a tiny ember on the fuse tip, plus a faint red warning glow on the shell in the last stretch of the fuse.
- **Bomber-bot roster proposal** (`godot/scripts/robot.gd`): Bolt, Tank, Pip and Sparky, built and animated in code. It's off (`USE_BOTS = false` in `game.gd`) until Pete approves the designs. The autotest `"lineup"` mode shows them side by side.
- **Round music: Arcade Drive** (Pete's pick from four options). It's a 128 bpm four-on-the-floor beat with octave bass, a 16th-note arpeggio and a pad, in A minor. It's an 8-bar seamless loop (`godot/assets/audio/music_arcade_drive.wav`, with a loop point embedded so Godot loops it without a gap). It plays through the countdown and the round at −9 dB under the effects, fades out for the win sting, and replaces the forest bass pulse (`bass_forest.wav` removed). The wind bed is lowered to −11 dB to sit under it.
- Files: `godot/scripts/audio.gd`, `game.gd`; `tools/render_music.py` (loop chunk), `tools/render_sfx.py`.

### 2026-11-24 (late evening)
- **Pick-ups are now 3D items** (mini bomb, flame, winged sneaker), floating over coloured glows instead of lettered tiles.
- **Arena edge defined:** raised stone base, the woods one step lower, a contact shadow inside the wall, and a darker forest floor.
- **Sudden death / walls closing in** ported from the browser rules (see "Sudden death"). The time-up draw is replaced by sudden death.
- **Sound v2:** GO, countdown, explosions, and round and match win redesigned as richer stereo sounds (impact, metallic partials, debris crackle, wider room), because the browser versions sounded cheap. New: sudden-death warning, start and wall slam. Recipes are in `V2` in `tools/render_sfx.py`.
- Fuse spark and tip shine reduced by about half. Coloured circles under fighters removed.
- **Music options** rendered for Pete to choose from (`tools/render_music.py preview`): Dark Trap, Arcade Drive, Forest Stomp, Tension Pulse. In-round music stays the Forest bass pulse until one is picked.
- Files: `godot/scripts/art.gd`, `fx.gd`, `game.gd`, `fighter.gd`, `audio.gd`, `config.gd`; `godot/assets/audio/*`; `tools/render_sfx.py`, `tools/render_music.py`.

### 2026-11-24 (evening)
- **Godot art, effects and sound pass** for a fair comparison with the browser build. Forest look as described under "Look and sound": procedural textures, log-pile crates, stone pillars, boulder border, trees and props, sun and shadows, fog, glow. Explosions with fireballs, smoke, sparks, debris, scorch marks, flash light and camera shake. Bombs with a lit fuse and red warning glow. All sounds ported from the browser synth.
- Checked on the "bakes" PC (RTX 5060): no errors, ~800 fps, ~230 draw calls, ~310k primitives a frame. Tuned from screenshots: less moss, no white-out on explosions or bomb sparks (spark brightness capped, glow kept tight, sun removed from sky reflections).
- Files: `godot/scripts/art.gd`, `fx.gd`, `audio.gd`, `game.gd`; `godot/assets/audio/*.wav`; `tools/render_sfx.py`.

### 2026-11-24
- **Godot vertical slice added** (`godot/`): Forest arena, you vs 3 bots, bombs + chain blasts, Bomb/Fire/Speed pick-ups, first-to-3 rounds, touch + keyboard + gamepad. Tuning copied from `CFG`; bots ported from the Normal tier.
- Godot decisions: 4.7.2, GL Compatibility renderer, single-threaded web export to `/play/`.
- Fighters 1.25 tiles tall in Godot (up from the browser size) so they read on a phone. Lighting: sun 0.78, ambient 0.38, linear tonemap; camera 44° FOV, steep (~67°) angle.
- Added `.github/workflows/godot-build.yml`: installs Godot 4.7.2, imports, runs a headless bots-only smoke test (8 rounds), exports Web, records screenshots to the `ci-screenshots` branch, and on `main` publishes `play/`. First smoke run: 8 rounds, 7 decided, 5 self-kills in 23 deaths.
- Repo restructured to stop drift: added `CLAUDE.md` (working rules) and `DESIGN.md` (this file).
- Logo `Main Logo.png` → `assets/branding/main-logo.png`; `bf-icon.svg` → `assets/branding/`.
- PWA icons moved from root → `assets/icons/`; `index.html`, `manifest.webmanifest`, `sw.js` paths updated; service-worker cache bumped to `v3`.
- 27 unreferenced legacy portraits/sheets moved from `assets/` root → `archive/legacy-portraits/`.
- Six one-off GitHub Actions patch workflows (brand refresh, combat classes, character polish, loadout focus, locker refresh, visual polish) retired to `tools/legacy-patches/` so they can no longer rewrite `index.html` on push.
- Reserved `godot/` for the Godot rebuild.
- Daily scheduled upkeep of this log set up.

### 2026-09-24 (last browser-build change before this log)
- Standardised walking fighter height; darkened haunted gates (build `standard-arenas-review-20260924`).
