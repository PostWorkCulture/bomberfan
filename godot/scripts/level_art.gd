extends RefCounted
## Procedural art for the arenas beyond the Forest (Beach, Haunted House,
## Factory): floors, walls,
## crates, the ground outside and the bases under shaped decks. Everything
## is generated in code and cached, like art.gd. Props on the walls and the
## hazard throwers live in level_props.gd.

const Art := preload("res://scripts/art.gd")
const Cfg := preload("res://scripts/config.gd")

static var _cache := {}

# ---- Palettes (from LEVELS in index.html, deepened for real lighting) -------------

const THEMES := {
	# Each arena has its own light and grade. Colour order on every arena:
	# floor quietest, walls next, crates stronger, fighters / bombs / hazards
	# brightest. Hazard yellow and red are kept for danger only.
	"forest": {
		# Golden hour: warm low sun, cool sky in the shadows.
		"sky": Color(0.05, 0.09, 0.065), "fog": Color(0.2, 0.24, 0.16), "fog_begin": 17.0, "fog_end": 36.0,
		"sun": Color(1.0, 0.84, 0.62), "sun_energy": 1.4, "sun_rot": Vector3(-50, -46, 0), "ambient": 0.42,
		"sky_top": Color(0.3, 0.44, 0.62), "sky_horizon": Color(0.74, 0.7, 0.56), "ground_horizon": Color(0.4, 0.44, 0.3),
		"exposure": 0.98, "saturation": 1.04, "contrast": 1.1, "glow": 0.35,
		"debris": Color(0, 0, 0, 0),
	},
	"beach": {
		# High noon on a sandbar: bright, warm, a little haze off the water.
		"sky": Color("0b3550"), "fog": Color(0.55, 0.72, 0.8), "fog_begin": 22.0, "fog_end": 50.0,
		"sun": Color(1.0, 0.94, 0.82), "sun_energy": 1.05, "sun_rot": Vector3(-48, -34, 0), "ambient": 0.3,
		"sky_top": Color(0.46, 0.56, 0.64), "sky_horizon": Color(0.84, 0.8, 0.72), "ground_horizon": Color(0.6, 0.52, 0.4),
		"exposure": 0.74, "saturation": 1.08, "contrast": 1.06, "glow": 0.3,
		"floor": {"pattern": 5, "a": Color("8c6c44"), "b": Color("9c7b4f"), "line": Color("5a4028"), "line_alpha": 0.12, "rough": 0.95},
		"block": {"style": 6, "side": Color("6e5842"), "top": Color("86705a"), "rough": 0.9, "scale": 0.9},
		"border": {"style": 0, "side": Color("6e5044"), "top": Color("8a6858"), "rough": 0.85, "scale": 0.9},
		"plinth": Color("a88e62"), "debris": Color("b89c6e"),
	},
	"haunted": {
		# Moonlit: cold blue key from behind, warm candle pools on the boards.
		"sky": Color("07040d"), "fog": Color(0.09, 0.06, 0.15), "fog_begin": 15.0, "fog_end": 32.0,
		"sun": Color(0.8, 0.84, 1.0), "sun_energy": 0.8, "sun_rot": Vector3(-52, -152, 0), "ambient": 0.4,
		"sky_top": Color(0.09, 0.08, 0.13), "sky_horizon": Color(0.21, 0.18, 0.26), "ground_horizon": Color(0.08, 0.07, 0.1),
		"exposure": 1.06, "saturation": 0.92, "contrast": 1.14, "glow": 0.55,
		"floor": {"pattern": 3, "a": Color("201819"), "b": Color("312628"), "line": Color("8a70c0"), "line_alpha": 0.05, "rough": 0.8, "plank": 0.25},
		"block": {"style": 1, "side": Color("38343e"), "top": Color("4a4552"), "rough": 0.9, "scale": 1.0},
		"border": {"style": 1, "side": Color("28242c"), "top": Color("3a3540"), "rough": 0.92, "scale": 1.0},
		"plinth": Color("2a2428"), "debris": Color("6a4a7c"),
	},
	"factory": {
		# Indoors: cool overhead strip light from almost straight above, warm
		# furnace glow round the edges.
		"sky": Color("0b0d11"), "fog": Color(0.08, 0.085, 0.1), "fog_begin": 17.0, "fog_end": 36.0,
		"sun": Color(0.92, 0.96, 1.0), "sun_energy": 1.1, "sun_rot": Vector3(-62, -24, 0), "ambient": 0.32,
		"sky_top": Color(0.16, 0.18, 0.22), "sky_horizon": Color(0.34, 0.33, 0.32), "ground_horizon": Color(0.12, 0.12, 0.13),
		"exposure": 1.04, "saturation": 1.0, "contrast": 1.2, "glow": 0.45,
		"floor": {"pattern": 4, "a": Color("272b32"), "b": Color("323741"), "line": Color("ffd60a"), "line_alpha": 0.06, "rough": 0.5, "metal": 0.55},
		"block": {"style": 2, "side": Color("4a525e"), "top": Color("5e6672"), "rough": 0.65, "metal": 0.45, "scale": 1.0},
		"border": {"style": 5, "side": Color("363c46"), "top": Color("ffc21a"), "rough": 0.5, "metal": 0.6, "scale": 1.0},
		"plinth": Color("3e434c"), "debris": Color("b08a5a"),
	},
}


static func theme(id: String) -> Dictionary:
	return THEMES.get(id, {})


