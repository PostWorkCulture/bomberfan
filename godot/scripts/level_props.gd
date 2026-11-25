extends RefCounted
## Set dressing on the walls (props) and the bomb-throwing hazards. Each
## model faces +Z (towards the camera when unrotated) and stands on y = 0.
## Ported from the browser's Props module: same kinds, same placement.

const LA := preload("res://scripts/level_art.gd")

static var _cache := {}

const RED := Color("e0201a")


static func _m(key: String, fn: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = fn.call()
	return _cache[key]


static func _node(mesh: Mesh, kind: String) -> Node3D:
	var n := Node3D.new()
	n.set_meta("kind", kind)
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = mesh
	n.add_child(mi)
	return n


## A prop by name. `angry` marks the level's hazard: it gets a scowl and a red
## bomb to hold up before each throw.
static func make(kind: String, angry := false) -> Node3D:
	var n: Node3D
	match kind:
		"beachball":
			n = _node(_m("beachball", _beachball), kind)
		"parasol":
			n = _node(_m("parasol", _parasol), kind)
		"snowman":
			n = _node(_m("snowman_angry" if angry else "snowman", func(): return _snowman(angry)), kind)
		"icespike":
			n = _node(icespike_mesh(), kind)
		"gravestone":
			n = _node(gravestone_mesh(), kind)
		"pumpkin":
			n = _node(_m("pumpkin", _pumpkin), kind)
		"ghost":
			n = _node(_m("ghost", _ghost), kind)
			(n.get_node("Model") as MeshInstance3D).transparency = 0.28
		"witch":
			n = _node(_m("witch_angry" if angry else "witch", func(): return _witch(angry)), kind)
		"conductor":
			n = _node(_m("conductor", _conductor), kind)
		"luggage":
			n = _node(_m("luggage", _luggage), kind)
		"spectralengine":
			n = _node(_m("spectralengine", _engine), kind)
		"lantern":
			n = _node(_m("lantern", _lantern), kind)
		"pylon":
			n = _node(_m("pylon", _pylon), kind)
		"server":
			n = _node(_m("server", _server), kind)
		"cannon":
			n = _node(_m("cannon_angry" if angry else "cannon", func(): return _cannon(angry)), kind)
		"mast":
			n = _node(_m("mast", _mast), kind)
		"pirate":
			n = _node(_m("pirate", _pirate), kind)
		"barrels":
			n = _node(_m("barrels", _barrels), kind)
		"treasure":
			n = _node(_m("treasure", _treasure), kind)
		_:
			n = Node3D.new()
	if angry:
		var held := MeshInstance3D.new()
		held.name = "HeldBomb"
		held.mesh = _m("held_bomb", _held_bomb)
		held.visible = false
		held.position = throw_offset(kind)
		n.add_child(held)
	n.set_meta("phase", randf() * TAU)
	return n


## Where the thrower holds its bomb up, in its own space.
static func throw_offset(kind: String) -> Vector3:
	match kind:
		"snowman":
			return Vector3(0.0, 1.55, 0.05)
		"witch":
			return Vector3(0.28, 1.55, 0.12)
		"cannon":
			return Vector3(0.0, 0.42, 0.55)
	return Vector3(0, 1.4, 0)


## Idle motion for the props that move: ghosts drift, the witch rocks,
## pumpkins flicker, the engine's lamps pulse.
static func animate(n: Node3D, t: float) -> void:
	var kind: String = n.get_meta("kind", "")
	var ph: float = n.get_meta("phase", 0.0)
	var model := n.get_node_or_null("Model") as Node3D
	if model == null:
		return
	match kind:
		"ghost":
			model.position.y = 0.16 + sin(t * 1.15 + ph) * 0.13
			model.position.x = sin(t * 0.47 + ph * 1.7) * 0.18
			model.rotation.y = sin(t * 0.63 + ph) * 0.45
		"witch":
			model.position.y = 0.06 + sin(t * 0.9 + ph) * 0.05
			model.rotation.z = sin(t * 0.72 + ph) * 0.07
		"beachball":
			model.rotation.y = t * 0.4 + ph
		"pylon":
			model.rotation.y = sin(t * 0.5 + ph) * 0.15
		"lantern":
			model.rotation.z = sin(t * 1.6 + ph) * 0.08


## The hazard's wind-up: k runs 0..1 over HAZARD_WINDUP, then -1 to hide.
static func wind_up(n: Node3D, k: float) -> void:
	var held := n.get_node_or_null("HeldBomb") as Node3D
	if held == null:
		return
	if k < 0.0:
		held.visible = false
		var mdl := n.get_node_or_null("Model") as Node3D
		if mdl:
			mdl.position.z = 0.0
		return
	held.visible = true
	var kind: String = n.get_meta("kind", "")
	var base := throw_offset(kind)
	var shake := sin(k * 60.0) * 0.03 * k
	if kind == "cannon":
		# the barrel recoils back as it builds pressure
		var mdl := n.get_node_or_null("Model") as Node3D
		if mdl:
			mdl.position.z = -0.08 * k
		held.position = base + Vector3(shake, 0, 0)
		held.scale = Vector3.ONE * (0.3 + 0.7 * minf(1.0, k * 2.0))
	else:
		held.position = base + Vector3(shake, 0.15 * k, 0)
		held.scale = Vector3.ONE * (0.6 + 0.4 * minf(1.0, k * 3.0))


static func _held_bomb() -> Mesh:
	return LA.build([
		[LA.sphere(0.2, 16, 10), LA.xf(Vector3.ZERO), RED],
		[LA.cyl(0.06, 0.07, 0.07, 10), LA.xf(Vector3(0, 0.2, 0)), LA.metal(Color("3a3a3a"))],
		[LA.sphere(0.035, 8, 4), LA.xf(Vector3(0.03, 0.27, 0)), LA.lit(Color("ffb050"))],
	], LA.vmat("held_bomb", 0.35, 0.0, 0.1, 3.0))


static func _scowl(parts: Array, y: float, z: float, w := 0.12) -> void:
	for s in [-1.0, 1.0]:
		parts.append([LA.box(Vector3(w, 0.03, 0.03)), LA.xf(Vector3(s * w * 0.75, y, z), Vector3(0, 0, s * 0.45)), Color("120808")])


# ---- Beach -----------------------------------------------------------------------------

static func _beachball() -> Mesh:
	var cols := [Color("ff4d4d"), Color("ffffff"), Color("2f80ed"), Color("ffffff"), Color("ffd23f"), Color("ffffff")]
	var r := 0.3
	# Six coloured gores with white poles, coloured per vertex by angle.
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 36
	s.rings = 18
	var arr := s.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c := PackedColorArray()
	c.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var seg := int(floor((atan2(v.z, v.x) + PI) / TAU * 6.0)) % 6
		c[i] = Color.WHITE if absf(v.y) > r * 0.9 else cols[seg]
		verts[i].y += r
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, LA.vmat("beachball", 0.3, 0.0, 0.05))
	return m


