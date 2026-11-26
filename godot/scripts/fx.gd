extends Node3D
## Visual effects: bombs, explosions, debris, scorch marks, flashes and camera
## shake. Purely presentation — nothing here changes the rules, so the smoke
## test runs with it switched off.

const Art := preload("res://scripts/art.gd")
const Cfg := preload("res://scripts/config.gd")

const SCORCH_LIFE := 3.5    # AAA review: 7 s left the lanes grimy

var enabled := true
var shake := 0.0
var debris_color := Color(0, 0, 0, 0)   # alpha 0: the Forest's bark splinters
var pale_bombs := false                 # dark floors get a pale shell (BOMB_PALE)
var theme := "forest"                   # the arena, for themed debris
var _quad: QuadMesh
var _fire_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _scorch_mat: StandardMaterial3D
var _flame_tile_mat: ShaderMaterial
# Pooled flat quads (AAA review round 3, draw calls): every lethal-tile flame
# sheet and every scorch mark is an instance in one MultiMesh, not a node.
const FLAME_POOL := 128
const SCORCH_POOL := 128
var _pool_root: Node3D
var _flame_mm: MultiMesh
var _flame_free: Array = []
var _scorch_mm: MultiMesh
var _scorch_next := 0
var _flame_pos := {}
var _flame_shape := {}
var _last_flash_ms := -1000
var _shock_mat: ShaderMaterial
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
	_flame_tile_mat = ShaderMaterial.new()
	var fs := Shader.new()
	fs.code = FLAME_TILE_SHADER
	_flame_tile_mat.shader = fs
	_flame_tile_mat.set_shader_parameter("noise_tex", Art.dapple_tex())
	_shock_mat = ShaderMaterial.new()
	var ss := Shader.new()
	ss.code = SHOCK_SHADER
	_shock_mat.shader = ss
	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_mat.albedo_texture = Art.soft_dot("scorch", 0.3)
	_scorch_mat.albedo_color = Color(0.05, 0.04, 0.03, 0.35)
	_scorch_mat.vertex_color_use_as_albedo = true
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3(0.09, 0.07, 0.2)
	_debris_mesh.material = Art.bark_mat()
	_fire_ramp = _ramp([0.0, 0.1, 0.35, 0.6, 1.0], [Color(1.0, 0.72, 0.35, 1.0), Color(1.0, 0.7, 0.25, 1.0),
		Color(1.0, 0.45, 0.1, 0.85), Color(0.35, 0.32, 0.3, 0.35), Color(0.25, 0.24, 0.23, 0.0)])
	_flash_ramp = _ramp([0.0, 0.4, 1.0], [Color(1.0, 0.85, 0.5, 0.18), Color(1.0, 0.5, 0.15, 0.2), Color(1, 0.4, 0.1, 0.0)])
	_spark_ramp = _ramp([0.0, 0.5, 1.0], [Color(1.25, 1.0, 0.6, 1.0), Color(1.0, 0.5, 0.12, 0.9), Color(0.8, 0.2, 0.05, 0.0)])
	# Lighter and thinner: dark smoke went muddy brown under coloured light
	# (AAA review round 8).
	_smoke_ramp = _ramp([0.0, 0.18, 0.6, 1.0], [Color(0.46, 0.45, 0.47, 0.0), Color(0.4, 0.4, 0.42, 0.36),
		Color(0.34, 0.34, 0.36, 0.2), Color(0.3, 0.3, 0.32, 0.0)])
	_dust_ramp = _ramp([0.0, 0.2, 1.0], [Color(0.55, 0.42, 0.28, 0.0), Color(0.5, 0.38, 0.25, 0.55), Color(0.45, 0.36, 0.26, 0.0)])
	_grow = _curve([Vector2(0, 0.45), Vector2(0.25, 1.0), Vector2(1, 0.75)])
	_shrink = _curve([Vector2(0, 1.0), Vector2(1, 0.2)])
	_bomb_body = SphereMesh.new()
	_bomb_body.radius = 0.29    # AAA review: bombs smaller than a fighter's footprint
	_bomb_body.height = 0.58
	_bomb_body.radial_segments = 24
	_bomb_body.rings = 12
	_bomb_cap = CylinderMesh.new()
	_bomb_cap.top_radius = 0.1
	_bomb_cap.bottom_radius = 0.12
	_bomb_cap.height = 0.1
	_bomb_cap.radial_segments = 14
	_bomb_cap.rings = 1
	_fuse = CylinderMesh.new()
	_fuse.top_radius = 0.025
	_fuse.bottom_radius = 0.03
	_fuse.height = 0.18
	_fuse.radial_segments = 6
	_fuse.rings = 1
	_spark_dot = SphereMesh.new()
	_spark_dot.radius = 0.016
	_spark_dot.height = 0.032
	_spark_dot.radial_segments = 6
	_spark_dot.rings = 3
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tip_mat.albedo_color = Color(0.95, 0.55, 0.22)
	_fire_mat.albedo_texture = Art.flame_tex()
	_pool_root = Node3D.new()
	add_child(_pool_root)
	_flame_tile_mat.render_priority = 2
	_flame_mm = _make_pool(_flame_tile_mat, FLAME_POOL)
	for k in FLAME_POOL:
		_flame_free.append(FLAME_POOL - 1 - k)
	_scorch_mm = _make_pool(_scorch_mat, SCORCH_POOL)


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
	free_flame(add_flame(at))
	b.queue_free()
	shake = 0.0


