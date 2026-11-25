extends Node3D
## Bomber Fan — Godot rebuild.
## Four arenas (a random one each round), you vs three bots, bombs, chain
## blasts, crates and the Bomb Up / Fire Up / Speed pick-ups, first to
## Cfg.WINS_NEEDED rounds. Level rules: conveyor belts (Factory), turning
## clockwork walls and the bomb-throwing witch (Haunted House).
## Rules and tuning follow the browser build (../index.html); see ../DESIGN.md.
##
## Run with `-- --smoke` for a headless bots-only test that prints a summary
## and exits non-zero if the game did not play properly. `-- --level <id>`
## plays one arena only; `-- --tour` shows every arena in turn (CI screenshots).

const Cfg := preload("res://scripts/config.gd")
const Fighter := preload("res://scripts/fighter.gd")
const BotBrain := preload("res://scripts/bot_brain.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const Hud := preload("res://scripts/hud.gd")
const Art := preload("res://scripts/art.gd")
const Fx := preload("res://scripts/fx.gd")
const AudioScript := preload("res://scripts/audio.gd")
const Levels := preload("res://scripts/levels.gd")
const LA := preload("res://scripts/level_art.gd")
const Scenery := preload("res://scripts/level_scenery.gd")
const Props := preload("res://scripts/level_props.gd")
const Ambient := preload("res://scripts/ambient.gd")
const Mechanics := preload("res://scripts/mechanics.gd")
const CRATE_SPARES := 8   # hidden crate instances per variant, for crates that appear mid-round

const EMPTY := 0
const HARD := 1
const SOFT := 2
const SAFE := 999.0
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## The Godot roster (Pete, 2026-11-25): Razor (the ninja) and three
## Blender bomber-bots, Sparky Mk II, Rivet and Pixel. HUD colours follow
## each character's own paint.
# Fighters. You are always Razor; each match the three bots are drawn at random
# from the rest (`-- --cast sparky,snap,arcade` or autotest "cast" picks them).
const ROSTER := [
	{"id": "ninja", "name": "RAZOR", "color": Color(0.36, 0.6, 1.0)},
	{"id": "sparky", "name": "SPARKY", "color": Color(1.0, 0.78, 0.12)},
	{"id": "rivet", "name": "RIVET", "color": Color(1.0, 0.34, 0.27)},
	{"id": "pixel", "name": "PIXEL", "color": Color(0.33, 0.88, 0.45)},
	{"id": "boiler", "name": "BOILER", "color": Color(0.96, 0.56, 0.24)},
	{"id": "gumball", "name": "GUMBALL", "color": Color(1.0, 0.46, 0.72)},
	{"id": "snap", "name": "SNAP", "color": Color(0.92, 0.93, 0.96)},
	{"id": "arcade", "name": "ARCADE", "color": Color(0.7, 0.52, 1.0)},
	{"id": "tick", "name": "TICK", "color": Color(0.36, 0.86, 0.82)},
]

# Forest backdrop colour behind everything (LEVELS[0].sky in index.html)
const SKY := Color(0.055, 0.102, 0.071)
const GROUND_Y := -0.34   # the woods sit this far below the arena floor


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
# Sudden death: after the last crate (or when the clock runs out) rings of
# rock drop in from the edge. Ported from updateEndgame() in index.html.
var soft_count := 0
var round_elapsed := 0.0
var crates_cleared_at := -1.0
var sd_warned := false
var sudden_death := false
var sd_ring := 0
var sd_queue: Array = []
var sd_stagger := 0.0
var sd_timer := 0.0
var sd_done := 0.0
var sd_countdown := 0.0
var _falling: Array = []

# ---- The current arena
var level: Dictionary = {}
var level_id := ""
var forced_level := ""          # `-- --level <id>`, autotest "level", or the L key
var rules := PackedByteArray()  # conveyor belts (Levels.BELT_*)
var clock := {}                 # Haunted House walls; empty on other levels
var _clock_nodes: Array = []    # one pivot per wall section
var _props: Array = []          # animated wall props
var hazards: Array = []         # [{"pos": Vector2i, "node": Node3D}]
var hazard_t := 0.0
var hazard_target := Vector2i(-1, -1)
var hazard_source := -1
var hazard_next := 0
var flights: Array = []         # thrown bombs still in the air
var _hazard_mark: MeshInstance3D
var tour := false
var _tour_t := 0.0
var _tour_i := 0
var tour_secs := 2.0
# Arrival flyover: the camera swings in over a new arena before the countdown.
const FLY_TIME := 2.3
## One line per arena under its name before each round: what is special here.
const ARENA_HINTS := {
	"forest": "Hide in the tall grass  ·  the beaver rebuilds crates",
	"beach": "The tide floods the outer lane  ·  crabs shove bombs",
	"haunted": "The walls turn  ·  the witch throws  ·  ghosts shove crates",
	"factory": "Crushers slam their tile  ·  blast the lever to reverse the belts",
}
var _win_cam := -1.0        # time into the winner close-up, -1 when off
var _win_target := Vector3.ZERO
const CAM_POS := Vector3(0.0, 15.2, 6.6)
const CAM_TARGET := Vector3(0.0, 0.0, 0.55)
var _fly := -1.0
var _hitstop := 0.0   # `-- --tour-secs 0.6`: a quicker tour for local previews
var _smoke_levels: Array = []
var level_root: Node3D          # everything static that belongs to the arena
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var sun_base_energy := 1.0
var msg_text := ""
var msg_t := 0.0

var rng := RandomNumberGenerator.new()
var smoke := false
var demo := false   # `-- --demo`: four bots, full visuals (attract mode / CI screenshots)
var gallery := false   # `-- --gallery`: close-up of the fighters for CI checks
var forced_cast: Array = []   # bot ids from autotest "cast"
var lineup := false    # autotest "lineup": the roster side by side on plain ground
var human_pid := 0
var stats := {"rounds": 0, "draws": 0, "deaths": 0, "self_kills": 0, "sudden_deaths": 0, "crushed": 0,
	"bombs": 0, "crates": 0, "pickups": 0, "shields": 0, "doused": 0, "wins": [0, 0, 0, 0]}

var static_root: Node3D
var round_root: Node3D
var camera: Camera3D
var touch = null
var hud = null          # player cards, timer pill, call-outs (hud.gd)
var _hud_layer: CanvasLayer
var _hud_hint := false

var _acc := 0.0
var _time := 0.0
var _want_bomb := false
var _mats := {}
var _crates: Array = []            # one multimesh per crate variant; broken ones are hidden
var _crate_xf := {}                 # tile index -> [variant, instance]
var fx = null
var audio = null
var ambient = null   # birds, bats, lightning, steam: presentation only
var mech = null      # per-arena mechanics: grass, beaver, tide, crabs, ghosts, presses, lever
var _crate_spare: Array = []        # per variant: free hidden instance indices
var _crate_anims: Array = []        # crates sliding (ghost shove) or popping up (beaver)
var _last_count := 0
var _shots: Array = []      # autotest: seconds at which to save a screenshot
var _shot_dir := ""
var _quit_at := -1.0
var occ_img: Image             # one texel per tile: walls and crates, for floor contact shadow
var occ_tex: ImageTexture
var _occ_dirty := false
var _perf := {"frames": 0, "worst": 0.0, "draws": 0, "prims": 0}


func _ready() -> void:
	smoke = "--smoke" in OS.get_cmdline_user_args()
	demo = "--demo" in OS.get_cmdline_user_args()
	gallery = "--gallery" in OS.get_cmdline_user_args()
	tour = "--tour" in OS.get_cmdline_user_args()
	var args := OS.get_cmdline_user_args()
	var li := args.find("--level")
	if li >= 0 and li + 1 < args.size() and Levels.index_of(args[li + 1]) >= 0:
		forced_level = args[li + 1]
	var ts := args.find("--tour-secs")
	if ts >= 0 and ts + 1 < args.size():
		tour_secs = float(args[ts + 1])
	if tour:
		demo = true
	_load_autotest()
	if gallery and forced_level == "":
		forced_level = "forest"   # the CI close-up is judged on the Forest
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
	_build_environment()
	occ_img = Image.create(Cfg.COLS, Cfg.ROWS, false, Image.FORMAT_L8)
	occ_tex = ImageTexture.create_from_image(occ_img)
	Art.occ_texture = occ_tex
	static_root = Node3D.new()
	add_child(static_root)
	if not smoke:
		ambient = Ambient.new()
		ambient.setup(self)
		add_child(ambient)
	round_root = Node3D.new()
	add_child(round_root)
	_build_hud()
	mech = Mechanics.new()
	mech.setup(self)
	_create_fighters()
	# Built in the smoke test too (and refreshed each round there), so CI
	# catches HUD script errors.
	hud = Hud.new()
	add_child(hud)
	hud.setup(self, fighters, Cfg.WINS_NEEDED, _hud_hint)
	start_round()
	if tour:
		phase = "play"
	if smoke:
		_run_smoke()
	elif lineup:
		_setup_lineup()
	elif gallery:
		_setup_gallery()
	else:
		audio.start_ambience()
		fx.prewarm(round_root)


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
			# Where a belt will have taken it by the time it goes off: both
			# crosses count, since a belt can be blocked.
			var drift := _belt_drift(b)
			if drift != Vector2i(b["x"], b["y"]):
				list.append({"x": drift.x, "y": drift.y, "fire": b["fire"], "t": b["fuse"]})
	# Thrown bombs still in the air, and the tile a hazard is winding up to hit
	for fl in flights:
		list.append({"x": fl["to"].x, "y": fl["to"].y, "fire": Levels.HAZARD_FIRE, "t": fl["fuse"]})
	if hazard_target.x >= 0 and hazards.size() > 0:
		var cadence := Levels.HAZARD_EVERY / hazards.size()
		var lands := maxf(0.0, cadence - hazard_t) + Cfg.BOMB_FUSE
		list.append({"x": hazard_target.x, "y": hazard_target.y, "fire": Levels.HAZARD_FIRE, "t": lands})
	if not extra.is_empty():
		list.append({"x": extra["x"], "y": extra["y"], "fire": extra["fire"], "t": extra["fuse"]})
	var by_tile := {}
	for e in list:
		var k0 := idx(e["x"], e["y"])
		if not by_tile.has(k0) or by_tile[k0]["t"] > e["t"]:
			by_tile[k0] = e
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
	for d in _doomed_tiles():
		var t: Vector2i = d[0]
		var k := idx(t.x, t.y)
		danger[k] = minf(danger[k], d[1])
	for k in flames.keys():
		danger[k] = 0.0
	return danger


func _belt_drift(b: Dictionary) -> Vector2i:
	var at := Vector2i(b["x"], b["y"])
	var budget: float = maxf(0.0, b["fuse"]) * Levels.BELT_SPEED
	var n := 0
	while n < 12 and budget >= 1.0:
		var d := belt_at(at.x, at.y)
		if d == Vector2i.ZERO:
			break
		var nx := at + d
		if cell_at(nx.x, nx.y) != EMPTY or bomb_at.has(idx(nx.x, nx.y)):
			break
		at = nx
		budget -= 1.0
		n += 1
	return at


## Sudden death, as the bots see it: tiles the walls are about to land on, with
## the seconds until they do — the same warning a human reads off the HUD.
func _doomed_tiles() -> Array:
	var out: Array = mech.doomed()
	if not sudden_death:
		if sd_warned:
			for t in _ring_tiles(1):
				if cell_at(t.x, t.y) != HARD:
					out.append([t, sd_countdown])
		return out
	var i := 0
	for t in sd_queue:
		out.append([t, i * Cfg.SD_BLOCK_STAGGER])
		i += 1
	if sd_ring < Cfg.SD_MAX_RINGS:
		var when := sd_queue.size() * Cfg.SD_BLOCK_STAGGER + sd_timer
		for t in _ring_tiles(sd_ring + 1):
			if cell_at(t.x, t.y) != HARD:
				out.append([t, when])
	return out


# ---- Setup --------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"bomb": [KEY_SPACE, KEY_ENTER, KEY_J], "restart": [KEY_R], "next_level": [KEY_L],
	}
	var pads := {
		"move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT,
		"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN,
		"bomb": JOY_BUTTON_A, "restart": JOY_BUTTON_START, "next_level": JOY_BUTTON_BACK,
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


func _build_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.5, 0.62)
	sky_mat.sky_horizon_color = Color(0.72, 0.74, 0.64)
	sky_mat.ground_horizon_color = Color(0.45, 0.5, 0.38)
	sky_mat.ground_bottom_color = Color(0.14, 0.18, 0.11)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	for lvl in [4, 5, 6, 7]:   # keep the glow tight: no wide halos round small bright things
		env.set("glow_levels/%d" % lvl, 0.0)
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
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Warm low sun from the top-left so walls and trees throw long shadows
	# across the board.
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 42.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # no sun disc to reflect and bloom
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 44.0
	add_child(camera)
	camera.position = CAM_POS
	camera.look_at(CAM_TARGET, Vector3.UP)
	camera.current = true


