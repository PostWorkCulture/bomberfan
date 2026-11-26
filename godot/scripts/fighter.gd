extends Node3D
## One fighter: grid movement, bomb laying and its animated model.
## Movement is a port of Player.update / slide / blockedAt in ../index.html.

const Cfg := preload("res://scripts/config.gd")
const ModelBot := preload("res://scripts/model_bot.gd")
const Levels := preload("res://scripts/levels.gd")
const R := Cfg.PLAYER_RADIUS
const TARGET_HEIGHT := 1.45   # every fighter stands the same height (uniform-height rule); sized to read on a phone (1.25 → 1.45, AAA review)

var game = null
var pid := 0
var char_id := ""
var display_name := ""
var color := Color.WHITE
var is_bot := false

var alive := true
var gx := 1.0
var gy := 1.0
var speed := Cfg.BASE_SPEED
var speed_t := 0.0
var max_bombs := Cfg.START_BOMBS
var fire := Cfg.START_FIRE
var active_bombs := 0
var ignore_bombs := {}     # bomb tiles we are allowed to walk off
var face_yaw := 0.0
var moving := false
var celebrating := false
var shield := false       # Shield pick-up: soaks one blast
var invuln_t := 0.0       # after the shield pops: a moment to get clear
var _bubble: MeshInstance3D = null

var model: Node3D = null
var anim: AnimationPlayer = null
var robot = null            # set for the Blender bomber-bots, which animate in code (model_bot.gd)
var _anim_names := {}
var _cur := ""
var _death_t := 0.0
var _yaw := 0.0
const CAMERA_LEAN := 0.22
var lean := CAMERA_LEAN
var _model_base_y := 0.0


func setup(g, id_: int, info: Dictionary, bot: bool) -> void:
	game = g
	pid = id_
	char_id = info["id"]
	display_name = info["name"]
	color = info["color"]
	dark_body = info.get("dark", false)
	lean = info.get("lean", CAMERA_LEAN)
	is_bot = bot
	_build_model()
	_apply_outline()
	_build_marker()
	_build_bubble()


func _build_model() -> void:
	var glb := "res://assets/characters/%s.glb" % char_id
	var baked := "res://assets/characters/%s-merged.res" % char_id
	if ResourceLoader.exists(baked) or ResourceLoader.exists(glb):
		# A rigid Blender bomber-bot: no skeleton, so model_bot.gd moves it.
		model = Node3D.new()
		add_child(model)
		robot = ModelBot.new()
		robot.setup(glb)
		if char_id == "tick":
			robot.add_hat_face(color)
		model.add_child(robot)
		_normalise_height()
		return
	var path := "res://assets/characters/%s.gltf" % char_id
	var ps = load(path) if ResourceLoader.exists(path) else null
	if ps is PackedScene:
		model = ps.instantiate()
		add_child(model)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if players.size() > 0:
			anim = players[0] as AnimationPlayer
			for n in anim.get_animation_list():
				var full := String(n)
				var key := full.get_slice("|", full.get_slice_count("|") - 1).to_lower()
				_anim_names[key] = full
			for k in ["idle", "run", "walk"]:
				if _anim_names.has(k):
					anim.get_animation(_anim_names[k]).loop_mode = Animation.LOOP_LINEAR
		else:
			push_warning("No AnimationPlayer in %s" % path)
		_normalise_height()
	else:
		push_warning("Could not load %s, using a placeholder body" % path)
		model = Node3D.new()
		add_child(model)
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 0.9
		body.mesh = cap
		body.position.y = 0.45
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		body.material_override = m
		model.add_child(body)


func _normalise_height() -> void:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first or box.size.y <= 0.001:
		return
	var s := TARGET_HEIGHT / box.size.y
	model.scale = Vector3.ONE * s
	model.position.y = -box.position.y * s
	_model_base_y = model.position.y


## Every fighter wears an outline and a rim light in their colour, so they are
## the clearest thing on any floor (AAA review: fighters must out-read the
## arena). Inverted hull in world space, plus an additive fresnel pass. The
## outline is dark on light arenas and light on dark ones (set_outline).
const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, world_vertex_coords, depth_draw_opaque;
uniform vec4 line_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float thick = 0.035;
void vertex() { VERTEX += normalize(NORMAL) * thick; }
void fragment() { ALBEDO = line_col.rgb; }
"""
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 rim_col : source_color = vec4(1.0);
uniform float power = 2.2;
uniform float strength = 0.9;
uniform float lift = 0.0;   // a soft fill in the fighter's colour on dark arenas
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = rim_col.rgb * (f * strength + lift);
}
"""
var _outline_mat: ShaderMaterial
var _rim_mat: ShaderMaterial


var _ghost_level := 0.0


