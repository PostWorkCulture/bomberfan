extends RefCounted
## Procedural art for the Forest arena. Every texture, mesh and material is
## generated in code — no image files to import — so CI builds and checks it,
## and the web download stays small. Results are cached: call freely.

static var _cache := {}


# ---- Textures -------------------------------------------------------------------

static func noise_tex(key: String, seed_value: int, freq: float, colors: PackedColorArray,
		offsets: PackedFloat32Array, size := 256, octaves := 5, normal := false, bump := 6.0,
		cellular := false) -> NoiseTexture2D:
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if cellular else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	else:
		var g := Gradient.new()
		g.offsets = offsets
		g.colors = colors
		t.color_ramp = g
	_cache[key] = t
	return t


static func grass_tex() -> NoiseTexture2D:
	return noise_tex("grass", 11, 0.018,
		PackedColorArray([Color("2a4419"), Color("38601f"), Color("487528"), Color("5f8433")]),
		PackedFloat32Array([0.0, 0.38, 0.66, 1.0]), 256, 6)


static func grass_detail_tex() -> NoiseTexture2D:
	return noise_tex("grass_detail", 12, 0.09,
		PackedColorArray([Color(0.55, 0.55, 0.55), Color(1, 1, 1), Color(1.25, 1.2, 1.05)]),
		PackedFloat32Array([0.0, 0.55, 1.0]), 256, 3)


static func grass_normal() -> NoiseTexture2D:
	return noise_tex("grass_n", 13, 0.06, PackedColorArray(), PackedFloat32Array(), 256, 4, true, 5.0)


static func forest_floor_tex() -> NoiseTexture2D:
	return noise_tex("floor", 21, 0.012,
		PackedColorArray([Color("2a2116"), Color("3a3020"), Color("344a22"), Color("4a5a2a"), Color("5b4a2c")]),
		PackedFloat32Array([0.0, 0.3, 0.55, 0.78, 1.0]), 512, 6)


static func stone_tex() -> NoiseTexture2D:
	return noise_tex("stone", 31, 0.03,
		PackedColorArray([Color("5f5b55"), Color("7f7a71"), Color("9b958a"), Color("6e6a62")]),
		PackedFloat32Array([0.0, 0.4, 0.7, 1.0]), 256, 6)


static func moss_tex() -> NoiseTexture2D:
	return noise_tex("moss", 41, 0.045,
		PackedColorArray([Color("26391a"), Color("37541f"), Color("4a6a2a")]),
		PackedFloat32Array([0.0, 0.5, 1.0]), 256, 5)


static func bark_tex() -> NoiseTexture2D:
	return noise_tex("bark", 51, 0.06,
		PackedColorArray([Color("3b2615"), Color("5a3a1f"), Color("70492a"), Color("4a3019")]),
		PackedFloat32Array([0.0, 0.35, 0.7, 1.0]), 256, 5, false, 6.0, true)


static func bark_normal() -> NoiseTexture2D:
	return noise_tex("bark_n", 52, 0.06, PackedColorArray(), PackedFloat32Array(), 256, 4, true, 9.0, true)


