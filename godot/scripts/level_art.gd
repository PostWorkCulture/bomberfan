extends RefCounted
## Procedural art for the seven arenas beyond the Forest: floors, walls,
## crates, the ground outside and the bases under shaped decks. Everything
## is generated in code and cached, like art.gd. Props on the walls and the
## hazard throwers live in level_props.gd.

const Art := preload("res://scripts/art.gd")
const Cfg := preload("res://scripts/config.gd")

static var _cache := {}

# ---- Palettes (from LEVELS in index.html, deepened for real lighting) -------------

const THEMES := {
	"beach": {
		"sky": Color("07293f"), "fog": Color(0.42, 0.66, 0.78), "fog_begin": 22.0, "fog_end": 48.0,
		"sun": Color(1.0, 0.95, 0.84), "sun_energy": 1.1, "sun_rot": Vector3(-56, -32, 0), "ambient": 0.5,
		"sky_top": Color(0.3, 0.55, 0.85), "sky_horizon": Color(0.78, 0.86, 0.9),
		"floor": {"pattern": 1, "a": Color("2a8cbd"), "b": Color("4cb0d6"), "line": Color(1, 1, 1), "line_alpha": 0.16, "rough": 0.12},
		"block": {"style": 0, "side": Color("d9604c"), "top": Color("ff9c84"), "rough": 0.75, "scale": 0.9},
		"border": {"style": 0, "side": Color("a8442f"), "top": Color("e07a63"), "rough": 0.8, "scale": 0.9},
		"plinth": Color("e7cf9c"), "debris": Color("e8b84a"),
	},
	"glacier": {
		"sky": Color("0d1b2e"), "fog": Color(0.16, 0.24, 0.36), "fog_begin": 18.0, "fog_end": 40.0,
		"sun": Color(0.86, 0.92, 1.0), "sun_energy": 1.15, "sun_rot": Vector3(-48, -40, 0), "ambient": 0.6,
		"sky_top": Color(0.2, 0.32, 0.5), "sky_horizon": Color(0.6, 0.72, 0.84),
		"floor": {"pattern": 2, "a": Color("6fa4c9"), "b": Color("9cc6e2"), "line": Color("0f2d55"), "line_alpha": 0.24, "rough": 0.22},
		"block": {"style": 4, "side": Color("1d3a63"), "top": Color("3f6ea8"), "rough": 0.12, "scale": 0.6},
		"border": {"style": 4, "side": Color("122642"), "top": Color("36609e"), "rough": 0.15, "scale": 0.6},
		"plinth": Color("dfeefa"), "debris": Color("dff0ff"),
	},
	"haunted": {
		"sky": Color("0a0512"), "fog": Color(0.12, 0.06, 0.18), "fog_begin": 15.0, "fog_end": 34.0,
		"sun": Color(0.82, 0.78, 1.0), "sun_energy": 0.85, "sun_rot": Vector3(-58, -150, 0), "ambient": 0.55,
		"sky_top": Color(0.08, 0.05, 0.16), "sky_horizon": Color(0.3, 0.2, 0.38),
		"floor": {"pattern": 3, "a": Color("1d1424"), "b": Color("2c2033"), "line": Color("a878ff"), "line_alpha": 0.13, "rough": 0.8, "plank": 0.25},
		"block": {"style": 1, "side": Color("d06a14"), "top": Color("f0943a"), "rough": 0.85, "scale": 1.0},
		"border": {"style": 1, "side": Color("8a460c"), "top": Color("c0701e"), "rough": 0.9, "scale": 1.0},
		"plinth": Color("3a2c33"), "debris": Color("9a5cf0"),
	},
	"haunted-train": {
		"sky": Color("020409"), "fog": Color(0.05, 0.08, 0.12), "fog_begin": 16.0, "fog_end": 36.0,
		"sun": Color(0.75, 0.86, 0.96), "sun_energy": 1.0, "sun_rot": Vector3(-55, -25, 0), "ambient": 0.7,
		"sky_top": Color(0.12, 0.16, 0.24), "sky_horizon": Color(0.3, 0.38, 0.46),
		"floor": {"pattern": 3, "a": Color("2c3642"), "b": Color("3d4a58"), "line": Color("84b0c2"), "line_alpha": 0.17, "rough": 0.7, "plank": 0.5, "metal": 0.1},
		"block": {"style": 2, "side": Color("3a4c5e"), "top": Color("62788c"), "rough": 0.5, "metal": 0.3, "scale": 1.0},
		"border": {"style": 2, "side": Color("1c2630"), "top": Color("3a4b5a"), "rough": 0.5, "metal": 0.3, "scale": 1.0},
		"plinth": Color("1b2129"), "debris": Color("607583"),
	},
	"factory": {
		"sky": Color("0f1116"), "fog": Color(0.1, 0.11, 0.13), "fog_begin": 18.0, "fog_end": 40.0,
		"sun": Color(1.0, 0.95, 0.86), "sun_energy": 1.05, "sun_rot": Vector3(-62, -30, 0), "ambient": 0.55,
		"sky_top": Color(0.16, 0.18, 0.22), "sky_horizon": Color(0.36, 0.37, 0.4),
		"floor": {"pattern": 4, "a": Color("2a2e36"), "b": Color("363b45"), "line": Color("ffd60a"), "line_alpha": 0.18, "rough": 0.5, "metal": 0.55},
		"block": {"style": 2, "side": Color("707d8f"), "top": Color("9aa5b5"), "rough": 0.42, "metal": 0.75, "scale": 1.0},
		"border": {"style": 5, "side": Color("3a424e"), "top": Color("ffcc1a"), "rough": 0.5, "metal": 0.6, "scale": 1.0},
		"plinth": Color("4a4f58"), "debris": Color("e08a1e"),
	},
	"circuit": {
		"sky": Color("090620"), "fog": Color(0.06, 0.04, 0.16), "fog_begin": 16.0, "fog_end": 38.0,
		"sun": Color(0.85, 0.85, 1.0), "sun_energy": 0.85, "sun_rot": Vector3(-60, -35, 0), "ambient": 0.5,
		"sky_top": Color(0.06, 0.04, 0.18), "sky_horizon": Color(0.2, 0.14, 0.4),
		"floor": {"pattern": 5, "a": Color("181230"), "b": Color("221a42"), "line": Color("78f0ff"), "line_alpha": 0.3, "rough": 0.35, "metal": 0.3},
		"block": {"style": 3, "side": Color("1d5a78"), "top": Color("2f8fb8"), "rough": 0.3, "metal": 0.2, "glow": Color("6ef0ff"), "scale": 1.0},
		"border": {"style": 3, "side": Color("12344a"), "top": Color("1b4f66"), "rough": 0.35, "metal": 0.4, "glow": Color("6ef0ff"), "scale": 1.0},
		"plinth": Color("120d26"), "debris": Color("ff3fa4"),
	},
	"pirate": {
		"sky": Color("031b35"), "fog": Color(0.12, 0.28, 0.42), "fog_begin": 20.0, "fog_end": 46.0,
		"sun": Color(1.0, 0.93, 0.8), "sun_energy": 1.25, "sun_rot": Vector3(-52, -36, 0), "ambient": 0.6,
		"sky_top": Color(0.22, 0.42, 0.7), "sky_horizon": Color(0.7, 0.8, 0.86),
		"floor": {"pattern": 3, "a": Color("8a5226"), "b": Color("a8683a"), "line": Color("ffd67e"), "line_alpha": 0.2, "rough": 0.75, "plank": 0.25},
		"block": {"style": 6, "side": Color("254860"), "top": Color("4c8aa7"), "rough": 0.6, "scale": 1.0},
		"border": {"style": 6, "side": Color("522713"), "top": Color("7d401c"), "rough": 0.7, "scale": 1.0},
		"plinth": Color("3d1d10"), "debris": Color("d99a42"),
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
uniform sampler2D cell_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D mask_tex : filter_nearest;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = wpos.xz + grid * 0.5;
	if (texture(mask_tex, g / grid).r < 0.5) discard;
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
	} else if (pattern == 2) {
		// Glacial ice: pale sheet with cracks and frosted tile seams.
		float cr = texture(cell_tex, wpos.xz * 0.35).r;
		float crack = 1.0 - smoothstep(0.0, 0.06, cr);
		col *= 1.0 - 0.05 * chk;
		col = mix(col, vec3(0.92, 0.97, 1.0), smoothstep(0.5, 1.0, texture(noise_tex, wpos.xz * 0.45).r) * 0.22);
		col = mix(col, line_col, crack * 0.35);
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
		// Circuit board: dark substrate, glowing traces and solder pads.
		float h = hash(cell);
		vec2 c = f - 0.5;
		float tx = (1.0 - smoothstep(0.018, 0.03, abs(c.y - (h - 0.5) * 0.5))) * step(0.5, fract(h * 7.0));
		float ty = (1.0 - smoothstep(0.018, 0.03, abs(c.x - (fract(h * 13.0) - 0.5) * 0.5))) * step(0.5, fract(h * 3.0));
		float pad = 1.0 - smoothstep(0.045, 0.06, length(c - vec2((h - 0.5) * 0.5, (fract(h * 13.0) - 0.5) * 0.5)));
		float trace = clamp(tx + ty + pad, 0.0, 1.0);
		float pulse = 0.55 + 0.45 * sin(TIME * 1.8 + (cell.x + cell.y) * 0.7);
		col *= 1.0 - 0.08 * chk;
		col = mix(col, line_col * 0.35, trace * 0.6);
		emit += line_col * (trace * 0.35 * pulse + line * line_alpha * 0.9);
		col = mix(col, line_col, line * line_alpha);
	}
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
uniform vec3 glow_col : source_color = vec3(0.0);
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform float scale = 1.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D cell_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
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
	vec3 emit = vec3(0.0);
	vec3 ap = abs(lpos);
	float edges = step(0.38, ap.x) + step(0.38, ap.z) + step(0.38, abs(lpos.y));
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
	} else if (style == 3) {
		// Dark tech block with glowing edges.
		float e = step(1.5, edges);
		float pulse = 0.75 + 0.25 * sin(TIME * 2.0 + wpos.x * 0.6 + wpos.z * 0.4);
		col = mix(col * 0.55, glow_col, e * 0.6);
		emit = glow_col * e * 0.9 * pulse;
		float grid = smoothstep(0.47, 0.5, abs(fract(luv.x * 4.0) - 0.5)) + smoothstep(0.47, 0.5, abs(fract(luv.y * 4.0) - 0.5));
		emit += glow_col * clamp(grid, 0.0, 1.0) * 0.12 * top;
	} else if (style == 4) {
		// Ice: glassy, with frosted cracks and a cold rim.
		float c = texture(cell_tex, uv * 0.9 * scale).r;
		float crack = 1.0 - smoothstep(0.0, 0.05, c);
		col = mix(col, vec3(0.75, 0.9, 1.0), crack * 0.5 + top * 0.15);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		emit = mix(side_col, vec3(0.6, 0.85, 1.0), 0.6) * fres * 0.45;
		r = rough + crack * 0.4;
	} else if (style == 5) {
		// Steel with a hazard-striped cap.
		float stripe = step(0.5, fract((wpos.x + wpos.z) * 2.2));
		vec3 haz = mix(top_col, vec3(0.06), stripe);
		col = mix(side_col * (0.85 + 0.3 * n2), haz, top);
		vec2 pf = fract(luv * 2.0 + 0.5);
		col *= 1.0 - 0.3 * smoothstep(0.46, 0.5, max(abs(pf.x - 0.5), abs(pf.y - 0.5))) * (1.0 - top);
		m = mix(metal, 0.1, top);
		r = mix(rough, 0.6, top);
	} else if (style == 6) {
		// Painted planking with dark seams.
		float v = luv.y * 5.0;
		float seam = smoothstep(0.42, 0.5, abs(fract(v) - 0.5));
		float bh = hash(vec2(floor(v), floor(wpos.x * 0.5 + wpos.z * 0.5)));
		float grain = texture(noise_tex, vec2(uv.x * 0.4, uv.y * 6.0)).r;
		col *= (0.85 + 0.2 * bh) * (0.88 + 0.2 * grain);
		col *= 1.0 - 0.5 * seam * (1.0 - top);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
	EMISSION = emit;
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
uniform vec3 arrow_col : source_color = vec3(1.0, 0.8, 0.05);
uniform float speed = 1.5;
void fragment() {
	// UV.x runs along the direction of travel (the mesh is rotated per tile).
	float u = UV.x - TIME * speed;
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

const PAD_SHADER := """
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


static func floor_mat(id: String, mask: Texture2D, edge_shadow: float) -> ShaderMaterial:
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
	m.set_shader_parameter("cell_tex", cell_tex())
	m.set_shader_parameter("mask_tex", mask)
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
	m.set_shader_parameter("glow_col", spec.get("glow", Color.BLACK))
	m.set_shader_parameter("rough", spec.get("rough", 0.8))
	m.set_shader_parameter("metal", spec.get("metal", 0.0))
	m.set_shader_parameter("scale", spec.get("scale", 1.0))
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("cell_tex", cell_tex())
	_cache[ck] = m
	return m


static func vmat(key: String, rough := 0.7, metal := 0.0, grain := 0.22, glow := 2.5) -> ShaderMaterial:
	var ck := "vmat:%s" % key
	if _cache.has(ck):
		return _cache[ck]
	var m := ShaderMaterial.new()
	m.shader = _shader("vcol", VCOL_SHADER)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
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


static func pad_mat(tint: Color, phase: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("pad", PAD_SHADER)
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
		var xf: Transform3D = p[1]
		var arr := src.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var own = arr[Mesh.ARRAY_COLOR]
		var keep: bool = p[2] == null and own != null and own.size() == verts.size()
		var c: Color = Color.WHITE if p[2] == null else p[2]
		var idxs = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		var order: Array = []
		if idxs != null and idxs.size() > 0:
			order = Array(idxs)
		else:
			order = range(verts.size())
		for i in order:
			st.set_color(own[i] if keep else c)
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
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
		4:
			m = Art.rounded_box(Vector3(0.92, 1.0, 0.92), 0.06, 3, 0.02, 23)
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
		4:
			m = Art.rounded_box(Vector3(1.0, 1.08, 1.0), 0.08, 3, 0.03, 140 + variant)
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
	var copper := Color("c8763a")
	var dark := Color("5a2c12")
	var brass := metal(Color("e0a84a"))
	var parts: Array = []
	for i in 3:
		var x := float(i - 1)
		parts.append([box(Vector3(0.94, 0.9, 0.94), 0.06), xf(Vector3(x, 0.45, 0)), copper])
		parts.append([box(Vector3(0.98, 0.08, 0.98), 0.02), xf(Vector3(x, 0.06, 0)), dark])
		parts.append([box(Vector3(0.98, 0.06, 0.98), 0.02), xf(Vector3(x, 0.88, 0)), dark])
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
	var brass := metal(Color("e0a84a"))
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
		"beach":
			out = [plank_crate("beach", Color("ffd35c"), Color("f0ad2b"), Color("c2810f"))]
		"glacier":
			out = [ice_block()]
		"haunted":
			out = [casket()]
		"haunted-train":
			out = [trunk(Color("3c4c5c"), Color("9ab4c4")), trunk(Color("5a3c2a"), Color("c09a5a"))]
		"factory":
			out = [pallet()]
		"circuit":
			out = [chip_block()]
		"pirate":
			out = [plank_crate("pirate", Color("d99a42"), Color("b7782e"), Color("3d1d10")), barrel()]
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


static func ice_block() -> ArrayMesh:
	var m := Art.rounded_box(Vector3(0.86, 0.82, 0.86), 0.1, 3, 0.025, 55)
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.41
	arr[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.surface_set_material(0, block_mat("ice_crate", {"style": 4, "side": Color("cfe4f7"), "top": Color("f2f9ff"), "rough": 0.1, "scale": 1.3}))
	return out


## A purple casket: panelled box, a stepped lid with a brass cross, brass corners.
static func casket() -> ArrayMesh:
	var purple := Color("9a4ae8")
	var dark := Color("5a1fa8")
	var light := Color("b47aff")
	var brass := metal(Color("e0b860"))
	var parts: Array = [
		[box(Vector3(0.8, 0.5, 0.84), 0.04), xf(Vector3(0, 0.29, 0)), purple],
		[box(Vector3(0.86, 0.07, 0.9), 0.02), xf(Vector3(0, 0.04, 0)), dark],
		[box(Vector3(0.86, 0.1, 0.9), 0.03), xf(Vector3(0, 0.58, 0)), dark],
		[box(Vector3(0.7, 0.1, 0.76), 0.04), xf(Vector3(0, 0.67, 0)), light],
		[box(Vector3(0.1, 0.03, 0.56)), xf(Vector3(0, 0.73, 0.02)), brass],
		[box(Vector3(0.36, 0.03, 0.1)), xf(Vector3(0, 0.73, -0.1)), brass],
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


static func trunk(body: Color, trim: Color) -> ArrayMesh:
	var m := metal(trim)
	var parts: Array = [
		[box(Vector3(0.86, 0.66, 0.78), 0.05), xf(Vector3(0, 0.34, 0)), body],
		[box(Vector3(0.88, 0.08, 0.8), 0.02), xf(Vector3(0, 0.56, 0)), body.darkened(0.3)],
	]
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			parts.append([box(Vector3(0.1, 0.7, 0.1), 0.02), xf(Vector3(a * 0.41, 0.35, b * 0.37)), m])
		parts.append([box(Vector3(0.06, 0.68, 0.8)), xf(Vector3(a * 0.22, 0.35, 0)), m.darkened(0.2)])
	parts.append([box(Vector3(0.14, 0.12, 0.04), 0.02), xf(Vector3(0, 0.5, 0.4)), metal(Color("c9a14a"))])
	parts.append([box(Vector3(0.3, 0.05, 0.08), 0.02), xf(Vector3(0, 0.71, 0)), Color("2a1c14")])
	return build(parts, vmat("trunk", 0.7, 0.0, 0.25))


static func pallet() -> ArrayMesh:
	var wood := Color("b58a52")
	var box_c := Color("e08a1e")
	var tape := Color("f2d28a")
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
			var c := box_c.lerp(Color("b3651b"), r.randf() * 0.5)
			parts.append([box(Vector3(0.4, hh, 0.4), 0.025), xf(Vector3(a * 0.21, 0.14 + hh * 0.5, b * 0.21)), c])
			parts.append([box(Vector3(0.41, 0.03, 0.1)), xf(Vector3(a * 0.21, 0.14 + hh + 0.005, b * 0.21)), tape])
	return build(parts, vmat("pallet", 0.8, 0.0, 0.3))


static func chip_block() -> ArrayMesh:
	var m := Art.rounded_box(Vector3(0.86, 0.8, 0.86), 0.06, 2)
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.4
	arr[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.surface_set_material(0, block_mat("chip_crate", {"style": 3, "side": Color("d41f80"), "top": Color("ff3fa4"),
		"glow": Color("ff6ec0"), "rough": 0.3, "metal": 0.2}))
	return out


static func barrel() -> ArrayMesh:
	var wood := Color("9a5a28")
	var wood2 := Color("b77a40")
	var hoop := metal(Color("4a4640"))
	var parts: Array = [
		[cyl(0.37, 0.31, 0.26, 16), xf(Vector3(0, 0.13, 0)), wood],
		[cyl(0.37, 0.37, 0.26, 16), xf(Vector3(0, 0.39, 0)), wood2],
		[cyl(0.31, 0.37, 0.26, 16), xf(Vector3(0, 0.65, 0)), wood],
		[cyl(0.3, 0.3, 0.02, 16), xf(Vector3(0, 0.785, 0)), Color("c48a4e")],
		[cyl(0.33, 0.33, 0.05, 16), xf(Vector3(0, 0.08, 0)), hoop],
		[cyl(0.33, 0.33, 0.05, 16), xf(Vector3(0, 0.72, 0)), hoop],
		[cyl(0.38, 0.38, 0.05, 16), xf(Vector3(0, 0.39, 0)), hoop],
		[cyl(0.05, 0.05, 0.03, 8), xf(Vector3(0.15, 0.8, 0.05)), Color("3a2410")],
	]
	return build(parts, vmat("barrel", 0.8, 0.0, 0.35))
