extends Node3D
## One fighter: grid movement, bomb laying and its animated model.
## Movement is a port of Player.update / slide / blockedAt in ../index.html.

const Cfg := preload("res://scripts/config.gd")
const R := Cfg.PLAYER_RADIUS
const TARGET_HEIGHT := 1.25   # every fighter stands the same height (uniform-height rule); sized to read on a phone

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

var model: Node3D = null
var anim: AnimationPlayer = null
var _anim_names := {}
var _cur := ""
var _death_t := 0.0


func setup(g, id_: int, info: Dictionary, bot: bool) -> void:
	game = g
	pid = id_
	char_id = info["id"]
	display_name = info["name"]
	color = info["color"]
	is_bot = bot
	_build_model()
	_build_marker()


func _build_model() -> void:
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


func _build_marker() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.02
	cm.radial_segments = 24
	disc.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.7)
	disc.material_override = m
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.015
	add_child(disc)
	if not is_bot:
		var tag := Label3D.new()
		tag.text = "YOU"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 64
		tag.pixel_size = 0.006
		tag.outline_size = 16
		tag.modulate = color
		tag.no_depth_test = true
		tag.position.y = 1.7
		add_child(tag)


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
	ignore_bombs.clear()
	moving = false
	celebrating = false
	face_yaw = 0.0
	rotation.y = 0.0
	_death_t = 0.0
	_cur = ""
	_play("idle")
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
	_play("death")


func celebrate() -> void:
	celebrating = true
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
	var stp := speed * dt
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
	_release_bombs()
	if want_bomb:
		game.try_place_bomb(self)


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
		rotation.y = lerp_angle(rotation.y, face_yaw, clampf(delta * 14.0, 0.0, 1.0))
	else:
		rotation.y = face_yaw
	if not alive:
		_death_t += delta
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
