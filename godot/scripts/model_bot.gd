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


func setup(glb_path: String) -> void:
	# The Blender export is ~40 separate parts; drawing them one by one costs
	# a draw call each. Fold them into one mesh with a surface per material.
	# The merged mesh with its LODs is baked by tools/bake_bots.gd into
	# <id>-merged.res (LOD generation may not exist in web export templates);
	# without the bake it is merged here, with LODs where the engine can.
	var key := glb_path
	if not _merged.has(key):
		var baked := key.get_basename() + "-merged.res"
		if ResourceLoader.exists(baked):
			_merged[key] = load(baked)
		else:
			_merged[key] = _merge((load(glb_path) as PackedScene).instantiate())
	_body = MeshInstance3D.new()
	(_body as MeshInstance3D).mesh = _merged[key]
	# A bot is ~45 px tall in play: pick the simpler LODs much sooner
	# (AAA review round 8, triangle budget).
	(_body as MeshInstance3D).lod_bias = 0.3
	add_child(_body)


## Every plain part in one surface: vertex colour is the albedo (sRGB), UV2
## carries roughness and metallic. Each surface costs a draw in the main,
## outline, rim and shadow passes, so 6 finish groups became 1.
const PLAIN_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back;
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 lin = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	ALBEDO = lin;
	SPECULAR = 0.5;
	if (UV2.x < 0.0) {   // emissive part: UV2.x is minus its energy
		EMISSION = lin * -UV2.x;
		ROUGHNESS = 0.5;
		METALLIC = 0.0;
	} else {
		ROUGHNESS = UV2.x;
		METALLIC = UV2.y;
	}
}
"""


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
			var plain: bool = bm != null and bm.albedo_texture == null and bm.emission_texture == null \
				and bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			var key: String
			if plain:
				key = "plain"   # one surface: finish rides in UV2 (AAA review round 8)
			else:
				key = "own:%d" % mat.get_instance_id() if mat != null else "own:none"
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var gm: Material = mat
				if plain:
					var nm := ShaderMaterial.new()
					var sh := Shader.new()
					sh.code = PLAIN_SHADER
					nm.shader = sh
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
			var fin := Vector2(clampf(bm.roughness, 0.0, 1.0), clampf(bm.metallic, 0.0, 1.0))
			if bm.emission_enabled:   # glowing parts: emission colour, energy as -UV2.x
				col = bm.emission
				fin = Vector2(-maxf(bm.emission_energy_multiplier, 0.01), 0.0)
			var order: Array = Array(idxs) if idxs != null and idxs.size() > 0 else range(verts.size())
			for i in order:
				st2.set_color(col)
				st2.set_uv2(fin)
				if norms != null and norms.size() == verts.size():
					st2.set_normal((nb * norms[i]).normalized())
				st2.add_vertex(xf * verts[i])
	# Indexed, then simplified into LODs so a bot far from the camera draws a
	# few thousand triangles, not 20-70k (AAA review round 4).
	var im := ImporterMesh.new()
	for key in groups:
		var st3: SurfaceTool = groups[key]
		st3.index()
		var arrays := st3.commit_to_arrays()
		var tmp := ArrayMesh.new()
		st3.commit(tmp)
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, tmp.surface_get_material(0))
	im.generate_lods(25.0, 60.0, [])
	root.free()
	return im.get_mesh()


## Tick: a clock face on top of the hat, so from above he reads as a clock
## rather than a hat disc (AAA review round 4).
func add_hat_face(col: Color) -> void:
	var mesh: Mesh = (_body as MeshInstance3D).mesh
	var box := mesh.get_aabb()
	var top := box.end.y
	var c := box.get_center()
	var r := minf(box.size.x, box.size.z) * 0.17
	var face := MeshInstance3D.new()
	var parts: Array = [
		[_cyl(r * 1.08, 0.02), Transform3D(Basis(), Vector3(0, 0.0, 0)), Color("c9a24a")],
		[_cyl(r, 0.03), Transform3D(Basis(), Vector3(0, 0.012, 0)), col.lightened(0.35)],
		[_boxm(Vector3(r * 0.12, 0.02, r * 0.75)), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 0.03, 0) + Basis(Vector3.UP, 0.4) * Vector3(0, 0, -r * 0.35)), Color("1a1a22")],
		[_boxm(Vector3(r * 0.12, 0.02, r * 0.5)), Transform3D(Basis(Vector3.UP, 2.2), Vector3(0, 0.03, 0) + Basis(Vector3.UP, 2.2) * Vector3(0, 0, -r * 0.22)), Color("1a1a22")],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var arr: Array = (p[0] as Mesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idxs: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var xf: Transform3D = p[1]
		for i in idxs:
			st.set_color(p[2])
			st.set_normal(xf.basis * norms[i])
			st.add_vertex(xf * verts[i])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = col * 0.25
	face.mesh = st.commit()
	face.material_override = m
	face.position = Vector3(c.x, top + 0.005, c.z)
	_body.add_child(face)


static func _cyl(r: float, h: float) -> Mesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 20
	return cm


static func _boxm(s: Vector3) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = s
	return bm


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
