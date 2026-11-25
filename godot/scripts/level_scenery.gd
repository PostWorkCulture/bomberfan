extends RefCounted
## Builds the static scene for one arena: floor, walls, the base the arena
## stands on, and the world outside it. Built once per level change.

const Art := preload("res://scripts/art.gd")
const LA := preload("res://scripts/level_art.gd")
const Levels := preload("res://scripts/levels.gd")
const Cfg := preload("res://scripts/config.gd")

const GROUND_Y := -0.34

static var _cache := {}


## voids/hard: PackedByteArrays over the grid. skip: tiles whose walls are drawn
## elsewhere (the clockwork sections).
static func build(root: Node3D, level: Dictionary, hard: PackedByteArray, voids: PackedByteArray, skip: Dictionary) -> void:
	var id: String = level["id"]
	var shaped: bool = Levels.SHAPES.has(level.get("layout", ""))
	# Floor, with void tiles cut out of it.
	var img := Image.create(Cfg.COLS, Cfg.ROWS, false, Image.FORMAT_L8)
	for y in Cfg.ROWS:
		for x in Cfg.COLS:
			img.set_pixel(x, y, Color(0, 0, 0) if voids[y * Cfg.COLS + x] == 1 else Color(1, 1, 1))
	var mask := ImageTexture.create_from_image(img)
	var fm := PlaneMesh.new()
	fm.size = Vector2(Cfg.COLS, Cfg.ROWS)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = fm
	floor_mi.material_override = LA.floor_mat(id, mask, 0.0 if shaped else 0.38)
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
			if hard[i] == 0 or voids[i] == 1 or skip.has(Vector2i(x, y)):
				continue
			var p := tile_pos(x, y)
			var edge: bool = not shaped and (x == 0 or y == 0 or x == Cfg.COLS - 1 or y == Cfg.ROWS - 1)
			if edge:
				var b := Basis(Vector3.UP, r.randi_range(0, 3) * PI / 2.0)
				if THEMES_ROUGH.has(id):
					b = Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, r.randf_range(0.94, 1.12), 1.0))
				borders[r.randi_range(0, 2)].append(Transform3D(b, p + Vector3(0, 0.52, 0)))
			else:
				pillars.append(Transform3D(Basis(Vector3.UP, r.randi_range(0, 3) * PI / 2.0), p + Vector3(0, 0.49, 0)))
	if not pillars.is_empty():
		root.add_child(Art.multimesh(LA.pillar_mesh(id), pillars))
	for v in 3:
		if not borders[v].is_empty():
			root.add_child(Art.multimesh(LA.border_mesh(id, v), borders[v]))
	# Base and surroundings
	if shaped:
		match level["layout"]:
			"twin-islands":
				_glacier_base(root)
			"pirate-fleet":
				_pirate_base(root)
			"haunted-train":
				_train_base(root)
	else:
		var th: Dictionary = LA.theme(id)
		var base := Vector3(Cfg.COLS + 0.36, -GROUND_Y + 0.02, Cfg.ROWS + 0.36)
		var pm := Art.rounded_box(base, 0.07, 6, 0.0)
		pm.surface_set_material(0, LA.block_mat(id + "_plinth", {"style": 0 if id == "beach" else (2 if id in ["factory", "circuit"] else 1),
			"side": th["plinth"], "top": th["plinth"].lightened(0.2), "rough": 0.85, "metal": 0.3 if id in ["factory", "circuit"] else 0.0,
			"glow": Color("6ef0ff") if id == "circuit" else Color.BLACK}))
		var pmi := MeshInstance3D.new()
		pmi.mesh = pm
		pmi.position = Vector3(0, GROUND_Y * 0.5 - 0.012, 0)
		root.add_child(pmi)
	match id:
		"beach":
			_beach(root)
		"glacier":
			_glacier(root)
		"haunted":
			_haunted(root)
		"haunted-train":
			_train(root)
		"factory":
			_factory(root)
		"circuit":
			_circuit(root)
		"pirate":
			_pirate(root)

