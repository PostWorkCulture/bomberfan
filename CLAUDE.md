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
├── tools/legacy-patches/ retired one-off patch scripts/workflows (not run by CI)
└── archive/              unused files kept for reference only — never load from here
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
- Locally: open `godot/project.godot` in Godot 4.7. Command-line modes: `-- --smoke`, `-- --demo` (four bots), `-- --gallery` (fighter close-up).
- Build the game in code (scripts) rather than hand-written `.tscn` files where possible, so CI can check it.

## Daily upkeep

A scheduled task runs each evening (UK time). It reviews that day's commits, records design changes in `DESIGN.md`'s change log, refreshes the *Current state* section below if needed, and pushes to `main`. Manual edits are welcome; keep the same format.

## Current state

- Browser build: playable, live on Pages (build `standard-arenas-review-20260924`).
- Godot rebuild: vertical slice playable (Forest, you vs 3 bots, Bomb/Fire/Speed) at https://postworkculture.github.io/bomberfan/play/ — see DESIGN.md "Not yet ported" for what's next.
- 2026-11-24: repo tidied (see `DESIGN.md` change log).