# ---- Shaders ----------------------------------------------------------------------------

const FLOOR_SHADER := """
shader_type spatial;
uniform int pattern = 1;
uniform vec3 col_a : source_color = vec3(0.2);
uniform vec3 col_b : source_color = vec3(0.3);
uniform vec3 line_col : source_color = vec3(1.0);
uniform float line_alpha = 0.2;
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform float plank = 0.25;
uniform float edge_shadow = 0.0;
uniform vec2 inner_half = vec2(6.5, 5.5);
uniform vec2 grid = vec2(15.0, 13.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D occ_tex : filter_linear, repeat_disable;
uniform float has_occ = 0.0;
uniform float occ_strength = 0.45;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = wpos.xz + grid * 0.5;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float n = texture(noise_tex, wpos.xz * 0.21).r;
	float chk = mod(cell.x + cell.y, 2.0);
	vec3 col = mix(col_a, col_b, n);
	float edge = max(abs(f.x - 0.5), abs(f.y - 0.5));
	float line = smoothstep(0.455, 0.5, edge);
	float r = rough;
	vec3 emit = vec3(0.0);
	if (pattern == 1) {
		// Shallow water over sand: drifting caustics, a little ripple sheen.
		vec2 p = wpos.xz;
		float c1 = texture(noise_tex, p * 0.34 + vec2(TIME * 0.035, TIME * 0.02)).r;
		float c2 = texture(noise_tex, p * 0.31 - vec2(TIME * 0.025, -TIME * 0.03)).r;
		float caustic = pow(clamp(1.0 - abs(c1 - c2) * 2.2, 0.0, 1.0), 9.0);
		col *= 1.0 - 0.07 * chk;
		col += vec3(0.55, 0.8, 0.85) * caustic * 0.45;
		emit += vec3(0.2, 0.42, 0.5) * caustic * 0.2;
		col = mix(col, line_col, line * line_alpha);
	} else if (pattern == 3) {
		// Planks running along x: per-board tint, staggered butt joints, grain.
		float v = g.y / plank;
		float id = floor(v);
		float off = hash(vec2(id, 3.1)) * 3.0;
		float len = 2.0 + hash(vec2(id, 7.7)) * 1.5;
		float u = (g.x + off) / len;
		float bid = floor(u);
		float tint = hash(vec2(id, bid));
		float grain = texture(noise_tex, vec2(g.x * 0.12 + bid * 0.37, v * 0.9)).r;
		col = mix(col_a, col_b, tint * 0.7 + grain * 0.3);
		col *= 0.86 + grain * 0.24;
		float gap = smoothstep(0.42, 0.5, abs(fract(v) - 0.5)) + smoothstep(0.485, 0.5, abs(fract(u) - 0.5));
		col *= 1.0 - 0.55 * clamp(gap, 0.0, 1.0);
		col = mix(col, line_col, line * line_alpha);
		col *= 1.0 - 0.04 * chk;
	} else if (pattern == 4) {
		// Factory plate: diamond tread, bolted tile plates, painted seam line.
		vec2 d = vec2(g.x + g.y, g.x - g.y) * 5.0;
		float tread = smoothstep(0.62, 0.78, abs(sin(d.x * 3.14159)) * abs(sin(d.y * 3.14159)));
		col *= 0.9 + 0.22 * tread;
		col *= 1.0 - 0.06 * chk;
		vec2 b = abs(f - 0.5);
		float bolt = 1.0 - smoothstep(0.02, 0.035, length(b - vec2(0.4)));
		col = mix(col, vec3(0.55, 0.58, 0.62), bolt);
		col *= 1.0 - 0.35 * smoothstep(0.44, 0.47, edge);
		col = mix(col, line_col, line * line_alpha * 2.0);
		r = mix(rough, 0.3, tread);
	} else if (pattern == 5) {
		// Sand: wind ripples, darker damp patches, a few shell flecks.
		vec2 p = wpos.xz;
		float rip = sin((p.x * 0.8 + p.y * 2.6) * 3.2 + n * 6.0) * 0.5 + 0.5;
		col *= 0.93 + 0.1 * rip;
		float damp = smoothstep(0.55, 0.78, texture(noise_tex, p * 0.09 + 0.3).r);
		col = mix(col, col * vec3(0.8, 0.77, 0.74), damp * 0.6);
		float fleck = step(0.986, hash(floor(p * 9.0))) * (1.0 - smoothstep(0.08, 0.2, length(fract(p * 9.0) - 0.5)));
		col = mix(col, vec3(0.97, 0.93, 0.86), fleck * 0.55);
		col *= 1.0 - 0.035 * chk;
		col = mix(col, line_col, line * line_alpha);
		r = mix(rough, 0.55, damp);
	}
	// Contact shadow round every wall and crate, from the occupancy map.
	float occ = has_occ * texture(occ_tex, g / grid).r;
	col *= 1.0 - occ_strength * smoothstep(0.06, 0.5, occ);
	if (edge_shadow > 0.0) {
		float d = min(inner_half.x - abs(wpos.x), inner_half.y - abs(wpos.z));
		col *= mix(1.0 - edge_shadow, 1.0, smoothstep(0.0, 0.6, d));
	}
	ALBEDO = col;
	ROUGHNESS = r;
	METALLIC = metal;
	EMISSION = emit;
	if (pattern == 1) { SPECULAR = 0.9; }
}
"""