const THEMES_ROUGH := {"beach": true, "glacier": true}


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
static func _scatter(r: RandomNumberGenerator, count: int, margin: float, reach: float, spacing: float, placed: Array, near_only := false) -> Array:
	var out: Array = []
	var hx := Cfg.COLS * 0.5
	var hz := Cfg.ROWS * 0.5
	var tries := 0
	while out.size() < count and tries < count * 80:
		tries += 1
		var x := r.randf_range(-hx - reach, hx + reach)
		var z := r.randf_range(-hz - reach, hz + 1.5)
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
	var sand := LA.block_mat("sand", {"style": 0, "side": Color("b8955c"), "top": Color("cfb07a"), "rough": 0.95, "scale": 0.5})
	var isl := Art.rounded_box(Vector3(25, 1.0, 20), 0.45, 8, 0.2, 5)
	isl.surface_set_material(0, sand)
	_mi(root, isl, Vector3(0, GROUND_Y - 0.5, -1.0), null, Vector3.ZERO, Vector3.ONE, false)
	_mi(root, _plane(Vector2(160, 160), 40), Vector3(0, GROUND_Y - 0.3, 0), LA.water_mat(Color("06415e"), Color("1aa0c4"), 0.05), Vector3.ZERO, Vector3.ONE, false)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var placed: Array = []
	_mm(root, _cached("palm", _palm_mesh), _scatter(r, 16, 1.2, 8.0, 1.8, placed), r, GROUND_Y, 0.85, 1.25)
	var P := load("res://scripts/level_props.gd")
	for pt in _scatter(r, 5, 0.8, 4.5, 1.6, placed):
		var n: Node3D = P.make("parasol")
		n.position = Vector3(pt.x, GROUND_Y, pt.y)
		n.rotation.y = r.randf() * TAU
		root.add_child(n)
	for pt in _scatter(r, 6, 0.5, 4.0, 1.0, placed):
		var n: Node3D = P.make("beachball")
		n.position = Vector3(pt.x, GROUND_Y, pt.y)
		n.rotation.y = r.randf() * TAU
		n.scale = Vector3.ONE * 0.8
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
	for k in 8:
		var a := TAU * k / 8.0 + (0.2 if k % 2 else 0.0)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP).normalized()
		var length := 0.95 if k % 2 == 0 else 0.8
		# each frond: an inner rising half and an outer drooping half
		for j in 2:
			var tilt := 0.25 if j == 0 else -0.55
			var bas := Basis(side, tilt) * Basis(Vector3.UP, -a + PI / 2.0)
			var mid := top + dir * (length * (0.28 + j * 0.5)) + Vector3(0, 0.08 - j * 0.22, 0)
			parts.append([LA.sphere(0.5, 12, 6), Transform3D(bas.scaled(Vector3(0.32, 0.05, length * 0.6)), mid), Color("3f8f3a").lerp(Color("6fbf4a"), 0.3 + j * 0.4)])
	for k in 3:
		parts.append([LA.sphere(0.09, 8, 5), LA.xf(top + Vector3(cos(k * 2.1) * 0.12, -0.12, sin(k * 2.1) * 0.12)), Color("5a3a1a")])
	return LA.build(parts, LA.vmat("palm", 0.8, 0.0, 0.3))


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


# ---- Glacier ---------------------------------------------------------------------------