func _set_ghost(v: float) -> void:
	if is_equal_approx(v, _ghost_level) or model == null:
		return
	_ghost_level = v
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).transparency = v if v < 1.0 else 0.0


func _apply_outline() -> void:
	_outline_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	_outline_mat.shader = sh
	_rim_mat = ShaderMaterial.new()
	var rs := Shader.new()
	rs.code = RIM_SHADER
	_rim_mat.shader = rs
	_rim_mat.set_shader_parameter("rim_col", color.lightened(0.25))
	_outline_mat.next_pass = _rim_mat
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = _outline_mat
	set_outline(false)


var _dark_arena := false
var dark_body := false   # Razor, Tick: a dark model needs a light line on any floor


## Outline and rim by body and floor (AAA review round 2): a dark body always
## gets a light line in its colour; light bodies get a dark line on light
## floors and a line in their own colour on dark ones. Your own fighter gets
## an extra lift so you find yourself first.
func set_outline(dark_arena: bool) -> void:
	_dark_arena = dark_arena
	if _outline_mat == null:
		return
	var line: Color
	var thick := 0.022
	var rim := 0.5
	var lift := 0.0
	# On dark floors: a softer rim and more body fill, so fighters read as
	# solid figures rather than neon line drawings (AAA review round 3).
	if dark_body:
		line = color.lightened(0.3)
		thick = 0.028 if dark_arena else 0.024
		rim = 0.5
		lift = 0.2 if dark_arena else 0.12
	elif dark_arena:
		line = color
		rim = 0.45
		lift = 0.18
	else:
		line = color.darkened(0.75)
		thick = 0.026
		rim = 0.45
	# Your own fighter is found by the ring and arrow (_build_marker), not by
	# washing the body out with lift (AAA review round 7).
	if not is_bot:
		lift = 0.26 if dark_arena else 0.12
		line = line.lightened(0.15)
	# The rim is a second pass per surface: on dark floors it is every body's
	# fill (without it metal bots go black); elsewhere only dark bodies and you.
	_outline_mat.next_pass = _rim_mat if (dark_arena or dark_body or not is_bot) else null
	_outline_mat.set_shader_parameter("line_col", line)
	_outline_mat.set_shader_parameter("thick", thick)
	_rim_mat.set_shader_parameter("strength", rim)
	_rim_mat.set_shader_parameter("lift", lift)
	# On dark floors the rim goes pale, so a red bot never reads as a wine
	# casket (AAA review round 8); your ring burns brighter there.
	_rim_mat.set_shader_parameter("rim_col", color.lerp(Color(1.0, 0.96, 0.86), 0.5) if dark_arena else color.lightened(0.25))
	if _ring:
		(_ring.material_override as ShaderMaterial).set_shader_parameter("col", Color(color.lightened(0.35 if dark_arena else 0.2), 1.0))


