extends Node3D
## Visual effects: bombs, explosions, debris, scorch marks, flashes and camera
## shake. Purely presentation — nothing here changes the rules, so the smoke
## test runs with it switched off.

const Art := preload("res://scripts/art.gd")
const Cfg := preload("res://scripts/config.gd")

const MAX_FLASH_LIGHTS := 2
const SCORCH_LIFE := 7.0

var enabled := true
var shake := 0.0
var _flash_lights := 0
var _quad: QuadMesh
var _fire_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _scorch_mat: StandardMaterial3D
var _debris_mesh: BoxMesh
var _fire_ramp: Gradient
var _flash_ramp: Gradient
var _spark_ramp: Gradient
var _smoke_ramp: Gradient
var _dust_ramp: Gradient
var _grow: Curve
var _shrink: Curve
var _bomb_body: SphereMesh
var _bomb_cap: CylinderMesh
var _fuse: CylinderMesh
var _spark_dot: SphereMesh
var _scorches: Array = []
var _tip_mat: StandardMaterial3D
var _add_mat: StandardMaterial3D


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_fire_mat = _particle_mat(false)
	_add_mat = _particle_mat(true)
	_smoke_mat = _particle_mat(false)
	_glow_mat = _particle_mat(true, false)
	_glow_mat.albedo_color = Color(1.0, 0.45, 0.12, 0.6)
	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_mat.albedo_texture = Art.soft_dot("scorch", 0.3)
	_scorch_mat.albedo_color = Color(0.05, 0.04, 0.03, 0.62)
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3(0.09, 0.07, 0.2)
	_debris_mesh.material = Art.bark_mat()
	_fire_ramp = _ramp([0.0, 0.1, 0.3, 0.62, 1.0], [Color(1.15, 0.92, 0.5, 1.0), Color(1.0, 0.62, 0.18, 1.0),
		Color(0.95, 0.36, 0.06, 0.95), Color(0.32, 0.1, 0.04, 0.7), Color(0.12, 0.08, 0.06, 0.0)])
	_flash_ramp = _ramp([0.0, 0.4, 1.0], [Color(1.2, 0.9, 0.5, 0.35), Color(1.0, 0.5, 0.15, 0.2), Color(1, 0.4, 0.1, 0.0)])
	_spark_ramp = _ramp([0.0, 0.5, 1.0], [Color(1.25, 1.0, 0.6, 1.0), Color(1.0, 0.5, 0.12, 0.9), Color(0.8, 0.2, 0.05, 0.0)])
	_smoke_ramp = _ramp([0.0, 0.18, 0.6, 1.0], [Color(0.3, 0.28, 0.25, 0.0), Color(0.22, 0.21, 0.2, 0.6),
		Color(0.17, 0.17, 0.17, 0.35), Color(0.15, 0.15, 0.15, 0.0)])
	_dust_ramp = _ramp([0.0, 0.2, 1.0], [Color(0.55, 0.42, 0.28, 0.0), Color(0.5, 0.38, 0.25, 0.55), Color(0.45, 0.36, 0.26, 0.0)])
	_grow = _curve([Vector2(0, 0.45), Vector2(0.25, 1.0), Vector2(1, 0.75)])
	_shrink = _curve([Vector2(0, 1.0), Vector2(1, 0.2)])
	_bomb_body = SphereMesh.new()
	_bomb_body.radius = 0.34
	_bomb_body.height = 0.68
	_bomb_cap = CylinderMesh.new()
	_bomb_cap.top_radius = 0.1
	_bomb_cap.bottom_radius = 0.12
	_bomb_cap.height = 0.1
	_fuse = CylinderMesh.new()
	_fuse.top_radius = 0.025
	_fuse.bottom_radius = 0.03
	_fuse.height = 0.18
	_fuse.radial_segments = 6
	_spark_dot = SphereMesh.new()
	_spark_dot.radius = 0.022
	_spark_dot.height = 0.044
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tip_mat.albedo_color = Color(1.0, 0.75, 0.35)