static func _glacier_base(root: Node3D) -> void:
	var cliff := LA.block_mat("glacier_cliff", {"style": 4, "side": Color("8fc0e4"), "top": Color("e8f4ff"), "rough": 0.2, "scale": 0.4})
	for rect in Levels.SHAPES["twin-islands"]["floors"]:
		var w: float = rect[2] - rect[0] + 1
		var h: float = rect[3] - rect[1] + 1
		var c := (tile_pos(rect[0], rect[1]) + tile_pos(rect[2], rect[3])) * 0.5
		var m := Art.rounded_box(Vector3(w + 0.3, 2.2, h + 0.3), 0.14, 6, 0.08, int(c.x * 10.0))
		m.surface_set_material(0, cliff)
		_mi(root, m, c + Vector3(0, -1.11, 0))
	# Rope bridge over the gap
	var parts: Array = []
	var wood := Color("8a6440")
	for p in Levels.SHAPES["twin-islands"]["paths"]:
		var pos := tile_pos(p[0], p[1])
		for k in 5:
			parts.append([LA.box(Vector3(0.18, 0.06, 0.96), 0.01), LA.xf(pos + Vector3(-0.4 + k * 0.2, -0.03, 0)), wood.lerp(Color("a8805a"), (k % 2) * 0.5)])
	var a := tile_pos(5.5, 6)
	var b := tile_pos(8.5, 6)
	for s in [-1.0, 1.0]:
		for x in [a.x, b.x]:
			parts.append([LA.cyl(0.05, 0.06, 0.7, 8), LA.xf(Vector3(x, 0.3, a.z + s * 0.52)), Color("5a3a20")])
		parts.append([LA.cyl(0.018, 0.018, b.x - a.x, 6), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3((a.x + b.x) * 0.5, 0.55, a.z + s * 0.52)), Color("c8b08a")])
	_mi(root, LA.build(parts, LA.vmat("bridge", 0.85, 0.0, 0.35)), Vector3.ZERO)


static func _glacier(root: Node3D) -> void:
	_mi(root, _plane(Vector2(160, 160), 40), Vector3(0, -1.0, 0), LA.water_mat(Color("031428"), Color("0d3a5e"), 0.04), Vector3.ZERO, Vector3.ONE, false)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var ice := LA.block_mat("iceberg", {"style": 4, "side": Color("a9d2f0"), "top": Color("f4fbff"), "rough": 0.18, "scale": 0.5})
	var placed: Array = [[Vector2(0, 0), 0.0]]
	for i in 3:
		var m := Art.rounded_box(Vector3(1.6, 1.4 + i * 0.6, 1.3), 0.3, 4, 0.22, 60 + i)
		m.surface_set_material(0, ice)
		_mm(root, m, _scatter(r, 6, 1.6, 11.0, 2.6, placed), r, -1.0, 0.7, 1.6)
	var floe := Art.rounded_box(Vector3(1.4, 0.18, 1.0), 0.08, 3, 0.05, 77)
	floe.surface_set_material(0, ice)
	_mm(root, floe, _scatter(r, 18, 0.9, 8.0, 1.1, placed), r, -0.96, 0.5, 1.4, false)
	# frosty spikes along the island edges
	var P := load("res://scripts/level_props.gd")
	var spike: Mesh = P.icespike_mesh()
	var xs: Array = []
	for rect in Levels.SHAPES["twin-islands"]["floors"]:
		for k in 10:
			var x := r.randf_range(rect[0] - 0.4, rect[2] + 0.4)
			var y: float = rect[1] - 0.62 if k % 2 == 0 else rect[3] + 0.62
			xs.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * r.randf_range(0.3, 0.55)), tile_pos(x, y) + Vector3(0, -0.5, 0)))
	root.add_child(Art.multimesh(spike, xs))


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


# ---- Haunted Train -----------------------------------------------------------------

const TRACK_SHADER := """
shader_type spatial;
uniform float speed = 2.6;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// The ground streams past under a train that never stops.
	float x = wpos.x + TIME * speed;
	vec2 p = vec2(x, wpos.z);
	float gravel = texture(noise_tex, p * 0.9).r;
	vec3 col = mix(vec3(0.05, 0.06, 0.07), vec3(0.14, 0.15, 0.16), gravel);
	float bed = 1.0 - smoothstep(3.6, 4.0, abs(wpos.z));
	float grass = texture(noise_tex, p * 0.15).r;
	col = mix(mix(vec3(0.03, 0.06, 0.05), vec3(0.06, 0.1, 0.07), grass), col, bed);
	float sleeper = step(0.62, fract(x * 1.2)) * (1.0 - smoothstep(3.0, 3.1, abs(wpos.z)));
	col = mix(col, vec3(0.12, 0.08, 0.06), sleeper);
	float rail = 0.0;
	for (int i = 0; i < 2; i++) {
		float rz = i == 0 ? -1.6 : 1.6;
		rail += 1.0 - smoothstep(0.05, 0.08, abs(abs(wpos.z) - abs(rz)) );
	}
	col = mix(col, vec3(0.55, 0.6, 0.65), clamp(rail, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.25, clamp(rail, 0.0, 1.0));
	METALLIC = clamp(rail, 0.0, 1.0) * 0.8;
}
"""