static func _parasol() -> Mesh:
	var parts: Array = [[LA.cyl(0.025, 0.03, 1.6, 8), LA.xf(Vector3(0, 0.8, 0)), Color("f2efe6")]]
	var cols := [Color("ff5a5f"), Color("fff4e0")]
	for i in 8:
		var a := TAU * i / 8.0
		parts.append([LA.box(Vector3(0.5, 0.02, 0.36)), Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -0.32), Vector3(cos(a), 0, sin(a)) * 0.36 + Vector3(0, 1.52, 0)), cols[i % 2]])
	parts.append([LA.sphere(0.05, 8, 4), LA.xf(Vector3(0, 1.66, 0)), Color("ff5a5f")])
	return LA.build(parts, LA.vmat("parasol", 0.8, 0.0, 0.2))


# ---- Glacier ---------------------------------------------------------------------------

static func _snowman(angry: bool) -> Mesh:
	var snow := Color("f4f8ff")
	var parts: Array = [
		[LA.sphere(0.36, 18, 10), LA.xf(Vector3(0, 0.34, 0), Vector3.ZERO, Vector3(1, 0.92, 1)), snow],
		[LA.sphere(0.27, 16, 9), LA.xf(Vector3(0, 0.84, 0)), snow],
		[LA.sphere(0.2, 16, 9), LA.xf(Vector3(0, 1.22, 0)), snow],
		[LA.cone(0.045, 0.24, 8), LA.xf(Vector3(0, 1.22, 0.3), Vector3(PI / 2.0, 0, 0)), Color("ff7a1a")],
		[LA.cyl(0.18, 0.18, 0.04, 14), LA.xf(Vector3(0, 1.38, 0)), Color("1a1c22")],
		[LA.cyl(0.12, 0.13, 0.2, 14), LA.xf(Vector3(0, 1.48, 0)), Color("1a1c22")],
		[LA.cyl(0.21, 0.21, 0.07, 14), LA.xf(Vector3(0, 1.03, 0)), Color("c83a3a")],
		[LA.box(Vector3(0.09, 0.3, 0.05)), LA.xf(Vector3(0.12, 0.88, 0.2), Vector3(0.2, 0, 0.1)), Color("c83a3a")],
	]
	for s in [-1.0, 1.0]:
		parts.append([LA.sphere(0.028, 8, 4), LA.xf(Vector3(s * 0.07, 1.28, 0.17)), Color("101014")])
		parts.append([LA.cyl(0.015, 0.02, 0.42, 5), LA.xf(Vector3(s * 0.36, 0.95, 0.0), Vector3(0, 0, -s * 1.0)), Color("5a3a20")])
	for k in 3:
		parts.append([LA.sphere(0.025, 8, 4), LA.xf(Vector3(0, 0.75 + k * 0.1, 0.26 - k * 0.01)), Color("101014")])
	if angry:
		_scowl(parts, 1.34, 0.17, 0.08)
	return LA.build(parts, LA.vmat("snowman", 0.75, 0.0, 0.15))


