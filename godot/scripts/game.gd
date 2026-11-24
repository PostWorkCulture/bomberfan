extends Node3D
## Bomber Fan — Godot vertical slice.
## Forest arena, you vs three bots, bombs, chain blasts, crates and the
## Bomb Up / Fire Up / Speed pick-ups, first to Cfg.WINS_NEEDED rounds.
## Rules and tuning follow the browser build (../index.html); see ../DESIGN.md.
##
## Run with `-- --smoke` for a headless bots-only test that prints a summary
## and exits non-zero if the game did not play properly.

const Cfg := preload("res://scripts/config.gd")
const Fighter := preload("res://scripts/fighter.gd")
const BotBrain := preload("res://scripts/bot_brain.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")

const EMPTY := 0
const HARD := 1
const SOFT := 2
const SAFE := 999.0
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SPAWNS := [Vector2i(1, 1), Vector2i(13, 11), Vector2i(13, 1), Vector2i(1, 11)]

const ROSTER := [
	{"id": "ninja", "name": "NINJA", "color": Color(1.0, 0.298, 0.247)},
	{"id": "orc", "name": "ORC", "color": Color(0.302, 0.561, 1.0)},
	{"id": "bunny", "name": "BUNNY", "color": Color(0.282, 0.863, 0.408)},
	{"id": "dino", "name": "DINO", "color": Color(1.0, 0.835, 0.18)},
]

# Forest palette (LEVELS[0] in index.html)
const SKY := Color(0.055, 0.102, 0.071)
const GROUND := Color(0.227, 0.502, 0.188)
const GROUND_ALT := Color(0.205, 0.46, 0.17)
const CRATE := Color(0.788, 0.529, 0.247)
const CRATE_BAND := Color(0.659, 0.416, 0.149)
const HARD_COL := Color(0.604, 0.639, 0.678)
const HARD_TOP := Color(0.824, 0.851, 0.875)
const BORDER := Color(0.361, 0.4, 0.447)
const BOMB_COL := Color(0.063, 0.075, 0.094)

const PICKUP_LOOK := {
	"bomb": {"color": Color(0.23, 0.42, 1.0), "letter": "B"},
	"fire": {"color": Color(1.0, 0.35, 0.12), "letter": "F"},
	"speed": {"color": Color(0.25, 0.82, 0.42), "letter": "S"},
}

var cells := PackedInt32Array()
var crate_nodes := {}
var bombs: Array = []
var bomb_at := {}
var flames := {}
var pickups := {}
var fighters: Array = []
var brains := {}

var phase := "intro"
var phase_t := 0.0
var round_t := 0.0
var round_no := 0
var wins := [0, 0, 0, 0]
var end_check_t := -1.0
var msg_text := ""
var msg_t := 0.0

var rng := RandomNumberGenerator.new()
var smoke := false
var demo := false   # `-- --demo`: four bots, full visuals (attract mode / CI screenshots)
var gallery := false   # `-- --gallery`: close-up of the fighters for CI checks
var human_pid := 0
var stats := {"rounds": 0, "draws": 0, "deaths": 0, "self_kills": 0,
	"bombs": 0, "crates": 0, "pickups": 0, "wins": [0, 0, 0, 0]}

var static_root: Node3D
var round_root: Node3D
var camera: Camera3D
var hud_round: Label
var hud_msg: Label
var hud_scores_box: HBoxContainer
var hud_scores: Array = []
var touch = null

var _acc := 0.0
var _time := 0.0
var _want_bomb := false
var _mats := {}
var _crate_mesh: BoxMesh
var _band_mesh: BoxMesh
var _bomb_mesh: SphereMesh
var _fuse_mesh: CylinderMesh
var _spark_mesh: SphereMesh
var _flame_mesh: BoxMesh
var _pickup_mesh: BoxMesh


