extends Node3D
## Life around each arena: birds, gulls and bats, drifting motes, lightning,
## candle flicker, steam and welding sparks. Presentation only — nothing here
## touches the rules, and the smoke test never builds it.

const Art := preload("res://scripts/art.gd")
const LA := preload("res://scripts/level_art.gd")
const Cfg := preload("res://scripts/config.gd")

const GROUND_Y := -0.34

var game = null
var id := ""
var _t := 0.0
var _flyers: Array = []     # {node, wings[], kind, ...}
var _lights: Array = []     # flickering glow pools: {mat, base, phase}
# No real lights here: DESIGN.md keeps the arenas to the one sun (each extra
# light is another pass on phones), so candles, furnaces and welding flashes
# are additive glow pools on the ground.
var _bursts: Array = []     # periodic emitters: {node, every, t, light}
var _flash := 0.0           # lightning, 0..1
var _next_flash := 6.0
var _rng := RandomNumberGenerator.new()


func setup(g) -> void:
	game = g
	_rng.seed = 77


func build(level_id: String) -> void:
	for c in get_children():
		c.queue_free()
	_flyers.clear()
	_lights.clear()
	_bursts.clear()
	_flash = 0.0
	_next_flash = 5.0 + _rng.randf() * 4.0
	id = level_id
	match id:
		"forest":
			_forest()
		"beach":
			_beach()
		"haunted":
			_haunted()
		"factory":
			_factory()


func _process(delta: float) -> void:
	_t += delta
	for f in _flyers:
		_fly(f, delta)
	for l in _lights:
		var lm: StandardMaterial3D = l["mat"]
		var ph: float = l["phase"]
		var c: Color = l["col"]
		lm.albedo_color = Color(c, c.a * (0.8 + 0.12 * sin(_t * 9.3 + ph) + 0.08 * sin(_t * 23.0 + ph * 2.1)))
	for b in _bursts:
		b["t"] -= delta
		if b["t"] <= 0.0:
			b["t"] = b["every"] * _rng.randf_range(0.7, 1.3)
			var p: CPUParticles3D = b["node"]
			p.restart()
			if b.has("flash"):
				b["k"] = 1.0
		if b.has("flash"):
			b["k"] = move_toward(b["k"], 0.0, delta * 5.0)
			var fm: StandardMaterial3D = b["flash"]
			fm.albedo_color = Color(1.0, 0.72, 0.4, 0.55 * b["k"])
	if id == "haunted":
		_lightning(delta)


# ---- Flyers: a body and two wings that flap ----------------------------------------

func _flyer(body_col: Color, wing_col: Color, size: float) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = LA.build([[LA.sphere(0.12, 10, 6), LA.xf(Vector3.ZERO, Vector3.ZERO, Vector3(0.7, 0.6, 1.4)), body_col],
		[LA.sphere(0.07, 8, 5), LA.xf(Vector3(0, 0.03, 0.15)), body_col]], LA.vmat("flyer_body", 0.8, 0.0, 0.2))
	root.add_child(body)
	var wings: Array = []
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		root.add_child(pivot)
		var w := MeshInstance3D.new()
		w.mesh = LA.build([[LA.box(Vector3(0.42, 0.015, 0.16)), LA.xf(Vector3(0.21, 0, 0)), wing_col],
			[LA.box(Vector3(0.2, 0.015, 0.1)), LA.xf(Vector3(0.46, 0, -0.03), Vector3(0, 0.3, 0)), wing_col]], LA.vmat("flyer_wing", 0.8, 0.0, 0.2))
		w.scale = Vector3(s, 1, 1)
		pivot.add_child(w)
		wings.append(pivot)
	root.scale = Vector3.ONE * size
	return {"node": root, "wings": wings, "ph": _rng.randf() * TAU}


## kind "cross": flies straight over the board now and then. "circle": glides
## round a point. "flit": a bat's erratic loop round a point.
func _fly(f: Dictionary, delta: float) -> void:
	var n: Node3D = f["node"]
	var ph: float = f["ph"]
	var flap: float = f.get("flap", 12.0)
	var pos := n.position
	match f["kind"]:
		"cross":
			if f["wait"] > 0.0:
				f["wait"] -= delta
				n.visible = false
				return
			n.visible = true
			f["u"] += delta * f["speed"]
			var a: Vector3 = f["a"]
			var b: Vector3 = f["b"]
			var k: float = f["u"] / a.distance_to(b)
			pos = a.lerp(b, k) + Vector3(0, sin(f["u"] * 1.3 + ph) * 0.25, 0)
			if k >= 1.0:
				_new_crossing(f)
		"circle":
			var c: Vector3 = f["c"]
			var ang: float = _t * f["speed"] + ph
			pos = c + Vector3(cos(ang) * f["r"], sin(_t * 0.7 + ph) * 0.3, sin(ang) * f["r"] * 0.7)
		"flit":
			var c2: Vector3 = f["c"]
			pos = c2 + Vector3(sin(_t * 1.7 + ph) * 2.2 + sin(_t * 4.1 + ph) * 0.4,
				sin(_t * 2.3 + ph * 1.3) * 0.5, cos(_t * 1.3 + ph) * 3.0 + sin(_t * 3.7) * 0.3)
	var vel := pos - n.position
	if vel.length() > 0.0005:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(vel.x, vel.z), clampf(delta * 6.0, 0.0, 1.0))
	n.position = pos
	var glide: float = f.get("glide", 0.0)
	var w: float = sin(_t * flap + ph)
	if glide > 0.0 and sin(_t * 0.6 + ph) > 0.2:
		w *= 0.15   # gliding
	var i := 0
	for p in f["wings"]:
		(p as Node3D).rotation.z = w * 0.75 * (1.0 if i == 0 else -1.0)
		i += 1