func clear() -> void:
	for c in get_children():
		if c != _pool_root:
			c.queue_free()
	_scorches.clear()
	var hide := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	_flame_free.clear()
	for i in FLAME_POOL:
		_flame_mm.set_instance_transform(i, hide)
		_flame_free.append(FLAME_POOL - 1 - i)
	for i in SCORCH_POOL:
		_scorch_mm.set_instance_transform(i, hide)
	shake = 0.0


func _process(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 1.6 * maxf(shake, 0.25))
	for s in _scorches.duplicate():
		s["t"] += delta
		var i: int = s["i"]
		if s["t"] >= SCORCH_LIFE:
			_scorch_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
			_scorches.erase(s)
		elif s["t"] > SCORCH_LIFE - 1.5:
			_scorch_mm.set_instance_color(i, Color(1, 1, 1, 1.0 - (s["t"] - (SCORCH_LIFE - 1.5)) / 1.5))


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

## A glossy black bomb with a lit fuse — pale on dark floors, red when a
## hazard threw it. Returns the node to keep.
func make_bomb(parent: Node3D, pos: Vector3, hazard := false) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var body := MeshInstance3D.new()
	body.mesh = _bomb_body
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.055, 0.07)
	if pale_bombs:
		m.albedo_color = Color(0.69, 0.72, 0.79)   # 0xd8dce6 in linear-ish terms
	if hazard:
		m.albedo_color = Color(0.75, 0.04, 0.03)
	m.roughness = 0.45
	m.metallic = 0.05
	m.metallic_specular = 0.35
	m.emission_enabled = true
	m.emission = Color(1.0, 0.12, 0.05)
	m.emission_energy_multiplier = 0.0
	body.material_override = m
	body.position.y = 0.31
	body.name = "Body"
	n.add_child(body)
	var cap := MeshInstance3D.new()
	cap.mesh = _bomb_cap
	cap.material_override = Art.flat_mat(Color(0.55, 0.57, 0.6), 0.35, 0.8)
	cap.position.y = 0.61
	n.add_child(cap)
	var fuse := MeshInstance3D.new()
	fuse.mesh = _fuse
	fuse.material_override = Art.flat_mat(Color(0.78, 0.68, 0.48), 0.9)
	fuse.position = Vector3(0.03, 0.72, 0.0)
	fuse.rotation.z = -0.35
	n.add_child(fuse)
	var tip := MeshInstance3D.new()
	tip.mesh = _spark_dot
	tip.material_override = _tip_mat
	tip.position = Vector3(0.065, 0.8, 0.0)
	tip.name = "Tip"
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(tip)
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
		# A faint red warning only in the last stretch of the fuse.
		var warn := clampf((urgency - 0.55) / 0.45, 0.0, 1.0)
		m.emission_energy_multiplier = warn * warn * 0.9 * (0.2 + 0.8 * absf(sin(age * rate * 0.5)))
	var tip := n.get_node_or_null("Tip") as Node3D
	if tip:
		tip.scale = Vector3.ONE * (0.85 + 0.2 * absf(sin(time * 23.0 + age * 7.0)))


# ---- Explosions ----------------------------------------------------------------------

