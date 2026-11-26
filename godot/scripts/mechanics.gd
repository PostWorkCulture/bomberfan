extends RefCounted
## Arena mechanics and their characters (AAA pass, 2026-11-25). One mechanic
## and one character per arena, each telegraphed before it acts and each known
## to the bots:
##   Forest   tall-grass meadows hide whoever stands in them; a beaver rebuilds
##            a crate now and then, so the woods never go bare.
##   Beach    the tide floods the outer lane: wading is slow and water puts
##            bombs out. Crabs scuttle along the lanes and shove bombs.
##   Haunted  the witch flies a broom circuit round the house (her throws are
##            unchanged); ghosts shove a crate one tile.
##   Factory  three presses stamp their tile on a cycle; blast the lever on the
##            north wall to run the conveyor loop backwards.
## Rules run headless (the smoke test plays them); models only when visible.

const Cfg := preload("res://scripts/config.gd")
const Levels := preload("res://scripts/levels.gd")
const LA := preload("res://scripts/level_art.gd")
const Art := preload("res://scripts/art.gd")
const Props := preload("res://scripts/level_props.gd")
const Fighter := preload("res://scripts/fighter.gd")

const EMPTY := 0
const HARD := 1
const SOFT := 2
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SAFE := 999.0

# ---- Forest
const GRASS_PATCHES := [Rect2i(3, 5, 3, 3), Rect2i(9, 5, 3, 3)]
const GRASS_SEE := 2            # bots spot someone in the grass from this close (tiles)
const BEAVER_FIRST := 10.0
const BEAVER_EVERY := 14.0
const BEAVER_WARN := 1.4        # he pops up and holds the log this long first
const BEAVER_MAX := 4           # crates rebuilt per round at most
const BEAVER_MIN_CRATES := 4    # stops once the woods are nearly cleared
# ---- Beach
const TIDE_FIRST := 15.0        # first flood starts rising this far into the round
const TIDE_LOW := 15.0          # dry spell between floods
const TIDE_RISE := 1.6          # the water creeping in is the warning
const TIDE_HIGH := 5.0
const TIDE_FALL := 1.4
const TIDE_SLOW := 0.6          # wading speed
const TIDE_WARN := 3.0          # banner and wet sand before the water starts rising
const CRAB_MIN_FUSE := 0.6      # crabs leave a bomb alone this close to going off
const CRAB_COUNT := 2
const CRAB_SPEED := 1.3         # tiles/s
const CRAB_RESPAWN := 6.0
# ---- Haunted House
const GHOST_FIRST := 8.0
const GHOST_EVERY := 16.0      # AAA review: the Haunted House was running three systems at once
const GHOST_WARN := 1.3
const WITCH_ORBIT := Vector2(8.9, 4.6)
const WITCH_CENTRE_Z := -2.6    # her circuit stays off the near rows: z from -7.2 to +2.0 (AAA review round 4)
const WITCH_HEIGHT := 3.0
const WITCH_SPEED := 0.32       # rad/s round the house
# ---- Factory
const PRESS_TILES := [Vector2i(7, 6), Vector2i(3, 6), Vector2i(11, 6)]
const PRESS_PERIOD := 8.0
const PRESS_WARN := 1.8         # red light and the head creeping down
const PRESS_DANGER := 2.6       # bots keep off a press bed this long before it drops
const PRESS_LIFT := 1.0
const LEVER_WALL := Vector2i(7, 0)
const LEVER_TILE := Vector2i(7, 1)   # a blast reaching this tile throws the lever
const LEVER_COOL := 2.0

var game = null
var id := ""
var _root: Node3D = null

var grass := {}          # tile index -> true while the grass stands
var _grass_mm: MultiMeshInstance3D = null
var _grass_inst := {}    # tile index -> [instance indices]
var _grass_base: Array = []   # resting transforms of every tuft
var beaver := {}         # {"t", "tile", "warn", "built"}
var _beaver_node: Node3D = null
var tide_t := 0.0
var tide_level := 0.0    # 0 dry .. 1 full (visual)
var flooded := false
var _flood_tiles := {}   # tile index -> true: the outer lane
var _water: MeshInstance3D = null
var crabs: Array = []    # {"pos": Vector2, "tile", "to", "dir", "dead", "node"}
var ghost := {}          # {"t", "from", "to", "warn"}
var _ghost_node: Node3D = null
var _ghost_mark: MeshInstance3D = null
var _witch_angle := 0.0
var presses: Array = []  # {"tile", "t", "node", "head", "light"}
var lever := {}          # {"cool", "on", "node"}
var _rng := RandomNumberGenerator.new()


func setup(g) -> void:
	game = g
	_rng.seed = 4242


# ---- Round set-up ------------------------------------------------------------------

## Tiles kept free of crates on this arena: the grass meadows, the press beds.
func reserved(level_id: String) -> Array:
	var out: Array = []
	match level_id:
		"forest":
			for r in GRASS_PATCHES:
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						out.append(Vector2i(x, y))
		"factory":
			for t in PRESS_TILES:
				out.append(t)
			out.append(LEVER_TILE)
	return out


