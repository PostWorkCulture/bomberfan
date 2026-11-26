extends CanvasLayer
## The match HUD: four player cards (colour badge, name, win pips, KO tag)
## either side of a round/timer pill, a sudden-death banner, and big animated
## call-outs (arena name, 3-2-1-GO, round results). Lilita One (OFL) display
## font. Purely presentation: game.gd hands it the state every frame.

const FONT := preload("res://assets/fonts/lilita-one.ttf")
const PANEL_BG := Color(0.05, 0.06, 0.09, 0.78)
const TINTS := {"bomb": Color(0.35, 0.6, 1.0), "fire": Color(1.0, 0.55, 0.2), "speed": Color(0.3, 0.9, 0.45), "shield": Color(0.62, 0.45, 1.0)}
const Cfg := preload("res://scripts/config.gd")
const Art := preload("res://scripts/art.gd")
static var _icons := {}   # pick-up id -> texture of its 3D model, rendered once

var game = null
var _cards: Array = []     # {panel, name, pips[], ko, badge, color}
var _round_lab: Label
var _time_lab: Label
var _banner: PanelContainer
var _banner_lab: Label
var _msg: Label
var _msg_holder: Control
var _last_msg := ""
var _msg_age := 0.0
var _last_secs := -1
var _time_pill: PanelContainer
var hint_bar: PanelContainer
var _top: Control
var _bars: Array = []      # letterbox, top and bottom
var _sub: Label            # the arena's one-line rules hint under the title
var _cine := 0.0
var _pill_warn := false


func setup(g, fighters: Array, wins_needed: int, show_hint: bool) -> void:
	game = g
	# Vignette: darkens the corners so the arena is the brightest part of the
	# frame and the cards don't compete with it.
	var vig := ColorRect.new()
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec2 p = UV * 2.0 - 1.0;\n\tfloat d = length(p * vec2(0.9, 1.0));\n\tCOLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.75, 1.45, d) * 0.28);\n}\n"
	vm.shader = vs
	vig.material = vm
	add_child(vig)
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in 2:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if side == 0 else Control.PRESET_BOTTOM_WIDE)
		_bars.append(bar)
	# Cards in the corners, over the surroundings, never over the playfield;
	# the timer pill sits over the far wall row.
	_top = Control.new()
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cols: Array = []
	for side in 2:
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 8)
		_top.add_child(v)
		v.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if side == 0 else Control.PRESET_TOP_RIGHT)
		if side == 0:
			v.offset_left = 12.0
		else:
			v.offset_right = -12.0
			v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		v.offset_top = 12.0
		cols.append(v)
	for k in fighters.size():
		var c := _build_card(fighters[k], wins_needed)
		cols[0 if k < 2 else 1].add_child(c["panel"])
		_cards.append(c)
	var pill := _build_time_pill()
	_top.add_child(pill)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.offset_top = 2.0
	# Sudden death / walls-closing banner, under the timer.
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", _box(Color(0.55, 0.06, 0.04, 0.9), 12, Color(1.0, 0.45, 0.3), 2))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 72.0
	_banner_lab = _label(26, Color(1.0, 0.92, 0.85), 6)
	_banner_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_lab)
	_banner.visible = false
	# Big call-outs: scaled about their centre when they change.
	_msg_holder = Control.new()
	_msg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_msg_holder)
	_msg_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_msg = _label(96, Color(1.0, 0.9, 0.42), 16)
	_msg.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_msg.add_theme_constant_override("shadow_offset_x", 0)
	_msg.add_theme_constant_override("shadow_offset_y", 8)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg_holder.add_child(_msg)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sub = _label(26, Color(1, 1, 1, 0.92), 8)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sub)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_sub.offset_left = -500.0
	_sub.offset_right = 500.0
	_sub.offset_top = 70.0
	_sub.offset_bottom = 110.0
	if show_hint:
		hint_bar = PanelContainer.new()
		hint_bar.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.09, 0.55), 10))
		hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint_bar)
		hint_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		hint_bar.offset_top = -40.0
		hint_bar.offset_bottom = -10.0
		var h := _label(15, Color(1, 1, 1, 0.82), 0)
		h.text = "  MOVE  WASD / ARROWS / STICK      BOMB  SPACE / A  "
		hint_bar.add_child(h)
		hint_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _build_time_pill() -> PanelContainer:
	_time_pill = PanelContainer.new()
	_time_pill.add_theme_stylebox_override("panel", _box(PANEL_BG, 16, Color(1, 1, 1, 0.18), 2))
	_time_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_pill.custom_minimum_size = Vector2(160, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -6)
	_time_pill.add_child(v)
	_round_lab = _label(16, Color(1, 0.95, 0.85, 0.9), 3)
	_round_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_round_lab)
	_time_lab = _label(32, Color(1, 1, 1), 0)
	_time_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_time_lab)
	return _time_pill