static func icespike_mesh() -> Mesh:
	if _cache.has("icespike"):
		return _cache["icespike"]
	var r := RandomNumberGenerator.new()
	r.seed = 61
	var parts: Array = []
	for k in 5:
		var h := r.randf_range(0.5, 1.1) * (1.4 if k == 0 else 1.0)
		var a := r.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else 0.18)
		parts.append([LA.cone(0.14 if k == 0 else 0.09, h, 6), LA.xf(off + Vector3(0, h * 0.5, 0), Vector3(off.z * 1.2, 0, -off.x * 1.2)), Color("bfe6ff").lerp(Color("6fb6ea"), r.randf())])
	var m := LA.build(parts, LA.vmat("icespike", 0.1, 0.0, 0.1))
	_cache["icespike"] = m
	return m


# ---- Haunted House ---------------------------------------------------------------------

static func gravestone_mesh() -> Mesh:
	if _cache.has("gravestone"):
		return _cache["gravestone"]
	var stone := Color("6e6a72")
	var parts: Array = [
		[LA.box(Vector3(0.46, 0.55, 0.14), 0.03), LA.xf(Vector3(0, 0.3, 0), Vector3(0.06, 0, 0.04)), stone],
		[LA.cyl(0.23, 0.23, 0.14, 14), LA.xf(Vector3(0, 0.58, 0.012), Vector3(PI / 2.0, 0, 0.04)), stone],
		[LA.box(Vector3(0.58, 0.08, 0.26), 0.02), LA.xf(Vector3(0, 0.04, 0)), stone.darkened(0.25)],
		[LA.box(Vector3(0.05, 0.22, 0.02)), LA.xf(Vector3(0, 0.48, 0.08)), stone.darkened(0.45)],
		[LA.box(Vector3(0.16, 0.05, 0.02)), LA.xf(Vector3(0, 0.52, 0.08)), stone.darkened(0.45)],
		[LA.sphere(0.12, 8, 5), LA.xf(Vector3(0.18, 0.05, 0.1), Vector3.ZERO, Vector3(1, 0.4, 1)), Color("3a4a2a")],
	]
	var m := LA.build(parts, LA.vmat("gravestone", 0.95, 0.0, 0.4))
	_cache["gravestone"] = m
	return m