## One bomb's blast: fireballs down every arm, smoke, sparks, a flash and shake.
func explosion(centre: Vector3, cells: Array, strength: float) -> void:
	if not enabled:
		return
	shake = minf(0.45, shake + 0.11 * strength)
	# One flash per moment: chains no longer stack flashes into white.
	var now := Time.get_ticks_msec()
	var skip_flash := now - _last_flash_ms < 100
	_last_flash_ms = now
	if not skip_flash:
		var flash := _emitter(centre + Vector3(0, 0.5, 0), _add_mat, 1, 0.14)
		flash.color_ramp = _flash_ramp
		flash.scale_amount_min = 0.8
		flash.scale_amount_max = 0.8
		flash.emitting = true
	# One fire and one smoke emitter for the whole blast (points on every
	# cell), not two nodes per cell: AAA review round 3, draw calls.
	var fire_pts := PackedVector3Array()
	var smoke_pts := PackedVector3Array()
	for c in cells:
		var p: Vector3 = c
		var jitter := Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
		# Near rows: fire rising towards the camera projects over the wall, so
		# only one low point there (the floor sheet already marks the tile).
		# Near rows: no fire points at all (the beam marks the tile); points
		# there glowed on the near wall (AAA review round 7). Elsewhere they
		# stay inside the tile.
		var near := p.z >= (Cfg.ROWS - 3) * 0.5 - 0.1
		if not near:
			for k in 3:
				fire_pts.append(p - centre + Vector3(randf_range(-0.22, 0.22), randf_range(0.0, 0.15), randf_range(-0.22, 0.22)))
		# No smoke beside the outer wall: it drifted out over the surroundings.
		if not near and absf(p.x) < (Cfg.COLS - 3) * 0.5 + 0.1 and absf(p.z) < (Cfg.ROWS - 3) * 0.5 + 0.1:
			smoke_pts.append(p - centre + jitter)
		scorch(p, 0.95 if p.distance_to(centre) < 0.1 else 0.7)
	if fire_pts.is_empty():   # a blast wholly in the near rows
		fire_pts.append(Vector3(0, -0.2, 0))
	var f := _emitter(centre + Vector3(0, 0.35, 0), _fire_mat, fire_pts.size(), Cfg.BLAST_LIFE + 0.08)
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	f.emission_points = fire_pts
	f.direction = Vector3.UP
	f.spread = 30.0
	f.initial_velocity_min = 0.4
	f.initial_velocity_max = 0.9
	f.gravity = Vector3(0, 0.6, 0)
	f.damping_min = 2.0
	f.damping_max = 3.0
	f.scale_amount_min = 0.5
	f.scale_amount_max = 0.85
	f.scale_amount_curve = _grow
	f.color_ramp = _fire_ramp
	f.emitting = true
	if not smoke_pts.is_empty():
		var s := _emitter(centre + Vector3(0, 0.45, 0), _smoke_mat, smoke_pts.size(), 1.1)
		s.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		s.emission_points = smoke_pts
		s.direction = Vector3.UP
		s.spread = 25.0
		s.initial_velocity_min = 0.3
		s.initial_velocity_max = 0.6
		s.gravity = Vector3(0, 0.2, 0)
		s.angle_max = 360.0
		s.scale_amount_min = 0.45
		s.scale_amount_max = 0.7
		s.scale_amount_curve = _grow
		s.color_ramp = _smoke_ramp
		s.emitting = true
	var sp := _emitter(centre + Vector3(0, 0.4, 0), _add_mat, 12, 0.9)
	sp.direction = Vector3.UP
	sp.spread = 75.0
	sp.initial_velocity_min = 3.5
	sp.initial_velocity_max = 7.5
	sp.gravity = Vector3(0, -11.0, 0)
	sp.scale_amount_min = 0.06
	sp.scale_amount_max = 0.12
	sp.color_ramp = _spark_ramp
	sp.emitting = true
	# No flash light any more: each omni light redraws everything near it on
	# phones (AAA review round 3). The flash quad and shockwave carry it.
	# Shockwave: a bright ring racing out over the floor.
	var ring := MeshInstance3D.new()
	ring.mesh = _quad
	var sm := _shock_mat.duplicate() as ShaderMaterial
	ring.material_override = sm
	ring.rotation.x = -PI / 2.0
	ring.position = centre + Vector3(0, 0.06, 0)
	ring.scale = Vector3.ONE * 0.3
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 3.2, 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(sm, "shader_parameter/fade", 1.0, 0.28)
	tw.chain().tween_callback(ring.queue_free)


