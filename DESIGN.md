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

- Target: **Godot 4**, project in `godot/`.
- Principle: port behaviour and tuning 1:1 from the browser build first; improvements come after parity and are logged here.
- Decisions so far: none recorded yet.

---

## Change log

Newest first. One dated heading per day; bullets say what changed, why, and where.

### 2026-11-24
- Repo restructured to stop drift: added `CLAUDE.md` (working rules) and `DESIGN.md` (this file).
- Logo `Main Logo.png` → `assets/branding/main-logo.png`; `bf-icon.svg` → `assets/branding/`.
- PWA icons moved from root → `assets/icons/`; `index.html`, `manifest.webmanifest`, `sw.js` paths updated; service-worker cache bumped to `v3`.
- 27 unreferenced legacy portraits/sheets moved from `assets/` root → `archive/legacy-portraits/`.
- Six one-off GitHub Actions patch workflows (brand refresh, combat classes, character polish, loadout focus, locker refresh, visual polish) retired to `tools/legacy-patches/` so they can no longer rewrite `index.html` on push.
- Reserved `godot/` for the Godot rebuild.
- Daily scheduled upkeep of this log set up.

### 2026-09-24 (last browser-build change before this log)
- Standardised walking fighter height; darkened haunted gates (build `standard-arenas-review-20260924`).
