extends RefCounted
## Builds the static scene for one arena: floor, walls, the base the arena
## stands on, and the world outside it. Built once per level change.

const Art := preload("res://scripts/art.gd")
const LA := preload("res://scripts/level_art.gd")
const Cfg := preload("res://scripts/config.gd")

const GROUND_Y := -0.34

static var _cache := {}


## hard: a PackedByteArray over the grid. skip: tiles whose walls are drawn
## elsewhere (the clockwork sections).
static func build(root: Node3D, level: Dictionary, hard: PackedByteArray, skip: Dictionary) -> void:
	var id: String = level["id"]
	var fm := PlaneMesh.new()
	fm.size = Vector2(Cfg.COLS, Cfg.ROWS)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = fm
	floor_mi.material_override = LA.floor_mat(id, 0.38)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_mi)
	# Walls
	var pillars: Array = []
	var borders := [[], [], []]
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			var i := y * Cfg.COLS + x
			if hard[i] == 0 or skip.has(Vector2i(x, y)):
				continue
			var p := tile_pos(x, y)
			var edge: bool = x == 0 or y == 0 or x == Cfg.COLS - 1 or y == Cfg.ROWS - 1
			if edge:
				var b := Basis(Vector3.UP, r.randi_range(0, 3) * PI / 2.0)
				if id == "beach":   # coral rocks sit any which way
					b = Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, r.randf_range(0.94, 1.12), 1.0))
				borders[r.randi_range(0, 2)].append(Transform3D(b, p + Vector3(0, 0.52, 0)))
			else:
				pillars.append(Transform3D(Basis(Vector3.UP, r.randi_range(0, 3) * PI / 2.0), p + Vector3(0, 0.49, 0)))
	if not pillars.is_empty():
		root.add_child(Art.multimesh(LA.pillar_mesh(id), pillars))
	for v in 3:
		if not borders[v].is_empty():
			root.add_child(Art.multimesh(LA.border_mesh(id, v), borders[v]))
	# The raised base the arena stands on, then the world around it
	var th: Dictionary = LA.theme(id)
	var base := Vector3(Cfg.COLS + 0.36, -GROUND_Y + 0.02, Cfg.ROWS + 0.36)
	var pm := Art.rounded_box(base, 0.07, 6, 0.0)
	pm.surface_set_material(0, LA.block_mat(id + "_plinth", {"style": {"beach": 0, "factory": 2}.get(id, 1),
		"side": th["plinth"], "top": th["plinth"].lightened(0.2), "rough": 0.85, "metal": 0.3 if id == "factory" else 0.0}))
	var pmi := MeshInstance3D.new()
	pmi.mesh = pm
	pmi.position = Vector3(0, GROUND_Y * 0.5 - 0.012, 0)
	root.add_child(pmi)
	var first := root.get_child_count()
	match id:
		"beach":
			_beach(root)
		"haunted":
			_haunted(root)
		"factory":
			_factory(root)
	# Nothing outside the walls casts a shadow (AAA review round 6, draw
	# calls): the shadow pass is for the board, where it tells you depth.
	for k in range(first, root.get_child_count()):
		var c := root.get_child(k)
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for g in c.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func tile_pos(x: float, y: float) -> Vector3:
	return Vector3(x - (Cfg.COLS - 1) * 0.5, 0.0, y - (Cfg.ROWS - 1) * 0.5)


