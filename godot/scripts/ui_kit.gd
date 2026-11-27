extends RefCounted
## Shared look for the front end, the select screen and the in-match menus
## (2026-11-27): a 90s arcade feel at modern quality. Chunky skewed buttons in
## bright colours with a raised lip, neon glows, animated shader backdrops and
## three OFL fonts (Lilita One for titles, Russo One for the interface, Press
## Start 2P for the arcade labels: 1P, TIME, PRESS START).

const TITLE := preload("res://assets/fonts/lilita-one.ttf")
const UI := preload("res://assets/fonts/russo-one.ttf")
const PIXEL := preload("res://assets/fonts/press-start-2p.ttf")
const Showcase := preload("res://scripts/showcase.gd")
const Art := preload("res://scripts/art.gd")

const PINK := Color(1.0, 0.24, 0.55)
const CYAN := Color(0.13, 0.83, 0.93)
const YELLOW := Color(1.0, 0.82, 0.25)
const ORANGE := Color(1.0, 0.54, 0.12)
const PURPLE := Color(0.55, 0.36, 0.96)
const LIME := Color(0.49, 1.0, 0.31)
const RED := Color(1.0, 0.27, 0.27)
const INK := Color(0.04, 0.02, 0.1)
const NIGHT := Color(0.07, 0.03, 0.17)

## Called with a sound name ("ui_move", "ui_select", ...) by every widget.
static var sound := Callable()


static func play(name: String) -> void:
	if sound.is_valid():
		sound.call(name)


static func label(text: String, font: Font, size: int, col: Color, outline := 0,
		outline_col := Color(0.03, 0.02, 0.08, 0.95), shadow := Vector2.ZERO) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = outline_col
	if shadow != Vector2.ZERO:
		ls.shadow_color = Color(0, 0, 0, 0.55)
		ls.shadow_offset = shadow
		ls.shadow_size = maxi(1, outline / 2)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, radius := 12, border := Color(0, 0, 0, 0), bw := 0, skew := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	if bw > 0:
		sb.set_border_width_all(bw)
	sb.skew = Vector2(skew, 0)
	sb.anti_aliasing = true
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## A big arcade button: skewed, a darker lip along the bottom so it looks
## raised, white border and a coloured glow when focused. Focus follows the
## mouse, so keyboard, pad and pointer all drive the same highlight.
static func button(text: String, col: Color, min_size := Vector2(380, 66), font_size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", UI)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_outline_color", col.darkened(0.7))
	b.add_theme_constant_override("outline_size", 8)
	var normal := box(col.darkened(0.12), 12, col.darkened(0.5), 0, -0.18)
	normal.border_width_bottom = 7
	normal.shadow_color = Color(0, 0, 0, 0.45)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 5)
	var hot := box(col.lightened(0.12), 12, Color(1, 1, 1), 4, -0.18)
	hot.border_width_bottom = 8
	hot.border_color = Color(1, 1, 1)
	hot.shadow_color = Color(col.r, col.g, col.b, 0.75)
	hot.shadow_size = 22
	var down := box(col.darkened(0.3), 12, Color(1, 1, 1), 4, -0.18)
	down.border_width_bottom = 3
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)
	b.add_theme_stylebox_override("hover_pressed", down)
	b.add_theme_stylebox_override("pressed", down)
	b.mouse_entered.connect(func():
		if not b.is_visible_in_tree() or b.disabled:
			return
		if b.focus_mode == Control.FOCUS_NONE:   # pointer-only buttons still answer
			play("ui_move")
			pop(b, 1.07, true)
		else:
			b.grab_focus())
	b.mouse_exited.connect(func():
		if b.focus_mode == Control.FOCUS_NONE:
			pop(b, 1.0, true))
	b.focus_entered.connect(func():
		play("ui_move")
		pop(b, 1.07, true))
	b.focus_exited.connect(func(): pop(b, 1.0, true))
	b.pressed.connect(func(): play("ui_select"))
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	return b