const BLOCK_SHADER := """
shader_type spatial;
uniform int style = 0;
uniform vec3 side_col : source_color = vec3(0.5);
uniform vec3 top_col : source_color = vec3(0.7);
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform float scale = 1.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D cell_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;
varying vec3 centre;
varying float vary;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	centre = MODEL_MATRIX[3].xyz;
	vary = fract(sin(dot(centre.xz, vec2(12.9898, 78.233))) * 43758.5453);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec3 b = pow(abs(wnrm), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec2 uv = b.y > max(b.x, b.z) ? wpos.xz : (b.x > b.z ? wpos.zy : wpos.xy);
	vec2 luv = b.y > max(b.x, b.z) ? lpos.xz : (b.x > b.z ? lpos.zy : lpos.xy);
	float n = texture(noise_tex, uv * 0.6 * scale).r;
	float n2 = texture(noise_tex, uv * 2.3 * scale + 0.5).r;
	float top = smoothstep(0.55, 0.9, wnrm.y);
	vec3 col = mix(side_col, top_col, top);
	col *= 0.82 + 0.36 * n;
	float r = rough;
	float m = metal;
	if (style == 0) {
		// Coral / porous rock: pitted with cells.
		float c = texture(cell_tex, uv * 1.1 * scale).r;
		col *= 0.75 + 0.35 * smoothstep(0.02, 0.25, c);
		col *= 0.9 + 0.2 * n2;
	} else if (style == 1) {
		// Brick: offset courses on the sides, a capstone on top.
		vec2 bu = luv * vec2(3.0, 4.0);
		bu.x += step(1.0, mod(floor(bu.y), 2.0)) * 0.5;
		vec2 bf = fract(bu);
		float mortar = max(smoothstep(0.43, 0.5, abs(bf.x - 0.5)), smoothstep(0.38, 0.5, abs(bf.y - 0.5)));
		float bh = hash(floor(bu) + floor(wpos.xz * 1.0));
		col *= mix(0.85 + 0.25 * bh, 0.45, mortar * (1.0 - top));
		r = mix(rough, 1.0, mortar);
	} else if (style == 2) {
		// Riveted metal panels.
		vec2 pf = fract(luv * 2.0 + 0.5);
		float seam = smoothstep(0.46, 0.5, max(abs(pf.x - 0.5), abs(pf.y - 0.5)));
		vec2 rv = abs(fract(luv * 2.0 + 0.5) - 0.5);
		float rivet = 1.0 - smoothstep(0.03, 0.05, length(rv - vec2(0.38)));
		col *= 1.0 - 0.35 * seam;
		col = mix(col, top_col * 1.3, rivet * 0.8);
		col *= 0.88 + 0.12 * n2;
		r = mix(rough, rough + 0.3, n2 * 0.6);
	} else if (style == 6) {
		// Sandstone: horizontal strata on the sides, wind-smoothed top.
		float strata = sin(wpos.y * 22.0 + n * 4.0) * 0.5 + 0.5;
		col *= mix(1.0, 0.86 + 0.22 * strata, 1.0 - top);
		col *= 0.92 + 0.14 * n2;
	} else if (style == 5) {
		// Steel with a hazard-striped rim round a dark tread-plate cap.
		float stripe = step(0.5, fract((wpos.x + wpos.z) * 2.2));
		vec3 haz = mix(top_col * 0.9, vec3(0.06), stripe);
		// One continuous band along the inside edge of the ring only (AAA
		// review: a striped frame on every block was the noisiest thing on screen).
		vec3 dl = wpos - centre;
		float rx = step(6.9, abs(centre.x)) * smoothstep(0.32, 0.38, -dl.x * sign(centre.x));
		float rz = step(5.9, abs(centre.z)) * smoothstep(0.32, 0.38, -dl.z * sign(centre.z));
		float rim = max(rx, rz);
		vec3 cap = side_col * (0.8 + 0.3 * n2);
		col = mix(side_col * (0.85 + 0.3 * n2), mix(cap, haz, rim), top);
		vec2 pf = fract(luv * 2.0 + 0.5);
		col *= 1.0 - 0.3 * smoothstep(0.46, 0.5, max(abs(pf.x - 0.5), abs(pf.y - 0.5))) * (1.0 - top);
		m = mix(metal, 0.1, top);
		r = mix(rough, 0.6, top);
	}
	// Worn bevels, grime at the foot, per-block tint (AAA review round 3).
	vec3 an = abs(wnrm);
	float edge = smoothstep(0.06, 0.24, 1.0 - max(an.x, max(an.y, an.z)));
	col *= 1.0 + 0.15 * edge;
	col *= mix(0.74, 1.0, smoothstep(0.0, 0.16, wpos.y));
	col *= 0.94 + 0.12 * vary;
	ALBEDO = col;
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
}
"""

