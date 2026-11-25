extends RefCounted
## The four arenas. Layouts, spawns, rules, hazards and prop spots are copied
## from LEVELS / CLOCKWORK_SECTIONS / RULE_LAYOUTS in ../index.html. The look
## of each one is built in level_art.gd from the theme id.

# ---- Rules (RULE in index.html: belts; ice is built there but never shipped)
const RULE_NONE := 0
const BELT_R := 1
const BELT_L := 2
const BELT_D := 3
const BELT_U := 4
const BELT_DIR := {1: Vector2i(1, 0), 2: Vector2i(-1, 0), 3: Vector2i(0, 1), 4: Vector2i(0, -1)}

# ---- Tuning from CFG
const BELT_SPEED := 1.5        # tiles/s: a current you can walk against, never a wall
const HAZARD_EVERY := 11.0     # seconds between throws for each thrower
const HAZARD_WINDUP := 1.5     # holds the bomb up this long before letting go
const HAZARD_FLIGHT := 1.05    # time in the air
const HAZARD_FIRE := 2
const CLOCKWORK_PERIOD := 7.5  # seconds between turns
const CLOCKWORK_TURN := 1.15   # how long a quarter turn takes
const CLOCKWORK_WARN := 1.65   # gears speed up this long before a turn

const STD_SPAWNS := [Vector2i(1, 1), Vector2i(13, 11), Vector2i(13, 1), Vector2i(1, 11)]
# Six spots on the outer wall: [x, y, yaw]
const STD_PROP_SPOTS := [
	[0, 3, PI / 2], [14, 3, -PI / 2],
	[0, 6, PI / 2], [14, 6, -PI / 2],
	[5, 12, PI], [9, 12, PI],
]
const DEFAULT_CLEAR := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]

# Four three-tile copper walls on the Haunted House, turning together.
const CLOCKWORK_SECTIONS := [Vector2i(4, 4), Vector2i(10, 4), Vector2i(4, 8), Vector2i(10, 8)]

# The four arenas Pete kept (2026-11-25); Glacier, Haunted Train, Circuit and
# Pirate Fleet were dropped from the Godot build.
# pale_bomb: the floor is too dark for a black bomb (bombColourFor in
# index.html: CFG.BOMB_PALE when the ground is within 200 of BOMB_DARK).
const LIST := [
	{
		"id": "forest", "name": "Forest", "density": 0.70,
	},
	{
		"id": "beach", "name": "Beach", "density": 0.68,
		"props": ["beachball", "parasol"],
	},
	{
		"id": "haunted", "pale_bomb": true, "name": "Haunted House", "density": 0.72, "layout": "clockwork-maze",
		# Order matters: dealt round the six wall spots, tall ones at the sides.
		"props": ["gravestone", "pumpkin", "ghost", "witch", "ghost", "ghost"],
		"hazard": "witch", "hazard_count": 1,
	},
	{
		"id": "factory", "pale_bomb": true, "name": "Factory", "density": 0.66, "rule": "belts",
		"props": ["pylon", "server"],
	},
]


static func by_id(id: String) -> Dictionary:
	for l in LIST:
		if l["id"] == id:
			return l
	return {}


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return -1


static func spawns(_level: Dictionary) -> Array:
	var out: Array = []
	for s in STD_SPAWNS:
		out.append([s, DEFAULT_CLEAR])
	return out


static func prop_spots(_level: Dictionary) -> Array:
	return STD_PROP_SPOTS


## Tiles the conveyor loop covers on the Factory: one clockwise loop on the
## odd lanes from (5,3) to (9,9).
static func belt_tiles() -> Array:
	var out: Array = []
	var x0 := 5
	var y0 := 3
	var x1 := 9
	var y1 := 9
	for x in range(x0, x1):
		out.append([Vector2i(x, y0), BELT_R])
	for y in range(y0, y1):
		out.append([Vector2i(x1, y), BELT_D])
	for x in range(x1, x0, -1):
		out.append([Vector2i(x, y1), BELT_L])
	for y in range(y1, y0, -1):
		out.append([Vector2i(x0, y), BELT_U])
	return out


static func clockwork_cells(section: Vector2i, vertical: bool) -> Array:
	if vertical:
		return [section + Vector2i(0, -1), section, section + Vector2i(0, 1)]
	return [section + Vector2i(-1, 0), section, section + Vector2i(1, 0)]
