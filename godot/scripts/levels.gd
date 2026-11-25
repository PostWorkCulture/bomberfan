extends RefCounted
## The eight arenas. Layouts, spawns, rules, hazards and prop spots are
## copied from LEVELS / TWIN_ISLANDS / PIRATE_FLEET / HAUNTED_TRAIN /
## CLOCKWORK_SECTIONS / RULE_LAYOUTS in ../index.html. The look of each one
## is built in level_art.gd from the theme id.

# ---- Rules (RULE in index.html; ice is built there but never shipped)
const RULE_NONE := 0
const BELT_R := 1
const BELT_L := 2
const BELT_D := 3
const BELT_U := 4
const PAD := 5
const BELT_DIR := {1: Vector2i(1, 0), 2: Vector2i(-1, 0), 3: Vector2i(0, 1), 4: Vector2i(0, -1)}

# ---- Tuning from CFG
const BELT_SPEED := 1.5        # tiles/s: a current you can walk against, never a wall
const PAD_COOLDOWN := 0.9      # a pad won't take the same traveller again for this long
const HAZARD_EVERY := 11.0     # seconds between throws for each thrower
const HAZARD_WINDUP := 1.5     # holds the bomb up this long before letting go
const HAZARD_FLIGHT := 1.05    # time in the air
const HAZARD_FIRE := 2
const CLOCKWORK_PERIOD := 7.5  # seconds between turns
const CLOCKWORK_TURN := 1.15   # how long a quarter turn takes
const CLOCKWORK_WARN := 1.65   # gears speed up this long before a turn

const STD_SPAWNS := [Vector2i(1, 1), Vector2i(13, 11), Vector2i(13, 1), Vector2i(1, 11)]
# Six spots on the outer wall for standard arenas: [x, y, yaw]
const STD_PROP_SPOTS := [
	[0, 3, PI / 2], [14, 3, -PI / 2],
	[0, 6, PI / 2], [14, 6, -PI / 2],
	[5, 12, PI], [9, 12, PI],
]
const DEFAULT_CLEAR := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]
const CLEAR_TL := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
const CLEAR_BR := [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1)]

# Shaped layouts: everything is void (HARD, not drawn) except these.
const SHAPES := {
	"twin-islands": {
		"floors": [[0, 3, 6, 9], [8, 3, 14, 9]],
		"paths": [[6, 6], [7, 6], [8, 6]],
		"pillars": [[2, 5], [4, 5], [2, 7], [4, 7], [10, 5], [12, 5], [10, 7], [12, 7]],
	},
	"pirate-fleet": {
		"floors": [[1, 1, 6, 11], [8, 1, 13, 11]],
		"paths": [[6, 2], [7, 2], [8, 2], [6, 6], [7, 6], [8, 6], [6, 10], [7, 10], [8, 10]],
		"pillars": [[1, 4], [13, 4], [6, 8], [8, 8], [1, 8], [13, 8], [6, 4], [8, 4],
			[3, 4], [4, 8], [10, 4], [11, 8], [2, 6], [5, 6], [9, 6], [12, 6], [3, 10], [11, 2]],
	},
	"haunted-train": {
		"floors": [[1, 2, 4, 10], [6, 2, 8, 10], [10, 2, 13, 10]],
		"paths": [[5, 5], [5, 6], [5, 7], [9, 5], [9, 6], [9, 7]],
		"pillars": [[2, 4], [3, 8], [7, 4], [8, 8], [12, 4], [11, 8]],
	},
}