func start_round(level_id: String) -> void:
	id = level_id
	_rng.seed = game.rng.randi()
	grass.clear()
	_grass_inst.clear()
	_grass_mm = null
	beaver = {"t": BEAVER_FIRST, "tile": Vector2i(-1, -1), "warn": 0.0, "built": 0}
	_beaver_node = null
	tide_t = -(TIDE_FIRST - TIDE_LOW)
	tide_level = 0.0
	flooded = false
	_flood_tiles.clear()
	_water = null
	crabs.clear()
	ghost = {"t": GHOST_FIRST, "from": Vector2i(-1, -1), "to": Vector2i(-1, -1), "warn": 0.0}
	_ghost_node = null
	_ghost_mark = null
	presses.clear()
	lever = {"cool": 0.0, "on": false, "node": null}
	_root = null
	match id:
		"forest":
			for r in GRASS_PATCHES:
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						if game.cell_at(x, y) == EMPTY:
							grass[game.idx(x, y)] = true
		"beach":
			for y in range(1, Cfg.ROWS - 1):
				for x in range(1, Cfg.COLS - 1):
					if (x == 1 or y == 1 or x == Cfg.COLS - 2 or y == Cfg.ROWS - 2) and game.cell_at(x, y) != HARD:
						_flood_tiles[game.idx(x, y)] = true
			for k in CRAB_COUNT:
				crabs.append({"pos": Vector2.ZERO, "tile": Vector2i(-1, -1), "to": Vector2i(-1, -1), "dir": Vector2i.ZERO,
					"dead": 0.0, "node": null, "spawned": false})
		"factory":
			for i in PRESS_TILES.size():
				# First stamps at 6 s, 8.7 s and 11.3 s, then every PRESS_PERIOD.
				presses.append({"tile": PRESS_TILES[i], "t": PRESS_PERIOD - (6.0 + i * 2.67), "node": null, "head": null, "light": null})
	if game.smoke:
		for c in crabs:
			_spawn_crab(c)
		return
	_root = Node3D.new()
	game.round_root.add_child(_root)
	match id:
		"forest":
			_build_grass()
			_beaver_node = _make_beaver()
			_beaver_node.visible = false
			_root.add_child(_beaver_node)
		"beach":
			_build_water()
			for c in crabs:
				c["node"] = _make_crab()
				_root.add_child(c["node"])
				_spawn_crab(c)
		"haunted":
			_ghost_node = Props.make("ghost")
			_ghost_node.visible = false
			_root.add_child(_ghost_node)
			_ghost_mark = _mark(Color(0.45, 1.0, 0.7))
		"factory":
			for p in presses:
				_build_press(p)
			_build_lever()
			_set_belt_dir(1.0)


# ---- Hooks from game.gd --------------------------------------------------------------

func step(dt: float) -> void:
	match id:
		"forest":
			_step_beaver(dt)
		"beach":
			_step_tide(dt)
			_step_crabs(dt)
		"haunted":
			_step_ghost(dt)
		"factory":
			_step_presses(dt)
			lever["cool"] = maxf(0.0, lever["cool"] - dt)


## Tiles about to be hit by something other than fire, with seconds to go:
## the presses, for the bots' danger map.
func doomed() -> Array:
	var out: Array = []
	if game.sudden_death:
		return out
	for p in presses:
		var left: float = PRESS_PERIOD - p["t"]
		if left <= PRESS_DANGER:
			out.append([p["tile"], maxf(0.0, left)])
	return out


## A tile something is about to land on (a ghost's crate, the beaver's log):
## bots will not path through it.
func blocked(t: Vector2i) -> bool:
	if ghost["warn"] > 0.0 and ghost["to"] == t:
		return true
	if beaver["warn"] > 0.0 and beaver["tile"] == t:
		return true
	return false


func move_mult(t: Vector2i) -> float:
	if flooded and _flood_tiles.has(game.idx(t.x, t.y)):
		return TIDE_SLOW
	return 1.0


func is_flooded(t: Vector2i) -> bool:
	return flooded and _flood_tiles.has(game.idx(t.x, t.y))


## Standing in tall grass: bots further than GRASS_SEE tiles cannot see you.
func hidden(f) -> bool:
	if grass.is_empty() or not f.alive or game.phase == "gallery":
		return false
	var t: Vector2i = f.tile()
	return grass.has(game.idx(t.x, t.y))


func can_see(viewer, f) -> bool:
	if not hidden(f):
		return true
	var a: Vector2i = viewer.tile()
	var b: Vector2i = f.tile()
	return absi(a.x - b.x) + absi(a.y - b.y) <= GRASS_SEE


func on_blast(cells: Array) -> void:
	for c in cells:
		var k: int = game.idx(c.x, c.y)
		if grass.has(k):
			_burn_grass(k)
		for cr in crabs:
			if cr["dead"] <= 0.0 and cr["spawned"] and (cr["tile"] == c or cr["to"] == c):
				_kill_crab(cr)
		if id == "factory" and c == LEVER_TILE and lever["cool"] <= 0.0:
			_flip_lever()


func visual(delta: float, t: float) -> void:
	if _root == null:
		return
	match id:
		"forest":
			_visual_beaver(t)
			_visual_grass(t)
		"beach":
			_visual_tide(delta, t)
			for c in crabs:
				_visual_crab(c, t)
		"haunted":
			_visual_ghost(t)
			_visual_witch(delta, t)
		"factory":
			_visual_presses(delta, t)
			_visual_lever(delta)


# ---- Forest: tall grass ------------------------------------------------------------------

func _build_grass() -> void:
	var xs: Array = []
	var cols: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for k in grass.keys():
		var t := Vector2i(k % Cfg.COLS, k / Cfg.COLS)
		var ids: Array = []
		for i in 14:
			var off := Vector3(r.randf_range(-0.46, 0.46), 0.0, r.randf_range(-0.46, 0.46))
			var s := r.randf_range(1.0, 1.2)
			ids.append(xs.size())
			xs.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s * 1.35, s * 3.0, s * 1.35)), game.tile_pos(t.x, t.y) + off))
			var tint := r.randf_range(0.97, 1.03)
			cols.append(Color(tint * 1.25, tint * 1.35, tint * 0.85))
		_grass_inst[k] = ids
	_grass_base = xs
	_grass_mm = Art.multimesh(Art.grass_tuft_mesh(), xs, cols, false)
	_root.add_child(_grass_mm)


var _rustling := {}   # tile index -> true while its tufts are bent


