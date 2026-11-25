extends Node3D
## A bomber-bot made in Blender (tools/blender/bomber_bots.py, exported as
## assets/characters/<id>.glb). The models are rigid, so all the motion is
## done here: idle bob, a bouncy waddle when running, a hop-and-spin cheer and
## a topple when hit. fighter.gd drives it through animate/die/cheer/revive.

var _body: Node3D
var _t := 0.0
var _dead_t := -1.0
var _cheer_t := -1.0
var _step := 0.0


static var _merged := {}   # scene path -> one ArrayMesh, built once per bot


func setup(scene: PackedScene) -> void:
	# The Blender export is ~40 separate parts; drawing them one by one costs
	# a draw call each. Fold them into one mesh with a surface per material.
	var key := scene.resource_path
	if not _merged.has(key):
		_merged[key] = _merge(scene.instantiate())
	_body = MeshInstance3D.new()
	(_body as MeshInstance3D).mesh = _merged[key]
	add_child(_body)


static func _merge(root: Node3D) -> ArrayMesh:
	# Plain-coloured materials are baked into vertex colours and grouped by
	# finish (metal / roughness), so a bot is a handful of surfaces instead of
	# ~30. Each surface is a draw call, and the outline and shadow passes
	# multiply it (AAA review round 3: fighters were ~380 of ~640 draw calls).
	# Emissive or textured materials keep their own surface.
	var groups := {}   # key -> [SurfaceTool, Material]
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node3D = item[0]
		var xf: Transform3D = item[1]
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			var bm := mat as BaseMaterial3D
			var plain: bool = bm != null and bm.albedo_texture == null and not bm.emission_enabled \
				and bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			var key: String
			if plain:
				key = "plain:%d:%d" % [int(bm.metallic > 0.4), int(clampf(bm.roughness, 0.0, 0.99) * 3.0)]
			else:
				key = "own:%d" % mat.get_instance_id() if mat != null else "own:none"
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var gm: Material = mat
				if plain:
					var nm := StandardMaterial3D.new()
					nm.vertex_color_use_as_albedo = true
					nm.vertex_color_is_srgb = true
					nm.metallic = bm.metallic
					nm.roughness = bm.roughness
					nm.metallic_specular = bm.metallic_specular
					gm = nm
				st.set_material(gm)
				groups[key] = st
			var st2: SurfaceTool = groups[key]
			if not plain:
				st2.append_from(mi.mesh, si, xf)
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms = arr[Mesh.ARRAY_NORMAL]
			var idxs = arr[Mesh.ARRAY_INDEX]
			var nb := xf.basis.inverse().transposed()
			var col := bm.albedo_color
			var order: Array = Array(idxs) if idxs != null and idxs.size() > 0 else range(verts.size())
			for i in order:
				st2.set_color(col)
				if norms != null and norms.size() == verts.size():
					st2.set_normal((nb * norms[i]).normalized())
				st2.add_vertex(xf * verts[i])
	var out := ArrayMesh.new()
	for key in groups:
		(groups[key] as SurfaceTool).commit(out)
	root.free()
	return out


func die() -> void:
	_dead_t = 0.0
	_cheer_t = -1.0


func revive() -> void:
	_dead_t = -1.0
	_cheer_t = -1.0
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	if _body:
		_body.rotation = Vector3.ZERO
		_body.position = Vector3.ZERO
		_body.scale = Vector3.ONE


func cheer() -> void:
	_cheer_t = 0.0


func animate(delta: float, moving: bool, speed01: float) -> void:
	_t += delta
	if _body == null:
		return
	if _dead_t >= 0.0:
		# Topple backwards with a little bounce, then lie still.
		_dead_t += delta
		var k := clampf(_dead_t / 0.45, 0.0, 1.0)
		_body.rotation.x = lerpf(0.0, -PI / 2.0, k * k)
		_body.position.y = 0.12 * sin(k * PI)
		return
	if _cheer_t >= 0.0:
		_cheer_t += delta
		var hop := absf(sin(_cheer_t * 7.0))
		_body.position.y = hop * 0.22
		_body.rotation.y = _cheer_t * 6.0
		_body.scale = Vector3(1.0 + (1.0 - hop) * 0.08, 1.0 - (1.0 - hop) * 0.08, 1.0 + (1.0 - hop) * 0.08)
		return
	if moving:
		# Step rate follows speed; each step is a bounce with a side-to-side roll.
		_step += delta * (9.0 + 4.0 * maxf(0.0, speed01 - 1.0))
		var s := sin(_step)
		var bounce := absf(s)
		_body.position.y = bounce * 0.07
		_body.rotation.z = s * 0.11
		_body.rotation.x = 0.16             # lean into the run
		var squash := 1.0 - (1.0 - bounce) * 0.06
		_body.scale = Vector3(2.0 - squash, squash, 2.0 - squash)
	else:
		# Idle: a slow breathing bob, settling back from the run.
		_body.position.y = lerpf(_body.position.y, (sin(_t * 2.4) * 0.5 + 0.5) * 0.025, minf(1.0, delta * 10.0))
		_body.rotation.z = lerpf(_body.rotation.z, sin(_t * 1.3) * 0.03, minf(1.0, delta * 8.0))
		_body.rotation.x = lerpf(_body.rotation.x, 0.0, minf(1.0, delta * 8.0))
		_body.scale = _body.scale.lerp(Vector3.ONE, minf(1.0, delta * 10.0))