static func _pumpkin() -> Mesh:
	var orange := Color("e8761a")
	var parts: Array = []
	for i in 8:
		var a := TAU * i / 8.0
		parts.append([LA.sphere(0.2, 14, 8), LA.xf(Vector3(cos(a), 0, sin(a)) * 0.13 + Vector3(0, 0.22, 0), Vector3.ZERO, Vector3(0.75, 0.85, 0.75)), orange.lerp(Color("c85a10"), (i % 2) * 0.4)])
	parts.append([LA.cyl(0.03, 0.05, 0.14, 6), LA.xf(Vector3(0.02, 0.45, 0), Vector3(0, 0, -0.3)), Color("4a5a20")])
	var glow := LA.lit(Color("ffb830"))
	for s in [-1.0, 1.0]:
		parts.append([LA.cone(0.06, 0.08, 3), LA.xf(Vector3(s * 0.09, 0.28, 0.27), Vector3(PI / 2.0, 0, 0)), glow])
	parts.append([LA.box(Vector3(0.22, 0.05, 0.04)), LA.xf(Vector3(0, 0.15, 0.28)), glow])
	for k in 3:
		parts.append([LA.box(Vector3(0.04, 0.05, 0.04)), LA.xf(Vector3(-0.08 + k * 0.08, 0.18, 0.285)), glow])
	return LA.build(parts, LA.vmat("pumpkin", 0.6, 0.0, 0.25, 4.0))


static func _ghost() -> Mesh:
	var white := Color("e8ecff")
	var parts: Array = [
		[LA.sphere(0.26, 16, 10), LA.xf(Vector3(0, 0.75, 0)), white],
		[LA.cyl(0.26, 0.33, 0.5, 16), LA.xf(Vector3(0, 0.5, 0)), white],
	]
	for i in 6:
		var a := TAU * i / 6.0
		parts.append([LA.cone(0.1, 0.18, 6), LA.xf(Vector3(cos(a), 0, sin(a)) * 0.24 + Vector3(0, 0.2, 0), Vector3(PI, 0, 0)), white])
	for s in [-1.0, 1.0]:
		parts.append([LA.sphere(0.05, 8, 5), LA.xf(Vector3(s * 0.09, 0.8, 0.23), Vector3.ZERO, Vector3(0.8, 1.3, 0.5)), Color("15121e")])
		parts.append([LA.sphere(0.08, 8, 5), LA.xf(Vector3(s * 0.3, 0.55, 0.05), Vector3.ZERO, Vector3(0.6, 1.0, 0.6)), white])
	parts.append([LA.sphere(0.05, 8, 5), LA.xf(Vector3(0, 0.66, 0.24), Vector3.ZERO, Vector3(0.8, 1.2, 0.4)), Color("15121e")])
	return LA.build(parts, LA.vmat("ghost", 0.4, 0.0, 0.05, 0.6))