func _build_forest_arena() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(Cfg.COLS, Cfg.ROWS)
	_mesh(level_root, floor_mesh, Art.arena_floor_mat(), Vector3.ZERO, false)
	# The arena stands on a stone base, one step above the woods, so the
	# edge of the playing area reads clearly from outside the rocks.
	var base := Vector3(Cfg.COLS + 0.36, -GROUND_Y + 0.02, Cfg.ROWS + 0.36)
	_mesh(level_root, Art.plinth_mesh(base), null, Vector3(0, GROUND_Y * 0.5 - 0.012, 0))
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
	level_root.add_child(Art.multimesh(Art.pillar_mesh(), pillar_xf))
	for v in 3:
		level_root.add_child(Art.multimesh(Art.boulder_mesh(v), boulder_xf[v]))


## The woods around the arena: forest floor, pines, broadleaf trees, bushes,
## rocks, toadstools, grass and a few fallen logs. Static, built once.
func _build_forest() -> void:
	var big := PlaneMesh.new()
	big.size = Vector2(80.0, 80.0)
	_mesh(level_root, big, Art.floor_mat(), Vector3(0, GROUND_Y, 0), false)
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
			xf[kind].append(Transform3D(b, Vector3(x, GROUND_Y, z)))
			var tint := r.randf_range(0.82, 1.12)
			col[kind].append(Color(tint, tint * r.randf_range(0.95, 1.05), tint * 0.95))
	level_root.add_child(Art.multimesh(Art.pine_mesh(), xf["pine"], col["pine"]))
	var broad_split := [[], []]
	var broad_cols := [[], []]
	for i in xf["broad"].size():
		broad_split[i % 2].append(xf["broad"][i])
		broad_cols[i % 2].append(col["broad"][i])
	for v in 2:
		level_root.add_child(Art.multimesh(Art.broadleaf_mesh(v), broad_split[v], broad_cols[v]))
	level_root.add_child(Art.multimesh(Art.bush_mesh(), xf["bush"], col["bush"]))
	level_root.add_child(Art.multimesh(Art.rock_mesh(r.randi_range(0, 2)), xf["rock"]))
	level_root.add_child(Art.multimesh(Art.toadstool_mesh(), xf["toad"], [], false))
	level_root.add_child(Art.multimesh(Art.grass_tuft_mesh(), xf["tuft"], [], false))
	level_root.add_child(Art.multimesh(Art.fallen_log_mesh(), xf["log"]))


# ---- Levels ---------------------------------------------------------------------

## Which arena this round: a forced one, every one in turn for the smoke test
## and the tour, otherwise a random one (the browser's Level: Random).
func _pick_level() -> String:
	if forced_level != "":
		return forced_level
	if tour:
		return Levels.LIST[_tour_i % Levels.LIST.size()]["id"]
	if smoke:
		return Levels.LIST[int(stats["rounds"]) % Levels.LIST.size()]["id"]
	return Levels.LIST[rng.randi() % Levels.LIST.size()]["id"]