static func _mi(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material = null, rot := Vector3.ZERO, scl := Vector3.ONE, shadows := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	if mat:
		m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = scl
	if not shadows:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	return m


static func _plane(size: Vector2, subdiv := 0) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	p.subdivide_width = subdiv
	p.subdivide_depth = subdiv
	return p


static func _ground(root: Node3D, c1: Color, c2: Color, y := GROUND_Y, rough := 0.95, key := "") -> void:
	var t := Art.noise_tex("ground_" + key, 31 + key.length(), 0.02,
		PackedColorArray([c1, c2.lerp(c1, 0.5), c2]), PackedFloat32Array([0.0, 0.55, 1.0]), 256, 6)
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.roughness = rough
	m.uv1_scale = Vector3(10, 10, 1)
	_mi(root, _plane(Vector2(90, 90)), Vector3(0, y, 0), m, Vector3.ZERO, Vector3.ONE, false)


## Points outside the arena rectangle (plus margin), at least `spacing` apart.
## `far_only`: nothing on the camera side of the arena, where tall props would
## sit on top of the near wall row.
static func _scatter(r: RandomNumberGenerator, count: int, margin: float, reach: float, spacing: float, placed: Array, near_only := false, far_only := false) -> Array:
	var out: Array = []
	var hx := Cfg.COLS * 0.5
	var hz := Cfg.ROWS * 0.5
	var tries := 0
	while out.size() < count and tries < count * 80:
		tries += 1
		var x := r.randf_range(-hx - reach, hx + reach)
		var z := r.randf_range(-hz - reach, hz - 1.2 if far_only else hz + 1.5)
		if absf(x) < hx + margin and absf(z) < hz + margin:
			continue
		if near_only and absf(x) > hx + reach * 0.6 and absf(z) > hz + reach * 0.6:
			continue
		var ok := true
		for q in placed:
			if Vector2(x, z).distance_to(q[0]) < maxf(spacing, q[1]):
				ok = false
				break
		if not ok:
			continue
		placed.append([Vector2(x, z), spacing])
		out.append(Vector2(x, z))
	return out


static func _mm(root: Node3D, mesh: Mesh, pts: Array, r: RandomNumberGenerator, y: float, smin := 0.85, smax := 1.2, shadows := true) -> void:
	if pts.is_empty():
		return
	var xs: Array = []
	for p in pts:
		var s := r.randf_range(smin, smax)
		xs.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
	root.add_child(Art.multimesh(mesh, xs, [], shadows))


static func _cached(key: String, fn: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = fn.call()
	return _cache[key]


# ---- Beach -----------------------------------------------------------------------------

static func _beach(root: Node3D) -> void:
	# A sandbar island in open water.
	var sand := LA.block_mat("sand", {"style": 9, "side": Color("6e5636"), "top": Color("86683f"), "rough": 0.95, "scale": 0.5})
	var isl := Art.rounded_box(Vector3(25, 1.0, 20), 0.45, 8, 0.2, 5)
	isl.surface_set_material(0, sand)
	_mi(root, isl, Vector3(0, GROUND_Y - 0.5, -1.0), null, Vector3.ZERO, Vector3.ONE, false)
	_mi(root, _plane(Vector2(160, 160), 40), Vector3(0, GROUND_Y - 0.3, 0), LA.water_mat(Color("06415e"), Color("1aa0c4"), 0.05), Vector3.ZERO, Vector3.ONE, false)
	# Surf where the sandbar meets the water: a band of foam that laps in and out.
	var foam := ShaderMaterial.new()
	foam.shader = LA._shader("foam", FOAM_SHADER)
	foam.set_shader_parameter("half", Vector2(12.5, 10.0))
	foam.set_shader_parameter("centre", Vector2(0.0, -1.0))
	foam.set_shader_parameter("radius", 0.45)
	foam.set_shader_parameter("noise_tex", LA.noise_tex())
	_mi(root, _plane(Vector2(31, 26)), Vector3(0, GROUND_Y - 0.26, -1.0), foam, Vector3.ZERO, Vector3.ONE, false)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var placed: Array = []
	# Mid-distance landmarks where the camera looks: a lifeguard tower on the
	# left, a boardwalk running off to the right.
	var bhx := Cfg.COLS * 0.5
	_mi(root, _cached("lifeguard", _lifeguard), Vector3(-bhx - 2.1, GROUND_Y, -1.5), null, Vector3(0, PI / 2.0, 0), Vector3.ONE, true)
	placed.append([Vector2(-bhx - 2.1, -1.5), 2.4])
	var planks: Array = []
	var px := bhx + 1.6
	while px < bhx + 12.0:
		planks.append(Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(1, 1, 1)), Vector3(px, GROUND_Y + 0.12, -2.0 + sin(px * 3.1) * 0.02)))
		px += 0.32
	var plank := LA.build([[LA.box(Vector3(0.28, 0.06, 1.5), 0.01), LA.xf(Vector3.ZERO), Color("9a7a52")]], LA.vmat("plank", 0.85, 0.0, 0.4))
	root.add_child(Art.multimesh(plank, planks))
	var posts: Array = []
	px = bhx + 1.8
	while px < bhx + 12.0:
		for side in [-0.8, 0.8]:
			posts.append(Transform3D(Basis(), Vector3(px, GROUND_Y, -2.0 + side)))
		px += 1.6
	var post := LA.build([[LA.cyl(0.07, 0.08, 0.5, 8), LA.xf(Vector3(0, 0.25, 0)), Color("6e5638")],
		[LA.box(Vector3(0.05, 0.5, 0.05)), LA.xf(Vector3(0, 0.6, 0)), Color("7a6040")]], LA.vmat("bwpost", 0.9, 0.0, 0.3))
	root.add_child(Art.multimesh(post, posts))
	for zz in [-2.0, -1.0, 0.0, -3.0]:
		placed.append([Vector2(bhx + 3.0, zz), 1.0])
		placed.append([Vector2(bhx + 5.0, zz), 1.0])
		placed.append([Vector2(bhx + 7.0, zz), 1.0])
	# No palm shadows: off-screen palms were throwing blobs across the floor.
	_mm(root, _cached("palm", _palm_mesh), _scatter(r, 16, 1.2, 8.0, 1.8, placed, false, true), r, GROUND_Y, 0.85, 1.25, false)
	var P := load("res://scripts/level_props.gd")
	for pt in _scatter(r, 5, 0.8, 4.5, 1.6, placed, false, true):
		var n: Node3D = P.make("parasol")
		n.position = Vector3(pt.x, GROUND_Y, pt.y)
		n.rotation.y = r.randf() * TAU
		root.add_child(n)
	for pt in _scatter(r, 6, 0.5, 4.0, 1.0, placed, false, true):
		var n: Node3D = P.make("beachball")
		n.position = Vector3(pt.x, GROUND_Y, pt.y)
		n.rotation.y = r.randf() * TAU
		n.scale = Vector3.ONE * 0.7
		root.add_child(n)
	var towels := _scatter(r, 5, 0.7, 4.0, 1.4, placed)
	for k in towels.size():
		var v := k % 3
		var pt: Vector2 = towels[k]
		_mi(root, _cached("towel%d" % v, func(): return _towel(v)), Vector3(pt.x, GROUND_Y + 0.01, pt.y), null, Vector3(0, r.randf() * TAU, 0))
	var rock := Art.rounded_box(Vector3(0.8, 0.5, 0.6), 0.22, 4, 0.1, 12)
	rock.surface_set_material(0, LA.block_mat("beach_border", LA.theme("beach")["border"]))
	_mm(root, rock, _scatter(r, 14, 0.4, 7.0, 0.9, placed), r, GROUND_Y, 0.6, 1.3)
	_mm(root, _cached("starfish", _starfish), _scatter(r, 10, 0.3, 5.0, 0.5, placed), r, GROUND_Y + 0.01, 0.8, 1.2, false)