func _particle_mat(additive: bool, billboard := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Art.soft_dot()
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_receive_shadows = true
	return m


func _ramp(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	return c


## Compile every effect's shaders during the countdown, off-screen, so the
## first explosion of the session doesn't hitch.
func prewarm(parent: Node3D) -> void:
	if not enabled:
		return
	var at := Vector3(0, -40, 0)
	var b := make_bomb(parent, at)
	explosion(at, [at, at + Vector3(1, 0, 0)], 0.0)
	crate_break(at)
	death_puff(at)
	flame_glow(parent, at).queue_free()
	b.queue_free()
	shake = 0.0


func clear() -> void:
	for c in get_children():
		c.queue_free()
	_scorches.clear()
	_flash_lights = 0
	shake = 0.0


func _process(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 1.6 * maxf(shake, 0.25))
	for s in _scorches.duplicate():
		var node: MeshInstance3D = s["node"]
		s["t"] += delta
		if s["t"] >= SCORCH_LIFE or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_scorches.erase(s)
		elif s["t"] > SCORCH_LIFE - 1.5:
			node.transparency = (s["t"] - (SCORCH_LIFE - 1.5)) / 1.5


func _emitter(pos: Vector3, mat: Material, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _quad
	p.material_override = mat
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	p.emitting = false
	add_child(p)
	get_tree().create_timer(lifetime + 0.5, false).timeout.connect(p.queue_free)
	return p


# ---- Bombs -------------------------------------------------------------------------

## A glossy black bomb with a lit, sparking fuse. Returns the node to keep.
func make_bomb(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var body := MeshInstance3D.new()
	body.mesh = _bomb_body
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.055, 0.07)
	m.roughness = 0.45
	m.metallic = 0.05
	m.metallic_specular = 0.35
	m.emission_enabled = true
	m.emission = Color(1.0, 0.12, 0.05)
	m.emission_energy_multiplier = 0.0
	body.material_override = m
	body.position.y = 0.36
	body.name = "Body"
	n.add_child(body)
	var cap := MeshInstance3D.new()
	cap.mesh = _bomb_cap
	cap.material_override = Art.flat_mat(Color(0.55, 0.57, 0.6), 0.35, 0.8)
	cap.position.y = 0.71
	n.add_child(cap)
	var fuse := MeshInstance3D.new()
	fuse.mesh = _fuse
	fuse.material_override = Art.flat_mat(Color(0.78, 0.68, 0.48), 0.9)
	fuse.position = Vector3(0.03, 0.82, 0.0)
	fuse.rotation.z = -0.35
	n.add_child(fuse)
	var tip := MeshInstance3D.new()
	tip.mesh = _spark_dot
	tip.material_override = _tip_mat
	tip.position = Vector3(0.065, 0.9, 0.0)
	tip.name = "Tip"
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(tip)
	if enabled:
		var sp := CPUParticles3D.new()
		sp.mesh = _quad
		sp.material_override = _add_mat
		sp.amount = 6
		sp.lifetime = 0.3
		sp.local_coords = false
		sp.position = tip.position
		sp.direction = Vector3.UP
		sp.spread = 70.0
		sp.initial_velocity_min = 0.35
		sp.initial_velocity_max = 0.8
		sp.gravity = Vector3(0, -3.0, 0)
		sp.scale_amount_min = 0.018
		sp.scale_amount_max = 0.035
		sp.color_ramp = _spark_ramp
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(sp)
	n.scale = Vector3.ONE * 0.55
	return n


## Called every frame per bomb: settle-in squash, pulse, and a red warning glow.
func animate_bomb(n: Node3D, age: float, fuse_left: float, time: float) -> void:
	var settle := clampf(age / 0.18, 0.0, 1.0)
	var pop := 1.0 + sin(settle * PI) * 0.12
	var urgency := clampf(1.0 - fuse_left / Cfg.BOMB_FUSE, 0.0, 1.0)
	var rate := 8.0 + urgency * 22.0
	var pulse := 1.0 + 0.06 * sin(age * rate) * (0.5 + urgency)
	var s := lerpf(0.55, 1.0, settle) * pop * pulse
	n.scale = Vector3(s, s * (2.0 - pulse), s)
	var body := n.get_node_or_null("Body") as MeshInstance3D
	if body:
		var m := body.material_override as StandardMaterial3D
		m.emission_energy_multiplier = pow(urgency, 2.2) * 3.0 * (0.6 + 0.4 * sin(age * rate))
	var tip := n.get_node_or_null("Tip") as Node3D
	if tip:
		tip.scale = Vector3.ONE * (0.8 + 0.3 * absf(sin(time * 31.0 + age * 7.0)))


# ---- Explosions ----------------------------------------------------------------------

## One bomb's blast: fireballs down every arm, smoke, sparks, a flash and shake.
func explosion(centre: Vector3, cells: Array, strength: float) -> void:
	if not enabled:
		return
	shake = minf(0.45, shake + 0.11 * strength)
	var flash := _emitter(centre + Vector3(0, 0.5, 0), _add_mat, 1, 0.14)
	flash.color_ramp = _flash_ramp
	flash.scale_amount_min = 1.2
	flash.scale_amount_max = 1.2
	flash.emitting = true
	for c in cells:
		var p: Vector3 = c
		var is_centre := p.distance_to(centre) < 0.1
		var f := _emitter(p + Vector3(0, 0.35, 0), _fire_mat, 5 if is_centre else 4, 0.6)
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		f.emission_sphere_radius = 0.28
		f.direction = Vector3.UP
		f.spread = 180.0
		f.initial_velocity_min = 0.3
		f.initial_velocity_max = 1.4
		f.gravity = Vector3(0, 1.6, 0)
		f.damping_min = 2.0
		f.damping_max = 3.0
		f.angle_max = 360.0
		f.scale_amount_min = 0.85 if is_centre else 0.7
		f.scale_amount_max = 1.35 if is_centre else 1.1
		f.scale_amount_curve = _grow
		f.color_ramp = _fire_ramp
		f.emitting = true
		var s := _emitter(p + Vector3(0, 0.45, 0), _smoke_mat, 2, 1.5)
		s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		s.emission_sphere_radius = 0.25
		s.direction = Vector3.UP
		s.spread = 40.0
		s.initial_velocity_min = 0.4
		s.initial_velocity_max = 0.9
		s.gravity = Vector3(0, 0.5, 0)
		s.angle_max = 360.0
		s.scale_amount_min = 0.7
		s.scale_amount_max = 1.2
		s.scale_amount_curve = _grow
		s.color_ramp = _smoke_ramp
		s.emitting = true
		scorch(p, 0.95 if is_centre else 0.7)
	var sp := _emitter(centre + Vector3(0, 0.4, 0), _add_mat, 22, 0.9)
	sp.direction = Vector3.UP
	sp.spread = 75.0
	sp.initial_velocity_min = 3.5
	sp.initial_velocity_max = 7.5
	sp.gravity = Vector3(0, -11.0, 0)
	sp.scale_amount_min = 0.06
	sp.scale_amount_max = 0.12
	sp.color_ramp = _spark_ramp
	sp.emitting = true
	_flash_light(centre + Vector3(0, 0.8, 0))


func _flash_light(pos: Vector3) -> void:
	if _flash_lights >= MAX_FLASH_LIGHTS:
		return
	_flash_lights += 1
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = Color(1.0, 0.62, 0.3)
	l.light_energy = 6.0
	l.omni_range = 4.5
	l.shadow_enabled = false
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_release_light.bind(l))


func _release_light(l: OmniLight3D) -> void:
	_flash_lights = maxi(0, _flash_lights - 1)
	if is_instance_valid(l):
		l.queue_free()


## A glowing floor patch that marks a tile as lethal while its flame is live.
func flame_glow(parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var g := MeshInstance3D.new()
	g.mesh = _quad
	g.material_override = _glow_mat
	g.rotation.x = -PI / 2.0
	g.position = pos + Vector3(0, 0.03, 0)
	g.scale = Vector3.ONE * 1.25
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g)
	return g


func scorch(pos: Vector3, size: float) -> void:
	var s := MeshInstance3D.new()
	s.mesh = _quad
	s.material_override = _scorch_mat
	s.rotation = Vector3(-PI / 2.0, randf() * TAU, 0.0)
	s.position = pos + Vector3(0, 0.012 + randf() * 0.004, 0)
	s.scale = Vector3.ONE * size * randf_range(0.9, 1.15)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	_scorches.append({"node": s, "t": 0.0})


## Splinters and sawdust from a log pile breaking.
func crate_break(pos: Vector3) -> void:
	if not enabled:
		return
	var d := CPUParticles3D.new()
	d.mesh = _debris_mesh
	d.amount = 9
	d.lifetime = 1.1
	d.one_shot = true
	d.explosiveness = 1.0
	d.local_coords = false
	d.position = pos + Vector3(0, 0.45, 0)
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	d.emission_sphere_radius = 0.25
	d.direction = Vector3.UP
	d.spread = 60.0
	d.initial_velocity_min = 3.0
	d.initial_velocity_max = 5.5
	d.gravity = Vector3(0, -14.0, 0)
	d.angular_velocity_min = -540.0
	d.angular_velocity_max = 540.0
	d.angle_max = 360.0
	d.scale_amount_min = 0.7
	d.scale_amount_max = 1.4
	d.scale_amount_curve = _shrink
	add_child(d)
	d.emitting = true
	get_tree().create_timer(1.6, false).timeout.connect(d.queue_free)
	var dust := _emitter(pos + Vector3(0, 0.4, 0), _smoke_mat, 4, 1.1)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.35
	dust.spread = 180.0
	dust.initial_velocity_min = 0.3
	dust.initial_velocity_max = 0.8
	dust.gravity = Vector3(0, 0.3, 0)
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.0
	dust.scale_amount_curve = _grow
	dust.color_ramp = _dust_ramp
	dust.emitting = true


## Dust kicked up where a sudden-death block lands.
func crate_dust(pos: Vector3) -> void:
	if not enabled:
		return
	var dust := _emitter(pos + Vector3(0, 0.1, 0), _smoke_mat, 5, 0.9)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.45
	dust.spread = 180.0
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 1.2
	dust.gravity = Vector3(0, 0.2, 0)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 0.9
	dust.scale_amount_curve = _grow
	dust.color_ramp = _dust_ramp
	dust.emitting = true


## A puff when a fighter is caught.
func death_puff(pos: Vector3) -> void:
	if not enabled:
		return
	var s := _emitter(pos + Vector3(0, 0.6, 0), _smoke_mat, 8, 1.3)
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.3
	s.spread = 180.0
	s.initial_velocity_min = 0.6
	s.initial_velocity_max = 1.4
	s.gravity = Vector3(0, 0.8, 0)
	s.scale_amount_min = 0.6
	s.scale_amount_max = 1.1
	s.scale_amount_curve = _grow
	s.color_ramp = _smoke_ramp
	s.emitting = true