static func _witch(angry: bool) -> Mesh:
	var robe := Color("2a1a3a")
	var skin := Color("7fbf5a")
	var parts: Array = [
		[LA.cyl(0.12, 0.3, 0.8, 14), LA.xf(Vector3(0, 0.4, 0)), robe],
		[LA.sphere(0.17, 14, 8), LA.xf(Vector3(0, 0.95, 0)), skin],
		[LA.cone(0.05, 0.14, 6), LA.xf(Vector3(0, 0.93, 0.2), Vector3(PI / 2.0 - 0.3, 0, 0)), skin],
		[LA.cyl(0.32, 0.32, 0.03, 18), LA.xf(Vector3(0, 1.08, 0), Vector3(0.12, 0, 0)), Color("1a1022")],
		[LA.cone(0.16, 0.55, 12), LA.xf(Vector3(0, 1.36, -0.03), Vector3(-0.25, 0, 0.1)), Color("1a1022")],
		[LA.cyl(0.165, 0.165, 0.05, 12), LA.xf(Vector3(0, 1.12, 0)), Color("7a37d6")],
		[LA.cyl(0.015, 0.02, 1.2, 6), LA.xf(Vector3(-0.3, 0.6, 0.15), Vector3(0, 0, 0.35)), Color("6a4a2a")],
		[LA.cone(0.1, 0.3, 8), LA.xf(Vector3(-0.5, 0.08, 0.15), Vector3(0, 0, 0.35 + PI)), Color("c8a060")],
	]
	for s in [-1.0, 1.0]:
		parts.append([LA.sphere(0.03, 8, 4), LA.xf(Vector3(s * 0.06, 0.99, 0.15)), LA.lit(Color("ffe040"))])
		parts.append([LA.cyl(0.04, 0.06, 0.35, 8), LA.xf(Vector3(s * 0.2, 0.68, 0.06), Vector3(0.4, 0, s * 0.6)), robe])
	if angry:
		_scowl(parts, 1.04, 0.15, 0.06)
	return LA.build(parts, LA.vmat("witch", 0.75, 0.0, 0.2, 4.0))


# ---- Haunted Train ---------------------------------------------------------------------

static func _conductor() -> Mesh:
	var coat := Color("1f2a3a")
	var spirit := Color("9fe8ff")
	var parts: Array = [
		[LA.cyl(0.14, 0.24, 0.7, 12), LA.xf(Vector3(0, 0.38, 0)), coat],
		[LA.sphere(0.16, 14, 8), LA.xf(Vector3(0, 0.88, 0)), LA.lit(spirit)],
		[LA.cyl(0.18, 0.18, 0.03, 14), LA.xf(Vector3(0, 1.0, 0.02)), Color("10141c")],
		[LA.cyl(0.15, 0.16, 0.14, 14), LA.xf(Vector3(0, 1.08, 0)), Color("10141c")],
		[LA.box(Vector3(0.1, 0.05, 0.02)), LA.xf(Vector3(0, 1.08, 0.16)), LA.metal(Color("d8b25a"))],
		[LA.cyl(0.03, 0.03, 0.08, 8), LA.xf(Vector3(0.12, 0.45, 0.18), Vector3(PI / 2.0, 0, 0)), LA.metal(Color("d8b25a"))],
	]
	for k in 3:
		parts.append([LA.sphere(0.02, 6, 4), LA.xf(Vector3(0, 0.55 + k * 0.1, 0.19)), LA.metal(Color("d8b25a"))])
	for s in [-1.0, 1.0]:
		parts.append([LA.sphere(0.03, 6, 4), LA.xf(Vector3(s * 0.06, 0.9, 0.14)), Color("0a0e18")])
	return LA.build(parts, LA.vmat("conductor", 0.7, 0.0, 0.2, 1.6))


static func _luggage() -> Mesh:
	var parts: Array = [
		[LA.box(Vector3(0.6, 0.32, 0.4), 0.04), LA.xf(Vector3(0, 0.16, 0)), Color("5a3a28")],
		[LA.box(Vector3(0.46, 0.26, 0.34), 0.04), LA.xf(Vector3(0.05, 0.45, 0), Vector3(0, 0.25, 0)), Color("2f4a5a")],
		[LA.box(Vector3(0.62, 0.04, 0.42)), LA.xf(Vector3(0, 0.22, 0)), LA.metal(Color("8a6a40"))],
		[LA.cyl(0.02, 0.02, 0.14, 6), LA.xf(Vector3(0.05, 0.62, 0), Vector3(0, 0.25, PI / 2.0)), Color("1a1410")],
	]
	return LA.build(parts, LA.vmat("luggage", 0.7, 0.0, 0.3))


