extends RefCounted
## Set dressing on the walls (props) and the bomb-throwing hazards. Each
## model faces +Z (towards the camera when unrotated) and stands on y = 0.
## Ported from the browser's Props module: same kinds, same placement. Haunted
## House's witch is the one hazard.

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
		"gravestone":
			n = _node(gravestone_mesh(), kind)
		"pumpkin":
			n = _node(_m("pumpkin", _pumpkin), kind)
		"ghost":
			n = _node(_m("ghost", _ghost), kind)
			(n.get_node("Model") as MeshInstance3D).transparency = 0.28
		"witch":
			n = _node(_m("witch_angry" if angry else "witch", func(): return _witch(angry)), kind)
		"pylon":
			n = _node(_m("pylon", _pylon), kind)
		"server":
			n = _node(_m("server", _server), kind)
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
		"witch":
			return Vector3(0.28, 1.55, 0.12)
	return Vector3(0, 1.4, 0)


## Idle motion for the props that move: ghosts drift, the witch rocks, the
## beach ball turns, the factory pylons sway.
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


## The hazard's wind-up: k runs 0..1 over HAZARD_WINDUP, then -1 to hide.
static func wind_up(n: Node3D, k: float) -> void:
	var held := n.get_node_or_null("HeldBomb") as Node3D
	if held == null:
		return
	if k < 0.0:
		held.visible = false
		return
	held.visible = true
	var kind: String = n.get_meta("kind", "")
	var base := throw_offset(kind)
	var shake := sin(k * 60.0) * 0.03 * k
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
	s.radial_segments = 20
	s.rings = 10
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
	var orange := Color("ff8f26")
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
	# AAA review round 6: a silhouette you read at a glance from above, a wide
	# brim with a bright band, a flaring cape, a lighter face.
	var robe := Color("3a2250")
	var skin := Color("9ad86a")
	var parts: Array = [
		[LA.cyl(0.12, 0.3, 0.8, 14), LA.xf(Vector3(0, 0.4, 0)), robe],
		# (her cape is a separate fluttering mesh, added in mechanics.gd)
		[LA.sphere(0.17, 14, 8), LA.xf(Vector3(0, 0.95, 0)), skin],
		[LA.cone(0.05, 0.14, 6), LA.xf(Vector3(0, 0.93, 0.2), Vector3(PI / 2.0 - 0.3, 0, 0)), skin],
		[LA.cyl(0.4, 0.4, 0.035, 20), LA.xf(Vector3(0, 1.08, 0), Vector3(0.12, 0, 0)), Color("221430")],
		[LA.cone(0.17, 0.62, 12), LA.xf(Vector3(0, 1.38, -0.03), Vector3(-0.3, 0, 0.12)), Color("221430")],
		[LA.cyl(0.18, 0.18, 0.07, 12), LA.xf(Vector3(0, 1.13, 0)), LA.lit(Color("c070ff"))],
		[LA.box(Vector3(0.09, 0.09, 0.03)), LA.xf(Vector3(0, 1.13, 0.17)), LA.lit(Color("ffd040"))],
		[LA.cyl(0.015, 0.02, 1.2, 6), LA.xf(Vector3(-0.3, 0.6, 0.15), Vector3(0, 0, 0.35)), Color("6a4a2a")],
		[LA.cone(0.1, 0.3, 8), LA.xf(Vector3(-0.5, 0.08, 0.15), Vector3(0, 0, 0.35 + PI)), Color("c8a060")],
	]
	for s in [-1.0, 1.0]:
		# hands out past the brim, gripping the broom
		parts.append([LA.sphere(0.055, 8, 5), LA.xf(Vector3(s * 0.09, 0.36, 0.36)), skin])
	for s in [-1.0, 1.0]:
		parts.append([LA.sphere(0.03, 8, 4), LA.xf(Vector3(s * 0.06, 0.99, 0.15)), LA.lit(Color("ffe040"))])
		parts.append([LA.cyl(0.04, 0.06, 0.35, 8), LA.xf(Vector3(s * 0.2, 0.68, 0.06), Vector3(0.4, 0, s * 0.6)), robe])
	if angry:
		_scowl(parts, 1.04, 0.15, 0.06)
	return LA.build(parts, LA.vmat("witch", 0.75, 0.0, 0.2, 4.0))


# ---- Factory ---------------------------------------------------------------

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