# Four three-tile copper walls on the Haunted House, turning together.
const CLOCKWORK_SECTIONS := [Vector2i(4, 4), Vector2i(10, 4), Vector2i(4, 8), Vector2i(10, 8)]

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
		"id": "glacier", "name": "Glacier", "density": 0.68, "layout": "twin-islands",
		"spawns": [[Vector2i(1, 4), CLEAR_TL], [Vector2i(5, 8), CLEAR_BR],
			[Vector2i(9, 4), CLEAR_TL], [Vector2i(13, 8), CLEAR_BR]],
		"props": ["snowman", "icespike"],
		"prop_spots": [[2, 5, PI / 2], [4, 7, -PI / 2], [10, 5, PI / 2], [12, 7, -PI / 2]],
		"hazard": "snowman", "hazard_count": 2,
	},
	{
		"id": "haunted", "pale_bomb": true, "name": "Haunted House", "density": 0.72, "layout": "clockwork-maze",
		# Order matters: dealt round the six wall spots, tall ones at the sides.
		"props": ["gravestone", "pumpkin", "ghost", "witch", "ghost", "ghost"],
		"hazard": "witch", "hazard_count": 1,
	},
	{
		"id": "haunted-train", "pale_bomb": true, "name": "Haunted Train", "density": 0.66, "layout": "haunted-train",
		"spawns": [[Vector2i(1, 2), CLEAR_TL], [Vector2i(4, 10), CLEAR_BR],
			[Vector2i(10, 2), CLEAR_TL], [Vector2i(13, 10), CLEAR_BR]],
		"props": ["conductor"],
		"prop_spots": [[2, 4, 0.0, "conductor", 1.12], [3, 8, 0.0, "luggage", 1.0],
			[7, 4, 0.0, "spectralengine", 1.08], [8, 8, 0.0, "lantern", 1.2],
			[12, 4, 0.0, "conductor", 1.08], [11, 8, 0.0, "luggage", 1.0]],
	},
	{
		"id": "factory", "pale_bomb": true, "name": "Factory", "density": 0.66, "rule": "belts",
		"props": ["pylon", "server"],
	},
	{
		"id": "circuit", "pale_bomb": true, "name": "Circuit", "density": 0.70, "rule": "pads",
		"props": ["pylon", "server"],
	},
	{
		"id": "pirate", "pale_bomb": true, "name": "Pirate Fleet", "density": 0.67, "layout": "pirate-fleet",
		"spawns": [[Vector2i(1, 1), CLEAR_TL], [Vector2i(6, 11), CLEAR_BR],
			[Vector2i(8, 1), CLEAR_TL], [Vector2i(13, 11), CLEAR_BR]],
		"props": ["cannon"],
		"prop_spots": [
			[1, 4, PI / 2, "cannon", 1.15], [13, 4, -PI / 2, "cannon", 1.15],
			[6, 8, PI / 2, "cannon", 1.1], [8, 8, -PI / 2, "cannon", 1.1],
			[1, 8, PI / 2, "cannon", 1.0], [13, 8, -PI / 2, "cannon", 1.0],
			[6, 4, PI / 2, "cannon", 1.0], [8, 4, -PI / 2, "cannon", 1.0],
			[3, 4, 0.0, "mast", 1.18], [4, 8, 0.0, "mast", 1.08],
			[10, 4, 0.0, "mast", 1.18], [11, 8, 0.0, "mast", 1.08],
			[2, 6, 0.0, "pirate", 1.0], [5, 6, PI, "pirate", 1.0],
			[9, 6, 0.0, "pirate", 1.0], [12, 6, PI, "pirate", 1.0],
			[3, 10, 0.0, "barrels", 1.0], [11, 2, 0.0, "treasure", 1.08],
		],
		"hazard": "cannon", "hazard_count": 4,
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


static func spawns(level: Dictionary) -> Array:
	if level.has("spawns"):
		return level["spawns"]
	var out: Array = []
	for s in STD_SPAWNS:
		out.append([s, DEFAULT_CLEAR])
	return out


static func prop_spots(level: Dictionary) -> Array:
	return level.get("prop_spots", STD_PROP_SPOTS)


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


## Teleport pads on the Circuit, paired in order: 0 with 1, 2 with 3.
static func pad_tiles() -> Array:
	return [[Vector2i(5, 8), PAD], [Vector2i(9, 4), PAD], [Vector2i(5, 4), PAD], [Vector2i(9, 8), PAD]]


static func clockwork_cells(section: Vector2i, vertical: bool) -> Array:
	if vertical:
		return [section + Vector2i(0, -1), section, section + Vector2i(0, 1)]
	return [section + Vector2i(-1, 0), section, section + Vector2i(1, 0)]