func _ready() -> void:
	smoke = "--smoke" in OS.get_cmdline_user_args()
	demo = "--demo" in OS.get_cmdline_user_args()
	gallery = "--gallery" in OS.get_cmdline_user_args()
	rng.randomize()
	if smoke:
		rng.seed = 20261124
	_setup_input()
	_build_meshes()
	_build_environment()
	_build_static_arena()
	_build_hud()
	_create_fighters()
	start_round()
	if smoke:
		_run_smoke()
	elif gallery:
		_setup_gallery()


# ---- Grid helpers ---------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * Cfg.COLS + x


func cell_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= Cfg.COLS or y >= Cfg.ROWS:
		return HARD
	return cells[idx(x, y)]


func tile_pos(x: float, y: float) -> Vector3:
	return Vector3(x - (Cfg.COLS - 1) * 0.5, 0.0, y - (Cfg.ROWS - 1) * 0.5)


## Every tile a bomb's cross reaches: stops at walls, stops ON a crate.
func blast_cells(x: int, y: int, fire: int) -> Array:
	var out: Array = [Vector2i(x, y)]
	for d in DIRS:
		for s in range(1, fire + 1):
			var cx: int = x + d.x * s
			var cy: int = y + d.y * s
			var c := cell_at(cx, cy)
			if c == HARD:
				break
			out.append(Vector2i(cx, cy))
			if c == SOFT:
				break
	return out


## Seconds until each tile burns (SAFE if never), with chain reactions.
## `extra` is an imagined bomb {x, y, fire, fuse} for "what if I lay one here".
func compute_danger(extra: Dictionary) -> PackedFloat32Array:
	var danger := PackedFloat32Array()
	danger.resize(Cfg.COLS * Cfg.ROWS)
	danger.fill(SAFE)
	var list: Array = []
	for b in bombs:
		if b["alive"]:
			list.append({"x": b["x"], "y": b["y"], "fire": b["fire"], "t": b["fuse"]})
	if not extra.is_empty():
		list.append({"x": extra["x"], "y": extra["y"], "fire": extra["fire"], "t": extra["fuse"]})
	var by_tile := {}
	for e in list:
		by_tile[idx(e["x"], e["y"])] = e
	var changed := true
	var guard := 0
	while changed and guard < 16:
		changed = false
		guard += 1
		for e in list:
			for c in blast_cells(e["x"], e["y"], e["fire"]):
				var k := idx(c.x, c.y)
				if by_tile.has(k):
					var o: Dictionary = by_tile[k]
					var t2: float = e["t"] + Cfg.CHAIN_DELAY
					if t2 < o["t"]:
						o["t"] = t2
						changed = true
	for e in list:
		for c in blast_cells(e["x"], e["y"], e["fire"]):
			var k := idx(c.x, c.y)
			danger[k] = minf(danger[k], e["t"])
	for k in flames.keys():
		danger[k] = 0.0
	return danger


# ---- Setup --------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"bomb": [KEY_SPACE, KEY_ENTER, KEY_J], "restart": [KEY_R],
	}
	var pads := {
		"move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT,
		"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN,
		"bomb": JOY_BUTTON_A, "restart": JOY_BUTTON_START,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		var jb := InputEventJoypadButton.new()
		jb.button_index = pads[action]
		InputMap.action_add_event(action, jb)
	var axes := {
		"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
	}
	for action in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[action][0]
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)


func _mat(c: Color, rough := 0.85, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), rough, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