## Vertex-coloured props with a little texture so flat colour never reads as
## plastic. Vertex alpha picks the finish: 1 = the material's own (wood, paint,
## cloth), 0.5 = polished metal, 0 = glowing. Colours are sRGB like the palette.
const VCOL_SHADER := """
shader_type spatial;
uniform float rough = 0.7;
uniform float metal = 0.0;
uniform float grain = 0.22;
uniform float glow = 2.5;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 lpos;
varying vec3 lnrm;
void vertex() { lpos = VERTEX; lnrm = NORMAL; }
void fragment() {
	vec3 b = abs(lnrm);
	vec2 uv = b.y > max(b.x, b.z) ? lpos.xz : (b.x > b.z ? lpos.zy : lpos.xy);
	float n = texture(noise_tex, uv * 3.0).r;
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float is_glow = step(COLOR.a, 0.25);
	float is_metal = step(0.25, COLOR.a) * step(COLOR.a, 0.75);
	ALBEDO = c * (1.0 - grain * 0.5 + grain * n) * (1.0 - is_glow * 0.5);
	ROUGHNESS = mix(rough, 0.32, is_metal);
	METALLIC = mix(metal, 0.9, is_metal);
	EMISSION = c * glow * is_glow;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep : source_color = vec3(0.02, 0.12, 0.2);
uniform vec3 shallow : source_color = vec3(0.1, 0.4, 0.5);
uniform vec3 foam : source_color = vec3(0.9, 0.96, 1.0);
uniform float wave = 0.06;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.1 + wpos.x * 0.6) * wave + cos(TIME * 0.9 + wpos.z * 0.7) * wave;
}
void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.07 + vec2(TIME * 0.01, 0.0)).r;
	float n2 = texture(noise_tex, wpos.xz * 0.19 - vec2(0.0, TIME * 0.02)).r;
	vec3 col = mix(deep, shallow, n1 * 0.7 + n2 * 0.3);
	float crest = smoothstep(0.74, 0.9, n2 * 0.6 + n1 * 0.5);
	col = mix(col, foam, crest * 0.18);
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	METALLIC = 0.05;
}
"""

const BELT_SHADER := """
shader_type spatial;
uniform vec3 belt_col : source_color = vec3(0.09, 0.1, 0.12);
uniform vec3 arrow_col : source_color = vec3(0.55, 0.5, 0.32);
uniform float speed = 1.5;
uniform float dir = 1.0;   // -1 when the Factory lever has reversed the loop
void fragment() {
	// UV.x runs along the direction of travel (the mesh is rotated per tile).
	float u = UV.x * dir - TIME * speed;
	float slat = smoothstep(0.42, 0.5, abs(fract(u * 6.0) - 0.5));
	vec3 col = belt_col * (1.0 - 0.45 * slat);
	float y = abs(UV.y - 0.5);
	float chevron = fract(u * 2.0 + y * 1.2);
	float arrow = (1.0 - smoothstep(0.12, 0.17, abs(chevron - 0.5))) * step(y, 0.3);
	col = mix(col, arrow_col, arrow * 0.85);
	float rail = smoothstep(0.4, 0.44, y);
	col = mix(col, vec3(0.45, 0.48, 0.52), rail);
	ALBEDO = col;
	EMISSION = arrow_col * arrow * 0.25;
	ROUGHNESS = mix(0.75, 0.35, rail);
	METALLIC = rail * 0.8;
}
"""

## A pulsing ring on the floor: where a hazard's bomb is about to land.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 tint : source_color = vec3(0.43, 0.94, 1.0);
uniform float phase = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = TIME * 2.2 + phase;
	float ring = (1.0 - smoothstep(0.03, 0.07, abs(r - 0.82))) * 1.2;
	float inner = (1.0 - smoothstep(0.02, 0.05, abs(r - fract(t * 0.35) * 0.8)));
	float swirl = 0.5 + 0.5 * sin(atan(p.y, p.x) * 3.0 - t * 2.0 + r * 8.0);
	float disc = (1.0 - smoothstep(0.6, 0.85, r)) * (0.18 + 0.22 * swirl);
	float a = clamp(ring + inner * 0.6 + disc, 0.0, 1.5) * step(r, 0.95);
	ALBEDO = tint * a;
}
"""


static func noise_tex() -> NoiseTexture2D:
	return Art.noise_tex("lv_noise", 91, 0.035,
		PackedColorArray([Color(0, 0, 0), Color(1, 1, 1)]), PackedFloat32Array([0.0, 1.0]), 256, 5)


static func cell_tex() -> NoiseTexture2D:
	if _cache.has("cell_tex"):
		return _cache["cell_tex"]
	var n := FastNoiseLite.new()
	n.seed = 92
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.05
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.normalize = true
	_cache["cell_tex"] = t
	return t


static func _shader(key: String, code: String) -> Shader:
	if _cache.has("sh:" + key):
		return _cache["sh:" + key]
	var s := Shader.new()
	s.code = code
	_cache["sh:" + key] = s
	return s


static func floor_mat(id: String, edge_shadow: float) -> ShaderMaterial:
	var f: Dictionary = THEMES[id]["floor"]
	var m := ShaderMaterial.new()
	m.shader = _shader("floor", FLOOR_SHADER)
	m.set_shader_parameter("pattern", f["pattern"])
	m.set_shader_parameter("col_a", f["a"])
	m.set_shader_parameter("col_b", f["b"])
	m.set_shader_parameter("line_col", f["line"])
	m.set_shader_parameter("line_alpha", f["line_alpha"])
	m.set_shader_parameter("rough", f["rough"])
	m.set_shader_parameter("metal", f.get("metal", 0.0))
	m.set_shader_parameter("plank", f.get("plank", 0.25))
	m.set_shader_parameter("edge_shadow", edge_shadow)
	m.set_shader_parameter("inner_half", Vector2((Cfg.COLS - 2) * 0.5, (Cfg.ROWS - 2) * 0.5))
	m.set_shader_parameter("grid", Vector2(Cfg.COLS, Cfg.ROWS))
	m.set_shader_parameter("noise_tex", noise_tex())
	if Art.occ_texture != null:
		m.set_shader_parameter("occ_tex", Art.occ_texture)
		m.set_shader_parameter("has_occ", 1.0)
	return m


static func block_mat(key: String, spec: Dictionary) -> ShaderMaterial:
	var ck := "blockmat:" + key
	if _cache.has(ck):
		return _cache[ck]
	var m := ShaderMaterial.new()
	m.shader = _shader("block", BLOCK_SHADER)
	m.set_shader_parameter("style", spec.get("style", 0))
	m.set_shader_parameter("side_col", spec["side"])
	m.set_shader_parameter("top_col", spec["top"])
	m.set_shader_parameter("rough", spec.get("rough", 0.8))
	m.set_shader_parameter("metal", spec.get("metal", 0.0))
	m.set_shader_parameter("scale", spec.get("scale", 1.0))
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("cell_tex", cell_tex())
	_cache[ck] = m
	return m


static func vmat(key: String, rough := 0.7, metalness := 0.0, grain := 0.22, glow := 2.5) -> ShaderMaterial:
	var ck := "vmat:%s" % key
	if _cache.has(ck):
		return _cache[ck]
	var m := ShaderMaterial.new()
	m.shader = _shader("vcol", VCOL_SHADER)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metalness)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("noise_tex", noise_tex())
	_cache[ck] = m
	return m


static func water_mat(deep: Color, shallow: Color, wave := 0.06) -> ShaderMaterial:
	var ck := "water:%s%s" % [deep.to_html(), shallow.to_html()]
	if _cache.has(ck):
		return _cache[ck]
	var m := ShaderMaterial.new()
	m.shader = _shader("water", WATER_SHADER)
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("shallow", shallow)
	m.set_shader_parameter("wave", wave)
	m.set_shader_parameter("noise_tex", noise_tex())
	_cache[ck] = m
	return m


static func belt_mat() -> ShaderMaterial:
	if _cache.has("belt_mat"):
		return _cache["belt_mat"]
	var m := ShaderMaterial.new()
	m.shader = _shader("belt", BELT_SHADER)
	_cache["belt_mat"] = m
	return m


static func ring_mat(tint: Color, phase: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("ring", RING_SHADER)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("phase", phase)
	return m


static func glow_mat(c: Color, energy := 2.0) -> StandardMaterial3D:
	var ck := "glow:%s:%s" % [c.to_html(), energy]
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_cache[ck] = m
	return m


# ---- Mesh building: a small kit of coloured parts merged into one mesh ------------

## A colour marked as polished metal / glowing for vmat (see VCOL_SHADER).
static func metal(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.5)


static func lit(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.0)


## parts: [mesh, Transform3D, Color or null]. null keeps the mesh's own
## vertex colours (lathe shapes).
static func build(parts: Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var src: Mesh = p[0]
		var tfm: Transform3D = p[1]
		var arr := src.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var own = arr[Mesh.ARRAY_COLOR]
		var keep: bool = p[2] == null and own != null and own.size() == verts.size()
		var c: Color = Color.WHITE if p[2] == null else p[2]
		var idxs = arr[Mesh.ARRAY_INDEX]
		var nb := tfm.basis.inverse().transposed()
		var order: Array = []
		if idxs != null and idxs.size() > 0:
			order = Array(idxs)
		else:
			order = range(verts.size())
		for i in order:
			st.set_color(own[i] if keep else c)
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(tfm * verts[i])
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


static func box(size: Vector3, r := 0.0) -> Mesh:
	var key := "box:%s:%s" % [size, r]
	if _cache.has(key):
		return _cache[key]
	var m: Mesh
	if r > 0.0:
		m = Art.rounded_box(size, r, 2)
	else:
		var b := BoxMesh.new()
		b.size = size
		m = b
	_cache[key] = m
	return m


static func cyl(r_top: float, r_bot: float, h: float, seg := 12) -> Mesh:
	var key := "cyl:%s:%s:%s:%s" % [r_top, r_bot, h, seg]
	if _cache.has(key):
		return _cache[key]
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	_cache[key] = c
	return c


static func sphere(r: float, seg := 14, rings := 8) -> Mesh:
	var key := "sph:%s:%s" % [r, seg]
	if _cache.has(key):
		return _cache[key]
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	_cache[key] = s
	return s


static func cone(r: float, h: float, seg := 10) -> Mesh:
	return cyl(0.001, r, h, seg)


static func xf(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


# ---- Walls -------------------------------------------------------------------------------

static func pillar_mesh(id: String) -> ArrayMesh:
	var key := "pillar:" + id
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = THEMES[id]["block"]
	var m: ArrayMesh
	match spec["style"]:
		0:
			m = Art.rounded_box(Vector3(0.94, 0.98, 0.94), 0.2, 4, 0.06, 17)
		_:
			m = Art.rounded_box(Vector3(0.95, 0.98, 0.95), 0.05, 3)
	m.surface_set_material(0, block_mat(id + "_pillar", spec))
	_cache[key] = m
	return m


static func border_mesh(id: String, variant: int) -> ArrayMesh:
	var key := "border:%s:%d" % [id, variant]
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = THEMES[id]["border"]
	var m: ArrayMesh
	match spec["style"]:
		0:
			m = Art.rounded_box(Vector3(1.04, 1.06, 1.04), 0.26, 4, 0.09, 130 + variant * 11)
		_:
			m = Art.rounded_box(Vector3(1.0, 1.04, 1.0), 0.04, 3)
	m.surface_set_material(0, block_mat(id + "_border", spec))
	_cache[key] = m
	return m


## The block that drops in Sudden Death.
static func drop_block_mesh(id: String) -> Mesh:
	if id == "forest":
		return Art.boulder_mesh(0)
	return border_mesh(id, 0)


## Clockwork wall section: three copper blocks on a common pivot, gears on top.
static func clockwork_mesh() -> ArrayMesh:
	if _cache.has("clockwork"):
		return _cache["clockwork"]
	var copper := Color("7c5a40")
	var dark := Color("5a2c12")
	var brass := metal(Color("8a6a40"))
	var parts: Array = []
	for i in 3:
		var x := float(i - 1)
		parts.append([box(Vector3(0.94, 0.9, 0.94), 0.06), xf(Vector3(x, 0.45, 0)), copper])
		parts.append([box(Vector3(0.98, 0.08, 0.98), 0.02), xf(Vector3(x, 0.06, 0)), dark])
		parts.append([box(Vector3(0.8, 0.03, 0.8), 0.01), xf(Vector3(x, 0.905, 0)), Color("5e4030")])
		for s in [-1.0, 1.0]:
			for k in 3:
				parts.append([sphere(0.03, 8, 4), xf(Vector3(x - 0.3 + k * 0.3, 0.75, s * 0.475)), brass])
	parts.append([box(Vector3(2.9, 0.12, 0.3), 0.04), xf(Vector3(0, 0.95, 0)), dark])
	var m := build(parts, vmat("clockwork", 0.6, 0.0, 0.3))
	_cache["clockwork"] = m
	return m


static func gear_mesh(r: float, teeth: int) -> ArrayMesh:
	var key := "gear:%s:%d" % [r, teeth]
	if _cache.has(key):
		return _cache[key]
	var brass := metal(Color("8a6a40"))
	var parts: Array = [[cyl(r, r, 0.06, 20), xf(Vector3.ZERO), brass],
		[cyl(r * 0.3, r * 0.3, 0.09, 10), xf(Vector3.ZERO), Color("6a3a16")]]
	for i in teeth:
		var a := TAU * i / teeth
		parts.append([box(Vector3(r * 0.28, 0.06, r * 0.3)), xf(Vector3(cos(a), 0, sin(a)) * r, Vector3(0, -a, 0)), brass])
	var m := build(parts, vmat("gear", 0.6, 0.0, 0.2))
	_cache[key] = m
	return m


# ---- Crates (the destructible blocks), one or two variants per level ----------------

static func crate_meshes(id: String) -> Array:
	var key := "crates:" + id
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	match id:
		"forest":
			out = [Art.log_pile_mesh(0), Art.log_pile_mesh(1), Art.log_pile_mesh(2)]
		"beach":
			# Sun-bleached driftwood crates and rope-bound barrels.
			out = [plank_crate("beach", Color("9a6c44"), Color("7a5a3c"), Color("3e2c1e")), barrel("beach")]
		"haunted":
			out = [casket(), trunk()]
		"factory":
			out = [pallet(), drums(), banded_crate()]
	_cache[key] = out
	return out


## A framed plank crate: slatted faces, darker edge frame, a diagonal brace.
static func plank_crate(key: String, light: Color, mid: Color, edge: Color) -> ArrayMesh:
	var parts: Array = []
	var s := 0.84
	var h := 0.8
	parts.append([box(Vector3(s - 0.04, h - 0.04, s - 0.04)), xf(Vector3(0, h * 0.5, 0)), mid.darkened(0.25)])
	# slats on each side face
	for side in 4:
		var yaw := side * PI / 2.0
		var nrm := Vector3(sin(yaw), 0, cos(yaw))
		for k in 3:
			var y := 0.17 + k * 0.23
			var c := light if (k + side) % 2 == 0 else light.lerp(mid, 0.5)
			parts.append([box(Vector3(s - 0.1, 0.2, 0.04), 0.01), Transform3D(Basis(Vector3.UP, yaw), nrm * (s * 0.5 - 0.02) + Vector3(0, y, 0)), c])
		parts.append([box(Vector3(0.07, 0.86, 0.03)), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, 0.72), nrm * (s * 0.5 + 0.005) + Vector3(0, h * 0.5, 0)), mid])
	# lid boards
	for k in 4:
		parts.append([box(Vector3(0.19, 0.04, s - 0.08), 0.01), xf(Vector3(-0.3 + k * 0.2, h + 0.005, 0)), light if k % 2 == 0 else light.lerp(mid, 0.4)])
	# frame
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			parts.append([box(Vector3(0.09, h + 0.02, 0.09), 0.015), xf(Vector3(a * (s * 0.5 - 0.02), h * 0.5, b * (s * 0.5 - 0.02))), edge])
		parts.append([box(Vector3(s + 0.02, 0.08, 0.09), 0.015), xf(Vector3(0, h, a * (s * 0.5 - 0.02))), edge])
		parts.append([box(Vector3(0.09, 0.08, s + 0.02), 0.015), xf(Vector3(a * (s * 0.5 - 0.02), h, 0)), edge])
		parts.append([box(Vector3(s + 0.02, 0.08, 0.09), 0.015), xf(Vector3(0, 0.04, a * (s * 0.5 - 0.02))), edge])
		parts.append([box(Vector3(0.09, 0.08, s + 0.02), 0.015), xf(Vector3(a * (s * 0.5 - 0.02), 0.04, 0)), edge])
	return build(parts, vmat("crate_" + key, 0.85, 0.0, 0.35))


## A purple casket: panelled box, a stepped lid with a brass cross, brass corners.
static func casket() -> ArrayMesh:
	var purple := Color("84405a")
	var dark := Color("4a2232")
	var light := Color("a05874")
	var brass := metal(Color("735428"))
	var parts: Array = [
		[box(Vector3(0.8, 0.5, 0.84), 0.04), xf(Vector3(0, 0.29, 0)), purple],
		[box(Vector3(0.86, 0.07, 0.9), 0.02), xf(Vector3(0, 0.04, 0)), dark],
		[box(Vector3(0.86, 0.1, 0.9), 0.03), xf(Vector3(0, 0.58, 0)), dark],
		[box(Vector3(0.7, 0.1, 0.76), 0.04), xf(Vector3(0, 0.67, 0)), light],
		[box(Vector3(0.07, 0.025, 0.42)), xf(Vector3(0, 0.73, 0.02)), brass],
		[box(Vector3(0.26, 0.025, 0.07)), xf(Vector3(0, 0.73, -0.08)), brass],
	]
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			parts.append([box(Vector3(0.12, 0.12, 0.12), 0.02), xf(Vector3(a * 0.4, 0.06, b * 0.42)), brass])
			parts.append([box(Vector3(0.1, 0.1, 0.1), 0.02), xf(Vector3(a * 0.4, 0.6, b * 0.42)), brass])
		# side panels
		parts.append([box(Vector3(0.6, 0.3, 0.02), 0.01), xf(Vector3(0, 0.3, a * 0.425)), dark])
		parts.append([box(Vector3(0.02, 0.3, 0.64), 0.01), xf(Vector3(a * 0.405, 0.3, 0)), dark])
	parts.append([box(Vector3(0.14, 0.06, 0.04), 0.01), xf(Vector3(0, 0.44, 0.44)), brass])
	return build(parts, vmat("casket", 0.55, 0.0, 0.3))


static func pallet() -> ArrayMesh:
	var wood := Color("b48a55")
	var box_c := Color("d0a66c")
	var tape := Color("e6d6b0")
	var parts: Array = []
	for k in 5:
		parts.append([box(Vector3(0.88, 0.035, 0.15)), xf(Vector3(0, 0.12, -0.36 + k * 0.18)), wood])
	for k in 3:
		parts.append([box(Vector3(0.12, 0.09, 0.86)), xf(Vector3(-0.36 + k * 0.36, 0.055, 0)), wood.darkened(0.15)])
	var r := RandomNumberGenerator.new()
	r.seed = 404
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			var hh := r.randf_range(0.6, 0.68)
			var c := box_c.lerp(Color("9c7444"), r.randf() * 0.6)
			parts.append([box(Vector3(0.4, hh, 0.4), 0.025), xf(Vector3(a * 0.21, 0.14 + hh * 0.5, b * 0.21)), c])
			parts.append([box(Vector3(0.41, 0.03, 0.1)), xf(Vector3(a * 0.21, 0.14 + hh + 0.005, b * 0.21)), tape])
	parts.append([box(Vector3(0.38, 0.22, 0.38), 0.02), xf(Vector3(-0.21, 0.93, -0.21)), box_c.lightened(0.08)])
	parts.append([box(Vector3(0.39, 0.025, 0.09)), xf(Vector3(-0.21, 1.045, -0.21)), tape])
	return build(parts, vmat("pallet", 0.8, 0.0, 0.3))


## A barrel bound with rope hoops, for the Beach.
static func barrel(key: String) -> ArrayMesh:
	var wood := Color("8a6440")
	var dark := Color("4e3a28")
	var rope := Color("e6d6aa")
	var parts: Array = [
		[cyl(0.34, 0.34, 0.12, 16), xf(Vector3(0, 0.06, 0)), dark],
		[cyl(0.38, 0.34, 0.32, 16), xf(Vector3(0, 0.27, 0)), wood],
		[cyl(0.34, 0.38, 0.32, 16), xf(Vector3(0, 0.59, 0)), wood],
		[cyl(0.33, 0.33, 0.04, 16), xf(Vector3(0, 0.76, 0)), dark],
		[cyl(0.3, 0.3, 0.02, 16), xf(Vector3(0, 0.775, 0)), wood.lightened(0.15)],
	]
	for y in [0.16, 0.43, 0.7]:
		parts.append([cyl(0.39 if y == 0.43 else 0.37, 0.39 if y == 0.43 else 0.37, 0.05, 16), xf(Vector3(0, y, 0)), rope])
	for k in 10:
		var a := TAU * k / 10.0
		parts.append([box(Vector3(0.012, 0.66, 0.02)), xf(Vector3(cos(a), 0, sin(a)) * 0.375 + Vector3(0, 0.43, 0), Vector3(0, -a, 0)), dark])
	# Seated in a square driftwood frame, so it reads as a full block.
	parts.append([box(Vector3(0.9, 0.08, 0.9), 0.015), xf(Vector3(0, 0.04, 0)), dark])
	for side in 4:
		var yaw := side * PI / 2.0
		var nrm := Vector3(sin(yaw), 0, cos(yaw))
		parts.append([box(Vector3(0.9, 0.07, 0.06), 0.01), Transform3D(Basis(Vector3.UP, yaw), nrm * 0.42 + Vector3(0, 0.78, 0)), wood.darkened(0.1)])
	for cx in [-0.42, 0.42]:
		for cz in [-0.42, 0.42]:
			parts.append([box(Vector3(0.07, 0.8, 0.07), 0.01), xf(Vector3(cx, 0.4, cz)), dark])
	return build(parts, vmat("barrel_" + key, 0.85, 0.0, 0.35))


## An old travelling trunk: domed lid, iron straps, a lock plate.
static func trunk() -> ArrayMesh:
	var wood := Color("7a5236")
	var lid := Color("8e6342")
	var iron := metal(Color("8a8490"))
	var brass := metal(Color("b8955a"))
	var parts: Array = [
		[box(Vector3(0.84, 0.48, 0.66), 0.03), xf(Vector3(0, 0.25, 0)), wood],
		[cyl(0.33, 0.33, 0.84, 16), xf(Vector3(0, 0.49, 0), Vector3(0, 0, PI / 2.0), Vector3(1, 0.62, 1)), lid],
		[box(Vector3(0.88, 0.05, 0.7), 0.01), xf(Vector3(0, 0.49, 0)), iron],
		[box(Vector3(0.14, 0.16, 0.03), 0.01), xf(Vector3(0, 0.44, 0.34)), brass],
	]
	for x in [-0.3, 0.3]:
		parts.append([box(Vector3(0.07, 0.5, 0.7), 0.01), xf(Vector3(x, 0.25, 0)), iron])
		parts.append([cyl(0.345, 0.345, 0.07, 16), xf(Vector3(x, 0.49, 0), Vector3(0, 0, PI / 2.0), Vector3(1, 0.62, 1)), iron])
	return build(parts, vmat("trunk", 0.7, 0.0, 0.35))


## Four oil drums on a pallet, for the Factory.
static func drums() -> ArrayMesh:
	var wood := Color("a8814e")
	var cols := [Color("a83a2e"), Color("2f5a8a"), Color("a83a2e"), Color("5a6470")]
	var rim := metal(Color("8a9099"))
	var parts: Array = []
	for k in 5:
		parts.append([box(Vector3(0.88, 0.035, 0.15)), xf(Vector3(0, 0.12, -0.36 + k * 0.18)), wood])
	for k in 3:
		parts.append([box(Vector3(0.12, 0.09, 0.86)), xf(Vector3(-0.36 + k * 0.36, 0.055, 0)), wood.darkened(0.15)])
	var i := 0
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			var p := Vector3(a * 0.21, 0.14, b * 0.21)
			parts.append([cyl(0.19, 0.19, 0.62, 14), xf(p + Vector3(0, 0.31, 0)), cols[i]])
			parts.append([cyl(0.2, 0.2, 0.03, 14), xf(p + Vector3(0, 0.2, 0)), rim])
			parts.append([cyl(0.2, 0.2, 0.03, 14), xf(p + Vector3(0, 0.44, 0)), rim])
			parts.append([cyl(0.17, 0.17, 0.02, 14), xf(p + Vector3(0, 0.625, 0)), cols[i].darkened(0.3)])
			parts.append([cyl(0.03, 0.03, 0.02, 8), xf(p + Vector3(0.08, 0.635, 0.05)), rim])
			i += 1
	# Shrink-wrap band round the four, and the strap that ties them.
	for side in 4:
		var yaw := side * PI / 2.0
		var nrm := Vector3(sin(yaw), 0, cos(yaw))
		parts.append([box(Vector3(0.82, 0.22, 0.02)), Transform3D(Basis(Vector3.UP, yaw), nrm * 0.405 + Vector3(0, 0.46, 0)), Color(0.75, 0.8, 0.85)])
		parts.append([box(Vector3(0.84, 0.04, 0.025)), Transform3D(Basis(Vector3.UP, yaw), nrm * 0.41 + Vector3(0, 0.62, 0)), Color("d0a020")])
	return build(parts, vmat("drums", 0.55, 0.0, 0.25))


## A wooden shipping crate with steel corner bands, for the Factory.
static func banded_crate() -> ArrayMesh:
	var wood := Color("9c7a4c")
	var light := Color("b8956a")
	var steel := metal(Color("7a828c"))
	var parts: Array = [[box(Vector3(0.84, 0.8, 0.84), 0.02), xf(Vector3(0, 0.4, 0)), wood]]
	for side in 4:
		var yaw := side * PI / 2.0
		var nrm := Vector3(sin(yaw), 0, cos(yaw))
		for k in 4:
			parts.append([box(Vector3(0.76, 0.17, 0.02), 0.005), Transform3D(Basis(Vector3.UP, yaw), nrm * 0.425 + Vector3(0, 0.12 + k * 0.19, 0)), light if (k + side) % 2 == 0 else wood])
		parts.append([box(Vector3(0.6, 0.06, 0.02)), Transform3D(Basis(Vector3.UP, yaw), nrm * 0.437 + Vector3(0, 0.62, 0)), Color("2a2a2a")])
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			parts.append([box(Vector3(0.1, 0.82, 0.1), 0.01), xf(Vector3(a * 0.41, 0.41, b * 0.41)), steel])
	parts.append([box(Vector3(0.86, 0.03, 0.86), 0.01), xf(Vector3(0, 0.805, 0)), light])
	return build(parts, vmat("banded_crate", 0.75, 0.0, 0.35))