static func _engine() -> Mesh:
	var iron := Color("1a2028")
	var parts: Array = [
		[LA.cyl(0.24, 0.24, 0.8, 16), LA.xf(Vector3(0, 0.36, 0), Vector3(PI / 2.0, 0, 0)), iron],
		[LA.box(Vector3(0.56, 0.12, 0.9), 0.03), LA.xf(Vector3(0, 0.06, 0)), Color("5a1414")],
		[LA.cyl(0.08, 0.12, 0.34, 10), LA.xf(Vector3(0, 0.72, 0.2)), iron],
		[LA.cyl(0.12, 0.08, 0.06, 10), LA.xf(Vector3(0, 0.9, 0.2)), iron],
		[LA.box(Vector3(0.5, 0.5, 0.3), 0.03), LA.xf(Vector3(0, 0.45, -0.32)), iron.lightened(0.1)],
		[LA.cyl(0.1, 0.1, 0.04, 12), LA.xf(Vector3(0, 0.38, 0.42), Vector3(PI / 2.0, 0, 0)), LA.lit(Color("9fe8ff"))],
		[LA.box(Vector3(0.16, 0.12, 0.02)), LA.xf(Vector3(0, 0.55, -0.16)), LA.lit(Color("ffd890"))],
	]
	for s in [-1.0, 1.0]:
		for z in [-0.25, 0.25]:
			parts.append([LA.cyl(0.1, 0.1, 0.05, 12), LA.xf(Vector3(s * 0.27, 0.12, z), Vector3(0, 0, PI / 2.0)), LA.metal(Color("8a1e1e"))])
	return LA.build(parts, LA.vmat("engine", 0.5, 0.4, 0.2, 3.0))


static func _lantern() -> Mesh:
	var parts: Array = [
		[LA.cyl(0.02, 0.025, 0.7, 6), LA.xf(Vector3(0, 0.35, 0)), LA.metal(Color("22262c"))],
		[LA.box(Vector3(0.16, 0.2, 0.16), 0.02), LA.xf(Vector3(0, 0.82, 0)), LA.lit(Color("ff4a3a"))],
		[LA.cone(0.13, 0.1, 4), LA.xf(Vector3(0, 0.97, 0), Vector3(0, PI / 4.0, 0)), LA.metal(Color("22262c"))],
		[LA.box(Vector3(0.18, 0.03, 0.18)), LA.xf(Vector3(0, 0.71, 0)), LA.metal(Color("22262c"))],
	]
	return LA.build(parts, LA.vmat("lantern", 0.5, 0.0, 0.1, 4.0))


# ---- Factory / Circuit ---------------------------------------------------------------

static func _pylon() -> Mesh:
	var parts: Array = [
		[LA.cyl(0.08, 0.14, 0.9, 6), LA.xf(Vector3(0, 0.45, 0)), LA.metal(Color("4a5260"))],
		[LA.cyl(0.18, 0.2, 0.08, 8), LA.xf(Vector3(0, 0.04, 0)), Color("2a2f38")],
		[LA.sphere(0.1, 12, 6), LA.xf(Vector3(0, 0.98, 0)), LA.lit(Color("6ef0ff"))],
	]
	for k in 3:
		parts.append([LA.cyl(0.13 - k * 0.02, 0.13 - k * 0.02, 0.03, 10), LA.xf(Vector3(0, 0.35 + k * 0.2, 0)), LA.lit(Color("ffcc1a"))])
	return LA.build(parts, LA.vmat("pylon", 0.4, 0.0, 0.15, 3.0))