func _mesh(parent: Node, mesh: Mesh, m: Material, pos: Vector3, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_meshes() -> void:
	_crate_mesh = BoxMesh.new()
	_crate_mesh.size = Vector3(0.86, 0.8, 0.86)
	_band_mesh = BoxMesh.new()
	_band_mesh.size = Vector3(0.88, 0.12, 0.88)
	_bomb_mesh = SphereMesh.new()
	_bomb_mesh.radius = 0.34
	_bomb_mesh.height = 0.68
	_fuse_mesh = CylinderMesh.new()
	_fuse_mesh.top_radius = 0.04
	_fuse_mesh.bottom_radius = 0.05
	_fuse_mesh.height = 0.16
	_spark_mesh = SphereMesh.new()
	_spark_mesh.radius = 0.07
	_spark_mesh.height = 0.14
	_flame_mesh = BoxMesh.new()
	_flame_mesh.size = Vector3(0.94, 0.5, 0.94)
	_pickup_mesh = BoxMesh.new()
	_pickup_mesh.size = Vector3(0.62, 0.12, 0.62)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.8)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 44.0
	add_child(camera)
	camera.position = Vector3(0.0, 15.2, 6.6)
	camera.look_at(Vector3(0.0, 0.0, 0.55), Vector3.UP)
	camera.current = true