## A glowing floor patch that marks a tile as lethal while its flame is live.
func scorch(pos: Vector3, size: float) -> void:
	var i := _scorch_next
	_scorch_next = (_scorch_next + 1) % SCORCH_POOL
	for s in _scorches:
		if s["i"] == i:
			_scorches.erase(s)
			break
	var b := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, -PI / 2.0)
	_scorch_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * size * randf_range(0.9, 1.15)), pos + Vector3(0, 0.012 + randf() * 0.004, 0)))
	_scorch_mm.set_instance_color(i, Color(1, 1, 1, 1))
	_scorches.append({"i": i, "t": 0.0})


func _make_pool(mat: Material, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _quad
	mm.instance_count = count
	var hide := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for i in count:
		mm.set_instance_transform(i, hide)
		mm.set_instance_color(i, Color(1, 1, 1, 1))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-30, -60, -30), Vector3(60, 70, 60))
	_pool_root.add_child(mi)
	return mm


## Lethal-tile flame sheets from the pool: add returns a handle (or -1),
## set_flame scales it, free_flame hides it.
func add_flame(pos: Vector3, shape := Color(0.5, 0.0, 0.5, 1.0)) -> int:
	if not enabled or _flame_free.is_empty():
		return -1
	var i: int = _flame_free.pop_back()
	_flame_mm.set_instance_color(i, shape)
	# Above the tide water (up to y 0.14): a lethal tile is never hidden.
	_flame_pos[i] = pos + Vector3(0, 0.17 + randf() * 0.005, 0)
	_flame_shape[i] = shape
	set_flame(i, 1.12)
	return i


func set_flame(i: int, s: float) -> void:
	if i < 0:
		return
	# Every sheet stays full size (mid-arm ones stretched 1.1 along the arm
	# so neighbours overlap). Dying is done in the shader: instance alpha is
	# the flame's thickness, so arms and the centre narrow together to a line
	# and never break into beads (AAA review round 8).
	var shp: Color = _flame_shape.get(i, Color(0.5, 0, 0.5, 1))
	var along := 1.12 * (1.0 if shp.g >= 0.5 else 1.1)
	var sx := 1.12
	var sz := 1.12
	if shp.r < 0.25:
		sx = along
	elif shp.r > 0.75:
		sz = along
	_flame_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sx, 1.0, sz)) * Basis(Vector3.RIGHT, -PI / 2.0), _flame_pos[i]))
	_flame_mm.set_instance_color(i, Color(shp.r, shp.g, shp.b, clampf(s / 1.12, 0.0, 1.0)))


func free_flame(i: int) -> void:
	if i < 0:
		return
	_flame_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
	_flame_free.append(i)


## A crate breaking, dressed for the arena: bark splinters and leaves in the
## Forest, sand and driftwood on the Beach, a wisp of spirit from a Haunted
## House casket, cardboard and sparks in the Factory.
func crate_break(pos: Vector3) -> void:
	if not enabled:
		return
	var d := CPUParticles3D.new()
	d.mesh = _debris_mesh
	if debris_color.a > 0.0:
		var tm := BoxMesh.new()
		tm.size = Vector3(0.11, 0.08, 0.16)
		tm.material = Art.flat_mat(debris_color, 0.7)
		d.mesh = tm
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
	dust.color_ramp = _theme_dust()
	dust.emitting = true
	match theme:
		"forest":
			_bits(pos, Color(0.36, 0.55, 0.2), 6, Vector3(0.09, 0.01, 0.07), 2.2, -3.0)
		"beach":
			var sand := _emitter(pos + Vector3(0, 0.3, 0), _smoke_mat, 6, 0.8)
			sand.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			sand.emission_sphere_radius = 0.3
			sand.direction = Vector3.UP
			sand.spread = 70.0
			sand.initial_velocity_min = 1.5
			sand.initial_velocity_max = 2.6
			sand.gravity = Vector3(0, -6.0, 0)
			sand.scale_amount_min = 0.35
			sand.scale_amount_max = 0.6
			sand.color_ramp = _ramp([0.0, 0.2, 1.0], [Color(0.82, 0.7, 0.5, 0.0), Color(0.82, 0.7, 0.5, 0.8), Color(0.8, 0.68, 0.5, 0.0)])
			sand.emitting = true
		"haunted":
			var wisp := _emitter(pos + Vector3(0, 0.5, 0), _add_mat, 4, 1.6)
			wisp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			wisp.emission_sphere_radius = 0.2
			wisp.direction = Vector3.UP
			wisp.spread = 20.0
			wisp.initial_velocity_min = 0.8
			wisp.initial_velocity_max = 1.3
			wisp.gravity = Vector3(0, 0.6, 0)
			wisp.scale_amount_min = 0.35
			wisp.scale_amount_max = 0.55
			wisp.scale_amount_curve = _grow
			wisp.color_ramp = _ramp([0.0, 0.25, 1.0], [Color(0.5, 1.0, 0.75, 0.0), Color(0.55, 1.0, 0.8, 0.7), Color(0.4, 0.7, 1.0, 0.0)])
			wisp.emitting = true
		"factory":
			var sp := _emitter(pos + Vector3(0, 0.4, 0), _add_mat, 10, 0.5)
			sp.direction = Vector3.UP
			sp.spread = 80.0
			sp.initial_velocity_min = 2.5
			sp.initial_velocity_max = 4.5
			sp.gravity = Vector3(0, -12.0, 0)
			sp.scale_amount_min = 0.05
			sp.scale_amount_max = 0.09
			sp.color_ramp = _spark_ramp
			sp.emitting = true