static func _server() -> Mesh:
	var parts: Array = [[LA.box(Vector3(0.5, 0.95, 0.42), 0.03), LA.xf(Vector3(0, 0.48, 0)), Color("1a1d24")]]
	for k in 6:
		parts.append([LA.box(Vector3(0.42, 0.1, 0.02)), LA.xf(Vector3(0, 0.15 + k * 0.13, 0.215)), Color("2a2f38")])
		parts.append([LA.box(Vector3(0.04, 0.025, 0.02)), LA.xf(Vector3(-0.15, 0.15 + k * 0.13, 0.23)), LA.lit(Color("3df2a0") if k % 2 == 0 else Color("6ef0ff"))])
		parts.append([LA.box(Vector3(0.04, 0.025, 0.02)), LA.xf(Vector3(-0.08, 0.15 + k * 0.13, 0.23)), LA.lit(Color("ffb020"))])
	return LA.build(parts, LA.vmat("server", 0.45, 0.2, 0.15, 3.0))


# ---- Pirate Fleet ------------------------------------------------------------------------

static func _cannon(angry: bool) -> Mesh:
	var iron := LA.metal(Color("22252a"))
	var wood := Color("6b3a1c")
	var parts: Array = [
		[LA.box(Vector3(0.44, 0.16, 0.6), 0.03), LA.xf(Vector3(0, 0.14, -0.05)), wood],
		[LA.cyl(0.13, 0.17, 0.72, 14), LA.xf(Vector3(0, 0.34, 0.12), Vector3(PI / 2.0 - 0.12, 0, 0)), RED if angry else Color("2a2d33")],
		[LA.cyl(0.15, 0.15, 0.06, 14), LA.xf(Vector3(0, 0.38, 0.47), Vector3(PI / 2.0 - 0.12, 0, 0)), iron],
		[LA.cyl(0.09, 0.09, 0.02, 10), LA.xf(Vector3(0, 0.39, 0.5), Vector3(PI / 2.0 - 0.12, 0, 0)), Color("050505")],
		[LA.sphere(0.12, 10, 6), LA.xf(Vector3(0, 0.3, -0.25)), iron],
	]
	for s in [-1.0, 1.0]:
		for z in [-0.22, 0.18]:
			parts.append([LA.cyl(0.1, 0.1, 0.05, 12), LA.xf(Vector3(s * 0.24, 0.1, z), Vector3(0, 0, PI / 2.0)), Color("4a2412")])
	return LA.build(parts, LA.vmat("cannon", 0.6, 0.0, 0.25))


static func _mast() -> Mesh:
	var wood := Color("7a4a24")
	var sail := Color("f2ead6")
	var parts: Array = [
		[LA.cyl(0.06, 0.08, 3.0, 10), LA.xf(Vector3(0, 1.5, 0)), wood],
		[LA.cyl(0.035, 0.035, 1.5, 8), LA.xf(Vector3(0, 2.5, 0.05), Vector3(0, 0, PI / 2.0)), wood],
		[LA.cyl(0.03, 0.03, 1.2, 8), LA.xf(Vector3(0, 1.4, 0.05), Vector3(0, 0, PI / 2.0)), wood],
		[LA.box(Vector3(1.4, 1.05, 0.03)), LA.xf(Vector3(0, 1.95, 0.12), Vector3(0.12, 0, 0)), sail],
		[LA.cyl(0.12, 0.1, 0.12, 10), LA.xf(Vector3(0, 2.95, 0)), wood],
		[LA.box(Vector3(0.4, 0.26, 0.01)), LA.xf(Vector3(0.22, 3.15, 0)), Color("111114")],
		[LA.sphere(0.05, 8, 4), LA.xf(Vector3(0.22, 3.17, 0.01), Vector3.ZERO, Vector3(1, 1, 0.3)), Color("f2f2f2")],
	]
	return LA.build(parts, LA.vmat("mast", 0.8, 0.0, 0.3))