func _apply_level(id: String) -> void:
	level_id = id
	level = Levels.by_id(id)
	if level_root != null:
		level_root.queue_free()
	level_root = Node3D.new()
	static_root.add_child(level_root)
	_props.clear()
	hazards.clear()
	_apply_env(id)
	audio.set_arena(id)
	for f in fighters:
		f.set_outline(id == "haunted" or id == "factory")
	fx.debris_color = LA.theme(id).get("debris", Color(0, 0, 0, 0))
	fx.theme = id
	fx.pale_bombs = level.get("pale_bomb", false)
	# The hazards are rules, not scenery: work out where they stand even headless.
	var kinds: Array = level.get("props", [])
	var hazard_kind: String = level.get("hazard", "")
	if hazard_kind != "" and not kinds.is_empty():
		var spots: Array = Levels.prop_spots(level)
		var limit: int = maxi(1, level.get("hazard_count", 1))
		for i in spots.size():
			var spot: Array = spots[i]
			var kind: String = kinds[i % kinds.size()]
			if kind == hazard_kind and hazards.size() < limit:
				hazards.append({"pos": Vector2i(spot[0], spot[1]), "node": null, "spot": i})


func _build_level_scene() -> void:
	# Built after the first round's cells exist, because the walls follow them.
	if ambient != null and not gallery:
		ambient.build(level_id)
	if level_id == "forest":
		_build_forest_arena()
		_build_forest()
		return
	var hard := PackedByteArray()
	hard.resize(cells.size())
	for i in cells.size():
		hard[i] = 1 if cells[i] == HARD else 0
	var skip := {}
	if not clock.is_empty():
		for k in clock["cells"]:
			skip[k] = true
	Scenery.build(level_root, level, hard, skip)
	# Props on the walls; the level's hazard gets a scowl and a bomb to throw.
	var kinds: Array = level.get("props", [])
	if kinds.is_empty():
		return
	var spots: Array = Levels.prop_spots(level)
	var angry_at := {}
	for h in hazards:
		angry_at[h["spot"]] = h
	for i in spots.size():
		var spot: Array = spots[i]
		var kind: String = kinds[i % kinds.size()]
		var angry: bool = angry_at.has(i)
		var n: Node3D = Props.make(kind, angry)
		var at := Vector2i(spot[0], spot[1])
		n.position = tile_pos(at.x, at.y) + Vector3(0, 1.04, 0)   # on top of the outer wall
		n.rotation.y = spot[2] + (0.25 if i % 2 == 1 else -0.2)
		level_root.add_child(n)
		_props.append(n)
		if angry:
			angry_at[i]["node"] = n


func _apply_env(id: String) -> void:
	var th: Dictionary = LA.theme(id)
	sky_mat.sky_top_color = th["sky_top"]
	sky_mat.sky_horizon_color = th["sky_horizon"]
	sky_mat.ground_horizon_color = th.get("ground_horizon", th["sky_horizon"].darkened(0.4))
	env.background_color = th["sky"]
	env.ambient_light_energy = th["ambient"]
	env.fog_light_color = th["fog"]
	_set_fog(th["fog_begin"], th["fog_end"])
	env.tonemap_exposure = th.get("exposure", 1.0)
	env.adjustment_saturation = th.get("saturation", 1.0)
	env.adjustment_contrast = th.get("contrast", 1.05)
	env.glow_intensity = th.get("glow", 0.35)
	sun.rotation_degrees = th["sun_rot"]
	sun.light_color = th["sun"]
	sun.light_energy = th["sun_energy"]
	sun_base_energy = th["sun_energy"]


func _set_fog(begin: float, end: float) -> void:
	if env.get("fog_mode") != null:
		env.set("fog_depth_begin", begin)
		env.set("fog_depth_end", end)


func _build_hud() -> void:
	# The HUD proper is built once the fighters exist (it needs their names and
	# colours); this layer holds the touch controls.
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	if not smoke and DisplayServer.is_touchscreen_available():
		touch = TouchControls.new()
		_hud_layer.add_child(touch)
	else:
		_hud_hint = not smoke


func _pick_cast() -> Array:
	var cast: Array = [ROSTER[0]]
	var pool: Array = ROSTER.slice(1)
	var ids: Array = forced_cast
	var args := OS.get_cmdline_user_args()
	var ci := args.find("--cast")
	if ci >= 0 and ci + 1 < args.size():
		ids = Array(args[ci + 1].split(","))
	for id in ids:
		for info in pool:
			if info["id"] == id and not cast.has(info) and cast.size() < Cfg.MAX_PLAYERS:
				cast.append(info)
	while cast.size() < Cfg.MAX_PLAYERS:
		var left := pool.filter(func(c): return not cast.has(c))
		cast.append(left[rng.randi() % left.size()])
	return cast


func _create_fighters() -> void:
	human_pid = -1 if smoke or demo or gallery else 0
	var cast := _pick_cast()
	for k in Cfg.MAX_PLAYERS:
		var f = Fighter.new()
		add_child(f)
		f.setup(self, k, cast[k], k != human_pid)
		fighters.append(f)
		if f.is_bot:
			var b = BotBrain.new()
			b.setup(self, f, 1000 + k * 7919 + (0 if smoke else rng.randi() % 100000))
			brains[k] = b


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
	flights.clear()
	hazard_t = 0.0
	hazard_target = Vector2i(-1, -1)
	hazard_source = -1
	hazard_next = 0
	var id := _pick_level()
	var fresh := id != level_id
	if fresh:
		_apply_level(id)
	if smoke:
		_smoke_levels.append(id)
	_generate_cells()
	if fresh and not smoke:
		_build_level_scene()
	for h in hazards:
		if h["node"] != null:
			Props.wind_up(h["node"], -1.0)
	_build_crates()
	_build_round_dressing()
	mech.start_round(level_id)
	var sp: Array = Levels.spawns(level)
	for k in fighters.size():
		fighters[k].spawn_at(sp[k][0])
		if brains.has(k):
			brains[k].reset()
	if _win_cam >= 0.0:
		_win_cam = -1.0
		camera.position = CAM_POS
		camera.look_at(CAM_TARGET, Vector3.UP)
	phase = "intro"
	phase_t = Cfg.ROUND_INTRO
	if fresh and not (smoke or tour or gallery or lineup or _quit_at >= 0.0):
		_fly = 0.0
		phase_t += FLY_TIME
		audio.play("whoosh")
	round_t = Cfg.ROUND_SECONDS
	end_check_t = -1.0
	msg_t = 0.0
	round_elapsed = 0.0
	crates_cleared_at = -1.0
	sd_warned = false
	sudden_death = false
	sd_ring = 0
	sd_queue.clear()
	sd_done = 0.0
	sd_countdown = 0.0
	_falling.clear()


func _generate_cells() -> void:
	soft_count = 0
	var n := Cfg.COLS * Cfg.ROWS
	cells.resize(n)
	rules.resize(n)
	rules.fill(Levels.RULE_NONE)
	clock = {}
	# 1. Hard layout: the classic rectangle with its pillar lattice.
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			var border: bool = x == 0 or y == 0 or x == Cfg.COLS - 1 or y == Cfg.ROWS - 1
			cells[idx(x, y)] = HARD if border or (x % 2 == 0 and y % 2 == 0) else EMPTY
	if level.get("layout", "") == "clockwork-maze":
		_init_clockwork()
	# 2. Spawn pockets: the level's clear pattern plus every tile within three
	#    steps of the spawn, so nobody starts boxed in.
	var safe := {}
	for s in Levels.spawns(level):
		var at: Vector2i = s[0]
		for d in s[1]:
			var t: Vector2i = at + d
			if t.x > 0 and t.y > 0 and t.x < Cfg.COLS - 1 and t.y < Cfg.ROWS - 1:
				safe[t] = true
		var q: Array = [[at, 0]]
		var seen := {at: true}
		var head := 0
		while head < q.size():
			var c: Vector2i = q[head][0]
			var dist: int = q[head][1]
			head += 1
			if cell_at(c.x, c.y) != EMPTY:
				continue
			safe[c] = true
			if dist == 3:
				continue
			for d in DIRS:
				var nb: Vector2i = c + d
				if seen.has(nb) or cell_at(nb.x, nb.y) != EMPTY:
					continue
				seen[nb] = true
				q.append([nb, dist + 1])
	# Tiles the arena's mechanics need open (grass meadows, press beds).
	for t in mech.reserved(level_id):
		safe[t] = true
	# A turning wall's destination stays empty all round.
	if not clock.is_empty():
		for c in clock["cells"]:
			safe[c] = true
	# 3. Crates
	var density: float = minf(0.92, level.get("density", Cfg.SOFT_DENSITY) + 0.16)
	for y in range(1, Cfg.ROWS - 1):
		for x in range(1, Cfg.COLS - 1):
			if cells[idx(x, y)] == EMPTY and not safe.has(Vector2i(x, y)) and rng.randf() < density:
				cells[idx(x, y)] = SOFT
				soft_count += 1
	# 4. The level's rule, laid after the crates so it can clear the tile it needs.
	if level.get("rule", "") == "belts":
		for e in Levels.belt_tiles():
			var t: Vector2i = e[0]
			if t.x < 1 or t.y < 1 or t.x > Cfg.COLS - 2 or t.y > Cfg.ROWS - 2 or cells[idx(t.x, t.y)] == HARD:
				continue
			if cells[idx(t.x, t.y)] == SOFT:
				cells[idx(t.x, t.y)] = EMPTY
				soft_count -= 1
			if safe.has(t):
				continue   # a spawn keeps plain floor: no being carried off before GO
			rules[idx(t.x, t.y)] = e[1]
	_occ_dirty = true


