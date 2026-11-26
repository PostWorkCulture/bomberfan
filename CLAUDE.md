# CLAUDE.md — Bomber Fan

Read this file and `DESIGN.md` before making any change. They are the single source of truth for this project and exist to stop drift between sessions, tools and machines.

## What this project is

Bomber Fan is a 3D bomber-arena game (Bomberman-style: grid arena, crates, bombs, power-ups, up to 4 players/bots).

- **Live version (reference build):** a single-file browser game, `index.html`, served by GitHub Pages from `main` at https://postworkculture.github.io/bomberfan/. Three.js, PWA (manifest + service worker).
- **Current goal:** rebuild Bomber Fan in **Godot 4**. The Godot project lives in `godot/`. The browser build is the behavioural reference: when in doubt about how something should play, match `index.html` unless `DESIGN.md` records a deliberate change.

## Repository layout

```
/                         GitHub Pages root (must stay here — do not move these)
├── index.html            the browser game (all game code, CSS and UI)
├── manifest.webmanifest  PWA manifest
├── sw.js                 service worker (must stay at root for its scope)
├── refresh.html          clears old service workers/caches, then reloads the game
├── .nojekyll             tells Pages to serve files as-is
├── CLAUDE.md             this file — how to work on the project
├── DESIGN.md             design spec + dated change log
├── README.md             public overview
├── assets/
│   ├── branding/         main-logo.png, bf-icon.svg
│   ├── icons/            PWA + favicon + apple-touch icons
│   ├── characters/       animated glTF fighters (+ .bin, textures) and fighter JS modules
│   ├── portraits/        character-select portraits (<id>.webp, matched to fighter ids)
│   └── vendor/           three.js, GLTFLoader, SkeletonUtils, BufferGeometryUtils, bootstrap
├── godot/                Godot 4.7 rebuild (project.godot, scenes/, scripts/, assets/)
├── play/                 Godot web build — written ONLY by the godot-build workflow
├── .github/workflows/    godot-build.yml (check + export + publish play/)
├── tests/                standalone HTML review pages + preview-server.py
├── tools/                render_sfx.py (sound effects), render_music.py (music loops),
│                         brand_refresh.py (regenerate PWA icons from the logo)
└── build/                local scratch, git-ignored: music previews, Blender concept renders
```

## Naming conventions

- Folders and files: **lowercase kebab-case** (`skull-orc.gltf`, `main-logo.png`). No spaces, no capitals.
- Python scripts: snake_case (`brand_refresh.py`).
- Godot: scenes/scripts snake_case (`player.tscn`, `bomb.gd`), nodes PascalCase, folders inside `godot/` lowercase (`scenes/`, `scripts/`, `assets/`, `ui/`, `levels/`).
- Character ids are shared across portraits, models and code: `assets/portraits/<id>.webp`, `assets/characters/<id>.gltf`.

## Working rules

1. **Check `DESIGN.md` first.** If a request contradicts a recorded decision, say so and confirm before changing it.
2. **Log every design change** in `DESIGN.md` → *Change log* under today's date (what changed, why, files touched). Update the spec sections if the change alters them.
3. **Don't break Pages.** Root files above stay at root. After moving or renaming any asset, grep for the old path in `index.html`, `sw.js`, `manifest.webmanifest`, `assets/**/*.js` and `tests/`.
4. **Cache busting:** bump `<meta name="build">` in `index.html` when shipping visible changes; bump the cache name in `sw.js` when its asset list changes.
5. **No auto-patching workflows.** Don't add GitHub Actions that rewrite `index.html` and push; make edits directly in commits. The one exception is `godot-build.yml`, which only writes `play/` (and the `ci-screenshots` branch). Never edit `play/` by hand.
6. **Godot parity:** when porting a system, copy its tuning numbers from `CFG`, `PU`, `LEVELS` etc. in `index.html` and note the port in the change log.
7. Commit messages: short imperative summary of the change.

## Where things live in `index.html`

