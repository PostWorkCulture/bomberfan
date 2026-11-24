extends Node3D
## Simple bomber-bots, built from primitives in code and animated in code (no
## rigs, no imported models). Four styles with distinct silhouettes so they
## read from the top-down camera; each wears its player's team colour.
## Faces +Z, like the imported fighters did.

const Art := preload("res://scripts/art.gd")

var style := "bolt"
var team := Color.WHITE
var _hips: Node3D
var _body: Node3D
var _head: Node3D
var _legs: Array = []
var _arms: Array = []
var _eyes: Array = []
var _treads: Array = []
var _hover: Node3D
var _t := 0.0
var _blink := 2.0
var _dead_t := -1.0
var _cheer := false


func setup(style_name: String, team_colour: Color) -> void:
	style = style_name
	team = team_colour
	_hips = Node3D.new()
	add_child(_hips)
	match style:
		"tank":
			_build_tank()
		"pip":
			_build_pip()
		"sparky":
			_build_sparky()
		_:
			_build_bolt()


# ---- materials -------------------------------------------------------------------------

func _team(shade := 1.0) -> StandardMaterial3D:
	return Art.flat_mat(Color(team.r * shade, team.g * shade, team.b * shade), 0.45, 0.1)


func _metal() -> StandardMaterial3D:
	return Art.flat_mat(Color(0.22, 0.24, 0.28), 0.4, 0.6)


func _light() -> StandardMaterial3D:
	return Art.flat_mat(Color(0.9, 0.91, 0.93), 0.35, 0.05)


func _glow(c: Color) -> StandardMaterial3D:
	var key := "robot_glow_%s" % c.to_html()
	if Art._cache.has(key):
		return Art._cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	Art._cache[key] = m
	return m


func _box(size: Vector3, r: float) -> Mesh:
	var key := "robot_box_%s_%s" % [size, r]
	if not Art._cache.has(key):
		Art._cache[key] = Art.rounded_box(size, r, 2)
	return Art._cache[key]