func _build_card(f, wins_needed: int) -> Dictionary:
	var col: Color = f.color
	var panel := PanelContainer.new()
	var sb := _box(PANEL_BG, 14, col, 0)
	sb.border_width_left = 7
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(212, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)
	var badge := PanelContainer.new()
	var bsb := _box(col.darkened(0.45), 28, col.lightened(0.3), 3)
	bsb.content_margin_left = 0
	bsb.content_margin_right = 0
	bsb.content_margin_top = 0
	bsb.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", bsb)
	badge.custom_minimum_size = Vector2(56, 56)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var tex := _portrait(f)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(56, 56)
		badge.add_child(tr)
	else:
		var ini := _label(26, Color(1, 1, 1), 5)
		ini.text = String(f.display_name).substr(0, 1)
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(ini)
	h.add_child(badge)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	h.add_child(v)
	var nm := _label(22, Color(1, 1, 1), 5)
	v.add_child(nm)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	v.add_child(row)
	var pips: Array = []
	for i in wins_needed:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(18, 18)
		p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.3), 9, Color(1, 1, 1, 0.6), 2))
		row.add_child(p)
		pips.append(p)
	var ko := _label(16, Color(1.0, 0.4, 0.32), 4)
	ko.text = "KO"
	ko.visible = false
	row.add_child(ko)
	# Power-ups held: small chips in each pick-up's colour.
	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 4)
	v.add_child(chips_row)
	var chips := {}
	for id in ["bomb", "fire", "speed", "shield"]:
		var chip := PanelContainer.new()
		var tint: Color = TINTS[id]
		var csb := _box(tint.darkened(0.55), 6, tint, 1)
		csb.content_margin_left = 5
		csb.content_margin_right = 5
		csb.content_margin_top = 0
		csb.content_margin_bottom = 0
		csb.shadow_size = 0
		chip.add_theme_stylebox_override("panel", csb)
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 1)
		chip.add_child(row2)
		var icon := _icon(id)
		if icon != null:
			var tr := TextureRect.new()
			tr.texture = icon
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(22, 22)
			if id == "shield":   # bigger and tilted: it has no count beside it
				tr.custom_minimum_size = Vector2(28, 28)
				tr.pivot_offset = Vector2(14, 14)
				tr.rotation = -0.22
			row2.add_child(tr)
		var cl := _label(16, tint.lightened(0.5), 3)
		cl.custom_minimum_size = Vector2(0 if id == "shield" else 20, 0)
		cl.visible = id != "shield"
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row2.add_child(cl)
		chips_row.add_child(chip)
		chips[id] = [chip, cl]
	return {"panel": panel, "name": nm, "pips": pips, "ko": ko, "color": col, "won": -1, "chips": chips}


## Cinematic mode (the arrival flyover): letterbox in, cards and timer out,
## the arena's rules hint under its name. `show_hint` keeps the controls bar
## to the start of the match.
func set_frame(cinematic: bool, sub: String, show_hint: bool, delta: float) -> void:
	_cine = move_toward(_cine, 1.0 if cinematic else 0.0, delta * 3.5)
	var e := _cine * _cine * (3.0 - 2.0 * _cine)
	for i in _bars.size():
		var bar: ColorRect = _bars[i]
		var h := 70.0 * e
		if i == 0:
			bar.offset_bottom = h
		else:
			bar.offset_top = -h
		bar.visible = e > 0.001
	_top.modulate.a = 1.0 - e
	_top.position.y = -60.0 * e
	_sub.text = sub
	_sub.visible = sub != ""
	if hint_bar:
		hint_bar.modulate.a = move_toward(hint_bar.modulate.a, 1.0 if show_hint and not cinematic else 0.0, delta * 3.0)


