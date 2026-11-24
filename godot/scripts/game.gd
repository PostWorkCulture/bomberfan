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
const Art := preload("res://scripts/art.gd")
const Fx := preload("res://scripts/fx.gd")
const AudioScript := preload("res://scripts/audio.gd")

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

# Forest backdrop colour behind everything (LEVELS[0].sky in index.html)
const SKY := Color(0.055, 0.102, 0.071)

const PICKUP_LOOK := {
	"bomb": {"color": Color(0.23, 0.42, 1.0), "letter": "B"},
	"fire": {"color": Color(1.0, 0.35, 0.12), "letter": "F"},
	"speed": {"color": Color(0.25, 0.82, 0.42), "letter": "S"},
}

var cells := PackedInt32Array()
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
var _pickup_mesh: Mesh
var _crates: MultiMeshInstance3D   # every log pile in one draw call; broken ones are hidden
var _crate_xf := {}                 # tile index -> its transform in the multimesh
var fx = null
var audio = null
var _last_count := 0
var _shots: Array = []      # autotest: seconds at which to save a screenshot
var _shot_dir := ""
var _quit_at := -1.0


func _ready() -> void:
	smoke = "--smoke" in OS.get_cmdline_user_args()
	demo = "--demo" in OS.get_cmdline_user_args()
	gallery = "--gallery" in OS.get_cmdline_user_args()
	_load_autotest()
	rng.randomize()
	if smoke:
		rng.seed = 20261124
	_setup_input()
	fx = Fx.new()
	fx.enabled = not smoke
	add_child(fx)
	audio = AudioScript.new()
	audio.enabled = not smoke and not gallery
	add_child(audio)
	_build_meshes()
	_build_environment()
	_build_static_arena()
	_build_forest()
	_build_hud()
	_create_fighters()
	start_round()
	if smoke:
		_run_smoke()
	elif gallery:
		_setup_gallery()
	else:
		audio.start_ambience()


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
	_pickup_mesh = Art.rounded_box(Vector3(0.6, 0.14, 0.6), 0.05, 2)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.5, 0.62)
	sky_mat.sky_horizon_color = Color(0.72, 0.74, 0.64)
	sky_mat.ground_horizon_color = Color(0.45, 0.5, 0.38)
	sky_mat.ground_bottom_color = Color(0.14, 0.18, 0.11)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.24, 0.18)
	if env.get("fog_mode") != null:
		# Depth fog (Godot 4.3+): the arena stays crisp, the far forest melts away.
		env.set("fog_mode", 1)
		env.set("fog_depth_begin", 17.0)
		env.set("fog_depth_end", 36.0)
		env.fog_density = 0.9
	else:
		env.fog_density = 0.008
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Warm low sun from the top-left so walls and trees throw long shadows
	# across the board.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 42.0
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
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(Cfg.COLS, Cfg.ROWS)
	_mesh(static_root, floor_mesh, Art.arena_floor_mat(), Vector3.ZERO, false)
	var pillar_xf: Array = []
	var boulder_xf := [[], [], []]
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			var p := tile_pos(x, y)
			var border: bool = x == 0 or y == 0 or x == Cfg.COLS - 1 or y == Cfg.ROWS - 1
			var pillar: bool = not border and x % 2 == 0 and y % 2 == 0
			if pillar:
				var b := Basis(Vector3.UP, r.randi_range(0, 3) * PI / 2.0)
				pillar_xf.append(Transform3D(b, p + Vector3(0, 0.49, 0)))
			elif border:
				var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, r.randf_range(0.92, 1.18), 1.0))
				boulder_xf[r.randi_range(0, 2)].append(Transform3D(b, p + Vector3(0, 0.5, 0)))
	static_root.add_child(Art.multimesh(Art.pillar_mesh(), pillar_xf))
	for v in 3:
		static_root.add_child(Art.multimesh(Art.boulder_mesh(v), boulder_xf[v]))