func _build_static_arena() -> void:
	static_root = Node3D.new()
	add_child(static_root)
	round_root = Node3D.new()
	add_child(round_root)
	var tile_mesh := PlaneMesh.new()
	tile_mesh.size = Vector2(1.0, 1.0)
	var hard_mesh := BoxMesh.new()
	hard_mesh.size = Vector3(0.96, 0.9, 0.96)
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.8, 0.06, 0.8)
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			var p := tile_pos(x, y)
			var border: bool = x == 0 or y == 0 or x == Cfg.COLS - 1 or y == Cfg.ROWS - 1
			var pillar: bool = not border and x % 2 == 0 and y % 2 == 0
			if border or pillar:
				_mesh(static_root, hard_mesh, _mat(BORDER if border else HARD_COL), p + Vector3(0, 0.45, 0))
				if pillar:
					_mesh(static_root, cap_mesh, _mat(HARD_TOP), p + Vector3(0, 0.93, 0))
			else:
				_mesh(static_root, tile_mesh, _mat(GROUND if (x + y) % 2 == 0 else GROUND_ALT), p, false)
	var base := BoxMesh.new()
	base.size = Vector3(Cfg.COLS + 0.6, 0.4, Cfg.ROWS + 0.6)
	_mesh(static_root, base, _mat(BORDER.darkened(0.4)), Vector3(0, -0.21, 0), false)
	# A ring of pines and toadstools beyond the walls
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.1
	trunk.height = 0.4
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 0.5
	crown.height = 1.3
	var pine_rng := RandomNumberGenerator.new()
	pine_rng.seed = 7
	for i in 26:
		var a := TAU * i / 26.0
		var p := Vector3(cos(a) * 10.2, 0.0, sin(a) * 8.6)
		var s := pine_rng.randf_range(0.8, 1.35)
		var pine := Node3D.new()
		pine.position = p
		pine.scale = Vector3.ONE * s
		static_root.add_child(pine)
		_mesh(pine, trunk, _mat(Color(0.36, 0.24, 0.14)), Vector3(0, 0.2, 0))
		_mesh(pine, crown, _mat(Color(0.12, 0.33, 0.17)), Vector3(0, 1.0, 0))


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_scores_box = HBoxContainer.new()
	hud_scores_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_scores_box)
	hud_scores_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud_scores_box.offset_top = 10.0
	hud_scores_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_scores_box.add_theme_constant_override("separation", 34)
	hud_round = _label(20, Color(1.0, 0.96, 0.9))
	layer.add_child(hud_round)
	hud_round.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud_round.offset_top = 44.0
	hud_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg = _label(72, Color(1.0, 0.92, 0.5))
	layer.add_child(hud_msg)
	hud_msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not smoke and DisplayServer.is_touchscreen_available():
		touch = TouchControls.new()
		layer.add_child(touch)
	else:
		var hint := _label(16, Color(1, 1, 1, 0.7))
		hint.text = "Move: WASD / Arrows    Bomb: Space    Restart: R"
		layer.add_child(hint)
		hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		hint.offset_top = -34.0
		hint.offset_bottom = -8.0
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(font_size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, int(font_size / 6.0)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _create_fighters() -> void:
	human_pid = -1 if smoke or demo or gallery else 0
	for k in Cfg.MAX_PLAYERS:
		var f = Fighter.new()
		add_child(f)
		f.setup(self, k, ROSTER[k], k != human_pid)
		fighters.append(f)
		if f.is_bot:
			var b = BotBrain.new()
			b.setup(self, f, 1000 + k * 7919 + (0 if smoke else rng.randi() % 100000))
			brains[k] = b
		var l := _label(22, ROSTER[k]["color"])
		hud_scores_box.add_child(l)
		hud_scores.append(l)


# ---- Rounds ---------------------------------------------------------------------

func start_round() -> void:
	if wins.max() == 0:
		round_no = 1
	else:
		round_no += 1
	for c in round_root.get_children():
		c.queue_free()
	bombs.clear()
	bomb_at.clear()
	flames.clear()
	pickups.clear()
	crate_nodes.clear()
	_generate_cells()
	_build_crates()
	for k in fighters.size():
		fighters[k].spawn_at(SPAWNS[k])
		if brains.has(k):
			brains[k].reset()
	phase = "intro"
	phase_t = Cfg.ROUND_INTRO
	round_t = Cfg.ROUND_SECONDS
	end_check_t = -1.0
	msg_t = 0.0


func _generate_cells() -> void:
	cells.resize(Cfg.COLS * Cfg.ROWS)
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			var c := EMPTY
			if x == 0 or y == 0 or x == Cfg.COLS - 1 or y == Cfg.ROWS - 1 or (x % 2 == 0 and y % 2 == 0):
				c = HARD
			cells[idx(x, y)] = c
	# Keep each corner spawn and its two exits clear
	var reserved := {}
	for s in SPAWNS:
		reserved[s] = true
		for d in DIRS:
			reserved[s + d] = true
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			if cells[idx(x, y)] == EMPTY and not reserved.has(Vector2i(x, y)) \
					and rng.randf() < Cfg.SOFT_DENSITY:
				cells[idx(x, y)] = SOFT


func _build_crates() -> void:
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			if cells[idx(x, y)] != SOFT:
				continue
			var n := Node3D.new()
			n.position = tile_pos(x, y)
			round_root.add_child(n)
			_mesh(n, _crate_mesh, _mat(CRATE), Vector3(0, 0.4, 0))
			_mesh(n, _band_mesh, _mat(CRATE_BAND), Vector3(0, 0.4, 0))
			crate_nodes[idx(x, y)] = n


func _end_round(winner, why: String) -> void:
	phase = "outro"
	phase_t = Cfg.ROUND_OUTRO
	stats["rounds"] += 1
	if winner == null:
		stats["draws"] += 1
		_show_msg(why if why != "" else "DRAW", Cfg.ROUND_OUTRO)
		return
	wins[winner.pid] += 1
	stats["wins"][winner.pid] += 1
	winner.celebrate()
	var who: String = "YOU" if winner.pid == human_pid else winner.display_name
	if wins[winner.pid] >= Cfg.WINS_NEEDED:
		_show_msg("%s WIN%s THE MATCH!" % [who, "" if who == "YOU" else "S"], Cfg.ROUND_OUTRO)
	else:
		_show_msg("%s WIN%s THE ROUND" % [who, "" if who == "YOU" else "S"], Cfg.ROUND_OUTRO)


func _show_msg(text: String, secs: float) -> void:
	msg_text = text
	msg_t = secs


# ---- Simulation -------------------------------------------------------------------

func _process(delta: float) -> void:
	if smoke:
		return
	_time += delta
	if Input.is_action_just_pressed("restart"):
		wins = [0, 0, 0, 0]
		start_round()
	if Input.is_action_just_pressed("bomb"):
		_want_bomb = true
	if touch != null and touch.consume_bomb():
		_want_bomb = true
	_acc += minf(delta, Cfg.MAX_FRAME_DT)
	while _acc >= Cfg.FIXED_DT:
		sim_step(Cfg.FIXED_DT)
		_acc -= Cfg.FIXED_DT
	_update_visuals(delta)
	_update_hud()


func sim_step(dt: float) -> void:
	if msg_t > 0.0:
		msg_t -= dt
	match phase:
		"intro":
			phase_t -= dt
			_want_bomb = false
			if phase_t <= 0.0:
				phase = "play"
				_show_msg("GO!", 0.7)
		"play":
			round_t -= dt
			_step_fighters(dt)
			_step_bombs(dt)
			_step_flames(dt)
			_step_pickups(dt)
			_check_deaths()
			_check_round_end(dt)
		"outro":
			_step_flames(dt)
			phase_t -= dt
			if phase_t <= 0.0:
				if wins.max() >= Cfg.WINS_NEEDED:
					wins = [0, 0, 0, 0]
				start_round()


func _human_input() -> Array:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if touch != null:
		v += touch.vector
	if v.length() < 0.35:
		return [Vector2i.ZERO, Vector2i.ZERO]
	var sx := 1 if v.x > 0.0 else -1
	var sy := 1 if v.y > 0.0 else -1
	if absf(v.x) >= absf(v.y):
		return [Vector2i(sx, 0), Vector2i(0, sy) if absf(v.y) > 0.35 else Vector2i.ZERO]
	return [Vector2i(0, sy), Vector2i(sx, 0) if absf(v.x) > 0.35 else Vector2i.ZERO]


func _step_fighters(dt: float) -> void:
	for f in fighters:
		if not f.alive:
			continue
		if f.is_bot:
			var out: Dictionary = brains[f.pid].update(dt)
			f.step(dt, out["dir"], out["alt"], out["bomb"])
		else:
			var dirs := _human_input()
			var bomb := _want_bomb
			_want_bomb = false
			f.step(dt, dirs[0], dirs[1], bomb)


func try_place_bomb(f) -> bool:
	var t: Vector2i = f.tile()
	if cell_at(t.x, t.y) != EMPTY:
		return false
	var i := idx(t.x, t.y)
	if bomb_at.has(i) or f.active_bombs >= f.max_bombs:
		return false
	var b := {"x": t.x, "y": t.y, "fuse": Cfg.BOMB_FUSE, "fire": f.fire, "owner": f,
		"alive": true, "age": 0.0, "node": _make_bomb_node(t)}
	bombs.append(b)
	bomb_at[i] = b
	f.active_bombs += 1
	for o in fighters:
		if o.alive and o.overlaps_tile(t):
			o.ignore_bombs[i] = true
	stats["bombs"] += 1
	return true


func _make_bomb_node(t: Vector2i) -> Node3D:
	var n := Node3D.new()
	n.position = tile_pos(t.x, t.y)
	round_root.add_child(n)
	_mesh(n, _bomb_mesh, _mat(BOMB_COL, 0.35), Vector3(0, 0.36, 0))
	_mesh(n, _fuse_mesh, _mat(Color(0.82, 0.72, 0.52)), Vector3(0, 0.75, 0))
	_mesh(n, _spark_mesh, _mat(Color(1.0, 0.78, 0.25), 1.0, true), Vector3(0, 0.85, 0), false)
	return n


func _step_bombs(dt: float) -> void:
	for b in bombs.duplicate():
		if not b["alive"]:
			continue
		b["fuse"] -= dt
		b["age"] += dt
		if b["fuse"] <= 0.0:
			_explode(b)
	bombs = bombs.filter(func(e): return e["alive"])


func _explode(b: Dictionary) -> void:
	b["alive"] = false
	bomb_at.erase(idx(b["x"], b["y"]))
	var bomber = b["owner"]
	bomber.active_bombs = maxi(0, bomber.active_bombs - 1)
	var node: Node3D = b["node"]
	if is_instance_valid(node):
		node.queue_free()
	var centre := Vector2i(b["x"], b["y"])
	for c in blast_cells(b["x"], b["y"], b["fire"]):
		var ci := idx(c.x, c.y)
		_add_flame(c, bomber.pid, c == centre)
		if cells[ci] == SOFT:
			_break_crate(c)
		elif pickups.has(ci) and pickups[ci]["shield"] <= 0.0:
			_remove_pickup(ci)
		if bomb_at.has(ci):
			var o: Dictionary = bomb_at[ci]
			o["fuse"] = minf(o["fuse"], Cfg.CHAIN_DELAY)


func _add_flame(c: Vector2i, pid: int, centre: bool) -> void:
	var ci := idx(c.x, c.y)
	if flames.has(ci):
		flames[ci]["t"] = Cfg.BLAST_LIFE
		flames[ci]["pid"] = pid
		return
	var col := Color(1.0, 0.85, 0.35) if centre else Color(1.0, 0.5, 0.12)
	var n := _mesh(round_root, _flame_mesh, _mat(col, 1.0, true), tile_pos(c.x, c.y) + Vector3(0, 0.25, 0), false)
	flames[ci] = {"t": Cfg.BLAST_LIFE, "pid": pid, "node": n}


func _step_flames(dt: float) -> void:
	for k in flames.keys():
		var fl: Dictionary = flames[k]
		fl["t"] -= dt
		var node: Node3D = fl["node"]
		if fl["t"] <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			flames.erase(k)
		elif is_instance_valid(node):
			node.scale = Vector3(1.0, maxf(0.15, fl["t"] / Cfg.BLAST_LIFE), 1.0)


func _break_crate(c: Vector2i) -> void:
	var ci := idx(c.x, c.y)
	cells[ci] = EMPTY
	stats["crates"] += 1
	if crate_nodes.has(ci):
		var n: Node3D = crate_nodes[ci]
		if is_instance_valid(n):
			n.queue_free()
		crate_nodes.erase(ci)
	var r := rng.randf()
	var id := ""
	if r < Cfg.DROP_BOMB:
		id = "bomb"
	elif r < Cfg.DROP_BOMB + Cfg.DROP_FIRE:
		id = "fire"
	elif r < Cfg.DROP_BOMB + Cfg.DROP_FIRE + Cfg.DROP_SPEED:
		id = "speed"
	if id != "":
		_spawn_pickup(c, id)


func _spawn_pickup(c: Vector2i, id: String) -> void:
	var look: Dictionary = PICKUP_LOOK[id]
	var n := Node3D.new()
	n.position = tile_pos(c.x, c.y)
	round_root.add_child(n)
	_mesh(n, _pickup_mesh, _mat(look["color"], 0.5), Vector3(0, 0.08, 0))
	var l := Label3D.new()
	l.text = look["letter"]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 96
	l.pixel_size = 0.005
	l.outline_size = 20
	l.position = Vector3(0, 0.45, 0)
	n.add_child(l)
	# The blast that revealed it cannot also destroy it
	pickups[idx(c.x, c.y)] = {"id": id, "node": n, "shield": Cfg.BLAST_LIFE + 0.05}


func _remove_pickup(ci: int) -> void:
	var node: Node3D = pickups[ci]["node"]
	if is_instance_valid(node):
		node.queue_free()
	pickups.erase(ci)


func _step_pickups(dt: float) -> void:
	for k in pickups.keys():
		pickups[k]["shield"] -= dt
	for f in fighters:
		if not f.alive:
			continue
		var t: Vector2i = f.tile()
		var ci := idx(t.x, t.y)
		if not pickups.has(ci):
			continue
		match pickups[ci]["id"]:
			"bomb":
				f.max_bombs = mini(f.max_bombs + 1, Cfg.MAX_BOMBS)
			"fire":
				f.fire = mini(f.fire + 1, Cfg.MAX_FIRE)
			"speed":
				f.speed = minf(f.speed + Cfg.SPEED_STEP, Cfg.MAX_SPEED)
				f.speed_t = Cfg.SPEED_DURATION
		stats["pickups"] += 1
		_remove_pickup(ci)


func _check_deaths() -> void:
	for f in fighters:
		if not f.alive:
			continue
		var t: Vector2i = f.tile()
		var ci := idx(t.x, t.y)
		if flames.has(ci):
			f.die()
			stats["deaths"] += 1
			if flames[ci]["pid"] == f.pid:
				stats["self_kills"] += 1


func _check_round_end(dt: float) -> void:
	if round_t <= 0.0:
		_end_round(null, "TIME UP - DRAW")
		return
	var alive: Array = fighters.filter(func(f): return f.alive)
	if alive.size() > 1:
		return
	if end_check_t < 0.0:
		end_check_t = 0.45   # let simultaneous deaths land before calling it
	end_check_t -= dt
	if end_check_t <= 0.0:
		_end_round(alive[0] if alive.size() == 1 else null, "")


# ---- Presentation -----------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	for f in fighters:
		f.update_visual(delta)
	for b in bombs:
		var node: Node3D = b["node"]
		if is_instance_valid(node):
			var rate: float = 10.0 + (Cfg.BOMB_FUSE - b["fuse"]) * 8.0
			node.scale = Vector3.ONE * (1.0 + 0.07 * sin(b["age"] * rate))
	for k in pickups.keys():
		var node: Node3D = pickups[k]["node"]
		if is_instance_valid(node):
			node.position.y = 0.04 + 0.04 * sin(_time * 4.0 + k)


func _update_hud() -> void:
	for k in fighters.size():
		var f = fighters[k]
		var nm: String = f.display_name + (" (YOU)" if k == human_pid else "")
		var lab: Label = hud_scores[k]
		lab.text = "%s  %d" % [nm, wins[k]]
		lab.modulate = Color(1, 1, 1, 1.0 if f.alive else 0.45)
	var secs := maxi(0, ceili(round_t))
	hud_round.text = "ROUND %d     %d:%02d     FIRST TO %d" % [round_no, floori(secs / 60.0), secs % 60, Cfg.WINS_NEEDED]
	if phase == "intro":
		var n := ceili(phase_t - 0.35)
		hud_msg.text = str(n) if n >= 1 else "GO!"
	elif msg_t > 0.0:
		hud_msg.text = msg_text
	else:
		hud_msg.text = ""


# ---- CI gallery: the four fighters up close, two idling and two running

func _setup_gallery() -> void:
	for c in round_root.get_children():
		c.queue_free()
	for k in fighters.size():
		var f = fighters[k]
		f.gx = 5.5 + k
		f.gy = 6.0
		f.face_yaw = 0.0
		f.moving = k >= 2
		f.update_visual(0.0)
	phase = "gallery"
	camera.position = tile_pos(7.0, 9.6) + Vector3(0, 2.4, 0)
	camera.look_at(tile_pos(7.0, 6.0) + Vector3(0, 0.5, 0), Vector3.UP)


# ---- Headless smoke test ---------------------------------------------------------

func _run_smoke() -> void:
	var t := 0.0
	while t < 900.0 and stats["rounds"] < 8:
		sim_step(Cfg.FIXED_DT)
		t += Cfg.FIXED_DT
	var decided: int = stats["rounds"] - stats["draws"]
	var ok: bool = stats["rounds"] >= 3 and decided >= 1 and stats["bombs"] > 0 and stats["crates"] > 0
	print("SMOKE %s rounds=%d decided=%d draws=%d wins=%s deaths=%d self_kills=%d bombs=%d crates=%d pickups=%d sim_seconds=%d" % [
		"OK" if ok else "FAIL", stats["rounds"], decided, stats["draws"], str(stats["wins"]),
		stats["deaths"], stats["self_kills"], stats["bombs"], stats["crates"], stats["pickups"], int(t)])
	get_tree().quit(0 if ok else 1)
