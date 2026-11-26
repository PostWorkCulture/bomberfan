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
| haunted | Haunted House | clockwork-maze (witch hazard) |
| haunted-train | Haunted Train | haunted-train (three carriages) |
| factory | Factory | standard (conveyor belts) |
| circuit | Circuit | standard (teleport pads) |
| pirate | Pirate Fleet | pirate-fleet (4 cannon hazards) |

Glacier is twin-islands with 2 snowman hazards.

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
- Controls: WASD/arrows + Space (R restarts, L skips to the next arena), gamepad d-pad/stick + A (Back = next arena); on touchscreens a floating thumbstick (left half) and BOMB button (right half).
- Fighters are normalised to one height (1.45 tiles since the AAA review on 2026-11-25; was 1.25), larger than the browser build so they read on a phone. Every fighter has an outline and a rim light in its HUD colour: a dark outline on Forest and Beach, a light one on Haunted House and Factory. Fighters are the clearest thing on any floor. A knocked-out fighter flashes white and is tossed up spinning before landing.

### Vertical slice (2026-11-24) — what's in
Forest arena (15×13, 70% crates), you vs 3 bots (originally Ninja, Orc, Bunny, Dino; see Fighters for today's roster), bombs with chain reactions, Bomb Up / Fire Up / Speed (temporary) at the browser drop rates, rounds to first-to-3, round intro/outro, HUD, keyboard + gamepad + touch.

Bots: Normal-tier port of the browser AI — danger map with chain timing, never bomb without a timed escape (escape slack 0.52 s, +0.35 s on the opening bomb), greed 0.34 / range 4, hunt 0.48, bomb gap 0.6 s.

### Look and sound (Godot)
- **All art is generated in code** (`godot/scripts/art.gd`): noise textures, meshes and shaders, with no image files. CI can then build and check it, and the web download stays small. Fighters are the only imported models.
- **Forest arena:** grass floor with a subtle checker and tile lines. Pillars are bevelled cut stone with patchy moss on top; moss is kept light so the pillars read as grey stone from the top-down camera, not as green blocks. The border is chunky mossy boulders. Crates are **log piles** (three crossed layers, bark plus end-grain rings), drawn as one multimesh.
- **Woods around the arena:** forest floor, ~46 pines, ~16 broadleaf trees, bushes, rocks, red toadstools, swaying grass tufts and fallen logs. All multimeshed (about 10 draw calls).
- **Lighting:** one sun with soft shadows (no second light; the Compatibility renderer draws each light as an extra pass, which costs phones). Candles, furnaces and welding flashes are additive glow pools on the ground, not lights. Sky-lit ambient, Filmic tonemap, depth fog. Glow is tight and high-threshold, so only real hot spots bloom. Each arena has its own sun, sky, fog and grade (exposure, saturation, contrast, glow) in `level_art.gd` `THEMES`:
  - Forest: golden hour (warm low sun, cool sky in the shadows), sunlight dappling the grass.
  - Beach: high noon, slightly hazy; exposure held down so the sand doesn't blow out.
  - Haunted House: cold moonlight from behind, warm candle pools on the corners and sides, lightning every 8–15 s (two strobes and thunder).
  - Factory: cool strip light from almost straight above, warm furnace and work-lamp pools round the edges.
- **Colour order (all arenas):** floor quietest, walls next, crates stronger, fighters / bombs / hazards brightest. Hazard yellow-and-black and red are kept for danger (belts, crushers, warnings).
- **Contact shadow:** an occupancy map (one texel per tile, `game.gd` `occ_tex`) darkens the floor round every wall and crate and updates as crates break, move or appear.
- **Bombs:** matte black shell, metal cap, lit fuse with small sparks. The shell glows red as the fuse runs down, and the bomb squashes in when laid.
- **Explosions:** each lethal tile is a sheet of flame that fills the tile edge to edge, so an arm reads as one band. It's white-yellow in the middle and red at the rim, in mixed blend so it never sums to white, and holds full size for the whole lethal window. Teardrop flame tongues (5 per tile, one emitter per blast) rise down every arm and cool to grey within the lethal window. There's a shockwave ring, a small hot flash quad, grey smoke (none beside the outer wall), sparks, and scorch marks at 35% that fade after 3.5 s. **No flash light since AAA review round 3:** each omni light redraws everything near it on phones (this reverses "a brief orange light, at most 2 at once"; Pete to confirm). Flame sheets and scorches are instances of two pooled MultiMeshes, not nodes. Camera shake grows with the bomber's bomb count. Crates burst into splinters and sawdust. Effect shaders are compiled during the first countdown, so the first blast doesn't hitch.
- **Music (per arena, 2026-11-25):** Forest keeps Arcade Drive (Pete's pick); Beach *Tide Pop* (116 bpm tropical house, steel-pan hook); Haunted House *Graveyard Swing* (104 bpm spooky shuffle, celesta and walking bass); Factory *Tension Pulse* (100 bpm, one of the original four options). All from `tools/render_music.py <name>`.
- **Ambience beds per arena:** forest wind, beach surf, haunted moaning wind, factory hum and vents (`tools/render_sfx.py arena`).
- **Surroundings move:** birds cross the Forest, pollen drifts in the low sun; gulls circle the Beach and the water glints; bats flit round the Haunted House with will-o'-the-wisps in the graveyard; steam vents puff and a welding cell sparks in the Factory (`ambient.gd`, presentation only).
- **Arrival flyover:** a new arena opens with a 2.3 s camera swing from high and to the side down to the play camera, with the arena's name and a whoosh, before the countdown. Same-arena rounds skip it.
- **Knockouts:** a beat of slow motion (0.11 s at 12% speed) when someone is caught.
- **Crate breaks are themed:** bark and leaves (Forest), sand and driftwood (Beach), a spirit wisp from the casket (Haunted House), cardboard and sparks (Factory).
- **Sound** is rendered by `tools/render_sfx.py`. Most sounds are a direct port of the browser build's WebAudio synth (same recipes, room reverb, high shelf and soft clipper). Sounds: bomb drop, explosion (3 variants), wood break, pick-up, death, countdown, GO, round and match win, sudden-death warning/start/wall slam, and a quiet wind bed (new in Godot). Master bus has a hard limiter.
- Local check: `godot/autotest.json` (git-ignored) runs a bots-only demo on the PC, saves screenshots and FPS/draw-call stats to `godot/.godot/autotest/`, then quits.

### Pick-ups (Godot)
Real items, not lettered tiles. Each floats and spins over a soft glow in its colour and pops up out of the rubble:
- **Bomb Up:** a mini bomb with a lit fuse (blue glow).
- **Fire Up:** a flickering flame with a yellow core and two side tongues (orange glow).
- **Speed Up:** a green sneaker with white feathered wings, spread so they read from above (green glow).
- **Shield (Godot, 2026-11-25):** a violet heater shield (violet glow). Soaks one blast, then 1 s of grace (the fighter flickers) to get clear. Drops at 2.5% per crate. The holder wears a faint violet bubble. Crushing (sudden death, Factory crushers) ignores it. Bots want one when they have none.

### Arena edge (Godot)
The arena stands on a raised stone base, one step (0.34) above the woods. A contact shadow runs along the inside of the rock wall, and the forest floor outside is darker and browner. Together these show clearly what's inside the rocks and what's outside.

### Sudden death
Ported from the browser build (`updateEndgame`, tuning in `config.gd`):
- Once the last crate is gone, "WALLS CLOSING IN" counts down 5 seconds.
- The same happens if the round clock runs out; time-up no longer ends a round as a draw.
- Then rings of rock drop in from the outside, one ring every 4 s and at most 4 rings. Blocks fall one at a time, 0.035 s apart.
- A falling block crushes anything on its tile: fighters, bombs and pick-ups.
- If nobody has won 20 s after the last ring, the round is a draw.
- Bots treat tiles the walls are about to land on as danger, timed like a bomb blast (the same warning a human reads off the HUD), so they step off them in time. Bots do **not** hunt harder during sudden death: that was tried and reverted because it caused more draws, not fewer.
- Sounds: an ominous horn for the warning, an impact chord when it starts, and a stone slam for each block landing.

### Fighters
No coloured circles under fighters. The human player keeps the "YOU" tag.

**Godot roster (Pete, 2026-11-25): Razor, plus eight bots: Sparky Mk II, Rivet, Pixel, Boiler, Gumball, Snap, Arcade and Tick.**
- From the browser roster, only Razor (the ninja) and Bomberman are kept. The rest are dropped from the Godot build, and their models are removed from `godot/assets/characters` (the browser game still has them).
- Bomberman is held back. Pete wants it "seriously upgraded", but it is Konami's character, so the plan is an original bomber hero for that slot.
- New characters are concepts 1, 5 and 6 from the Blender set (`tools/blender/bomber_bots.py`, branch `art/bot-concepts`), exported as `sparky.glb`, `rivet.glb` and `pixel.glb`. They are rigid models; `godot/scripts/model_bot.gd` animates them in code (bob, waddle, lean, squash, hop-and-spin cheer, topple). The other five concepts are dropped.
- The first-pass code bots (`robot.gd`: Bolt, Tank, Pip, Sparky) were rejected and deleted.
- Round-2 bots (Pete picked 1, 3, 7 and 8 of eight: `tools/blender/bomber_bots_2.py`, branch `art/bot-concepts`): Boiler (copper steam boiler), Gumball (gumball machine), Snap (box camera) and Arcade (arcade cabinet), exported as `boiler/gumball/snap/arcade.glb` and animated by `model_bot.gd`. Dial, Crumb, Reel and Lumen are dropped.
- Slots: you are always Razor (blue). Each match the three bots are drawn at random from the eight. Every fighter has its own HUD colour: Sparky yellow, Rivet red, Pixel green, Boiler orange, Gumball pink, Snap white, Arcade purple, Tick teal. `-- --cast id,id,id` or autotest `"cast"` picks them by hand.
- Tick (Pete, 2026-11-25): the clockwork gentleman from the darker set (`tools/blender/bombr_dark.py`, Tick v2, branch `art/bot-concepts`), exported as `tick.glb` and animated by `model_bot.gd`. The other dark concepts are dropped.

### Arenas (Godot)
**Four arenas (Pete, 2026-11-25): Forest, Beach, Haunted House and Factory.** These are the ones to keep working on. Glacier, Haunted Train, Circuit and Pirate Fleet were ported, then dropped from the Godot build (teleport pads and shaped/void layouts went with them). They stay in the browser game, but don't bring them back to Godot unless Pete asks.

Code: `godot/scripts/levels.gd` holds layouts and rules; `level_art.gd`, `level_scenery.gd` and `level_props.gd` build the look. Each round picks one at random, like the browser's default "Level: Random", and the HUD shows its name. Spawns, rules, the hazard and prop spots are copied 1:1 from `LEVELS`, `CLOCKWORK_SECTIONS` and `RULE_LAYOUTS`.
- **Rules:** Factory's conveyor loop (5,3)–(9,9) carries fighters and bombs at 1.5 tiles/s. Haunted House's clockwork walls turn every 7.5 s over 1.15 s, and wait while anything is in the way.
- **Hazard:** the Haunted House witch throws a red bomb every 11 s. The target tile is marked at the start of a 1.5 s wind-up, then the bomb arcs over for 1.05 s with its fuse burning (fire 2). She stops during sudden death.
- **Bots** know the rules: belts change their escape timing, and the danger map includes where a belt will carry a bomb, thrown bombs in the air and the witch's marked target.
- **Spawns:** every tile within three steps of a spawn, plus the default clear pattern, stays crate-free. Crate density is the level's density +0.16 (max 0.92), as in the browser.
- **Bomb colour:** pale shell on the dark floors (Haunted House, Factory), like `bombColourFor`.
- **Looks (AAA pass, 2026-11-25):**
  - Forest: grass under dappled sun; three log-pile variants (classic stack, low pile, rope-lashed).
  - Beach: sand floor with wind ripples and damp patches, sandstone pillars, dusty coral border; driftwood crates and rope-bound barrels; a foam line laps round the sandbar; palms with arching segmented fronds.
  - Haunted House: dark boards, grey stone brick, wine-red caskets with dull brass, old travelling trunks, copper clockwork, candelabras, dead trees, graves, iron fence, mist.
  - Factory: diamond plate, steel pillars, a dark tread-plate border with a thin hazard-striped rim (stripes no longer on every block); cardboard pallets, oil drums and steel-banded crates.
- **Mechanics and characters (2026-11-25, `mechanics.gd`):** one of each per arena. All are telegraphed before they act, run headless (the smoke test plays them) and are known to the bots.
  - **Forest, tall grass:** two 3×3 meadows (x 3–5 and 9–11, y 5–7) are kept crate-free. Bots can't see a fighter in the grass unless they are within 2 tiles (they won't hunt or bomb at what they can't see); bots in the grass are hidden from you. A blast burns the grass on its tiles away for the round. The meadows are dense (14 tufts a tile) and lighter than the lawn, so they read as a zone. The grass sways over anyone moving in it, and a bot in the grass shows as a faint ghost when you are close enough that a bot would see you.
  - **Forest, the beaver:** from 10 s, every 14 s he pops up on an open tile holding a log for 1.4 s, then builds a crate there. He picks a tile nobody is within a tile of and that nothing is about to burn, preferring tiles with cover beside them. Stepping on it cancels. At most 4 per round, and none once fewer than 4 crates remain or the walls start closing. Bots treat his tile as blocked while he holds the log.
  - **Beach, the tide:** from 15 s, the outer lane floods every 23 s: 1.6 s rising (the warning), 5 s high, 1.4 s ebbing. For 3 s beforehand a "TIDE COMING IN" banner counts down and the lane goes dark and glossy. In the water fighters wade at 60% speed and bombs are put out (they fizzle and go back to their owner). Off during sudden death. Bots account for the slow wading and don't lay bombs in the water.
  - **Beach, crabs:** two crabs scuttle sideways along the lanes at 1.3 tiles/s and shove any bomb in their way one tile on (if the next tile can take it, and only if the bomb has at least 0.6 s of fuse left, with a puff of sand). They're harmless to fighters. A blast flings them away for 6 s.
  - **Haunted House, the witch flies:** she rides a broom round the house on an ellipse (8.7 × 7.4, 2.3 up) and stops to face her target during each wind-up. Her throw timing and fire are unchanged.
  - **Haunted House, ghosts:** from 8 s, every 16 s a ghost drifts in behind a crate for 1.3 s (with a moan, and a green ring marking where it will go), then shoves it one tile into an open space. Never a crate with a fighter within 2 tiles. Never onto a clockwork tile, a bomb, a pick-up, a fighter or the witch's target. Bots treat the ring as blocked.
  - **Factory, crushers:** three crushers at (7,6), (3,6) and (11,6), each two hydraulic jaws set in the pillars either side, so nothing hangs over the tile. The bed is striped. Every 8 s (first at 6 s, 8.7 s and 11.3 s): a 1.8 s warning (red lamps, the whole bed pulsing red, the jaws closing in three hydraulic steps), then the jaws slam. Anyone on the tile is crushed, a bomb there goes off, and a pick-up is destroyed. Off during sudden death. Bots treat the tile as dangerous for the last 2.6 s before it shuts.
  - **Factory, the lever:** on the north wall at (7,0). A blast reaching (7,1) throws it and the conveyor loop runs the other way ("BELTS REVERSED"). 2 s cooldown. (7,1) is kept crate-free.
- **CI screenshots:** `-- --tour` shows every arena for two seconds, and CI saves one frame of each as `arena-<id>.png` on the `ci-screenshots` branch. Locally, use autotest `"mode": "tour"`, or `"level": "<id>"` to play one arena.

### Not yet ported
Kick (and the other power-ups), character select / Loadout / Prize Locker, menus and options (level choice, difficulty, rounds, music volume), menu music, per-level music, the rest of the roster.

---

## Change log

Newest first. One dated heading per day; bullets say what changed, why, and where.

### 2026-11-25
- **AAA review round 4** (a fresh reviewer; the first one could not be resumed): FAIL, mostly 7s, technical polish 5. Blockers: bot triangle counts (20–73k each, frames at 1.4–1.7M triangles), the 44° lens making corner fighters look knocked out, and the witch over the near rows. Fixes:
  - **Bot LODs:** `tools/bake_bots.gd` (run with `--headless --script`) bakes each bot into `assets/characters/<id>-merged.res`: few surfaces, indexed, with generated LODs, so the web build needs no mesh simplifier at runtime. The game loads the bake; the raw `.glb` files are excluded from the web export (`export_presets.cfg`). Rerun the bake after changing a bot model. Forest frame: 1.37M → 0.43M triangles, about 320 draw calls.
  - **Camera:** fov 44 → 30, camera at (0, 24.8, 10.4) looking at (0, 0, 0.45). A longer lens, so nothing leans out at the corners. Shadow distance 36. Flyover and winner camera scaled to match.
  - **Flame arms are continuous beams:** each sheet knows its arm's axis, whether it's the end tile and which way it runs (instance colour), so heat runs unbroken across tiles with a rounded cap at the end. The flash is smaller and dimmer, fire is 3 points per cell and rises less, so chains no longer bleach to white or drift over the walls.
  - **Witch:** circuit centre z −2.6, radius 8.9 × 4.6, so she stays between z −7.2 and +2.0. She fades from z > 0, casts no shadow, and the fade covers her outline too.
  - **Clockwork at rest:** top plates `5e4030`, brass `8a6a40` (were lava-orange and bright yellow).
  - **Beach value steps:** sand floor, sandstone pillars (new block style 6, horizontal strata), dark driftwood crates (`7a5a3c`) with pale rope, a dusty-terracotta border (was pink), a warmer sky so shadows aren't blue, palms cast no shadow, soft shell flecks.
  - **Forest pillars:** a wider plinth, a carved band, and moss cushions on the cap.
  - **HUD:** chips show each pick-up's own 3D model (rendered once) with a count, not letters. Wall and tide warnings take over the timer pill's top line (red), with no banner over row 1. Controls bar: move and bomb only, during the first intro only.
  - **Tick:** a clock face on top of his hat.
  - **Haunted:** the mausoleum moves to the left middle, clear of the cards, with a pediment; its glow pool follows.
- **AAA review round 3:** FAIL. HUD reached 8 and the rest are at 7, but performance blocked: 656–999 peak draw calls on a phone web build. Fixes:
  - **Draw calls:** the bomber-bots now bake plain materials into vertex colours, grouped by finish, so each bot is a few surfaces instead of ~31. The four fighters with outline, rim and shadow passes went from about 380 draws to about 90 (`model_bot.gd` `_merge`). The rim pass only runs on dark floors, dark bodies and your own fighter. Explosions use one fire and one smoke emitter per blast (emission points), not two per cell. Flame sheets and scorch marks are pooled MultiMesh instances. Flash lights removed. Shadow distance 42 → 26. Ambient creatures cast no shadow. Measured mid-chain on Forest: 643 → 310 draw calls. `fx.gd`, `fighter.gd`, `game.gd`, `ambient.gd`.
  - **Look:** teardrop flame texture for fire particles (they read as flames, not discs); smoke cool grey and smaller; shockwave smaller. Worn, lighter bevels, grime at the foot and ±6% tint per block on pillars and walls (stone and block shaders, no new draw calls). Fighters on dark floors read as solid (more body fill, softer rim). Tick leans 0.45 so his face shows past the top hat (`ROSTER` `"lean"`).
  - **Haunted:** the witch's circuit moves back from the near rows (centre z −1.2, radius 6.4, 3 m up). She fades to half over the near rows and waits at the far side until play starts. The mausoleum gets a green-lit doorway and a moon-blue cap edge.
  - **HUD:** a vignette frames the arena; the timer pill is smaller and fades while someone plays right under it; four fixed short chips (B, F, S, SH, dim when empty), so cards never change width.
  - **Beach:** the lifeguard tower moved into frame.
- **AAA review round 2:** FAIL again, but every category improved (scores 6–7, were 3–6). The remaining blocker: Razor (dark body) had a dark outline on Forest and Beach. Fixes:
  - **Outlines by body, not just floor:** `ROSTER` marks dark-bodied fighters (`"dark": true`: Razor, Tick), and they always get a light line in their colour. Forest counts as a dark arena. Your own fighter gets an extra rim lift. Every fighter leans 0.22 rad towards the camera so faces show from above. `fighter.gd`, `game.gd`.
  - **Bombs** shrink (radius 0.34 → 0.29), and the red warning pulses instead of holding. Fireballs live no longer than the lethal window and fade to smoke grey. Pick-up rings take the item's colour and are smaller. "+BOMB" labels drop below the fighter in the top rows so they never slide under the timer. Smoke rises less. `fx.gd`.
  - **HUD:** portraits of each fighter's own model (rendered once into a small viewport) replace the initial badges. Bigger text for phones (chips 17 px, round label 16 px, names 22 px). Win pips 18 px with a visible empty state. Cards 212 px wide. The rules hint only shows during the flyover, never under the countdown. `hud.gd`, `game.gd`.
  - **Arenas:** Forest pillars neutral grey with little moss, so they don't merge with the grass; border boulders mossier and darker; sun higher (−50°). Factory border is plain tread plate with one continuous stripe band along the inside edge, and the hall has three machine kinds (press, lathe, control cabinet). Haunted House gets a mausoleum (left) and a broken wall with an arched gate and a lantern (right) where the camera looks, denser grave rows, and a red outline, rim and green spark trail on the witch; clockwork copper calmer at rest. Beach gets a lifeguard tower and a boardwalk. Bombs and pick-ups flatten the tall grass so they always show. `art.gd`, `level_art.gd`, `level_scenery.gd`, `ambient.gd`, `mechanics.gd`.
  - **Near-wall props dropped (Godot only):** nothing is placed on the camera-side wall row (except a hazard), because from this camera props there sat over the bottom lane. This departs from the browser's 1:1 prop spots. Pete to confirm. `game.gd` `_build_level_scene`.
- **AAA review round 1** (Pete: "Review all changes against a AAA title and only pass if a subagent confirms it meets AAA level"). An independent reviewer scored the AAA pass FAIL (5 of 9 categories at 5 or below). Its blocking issues were fighters that don't read, a reversed value order, explosions that don't show lethal tiles, and a prototype HUD. Fixes on branch `aaa-review`:
  - **Fighters:** height 1.25 → 1.45; outline (inverted hull) and rim light in the HUD colour, dark on light arenas and light on dark; KO toss with a white flash; slow motion 0.11 → 0.2 s. `fighter.gd`, `game.gd`.
  - **Value order:** pillars and borders darkened on all four arenas (Forest stone 0.84 → 0.56; Beach, Haunted and Factory block colours down; Factory pillars less metallic). Crates brightened. Casket crosses smaller and darker. Clockwork copper −25%, and its warning bar hidden between warnings. Conveyor chevrons muted (yellow is for danger). `art.gd`, `level_art.gd`, `game.gd`.
  - **Explosions:** lethal-tile flame sheets, a fire ramp that stays orange longer, 7–8 fireballs a tile, a shockwave ring, scorch at 35% for 3.5 s (was 62% for 7 s). Pick-ups get a coloured burst, a ring and a floating "+BOMB". `fx.gd`.
  - **HUD (new `hud.gd`):** Lilita One (OFL, `godot/assets/fonts/`). Player cards in the corners over the surroundings, with a colour badge, name, win pips, power-up chips and a KO tag. A compact round/timer pill over the far wall (red and pulsing for the last 10 s). A sudden-death / tide banner. Call-outs that punch in from big. Controls bar only at the start of the match.
  - **Flow:** letterbox and no HUD during the arrival flyover; a one-line rules hint under the arena name before each round; winner close-up camera during the outro. `game.gd`, `hud.gd`.
  - **Crate silhouettes fill the tile:** corner stakes on log piles, barrels seated in a square frame, a shrink-wrap band on drums, a stacked box on pallets.
  - **Surroundings:** the Factory is now an organised hall (corrugated walls with lit windows, I-beam columns, machine rows on painted bays, pallet racks, a forklift working each aisle). Haunted House gets a manor behind the far wall, grave rows either side and drifting ground fog. Beach palms have curved ribbon fronds, beach balls are smaller, and nothing tall sits on the camera side. `level_scenery.gd`, `ambient.gd`.
  - **Mechanic fairness:** see "Arenas (Godot)" (grass zone and ghosting, tide warning, crab fuse rule, ghosts every 16 s and not near fighters, crusher warning).
  - **Light:** Beach lower sun with more contrast; Factory sun angled more, less ambient, more contrast.
- **Tick joins the roster** as the eighth bot (Pete: "Yes" to adding him). He is the clockwork gentleman from the darker set, exported from `build/bombr/tick/tick.blend`, with a teal HUD colour, and goes into the random bot draw. Files: `godot/scripts/game.gd` (`ROSTER`), `godot/assets/characters/tick.glb`.
- **AAA pass on all four arenas** (Pete: "work through the whole list and make decisions based on what adds the most style, playability and meets our AAA goals"). Branch `arena-aaa-pass`. See "Look and sound", "Pick-ups" and "Arenas (Godot)" for the spec. In short:
  - Per-arena lighting and colour grade, a colour order on every arena (floor < walls < crates < fighters/hazards), and floor contact shadow from a live occupancy map. Files: `level_art.gd`, `art.gd`, `game.gd`.
  - Crate variants: three log piles (Forest), driftwood crate + barrel (Beach), casket + trunk (Haunted House), cardboard pallet + oil drums + banded crate (Factory). Half the crates are the main kind. Beach sand floor (new floor pattern 5), sandstone pillars, toned-down coral; Haunted House stone brick and wine caskets; Factory hazard stripes only on the border rim. Files: `level_art.gd`, `art.gd`, `level_scenery.gd`.
  - Moving surroundings (`ambient.gd`, new): birds, gulls, bats, pollen, glints, wisps, lightning, candles, steam, welding sparks. Glow pools instead of lights, keeping the one-sun rule. Beach foam line and new palms.
  - Arrival flyover, knockout slow motion, themed crate breaks. Files: `game.gd`, `fx.gd`.
  - Mechanics and characters (`mechanics.gd`, new): Forest tall grass + beaver, Beach tide + crabs, Haunted House flying witch + ghosts, Factory crushers + lever. Bots know them all (`bot_brain.gd`: passability, wading speed, can't see into grass, no bombs in water). Crates can now appear (spare multimesh instances) and slide.
  - Shield pick-up (Godot-only; the browser has a Shield too). Files: `config.gd`, `game.gd`, `fighter.gd`, `art.gd`, `fx.gd`.
  - Per-arena music (two new loops, Tide Pop and Graveyard Swing; Tension Pulse rendered for the Factory) and ambience beds; new sounds: tide, fizz, crusher, lever, shield pop, ghost, thunder, whoosh, beaver build. Files: `tools/render_music.py`, `tools/render_sfx.py` (new `arena` mode renders only these), `audio.gd`, `godot/assets/audio/`.
  - Smoke test: prints one `ROUND` line per round (arena, winner, length) and counts shields and doused bombs. `-- --smoke-rounds N` plays more rounds locally; `-- --tour-secs S` shortens the tour.
  - Balance check, 40 bot rounds against `main`: draws unchanged (9 in 40 on both). Rounds run longer on the Forest (70 → ~90 s) and the Haunted House (76 → ~93 s); the beaver was cut from 6 to 4 crates and the Shield drop rate from 3% to 2.5% because of this. Watch round length in play.
- **Four more bots** (Pete: "1, 3, 7 and 8 can stay" from the round-2 set in the Sparky/Rivet/Pixel style). Boiler, Gumball, Snap and Arcade are added to the Godot roster. Each match the three bot slots are filled at random from the seven bots, and each fighter brings its own HUD colour. Files: `godot/scripts/game.gd` (`ROSTER`, `_pick_cast`, autotest `"cast"`), `godot/assets/characters/{boiler,gumball,snap,arcade}.glb`; `tools/blender/bomber_bots_2.py` (branch `art/bot-concepts`).
- **Repo tidy** (Pete: "delete anything we don't need"): removed `archive/` (27 unreferenced legacy portraits), the retired patch workflows/scripts in `tools/legacy-patches/`, and the unused `assets/portraits/birb.webp` (Birb uses `bomber-og.webp`). `brand_refresh.py` moved to `tools/`. All still recoverable from git history. `.gitignore` now also covers `node_modules/`, `*.blend1` and `*.backup.*`. No runtime files changed. Files: `CLAUDE.md`, `.gitignore`.
- **Down to four arenas** (Pete: keep Forest, Beach, Factory and Haunted House "which we can further work on. The rest can go"). Glacier, Haunted Train, Circuit and Pirate Fleet are removed from the Godot build, together with the code only they used: teleport pads (fighters and bots), shaped/void layouts, the snowman and cannon hazards, and their art. The smoke test plays each arena twice (8 rounds). Files: `levels.gd`, `level_art.gd`, `level_scenery.gd`, `level_props.gd`, `game.gd`, `fighter.gd`, `bot_brain.gd`, `godot-build.yml`.
- **Roster cut** (Pete: keep concepts 1, 5, 6; of the existing fighters "keep Razor and Bomberman … get rid of the rest"). The Godot roster is now Razor + Sparky Mk II, Rivet and Pixel; their models (`sparky/rivet/pixel.glb`) are exported from Blender and animated by the new `model_bot.gd`. Orc, Bunny and Dino were removed from `godot/assets/characters`, and the rejected `robot.gd` bots were deleted. Bomberman is not in the Godot build yet: rather than upgrading Konami's character, the plan is an original bomber hero for that slot. Files: `game.gd`, `fighter.gd`, `model_bot.gd` (new), `assets/characters/`.
- **The other seven arenas are in the Godot build** (Pete: "let's get the rest of the maps in"): Beach, Glacier, Haunted House, Haunted Train, Factory, Circuit and Pirate Fleet, with their rules (belts, pads, clockwork walls), hazards (snowmen, witch, cannons) and shaped decks, ported from `LEVELS` and friends in `index.html`. A random arena each round; L skips to the next. See "Arenas (Godot)". Files: `godot/scripts/levels.gd`, `level_art.gd`, `level_scenery.gd`, `level_props.gd` (new); `game.gd`, `fighter.gd`, `bot_brain.gd`, `fx.gd`; `.github/workflows/godot-build.yml` (arena screenshots).
- **Parity fix — spawn pockets and crate density:** Godot only kept each spawn and its four neighbours clear and dealt crates at 70%. It now matches the browser: everything within three steps of a spawn stays clear, and density is the level's + 0.16.
- **Smoke test** now plays one round on each of the eight arenas.
- **Bot concepts re-rendered** (branch `art/bot-concepts`): the Blender script now runs inside the live Blender (no operator calls that need a UI context), with a seamless studio backdrop and fixed faces for Sparky, Pixel and Nova. Eight renders and a contact sheet were sent to Pete for a pick.

### 2026-11-24 (night)
- **Fuse made subtle** (Pete: still too big and bright): no spark particles any more, just a tiny ember on the fuse tip, plus a faint red warning glow on the shell in the last stretch of the fuse.
- **Bomber-bot roster proposal** (`godot/scripts/robot.gd`): Bolt, Tank, Pip and Sparky, built and animated in code. It's off (`USE_BOTS = false` in `game.gd`) until Pete approves the designs. The autotest `"lineup"` mode shows them side by side.
- **Round music: Arcade Drive** (Pete's pick from four options). It's a 128 bpm four-on-the-floor beat with octave bass, a 16th-note arpeggio and a pad, in A minor. It's an 8-bar seamless loop (`godot/assets/audio/music_arcade_drive.wav`, with a loop point embedded so Godot loops it without a gap). It plays through the countdown and the round at −9 dB under the effects, fades out for the win sting, and replaces the forest bass pulse (`bass_forest.wav` removed). The wind bed is lowered to −11 dB to sit under it.
- **Bot concepts in Blender** (branch `art/bot-concepts`, not merged): `tools/blender/bomber_bots.py` models, lights and renders eight bomber-bot concepts (Sparky Mk II, Fuse, Boomer, Volt, Rivet, Pixel, Mortar, Nova) in Blender 5.x, each parented to a `Bot_<name>` empty ready for glTF export to Godot. Awaiting Pete's pick.
- Files: `godot/scripts/audio.gd`, `game.gd`; `tools/render_music.py` (loop chunk), `tools/render_sfx.py`.

### 2026-11-24 (late evening)
- **Pick-ups are now 3D items** (mini bomb, flame, winged sneaker), floating over coloured glows instead of lettered tiles.
- **Arena edge defined:** raised stone base, the woods one step lower, a contact shadow inside the wall, and a darker forest floor.
- **Sudden death / walls closing in** ported from the browser rules (see "Sudden death"). The time-up draw is replaced by sudden death.
- **Sound v2:** GO, countdown, explosions, and round and match win redesigned as richer stereo sounds (impact, metallic partials, debris crackle, wider room), because the browser versions sounded cheap. New: sudden-death warning, start and wall slam. Recipes are in `V2` in `tools/render_sfx.py`.
- **Bots read the closing walls as danger** (`game.gd` `_doomed_tiles`): warned and queued wall tiles feed the danger map with their landing times. A sudden-death "hunt harder" boost for bots was tried and reverted (more draws, not fewer).
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