## The woods around the arena: forest floor, pines, broadleaf trees, bushes,
## rocks, toadstools, grass and a few fallen logs. Static, built once.
func _build_forest() -> void:
	var big := PlaneMesh.new()
	big.size = Vector2(80.0, 80.0)
	_mesh(static_root, big, Art.floor_mat(), Vector3(0, -0.015, 0), false)
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var placed: Array = []
	var hx := Cfg.COLS * 0.5
	var hz := Cfg.ROWS * 0.5
	# kind: [count, keep-out margin beyond the walls, spacing, max distance out]
	var kinds := {
		"pine": [46, 0.75, 1.15, 9.0], "broad": [16, 1.0, 1.6, 9.5], "bush": [34, 0.45, 0.8, 6.0],
		"rock": [22, 0.35, 0.7, 7.0], "toad": [26, 0.25, 0.45, 5.0], "tuft": [320, 0.15, 0.22, 7.0],
		"log": [3, 1.3, 2.6, 5.0],
	}
	var xf := {}
	var col := {}
	for kind in kinds:
		xf[kind] = []
		col[kind] = []
		var spec: Array = kinds[kind]
		var tries := 0
		while xf[kind].size() < spec[0] and tries < spec[0] * 60:
			tries += 1
			var x := r.randf_range(-hx - spec[3], hx + spec[3])
			var z := r.randf_range(-hz - spec[3], hz + 1.2)
			if absf(x) < hx + spec[1] and absf(z) < hz + spec[1]:
				continue
			var ok := true
			for q in placed:
				var d := Vector2(x, z).distance_to(q[0])
				if kind == "tuft":
					if d < 0.35:
						ok = false
						break
				elif d < maxf(spec[2], q[1]):
					ok = false
					break
			if not ok:
				continue
			if kind != "tuft":   # tufts only keep clear of solid things, not of each other
				placed.append([Vector2(x, z), spec[2], kind])
			var s := r.randf_range(0.8, 1.3)
			if kind == "pine":
				s = r.randf_range(0.85, 1.55)
			elif kind == "broad":
				s = r.randf_range(0.9, 1.3)
			var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s)
			xf[kind].append(Transform3D(b, Vector3(x, 0, z)))
			var tint := r.randf_range(0.82, 1.12)
			col[kind].append(Color(tint, tint * r.randf_range(0.95, 1.05), tint * 0.95))
	static_root.add_child(Art.multimesh(Art.pine_mesh(), xf["pine"], col["pine"]))
	var broad_split := [[], []]
	var broad_cols := [[], []]
	for i in xf["broad"].size():
		broad_split[i % 2].append(xf["broad"][i])
		broad_cols[i % 2].append(col["broad"][i])
	for v in 2:
		static_root.add_child(Art.multimesh(Art.broadleaf_mesh(v), broad_split[v], broad_cols[v]))
	static_root.add_child(Art.multimesh(Art.bush_mesh(), xf["bush"], col["bush"]))
	static_root.add_child(Art.multimesh(Art.rock_mesh(r.randi_range(0, 2)), xf["rock"]))
	static_root.add_child(Art.multimesh(Art.toadstool_mesh(), xf["toad"], [], false))
	static_root.add_child(Art.multimesh(Art.grass_tuft_mesh(), xf["tuft"], [], false))
	static_root.add_child(Art.multimesh(Art.fallen_log_mesh(), xf["log"]))


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
	fx.clear()
	_last_count = 0
	bombs.clear()
	bomb_at.clear()
	flames.clear()
	pickups.clear()
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
	var xforms: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	_crate_xf.clear()
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			if cells[idx(x, y)] != SOFT:
				continue
			var b := Basis(Vector3.UP, r.randi_range(0, 3) * PI / 2.0 + r.randf_range(-0.06, 0.06))
			b = b.scaled(Vector3(1.0, r.randf_range(0.96, 1.04), 1.0))
			_crate_xf[idx(x, y)] = xforms.size()
			xforms.append(Transform3D(b, tile_pos(x, y)))
	_crates = Art.multimesh(Art.log_pile_mesh(), xforms)
	round_root.add_child(_crates)