## Tufts sway over anyone in the grass, so a hidden fighter still gives itself
## away by moving.
func _visual_grass(t: float) -> void:
	if _grass_mm == null:
		return
	var now := {}
	for f in game.fighters:
		if f.alive:
			var ft: Vector2i = f.tile()
			var k: int = game.idx(ft.x, ft.y)
			if _grass_inst.has(k):
				now[k] = f.moving
	# Bombs and pick-ups in the grass flatten it so they always show.
	for k in game.bomb_at.keys():
		if _grass_inst.has(k):
			now[k] = "flat"
	for k in game.pickups.keys():
		if _grass_inst.has(k):
			now[k] = "flat"
	for k in _rustling.keys():
		if not now.has(k):
			_set_tufts(k, 0.0, t)
	for k in now.keys():
		var v = now[k]
		if v is String:
			_set_tufts(k, -1.0, t)
		else:
			_set_tufts(k, 1.0 if v else 0.35, t)
	_rustling = now


func _set_tufts(k: int, amt: float, t: float) -> void:
	if not _grass_inst.has(k):
		return
	var mm := _grass_mm.multimesh
	var i := 0
	for inst in _grass_inst[k]:
		var xf: Transform3D = _grass_base[inst]
		if amt < 0.0:
			xf.basis = xf.basis.scaled(Vector3(1.0, 0.22, 1.0))
		elif amt > 0.0:
			var lean := sin(t * 14.0 + i * 1.7) * 0.32 * amt
			xf.basis = Basis(Vector3(1, 0, 0.3).normalized(), lean) * xf.basis
		mm.set_instance_transform(inst, xf)
		i += 1


func _burn_grass(k: int) -> void:
	grass.erase(k)
	if _grass_mm == null or not _grass_inst.has(k):
		return
	for i in _grass_inst[k]:
		_grass_mm.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
	_grass_inst.erase(k)


# ---- Forest: the beaver ----------------------------------------------------------------

func _step_beaver(dt: float) -> void:
	if beaver["warn"] > 0.0:
		var t: Vector2i = beaver["tile"]
		if not _tile_clear(t, 0):
			beaver["warn"] = 0.0   # someone stepped on it: he ducks back down
			beaver["t"] = 3.0
			return
		beaver["warn"] -= dt
		if beaver["warn"] <= 0.0:
			game.add_crate(t)
			beaver["built"] += 1
			if not game.smoke:
				game.fx.crate_dust(game.tile_pos(t.x, t.y))
				game.audio.play("build", 0.0, 0.1)
		return
	if game.sd_warned or game.sudden_death or beaver["built"] >= BEAVER_MAX or game.soft_count < BEAVER_MIN_CRATES:
		return
	beaver["t"] -= dt
	if beaver["t"] > 0.0:
		return
	beaver["t"] = BEAVER_EVERY
	var pick := _beaver_tile()
	if pick.x >= 0:
		beaver["tile"] = pick
		beaver["warn"] = BEAVER_WARN


## An open tile nobody is near and nothing is about to burn, ideally one with
## cover either side (he rebuilds walls of logs, not islands).
func _beaver_tile() -> Vector2i:
	var danger: PackedFloat32Array = game.compute_danger({})
	var best: Array = []
	var best_score := -1
	for y in range(1, Cfg.ROWS - 1):
		for x in range(1, Cfg.COLS - 1):
			var t := Vector2i(x, y)
			if not _tile_clear(t, 1) or danger[game.idx(x, y)] < SAFE or grass.has(game.idx(x, y)):
				continue
			var cover := 0
			for d in DIRS:
				if game.cell_at(x + d.x, y + d.y) != EMPTY:
					cover += 1
			if cover >= 4:
				continue
			if cover > best_score:
				best_score = cover
				best = [t]
			elif cover == best_score:
				best.append(t)
	return best[_rng.randi() % best.size()] if not best.is_empty() else Vector2i(-1, -1)


func _tile_clear_of_fighters(t: Vector2i, margin: int) -> bool:
	for f in game.fighters:
		if f.alive:
			var ft: Vector2i = f.tile()
			if absi(ft.x - t.x) <= margin and absi(ft.y - t.y) <= margin:
				return false
	return true


## Seconds until the tide starts rising, while the warning is up (else 0).
func tide_warning() -> float:
	if id != "beach" or game.sudden_death or tide_t < -TIDE_WARN:
		return 0.0
	var c := fmod(tide_t, _tide_cycle()) if tide_t >= 0.0 else tide_t - TIDE_LOW
	if c >= TIDE_LOW - TIDE_WARN and c < TIDE_LOW:
		return TIDE_LOW - c
	return 0.0


## Empty, no bomb / pick-up / flame, and no fighter within `margin` tiles.
func _tile_clear(t: Vector2i, margin: int) -> bool:
	if game.cell_at(t.x, t.y) != EMPTY:
		return false
	var k: int = game.idx(t.x, t.y)
	if game.bomb_at.has(k) or game.pickups.has(k) or game.flames.has(k):
		return false
	if t == game.hazard_target:
		return false
	for fl in game.flights:
		if fl["to"] == t:
			return false
	for f in game.fighters:
		if not f.alive:
			continue
		if f.overlaps_tile(t):
			return false
		var ft: Vector2i = f.tile()
		if margin > 0 and absi(ft.x - t.x) <= margin and absi(ft.y - t.y) <= margin:
			return false
	return true


func _visual_beaver(t: float) -> void:
	if _beaver_node == null:
		return
	var on: bool = beaver["warn"] > 0.0
	_beaver_node.visible = on
	if not on:
		return
	var tile: Vector2i = beaver["tile"]
	var k: float = 1.0 - beaver["warn"] / BEAVER_WARN
	var rise := minf(1.0, k * 4.0)
	var sink := maxf(0.0, (k - 0.82) / 0.18)
	_beaver_node.position = game.tile_pos(tile.x, tile.y) + Vector3(0, -0.55 + 0.55 * rise - 0.6 * sink, 0)
	_beaver_node.rotation.y = sin(t * 3.0) * 0.25
	var log_n := _beaver_node.get_node("Log") as Node3D
	log_n.position.y = 0.72 + sin(t * 9.0) * 0.04