## Scale a control to `s` with a springy ease (stay = keep the new scale).
static func pop(c: Control, s: float, stay := false) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if stay:
		tw.tween_property(c, "scale", Vector2(s, s), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(c, "scale", Vector2(s, s), 0.07)
		tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Animated backdrop: a deep gradient, slow diagonal stripes, a synthwave
## grid floor scrolling towards you and a vignette. `accent` tints the
## stripes and grid (the select screen sets it to the hovered fighter).
const BACKDROP_SHADER := """
shader_type canvas_item;
uniform vec4 top : source_color = vec4(0.07, 0.03, 0.18, 1.0);
uniform vec4 bottom : source_color = vec4(0.36, 0.04, 0.34, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.24, 0.55, 1.0);
uniform float grid = 1.0;
uniform float alpha = 1.0;
uniform float aspect = 1.7778;
void fragment() {
	vec2 uv = UV;
	vec3 c = mix(top.rgb, bottom.rgb, smoothstep(0.0, 1.0, uv.y * 0.9 + uv.x * 0.15));
	float s = smoothstep(0.45, 0.55, fract((uv.x * aspect + uv.y) * 7.0 - TIME * 0.25));
	c += accent.rgb * s * 0.045;
	float hz = 0.66;
	if (grid > 0.0 && uv.y > hz) {
		float d = uv.y - hz;
		float x = (uv.x - 0.5) * aspect / d;
		float z = 1.0 / d + TIME * 2.2;
		float lx = 1.0 - smoothstep(0.0, 0.06 / d * 0.02 + 0.03, abs(fract(x * 0.9) - 0.5) * 2.0 * 0.5);
		float lz = 1.0 - smoothstep(0.0, 0.08, abs(fract(z * 0.25) - 0.5));
		float line = max(lx, lz) * smoothstep(0.0, 0.12, d);
		c = mix(c, accent.rgb * 1.2, line * 0.55 * grid);
		c += accent.rgb * 0.18 * smoothstep(0.06, 0.0, d) * grid;
	}
	vec2 v = (uv - 0.5) * vec2(1.5, 1.0);
	c *= mix(0.5, 1.05, smoothstep(1.1, 0.2, length(v)));
	COLOR = vec4(c, alpha);
}
"""


static func backdrop(accent := PINK, grid := 1.0) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BACKDROP_SHADER
	m.shader = sh
	m.set_shader_parameter("accent", accent)
	m.set_shader_parameter("grid", grid)
	r.material = m
	return r


## Rotating light rays behind a hero (the select screen's fighter, VS).
const BURST_SHADER := """
shader_type canvas_item;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float rays = 14.0;
uniform float speed = 0.15;
uniform float strength = 0.55;
void fragment() {
	vec2 p = UV - 0.5;
	float a = atan(p.y, p.x) + TIME * speed;
	float r = length(p) * 2.0;
	float ray = smoothstep(0.25, 0.75, 0.5 + 0.5 * sin(a * rays));
	float fall = smoothstep(1.0, 0.0, r);
	float core = smoothstep(0.55, 0.0, r);
	COLOR = vec4(col.rgb, (ray * fall * 0.6 + core * 0.7) * strength);
}
"""


static func burst(col: Color, rays := 14.0) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BURST_SHADER
	m.shader = sh
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("rays", rays)
	r.material = m
	return r


## Vertical two-tone gradient through glyphs: chunky arcade titles.
const GRADIENT_TEXT_SHADER := """
shader_type canvas_item;
uniform vec4 top : source_color = vec4(1.0, 0.95, 0.5, 1.0);
uniform vec4 bottom : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float y0 = 0.0;
uniform float y1 = 80.0;
varying float vy;
void vertex() { vy = VERTEX.y; }
void fragment() {
	vec4 t = texture(TEXTURE, UV) * COLOR;
	float k = clamp((vy - y0) / max(1.0, y1 - y0), 0.0, 1.0);
	vec3 g = mix(top.rgb, bottom.rgb, k);
	// The fill is drawn white: it takes the gradient. The outline and the
	// shadow are dark and keep their own colour.
	float fill = step(2.5, COLOR.r + COLOR.g + COLOR.b);
	COLOR = vec4(mix(t.rgb, g, fill), t.a);
}
"""


static func gradient_title(text: String, size: int, top := Color(1.0, 0.96, 0.55), bottom := Color(1.0, 0.42, 0.08),
		outline := 14) -> Label:
	var l := label(text, TITLE, size, Color(1, 1, 1), outline, Color(0.06, 0.02, 0.12, 1.0), Vector2(0, 7))
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRADIENT_TEXT_SHADER
	m.shader = sh
	m.set_shader_parameter("top", top)
	m.set_shader_parameter("bottom", bottom)
	m.set_shader_parameter("y0", size * 0.15)
	m.set_shader_parameter("y1", size * 1.05)
	l.material = m
	return l


## A fighter rendered once into a small viewport, for tiles and portraits.
## `full` frames the whole body; otherwise head and shoulders.
static func portrait(host: Node, char_id: String, col: Color, px: int, full := false, yaw := 0.35) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var sc = Showcase.new()
	sc.setup(char_id, col)
	sc.rotation.y = yaw
	sc.still = true
	vp.add_child(sc)
	var cam := Camera3D.new()
	vp.add_child(cam)
	if full:
		cam.fov = 30.0
		cam.position = Vector3(0.0, 0.95, 3.6)
		cam.look_at(Vector3(0, 0.72, 0), Vector3.UP)
	else:
		cam.fov = 32.0
		var head: float = sc.HEIGHT * 0.72
		cam.position = Vector3(0.0, head + 0.14, 1.5)
		cam.look_at(Vector3(0, head - 0.02, 0), Vector3.UP)
	stage_lights(vp, col)
	return vp.get_texture()


## Key, fill and a rim in the fighter's colour, on a clear background.
static func stage_lights(vp: Node, col: Color, energy := 1.0) -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 28, 0)
	key.light_energy = 1.35 * energy
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -60, 0)
	fill.light_energy = 0.45 * energy
	fill.light_color = Color(0.75, 0.82, 1.0)
	vp.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 195, 0)
	rim.light_energy = 1.6 * energy
	rim.light_color = col.lightened(0.2)
	vp.add_child(rim)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.52, 0.65)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	we.environment = e
	vp.add_child(we)


## The pick-up's own 3D model rendered once (How to Play).
static func item_icon(host: Node, id: String, px := 72) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var item: Node3D = Art.pickup_model(id)
	vp.add_child(item)
	var glow := item.get_node_or_null("Glow")
	if glow:
		glow.visible = false
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0.75, 1.25)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.42, 0), Vector3.UP)
	stage_lights(vp, Color(1, 1, 1))
	return vp.get_texture()


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c