static func _train_base(root: Node3D) -> void:
	var body := LA.block_mat("train_body", {"style": 2, "side": Color("1d2832"), "top": Color("425464"), "rough": 0.5, "metal": 0.7})
	var red := LA.block_mat("train_trim", {"style": 2, "side": Color("5a1414"), "top": Color("8a2020"), "rough": 0.5, "metal": 0.5})
	var wheel := LA.build([[LA.cyl(0.3, 0.3, 0.12, 16), LA.xf(Vector3.ZERO, Vector3(PI / 2.0, 0, 0)), LA.metal(Color("2a2e33"))],
		[LA.cyl(0.12, 0.12, 0.16, 10), LA.xf(Vector3.ZERO, Vector3(PI / 2.0, 0, 0)), LA.metal(Color("8a1e1e"))]], LA.vmat("wheel", 0.5, 0.0, 0.2))
	var wheels: Array = []
	for rect in Levels.SHAPES["haunted-train"]["floors"]:
		var w: float = rect[2] - rect[0] + 1
		var h: float = rect[3] - rect[1] + 1
		var c := (tile_pos(rect[0], rect[1]) + tile_pos(rect[2], rect[3])) * 0.5
		var m := Art.rounded_box(Vector3(w + 0.2, 1.0, h + 0.2), 0.08, 3)
		m.surface_set_material(0, body)
		_mi(root, m, c + Vector3(0, -0.52, 0))
		var t := Art.rounded_box(Vector3(w + 0.26, 0.12, h + 0.26), 0.04, 2)
		t.surface_set_material(0, red)
		_mi(root, t, c + Vector3(0, -0.12, 0))
		# Bogies: wheels showing under each end of the carriage, either side of the rails
		for zs in [-1.0, 1.0]:
			for xo in [-0.6, 0.6]:
				wheels.append(Transform3D(Basis(), c + Vector3(xo * (w * 0.35), -1.05, zs * 1.6 + (0.35 if zs > 0 else -0.35))))
	root.add_child(Art.multimesh(wheel, wheels))
	# Gangways between carriages
	var gw: Array = []
	for p in Levels.SHAPES["haunted-train"]["paths"]:
		gw.append([LA.box(Vector3(1.02, 0.08, 1.0), 0.02), LA.xf(tile_pos(p[0], p[1]) + Vector3(0, -0.04, 0)), LA.metal(Color("3a4450"))])
		gw.append([LA.box(Vector3(1.0, 0.5, 1.0)), LA.xf(tile_pos(p[0], p[1]) + Vector3(0, -0.36, 0)), Color("15191e")])
	_mi(root, LA.build(gw, LA.vmat("gangway", 0.6, 0.0, 0.3)), Vector3.ZERO)


static func _train(root: Node3D) -> void:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TRACK_SHADER
	m.shader = sh
	m.set_shader_parameter("noise_tex", LA.noise_tex())
	_mi(root, _plane(Vector2(120, 80)), Vector3(0, -1.36, 0), m, Vector3.ZERO, Vector3.ONE, false)
	# Distant hills, a dark silhouette line behind the train
	var hills := Art.rounded_box(Vector3(70, 3.0, 4), 1.4, 8, 0.9, 3)
	hills.surface_set_material(0, Art.flat_mat(Color(0.02, 0.03, 0.05), 1.0))
	_mi(root, hills, Vector3(0, -0.6, -17.0), null, Vector3.ZERO, Vector3.ONE, false)