# ---- Beach: the tide -----------------------------------------------------------------------

func _tide_cycle() -> float:
	return TIDE_LOW + TIDE_RISE + TIDE_HIGH + TIDE_FALL


func _step_tide(dt: float) -> void:
	if game.sudden_death:
		flooded = false
		tide_level = maxf(0.0, tide_level - dt / TIDE_FALL)
		return
	tide_t += dt
	var c := fmod(maxf(tide_t, 0.0), _tide_cycle()) if tide_t >= 0.0 else -1.0
	var was := flooded
	if c < TIDE_LOW:
		flooded = false
		tide_level = 0.0
	elif c < TIDE_LOW + TIDE_RISE:
		flooded = false
		tide_level = (c - TIDE_LOW) / TIDE_RISE
	elif c < TIDE_LOW + TIDE_RISE + TIDE_HIGH:
		flooded = true
		tide_level = 1.0
	else:
		flooded = false
		tide_level = 1.0 - (c - TIDE_LOW - TIDE_RISE - TIDE_HIGH) / TIDE_FALL
	if flooded and not was and not game.smoke:
		game.audio.play("tide", -4.0, 0.0, 0.5)
	if flooded:
		for b in game.bombs:
			if b["alive"] and _flood_tiles.has(game.idx(b["x"], b["y"])):
				game.douse_bomb(b)


func _build_water() -> void:
	# The outer lane as one frame of shallow water that rises and falls.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := 0.5
	var x1 := Cfg.COLS - 1.5
	var y0 := 0.5
	var y1 := Cfg.ROWS - 1.5
	var rects := [Rect2(x0, y0, x1 - x0, 1.0), Rect2(x0, y1 - 1.0, x1 - x0, 1.0),
		Rect2(x0, y0 + 1.0, 1.0, y1 - y0 - 2.0), Rect2(x1 - 1.0, y0 + 1.0, 1.0, y1 - y0 - 2.0)]
	for r in rects:
		var p0 := game.tile_pos(r.position.x, r.position.y) as Vector3
		var p1 := game.tile_pos(r.end.x, r.end.y) as Vector3
		var quad := [Vector3(p0.x, 0, p0.z), Vector3(p1.x, 0, p0.z), Vector3(p1.x, 0, p1.z),
			Vector3(p0.x, 0, p0.z), Vector3(p1.x, 0, p1.z), Vector3(p0.x, 0, p1.z)]
		for v in quad:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	_water = MeshInstance3D.new()
	_water.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = LA._shader("tide", TIDE_SHADER)
	m.set_shader_parameter("noise_tex", LA.noise_tex())
	_water.material_override = m
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.visible = false
	_root.add_child(_water)


func _visual_tide(_delta: float, _t: float) -> void:
	if _water == null:
		return
	# During the warning the lane goes dark and glossy: wet sand, water coming.
	var warn := tide_warning()
	var lvl := tide_level
	if warn > 0.0:
		lvl = maxf(lvl, 0.12 * (1.0 - warn / TIDE_WARN) + 0.04)
	_water.visible = lvl > 0.01
	_water.position.y = -0.06 + 0.2 * lvl
	(_water.material_override as ShaderMaterial).set_shader_parameter("level", lvl)