func _new_crossing(f: Dictionary) -> void:
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var z0 := _rng.randf_range(-7.0, 5.0)
	var z1 := clampf(z0 + _rng.randf_range(-4.0, 4.0), -7.5, 6.0)
	var y := _rng.randf_range(3.2, 4.6)
	f["a"] = Vector3(side * 14.0, y, z0)
	f["b"] = Vector3(-side * 14.0, y + _rng.randf_range(-0.5, 0.8), z1)
	f["u"] = 0.0
	f["wait"] = _rng.randf_range(4.0, 11.0)
	f["speed"] = _rng.randf_range(3.2, 4.4)


# ---- Particles -----------------------------------------------------------------------

func _motes(col: Color, amount: int, box: Vector3, centre: Vector3, size: float, rise: float, lifetime := 6.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Art.soft_dot()
	p.material_override = m
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.position = centre
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.gravity = Vector3(0, rise, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), col, col, Color(col, 0.0)])
	p.color_ramp = g
	add_child(p)
	return p


func _puffer(pos: Vector3, col: Color, every: float, amount := 6, up := 1.6, lifetime := 1.8) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Art.soft_dot()
	p.material_override = m
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.6
	p.position = pos
	p.direction = Vector3.UP
	p.spread = 14.0
	p.initial_velocity_min = up * 0.7
	p.initial_velocity_max = up
	p.gravity = Vector3(0.3, 0.4, 0)
	p.damping_min = 0.6
	p.damping_max = 1.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.55
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), col, Color(col, 0.0)])
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	add_child(p)
	_bursts.append({"node": p, "every": every, "t": _rng.randf() * every})
	return p


## A soft additive pool of light on the ground (cheaper than a lamp).
func _pool(pos: Vector3, col: Color, size: float, flicker := false) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Art.soft_dot()
	m.albedo_color = col
	mi.material_override = m
	mi.rotation.x = -PI / 2.0
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if flicker:
		_lights.append({"mat": m, "col": col, "phase": _rng.randf() * TAU})
	return m


# ---- The arenas ------------------------------------------------------------------------

func _forest() -> void:
	# Pollen and seed fluff drifting through the low sun.
	_motes(Color(1.0, 0.86, 0.5, 0.55), 40, Vector3(9.0, 1.2, 7.5), Vector3(0, 1.4, 0), 0.07, 0.02, 7.0)
	for i in 3:
		var f := _flyer(Color("3a2e26"), Color("4a3a2e"), 0.9)
		f["kind"] = "cross"
		_new_crossing(f)
		f["wait"] = 1.5 + i * 3.5
		_flyers.append(f)


func _beach() -> void:
	# Gulls circling over the sand either side; glints on the water.
	for i in 3:
		var f := _flyer(Color("f2f2ee"), Color("dcdcd8"), 1.1)
		f["kind"] = "circle"
		f["c"] = Vector3(-10.5 if i % 2 == 0 else 10.5, 4.2 + i * 0.4, -2.0 + i * 2.0)
		f["r"] = 2.2 + i * 0.5
		f["speed"] = 0.55 + i * 0.1
		f["flap"] = 7.0
		f["glide"] = 1.0
		_flyers.append(f)
	_motes(Color(1.0, 1.0, 0.95, 0.9), 26, Vector3(17.0, 0.02, 4.0), Vector3(0, -0.6, 12.5), 0.12, 0.0, 1.2)
	_motes(Color(1.0, 1.0, 0.95, 0.9), 22, Vector3(4.0, 0.02, 12.0), Vector3(-16.5, -0.6, 0), 0.12, 0.0, 1.2)
	_motes(Color(1.0, 1.0, 0.95, 0.9), 22, Vector3(4.0, 0.02, 12.0), Vector3(16.5, -0.6, 0), 0.12, 0.0, 1.2)