## Small flat bits (leaves, chips) that flutter down.
func _bits(pos: Vector3, c: Color, amount: int, size: Vector3, up: float, grav: float) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = Art.flat_mat(c, 0.8)
	p.mesh = bm
	p.amount = amount
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.position = pos + Vector3(0, 0.6, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = up * 0.6
	p.initial_velocity_max = up
	p.gravity = Vector3(0, grav, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.angle_max = 360.0
	p.scale_amount_curve = _shrink
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.9, false).timeout.connect(p.queue_free)


func _theme_dust() -> Gradient:
	match theme:
		"beach":
			return _ramp([0.0, 0.2, 1.0], [Color(0.8, 0.7, 0.52, 0.0), Color(0.78, 0.68, 0.5, 0.5), Color(0.75, 0.66, 0.5, 0.0)])
		"haunted":
			return _ramp([0.0, 0.2, 1.0], [Color(0.4, 0.36, 0.45, 0.0), Color(0.38, 0.34, 0.44, 0.5), Color(0.3, 0.28, 0.36, 0.0)])
		"factory":
			return _ramp([0.0, 0.2, 1.0], [Color(0.5, 0.48, 0.45, 0.0), Color(0.46, 0.44, 0.42, 0.5), Color(0.4, 0.4, 0.4, 0.0)])
	return _dust_ramp


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


## A bomb put out by water: a hiss of steam.
func steam_puff(pos: Vector3) -> void:
	if not enabled:
		return
	var s := _emitter(pos + Vector3(0, 0.3, 0), _smoke_mat, 7, 1.2)
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.2
	s.direction = Vector3.UP
	s.spread = 25.0
	s.initial_velocity_min = 1.0
	s.initial_velocity_max = 1.8
	s.gravity = Vector3(0, 0.6, 0)
	s.scale_amount_min = 0.4
	s.scale_amount_max = 0.8
	s.scale_amount_curve = _grow
	s.color_ramp = _ramp([0.0, 0.15, 1.0], [Color(0.92, 0.95, 1.0, 0.0), Color(0.92, 0.95, 1.0, 0.7), Color(0.9, 0.92, 0.95, 0.0)])
	s.emitting = true


## The Shield bursting: a ring of violet light.
func shield_pop(pos: Vector3) -> void:
	if not enabled:
		return
	var p := _emitter(pos + Vector3(0, 0.6, 0), _add_mat, 18, 0.5)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.2
	p.gravity = Vector3.ZERO
	p.damping_min = 4.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.2
	p.color_ramp = _ramp([0.0, 0.3, 1.0], [Color(0.8, 0.7, 1.2, 1.0), Color(0.6, 0.45, 1.0, 0.8), Color(0.4, 0.3, 1.0, 0.0)])
	p.emitting = true
	shake = minf(0.45, shake + 0.08)


## A puff when a fighter is caught.
func death_puff(pos: Vector3) -> void:
	if not enabled:
		return
	_burst(pos + Vector3(0, 0.7, 0), Color(1.0, 0.95, 0.8), 16, 3.5, 0.6)
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


const FLAME_TILE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// Instance colour: r axis (0 x, 1 z, 0.5 centre), g end-of-arm, b direction.
	vec2 p = UV * 2.0 - 1.0;
	float axis = COLOR.r;
	float dir = COLOR.b * 2.0 - 1.0;
	float across;
	float along;
	if (axis < 0.25) { across = abs(p.y); along = p.x * dir; }
	else if (axis > 0.75) { across = abs(p.x); along = p.y * dir; }
	// Centre: a plus, so it meets each arm at the arm's own width.
	else { across = min(abs(p.x), abs(p.y)); along = -1.0; }
	// Thickness (instance alpha): narrows every sheet the same way as it dies.
	float k = COLOR.a;
	across /= mix(0.28, 1.0, k);
	float r = across;
	if (COLOR.g > 0.5 && along > 0.0) r = length(vec2(across, along * 1.1));
	float n = texture(noise_tex, wpos.xz * 0.6 + vec2(0.0, TIME * 1.8)).r;
	float n2 = texture(noise_tex, wpos.xz * 1.3 - vec2(TIME * 1.1, 0.0)).r;
	float heat = clamp(1.15 - r * 1.05 + (n - 0.5) * 0.55 + (n2 - 0.5) * 0.3, 0.0, 1.0);
	vec3 col = mix(vec3(0.75, 0.1, 0.02), vec3(1.0, 0.45, 0.06), smoothstep(0.1, 0.45, heat));
	col = mix(col, vec3(1.0, 0.85, 0.42), smoothstep(0.55, 0.85, heat));
	col = mix(col, vec3(1.0, 0.93, 0.78), smoothstep(0.96, 1.0, heat));
	ALBEDO = min(col, vec3(0.92));
	ALPHA = smoothstep(0.02, 0.22, heat) * smoothstep(0.0, 0.35, k);
}
"""

const SHOCK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec3 tint = vec3(1.0, 0.75, 0.4);
uniform float fade = 0.0;
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	// Soft both sides, and dimmer: it read as a hard pale disc (round 8).
	float ring = smoothstep(0.5, 0.85, d) * (1.0 - smoothstep(0.86, 1.0, d));
	ALBEDO = tint * ring * 0.5 * (1.0 - fade);
}
"""