const TIDE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
uniform float level = 1.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 2.0 + wpos.x * 1.3 + wpos.z * 0.7) * 0.015;
}
void fragment() {
	vec2 p = wpos.xz;
	float c1 = texture(noise_tex, p * 0.34 + vec2(TIME * 0.05, TIME * 0.03)).r;
	float c2 = texture(noise_tex, p * 0.31 - vec2(TIME * 0.04, -TIME * 0.05)).r;
	float caustic = pow(clamp(1.0 - abs(c1 - c2) * 2.2, 0.0, 1.0), 8.0);
	float foam = smoothstep(0.62, 0.8, texture(noise_tex, p * 0.6 + vec2(TIME * 0.12, 0.0)).r);
	vec3 col = mix(vec3(0.08, 0.36, 0.42), vec3(0.22, 0.56, 0.6), c1);
	col += vec3(0.6, 0.9, 0.95) * caustic * 0.4;
	col = mix(col, vec3(0.92, 0.97, 1.0), foam * 0.35);
	ALBEDO = col;
	ALPHA = clamp(0.22 + 0.3 * level + foam * 0.25, 0.0, 0.8) * smoothstep(0.0, 0.25, level);
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = vec3(0.1, 0.3, 0.35) * caustic * 0.3;
}
"""


# ---- Beach: crabs -----------------------------------------------------------------------

func _crab_ok(t: Vector2i) -> bool:
	if game.cell_at(t.x, t.y) != EMPTY:
		return false
	return not game.flames.has(game.idx(t.x, t.y))


func _spawn_crab(c: Dictionary) -> void:
	# Somewhere open on the middle rows, away from everyone.
	var opts: Array = []
	for y in range(3, Cfg.ROWS - 3):
		for x in range(1, Cfg.COLS - 1):
			var t := Vector2i(x, y)
			if not _crab_ok(t) or game.bomb_at.has(game.idx(x, y)):
				continue
			var near := false
			for f in game.fighters:
				if f.alive and (f.tile() - t).length() < 3.0:
					near = true
			if not near:
				opts.append(t)
	if opts.is_empty():
		c["dead"] = 2.0
		return
	var t: Vector2i = opts[_rng.randi() % opts.size()]
	c["tile"] = t
	c["to"] = t
	c["pos"] = Vector2(t)
	c["dir"] = DIRS[_rng.randi() % 4]
	c["dead"] = 0.0
	c["spawned"] = true
	if c["node"] != null:
		var n: Node3D = c["node"]
		n.visible = true
		n.rotation = Vector3.ZERO


func _step_crabs(dt: float) -> void:
	for c in crabs:
		if c["dead"] > 0.0:
			c["dead"] -= dt
			if c["dead"] <= 0.0:
				_spawn_crab(c)
			continue
		if not c["spawned"]:
			continue
		var to: Vector2i = c["to"]
		var pos: Vector2 = c["pos"]
		pos = pos.move_toward(Vector2(to), CRAB_SPEED * dt)
		c["pos"] = pos
		if pos.distance_to(Vector2(to)) > 0.001:
			continue
		c["tile"] = to
		# At a tile centre: carry on, shove a bomb, or pick another lane.
		var order: Array = [c["dir"]]
		var others: Array = DIRS.duplicate()
		others.shuffle()
		if _rng.randf() < 0.25:
			order = others
		else:
			order.append_array(others)
		for d in order:
			var n: Vector2i = to + d
			if not _crab_ok(n):
				continue
			var k: int = game.idx(n.x, n.y)
			if game.bomb_at.has(k):
				var bomb: Dictionary = game.bomb_at[k]
				if bomb["fuse"] < CRAB_MIN_FUSE or not game.push_bomb(bomb, d):
					continue
				if not game.smoke:
					game.fx.crate_dust(game.tile_pos(n.x, n.y))
			c["dir"] = d
			c["to"] = n
			break


func _kill_crab(c: Dictionary) -> void:
	c["dead"] = CRAB_RESPAWN
	c["spawned"] = false
	if c["node"] != null:
		var n: Node3D = c["node"]
		n.set_meta("fling", 0.0)


func _visual_crab(c: Dictionary, t: float) -> void:
	var n: Node3D = c["node"]
	if n == null:
		return
	if c["dead"] > 0.0:
		# Flung out of the blast, tumbling, then gone until it scuttles back.
		var f: float = n.get_meta("fling", 9.0)
		f += _pdt()
		n.set_meta("fling", f)
		n.visible = f < 0.9
		n.position += Vector3(0, (3.0 - f * 7.0) * _pdt(), 0)
		n.rotation.x += _pdt() * 12.0
		return
	var p: Vector2 = c["pos"]
	n.position = game.tile_pos(p.x, p.y)
	var d: Vector2i = c["dir"]
	# Crabs walk sideways: face across the direction of travel.
	n.rotation.y = lerp_angle(n.rotation.y, 0.0 if d.x != 0 else PI / 2.0, 0.2)
	var body := n.get_node("Body") as Node3D
	body.position.y = 0.02 + absf(sin(t * 16.0)) * 0.03
	body.rotation.z = sin(t * 16.0) * 0.08


func _pdt() -> float:
	return game.get_process_delta_time()


# ---- Haunted House: ghosts shove crates ----------------------------------------------

func _step_ghost(dt: float) -> void:
	if ghost["warn"] > 0.0:
		ghost["warn"] -= dt
		if ghost["warn"] <= 0.0:
			var f: Vector2i = ghost["from"]
			var t: Vector2i = ghost["to"]
			if game.cell_at(f.x, f.y) == SOFT and _ghost_dest_ok(t):
				game.move_crate(f, t)
				if not game.smoke:
					game.audio.play("wall_slam", -12.0, 0.15)
		return
	if game.sudden_death:
		return
	ghost["t"] -= dt
	if ghost["t"] > 0.0:
		return
	ghost["t"] = GHOST_EVERY
	var opts: Array = []
	for y in range(1, Cfg.ROWS - 1):
		for x in range(1, Cfg.COLS - 1):
			if game.cell_at(x, y) != SOFT or not _tile_clear_of_fighters(Vector2i(x, y), 2):
				continue
			for d in DIRS:
				var t: Vector2i = Vector2i(x, y) + d
				if _ghost_dest_ok(t):
					opts.append([Vector2i(x, y), t])
	if opts.is_empty():
		return
	var pick: Array = opts[_rng.randi() % opts.size()]
	ghost["from"] = pick[0]
	ghost["to"] = pick[1]
	ghost["warn"] = GHOST_WARN
	if not game.smoke:
		game.audio.play("ghost", 0.0, 0.1)


func _ghost_dest_ok(t: Vector2i) -> bool:
	if t.x < 1 or t.y < 1 or t.x > Cfg.COLS - 2 or t.y > Cfg.ROWS - 2:
		return false
	if not game.clock.is_empty() and t in game.clock["cells"]:
		return false
	return _tile_clear(t, 0)


func _visual_ghost(t: float) -> void:
	if _ghost_node == null:
		return
	var on: bool = ghost["warn"] > 0.0
	_ghost_node.visible = on
	_ghost_mark.visible = on
	if not on:
		return
	var f: Vector2i = ghost["from"]
	var to: Vector2i = ghost["to"]
	var k: float = 1.0 - ghost["warn"] / GHOST_WARN
	var a: Vector3 = game.tile_pos(f.x, f.y)
	var b: Vector3 = game.tile_pos(to.x, to.y)
	# Drifts in behind the crate, leans into it, then pushes.
	var behind := a - (b - a) * 0.55
	_ghost_node.position = behind.lerp(a - (b - a) * 0.2, minf(1.0, k * 1.5)) + Vector3(0, 0.55 + sin(t * 4.0) * 0.08, 0)
	_ghost_node.rotation.y = atan2(b.x - a.x, b.z - a.z)
	_ghost_node.scale = Vector3.ONE * minf(1.0, k * 5.0)
	_ghost_mark.position = b + Vector3(0, 0.03, 0)
	_ghost_mark.scale = Vector3.ONE * (0.85 + 0.1 * sin(t * 10.0))


# ---- Haunted House: the witch flies a circuit --------------------------------------------

func _visual_witch(delta: float, t: float) -> void:
	if game.hazards.is_empty():
		return
	var h: Dictionary = game.hazards[0]
	var n: Node3D = h["node"]
	if n == null or not is_instance_valid(n):
		return
	var winding: bool = game.hazard_target.x >= 0
	if not winding and game.phase == "play":
		_witch_angle += delta * WITCH_SPEED
	elif game.phase != "play":
		_witch_angle = lerp_angle(_witch_angle, -PI / 2.0, clampf(delta * 2.0, 0.0, 1.0))   # waits at the far side
	var p := Vector3(cos(_witch_angle) * WITCH_ORBIT.x, WITCH_HEIGHT + sin(t * 1.7) * 0.15, WITCH_CENTRE_Z + sin(_witch_angle) * WITCH_ORBIT.y)
	# Over the near rows she fades to half, so she never hides a fighter.
	var fade := clampf(p.z / 2.0, 0.0, 1.0) * 0.5
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).transparency = fade
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = p
	var face: float
	if winding:
		var tgt: Vector3 = game.tile_pos(game.hazard_target.x, game.hazard_target.y)
		face = atan2(tgt.x - p.x, tgt.z - p.z)
	else:
		face = atan2(-sin(_witch_angle) * WITCH_ORBIT.x, cos(_witch_angle) * WITCH_ORBIT.y)
	n.rotation.y = lerp_angle(n.rotation.y, face, clampf(delta * 5.0, 0.0, 1.0))
	n.rotation.z = 0.0 if winding else -0.18
	if not n.has_node("Broom"):
		var broom := MeshInstance3D.new()
		broom.name = "Broom"
		broom.mesh = _broom_mesh()
		broom.position = Vector3(0, 0.22, 0)
		n.add_child(broom)
		# The hazard reads like a fighter: a red outline and rim, and a trail
		# of green sparks off the broom.
		var line := ShaderMaterial.new()
		var ls := Shader.new()
		ls.code = Fighter.OUTLINE_SHADER
		line.shader = ls
		line.set_shader_parameter("line_col", Color(1.0, 0.28, 0.2))
		line.set_shader_parameter("thick", 0.03)
		var rim := ShaderMaterial.new()
		var rs := Shader.new()
		rs.code = Fighter.RIM_SHADER
		rim.shader = rs
		rim.set_shader_parameter("rim_col", Color(1.0, 0.35, 0.25))
		rim.set_shader_parameter("strength", 0.8)
		line.next_pass = rim
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = line
		var trail := CPUParticles3D.new()
		trail.local_coords = false
		trail.amount = 24
		trail.lifetime = 0.8
		trail.position = Vector3(0, 0.22, -0.8)
		var tq := QuadMesh.new()
		tq.size = Vector2(0.14, 0.14)
		trail.mesh = tq
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		tm.vertex_color_use_as_albedo = true
		tm.albedo_texture = Art.soft_dot()
		trail.material_override = tm
		trail.gravity = Vector3(0, -0.4, 0)
		trail.initial_velocity_min = 0.0
		trail.initial_velocity_max = 0.2
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.6, 1.0, 0.6, 0.9), Color(0.3, 1.0, 0.5, 0.0)])
		trail.color_ramp = g
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(trail)
	# Her arc height uses this tile; keep it to the nearest one under her.
	h["pos"] = Vector2i(clampi(roundi(p.x + (Cfg.COLS - 1) * 0.5), 0, Cfg.COLS - 1), clampi(roundi(p.z + (Cfg.ROWS - 1) * 0.5), 0, Cfg.ROWS - 1))


# ---- Factory: presses ----------------------------------------------------------------

func _step_presses(dt: float) -> void:
	if game.sudden_death:
		return
	for p in presses:
		p["t"] += dt
		if p["t"] < PRESS_PERIOD:
			continue
		p["t"] -= PRESS_PERIOD
		var t: Vector2i = p["tile"]
		var k: int = game.idx(t.x, t.y)
		for f in game.fighters:
			if f.alive and f.tile() == t:
				game.crush(f)
		if game.bomb_at.has(k):
			var b: Dictionary = game.bomb_at[k]
			b["fuse"] = minf(b["fuse"], Cfg.CHAIN_DELAY)
		if game.pickups.has(k):
			game._remove_pickup(k)
		for cr in crabs:
			if cr["tile"] == t:
				_kill_crab(cr)
		if not game.smoke:
			game.fx.shake = minf(0.45, game.fx.shake + 0.12)
			game.fx.crate_dust(game.tile_pos(t.x, t.y))
			game.audio.play("press", 0.0, 0.06)


## A crusher: two hydraulic steel jaws set in the pillars either side of the
## tile. Nothing hangs over the tile, so it never hides who is standing there.
## The bed is striped so you learn the tile; red lamps and twitching jaws warn.
func _build_press(p: Dictionary) -> void:
	var t: Vector2i = p["tile"]
	var n := Node3D.new()
	n.position = game.tile_pos(t.x, t.y)
	_root.add_child(n)
	var bed := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(0.96, 0.96)
	bed.mesh = q
	var bm := ShaderMaterial.new()
	bm.shader = LA._shader("press_bed", PRESS_BED_SHADER)
	bed.material_override = bm
	bed.position.y = 0.014
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(bed)
	var jaws: Array = []
	var lamps: Array = []
	for side in [-1.0, 1.0]:
		var jaw := Node3D.new()
		n.add_child(jaw)
		var jm := MeshInstance3D.new()
		var parts: Array = [
			[LA.box(Vector3(0.14, 0.78, 0.86), 0.02), LA.xf(Vector3(0, 0.41, 0)), Color("4a525e")],
			[LA.box(Vector3(0.02, 0.7, 0.8)), LA.xf(Vector3(-side * 0.075, 0.41, 0)), LA.metal(Color("9aa2ac"))],
			[LA.cyl(0.05, 0.05, 0.5, 10), LA.xf(Vector3(side * 0.28, 0.25, -0.22), Vector3(0, 0, PI / 2.0)), LA.metal(Color("c0c6ce"))],
			[LA.cyl(0.05, 0.05, 0.5, 10), LA.xf(Vector3(side * 0.28, 0.25, 0.22), Vector3(0, 0, PI / 2.0)), LA.metal(Color("c0c6ce"))],
		]
		for k in 4:
			parts.append([LA.box(Vector3(0.03, 0.14, 0.2)), LA.xf(Vector3(-side * 0.075, 0.68, -0.3 + k * 0.2), Vector3(0.6, 0, 0)), Color("e0b020") if k % 2 == 0 else Color("161616")])
		jm.mesh = LA.build(parts, LA.vmat("crusher_jaw", 0.5, 0.0, 0.2))
		jaw.add_child(jm)
		jaws.append(jaw)
		var lamp := MeshInstance3D.new()
		lamp.mesh = LA.sphere(0.075, 10, 6)
		lamp.material_override = LA.glow_mat(Color(1.0, 0.15, 0.1), 4.0)
		lamp.position = Vector3(side * 1.0, 1.04, 0.3)
		n.add_child(lamp)
		lamps.append(lamp)
	var mark := _mark(Color(1.0, 0.25, 0.15))
	mark.position = n.position + Vector3(0, 0.025, 0)
	p["node"] = n
	p["bed"] = bm
	p["jaws"] = jaws
	p["lamps"] = lamps
	p["mark"] = mark


const PRESS_BED_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform float warn = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = max(abs(p.x), abs(p.y));
	float stripe = step(0.5, fract((UV.x + UV.y) * 4.0));
	vec3 col = mix(vec3(0.85, 0.65, 0.08), vec3(0.06), stripe);
	float border = smoothstep(0.78, 0.82, edge) * (1.0 - smoothstep(0.95, 0.99, edge));
	float inner = 1.0 - smoothstep(0.78, 0.82, edge);
	float pulse = warn * (0.55 + 0.45 * sin(TIME * 14.0));
	ALBEDO = mix(col, vec3(1.0, 0.12, 0.06), inner * pulse);
	ALPHA = border * 0.85 + inner * max(0.08, pulse * 0.75);
	ROUGHNESS = 0.6;
}
"""