| Area | Search for |
|---|---|
| Core tuning (grid, speeds, bombs, fire) | `const CFG` |
| Power-ups | `const PU` |
| Tile rules (belts, ice) | `const RULE` |
| Difficulty / rounds options | `DIFFICULTIES`, `ROUND_OPTIONS` |
| Arenas | `const LEVELS` |
| Saved settings keys | `blastarena.audio`, `blastarena.locker`, `blastarena.controls` |
| Build id | `meta name="build"` |

## Godot workflow

- Every push touching `godot/` runs `godot-build.yml` on real Godot 4.7.2: import → headless smoke test (`-- --smoke`, bots-only, fails on script errors or if rounds don't finish) → web export → screenshots.
- Check results: `gh api repos/PostWorkCulture/bomberfan/actions/runs?branch=<branch>`; the smoke summary is a `::notice` annotation on the job's check run. Screenshots land on the `ci-screenshots` branch (`git fetch origin ci-screenshots`).
- Work on a branch until CI is green, then merge to `main`; CI then publishes `play/`.
- Local working copy: `Documents\AI\Claude\Projects\Games\Bman` on the "bakes" PC (a git clone; open `Bman\godot\project.godot` in Godot 4.7.2). Run it with the Godot MCP `run_project` and check `get_debug_output` for zero errors/warnings before pushing. Commit the `.import` and `.uid` files Godot generates. Command-line modes: `-- --smoke`, `-- --demo` (four bots), `-- --gallery` (fighter close-up).
- Build the game in code (scripts) rather than hand-written `.tscn` files where possible, so CI can check it. Art is procedural too (`scripts/art.gd`); add image files only when procedural can't do the job.
- Visual check on the PC: set `"enabled": true` in `godot/autotest.json` (git-ignored), run with `run_project`, then read `godot/.godot/autotest/shot_*.png` and `stats.txt`. **Set it back to `false` afterwards**, or the game quits itself.
- Sounds: edit recipes in `tools/render_sfx.py` (a port of the browser synth plus `V2` upgraded designs), run it, and commit the WAVs. Don't hand-edit WAVs. Music: `tools/render_music.py preview` makes MP3 previews in `build/` (git-ignored); `tools/render_music.py <name>` writes a seamless loop to `godot/assets/audio/music_<name>.wav`.
- When copying files to the PC with `device_commit_files`, wait about 20 s after writing them, then compare checksums. The file store can serve a stale copy.

## Daily upkeep

A scheduled task runs each evening (UK time). It reviews that day's commits, records design changes in `DESIGN.md`'s change log, refreshes the *Current state* section below if needed, and pushes to `main`. Manual edits are welcome; keep the same format.

## Current state

- Browser build: playable, live on Pages (build `standard-arenas-review-20260924`).
- Godot rebuild: four arenas (Forest, Beach, Haunted House, Factory), you (Razor) vs 3 bots drawn each match from eight (Sparky, Rivet, Pixel, Boiler, Gumball, Snap, Arcade, Tick), Bomb/Fire/Speed/Shield pick-ups, sudden death, at https://postworkculture.github.io/bomberfan/play/. AAA pass (2026-11-25): per-arena lighting, grade, crate variants, moving surroundings, arrival flyover, per-arena music and ambience, and one mechanic + one character per arena (`mechanics.gd`). See DESIGN.md "Arenas (Godot)" and "Not yet ported".
- Local preview without the PC: `-- --tour --tour-secs 0.8` with `--write-movie` under xvfb renders all four arenas in about 2 minutes; `-- --smoke --smoke-rounds 40` (optionally `--level <id>`) gives per-round lines for balance checks.
- AAA review (2026-11-26): passed by an independent reviewer after 12 rounds, conditional on a real-phone frame-time check (see DESIGN.md change log, "AAA review round 12"). `tools/xray_ab.sh` A/B-checks your fighter's x-ray silhouette; `-- --seed N`, `-- --autopilot` and `-- --no-xray` support it.
- Waiting on Pete: a pick for the original bomber hero ("Bombr") that replaces Bomberman. Blender concepts and scripts (`tools/blender/`) are on branch `art/bot-concepts`, not on `main`.
- 2026-11-25: repo tidied again — `archive/` and retired patch scripts removed (still in git history; see `DESIGN.md` change log).