static func _pirate() -> Mesh:
	var parts: Array = [
		[LA.cyl(0.14, 0.2, 0.55, 12), LA.xf(Vector3(0, 0.38, 0)), Color("c83a2a")],
		[LA.cyl(0.15, 0.15, 0.08, 12), LA.xf(Vector3(0, 0.6, 0)), Color("f2ead6")],
		[LA.sphere(0.15, 12, 8), LA.xf(Vector3(0, 0.78, 0)), Color("e8b08a")],
		[LA.sphere(0.155, 12, 8), LA.xf(Vector3(0, 0.83, -0.01), Vector3.ZERO, Vector3(1.05, 0.6, 1.05)), Color("b83030")],
		[LA.box(Vector3(0.36, 0.06, 0.1), 0.02), LA.xf(Vector3(0, 0.95, 0)), Color("15151a")],
		[LA.sphere(0.035, 8, 4), LA.xf(Vector3(-0.06, 0.8, 0.13)), Color("101014")],
		[LA.box(Vector3(0.07, 0.06, 0.02)), LA.xf(Vector3(0.06, 0.8, 0.14)), Color("101014")],
		[LA.box(Vector3(0.24, 0.02, 0.02)), LA.xf(Vector3(0.02, 0.83, 0.13), Vector3(0, 0, -0.35)), Color("101014")],
		[LA.cyl(0.05, 0.06, 0.2, 8), LA.xf(Vector3(-0.06, 0.08, 0)), Color("4a2412")],
		[LA.cyl(0.02, 0.02, 0.24, 6), LA.xf(Vector3(0.06, 0.1, 0)), Color("8a6a44")],
		[LA.box(Vector3(0.03, 0.4, 0.03)), LA.xf(Vector3(0.24, 0.6, 0.12), Vector3(0.3, 0, -0.3)), LA.metal(Color("c8ccd4"))],
	]
	return LA.build(parts, LA.vmat("pirate", 0.75, 0.0, 0.2))


static func _barrels() -> Mesh:
	var b: Mesh = LA.barrel()
	var parts: Array = [
		[b, LA.xf(Vector3(-0.15, 0, -0.1), Vector3.ZERO, Vector3.ONE * 0.6), null],
		[b, LA.xf(Vector3(0.2, 0, 0.1), Vector3(0, 1.0, 0), Vector3.ONE * 0.55), null],
		[b, LA.xf(Vector3(0.0, 0.47, 0.0), Vector3(0, 0.5, PI / 2.0), Vector3.ONE * 0.5), null],
	]
	return LA.build(parts, LA.vmat("barrels", 0.8, 0.0, 0.35))


static func _treasure() -> Mesh:
	var gold := LA.metal(Color("f2c240"))
	var parts: Array = [
		[LA.box(Vector3(0.6, 0.34, 0.4), 0.03), LA.xf(Vector3(0, 0.17, 0)), Color("6b3a1c")],
		[LA.cyl(0.2, 0.2, 0.6, 14), LA.xf(Vector3(0, 0.42, -0.12), Vector3(-0.9, 0, PI / 2.0), Vector3(1, 1, 1)), Color("7a4424")],
		[LA.box(Vector3(0.56, 0.1, 0.36)), LA.xf(Vector3(0, 0.36, 0)), gold],
		[LA.box(Vector3(0.62, 0.04, 0.42)), LA.xf(Vector3(0, 0.2, 0)), gold],
	]
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for k in 9:
		parts.append([LA.cyl(0.05, 0.05, 0.015, 10), LA.xf(Vector3(r.randf_range(-0.22, 0.22), 0.42 + r.randf() * 0.06, r.randf_range(-0.12, 0.12)), Vector3(r.randf(), 0, r.randf())), gold])
	parts.append([LA.sphere(0.05, 8, 5), LA.xf(Vector3(0.1, 0.46, 0.05)), LA.lit(Color("ff3a5a"))])
	return LA.build(parts, LA.vmat("treasure", 0.6, 0.0, 0.2, 2.0))