const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.58, 0.68, d) * (1.0 - smoothstep(0.86, 0.97, d));
	float pulse = 0.8 + 0.2 * sin(TIME * 4.0);
	ALBEDO = col.rgb * 1.6;
	ALPHA = clamp(ring * col.a * pulse + (1.0 - smoothstep(0.0, 0.62, d)) * 0.18 * col.a, 0.0, 1.0);
}
"""

var _ring: MeshInstance3D = null
var _arrow: MeshInstance3D = null


## Your own fighter: a pulsing ring on the floor in your colour and a bobbing
## arrow over your head (Super Bomberman R 2 style), so you find yourself at a
## glance on a phone. Both ignore the fighter's lean (top_level).
func _build_marker() -> void:
	if is_bot:
		return
	_ring = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.35, 1.35)
	q.orientation = PlaneMesh.FACE_Y
	_ring.mesh = q
	var rm := ShaderMaterial.new()
	var rs := Shader.new()
	rs.code = RING_SHADER
	rm.shader = rs
	rm.set_shader_parameter("col", Color(color.lightened(0.2), 1.0))
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.top_level = true
	add_child(_ring)
	# A flat chevron lying level, pointing down the screen at you, with a dark
	# border so it reads on any floor.
	_arrow = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in 2:
		var k := 1.0 if layer == 0 else 0.62
		var y := 0.0 if layer == 0 else 0.01
		st.set_color(Color(0.06, 0.06, 0.1) if layer == 0 else Color.WHITE)
		for v in [Vector3(-0.3, y, -0.12), Vector3(0.3, y, -0.12), Vector3(0, y, 0.26)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x * k, v.y, (v.z - 0.0) * k + (0.02 if layer == 1 else 0.0)))
	_arrow.mesh = st.commit()
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = color.lightened(0.45)
	am.vertex_color_use_as_albedo = true
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	am.no_depth_test = true
	am.render_priority = 3
	_arrow.material_override = am
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.top_level = true
	add_child(_arrow)
	var tag := Label3D.new()
	tag.text = "YOU"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font = load("res://assets/fonts/lilita-one.ttf")
	tag.font_size = 84
	tag.pixel_size = 0.006
	tag.outline_size = 20
	tag.outline_modulate = Color(0.03, 0.03, 0.06)
	tag.modulate = color.lightened(0.35)
	tag.no_depth_test = true
	tag.top_level = true
	tag.name = "YouTag"
	add_child(tag)


func _place_marker() -> void:
	if _ring == null:
		return
	var on := alive and visible
	_ring.visible = on
	_arrow.visible = on
	var tag := get_node_or_null("YouTag") as Label3D
	var bob := sin(Time.get_ticks_msec() * 0.006) * 0.08
	var p := global_position
	_ring.global_transform = Transform3D(Basis(), p + Vector3(0, 0.03, 0))
	_arrow.global_transform = Transform3D(Basis(), p + Vector3(0, TARGET_HEIGHT + 0.42 + bob, -0.1))
	if tag:
		tag.visible = on
		# In the top two rows the tag would sit on the timer pill: put it at
		# your feet instead (the arrow stays overhead).
		var top := p.z < -(Cfg.ROWS * 0.5 - 2.6)
		tag.global_position = p + (Vector3(0, 0.3, 0.85) if top else Vector3(0, TARGET_HEIGHT + 0.95 + bob, -0.15))


## The Shield pick-up's bubble: a soft violet glass sphere round the fighter.
func _build_bubble() -> void:
	_bubble = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.62
	sm.height = 1.24
	sm.radial_segments = 24
	sm.rings = 12
	_bubble.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.55, 0.4, 1.0, 0.16)
	m.rim_enabled = false
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_bubble.material_override = m
	_bubble.position.y = 0.62
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.visible = false
	add_child(_bubble)


# ---- Round state ------------------------------------------------------------

func spawn_at(t: Vector2i) -> void:
	gx = t.x
	gy = t.y
	alive = true
	visible = true
	speed = Cfg.BASE_SPEED
	speed_t = 0.0
	max_bombs = Cfg.START_BOMBS
	fire = Cfg.START_FIRE
	active_bombs = 0
	shield = false
	invuln_t = 0.0
	ignore_bombs.clear()
	moving = false
	celebrating = false
	face_yaw = 0.0
	_yaw = 0.0
	rotation.y = 0.0
	_death_t = 0.0
	if model:
		model.position.y = _model_base_y
		model.rotation.y = 0.0
	set_outline(_dark_arena)
	_cur = ""
	_play("idle")
	if robot:
		robot.revive()
	update_visual(0.0)


func tile() -> Vector2i:
	return Vector2i(roundi(gx), roundi(gy))


func overlaps_tile(t: Vector2i) -> bool:
	return t.x >= floori(gx - R + 0.5) and t.x <= floori(gx + R + 0.5) \
		and t.y >= floori(gy - R + 0.5) and t.y <= floori(gy + R + 0.5)


func die() -> void:
	alive = false
	moving = false
	_death_t = 0.0
	if model:
		model.position.y = _model_base_y
	_play("death")
	if robot:
		robot.die()


func celebrate() -> void:
	celebrating = true
	if robot:
		robot.cheer()
	if _anim_names.has("wave"):
		_play("wave")
	else:
		_play("yes")


# ---- Movement ---------------------------------------------------------------

func blocked_at(px: float, py: float) -> bool:
	var x0 := floori(px - R + 0.5)
	var x1 := floori(px + R + 0.5)
	var y0 := floori(py - R + 0.5)
	var y1 := floori(py + R + 0.5)
	var hx0 := floori(gx - R + 0.5)
	var hx1 := floori(gx + R + 0.5)
	var hy0 := floori(gy - R + 0.5)
	var hy1 := floori(gy + R + 0.5)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if game.cell_at(x, y) != 0:   # 0 = EMPTY; walls and crates block
				return true
			var k: int = game.idx(x, y)
			if game.bomb_at.has(k):
				if ignore_bombs.has(k):
					continue
				if x >= hx0 and x <= hx1 and y >= hy0 and y <= hy1:
					continue   # already overlapping it: you may walk off
				return true
	return false


func _slide(axis_x: bool, delta: float) -> bool:
	var rem := delta
	for i in 4:
		if absf(rem) <= 0.0001:
			break
		var nx := gx + rem if axis_x else gx
		var ny := gy if axis_x else gy + rem
		if not blocked_at(nx, ny):
			gx = nx
			gy = ny
			return true
		rem *= 0.5
	return false


func _move(d: Vector2i, dt: float) -> bool:
	var stp: float = speed * dt * game.move_mult(tile())
	if d.x != 0:
		face_yaw = PI / 2.0 if d.x > 0 else -PI / 2.0
		gy = move_toward(gy, float(roundi(gy)), stp * Cfg.TURN_SNAP)
		return _slide(true, d.x * stp)
	face_yaw = 0.0 if d.y > 0 else PI
	gx = move_toward(gx, float(roundi(gx)), stp * Cfg.TURN_SNAP)
	return _slide(false, d.y * stp)


## dir is the main direction; alt is tried only when dir is blocked head-on
## (already centred), so holding two keys turns corners cleanly.
func step(dt: float, dir: Vector2i, alt: Vector2i, want_bomb: bool) -> void:
	if not alive:
		return
	invuln_t = maxf(0.0, invuln_t - dt)
	if speed_t > 0.0:
		speed_t -= dt
		if speed_t <= 0.0:
			speed_t = 0.0
			speed = Cfg.BASE_SPEED
	var moved := false
	if dir != Vector2i.ZERO:
		moved = _move(dir, dt)
		if not moved and alt != Vector2i.ZERO:
			var centred := absf(gy - roundf(gy)) < 0.01 if dir.x != 0 else absf(gx - roundf(gx)) < 0.01
			if centred:
				moved = _move(alt, dt)
	moving = moved
	_floor_rules(dt)
	_release_bombs()
	if want_bomb:
		game.try_place_bomb(self)


## Conveyor belts, judged on the tile under your centre. A belt only
## carries: it never steers you, so walking across one works.
func _floor_rules(dt: float) -> void:
	var t := tile()
	var belt: Vector2i = game.belt_at(t.x, t.y)
	if belt != Vector2i.ZERO:
		var carry: float = Levels.BELT_SPEED * dt
		_slide(belt.x != 0, (belt.x + belt.y) * carry)


func _release_bombs() -> void:
	if ignore_bombs.is_empty():
		return
	for k in ignore_bombs.keys():
		var t := Vector2i(k % Cfg.COLS, k / Cfg.COLS)
		if not game.bomb_at.has(k) or not overlaps_tile(t):
			ignore_bombs.erase(k)


# ---- Visuals ------------------------------------------------------------------

func update_visual(delta: float) -> void:
	position = game.tile_pos(gx, gy)
	if delta > 0.0:
		_yaw = lerp_angle(_yaw, face_yaw, clampf(delta * 14.0, 0.0, 1.0))
	else:
		_yaw = face_yaw
	# A small lean towards the camera so faces and fronts show from above.
	basis = Basis(Vector3.RIGHT, lean) * Basis(Vector3.UP, _yaw)
	_place_marker()
	if robot:
		robot.animate(delta, moving and alive, speed / Cfg.BASE_SPEED)
	# Tall grass (Forest): a bot in it is hidden from you, unless you are close
	# enough that a bot would see you (the same GRASS_SEE rule): then it shows
	# as a faint ghost. The grass rustles over anyone moving in it.
	if model:
		var ghost := 0.0
		if is_bot and alive and game.mech.hidden(self):
			var me = game.human_fighter()
			ghost = 0.6 if me != null and game.mech.can_see(me, self) else 1.0
		_set_ghost(ghost)
		model.visible = ghost < 1.0
		if invuln_t > 0.0 and alive:
			model.visible = model.visible and fmod(invuln_t * 14.0, 1.0) < 0.6
	if _bubble:
		_bubble.visible = shield and alive and (model == null or model.visible or not is_bot)
		if _bubble.visible:
			_bubble.scale = Vector3.ONE * (1.0 + 0.03 * sin(Time.get_ticks_msec() * 0.006))
	if not alive:
		_death_t += delta
		# Knocked out: a white flash, tossed up spinning, then down to the ground.
		if model:
			var k := clampf(_death_t / 0.55, 0.0, 1.0)
			model.position.y = _model_base_y + sin(k * PI) * 0.9
			model.rotation.y = k * TAU * 1.5
		if _rim_mat:
			_rim_mat.set_shader_parameter("strength", maxf(0.0, 3.5 - _death_t * 8.0))
		if _death_t > 2.0:
			visible = false
		return
	if celebrating:
		return
	if moving:
		_play("run")
		if anim:
			anim.speed_scale = clampf(speed / Cfg.BASE_SPEED, 1.0, 1.8)
	else:
		_play("idle")
		if anim:
			anim.speed_scale = 1.0


func _play(key: String) -> void:
	if anim == null or _cur == key:
		return
	var n: String = _anim_names.get(key, "")
	if n == "" and key == "run":
		n = _anim_names.get("walk", "")
	if n == "":
		return
	_cur = key
	anim.play(n, 0.15)