## Soft round sprite for fire, smoke and glows: white centre fading to clear.
static func soft_dot(key := "dot", hardness := 0.0) -> GradientTexture2D:
	if _cache.has(key):
		return _cache[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, clampf(0.35 + hardness * 0.5, 0.0, 0.95), 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache[key] = t
	return t


# ---- Materials -------------------------------------------------------------------

const ARENA_FLOOR_SHADER := """
shader_type spatial;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = floor(wpos.xz + 0.5);
	float chk = mod(cell.x + cell.y, 2.0);
	vec3 col = texture(grass_tex, wpos.xz * 0.21).rgb;
	col *= texture(detail_tex, wpos.xz * 0.9).rgb;
	col *= mix(1.0, 0.88, chk);
	vec2 f = abs(fract(wpos.xz + 0.5) - 0.5);
	col *= 1.0 - 0.22 * smoothstep(0.455, 0.5, max(f.x, f.y));
	ALBEDO = col;
	ROUGHNESS = 0.93;
	NORMAL_MAP = texture(grass_nrm, wpos.xz * 0.45).rgb;
	NORMAL_MAP_DEPTH = 0.7;
}
"""

const STONE_SHADER := """
shader_type spatial;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float moss_amount = 0.75;
uniform float scale = 0.55;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 b = pow(abs(wnrm), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec3 s = texture(stone_tex, wpos.zy * scale).rgb * b.x
		+ texture(stone_tex, wpos.xz * scale).rgb * b.y
		+ texture(stone_tex, wpos.xy * scale).rgb * b.z;
	float m = smoothstep(0.62, 0.97, wnrm.y) * moss_amount;
	m *= smoothstep(0.42, 0.62, texture(moss_tex, wpos.xz * 0.55).g * 2.2);
	vec3 moss = texture(moss_tex, wpos.xz * 1.4).rgb;
	ALBEDO = mix(s * tint, moss, clamp(m, 0.0, 1.0));
	ROUGHNESS = mix(0.82, 0.95, m);
}
"""

const LOG_END_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 light_wood : source_color = vec3(0.86, 0.66, 0.42);
uniform vec3 dark_wood : source_color = vec3(0.5, 0.31, 0.15);
uniform vec3 bark : source_color = vec3(0.24, 0.15, 0.08);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rings = 0.5 + 0.5 * sin(r * 30.0 + sin(a * 3.0) * 0.8);
	vec3 c = mix(dark_wood, light_wood, 0.35 + 0.5 * rings);
	c = mix(c, dark_wood * 0.8, smoothstep(0.0, 0.12, 0.12 - r));
	c = mix(c, bark, smoothstep(0.8, 0.9, r));
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float sway = 0.06;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 1.7 + w.x * 0.8 + w.z * 0.6) * sway * h * 3.0;
	VERTEX.z += cos(TIME * 1.3 + w.z * 0.7) * sway * 0.6 * h * 3.0;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