func _visual_presses(_delta: float, t: float) -> void:
	for p in presses:
		if not p.has("jaws"):
			continue
		var c: float = p["t"]
		var left := PRESS_PERIOD - c
		# Inner face distance from the tile centre: 0.47 open, 0.07 shut.
		var gap := 0.47
		if c < 0.14:
			gap = 0.07                                   # just slammed
		elif c < 0.14 + PRESS_LIFT:
			var k := (c - 0.14) / PRESS_LIFT
			gap = lerpf(0.07, 0.47, k * k * (3.0 - 2.0 * k))   # opening
		elif left < PRESS_WARN and not game.sudden_death:
			var k2 := 1.0 - left / PRESS_WARN
			# Closing in three hydraulic steps, juddering between them.
			gap = 0.47 - 0.07 * floorf(k2 * 3.0) / 2.0 + sin(t * 45.0) * 0.012 * k2
		if left < 0.1 and not game.sudden_death:
			gap = lerpf(0.07, 0.42, left / 0.1)            # the slam
		var i := 0
		for jaw in p["jaws"]:
			var side := -1.0 if i == 0 else 1.0
			(jaw as Node3D).position.x = side * (gap + 0.07)
			i += 1
		var warn: bool = left < PRESS_WARN and not game.sudden_death
		var on: bool = warn and fmod(t * 6.0, 1.0) < 0.6
		for lamp in p["lamps"]:
			(lamp as Node3D).visible = on
		var bedm: ShaderMaterial = p["bed"]
		bedm.set_shader_parameter("warn", 1.0 if warn else 0.0)
		var mark: MeshInstance3D = p["mark"]
		mark.visible = warn
		mark.scale = Vector3.ONE * (0.85 + 0.1 * sin(t * 12.0))