func _sphere(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 20
	s.rings = 10
	return s


func _cyl(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 14
	return c


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return Art._part(parent, mesh, mat, pos, rot, scl)


## A limb that swings from a pivot: returns the pivot.
func _limb(parent: Node3D, at: Vector3, length: float, radius: float, mat: Material, end_mesh: Mesh, end_mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	_part(pivot, cap, mat, Vector3(0, -length * 0.5, 0))
	if end_mesh:
		_part(pivot, end_mesh, end_mat, Vector3(0, -length, 0.02))
	return pivot


# ---- the four styles ---------------------------------------------------------------------

## BOLT: the classic — round helmet head, glowing visor, antenna, stubby limbs.
func _build_bolt() -> void:
	_hips.position.y = 0.3
	for side in [-1.0, 1.0]:
		var leg := _limb(_hips, Vector3(side * 0.1, 0, 0), 0.22, 0.065, _metal(), _box(Vector3(0.15, 0.07, 0.22), 0.03), _team(0.8))
		_legs.append(leg)
	_body = Node3D.new()
	_hips.add_child(_body)
	_part(_body, _box(Vector3(0.44, 0.36, 0.32), 0.1), _team(), Vector3(0, 0.2, 0))
	_part(_body, _box(Vector3(0.26, 0.16, 0.04), 0.03), _light(), Vector3(0, 0.22, 0.16))
	_part(_body, _sphere(0.035), _glow(Color(1.0, 0.85, 0.3)), Vector3(0, 0.22, 0.185))
	for side in [-1.0, 1.0]:
		var arm := _limb(_body, Vector3(side * 0.27, 0.33, 0), 0.22, 0.05, _metal(), _sphere(0.07), _team(0.85))
		arm.rotation.z = side * 0.18
		_arms.append(arm)
	_head = Node3D.new()
	_head.position.y = 0.6
	_body.add_child(_head)
	_part(_head, _sphere(0.25), _light(), Vector3.ZERO)
	var visor := _part(_head, _box(Vector3(0.36, 0.12, 0.08), 0.05), _metal(), Vector3(0, 0.02, 0.2))
	for side in [-1.0, 1.0]:
		_eyes.append(_part(_head, _sphere(0.04), _glow(Color(0.35, 0.95, 1.0)), Vector3(side * 0.08, 0.02, 0.245), Vector3.ZERO, Vector3(1, 1, 0.5)))
	_part(_head, _cyl(0.012, 0.012, 0.16), _metal(), Vector3(0.06, 0.3, -0.02), Vector3(0, 0, -0.25))
	_part(_head, _sphere(0.045), _glow(team.lightened(0.3)), Vector3(0.1, 0.38, -0.02))
	visor.name = "Visor"


## TANK: chunky, on caterpillar treads, one big eye, boxy arms.
func _build_tank() -> void:
	_hips.position.y = 0.0
	for side in [-1.0, 1.0]:
		var tread := Node3D.new()
		tread.position = Vector3(side * 0.2, 0.09, 0)
		_hips.add_child(tread)
		_part(tread, _box(Vector3(0.14, 0.18, 0.46), 0.08), _metal(), Vector3.ZERO)
		for k in 3:
			_part(tread, _cyl(0.06, 0.06, 0.02), _team(0.7), Vector3(side * 0.075, 0, -0.14 + k * 0.14), Vector3(0, 0, PI / 2))
		_treads.append(tread)
	_body = Node3D.new()
	_body.position.y = 0.18
	_hips.add_child(_body)
	_part(_body, _box(Vector3(0.48, 0.32, 0.4), 0.07), _team(), Vector3(0, 0.16, 0))
	_part(_body, _box(Vector3(0.5, 0.06, 0.42), 0.03), _metal(), Vector3(0, 0.04, 0))
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.3, 0.26, 0)
		_body.add_child(arm)
		_part(arm, _box(Vector3(0.1, 0.24, 0.12), 0.04), _metal(), Vector3(0, -0.08, 0))
		_part(arm, _box(Vector3(0.12, 0.08, 0.14), 0.03), _team(0.8), Vector3(0, -0.22, 0.02))
		_arms.append(arm)
	_head = Node3D.new()
	_head.position.y = 0.32
	_body.add_child(_head)
	_part(_head, _box(Vector3(0.34, 0.22, 0.3), 0.06), _light(), Vector3(0, 0.11, 0))
	_part(_head, _cyl(0.085, 0.085, 0.04), _metal(), Vector3(0, 0.11, 0.15), Vector3(PI / 2, 0, 0))
	_eyes.append(_part(_head, _sphere(0.06), _glow(Color(1.0, 0.3, 0.2)), Vector3(0, 0.11, 0.165), Vector3.ZERO, Vector3(1, 1, 0.45)))
	_part(_head, _box(Vector3(0.06, 0.1, 0.06), 0.02), _team(0.8), Vector3(-0.12, 0.26, -0.05))


## PIP: a small round drone hovering on a glowing ring, floating hands, ear fins.
func _build_pip() -> void:
	_hips.position.y = 0.22
	_hover = Node3D.new()
	_hover.position.y = -0.14
	_hips.add_child(_hover)
	_part(_hover, _cyl(0.2, 0.16, 0.05), _metal(), Vector3.ZERO)
	var ring := _part(_hover, _cyl(0.17, 0.17, 0.012), _glow(team.lightened(0.35)), Vector3(0, -0.03, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body = Node3D.new()
	_hips.add_child(_body)
	_part(_body, _sphere(0.27), _team(), Vector3(0, 0.22, 0), Vector3.ZERO, Vector3(1, 0.92, 1))
	_part(_body, _sphere(0.2, true), _light(), Vector3(0, 0.3, 0.05), Vector3(-0.35, 0, 0), Vector3(1, 0.9, 0.9))
	_head = Node3D.new()
	_head.position.y = 0.22
	_body.add_child(_head)
	for side in [-1.0, 1.0]:
		_eyes.append(_part(_head, _sphere(0.045), _glow(Color(0.4, 1.0, 0.75)), Vector3(side * 0.085, 0.06, 0.235), Vector3.ZERO, Vector3(0.8, 1.25, 0.5)))
		_part(_head, _cyl(0.0, 0.05, 0.14), _team(0.75), Vector3(side * 0.2, 0.25, 0), Vector3(0, 0, -side * 0.55))
		var hand := Node3D.new()
		hand.position = Vector3(side * 0.36, 0.14, 0.04)
		_body.add_child(hand)
		_part(hand, _sphere(0.07), _metal(), Vector3.ZERO)
		_arms.append(hand)


## SPARKY: tall and slim, a TV-screen face and a bomb on its back.
func _build_sparky() -> void:
	_hips.position.y = 0.36
	for side in [-1.0, 1.0]:
		var leg := _limb(_hips, Vector3(side * 0.08, 0, 0), 0.3, 0.045, _metal(), _box(Vector3(0.12, 0.06, 0.2), 0.025), _team(0.8))
		_legs.append(leg)
	_body = Node3D.new()
	_hips.add_child(_body)
	_part(_body, _box(Vector3(0.3, 0.34, 0.24), 0.08), _team(), Vector3(0, 0.18, 0))
	_part(_body, _sphere(0.13), Art.flat_mat(Color(0.05, 0.055, 0.07), 0.4, 0.05), Vector3(0, 0.22, -0.2))
	_part(_body, _cyl(0.012, 0.015, 0.1), Art.flat_mat(Color(0.8, 0.7, 0.5)), Vector3(0.03, 0.38, -0.22), Vector3(0, 0, -0.5))
	_part(_body, _sphere(0.022), _glow(Color(1.0, 0.75, 0.3)), Vector3(0.06, 0.43, -0.22))
	for side in [-1.0, 1.0]:
		var arm := _limb(_body, Vector3(side * 0.2, 0.32, 0), 0.26, 0.04, _metal(), _sphere(0.055), _team(0.85))
		arm.rotation.z = side * 0.12
		_arms.append(arm)
	_head = Node3D.new()
	_head.position.y = 0.5
	_body.add_child(_head)
	_part(_head, _cyl(0.03, 0.03, 0.08), _metal(), Vector3(0, -0.04, 0))
	_part(_head, _box(Vector3(0.4, 0.3, 0.26), 0.06), _team(0.75), Vector3(0, 0.15, 0))
	_part(_head, _box(Vector3(0.32, 0.22, 0.04), 0.04), Art.flat_mat(Color(0.04, 0.06, 0.08), 0.2), Vector3(0, 0.15, 0.12))
	for side in [-1.0, 1.0]:
		_eyes.append(_part(_head, _box(Vector3(0.06, 0.09, 0.02), 0.015), _glow(Color(0.5, 1.0, 0.95)), Vector3(side * 0.07, 0.17, 0.145)))
	_part(_head, _box(Vector3(0.1, 0.02, 0.02), 0.008), _glow(Color(0.5, 1.0, 0.95)), Vector3(0, 0.08, 0.145))
	for side in [-1.0, 1.0]:
		_part(_head, _cyl(0.008, 0.008, 0.16), _metal(), Vector3(side * 0.08, 0.36, -0.02), Vector3(0, 0, side * 0.4))


# ---- animation -------------------------------------------------------------------------------

func die() -> void:
	_dead_t = 0.0


func revive() -> void:
	_dead_t = -1.0
	_cheer = false
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	if _body:
		_body.rotation = Vector3.ZERO


func cheer() -> void:
	_cheer = true


## speed01: 0 standing, 1 running at base speed (more when boosted).
func animate(delta: float, moving: bool, speed01: float) -> void:
	_t += delta
	if _dead_t >= 0.0:
		_dead_t += delta
		var k := clampf(_dead_t / 0.45, 0.0, 1.0)
		rotation.x = lerpf(0.0, -PI / 2.0, k * k)
		position.y = 0.12 * sin(k * PI)
		for e in _eyes:
			e.visible = false
		return
	for e in _eyes:
		e.visible = true
	_blink -= delta
	var eye_y := 1.0
	if _blink < 0.12:
		eye_y = 0.15
		if _blink < 0.0:
			_blink = randf_range(2.0, 4.5)
	for e in _eyes:
		e.scale.y = eye_y * (1.25 if style == "pip" else 1.0)
	var cycle := _t * (9.0 + 4.0 * speed01)
	var walk := 1.0 if moving else 0.0
	if _cheer:
		position.y = absf(sin(_t * 7.0)) * 0.22
		rotation.y += delta * 5.0
		for a in _arms:
			a.rotation.x = -2.6
		return
	position.y = 0.0
	match style:
		"tank":
			_body.position.y = 0.18 + (0.012 * sin(cycle * 2.0) if moving else 0.008 * sin(_t * 2.2))
			_body.rotation.x = 0.08 * walk
			for i in _arms.size():
				_arms[i].rotation.x = (sin(cycle + i * PI) * 0.35) * walk
		"pip":
			_hips.position.y = 0.22 + 0.04 * sin(_t * 3.0)
			_body.rotation.x = 0.28 * walk
			_hover.rotation.y += delta * (6.0 + 8.0 * walk)
			for i in _arms.size():
				_arms[i].position.y = 0.14 + 0.04 * sin(_t * 3.0 + i * PI + 0.6)
				_arms[i].position.z = 0.04 - 0.08 * walk
		_:
			var swing := 0.75 if style == "sparky" else 0.6
			for i in _legs.size():
				_legs[i].rotation.x = sin(cycle + i * PI) * swing * walk
			for i in _arms.size():
				_arms[i].rotation.x = -sin(cycle + i * PI) * swing * 0.9 * walk
			var base_y := _hips.position.y
			_body.position.y = absf(sin(cycle)) * 0.035 * walk + (0.01 * sin(_t * 2.4) if not moving else 0.0)
			_body.rotation.x = 0.1 * walk
			_head.rotation.z = 0.05 * sin(cycle) * walk
			_hips.position.y = base_y