func _end_round(winner, why: String) -> void:
	phase = "outro"
	phase_t = Cfg.ROUND_OUTRO
	stats["rounds"] += 1
	audio.bass(false)
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
		audio.play("match_win")
	else:
		_show_msg("%s WIN%s THE ROUND" % [who, "" if who == "YOU" else "S"], Cfg.ROUND_OUTRO)
		audio.play("round_win")


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
	_autotest_tick()
	if fx.shake > 0.001:
		camera.h_offset = randf_range(-1.0, 1.0) * fx.shake * 0.35
		camera.v_offset = randf_range(-1.0, 1.0) * fx.shake * 0.35
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func sim_step(dt: float) -> void:
	if msg_t > 0.0:
		msg_t -= dt
	match phase:
		"intro":
			phase_t -= dt
			_want_bomb = false
			audio.bass(true)
			var n := ceili(phase_t - 0.35)
			if n != _last_count and n >= 1 and n <= 3:
				_last_count = n
				audio.play("countdown_hi" if n == 1 else "countdown_lo")
			if phase_t <= 0.0:
				phase = "play"
				_show_msg("GO!", 0.7)
				audio.play("go")
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
		"alive": true, "age": 0.0, "node": fx.make_bomb(round_root, tile_pos(t.x, t.y))}
	bombs.append(b)
	bomb_at[i] = b
	f.active_bombs += 1
	for o in fighters:
		if o.alive and o.overlaps_tile(t):
			o.ignore_bombs[i] = true
	stats["bombs"] += 1
	audio.play("place_bomb", -2.0, 0.05)
	return true



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
	var world_cells: Array = []
	var broke := false
	for c in blast_cells(b["x"], b["y"], b["fire"]):
		var ci := idx(c.x, c.y)
		world_cells.append(tile_pos(c.x, c.y))
		_add_flame(c, bomber.pid)
		if cells[ci] == SOFT:
			_break_crate(c)
			broke = true
		elif pickups.has(ci) and pickups[ci]["shield"] <= 0.0:
			_remove_pickup(ci)
		if bomb_at.has(ci):
			var o: Dictionary = bomb_at[ci]
			o["fuse"] = minf(o["fuse"], Cfg.CHAIN_DELAY)
	# Bigger bomb counts shake harder (SHAKE_PER_BOMBUP in the browser build)
	var strength := minf(pow(1.36759, maxi(0, bomber.max_bombs - 1)) * 0.6, 1.6)
	fx.explosion(tile_pos(centre.x, centre.y), world_cells, strength)
	audio.play("explode", 0.0, 0.06, 0.05)
	if broke:
		audio.play("break_block", -3.0, 0.08, 0.05)


func _add_flame(c: Vector2i, pid: int) -> void:
	var ci := idx(c.x, c.y)
	if flames.has(ci):
		flames[ci]["t"] = Cfg.BLAST_LIFE
		flames[ci]["pid"] = pid
		return
	var n: Node3D = fx.flame_glow(round_root, tile_pos(c.x, c.y)) if fx.enabled else null
	flames[ci] = {"t": Cfg.BLAST_LIFE, "pid": pid, "node": n}


func _step_flames(dt: float) -> void:
	for k in flames.keys():
		var fl: Dictionary = flames[k]
		fl["t"] -= dt
		var node = fl["node"]
		if fl["t"] <= 0.0:
			if node != null and is_instance_valid(node):
				node.queue_free()
			flames.erase(k)
		elif node != null and is_instance_valid(node):
			node.scale = Vector3.ONE * (0.6 + 0.65 * fl["t"] / Cfg.BLAST_LIFE)


func _break_crate(c: Vector2i) -> void:
	var ci := idx(c.x, c.y)
	cells[ci] = EMPTY
	stats["crates"] += 1
	if _crate_xf.has(ci) and is_instance_valid(_crates):
		_crates.multimesh.set_instance_transform(_crate_xf[ci], Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
		_crate_xf.erase(ci)
	fx.crate_break(tile_pos(c.x, c.y))
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
	var pm := StandardMaterial3D.new()
	pm.albedo_color = look["color"]
	pm.roughness = 0.35
	pm.emission_enabled = true
	pm.emission = look["color"]
	pm.emission_energy_multiplier = 0.9
	_mesh(n, _pickup_mesh, pm, Vector3(0, 0.1, 0))
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
		audio.play("pickup", 4.0)


func _check_deaths() -> void:
	for f in fighters:
		if not f.alive:
			continue
		var t: Vector2i = f.tile()
		var ci := idx(t.x, t.y)
		if flames.has(ci):
			f.die()
			fx.death_puff(f.position)
			audio.play("death")
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
			fx.animate_bomb(node, b["age"], b["fuse"], _time)
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


# ---- Local autotest: res://autotest.json (git-ignored) runs a demo, saves
# screenshots to .godot/autotest/ and quits. {"enabled": true, "mode": "demo",
# "shots": [5, 9, 14]} — "mode" may also be "gallery" or "play".

func _load_autotest() -> void:
	var path := "res://autotest.json"
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not data.get("enabled", false):
		return
	var mode: String = data.get("mode", "demo")
	demo = mode == "demo"
	gallery = mode == "gallery"
	_shots = data.get("shots", [5.0, 9.0, 14.0])
	_shots.sort()
	_shot_dir = ProjectSettings.globalize_path("res://.godot/autotest")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_quit_at = (float(_shots.back()) if not _shots.is_empty() else 10.0) + 0.6


func _autotest_tick() -> void:
	if _quit_at < 0.0:
		return
	if not _shots.is_empty() and _time >= float(_shots[0]):
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%02d.png" % [_shot_dir, int(float(_shots[0]))])
		_shots.pop_front()
	if _time >= _quit_at:
		get_tree().quit()


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