# ---- Factory: the lever ---------------------------------------------------------------

func _build_lever() -> void:
	var n := Node3D.new()
	n.position = game.tile_pos(LEVER_WALL.x, LEVER_WALL.y) + Vector3(0, 1.04, 0.2)
	_root.add_child(n)
	var base := MeshInstance3D.new()
	base.mesh = LA.build([
		[LA.box(Vector3(0.5, 0.36, 0.2), 0.03), LA.xf(Vector3(0, 0.18, 0)), Color("2a2e36")],
		[LA.box(Vector3(0.44, 0.06, 0.22)), LA.xf(Vector3(0, 0.32, 0)), Color("e0b020")],
		[LA.box(Vector3(0.16, 0.1, 0.03)), LA.xf(Vector3(-0.12, 0.17, 0.11)), LA.lit(Color("3df2a0"))],
		[LA.box(Vector3(0.16, 0.1, 0.03)), LA.xf(Vector3(0.12, 0.17, 0.11)), LA.lit(Color("ff5030"))],
	], LA.vmat("lever_base", 0.5, 0.0, 0.2, 3.0))
	n.add_child(base)
	var handle := Node3D.new()
	handle.name = "Handle"
	handle.position = Vector3(0, 0.36, 0)
	n.add_child(handle)
	var hm := MeshInstance3D.new()
	hm.mesh = LA.build([
		[LA.cyl(0.035, 0.035, 0.55, 8), LA.xf(Vector3(0, 0.27, 0)), LA.metal(Color("a0a6b0"))],
		[LA.sphere(0.09, 12, 8), LA.xf(Vector3(0, 0.56, 0)), Color("d02a20")],
	], LA.vmat("lever_handle", 0.4, 0.0, 0.1))
	handle.add_child(hm)
	handle.rotation.x = 0.6
	lever["node"] = n