static func _palm_mesh() -> Mesh:
	var trunk_c := Color("8a6a44")
	var parts: Array = []
	var lean := Vector3(0.35, 0, 0.1)
	var segs := 9
	for i in segs:
		var t := float(i) / segs
		var p := lean * t * t * 3.0 + Vector3(0, t * 2.7, 0)
		parts.append([LA.cyl(0.11 - t * 0.04, 0.13 - t * 0.04, 0.34, 8), LA.xf(p + Vector3(0, 0.15, 0), Vector3(0, 0, -0.18 * t)), trunk_c.lerp(Color("b08a58"), (i % 2) * 0.4)])
	var top := lean * 3.0 + Vector3(0, 2.85, 0)
	# Fronds: curved, tapering ribbons folded along the midrib (a shallow V),
	# with a serrated edge for the leaflets. Both faces, so they read from above.
	for k in 9:
		var a := TAU * k / 9.0 + (0.17 if k % 2 else 0.0)
		parts.append([_frond(a, 1.25 if k % 2 == 0 else 1.05), Transform3D(Basis(), top), null])
	for k in 3:
		parts.append([LA.sphere(0.09, 8, 5), LA.xf(top + Vector3(cos(k * 2.1) * 0.12, -0.12, sin(k * 2.1) * 0.12)), Color("5a3a1a")])
	return LA.build(parts, LA.vmat("palm", 0.8, 0.0, 0.3))


const FOAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec2 half = vec2(12.5, 10.0);
uniform vec2 centre = vec2(0.0);
uniform float radius = 0.45;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = abs(wpos.xz - centre) - half + radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float n = texture(noise_tex, wpos.xz * 0.25 + vec2(TIME * 0.03, 0.0)).r;
	float lap = 0.35 + 0.3 * sin(TIME * 0.9 + n * 4.0);
	float band = 1.0 - smoothstep(0.0, lap + 0.25, d);
	float edge = smoothstep(lap - 0.05, lap, d) * (1.0 - smoothstep(lap, lap + 0.12, d));
	float a = band * 0.45 * smoothstep(0.35, 0.75, n + 0.2) + edge * 0.85;
	a *= step(0.0, d);
	ALBEDO = vec3(0.95, 0.98, 1.0);
	ALPHA = clamp(a, 0.0, 0.9);
}
"""


static func _towel(v: int) -> Mesh:
	var cols := [[Color("ff5a5f"), Color("ffffff")], [Color("2f80ed"), Color("ffe066")], [Color("27ae60"), Color("ffffff")]]
	var parts: Array = []
	for k in 6:
		parts.append([LA.box(Vector3(0.62, 0.02, 0.2)), LA.xf(Vector3(0, 0.01, -0.5 + k * 0.2)), cols[v][k % 2]])
	return LA.build(parts, LA.vmat("towel", 0.95, 0.0, 0.4))


static func _starfish() -> Mesh:
	var parts: Array = []
	for k in 5:
		var a := TAU * k / 5.0
		parts.append([LA.cone(0.06, 0.22, 6), Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -PI / 2.0).scaled(Vector3(1, 1, 0.45)), Vector3(cos(a), 0, sin(a)) * 0.1 + Vector3(0, 0.02, 0)), Color("ff7a4a")])
	return LA.build(parts, LA.vmat("starfish", 0.8, 0.0, 0.5))


# ---- Haunted House -----------------------------------------------------------------

static func _haunted(root: Node3D) -> void:
	_ground(root, Color("120c14"), Color("2a1e22"), GROUND_Y, 0.95, "haunted")
	var r := RandomNumberGenerator.new()
	r.seed = 13
	var placed: Array = []
	_mm(root, _cached("deadtree0", func(): return _dead_tree(0)), _scatter(r, 9, 1.3, 9.0, 2.2, placed), r, GROUND_Y, 0.9, 1.4)
	_mm(root, _cached("deadtree1", func(): return _dead_tree(1)), _scatter(r, 9, 1.3, 9.0, 2.2, placed), r, GROUND_Y, 0.9, 1.4)
	var P := load("res://scripts/level_props.gd")
	_mm(root, P.gravestone_mesh(), _scatter(r, 22, 0.5, 6.0, 0.8, placed, true), r, GROUND_Y, 0.7, 1.05)
	for pt in _scatter(r, 6, 0.6, 5.0, 1.2, placed, true):
		var n: Node3D = P.make("pumpkin")
		n.position = Vector3(pt.x, GROUND_Y, pt.y)
		n.rotation.y = atan2(-pt.x, -pt.y) + PI
		root.add_child(n)
	# Iron fence along the plinth
	var fence: Array = []
	var hx := Cfg.COLS * 0.5 + 0.55
	var hz := Cfg.ROWS * 0.5 + 0.55
	var x := -hx
	while x <= hx:
		fence.append(Transform3D(Basis(), Vector3(x, GROUND_Y, -hz)))
		fence.append(Transform3D(Basis(), Vector3(x, GROUND_Y, hz)))
		x += 0.5
	var z := -hz + 0.5
	while z < hz:
		fence.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-hx, GROUND_Y, z)))
		fence.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(hx, GROUND_Y, z)))
		z += 0.5
	root.add_child(Art.multimesh(_cached("fence", _fence_post), fence))
	# The house itself behind the far wall (seen in the arrival flyover), and
	# graves in ordered rows either side instead of only a scatter.
	_mi(root, _cached("mansion", _mansion), Vector3(0.5, GROUND_Y, -hz - 6.0), null, Vector3.ZERO, Vector3.ONE, true)
	var rows: Array = []
	for s in [-1.0, 1.0]:
		for col in 3:
			var gx: float = s * (hx + 2.4 + col * 1.1)
			var gz := -hz + 0.4 + col * 0.4
			while gz < hz - 0.6:
				var skip: bool = (s < 0.0 and gz > -0.9 and gz < 3.3) or (s > 0.0 and gz > -0.4 and gz < 4.6)
				if not skip:
					rows.append(Transform3D(Basis(Vector3.UP, r.randf_range(-0.12, 0.12)).scaled(Vector3.ONE * r.randf_range(0.85, 1.05)), Vector3(gx, GROUND_Y, gz)))
				gz += 1.2
	# Architecture where the camera looks during play: a mausoleum on the left,
	# a broken wall with an arched gate and a lantern on the right.
	# Both turned three-quarters to the camera so their fronts (door, columns,
	# arch and lantern) read from the play view, not just their roofs.
	_mi(root, _cached("mausoleum", _mausoleum), Vector3(-hx - 2.6, GROUND_Y, 1.2), null, Vector3(0, 0.55, 0), Vector3.ONE, true)
	_mi(root, _cached("gate", _gate), Vector3(hx + 2.5, GROUND_Y, 2.0), null, Vector3(0, -0.55, 0), Vector3.ONE, true)
	root.add_child(Art.multimesh(P.gravestone_mesh(), rows))
	# low mist
	var mist := StandardMaterial3D.new()
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.albedo_texture = Art.soft_dot("mist", 0.0)
	mist.albedo_color = Color(0.55, 0.45, 0.75, 0.16)
	mist.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(5, 5)
	var mx: Array = []
	for pt in _scatter(r, 14, 0.2, 7.0, 2.0, placed):
		mx.append(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(pt.x, GROUND_Y + 0.15, pt.y)))
	var mm := Art.multimesh(q, mx, [], false)
	mm.material_override = mist
	root.add_child(mm)


static func _dead_tree(v: int) -> Mesh:
	var bark := Color("2a2026")
	var parts: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = 900 + v
	parts.append([LA.cyl(0.09, 0.2, 1.6, 8), LA.xf(Vector3(0, 0.8, 0), Vector3(0, 0, 0.06)), bark])
	for k in 5:
		var y := 0.9 + k * 0.28
		var a := r.randf() * TAU
		var l := r.randf_range(0.5, 0.95) * (1.0 - k * 0.1)
		var dir := Vector3(cos(a), r.randf_range(0.3, 0.9), sin(a)).normalized()
		var bas := Basis(Quaternion(Vector3.UP, dir))
		parts.append([LA.cyl(0.015, 0.06, l, 6), Transform3D(bas, Vector3(0, y, 0) + dir * l * 0.5), bark])
		var tip := Vector3(0, y, 0) + dir * l
		var d2 := (dir + Vector3(r.randf_range(-0.6, 0.6), 0.4, r.randf_range(-0.6, 0.6))).normalized()
		parts.append([LA.cyl(0.008, 0.025, l * 0.5, 5), Transform3D(Basis(Quaternion(Vector3.UP, d2)), tip + d2 * l * 0.25), bark])
	return LA.build(parts, LA.vmat("deadtree", 0.95, 0.0, 0.4))


static func _fence_post() -> Mesh:
	var iron := LA.metal(Color("1a1a20"))
	var parts: Array = [
		[LA.cyl(0.018, 0.018, 0.62, 6), LA.xf(Vector3(0, 0.31, 0)), iron],
		[LA.cone(0.035, 0.09, 6), LA.xf(Vector3(0, 0.66, 0)), iron],
		[LA.box(Vector3(0.5, 0.025, 0.02)), LA.xf(Vector3(0.25, 0.5, 0)), iron],
		[LA.box(Vector3(0.5, 0.025, 0.02)), LA.xf(Vector3(0.25, 0.14, 0)), iron],
	]
	return LA.build(parts, LA.vmat("fence", 0.6, 0.0, 0.2))


# ---- Factory -----------------------------------------------------------------------

static func _factory(root: Node3D) -> void:
	# An organised hall (AAA review: not props scattered on a void):
	# corrugated walls with lit clerestory windows and I-beam columns either
	# side, rows of machines facing the arena, pallet racks against the walls,
	# painted floor bays and walkways, pipes along the far side.
	_ground(root, Color("1e2024"), Color("33363c"), GROUND_Y, 0.8, "factory")
	var hx := Cfg.COLS * 0.5
	var hz := Cfg.ROWS * 0.5
	var wall_x := hx + 5.2
	var steel := Color("3a4048")
	var ribs: Array = []
	var z := -16.0
	while z <= 16.0:
		for s in [-1.0, 1.0]:
			ribs.append(Transform3D(Basis(), Vector3(s * wall_x, GROUND_Y + 2.2, z)))
		z += 0.45
	var rib := LA.build([[LA.box(Vector3(0.12, 4.4, 0.24)), LA.xf(Vector3.ZERO), steel],
		[LA.box(Vector3(0.06, 4.4, 0.22)), LA.xf(Vector3(0.05, 0, 0.0)), steel.lightened(0.12)]], LA.vmat("hall_rib", 0.6, 0.4, 0.2))
	root.add_child(Art.multimesh(rib, ribs))
	for s in [-1.0, 1.0]:
		var win := MeshInstance3D.new()
		win.mesh = LA.build([[LA.box(Vector3(0.05, 0.7, 32.0)), LA.xf(Vector3.ZERO), LA.lit(Color("9fd0ff"))]], LA.vmat("hall_window", 0.3, 0.0, 0.0, 1.6))
		win.position = Vector3(s * (wall_x - 0.1), GROUND_Y + 3.4, 0)
		root.add_child(win)
	# I-beam columns with yellow feet, every 3 m in front of each wall.
	var beam := LA.build([
		[LA.box(Vector3(0.36, 5.0, 0.06)), LA.xf(Vector3(0, 2.5, -0.15)), Color("4a525c")],
		[LA.box(Vector3(0.36, 5.0, 0.06)), LA.xf(Vector3(0, 2.5, 0.15)), Color("4a525c")],
		[LA.box(Vector3(0.06, 5.0, 0.3)), LA.xf(Vector3(0, 2.5, 0)), Color("40474f")],
		[LA.box(Vector3(0.46, 0.5, 0.42), 0.02), LA.xf(Vector3(0, 0.25, 0)), Color("d8a818")],
	], LA.vmat("ibeam", 0.55, 0.35, 0.2))
	var cols: Array = []
	z = -15.0
	while z <= 15.0:
		for s in [-1.0, 1.0]:
			cols.append(Transform3D(Basis(), Vector3(s * (wall_x - 0.25), GROUND_Y, z)))
		z += 3.0
	root.add_child(Art.multimesh(beam, cols))
	# Machines in a row each side, facing the arena, on painted bays.
	var mxs: Array = [[], [], []]
	var bay := StandardMaterial3D.new()
	bay.albedo_color = Color(0.17, 0.19, 0.22)
	bay.roughness = 0.75
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(0.85, 0.66, 0.08)
	line.roughness = 0.7
	for s in [-1.0, 1.0]:
		var mx: float = s * (hx + 2.2)
		var zz := -hz + 0.6
		var mi := 0 if s < 0.0 else 1
		while zz < hz + 0.5:
			mxs[mi % 3].append(Transform3D(Basis(Vector3.UP, -s * PI / 2.0), Vector3(mx, GROUND_Y, zz)))
			mi += 1
			zz += 2.3
		_mi(root, _plane(Vector2(2.2, Cfg.ROWS + 3.0)), Vector3(mx, GROUND_Y + 0.004, 0), bay, Vector3.ZERO, Vector3.ONE, false)
		for e in [-1.0, 1.0]:
			_mi(root, _plane(Vector2(0.1, Cfg.ROWS + 3.0)), Vector3(mx + e * 1.1, GROUND_Y + 0.006, 0), line, Vector3.ZERO, Vector3.ONE, false)
	for v in 3:
		if not mxs[v].is_empty():
			_mm_fixed(root, _cached("machine%d" % v, func(): return _machine_v(v)), mxs[v])
	# Pallet racks against the walls, stocked with the arena's crates.
	var racks: Array = []
	var stock: Array = []
	var crates: Array = LA.crate_meshes("factory")
	for s in [-1.0, 1.0]:
		var rx: float = s * (wall_x - 1.0)
		var zz := -hz - 1.0
		while zz < hz + 2.0:
			racks.append(Transform3D(Basis(Vector3.UP, s * PI / 2.0), Vector3(rx, GROUND_Y, zz)))
			for lvl in [0.12, 1.32]:
				stock.append(Transform3D(Basis(), Vector3(rx, GROUND_Y + lvl, zz - 0.5)))
				stock.append(Transform3D(Basis(), Vector3(rx, GROUND_Y + lvl, zz + 0.5)))
			zz += 2.3
	root.add_child(Art.multimesh(_cached("rack", _rack), racks))
	root.add_child(Art.multimesh(crates[0], stock))
	# Pipes running along the far side
	var pipe := LA.build([[LA.cyl(0.14, 0.14, 1.0, 12), LA.xf(Vector3.ZERO, Vector3(0, 0, PI / 2.0)), LA.metal(Color("7a828c"))],
		[LA.cyl(0.17, 0.17, 0.06, 12), LA.xf(Vector3(0.48, 0, 0), Vector3(0, 0, PI / 2.0)), LA.metal(Color("c9a020"))]], LA.vmat("pipe", 0.45, 0.0, 0.2))
	var px: Array = []
	for i in 30:
		var x := -15.0 + i
		px.append(Transform3D(Basis(), Vector3(x, GROUND_Y + 0.3, -hz - 2.4)))
		px.append(Transform3D(Basis(), Vector3(x, GROUND_Y + 0.75, -hz - 2.4)))
	root.add_child(Art.multimesh(pipe, px))
	# Walkway lines round the plinth
	for s in [-1.0, 1.0]:
		_mi(root, _plane(Vector2(Cfg.COLS + 2.2, 0.12)), Vector3(0, GROUND_Y + 0.005, s * (hz + 1.0)), line, Vector3.ZERO, Vector3.ONE, false)
		_mi(root, _plane(Vector2(0.12, Cfg.ROWS + 2.1)), Vector3(s * (hx + 1.0), GROUND_Y + 0.005, 0), line, Vector3.ZERO, Vector3.ONE, false)


static func _mm_fixed(root: Node3D, mesh: Mesh, xs: Array) -> void:
	root.add_child(Art.multimesh(mesh, xs))


## A two-level pallet rack: orange uprights, blue beams, plank decks.
## The haunted house: a tall dark manor with two towers, a steep roof and a
## few lit windows.
static func _mansion() -> Mesh:
	var wall := Color("2a2230")
	var roof := Color("1a1420")
	var trim := Color("3a3040")
	var win := LA.lit(Color("ffb050"))
	var dark_win := Color("101015")
	var parts: Array = [
		[LA.box(Vector3(7.0, 3.6, 3.0), 0.05), LA.xf(Vector3(0, 1.8, 0)), wall],
		[LA.box(Vector3(7.4, 0.2, 3.3)), LA.xf(Vector3(0, 3.6, 0)), trim],
		[LA.box(Vector3(7.2, 2.2, 2.2)), LA.xf(Vector3(0, 4.3, 0), Vector3(PI / 4.0, 0, 0), Vector3(1, 0.72, 0.72)), roof],
		[LA.box(Vector3(0.5, 1.4, 0.5)), LA.xf(Vector3(1.6, 5.2, 0.3)), trim],
	]
	for tx in [-3.9, 3.9]:
		parts.append([LA.box(Vector3(1.8, 5.0, 1.8), 0.04), LA.xf(Vector3(tx, 2.5, 0.4)), wall.lightened(0.04)])
		parts.append([LA.cone(1.35, 2.4, 8), LA.xf(Vector3(tx, 6.2, 0.4)), roof])
	var lit := [[-2.2, 2.4], [0.8, 1.0], [2.4, 2.4], [-3.9, 3.6], [3.9, 1.4]]
	for wx in [-2.2, -0.7, 0.8, 2.4]:
		for wy in [1.0, 2.4]:
			var on := false
			for l in lit:
				if is_equal_approx(l[0], wx) and is_equal_approx(l[1], wy):
					on = true
			parts.append([LA.box(Vector3(0.55, 0.8, 0.05)), LA.xf(Vector3(wx, wy, 1.52)), win if on else dark_win])
	for tx in [-3.9, 3.9]:
		for wy in [1.4, 3.6]:
			parts.append([LA.box(Vector3(0.45, 0.7, 0.05)), LA.xf(Vector3(tx, wy, 1.32)), win if (tx < 0.0) == (wy > 2.0) else dark_win])
	parts.append([LA.box(Vector3(1.1, 1.6, 0.08)), LA.xf(Vector3(0.0, 0.8, 1.52)), Color("1a1010")])
	return LA.build(parts, LA.vmat("mansion", 0.9, 0.0, 0.3, 3.0))


## AAA review round 6: a temple front that reads from the play camera, cool
## stone with moonlit edges, four columns, steps, a cross on the pediment and
## a warm lit doorway (its glow pool is in ambient.gd).
static func _mausoleum() -> Mesh:
	var stone := Color("55506a")
	var dark := Color("3a3648")
	var moon := Color("8fa0d8")
	var parts: Array = [
		[LA.box(Vector3(2.9, 0.18, 2.7)), LA.xf(Vector3(0, 0.09, -0.1)), dark],
		[LA.box(Vector3(2.3, 0.14, 0.36)), LA.xf(Vector3(0, 0.07, 1.38)), dark],
		[LA.box(Vector3(2.5, 0.12, 0.34)), LA.xf(Vector3(0, 0.24, 1.08)), moon.darkened(0.35)],
		[LA.box(Vector3(2.2, 2.0, 1.7), 0.03), LA.xf(Vector3(0, 1.18, -0.35)), stone],
		[LA.box(Vector3(2.7, 0.22, 2.4)), LA.xf(Vector3(0, 2.29, 0.0)), dark],
		[LA.box(Vector3(2.74, 0.05, 0.08)), LA.xf(Vector3(0, 2.41, 1.18)), moon],
		[LA.box(Vector3(1.4, 1.4, 2.4)), LA.xf(Vector3(0, 2.42, 0), Vector3(0, 0, PI / 4.0), Vector3(1.32, 0.5, 1.0)), Color("2e2a3c")],
		[LA.box(Vector3(0.07, 0.07, 2.44)), LA.xf(Vector3(0, 2.92, 0)), moon.darkened(0.2)],
		[LA.box(Vector3(1.6, 0.06, 0.06)), LA.xf(Vector3(-0.66, 2.78, 1.2), Vector3(0, 0, 0.37)), moon],
		[LA.box(Vector3(1.6, 0.06, 0.06)), LA.xf(Vector3(0.66, 2.78, 1.2), Vector3(0, 0, -0.37)), moon],
		# cross on the apex
		[LA.box(Vector3(0.11, 0.62, 0.11)), LA.xf(Vector3(0, 3.55, 1.0)), moon.darkened(0.1)],
		[LA.box(Vector3(0.4, 0.11, 0.11)), LA.xf(Vector3(0, 3.65, 1.0)), moon.darkened(0.1)],
		# doorway: dark frame, warm glow inside
		[LA.box(Vector3(0.95, 1.45, 0.06)), LA.xf(Vector3(0, 1.0, 0.52)), Color("1a1418")],
		[LA.box(Vector3(0.72, 1.25, 0.04)), LA.xf(Vector3(0, 0.95, 0.56)), LA.lit(Color("ffa850"))],
		[LA.box(Vector3(1.1, 0.12, 0.1)), LA.xf(Vector3(0, 1.75, 0.55)), moon.darkened(0.25)],
	]
	for x in [-1.08, -0.62, 0.62, 1.08]:
		parts.append([LA.cyl(0.11, 0.13, 1.92, 10), LA.xf(Vector3(x, 1.26, 1.0)), stone.lightened(0.18)])
		parts.append([LA.box(Vector3(0.3, 0.1, 0.3)), LA.xf(Vector3(x, 2.17, 1.0)), moon.darkened(0.2)])
		parts.append([LA.box(Vector3(0.3, 0.1, 0.3)), LA.xf(Vector3(x, 0.35, 1.0)), dark])
	return LA.build(parts, LA.vmat("mausoleum", 0.9, 0.0, 0.4))


## AAA review round 6: an arched gateway silhouette, moonlit stone, iron
## bars rising to the arch, and a lantern hanging from the keystone.
static func _gate() -> Mesh:
	var stone := Color("55506a")
	var moon := Color("8fa0d8")
	var iron := Color("1c1a20")
	var parts: Array = [
		[LA.box(Vector3(0.62, 2.4, 0.62), 0.03), LA.xf(Vector3(-1.15, 1.2, 0)), stone],
		[LA.box(Vector3(0.62, 2.4, 0.62), 0.03), LA.xf(Vector3(1.15, 1.2, 0)), stone],
		[LA.box(Vector3(0.72, 0.12, 0.72)), LA.xf(Vector3(-1.15, 2.42, 0)), moon.darkened(0.3)],
		[LA.box(Vector3(0.72, 0.12, 0.72)), LA.xf(Vector3(1.15, 2.42, 0)), moon.darkened(0.3)],
		[LA.box(Vector3(2.2, 1.0, 0.45), 0.02), LA.xf(Vector3(-2.6, 0.5, 0.0), Vector3(0, 0, 0.05)), stone],
		[LA.box(Vector3(1.4, 0.6, 0.45), 0.02), LA.xf(Vector3(2.4, 0.3, 0.0)), stone],
		[LA.box(Vector3(2.24, 0.05, 0.49)), LA.xf(Vector3(-2.6, 1.02, 0.0), Vector3(0, 0, 0.05)), moon.darkened(0.2)],
	]
	# The arch: voussoirs round a semicircle springing from the pillar tops.
	var seg := 9
	for k in seg:
		var a := PI * (k + 0.5) / seg
		var pos := Vector3(cos(a) * 1.15, 2.48 + sin(a) * 1.0, 0)
		parts.append([LA.box(Vector3(0.4, 0.3, 0.44)), LA.xf(pos, Vector3(0, 0, a - PI / 2.0)), stone.lightened(0.1) if k == seg / 2 else stone])
		parts.append([LA.box(Vector3(0.38, 0.03, 0.04)), LA.xf(pos + Vector3(cos(a), sin(a), 0) * 0.16 + Vector3(0, 0, 0.22), Vector3(0, 0, a - PI / 2.0)), moon.darkened(0.2)])
	# Bars rise to the arch's inner curve.
	for k in 7:
		var x := -0.66 + k * 0.22
		var top := 2.48 + sqrt(maxf(0.0, 0.8 * 0.8 - x * x)) * 0.95
		var h := top - 0.05
		parts.append([LA.box(Vector3(0.045, h, 0.045)), LA.xf(Vector3(x, h * 0.5, 0.05), Vector3(0, 0, 0.0 if k % 3 else 0.05)), iron])
		parts.append([LA.cone(0.04, 0.12, 4), LA.xf(Vector3(x, top + 0.04, 0.05)), iron])
	parts.append([LA.box(Vector3(1.6, 0.05, 0.05)), LA.xf(Vector3(0, 1.8, 0.05)), iron])
	parts.append([LA.box(Vector3(1.6, 0.05, 0.05)), LA.xf(Vector3(0, 0.4, 0.05)), iron])
	# Lantern under the keystone, on the near face.
	parts.append([LA.box(Vector3(0.03, 0.4, 0.03)), LA.xf(Vector3(0, 3.0, 0.32)), iron])
	parts.append([LA.box(Vector3(0.3, 0.06, 0.3)), LA.xf(Vector3(0, 2.8, 0.32)), iron])
	parts.append([LA.box(Vector3(0.22, 0.3, 0.22)), LA.xf(Vector3(0, 2.6, 0.32)), LA.lit(Color("ffb050"))])
	parts.append([LA.cone(0.2, 0.16, 4), LA.xf(Vector3(0, 2.84, 0.32), Vector3(0, PI / 4.0, 0)), iron])
	parts.append([LA.box(Vector3(0.26, 0.04, 0.26)), LA.xf(Vector3(0, 2.44, 0.32)), iron])
	return LA.build(parts, LA.vmat("gate", 0.9, 0.0, 0.4, 3.0))


static func _lifeguard() -> Mesh:
	var wood := Color("e8e2d6")
	var red := Color("d8402e")
	var parts: Array = []
	for x in [-0.6, 0.6]:
		for z in [-0.6, 0.6]:
			parts.append([LA.box(Vector3(0.1, 2.0, 0.1)), LA.xf(Vector3(x, 1.0, z), Vector3(z * -0.08, 0, x * 0.08)), wood])
	parts.append_array([
		[LA.box(Vector3(1.6, 0.1, 1.6)), LA.xf(Vector3(0, 2.0, 0)), wood.darkened(0.15)],
		[LA.box(Vector3(1.2, 0.9, 1.2), 0.02), LA.xf(Vector3(0, 2.5, 0)), red],
		[LA.box(Vector3(1.24, 0.25, 1.24)), LA.xf(Vector3(0, 2.6, 0)), wood],
		[LA.box(Vector3(1.6, 0.08, 1.6)), LA.xf(Vector3(0, 3.0, 0), Vector3(0.12, 0, 0)), red.darkened(0.1)],
		[LA.box(Vector3(0.6, 0.4, 0.04)), LA.xf(Vector3(0, 2.6, 0.63)), Color("2a3a48")],
		[LA.box(Vector3(0.04, 1.2, 0.04)), LA.xf(Vector3(0.75, 3.6, -0.6)), wood],
		[LA.box(Vector3(0.5, 0.3, 0.02)), LA.xf(Vector3(1.0, 4.05, -0.6)), red],
	])
	for k in 6:
		parts.append([LA.box(Vector3(0.5, 0.05, 0.08)), LA.xf(Vector3(0, 0.25 + k * 0.3, 1.0), Vector3(-0.4, 0, 0)), wood.darkened(0.1)])
	return LA.build(parts, LA.vmat("lifeguard", 0.8, 0.0, 0.3))


static func _rack() -> Mesh:
	var up := Color("d0641c")
	var beam := Color("2c5a9a")
	var deck := Color("8a6a44")
	var parts: Array = []
	for x in [-1.05, 1.05]:
		for zz in [-0.45, 0.45]:
			parts.append([LA.box(Vector3(0.08, 2.5, 0.08)), LA.xf(Vector3(x, 1.25, zz)), up])
	for y in [0.1, 1.3, 2.45]:
		for zz in [-0.45, 0.45]:
			parts.append([LA.box(Vector3(2.2, 0.1, 0.06)), LA.xf(Vector3(0, y, zz)), beam])
		parts.append([LA.box(Vector3(2.1, 0.03, 0.9)), LA.xf(Vector3(0, y + 0.05, 0)), deck])
	return LA.build(parts, LA.vmat("rack", 0.6, 0.2, 0.2))


static func _frond(a: float, length: float) -> ArrayMesh:
	var dir := Vector3(cos(a), 0, sin(a))
	var side := dir.cross(Vector3.UP).normalized()
	var rows: Array = []
	var p := Vector3.ZERO
	var pitch := 0.6
	var n := 8
	for i in n + 1:
		var t := float(i) / n
		var w := 0.34 * sin(clampf(t * 1.15, 0.0, 1.0) * PI) * (0.82 + 0.18 * float(i % 2)) + 0.02
		var droop := 0.07 * w / 0.34
		var col := Color("2a6e2c").lerp(Color("78bc4e"), t * 0.8)
		rows.append([p + side * w - Vector3(0, droop, 0), p, p - side * w - Vector3(0, droop, 0), col])
		var d := (dir * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
		p += d * (length / n)
		pitch -= 0.27
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for half in 2:
			var a0: Vector3 = r0[half]
			var a1: Vector3 = r0[half + 1]
			var b0: Vector3 = r1[half]
			var b1: Vector3 = r1[half + 1]
			for tri in [[a0, b0, a1], [a1, b0, b1]]:
				var nrm: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				for face in 2:
					var order: Array = tri if face == 0 else [tri[0], tri[2], tri[1]]
					for v in order:
						st.set_color(r0[3] if v == a0 or v == a1 else r1[3])
						st.set_normal(nrm if face == 0 else -nrm)
						st.add_vertex(v)
	return st.commit()


## Three kinds of machine so the hall isn't one model cloned: the original
## press (0), a long lathe (1) and a tall control cabinet (2).
static func _machine_v(v: int) -> Mesh:
	if v == 0:
		return _machine()
	var body := Color("4c5562")
	var parts: Array = [[LA.box(Vector3(1.5, 0.08, 1.0), 0.02), LA.xf(Vector3(0, 0.04, 0)), Color("ffcc1a")]]
	if v == 1:
		parts.append_array([
			[LA.box(Vector3(1.6, 0.7, 0.6), 0.05), LA.xf(Vector3(0, 0.35, -0.1)), Color("3d6b5a")],
			[LA.box(Vector3(1.5, 0.12, 0.5)), LA.xf(Vector3(0, 0.78, -0.1)), LA.metal(Color("9aa2ac"))],
			[LA.cyl(0.2, 0.2, 0.3, 14), LA.xf(Vector3(-0.55, 0.98, -0.1), Vector3(0, 0, PI / 2.0)), LA.metal(Color("b0b6bf"))],
			[LA.cyl(0.05, 0.05, 0.9, 8), LA.xf(Vector3(0.0, 0.98, -0.1), Vector3(0, 0, PI / 2.0)), LA.metal(Color("c9ced6"))],
			[LA.box(Vector3(0.18, 0.25, 0.25), 0.02), LA.xf(Vector3(0.45, 0.98, -0.1)), Color("2a2e36")],
			[LA.box(Vector3(0.3, 0.3, 0.05), 0.02), LA.xf(Vector3(0.6, 0.6, 0.22)), Color("23272e")],
			[LA.box(Vector3(0.1, 0.06, 0.06)), LA.xf(Vector3(0.55, 0.65, 0.25)), LA.lit(Color("3df2a0"))],
		])
	else:
		parts.append_array([
			[LA.box(Vector3(0.9, 1.9, 0.6), 0.04), LA.xf(Vector3(0, 0.95, -0.1)), body.darkened(0.1)],
			[LA.box(Vector3(0.7, 0.45, 0.04), 0.02), LA.xf(Vector3(0, 1.45, 0.21)), LA.lit(Color("2f8fd8"))],
			[LA.box(Vector3(0.7, 0.05, 0.05)), LA.xf(Vector3(0, 1.1, 0.22)), Color("1a1d22")],
			[LA.box(Vector3(0.12, 0.08, 0.04)), LA.xf(Vector3(-0.2, 0.95, 0.22)), LA.lit(Color("ff4040"))],
			[LA.box(Vector3(0.12, 0.08, 0.04)), LA.xf(Vector3(0.0, 0.95, 0.22)), LA.lit(Color("ffb020"))],
			[LA.box(Vector3(0.12, 0.08, 0.04)), LA.xf(Vector3(0.2, 0.95, 0.22)), LA.lit(Color("3df2a0"))],
			[LA.box(Vector3(0.5, 0.6, 0.5), 0.04), LA.xf(Vector3(0.75, 0.3, -0.1)), Color("2f5a8a")],
			[LA.cyl(0.08, 0.08, 1.2, 8), LA.xf(Vector3(-0.6, 0.6, -0.25)), LA.metal(Color("8a9099"))],
		])
	return LA.build(parts, LA.vmat("machine%d" % v, 0.55, 0.3, 0.25, 2.5))


static func _machine() -> Mesh:
	var body := Color("4c5562")
	var parts: Array = [
		[LA.box(Vector3(1.4, 1.1, 0.9), 0.05), LA.xf(Vector3(0, 0.55, 0)), body],
		[LA.box(Vector3(1.2, 0.5, 0.04), 0.02), LA.xf(Vector3(0, 0.66, 0.46)), Color("23272e")],
		[LA.box(Vector3(0.3, 0.2, 0.06), 0.02), LA.xf(Vector3(-0.35, 0.72, 0.48)), LA.lit(Color("3df2a0"))],
		[LA.box(Vector3(0.14, 0.08, 0.06), 0.02), LA.xf(Vector3(0.2, 0.8, 0.48)), LA.lit(Color("ffb020"))],
		[LA.box(Vector3(0.14, 0.08, 0.06), 0.02), LA.xf(Vector3(0.4, 0.8, 0.48)), LA.lit(Color("ff4040"))],
		[LA.cyl(0.12, 0.12, 0.5, 10), LA.xf(Vector3(0.45, 1.3, -0.15)), LA.metal(Color("8a9099"))],
		[LA.box(Vector3(1.46, 0.08, 0.96), 0.02), LA.xf(Vector3(0, 0.04, 0)), Color("ffcc1a")],
	]
	return LA.build(parts, LA.vmat("machine", 0.55, 0.3, 0.25))