func update(delta: float, fighters: Array, wins: Array, human_pid: int, round_no: int, arena: String,
		secs: int, banner: String, msg: String) -> void:
	for k in _cards.size():
		var c: Dictionary = _cards[k]
		var f = fighters[k]
		(c["name"] as Label).text = String(f.display_name).to_upper() + ("  YOU" if k == human_pid else "")
		var panel: PanelContainer = c["panel"]
		panel.modulate = Color(1, 1, 1, 1.0 if f.alive else 0.55)
		(c["ko"] as Label).visible = not f.alive and game.phase == "play"
		# Four fixed chips (they dim when empty), so a card never changes width.
		var chips: Dictionary = c["chips"]
		(chips["bomb"][1] as Label).text = str(f.max_bombs)
		(chips["fire"][1] as Label).text = str(f.fire)
		var spd := int(round((f.speed - Cfg.BASE_SPEED) / Cfg.SPEED_STEP))
		(chips["speed"][1] as Label).text = str(spd)
		(chips["speed"][0] as Control).modulate.a = 1.0 if spd > 0 else 0.3
		(chips["shield"][1] as Label).text = ""
		(chips["shield"][0] as Control).modulate.a = 1.0 if f.shield else 0.3
		if c["won"] != wins[k]:
			c["won"] = wins[k]
			var i := 0
			for p in c["pips"]:
				var on: bool = i < wins[k]
				(p as Panel).add_theme_stylebox_override("panel", _box(c["color"] if on else Color(1, 1, 1, 0.3), 9,
					Color(1, 1, 1, 0.95) if on else Color(1, 1, 1, 0.6), 2))
				i += 1
			if wins[k] > 0:
				_pop(panel, 1.12)
	# Fade the timer while someone plays right under it.
	var under := false
	for f in fighters:
		if f.alive and f.gy < 2.6 and absf(f.gx - (Cfg.COLS - 1) * 0.5) < 2.6:
			under = true
	_time_pill.modulate.a = move_toward(_time_pill.modulate.a, 0.4 if under else 1.0, delta * 4.0)
	_round_lab.text = "ROUND %d  ·  %s" % [round_no, arena.to_upper()]
	_time_lab.text = "%d:%02d" % [floori(secs / 60.0), secs % 60]
	var low: bool = secs <= 10 and game.phase == "play"
	_time_lab.add_theme_color_override("font_color", Color(1.0, 0.42, 0.3) if low else Color(1, 1, 1))
	if low and secs != _last_secs:
		_pop(_time_pill, 1.1)
	_last_secs = secs
	# Warnings (walls closing, tide) take over the timer pill's top line rather
	# than a banner over row 1 (AAA review round 4).
	_banner.visible = false
	if banner != "":
		_round_lab.text = banner
		_round_lab.add_theme_color_override("font_color", Color(1.0, 0.5, 0.38).lerp(Color(1, 0.9, 0.8), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)))
		_time_pill.add_theme_stylebox_override("panel", _box(Color(0.35, 0.05, 0.04, 0.88), 16, Color(1.0, 0.45, 0.3), 2))
	elif _pill_warn:
		_round_lab.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 0.9))
		_time_pill.add_theme_stylebox_override("panel", _box(PANEL_BG, 16, Color(1, 1, 1, 0.18), 2))
	_pill_warn = banner != ""
	# Call-outs punch in from big, settle, and fade on their way out.
	if msg != _last_msg:
		_last_msg = msg
		_msg_age = 0.0
		_msg.text = msg
	_msg_age += delta
	if msg != "":
		var k2 := clampf(_msg_age / 0.22, 0.0, 1.0)
		var s := lerpf(1.6, 1.0, 1.0 - pow(1.0 - k2, 3.0))
		_msg_holder.pivot_offset = _msg_holder.size * 0.5
		_msg_holder.scale = Vector2(s, s)
		_msg.modulate.a = clampf(_msg_age / 0.1, 0.0, 1.0)


## A head-and-shoulders portrait of the fighter's own model, rendered once
## into a small viewport with a key and rim light.
func _portrait(f) -> Texture2D:
	if f.model == null or game.smoke:
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var copy: Node3D = f.model.duplicate()
	copy.position = Vector3(0, copy.position.y, 0)
	copy.rotation = Vector3(0, 0.35, 0)
	vp.add_child(copy)
	var cam := Camera3D.new()
	cam.fov = 34.0
	var head: float = f.TARGET_HEIGHT * 0.74
	cam.position = Vector3(0.0, head + 0.12, 1.35)
	vp.add_child(cam)
	cam.look_at(Vector3(0, head, 0), Vector3.UP)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 30, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 1.1
	rim.light_color = f.color
	vp.add_child(rim)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	return vp.get_texture()


## The pick-up's own 3D model, rendered once into a small viewport.
func _icon(id: String) -> Texture2D:
	if game.smoke:
		return null
	if _icons.has(id) and is_instance_valid(_icons[id]["vp"]):
		return _icons[id]["tex"]
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
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
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 25, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)
	_icons[id] = {"vp": vp, "tex": vp.get_texture()}
	return _icons[id]["tex"]


func _pop(c: Control, s: float) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(s, s), 0.08)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _label(size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.06, 0.9))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb
