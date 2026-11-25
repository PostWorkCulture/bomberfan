extends RefCounted
## Tuning copied 1:1 from the browser build's `CFG` in ../index.html.
## Change a number here only with a DESIGN.md change-log entry.

# ---- Arena
const COLS := 15             # total columns including the outer wall
const ROWS := 13             # total rows including the outer wall
const SOFT_DENSITY := 0.70   # share of free interior tiles that get a crate

# ---- Players
const MAX_PLAYERS := 4
const BASE_SPEED := 3.9      # tiles per second
const SPEED_STEP := 3.9      # one Speed Up doubles base speed
const MAX_SPEED := 9.0
const SPEED_DURATION := 4.0  # Speed Up is temporary; a fresh one resets the clock
const PLAYER_RADIUS := 0.36
const TURN_SNAP := 2.8       # how fast you re-centre on the perpendicular axis
const START_BOMBS := 1
const START_FIRE := 2
const MAX_BOMBS := 8
const MAX_FIRE := 9

# ---- Bombs
const BOMB_FUSE := 1.8
const BLAST_LIFE := 0.52
const CHAIN_DELAY := 0.06

# ---- Pick-ups: per-crate drop rates from PU_DROPS (POWERUP_CHANCE 0.26004,
# weights Bomb 50 / Fire 24 / Speed 16 / Kick 20). Kick is not in the slice yet.
const DROP_BOMB := 0.1182
const DROP_FIRE := 0.0567
const DROP_SPEED := 0.0378
const DROP_SHIELD := 0.025     # Godot-only pick-up (2026-11-25): soaks one blast
const SHIELD_GRACE := 1.0      # seconds of safety after a shield pops

# ---- Endgame (sudden death), from CFG in index.html
const CRATES_CLEAR_GRACE := 5.0   # seconds after the last crate before the walls move
const SD_WARNING := 5.0           # warning shown this long before the walls move
const SD_RING_INTERVAL := 4.0     # seconds between shrinking rings
const SD_MAX_RINGS := 4           # how far the arena is allowed to close in
const SD_DRAW_AFTER := 20.0       # seconds after the final ring before calling a draw
const SD_BLOCK_STAGGER := 0.035   # delay between blocks within one ring

# ---- Match
const ROUND_SECONDS := 120.0
const WINS_NEEDED := 3
const ROUND_INTRO := 3.35    # 3 - 2 - 1, then GO!
const ROUND_OUTRO := 3.0

# ---- Simulation
const FIXED_DT := 1.0 / 60.0
const MAX_FRAME_DT := 0.25