func _flip_lever() -> void:
	lever["cool"] = LEVER_COOL
	lever["on"] = not lever["on"]
	var swap := {Levels.BELT_R: Levels.BELT_L, Levels.BELT_L: Levels.BELT_R, Levels.BELT_D: Levels.BELT_U, Levels.BELT_U: Levels.BELT_D}
	for i in game.rules.size():
		var r: int = game.rules[i]
		if swap.has(r):
			game.rules[i] = swap[r]
	if game.smoke:
		return
	_set_belt_dir(-1.0 if lever["on"] else 1.0)
	game.audio.play("lever", 0.0)
	game._show_msg("BELTS REVERSED", 1.1)


func _set_belt_dir(d: float) -> void:
	LA.belt_mat().set_shader_parameter("dir", d)


func _visual_lever(delta: float) -> void:
	var n: Node3D = lever["node"]
	if n == null:
		return
	var h := n.get_node("Handle") as Node3D
	h.rotation.x = lerpf(h.rotation.x, -0.6 if lever["on"] else 0.6, clampf(delta * 12.0, 0.0, 1.0))


# ---- Models ------------------------------------------------------------------------

func _mark(c: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(0.95, 0.95)
	m.mesh = q
	m.material_override = LA.ring_mat(c, 0.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	_root.add_child(m)
	return m


func _make_beaver() -> Node3D:
	var fur := Color("7a5032")
	var dark := Color("4a2e1c")
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = LA.build([
		[LA.sphere(0.22, 14, 8), LA.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.0, 1.25, 0.95)), fur],
		[LA.sphere(0.15, 12, 8), LA.xf(Vector3(0, 0.6, 0.06)), fur],
		[LA.sphere(0.07, 10, 6), LA.xf(Vector3(0, 0.56, 0.18)), Color("b08a6a")],
		[LA.sphere(0.03, 8, 4), LA.xf(Vector3(0, 0.6, 0.24)), Color("1a1010")],
		[LA.box(Vector3(0.07, 0.06, 0.02)), LA.xf(Vector3(0, 0.5, 0.235)), Color("f0eadc")],
		[LA.sphere(0.025, 8, 4), LA.xf(Vector3(-0.07, 0.67, 0.17)), Color("120a0a")],
		[LA.sphere(0.025, 8, 4), LA.xf(Vector3(0.07, 0.67, 0.17)), Color("120a0a")],
		[LA.sphere(0.04, 8, 4), LA.xf(Vector3(-0.11, 0.73, 0.0)), dark],
		[LA.sphere(0.04, 8, 4), LA.xf(Vector3(0.11, 0.73, 0.0)), dark],
		[LA.box(Vector3(0.22, 0.04, 0.34), 0.02), LA.xf(Vector3(0, 0.1, -0.3), Vector3(0.3, 0, 0)), Color("3a2a22")],
		[LA.cyl(0.32, 0.36, 0.08, 14), LA.xf(Vector3(0, 0.0, 0)), Color("5a4028")],
	], LA.vmat("beaver", 0.85, 0.0, 0.35))
	n.add_child(body)
	var log_n := MeshInstance3D.new()
	log_n.name = "Log"
	log_n.mesh = LA.build([[LA.cyl(0.07, 0.07, 0.5, 10), LA.xf(Vector3.ZERO, Vector3(0, 0, PI / 2.0)), Color("6a4628")],
		[LA.cyl(0.06, 0.06, 0.505, 10), LA.xf(Vector3.ZERO, Vector3(0, 0, PI / 2.0)), Color("c9a070")]], LA.vmat("beaver_log", 0.85, 0.0, 0.3))
	log_n.position = Vector3(0, 0.72, 0.12)
	n.add_child(log_n)
	return n


func _make_crab() -> Node3D:
	var shell := Color("d0502e")
	var dark := Color("8a2a18")
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Body"
	var parts: Array = [
		[LA.sphere(0.18, 14, 8), LA.xf(Vector3(0, 0.14, 0), Vector3.ZERO, Vector3(1.2, 0.55, 0.9)), shell],
		[LA.sphere(0.035, 8, 4), LA.xf(Vector3(-0.06, 0.26, 0.12)), Color("101010")],
		[LA.sphere(0.035, 8, 4), LA.xf(Vector3(0.06, 0.26, 0.12)), Color("101010")],
		[LA.cyl(0.012, 0.012, 0.08, 6), LA.xf(Vector3(-0.06, 0.21, 0.12)), dark],
		[LA.cyl(0.012, 0.012, 0.08, 6), LA.xf(Vector3(0.06, 0.21, 0.12)), dark],
	]
	for s in [-1.0, 1.0]:
		parts.append([LA.sphere(0.07, 10, 6), LA.xf(Vector3(s * 0.24, 0.16, 0.14), Vector3.ZERO, Vector3(1.0, 0.7, 1.3)), shell])
		parts.append([LA.box(Vector3(0.05, 0.03, 0.12)), LA.xf(Vector3(s * 0.16, 0.13, 0.1), Vector3(0, s * 0.6, 0)), dark])
		for k in 3:
			parts.append([LA.box(Vector3(0.16, 0.025, 0.025)), LA.xf(Vector3(s * 0.24, 0.07, -0.06 + k * 0.07), Vector3(0, 0, s * -0.5)), dark])
	body.mesh = LA.build(parts, LA.vmat("crab", 0.6, 0.0, 0.2))
	n.add_child(body)
	n.scale = Vector3.ONE * 1.15
	n.visible = false
	return n


func _broom_mesh() -> Mesh:
	return LA.build([
		[LA.cyl(0.022, 0.022, 1.3, 8), LA.xf(Vector3(0, 0, 0), Vector3(PI / 2.0, 0, 0)), Color("6a4a2a")],
		[LA.cone(0.13, 0.36, 10), LA.xf(Vector3(0, 0, -0.78), Vector3(-PI / 2.0, 0, 0)), Color("c8a060")],
		[LA.cyl(0.05, 0.05, 0.05, 10), LA.xf(Vector3(0, 0, -0.6), Vector3(PI / 2.0, 0, 0)), Color("7a37d6")],
	], LA.vmat("broom", 0.8, 0.0, 0.3))