# ---- Factory -----------------------------------------------------------------------

static func _factory(root: Node3D) -> void:
	_ground(root, Color("26282c"), Color("3c3f45"), GROUND_Y, 0.8, "factory")
	var r := RandomNumberGenerator.new()
	r.seed = 17
	var placed: Array = []
	_mm(root, _cached("machine", _machine), _scatter(r, 8, 1.4, 6.0, 2.2, placed, true), r, GROUND_Y, 0.9, 1.15)
	var drum := LA.build([[LA.cyl(0.3, 0.3, 0.86, 14), LA.xf(Vector3(0, 0.43, 0)), Color("2f6fb0")],
		[LA.cyl(0.31, 0.31, 0.04, 14), LA.xf(Vector3(0, 0.3, 0)), LA.metal(Color("8a9099"))],
		[LA.cyl(0.31, 0.31, 0.04, 14), LA.xf(Vector3(0, 0.6, 0)), LA.metal(Color("8a9099"))]], LA.vmat("drum", 0.55, 0.0, 0.25))
	_mm(root, drum, _scatter(r, 16, 0.5, 5.0, 0.75, placed), r, GROUND_Y, 0.9, 1.05)
	var crates: Array = LA.crate_meshes("factory")
	_mm(root, crates[0], _scatter(r, 10, 0.6, 5.0, 1.1, placed), r, GROUND_Y, 0.9, 1.0)
	# Pipes running round the hall
	var pipe := LA.build([[LA.cyl(0.14, 0.14, 1.0, 12), LA.xf(Vector3.ZERO, Vector3(0, 0, PI / 2.0)), LA.metal(Color("7a828c"))],
		[LA.cyl(0.17, 0.17, 0.06, 12), LA.xf(Vector3(0.48, 0, 0), Vector3(0, 0, PI / 2.0)), LA.metal(Color("c9a020"))]], LA.vmat("pipe", 0.45, 0.0, 0.2))
	var px: Array = []
	for i in 30:
		var x := -15.0 + i
		px.append(Transform3D(Basis(), Vector3(x, GROUND_Y + 0.3, -Cfg.ROWS * 0.5 - 2.4)))
		px.append(Transform3D(Basis(), Vector3(x, GROUND_Y + 0.75, -Cfg.ROWS * 0.5 - 2.4)))
	root.add_child(Art.multimesh(pipe, px))
	# Painted safety lines round the plinth
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(1.0, 0.8, 0.05)
	line.roughness = 0.7
	for s in [-1.0, 1.0]:
		_mi(root, _plane(Vector2(Cfg.COLS + 2.2, 0.12)), Vector3(0, GROUND_Y + 0.005, s * (Cfg.ROWS * 0.5 + 1.0)), line, Vector3.ZERO, Vector3.ONE, false)
		_mi(root, _plane(Vector2(0.12, Cfg.ROWS + 2.1)), Vector3(s * (Cfg.COLS * 0.5 + 1.0), GROUND_Y + 0.005, 0), line, Vector3.ZERO, Vector3.ONE, false)


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


# ---- Circuit -----------------------------------------------------------------------