## Floor contact shadow follows the grid: call after any change to cells.
func _refresh_occ() -> void:
	_occ_dirty = false
	if smoke or occ_img == null:
		return
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			var c := cells[idx(x, y)]
			occ_img.set_pixel(x, y, Color.WHITE if c == HARD else (Color(0.75, 0.75, 0.75) if c == SOFT else Color.BLACK))
	occ_tex.update(occ_img)


func belt_at(x: int, y: int) -> Vector2i:
	if x < 0 or y < 0 or x >= Cfg.COLS or y >= Cfg.ROWS:
		return Vector2i.ZERO
	return Levels.BELT_DIR.get(rules[idx(x, y)], Vector2i.ZERO)


func _build_crates() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	_crate_xf.clear()
	_crates.clear()
	var meshes: Array = LA.crate_meshes(level_id)
	var xforms: Array = []
	for m in meshes:
		xforms.append([])
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			if cells[idx(x, y)] != SOFT:
				continue
			# Half the crates are the arena's main kind; the rest share the variants.
			var v := 0
			if meshes.size() > 1 and r.randf() < 0.5:
				v = 1 + r.randi() % (meshes.size() - 1)
			var b := Basis(Vector3.UP, r.randi_range(0, 3) * PI / 2.0 + r.randf_range(-0.06, 0.06))
			b = b.scaled(Vector3(1.0, r.randf_range(0.96, 1.04), 1.0))
			_crate_xf[idx(x, y)] = [v, xforms[v].size()]
			xforms[v].append(Transform3D(b, tile_pos(x, y)))
	_crate_spare.clear()
	_crate_anims.clear()
	if smoke:
		return
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for v in meshes.size():
		var spare: Array = []
		for k in CRATE_SPARES:
			spare.append(xforms[v].size())
			xforms[v].append(hidden)
		_crate_spare.append(spare)
		var mm := Art.multimesh(meshes[v], xforms[v])
		round_root.add_child(mm)
		_crates.append(mm)


func _hide_crate(ci: int) -> void:
	if not _crate_xf.has(ci):
		return
	var e: Array = _crate_xf[ci]
	_crate_xf.erase(ci)
	if e[0] < _crates.size() and is_instance_valid(_crates[e[0]]):
		_crates[e[0]].multimesh.set_instance_transform(e[1], Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))


## A crate that appears mid-round (the Forest beaver builds one). Takes a
## spare hidden instance and pops it up.
func add_crate(t: Vector2i) -> void:
	var ci := idx(t.x, t.y)
	cells[ci] = SOFT
	soft_count += 1
	_occ_dirty = true
	if _crates.is_empty():
		return
	var v := rng.randi() % _crates.size()
	for k in _crates.size():
		var vv := (v + k) % _crates.size()
		if not _crate_spare[vv].is_empty():
			var inst: int = _crate_spare[vv].pop_back()
			_crate_xf[ci] = [vv, inst]
			var b := Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0)
			_crate_anims.append({"v": vv, "i": inst, "basis": b, "from": tile_pos(t.x, t.y), "to": tile_pos(t.x, t.y), "t": 0.0, "dur": 0.35, "pop": true})
			return


## A crate shoved one tile (the Haunted House ghosts). The rules move at once;
## the model slides over a quarter second.
func move_crate(from: Vector2i, to: Vector2i) -> void:
	var fi := idx(from.x, from.y)
	var ti := idx(to.x, to.y)
	cells[fi] = EMPTY
	cells[ti] = SOFT
	_occ_dirty = true
	if not _crate_xf.has(fi):
		return
	var e: Array = _crate_xf[fi]
	_crate_xf.erase(fi)
	_crate_xf[ti] = e
	if e[0] < _crates.size() and is_instance_valid(_crates[e[0]]):
		var cur: Transform3D = _crates[e[0]].multimesh.get_instance_transform(e[1])
		_crate_anims.append({"v": e[0], "i": e[1], "basis": cur.basis, "from": tile_pos(from.x, from.y), "to": tile_pos(to.x, to.y), "t": 0.0, "dur": 0.28, "pop": false})


func _update_crate_anims(delta: float) -> void:
	for a in _crate_anims.duplicate():
		a["t"] += delta
		var k: float = clampf(a["t"] / a["dur"], 0.0, 1.0)
		var mm: MultiMeshInstance3D = _crates[a["v"]] if a["v"] < _crates.size() else null
		if mm == null or not is_instance_valid(mm):
			_crate_anims.erase(a)
			continue
		var e: float = k * k * (3.0 - 2.0 * k)
		var b: Basis = a["basis"]
		var p: Vector3 = a["from"].lerp(a["to"], e)
		if a["pop"]:
			var s := 0.2 + 0.8 * e + sin(k * PI) * 0.15
			b = b.scaled(Vector3(s, s, s))
		else:
			p.y += sin(k * PI) * 0.08
		mm.multimesh.set_instance_transform(a["i"], Transform3D(b, p))
		if k >= 1.0:
			_crate_anims.erase(a)


## Water puts a bomb out (Beach tide): it fizzles and goes back to its owner.
func douse_bomb(b: Dictionary) -> void:
	if not b["alive"]:
		return
	b["alive"] = false
	stats["doused"] += 1
	bomb_at.erase(idx(b["x"], b["y"]))
	if b["owner"] != null:
		b["owner"].active_bombs = maxi(0, b["owner"].active_bombs - 1)
	var node: Node3D = b["node"]
	if is_instance_valid(node):
		fx.steam_puff(node.position)
		node.queue_free()
	if not smoke:
		audio.play("fizz", 0.0, 0.1)