## A ring of sparks in a colour: pick-ups, knockouts.
func _burst(pos: Vector3, c: Color, amount: int, speed: float, life: float) -> void:
	var p := _emitter(pos, _add_mat, amount, life)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -4.0, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.18
	p.color_ramp = _ramp([0.0, 0.3, 1.0], [Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1.0), c, Color(c, 0.0)])
	p.emitting = true


## Collecting a pick-up: a burst and ring in its colour and a "+BOMB" that
## floats up off the fighter.
func pickup_burst(pos: Vector3, c: Color, text: String, below := false) -> void:
	if not enabled:
		return
	_burst(pos + Vector3(0, 0.6, 0), c, 12, 2.2, 0.45)
	var ring := MeshInstance3D.new()
	ring.mesh = _quad
	var rm := _shock_mat.duplicate() as ShaderMaterial
	rm.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	ring.material_override = rm
	ring.rotation.x = -PI / 2.0
	ring.position = pos + Vector3(0, 0.08, 0)
	ring.scale = Vector3.ONE * 0.4
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 1.3, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(rm, "shader_parameter/fade", 1.0, 0.3)
	tw.chain().tween_callback(ring.queue_free)
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/lilita-one.ttf")
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = c.lightened(0.3)
	l.outline_size = 14
	l.outline_modulate = Color(0.03, 0.03, 0.06)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	# Near the top of the board the label would slide under the timer pill:
	# put it below the fighter there.
	# Your own fighter wears the YOU tag up there, so yours drops below too.
	var top_rows := below or pos.z < -(Cfg.ROWS * 0.5 - 2.6)
	l.position = pos + (Vector3(0, 0.4, 1.1) if top_rows else Vector3(0, 1.5, 0))
	if below and pos.z < -(Cfg.ROWS * 0.5 - 2.6):   # your YOU tag is at your feet there
		l.position = pos + Vector3(1.2, 0.4, 0.4)
	add_child(l)
	var lt := l.create_tween()
	lt.set_parallel(true)
	lt.tween_property(l, "position", l.position + (Vector3(0, 0.3, 0.5) if top_rows else Vector3(0, 0.9, 0)), 0.7).set_ease(Tween.EASE_OUT)
	lt.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	lt.chain().tween_callback(l.queue_free)