static func _circuit(root: Node3D) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_L8)
	img.fill(Color(1, 1, 1))
	var mask := ImageTexture.create_from_image(img)
	var m := LA.floor_mat("circuit", mask, 0.0)
	m.set_shader_parameter("col_a", Color("0c1a16"))
	m.set_shader_parameter("col_b", Color("11261f"))
	m.set_shader_parameter("line_col", Color("2fd6a0"))
	m.set_shader_parameter("line_alpha", 0.12)
	m.set_shader_parameter("grid", Vector2(4.0, 4.0))
	_mi(root, _plane(Vector2(90, 90)), Vector3(0, GROUND_Y, 0), m, Vector3.ZERO, Vector3.ONE, false)
	var r := RandomNumberGenerator.new()
	r.seed = 19
	var placed: Array = []
	_mm(root, _cached("chip", _chip), _scatter(r, 10, 1.3, 7.0, 2.4, placed), r, GROUND_Y, 0.8, 1.5)
	var cap := LA.build([[LA.cyl(0.18, 0.18, 0.6, 14), LA.xf(Vector3(0, 0.3, 0)), Color("2a3cff")],
		[LA.cyl(0.185, 0.185, 0.05, 14), LA.xf(Vector3(0, 0.6, 0)), LA.metal(Color("c8ccd4"))],
		[LA.box(Vector3(0.06, 0.62, 0.05)), LA.xf(Vector3(0.15, 0.3, 0.1)), Color("dfe6ff")]], LA.vmat("capacitor", 0.4, 0.0, 0.15))
	_mm(root, cap, _scatter(r, 14, 0.5, 6.0, 0.7, placed), r, GROUND_Y, 0.8, 1.3)
	var led := LA.build([[LA.cyl(0.06, 0.06, 0.12, 10), LA.xf(Vector3(0, 0.08, 0)), LA.lit(Color("ff3fa4"))],
		[LA.sphere(0.06, 10, 6), LA.xf(Vector3(0, 0.14, 0)), LA.lit(Color("ff6ec0"))]], LA.vmat("led", 0.3, 0.0, 0.0, 3.0))
	_mm(root, led, _scatter(r, 20, 0.3, 5.0, 0.45, placed), r, GROUND_Y, 0.8, 1.3, false)


static func _chip() -> Mesh:
	var parts: Array = [[LA.box(Vector3(1.6, 0.22, 1.2), 0.03), LA.xf(Vector3(0, 0.13, 0)), Color("15161c")],
		[LA.box(Vector3(0.5, 0.01, 0.2)), LA.xf(Vector3(-0.4, 0.245, -0.35)), Color("c8ccd4")]]
	for k in 8:
		for s in [-1.0, 1.0]:
			parts.append([LA.box(Vector3(0.07, 0.04, 0.22)), LA.xf(Vector3(-0.7 + k * 0.2, 0.05, s * 0.68)), LA.metal(Color("d0d4dc"))])
	parts.append([LA.sphere(0.04, 8, 4), LA.xf(Vector3(0.62, 0.24, 0.4)), LA.lit(Color("6ef0ff"))])
	return LA.build(parts, LA.vmat("chip", 0.35, 0.0, 0.2))


# ---- Pirate Fleet ------------------------------------------------------------------