## Slide a bomb one tile (Beach crabs shove them). False if it cannot go.
func push_bomb(b: Dictionary, d: Vector2i) -> bool:
	var nx: int = b["x"] + d.x
	var ny: int = b["y"] + d.y
	if not bomb_can_enter(nx, ny, b):
		return false
	bomb_at.erase(idx(b["x"], b["y"]))
	b["x"] = nx
	b["y"] = ny
	b.erase("fx")
	b.erase("fy")
	bomb_at[idx(nx, ny)] = b
	var node: Node3D = b["node"]
	if is_instance_valid(node):
		var tw := node.create_tween()
		tw.tween_property(node, "position", tile_pos(nx, ny), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return true


## A fighter caught by something other than fire (a press, falling walls).
func crush(f) -> void:
	if not f.alive:
		return
	f.die()
	_knockout_pause()
	fx.death_puff(f.position)
	audio.play("death")
	stats["deaths"] += 1
	stats["crushed"] += 1


func human_fighter():
	return fighters[human_pid] if human_pid >= 0 and human_pid < fighters.size() else null


## Speed on this tile: the Beach tide slows wading.
func move_mult(t: Vector2i) -> float:
	return mech.move_mult(t)


## Per-round pieces of the arena: conveyor belts, the clockwork walls and the
## hazard's landing marker.
func _build_round_dressing() -> void:
	_clock_nodes.clear()
	_hazard_mark = null
	if smoke:
		return
	var belts: Array = []
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			var d := belt_at(x, y)
			if d != Vector2i.ZERO:
				var yaw := atan2(-float(d.y), float(d.x))
				belts.append(Transform3D(Basis(Vector3.UP, yaw), tile_pos(x, y) + Vector3(0, 0.012, 0)))
	if not belts.is_empty():
		var q := PlaneMesh.new()
		q.size = Vector2(1.0, 0.92)
		var mm := Art.multimesh(q, belts, [], false)
		mm.material_override = LA.belt_mat()
		round_root.add_child(mm)
	if not clock.is_empty():
		for sec in Levels.CLOCKWORK_SECTIONS:
			var pivot := Node3D.new()
			pivot.position = tile_pos(sec.x, sec.y)
			round_root.add_child(pivot)
			var body := MeshInstance3D.new()
			body.mesh = LA.clockwork_mesh()
			pivot.add_child(body)
			var gears: Array = []
			for g in 2:
				var gm := MeshInstance3D.new()
				gm.mesh = LA.gear_mesh(0.3 if g == 0 else 0.22, 10 if g == 0 else 8)
				gm.position = Vector3(-0.42 + g * 0.8, 1.04, 0)
				pivot.add_child(gm)
				gears.append(gm)
			var warn := MeshInstance3D.new()
			var wq := BoxMesh.new()
			wq.size = Vector3(2.7, 0.04, 0.1)
			warn.mesh = wq
			warn.material_override = LA.glow_mat(Color(1.0, 0.45, 0.1), 3.0)
			warn.position = Vector3(0, 1.03, 0.2)
			pivot.add_child(warn)
			_clock_nodes.append({"pivot": pivot, "gears": gears, "warn": warn})
	if not hazards.is_empty():
		_hazard_mark = MeshInstance3D.new()
		var hq := PlaneMesh.new()
		hq.size = Vector2(0.95, 0.95)
		_hazard_mark.mesh = hq
		_hazard_mark.material_override = LA.ring_mat(Color(1.0, 0.2, 0.15), 0.0)
		_hazard_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hazard_mark.visible = false
		round_root.add_child(_hazard_mark)


func _end_round(winner, why: String) -> void:
	phase = "outro"
	phase_t = Cfg.ROUND_OUTRO
	stats["rounds"] += 1
	if winner != null and not smoke and _quit_at < 0.0:
		_win_cam = 0.0
		_win_target = winner.position
	if smoke:
		_update_hud()
		print("ROUND %d %s %s %ds%s" % [stats["rounds"], level_id, "draw" if winner == null else winner.display_name,
			int(round_elapsed), " sudden-death" if sudden_death else ""])
	audio.music(false)
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
	if Input.is_action_just_pressed("next_level"):
		# Try the next arena (and stay on it until L again or R).
		var i := Levels.index_of(level_id)
		forced_level = Levels.LIST[(i + 1) % Levels.LIST.size()]["id"]
		start_round()
	if tour:
		_tour_t += delta
		if _tour_t >= tour_secs:
			_tour_t = 0.0
			_tour_i += 1
			start_round()
			phase = "play"   # skip the countdown: the camera only has two seconds
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
	_update_camera(delta)
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
			audio.music(true)
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
			_update_clockwork(dt)
			_step_hazard(dt)
			mech.step(dt)
			_step_flights(dt)
			_step_bombs(dt)
			_step_flames(dt)
			_step_pickups(dt)
			_check_deaths()
			_update_endgame(dt)
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
		_belt_carry_bomb(b, dt)
		if b["fuse"] <= 0.0:
			_explode(b)
	bombs = bombs.filter(func(e): return e["alive"])


## A belt carries bombs too: post one round a corner at someone who never saw
## you lay it. It moves to the next tile only once it has crossed, and only if
## that tile will take it; a belt into a wall stacks bombs against it.
func _belt_carry_bomb(b: Dictionary, dt: float) -> void:
	var d := belt_at(b["x"], b["y"])
	if d == Vector2i.ZERO:
		return
	var step := Levels.BELT_SPEED * dt
	var nx: float = b.get("fx", float(b["x"])) + d.x * step
	var ny: float = b.get("fy", float(b["y"])) + d.y * step
	var tx := roundi(nx)
	var ty := roundi(ny)
	if tx != b["x"] or ty != b["y"]:
		if not bomb_can_enter(tx, ty, b):
			return
		bomb_at.erase(idx(b["x"], b["y"]))
		b["x"] = tx
		b["y"] = ty
		bomb_at[idx(tx, ty)] = b
	b["fx"] = nx
	b["fy"] = ny
	var node: Node3D = b["node"]
	if is_instance_valid(node):
		node.position = tile_pos(nx, ny)


func bomb_can_enter(x: int, y: int, self_bomb = null) -> bool:
	if cell_at(x, y) != EMPTY:
		return false
	var other = bomb_at.get(idx(x, y))
	if other != null and other != self_bomb:
		return false
	for f in fighters:
		if f.alive and f.tile() == Vector2i(x, y):
			if self_bomb != null and f == self_bomb["owner"] and f.ignore_bombs.has(idx(x, y)):
				continue
			return false
	return true


func _explode(b: Dictionary) -> void:
	b["alive"] = false
	bomb_at.erase(idx(b["x"], b["y"]))
	var bomber = b["owner"]
	var pid := -1
	var strength := 0.6
	if bomber != null:
		bomber.active_bombs = maxi(0, bomber.active_bombs - 1)
		pid = bomber.pid
		# Bigger bomb counts shake harder (SHAKE_PER_BOMBUP in the browser build)
		strength = minf(pow(1.36759, maxi(0, bomber.max_bombs - 1)) * 0.6, 1.6)
	var node: Node3D = b["node"]
	if is_instance_valid(node):
		node.queue_free()
	var centre := Vector2i(b["x"], b["y"])
	var world_cells: Array = []
	var broke := false
	for c in blast_cells(b["x"], b["y"], b["fire"]):
		var ci := idx(c.x, c.y)
		world_cells.append(tile_pos(c.x, c.y))
		_add_flame(c, pid)
		if cells[ci] == SOFT:
			_break_crate(c)
			broke = true
		elif pickups.has(ci) and pickups[ci]["shield"] <= 0.0:
			_remove_pickup(ci)
		if bomb_at.has(ci):
			var o: Dictionary = bomb_at[ci]
			o["fuse"] = minf(o["fuse"], Cfg.CHAIN_DELAY)
	mech.on_blast(blast_cells(b["x"], b["y"], b["fire"]))
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
			# Full size for the lethal window, snapping shut in the last 0.1 s.
			node.scale = Vector3.ONE * (1.12 * clampf(fl["t"] / 0.1, 0.25, 1.0))


func _break_crate(c: Vector2i) -> void:
	var ci := idx(c.x, c.y)
	cells[ci] = EMPTY
	soft_count -= 1
	stats["crates"] += 1
	_occ_dirty = true
	_hide_crate(ci)
	fx.crate_break(tile_pos(c.x, c.y))
	var r := rng.randf()
	var id := ""
	if r < Cfg.DROP_BOMB:
		id = "bomb"
	elif r < Cfg.DROP_BOMB + Cfg.DROP_FIRE:
		id = "fire"
	elif r < Cfg.DROP_BOMB + Cfg.DROP_FIRE + Cfg.DROP_SPEED:
		id = "speed"
	elif r < Cfg.DROP_BOMB + Cfg.DROP_FIRE + Cfg.DROP_SPEED + Cfg.DROP_SHIELD:
		id = "shield"
	if id != "":
		_spawn_pickup(c, id)


func _spawn_pickup(c: Vector2i, id: String) -> void:
	var n := Art.pickup_model(id)
	n.position = tile_pos(c.x, c.y)
	n.scale = Vector3.ONE * 0.01
	round_root.add_child(n)
	# The blast that revealed it cannot also destroy it
	pickups[idx(c.x, c.y)] = {"id": id, "node": n, "shield": Cfg.BLAST_LIFE + 0.05, "age": 0.0}


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
		var pid: String = pickups[ci]["id"]
		fx.pickup_burst(f.position, Art.PICKUP_TINT.get(pid, Color.WHITE), {"bomb": "+BOMB", "fire": "+FIRE", "speed": "+SPEED", "shield": "+SHIELD"}.get(pid, ""))
		match pid:
			"bomb":
				f.max_bombs = mini(f.max_bombs + 1, Cfg.MAX_BOMBS)
			"fire":
				f.fire = mini(f.fire + 1, Cfg.MAX_FIRE)
			"speed":
				f.speed = minf(f.speed + Cfg.SPEED_STEP, Cfg.MAX_SPEED)
				f.speed_t = Cfg.SPEED_DURATION
			"shield":
				f.shield = true
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
			if f.invuln_t > 0.0:
				continue
			if f.shield:
				# The Shield soaks this blast, then a moment's grace to get clear.
				f.shield = false
				f.invuln_t = Cfg.SHIELD_GRACE
				stats["shields"] += 1
				fx.shield_pop(f.position)
				audio.play("shield_pop")
				continue
			f.die()
			_knockout_pause()
			fx.death_puff(f.position)
			audio.play("death")
			stats["deaths"] += 1
			if flames[ci]["pid"] == f.pid:
				stats["self_kills"] += 1


func _check_round_end(dt: float) -> void:
	var alive: Array = fighters.filter(func(f): return f.alive)
	if alive.size() > 1:
		return
	if end_check_t < 0.0:
		end_check_t = 0.45   # let simultaneous deaths land before calling it
	end_check_t -= dt
	if end_check_t <= 0.0:
		_end_round(alive[0] if alive.size() == 1 else null, "")


# ---- Clockwork walls (Haunted House) ----------------------------------------------
# Port of initClockwork / updateClockwork: four three-tile walls turn a quarter
# turn together every 7.5 s. The switch happens halfway through the turn, and
# waits while anything is in the way, so a wall never lands on anyone.

func _init_clockwork() -> void:
	var all := {}
	for sec in Levels.CLOCKWORK_SECTIONS:
		for vertical in [false, true]:
			for c in Levels.clockwork_cells(sec, vertical):
				cells[idx(c.x, c.y)] = EMPTY
				all[c] = true
	for sec in Levels.CLOCKWORK_SECTIONS:
		for c in Levels.clockwork_cells(sec, false):
			cells[idx(c.x, c.y)] = HARD
	clock = {"vertical": false, "timer": Levels.CLOCKWORK_PERIOD, "turning": false, "progress": 0.0,
		"switched": false, "angle": 0.0, "start": 0.0, "target": false, "pulse": 0.0, "cells": all.keys()}


func _clock_blocked(c: Vector2i) -> bool:
	var k := idx(c.x, c.y)
	if bomb_at.has(k) or pickups.has(k) or flames.has(k) or c == hazard_target:
		return true
	for fl in flights:
		if fl["to"] == c:
			return true
	for f in fighters:
		if f.alive and f.overlaps_tile(c):
			return true
	return false


func _update_clockwork(dt: float) -> void:
	if clock.is_empty():
		return
	clock["pulse"] += dt
	if not clock["turning"]:
		clock["timer"] -= dt
		if clock["timer"] <= 0.0:
			clock["turning"] = true
			clock["progress"] = 0.0
			clock["switched"] = false
			clock["target"] = not clock["vertical"]
			clock["start"] = clock["angle"]
	if not clock["turning"]:
		return
	var nxt: float = minf(1.0, clock["progress"] + dt / Levels.CLOCKWORK_TURN)
	if not clock["switched"] and nxt >= 0.5:
		var dest: Array = []
		for sec in Levels.CLOCKWORK_SECTIONS:
			dest.append_array(Levels.clockwork_cells(sec, clock["target"]))
		var blocked := false
		for c in dest:
			if _clock_blocked(c):
				blocked = true
				break
		if blocked:
			nxt = 0.49
		else:
			for sec in Levels.CLOCKWORK_SECTIONS:
				for c in Levels.clockwork_cells(sec, clock["vertical"]):
					cells[idx(c.x, c.y)] = EMPTY
			for sec in Levels.CLOCKWORK_SECTIONS:
				for c in Levels.clockwork_cells(sec, clock["target"]):
					cells[idx(c.x, c.y)] = HARD
			clock["vertical"] = clock["target"]
			clock["switched"] = true
			_occ_dirty = true
			if not smoke:
				audio.play("wall_slam", -10.0, 0.1, 0.05)
	clock["progress"] = nxt
	var e: float = nxt * nxt * (3.0 - 2.0 * nxt)
	clock["angle"] = clock["start"] + e * PI / 2.0
	if nxt >= 1.0:
		clock["angle"] = clock["start"] + PI / 2.0
		clock["turning"] = false
		clock["progress"] = 0.0
		clock["switched"] = false
		clock["timer"] = Levels.CLOCKWORK_PERIOD


## Sudden death owns the grid: park the walls where they logically are.
func _settle_clockwork() -> void:
	if clock.is_empty():
		return
	if clock["turning"]:
		clock["angle"] = clock["start"] + (PI / 2.0 if clock["switched"] else 0.0)
	clock["turning"] = false
	clock["progress"] = 0.0
	clock["switched"] = false
	clock["timer"] = INF


# ---- Hazards: the Haunted House witch ----------------------------------------------
# Port of hazardStep: each thrower throws once every HAZARD_EVERY seconds, taking
# turns (the browser's Glacier and Pirate Fleet had several; here only the witch). The target is picked (and marked) at the start of the 1.5 s wind-up,
# then the bomb arcs over for 1.05 s, its fuse burning all the way.

func _free_hazard_tile() -> Vector2i:
	var free: Array = []
	for y in range(1, Cfg.ROWS - 1):
		for x in range(1, Cfg.COLS - 1):
			if cells[idx(x, y)] != EMPTY or bomb_at.has(idx(x, y)):
				continue
			var taken := false
			for f in fighters:
				if f.alive and f.tile() == Vector2i(x, y):
					taken = true
					break
			if not taken:
				free.append(Vector2i(x, y))
	return free[rng.randi() % free.size()] if not free.is_empty() else Vector2i(-1, -1)


func _step_hazard(dt: float) -> void:
	var count := hazards.size()
	if count == 0 or sudden_death:
		return
	hazard_t += dt
	var cadence := Levels.HAZARD_EVERY / count
	var wind_start := cadence - Levels.HAZARD_WINDUP
	if hazard_t < wind_start:
		return
	if hazard_target.x < 0:
		hazard_source = hazard_next % count
		hazard_target = _free_hazard_tile()
		if hazard_target.x < 0:
			hazard_t = 0.0
			hazard_source = -1
			return
	var h: Dictionary = hazards[hazard_source]
	if hazard_t < cadence:
		if h["node"] != null:
			Props.wind_up(h["node"], (hazard_t - wind_start) / Levels.HAZARD_WINDUP)
		return
	# Throw
	var from := tile_pos(h["pos"].x, h["pos"].y) + Vector3(0, 1.4, 0)
	if h["node"] != null:
		var held := h["node"].get_node_or_null("HeldBomb") as Node3D
		if held:
			from = held.global_position
		Props.wind_up(h["node"], -1.0)
	var dist := Vector2(hazard_target - h["pos"]).length()
	var node: Node3D = fx.make_bomb(round_root, from, true) if fx.enabled else null
	flights.append({"to": hazard_target, "from": from, "t": 0.0, "fuse": Cfg.BOMB_FUSE,
		"h": minf(1.0 + dist * 0.16, 3.0), "node": node})
	hazard_target = Vector2i(-1, -1)
	hazard_t = 0.0
	hazard_next = (hazard_source + 1) % count
	hazard_source = -1
	fx.shake = minf(0.45, fx.shake + 0.02)
	if not smoke:
		audio.play("place_bomb", -4.0, 0.1)


func _step_flights(dt: float) -> void:
	for fl in flights.duplicate():
		fl["t"] += dt
		fl["fuse"] -= dt
		var k: float = clampf(fl["t"] / Levels.HAZARD_FLIGHT, 0.0, 1.0)
		var to: Vector2i = fl["to"]
		var node = fl["node"]
		if node != null and is_instance_valid(node):
			var end := tile_pos(to.x, to.y)
			var p: Vector3 = fl["from"].lerp(end, k)
			p.y = lerpf(fl["from"].y, 0.0, k) + sin(k * PI) * fl["h"]
			node.position = p
			node.rotation.x += dt * 5.0
		if k < 1.0:
			continue
		flights.erase(fl)
		if node != null and is_instance_valid(node):
			node.rotation = Vector3.ZERO
		var ci := idx(to.x, to.y)
		if cells[ci] != EMPTY or bomb_at.has(ci):
			# Landed somewhere it cannot sit: on a bomb it sets that one off,
			# on a wall that has just closed it fizzles.
			if bomb_at.has(ci):
				bomb_at[ci]["fuse"] = minf(bomb_at[ci]["fuse"], Cfg.CHAIN_DELAY)
			if node != null and is_instance_valid(node):
				node.queue_free()
			continue
		var b := {"x": to.x, "y": to.y, "fuse": maxf(fl["fuse"], Cfg.CHAIN_DELAY), "fire": Levels.HAZARD_FIRE,
			"owner": null, "alive": true, "age": 0.0, "node": node}
		bombs.append(b)
		bomb_at[ci] = b
		fx.shake = minf(0.45, fx.shake + 0.04)


# ---- Sudden death ---------------------------------------------------------------

func _update_endgame(dt: float) -> void:
	round_elapsed += dt
	if crates_cleared_at < 0.0 and soft_count <= 0:
		crates_cleared_at = round_elapsed
	if not sudden_death:
		var since := round_elapsed - crates_cleared_at if crates_cleared_at >= 0.0 else -1.0
		if not sd_warned and since >= Cfg.CRATES_CLEAR_GRACE - Cfg.SD_WARNING:
			sd_warned = true
			audio.play("sd_warning")
		if sd_warned:
			sd_countdown = maxf(0.0, crates_cleared_at + Cfg.CRATES_CLEAR_GRACE - round_elapsed)
		if since >= Cfg.CRATES_CLEAR_GRACE or round_t <= 0.0:
			_start_sudden_death()
		return
	if not sd_queue.is_empty():
		sd_stagger -= dt
		while sd_stagger <= 0.0 and not sd_queue.is_empty():
			_drop_block(sd_queue.pop_front())
			sd_stagger += Cfg.SD_BLOCK_STAGGER
		return
	if sd_ring < Cfg.SD_MAX_RINGS:
		sd_timer -= dt
		if sd_timer <= 0.0:
			sd_timer = Cfg.SD_RING_INTERVAL
			_close_next_ring()
		return
	# As small as it gets: nobody has won, so call it a draw
	sd_done += dt
	if sd_done >= Cfg.SD_DRAW_AFTER:
		_end_round(null, "DRAW")


func _start_sudden_death() -> void:
	if sudden_death:
		return
	sudden_death = true
	sd_ring = 0
	sd_done = 0.0
	stats["sudden_deaths"] += 1
	_settle_clockwork()
	audio.play("sd_start")
	_close_next_ring()   # the first ring falls the moment the countdown reads zero
	sd_timer = Cfg.SD_RING_INTERVAL


## The tiles forming one square ring, `inset` steps in from the outer wall.
func _ring_tiles(inset: int) -> Array:
	var x0 := inset
	var x1 := Cfg.COLS - 1 - inset
	var y0 := inset
	var y1 := Cfg.ROWS - 1 - inset
	var out: Array = []
	if x0 > x1 or y0 > y1:
		return out
	for x in range(x0, x1 + 1):
		out.append(Vector2i(x, y0))
		if y1 != y0:
			out.append(Vector2i(x, y1))
	for y in range(y0 + 1, y1):
		out.append(Vector2i(x0, y))
		if x1 != x0:
			out.append(Vector2i(x1, y))
	return out


func _close_next_ring() -> void:
	while sd_ring < Cfg.SD_MAX_RINGS:
		sd_ring += 1
		sd_queue = _ring_tiles(sd_ring).filter(func(t): return cell_at(t.x, t.y) != HARD)
		if not sd_queue.is_empty():
			break
	sd_stagger = 0.0
	if not sd_queue.is_empty():
		fx.shake = minf(0.45, fx.shake + 0.12)


func _drop_block(t: Vector2i) -> void:
	if cell_at(t.x, t.y) == HARD:
		return
	var ci := idx(t.x, t.y)
	if cells[ci] == SOFT:
		soft_count -= 1
		_hide_crate(ci)
	cells[ci] = HARD
	_occ_dirty = true
	if pickups.has(ci):
		_remove_pickup(ci)
	if bomb_at.has(ci):
		var b: Dictionary = bomb_at[ci]
		b["alive"] = false
		bomb_at.erase(ci)
		if b["owner"] != null:
			b["owner"].active_bombs = maxi(0, b["owner"].active_bombs - 1)
		var bn: Node3D = b["node"]
		if is_instance_valid(bn):
			bn.queue_free()
	# Forced: anything standing there is crushed
	for f in fighters:
		if f.alive and f.tile() == t:
			f.die()
			fx.death_puff(f.position)
			audio.play("death")
			stats["deaths"] += 1
			stats["crushed"] += 1
	if not fx.enabled:
		return
	var m := MeshInstance3D.new()
	m.mesh = Art.boulder_mesh(rng.randi_range(0, 2)) if level_id == "forest" else LA.drop_block_mesh(level_id)
	m.rotation.y = rng.randf() * TAU
	m.position = tile_pos(t.x, t.y) + Vector3(0, 5.0, 0)
	round_root.add_child(m)
	_falling.append({"node": m, "y": 5.0, "vy": 0.0})


func _update_falling(delta: float) -> void:
	for b in _falling.duplicate():
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			_falling.erase(b)
			continue
		b["vy"] += 34.0 * delta
		b["y"] -= b["vy"] * delta
		if b["y"] <= 0.5:
			b["y"] = 0.5
			fx.shake = minf(0.45, fx.shake + 0.04)
			fx.crate_dust(node.position)
			audio.play("wall_slam", -4.0, 0.08, 0.07)
			_falling.erase(b)
		node.position.y = b["y"]


# ---- Presentation -----------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	if _occ_dirty:
		_refresh_occ()
	_update_falling(delta)
	_update_crate_anims(delta)
	mech.visual(delta, _time)
	for p in _props:
		if is_instance_valid(p):
			Props.animate(p, _time)
	if not clock.is_empty():
		var warning: float = 1.0 if clock["turning"] else maxf(0.0, 1.0 - clock["timer"] / Levels.CLOCKWORK_WARN)
		for cn in _clock_nodes:
			cn["pivot"].rotation.y = clock["angle"]
			var w: Node3D = cn["warn"]
			w.visible = warning > 0.01
			w.scale = Vector3(maxf(0.08, 0.18 + warning * (0.82 + 0.16 * sin(clock["pulse"] * 18.0))), 1.0, 0.7 + warning * 0.8)
			var gi := 0
			for g in cn["gears"]:
				g.rotation.y += delta * (0.7 + warning * 5.8) * (1.0 if gi == 0 else -1.4)
				gi += 1
	if _hazard_mark != null:
		var tgt := hazard_target
		if tgt.x < 0 and not flights.is_empty():
			tgt = flights[0]["to"]
		_hazard_mark.visible = tgt.x >= 0 and phase == "play"
		if _hazard_mark.visible:
			_hazard_mark.position = tile_pos(tgt.x, tgt.y) + Vector3(0, 0.03, 0)
			_hazard_mark.scale = Vector3.ONE * (0.9 + 0.1 * sin(_time * 10.0))
	for f in fighters:
		f.update_visual(delta)
	for b in bombs:
		var node: Node3D = b["node"]
		if is_instance_valid(node):
			fx.animate_bomb(node, b["age"], b["fuse"], _time)
	for k in pickups.keys():
		var p: Dictionary = pickups[k]
		var node: Node3D = p["node"]
		if not is_instance_valid(node):
			continue
		p["age"] += delta
		node.scale = Vector3.ONE * minf(1.0, 0.2 + p["age"] * 3.5)   # pops up out of the rubble
		var model := node.get_node("Model") as Node3D
		model.rotation.y += delta * 1.7
		model.position.y = 0.42 + 0.06 * sin(_time * 3.2 + k)
		var glow := node.get_node("Glow") as Node3D
		glow.scale = Vector3.ONE * (0.92 + 0.08 * sin(_time * 3.2 + k))
		if p["id"] == "fire":
			var fl := model.get_node_or_null("Flame") as Node3D
			if fl:
				fl.scale = Vector3(1.0 + 0.05 * sin(_time * 17.0 + k), 1.0 + 0.1 * sin(_time * 13.0 + k * 2.0), 1.0)


## The arrival flyover: from high and round to the side, swinging in to the
## play camera. Eased, and only on a fresh arena.
func _update_camera(delta: float) -> void:
	if _win_cam >= 0.0 and _fly < 0.0:
		# Winner close-up: ease in to the winner while they celebrate.
		_win_cam += delta
		var wk := clampf(_win_cam / 0.7, 0.0, 1.0)
		var we := 1.0 - pow(1.0 - wk, 3.0)
		var tgt := CAM_TARGET.lerp(_win_target + Vector3(0, 0.6, 0), we)
		camera.position = CAM_POS.lerp(_win_target + Vector3(0, 5.2, 3.6), we)
		camera.look_at(tgt, Vector3.UP)
		return
	if _fly < 0.0:
		return
	_fly += delta
	var k := clampf(_fly / FLY_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var off := CAM_POS - CAM_TARGET
	var start := Vector3(0.0, 24.0, 15.0)
	var yaw := lerpf(-1.25, 0.0, e)
	var o := start.lerp(off, e)
	var flat := Vector2(o.x, o.z).rotated(-yaw)
	camera.position = CAM_TARGET + Vector3(flat.x, o.y, flat.y)
	camera.look_at(CAM_TARGET, Vector3.UP)
	if k >= 1.0:
		_fly = -1.0
		camera.position = CAM_POS
		camera.look_at(CAM_TARGET, Vector3.UP)


## A beat of slow motion when someone is caught: the hit lands.
func _knockout_pause() -> void:
	if smoke or not fx.enabled:
		return
	Engine.time_scale = 0.12
	get_tree().create_timer(0.2, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _update_hud() -> void:
	if hud == null:
		return
	var secs := maxi(0, ceili(round_t))
	var banner := ""
	if phase == "play" and sudden_death:
		banner = "SUDDEN DEATH"
	elif phase == "play" and sd_warned:
		banner = "WALLS CLOSING IN  %d" % ceili(sd_countdown)
	elif phase == "play" and mech.tide_warning() > 0.0:
		banner = "TIDE COMING IN  %d" % ceili(mech.tide_warning())
	var msg := ""
	if phase == "intro":
		var n := ceili(phase_t - 0.35)
		if n > 3:
			msg = String(level.get("name", "")).to_upper()
		else:
			msg = str(n) if n >= 1 else "GO!"
	elif msg_t > 0.0:
		msg = msg_text
	var dt := get_process_delta_time()
	var sub := ""
	if phase == "intro" and ceili(phase_t - 0.35) >= 1:
		sub = ARENA_HINTS.get(level_id, "")
	hud.set_frame(_fly >= 0.0, sub, round_no == 1 and (phase == "intro" or round_elapsed < 6.0), dt)
	hud.update(dt, fighters, wins, human_pid, round_no, String(level.get("name", "")), secs, banner, msg)


# ---- Character line-up: plain ground, soft light, the four fighters side by
# side facing the camera. They stand for 2.5 s, then run on the spot.

func _setup_lineup() -> void:
	for c in round_root.get_children():
		c.queue_free()
	static_root.visible = false
	var ground := PlaneMesh.new()
	ground.size = Vector2(12, 8)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.34, 0.37, 0.33)
	gm.roughness = 0.9
	_mesh(self, ground, gm, Vector3.ZERO, false)
	for k in fighters.size():
		var f = fighters[k]
		f.gx = (Cfg.COLS - 1) * 0.5 - 2.1 + k * 1.4
		f.gy = (Cfg.ROWS - 1) * 0.5
		f.face_yaw = 0.0
		f.moving = false
		f.update_visual(0.0)
	phase = "gallery"
	camera.position = Vector3(0, 1.35, 3.6)
	camera.look_at(Vector3(0, 0.55, 0), Vector3.UP)
	get_tree().create_timer(2.5).timeout.connect(_lineup_run)


func _lineup_run() -> void:
	for f in fighters:
		f.moving = true


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
	pickups.clear()
	for i in 4:
		_spawn_pickup(Vector2i(5 + i, 7), ["bomb", "fire", "speed", "shield"][i])
	# A freshly laid bomb, to judge the fuse at close range
	var bn: Node3D = fx.make_bomb(round_root, tile_pos(9, 7))
	bombs.append({"x": 9, "y": 7, "fuse": 1.5, "fire": 2, "owner": fighters[0], "alive": true, "age": 0.4, "node": bn})
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
	demo = mode == "demo" or mode == "tour"
	tour = mode == "tour"
	if Levels.index_of(data.get("level", "")) >= 0:
		forced_level = data["level"]
	gallery = mode == "gallery" or mode == "lineup"
	lineup = mode == "lineup"
	forced_cast = data.get("cast", [])
	_shots = data.get("shots", [5.0, 9.0, 14.0])
	_shots.sort()
	_shot_dir = ProjectSettings.globalize_path("res://.godot/autotest")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_quit_at = (float(_shots.back()) if not _shots.is_empty() else 10.0) + 0.6


func _autotest_tick() -> void:
	if _quit_at < 0.0:
		return
	if _time > 2.0:
		_perf["frames"] += 1
		_perf["worst"] = maxf(_perf["worst"], get_process_delta_time())
		_perf["draws"] = maxi(_perf["draws"], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_perf["prims"] = maxi(_perf["prims"], int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	if not _shots.is_empty() and _time >= float(_shots[0]):
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%02d.png" % [_shot_dir, int(float(_shots[0]))])
		_shots.pop_front()
	if _time >= _quit_at:
		var f := FileAccess.open(_shot_dir + "/stats.txt", FileAccess.WRITE)
		if f:
			f.store_line("avg_fps=%.1f worst_frame_ms=%.1f max_draw_calls=%d max_primitives=%d" % [
				_perf["frames"] / maxf(_time - 2.0, 0.001), _perf["worst"] * 1000.0, _perf["draws"], _perf["prims"]])
			f.close()
		get_tree().quit()


# ---- Headless smoke test ---------------------------------------------------------

func _run_smoke() -> void:
	var t := 0.0
	var want := Levels.LIST.size() * 2
	var ri := OS.get_cmdline_user_args().find("--smoke-rounds")
	if ri >= 0 and ri + 1 < OS.get_cmdline_user_args().size():
		want = int(OS.get_cmdline_user_args()[ri + 1])
	while t < 200.0 * want and stats["rounds"] < want:
		sim_step(Cfg.FIXED_DT)
		t += Cfg.FIXED_DT
	var decided: int = stats["rounds"] - stats["draws"]
	var ok: bool = stats["rounds"] >= 3 and decided >= 1 and stats["bombs"] > 0 and stats["crates"] > 0
	print("SMOKE %s levels=%s rounds=%d decided=%d draws=%d sudden_deaths=%d crushed=%d wins=%s deaths=%d self_kills=%d bombs=%d crates=%d pickups=%d shields=%d doused=%d sim_seconds=%d" % [
		"OK" if ok else "FAIL", ",".join(PackedStringArray(_smoke_levels)), stats["rounds"], decided, stats["draws"], stats["sudden_deaths"], stats["crushed"], str(stats["wins"]),
		stats["deaths"], stats["self_kills"], stats["bombs"], stats["crates"], stats["pickups"], stats["shields"], stats["doused"], int(t)])
	get_tree().quit(0 if ok else 1)