"""


static func _shader_mat(name_key: String, code: String, params := {}) -> ShaderMaterial:
	var key := "shader_mat:" + name_key
	if _cache.has(key):
		return _cache[key]
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	_cache[key] = m
	return m


static func arena_floor_mat() -> ShaderMaterial:
	return _shader_mat("floor_mat", ARENA_FLOOR_SHADER, {
		"grass_tex": grass_tex(), "detail_tex": grass_detail_tex(), "grass_nrm": grass_normal()})


static func stone_mat(key: String, tint: Color, moss: float, scale := 0.55) -> ShaderMaterial:
	return _shader_mat("stone_" + key, STONE_SHADER, {
		"stone_tex": stone_tex(), "moss_tex": moss_tex(), "tint": tint, "moss_amount": moss, "scale": scale})


static func log_end_mat() -> ShaderMaterial:
	return _shader_mat("log_end", LOG_END_SHADER)


static func grass_mat() -> ShaderMaterial:
	return _shader_mat("grass", GRASS_SHADER)


static func bark_mat() -> StandardMaterial3D:
	if _cache.has("bark_mat"):
		return _cache["bark_mat"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = bark_tex()
	m.normal_enabled = true
	m.normal_texture = bark_normal()
	m.normal_scale = 0.8
	m.roughness = 0.92
	m.uv1_scale = Vector3(2.0, 0.45, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["bark_mat"] = m
	return m


static func floor_mat() -> StandardMaterial3D:
	if _cache.has("forest_floor_mat"):
		return _cache["forest_floor_mat"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = forest_floor_tex()
	m.normal_enabled = true
	m.normal_texture = grass_normal()
	m.roughness = 0.97
	m.uv1_scale = Vector3(14.0, 14.0, 1.0)
	_cache["forest_floor_mat"] = m
	return m


static func vcol_mat(key: String, rough := 0.9, double_sided := true) -> StandardMaterial3D:
	if _cache.has("vcol_" + key):
		return _cache["vcol_" + key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["vcol_" + key] = m
	return m


static func flat_mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%s_%s" % [c.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m


# ---- Mesh helpers ------------------------------------------------------------------

## A box with rounded edges, optionally roughened with noise (boulders).
static func rounded_box(size: Vector3, radius: float, subdiv := 5, noise_amp := 0.0, noise_seed := 0) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_width = subdiv
	bm.subdivide_height = subdiv
	bm.subdivide_depth = subdiv
	var arr := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var inner := size * 0.5 - Vector3.ONE * radius
	var nz: FastNoiseLite = null
	if noise_amp > 0.0:
		nz = FastNoiseLite.new()
		nz.seed = noise_seed
		nz.frequency = 1.4
		nz.fractal_octaves = 3
	for i in verts.size():
		var p := verts[i]
		var c := p.clamp(-inner, inner)
		var d := p - c
		var n := d.normalized() if d.length() > 0.00001 else norms[i]
		var q := c + n * radius
		if nz != null:
			q += n * nz.get_noise_3dv(q) * noise_amp
		verts[i] = q
		norms[i] = n
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Adds one triangle with an explicit outward normal (flat shading).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outward: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:   # Godot front faces wind clockwise
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
	var fn := -((b - a).cross(c - a)).normalized()
	for pair in [[a, ca], [b, cb], [c, cc]]:
		st.set_color(pair[1])
		st.set_normal(fn)
		st.add_vertex(pair[0])


## A lumpy sphere with vertex colours (foliage, bushes, toadstool caps).
static func blob(radius: float, seed_value: int, amp: float, top: Color, bottom: Color,
		squash := 1.0, rings := 8, segs := 14, spots := 0.0, spot_col := Color.WHITE,
		hemisphere := false) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.rings = rings
	sm.radial_segments = segs
	sm.is_hemisphere = hemisphere
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var nz := FastNoiseLite.new()
	nz.seed = seed_value
	nz.frequency = 2.2 / maxf(radius, 0.05)
	for i in verts.size():
		var p := verts[i]
		var n := norms[i]
		p += n * nz.get_noise_3dv(p) * amp
		p.y *= squash
		verts[i] = p
		var t := clampf((p.y / maxf(radius * squash, 0.001)) * 0.5 + 0.5, 0.0, 1.0)
		var c := bottom.lerp(top, t)
		if spots > 0.0 and nz.get_noise_3dv(p * 2.3 + Vector3(9, 0, 0)) > 1.0 - spots and p.y > 0.0:
			c = spot_col
		cols[i] = c
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	return st.commit()


## Merge meshes (each with one surface) into one surface, with transforms.
static func merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		st.append_from(part[0], 0, part[1])
	return st.commit()


# ---- Arena pieces ----------------------------------------------------------------------

## Interior pillar: a cut stone block, bevelled, moss on top.
static func pillar_mesh() -> ArrayMesh:
	if _cache.has("pillar"):
		return _cache["pillar"]
	var m := rounded_box(Vector3(0.94, 0.98, 0.94), 0.09, 3, 0.025, 3)
	m.surface_set_material(0, stone_mat("pillar", Color(1.0, 1.0, 1.0), 0.32))
	_cache["pillar"] = m
	return m


## Border wall: chunky mossy boulders, a few shapes to vary between.
static func boulder_mesh(variant: int) -> ArrayMesh:
	var key := "boulder_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := rounded_box(Vector3(1.04, 1.1, 1.04), 0.28, 4, 0.09, 100 + variant * 17)
	m.surface_set_material(0, stone_mat("border", Color(0.82, 0.82, 0.8), 0.6))
	_cache[key] = m
	return m


## The destructible "crate": a stack of logs, three layers crossed.
static func log_pile_mesh() -> ArrayMesh:
	if _cache.has("logs"):
		return _cache["logs"]
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ends := SurfaceTool.new()
	ends.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.135
	var length := 0.86
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for layer in 3:
		var y := r + layer * (r * 1.96)
		var along_x := layer % 2 == 0
		for k in 3:
			var off := (k - 1) * 0.29
			var rr := r * rng.randf_range(0.9, 1.04)
			var ln := length * rng.randf_range(0.94, 1.02)
			var centre := Vector3(0.0, y, off) if along_x else Vector3(off, y, 0.0)
			var axis := Vector3.RIGHT if along_x else Vector3.BACK
			_add_log(side, ends, centre, axis, rr, ln, 10)
	var mesh := ArrayMesh.new()
	side.commit(mesh)
	ends.commit(mesh)
	mesh.surface_set_material(0, bark_mat())
	mesh.surface_set_material(1, log_end_mat())
	_cache["logs"] = mesh
	return mesh


static func _add_log(side: SurfaceTool, ends: SurfaceTool, centre: Vector3, axis: Vector3, r: float, ln: float, seg: int) -> void:
	var u := Vector3.UP
	var v := axis.cross(u).normalized()
	var a := centre - axis * ln * 0.5
	var b := centre + axis * ln * 0.5
	for i in seg:
		var t0 := TAU * i / seg
		var t1 := TAU * (i + 1) / seg
		var n0 := (u * cos(t0) + v * sin(t0))
		var n1 := (u * cos(t1) + v * sin(t1))
		var quad := [[a + n0 * r, n0, Vector2(float(i) / seg, 0)], [b + n0 * r, n0, Vector2(float(i) / seg, 1)],
			[b + n1 * r, n1, Vector2(float(i + 1) / seg, 1)], [a + n1 * r, n1, Vector2(float(i + 1) / seg, 0)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			side.set_normal(quad[idx][1])
			side.set_uv(quad[idx][2])
			side.add_vertex(quad[idx][0])
		for cap in [[a, -axis], [b, axis]]:
			var cp: Vector3 = cap[0]
			var cn: Vector3 = cap[1]
			var p0 := cp + n0 * r
			var p1 := cp + n1 * r
			var tri := [[cp, Vector2(0.5, 0.5)], [p0, Vector2(0.5 + 0.5 * cos(t0), 0.5 + 0.5 * sin(t0))],
				[p1, Vector2(0.5 + 0.5 * cos(t1), 0.5 + 0.5 * sin(t1))]]
			if ((p0 - cp).cross(p1 - cp)).dot(cn) > 0.0:
				tri = [tri[0], tri[2], tri[1]]
			for e in tri:
				ends.set_normal(cn)
				ends.set_uv(e[1])
				ends.add_vertex(e[0])


## A fallen log for set dressing (same materials as the pile).
static func fallen_log_mesh() -> ArrayMesh:
	if _cache.has("fallen_log"):
		return _cache["fallen_log"]
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ends := SurfaceTool.new()
	ends.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_log(side, ends, Vector3(0, 0.2, 0), Vector3.RIGHT, 0.2, 2.2, 14)
	var mesh := ArrayMesh.new()
	side.commit(mesh)
	ends.commit(mesh)
	mesh.surface_set_material(0, bark_mat())
	mesh.surface_set_material(1, log_end_mat())
	_cache["fallen_log"] = mesh
	return mesh


# ---- Trees and props --------------------------------------------------------------------

## A stylised pine: tiers of jagged, drooping cones on a trunk.
static func pine_mesh() -> ArrayMesh:
	if _cache.has("pine"):
		return _cache["pine"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := [[0.78, 0.55, 1.0], [0.64, 1.02, 0.92], [0.5, 1.45, 0.84], [0.35, 1.84, 0.74], [0.2, 2.18, 0.6]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for tier in tiers:
		var r: float = tier[0]
		var y0: float = tier[1]
		var h: float = tier[2]
		var seg := 14
		var apex := Vector3(0, y0 + h, 0)
		var under := Vector3(0, y0 + h * 0.22, 0)
		var tip_col := Color("5e9a3e")
		var rim_col := Color("1f4a22")
		var rim: Array = []
		for i in seg:
			var a := TAU * i / seg + rng.randf_range(-0.08, 0.08)
			var rr := r * (1.0 if i % 2 == 0 else 0.72) * rng.randf_range(0.92, 1.06)
			var droop := -0.1 if i % 2 == 0 else 0.03
			rim.append(Vector3(cos(a) * rr, y0 + droop, sin(a) * rr))
		for i in seg:
			var p0: Vector3 = rim[i]
			var p1: Vector3 = rim[(i + 1) % seg]
			var out := ((p0 + p1) * 0.5 - Vector3(0, y0 + h * 0.5, 0))
			out.y = absf(out.y) + 0.3
			_tri(st, apex, p0, p1, tip_col, rim_col, rim_col, out)
			_tri(st, under, p1, p0, rim_col.darkened(0.4), rim_col.darkened(0.2), rim_col.darkened(0.2), Vector3(0, -1, 0) + (p0 + p1) * 0.2)
	var foliage := st.commit()
	foliage.surface_set_material(0, vcol_mat("foliage"))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.07
	trunk.bottom_radius = 0.13
	trunk.height = 0.75
	trunk.radial_segments = 8
	var mesh := ArrayMesh.new()
	var ta := trunk.get_mesh_arrays()
	ta[Mesh.ARRAY_TANGENT] = null
	var verts: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.375
	ta[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
	mesh.surface_set_material(0, bark_mat())
	var fa := foliage.surface_get_arrays(0)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fa)
	mesh.surface_set_material(1, vcol_mat("foliage"))
	_cache["pine"] = mesh
	return mesh


## A broadleaf tree: trunk with a crown of lumpy blobs.
static func broadleaf_mesh(variant: int) -> ArrayMesh:
	var key := "broadleaf_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant
	var parts: Array = []
	var top := Color("5b8a36") if variant % 2 == 0 else Color("6f8a34")
	var bottom := Color("1d3616")
	var centres := [Vector3(0, 1.75, 0), Vector3(0.42, 1.55, 0.1), Vector3(-0.38, 1.6, -0.15),
		Vector3(0.05, 1.5, 0.42), Vector3(-0.1, 2.15, -0.05)]
	for i in centres.size():
		var rad := rng.randf_range(0.48, 0.66)
		var b := blob(rad, 400 + variant * 10 + i, rad * 0.22, top, bottom, 0.85, 7, 12)
		parts.append([b, Transform3D(Basis(), centres[i])])
	var crown := merge(parts)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.16
	trunk.height = 1.5
	trunk.radial_segments = 8
	var mesh := ArrayMesh.new()
	var ta := trunk.get_mesh_arrays()
	ta[Mesh.ARRAY_TANGENT] = null
	var verts: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.75
	ta[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
	mesh.surface_set_material(0, bark_mat())
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, crown.surface_get_arrays(0))
	mesh.surface_set_material(1, vcol_mat("foliage"))
	_cache[key] = mesh
	return mesh


static func bush_mesh() -> ArrayMesh:
	if _cache.has("bush"):
		return _cache["bush"]
	var parts: Array = []
	var offs := [Vector3(0, 0.28, 0), Vector3(0.3, 0.22, 0.08), Vector3(-0.26, 0.2, -0.1), Vector3(0.05, 0.2, -0.3)]
	for i in offs.size():
		parts.append([blob(0.32, 600 + i, 0.07, Color("4f7d31"), Color("1a3315"), 0.8, 6, 10), Transform3D(Basis(), offs[i])])
	var m := merge(parts)
	m.surface_set_material(0, vcol_mat("foliage"))
	_cache["bush"] = m
	return m


static func rock_mesh(variant: int) -> ArrayMesh:
	var key := "rock_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := rounded_box(Vector3(0.7, 0.45, 0.55), 0.2, 4, 0.08, 700 + variant * 13)
	m.surface_set_material(0, stone_mat("rock", Color(0.85, 0.86, 0.82), 0.5))
	_cache[key] = m
	return m


static func toadstool_mesh() -> ArrayMesh:
	if _cache.has("toadstool"):
		return _cache["toadstool"]
	var stem := blob(0.07, 801, 0.0, Color("f3ead6"), Color("d9ccb0"), 2.6, 6, 8)
	var cap := blob(0.2, 802, 0.02, Color("d8322a"), Color("8e1a16"), 0.55, 6, 14, 0.38, Color("fbf6ea"), true)
	var m := merge([[stem, Transform3D(Basis(), Vector3(0, 0.17, 0))], [cap, Transform3D(Basis(), Vector3(0, 0.33, 0))]])
	m.surface_set_material(0, vcol_mat("toadstool", 0.6, false))
	_cache["toadstool"] = m
	return m


static func grass_tuft_mesh() -> ArrayMesh:
	if _cache.has("tuft"):
		return _cache["tuft"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 7:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * 0.025
		var base := d * rng.randf_range(0.0, 0.08)
		var h := rng.randf_range(0.18, 0.34)
		var tip := base + d * rng.randf_range(0.04, 0.12) + Vector3(0, h, 0)
		var dark := Color("2c4d1c")
		var light := Color("86b04a").lerp(Color("b5b85a"), rng.randf() * 0.4)
		for v in [[base - side, dark], [base + side, dark], [tip, light]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	var m := st.commit()
	m.surface_set_material(0, grass_mat())
	_cache["tuft"] = m
	return m


static func multimesh(mesh: Mesh, xforms: Array, colors: Array = [], shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