static func _pirate_base(root: Node3D) -> void:
	var hull := LA.block_mat("hull", {"style": 6, "side": Color("4a2412"), "top": Color("6b3a1c"), "rough": 0.75})
	var trim := LA.block_mat("hull_trim", {"style": 6, "side": Color("c8a050"), "top": Color("e0c070"), "rough": 0.5, "metal": 0.4})
	var rails: Array = []
	for rect in Levels.SHAPES["pirate-fleet"]["floors"]:
		var w: float = rect[2] - rect[0] + 1
		var h: float = rect[3] - rect[1] + 1
		var c := (tile_pos(rect[0], rect[1]) + tile_pos(rect[2], rect[3])) * 0.5
		var m := Art.rounded_box(Vector3(w + 0.4, 1.8, h + 0.4), 0.3, 6)
		_taper_hull(m)
		m.surface_set_material(0, hull)
		_mi(root, m, c + Vector3(0, -0.91, 0))
		var bow := Art.rounded_box(Vector3(w * 0.7, 1.4, 2.0), 0.3, 5)
		bow.surface_set_material(0, hull)
		_mi(root, bow, c + Vector3(0, -0.85, -h * 0.5 - 0.6), null, Vector3(0, PI / 4.0, 0), Vector3(1.0, 1.0, 0.75))
		var band := Art.rounded_box(Vector3(w + 0.46, 0.1, h + 0.46), 0.05, 2)
		band.surface_set_material(0, trim)
		_mi(root, band, c + Vector3(0, -0.1, 0))
		# Gunwale rails along the long sides, open where the gangplanks meet
		for x in range(rect[0], rect[2] + 1):
			for side in [rect[1] - 0.55, rect[3] + 0.55]:
				rails.append(Transform3D(Basis(), tile_pos(x, side)))
		for y in range(rect[1], rect[3] + 1):
			for xs in [rect[0] - 0.55, rect[2] + 0.55]:
				var open := false
				for p in Levels.SHAPES["pirate-fleet"]["paths"]:
					if p[1] == y and absf(p[0] - xs) < 1.0:
						open = true
				if not open:
					rails.append(Transform3D(Basis(Vector3.UP, PI / 2.0), tile_pos(xs, y)))
	var rail := LA.build([[LA.box(Vector3(1.0, 0.07, 0.1), 0.02), LA.xf(Vector3(0, 0.36, 0)), Color("6b3a1c")],
		[LA.cyl(0.035, 0.04, 0.36, 6), LA.xf(Vector3(-0.25, 0.18, 0)), Color("8a5226")],
		[LA.cyl(0.035, 0.04, 0.36, 6), LA.xf(Vector3(0.25, 0.18, 0)), Color("8a5226")]], LA.vmat("rail", 0.75, 0.0, 0.3))
	root.add_child(Art.multimesh(rail, rails))
	var planks: Array = []
	for p in Levels.SHAPES["pirate-fleet"]["paths"]:
		if p[0] != 7:
			continue
		var pos := tile_pos(p[0], p[1])
		planks.append([LA.box(Vector3(3.1, 0.08, 0.9), 0.02), LA.xf(pos + Vector3(0, -0.05, 0)), Color("9a6a3a")])
		for k in 6:
			planks.append([LA.box(Vector3(0.05, 0.09, 0.92)), LA.xf(pos + Vector3(-1.25 + k * 0.5, -0.045, 0)), Color("5a3a1a")])
	_mi(root, LA.build(planks, LA.vmat("gangplank", 0.8, 0.0, 0.35)), Vector3.ZERO)


## Pull the bottom of a hull box in so it reads as a boat, not a crate.
static func _taper_hull(m: ArrayMesh) -> void:
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		if v.y < 0.0:
			var t := clampf(-v.y / 0.9, 0.0, 1.0)
			v.x *= 1.0 - 0.35 * t
			v.z *= 1.0 - 0.08 * t
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	m.clear_surfaces()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


static func _pirate(root: Node3D) -> void:
	_mi(root, _plane(Vector2(160, 160), 48), Vector3(0, -1.05, 0), LA.water_mat(Color("03223f"), Color("0e5a7a"), 0.09), Vector3.ZERO, Vector3.ONE, false)
	var r := RandomNumberGenerator.new()
	r.seed = 23
	# A small island with palms off to one side, rocks in the swell
	var sand := LA.block_mat("sand", {"style": 0, "side": Color("b8955c"), "top": Color("cfb07a"), "rough": 0.95, "scale": 0.5})
	var isl := Art.rounded_box(Vector3(7, 1.2, 5), 0.5, 5, 0.3, 9)
	isl.surface_set_material(0, sand)
	_mi(root, isl, Vector3(-13.5, -1.2, -9.0))
	var palm: Mesh = _cached("palm", _palm_mesh)
	for k in 3:
		_mi(root, palm, Vector3(-14.5 + k * 1.3, -0.65, -9.5 + (k % 2) * 0.9), null, Vector3(0, k * 2.0, 0), Vector3.ONE * (0.9 + k * 0.1))
	var rock := Art.rounded_box(Vector3(1.0, 0.9, 0.8), 0.3, 4, 0.15, 41)
	rock.surface_set_material(0, Art.stone_mat("searock", Color(0.5, 0.52, 0.55), 0.1))
	var placed: Array = [[Vector2(-13.5, -9.0), 4.5]]
	_mm(root, rock, _scatter(r, 10, 1.5, 10.0, 2.0, placed), r, -1.2, 0.6, 1.4)