func _haunted() -> void:
	for i in 4:
		var f := _flyer(Color("16121a"), Color("221a26"), 0.75)
		f["kind"] = "flit"
		f["c"] = Vector3(-10.0 if i % 2 == 0 else 10.0, 2.6 + i * 0.4, -1.5 + i)
		f["flap"] = 22.0
		_flyers.append(f)
	# Will-o'-the-wisps in the graveyard either side.
	_motes(Color(0.55, 1.0, 0.7, 0.8), 10, Vector3(2.0, 0.6, 6.0), Vector3(-10.0, 0.4, 0), 0.16, 0.04, 5.0)
	_motes(Color(0.55, 1.0, 0.7, 0.8), 10, Vector3(2.0, 0.6, 6.0), Vector3(10.0, 0.4, 0), 0.16, 0.04, 5.0)
	# Candelabras on the four corners of the base light the edges warm.
	var hx := Cfg.COLS * 0.5 + 0.9
	var hz := Cfg.ROWS * 0.5 + 0.7
	var cand := _candelabra_mesh()
	for c in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz), Vector2(-hx, 0.5), Vector2(hx, 0.5)]:
		var mi := MeshInstance3D.new()
		mi.mesh = cand
		mi.position = Vector3(c.x, GROUND_Y, c.y)
		add_child(mi)
		_pool(Vector3(c.x, GROUND_Y + 0.02, c.y), Color(1.0, 0.6, 0.28, 0.5), 4.2, true)
		_pool(Vector3(c.x, 1.06, c.y + (0.0 if absf(c.y) < 1.0 else -signf(c.y) * 0.35)), Color(1.0, 0.6, 0.28, 0.28), 2.6, true)


func _factory() -> void:
	# Steam venting from the floor grates, sparks from a welding cell, and
	# warm work-lamp pools round the hall.
	var hx := Cfg.COLS * 0.5
	for p in [Vector3(-hx - 2.6, GROUND_Y, -3.5), Vector3(hx + 2.4, GROUND_Y, 1.5), Vector3(-hx - 1.8, GROUND_Y, 4.0)]:
		_puffer(p, Color(0.85, 0.88, 0.92, 0.42), 3.2, 7, 1.8, 2.2)
	for p in [Vector3(hx + 2.2, 0.6, -4.2), Vector3(-hx - 2.4, 0.6, 1.0)]:
		var sp := CPUParticles3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.02
		sm.height = 0.04
		sp.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.6, 1.0, 0.45)
		sp.material_override = m
		sp.amount = 24
		sp.lifetime = 0.7
		sp.one_shot = true
		sp.explosiveness = 0.85
		sp.position = p
		sp.direction = Vector3.UP
		sp.spread = 70.0
		sp.initial_velocity_min = 1.5
		sp.initial_velocity_max = 3.5
		sp.gravity = Vector3(0, -9.0, 0)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.emitting = false
		add_child(sp)
		var fl := _pool(Vector3(p.x, GROUND_Y + 0.03, p.z), Color(1.0, 0.72, 0.4, 0.0), 3.0)
		_bursts.append({"node": sp, "every": 2.4, "t": _rng.randf() * 2.0, "flash": fl, "k": 0.0})
	for p in [Vector3(-hx - 2.0, GROUND_Y + 0.02, -1.0), Vector3(hx + 2.0, GROUND_Y + 0.02, 3.5), Vector3(hx + 1.8, GROUND_Y + 0.02, -5.5)]:
		_pool(p, Color(1.0, 0.66, 0.3, 0.22), 4.0)
	_pool(Vector3(-hx - 3.0, GROUND_Y + 0.02, -2.0), Color(1.0, 0.45, 0.15, 0.4), 5.0, true)


func _lightning(delta: float) -> void:
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = _rng.randf_range(8.0, 15.0)
		_flash = 1.0
		if game != null and game.audio != null:
			game.audio.play("thunder", -3.0, 0.08)
	if _flash <= 0.0 or game == null:
		return
	_flash = maxf(0.0, _flash - delta * 3.2)
	# Two quick strobes, then a fade.
	var k := _flash
	if _flash > 0.75 and _flash < 0.85:
		k = 0.25
	game.sun.light_energy = game.sun_base_energy * (1.0 + k * 2.6)
	game.env.ambient_light_energy = LA.theme("haunted")["ambient"] * (1.0 + k * 1.4)
	if _flash <= 0.0:
		game.sun.light_energy = game.sun_base_energy
		game.env.ambient_light_energy = LA.theme("haunted")["ambient"]


func _candelabra_mesh() -> Mesh:
	var iron := LA.metal(Color("2a2630"))
	var wax := Color("e8dcc0")
	var flame := LA.lit(Color("ffb050"))
	var parts: Array = [
		[LA.cyl(0.18, 0.24, 0.08, 10), LA.xf(Vector3(0, 0.04, 0)), iron],
		[LA.cyl(0.035, 0.05, 1.0, 8), LA.xf(Vector3(0, 0.55, 0)), iron],
		[LA.box(Vector3(0.62, 0.04, 0.05)), LA.xf(Vector3(0, 1.02, 0)), iron],
	]
	for x in [-0.3, 0.0, 0.3]:
		var h := 0.22 if x == 0.0 else 0.16
		parts.append([LA.cyl(0.04, 0.04, h, 8), LA.xf(Vector3(x, 1.04 + h * 0.5, 0)), wax])
		parts.append([LA.sphere(0.035, 8, 5), LA.xf(Vector3(x, 1.06 + h + 0.03, 0), Vector3.ZERO, Vector3(1, 1.8, 1)), flame])
	return LA.build(parts, LA.vmat("candelabra", 0.6, 0.0, 0.2, 5.0))
