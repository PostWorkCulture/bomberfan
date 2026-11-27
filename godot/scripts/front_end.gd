extends CanvasLayer
## The front end (2026-11-27): title, main menu, options, how to play, the
## character select and the VS screen, over a live bots-only match (attract
## mode) that game.gd runs behind it. 90s arcade structure (PRESS START, a
## 3x3 select grid with a 1P cursor and a countdown, a VS slam), modern
## finish: shader backdrops, 3D turntable, springy motion, glows.
##
## Keyboard, gamepad, mouse and touch all work: buttons take focus, the grid
## moves with the arrows / d-pad, taps pick.

const UI := preload("res://scripts/ui_kit.gd")
const Showcase := preload("res://scripts/showcase.gd")
const Levels := preload("res://scripts/levels.gd")
const Art := preload("res://scripts/art.gd")

const BLURBS := {
	"ninja": "Silent blades. Loud bombs.",
	"sparky": "Live wire, short fuse.",
	"rivet": "Built tough. Hits tougher.",
	"pixel": "8-bit heart, big boom.",
	"boiler": "Full steam ahead.",
	"gumball": "Sweet treats. Sour surprises.",
	"snap": "Say cheese... then run.",
	"arcade": "Insert coin to lose.",
	"tick": "Your time is up.",
}
const SELECT_SECONDS := 30

var game = null
var _root: Control
var _dim: ColorRect
var _screen := ""
var _current: Control = null
var _busy := false

# Character select state
var _sel_i := 0
var _sel_tiles: Array = []
var _sel_locked := false
var _sel_time := 0.0
var _sel_time_lab: Label
var _sel_name: Label
var _sel_blurb: Label
var _sel_plate: PanelContainer
var _sel_back: ColorRect
var _sel_burst: ColorRect
var _sel_vp: SubViewport
var _sel_show: Node3D = null
var _sel_ready: Label
var _fight_btn: Button
# VS
var _vs_t := -1.0
var _vs_fade: ColorRect


func setup(g, start_screen := "title") -> void:
	game = g
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	UI.sound = func(n: String): game.audio.ui(n)
	_dim = ColorRect.new()
	UI.full_rect(_dim)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = DIM_SHADER
	m.shader = sh
	m.set_shader_parameter("side", 0.0)
	m.set_shader_parameter("amount", 0.55)
	_dim.material = m
	add_child(_dim)
	_root = Control.new()
	UI.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	show_screen(start_screen)
	# `-- --flow`: click through title, menu, select and VS into a match by
	# itself (a check that the hand-off and scene reload work).
	if "--flow" in OS.get_cmdline_user_args():
		var t := get_tree()
		t.create_timer(1.5).timeout.connect(_press_start)
		t.create_timer(3.0).timeout.connect(func(): show_screen("select"))
		t.create_timer(5.0).timeout.connect(func(): _hover(5))
		t.create_timer(6.0).timeout.connect(_lock_in)


## Over the live arena: darker on the left where the menu sits, a soft
## vignette everywhere. `side` slides the dark band (0 = centred, 1 = left).
const DIM_SHADER := """
shader_type canvas_item;
uniform float side = 0.0;
uniform float amount = 0.55;
void fragment() {
	vec2 v = (UV - 0.5) * vec2(1.4, 1.0);
	float vig = smoothstep(0.25, 1.0, length(v));
	float left = side * smoothstep(0.75, 0.05, UV.x);
	float a = clamp(amount * 0.45 + vig * 0.5 + left * 0.75, 0.0, 0.95);
	COLOR = vec4(0.03, 0.01, 0.08, a);
}
"""


func _set_dim(side: float, amount: float) -> void:
	var m := _dim.material as ShaderMaterial
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(v: float): m.set_shader_parameter("side", v), float(m.get_shader_parameter("side")), side, 0.4)
	tw.tween_method(func(v: float): m.set_shader_parameter("amount", v), float(m.get_shader_parameter("amount")), amount, 0.4)


# ---- Screen switching ------------------------------------------------------------

func show_screen(screen_name: String) -> void:
	var old := _current
	_screen = screen_name
	_busy = true
	if old != null:
		var tw := old.create_tween()
		tw.set_parallel(true)
		tw.tween_property(old, "modulate:a", 0.0, 0.18)
		tw.tween_property(old, "position:x", -60.0, 0.18)
		tw.chain().tween_callback(old.queue_free)
	var s := Control.new()
	UI.full_rect(s)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(s)
	_current = s
	match screen_name:
		"title":
			_set_dim(0.0, 1.05)
			_build_title(s)
		"main":
			_set_dim(1.0, 0.35)
			_build_main(s)
		"options":
			_set_dim(0.0, 1.5)
			_build_options(s)
		"howto":
			_set_dim(0.0, 1.5)
			_build_howto(s)
		"select":
			_set_dim(0.0, 1.0)
			_build_select(s)
		"vs":
			_build_vs(s)
	s.modulate.a = 0.0
	s.position.x = 60.0
	var tw2 := s.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(s, "modulate:a", 1.0, 0.22).set_delay(0.06)
	tw2.tween_property(s, "position:x", 0.0, 0.3).set_delay(0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.chain().tween_callback(func(): _busy = false)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	var pressed := event.is_pressed() and not event.is_echo()
	match _screen:
		"title":
			if pressed and (event is InputEventKey or event is InputEventJoypadButton
					or event is InputEventMouseButton or event is InputEventScreenTouch):
				get_viewport().set_input_as_handled()
				_press_start()
		"options", "howto":
			if event.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				UI.play("ui_back")
				show_screen("main")
		"main":
			if event.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				UI.play("ui_back")
				show_screen("title")
		"select":
			_select_input(event)
		"vs":
			if _vs_t > 1.4 and (event.is_action_pressed("ui_accept") or (pressed and event is InputEventMouseButton)):
				get_viewport().set_input_as_handled()
				_vs_t = 99.0


func _process(delta: float) -> void:
	if _screen == "select" and not _sel_locked and _sel_time_lab != null and not _busy:
		var before := ceili(_sel_time)
		_sel_time -= delta
		var n := maxi(0, ceili(_sel_time))
		_sel_time_lab.text = "%02d" % n
		if n != before and n <= 5:
			UI.pop(_sel_time_lab, 1.35)
			UI.play("ui_move")
			_sel_time_lab.label_settings.font_color = UI.RED
		if _sel_time <= 0.0:
			_lock_in()
	if _vs_t >= 0.0:
		_vs_t += delta
		if _vs_t >= 3.6:
			_vs_t = -1.0
			_go_to_match()


# ---- Title -------------------------------------------------------------------------

func _build_title(s: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", -6)
	col.position = Vector2(-450, 36)
	col.custom_minimum_size = Vector2(900, 0)
	s.add_child(col)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(900, 300)
	col.add_child(holder)
	var glow := UI.burst(UI.ORANGE, 16.0)
	glow.size = Vector2(620, 620)
	glow.position = Vector2(450 - 310, 150 - 310)
	(glow.material as ShaderMaterial).set_shader_parameter("strength", 0.85)
	holder.add_child(glow)
	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/ui/logo-emblem.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size = Vector2(280, 280)
	emblem.position = Vector2(450 - 140, 10)
	emblem.pivot_offset = Vector2(140, 140)
	holder.add_child(emblem)
	var bob := emblem.create_tween().set_loops()
	bob.tween_property(emblem, "rotation", 0.05, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(emblem, "rotation", -0.05, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var word := UI.gradient_title("BOMBER FAN", 132)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(word)
	var tag := UI.label("ARENA BLAST-'EM-UP", UI.PIXEL, 16, UI.CYAN, 6)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	# Slam the wordmark in
	word.pivot_offset = Vector2(450, 70)
	word.scale = Vector2(2.2, 2.2)
	word.modulate.a = 0.0
	var tw := word.create_tween()
	tw.set_parallel(true)
	tw.tween_property(word, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tw.tween_property(word, "modulate:a", 1.0, 0.2).set_delay(0.15)
	var start := UI.label("TAP TO START" if DisplayServer.is_touchscreen_available() else "PRESS START", UI.PIXEL, 30, UI.YELLOW, 10, Color(0.25, 0.05, 0.1), Vector2(0, 4))
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	start.position = Vector2(-300, -150)
	start.size = Vector2(600, 40)
	start.name = "Start"
	s.add_child(start)
	var blink := start.create_tween().set_loops()
	blink.tween_property(start, "modulate:a", 0.15, 0.5).set_delay(0.35)
	blink.tween_property(start, "modulate:a", 1.0, 0.12)
	var foot := UI.label("© 2026 POSTWORKCULTURE", UI.PIXEL, 12, Color(1, 1, 1, 0.55), 4)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(28, -40)
	s.add_child(foot)
	var free := UI.label("FREE PLAY", UI.PIXEL, 12, Color(1, 1, 1, 0.55), 4)
	free.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	free.position = Vector2(-150, -40)
	s.add_child(free)


func _press_start() -> void:
	_busy = true
	UI.play("ui_start")
	var start := _current.get_node_or_null("Start") as Label
	if start:
		start.create_tween().kill()
		var tw := start.create_tween().set_loops(6)
		tw.tween_property(start, "modulate:a", 0.0, 0.04)
		tw.tween_property(start, "modulate:a", 1.0, 0.04)
	get_tree().create_timer(0.55, true, false, true).timeout.connect(func(): show_screen("main"))


# ---- Main menu -----------------------------------------------------------------------

func _build_main(s: Control) -> void:
	var head := HBoxContainer.new()
	head.position = Vector2(70, 46)
	head.add_theme_constant_override("separation", 16)
	s.add_child(head)
	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/ui/logo-emblem.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(112, 112)
	head.add_child(emblem)
	var word := UI.gradient_title("BOMBER FAN", 78, Color(1.0, 0.96, 0.55), Color(1.0, 0.42, 0.08), 11)
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(word)
	var box := VBoxContainer.new()
	box.position = Vector2(96, 214)
	box.add_theme_constant_override("separation", 18)
	s.add_child(box)
	var items: Array = [["PLAY", UI.PINK, func(): show_screen("select")],
		["OPTIONS", UI.CYAN, func(): show_screen("options")],
		["HOW TO PLAY", UI.ORANGE, func(): show_screen("howto")]]
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		items.append(["QUIT", UI.PURPLE, func(): get_tree().quit()])
	var first: Button = null
	var i := 0
	for it in items:
		var b := UI.button(it[0], it[1], Vector2(400, 70), 32)
		b.pressed.connect(it[2])
		box.add_child(b)
		if first == null:
			first = b
		b.modulate.a = 0.0
		var tw := b.create_tween()
		tw.tween_interval(0.08 + i * 0.07)
		tw.tween_property(b, "modulate:a", 1.0, 0.15)
		i += 1
	first.call_deferred("grab_focus")
	var demo := UI.label("DEMO PLAY", UI.PIXEL, 16, UI.YELLOW, 6)
	demo.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	demo.position = Vector2(-210, 36)
	s.add_child(demo)
	var blink := demo.create_tween().set_loops()
	blink.tween_property(demo, "modulate:a", 0.2, 0.6)
	blink.tween_property(demo, "modulate:a", 1.0, 0.6)
	var summary := UI.label("%s  ·  %s  ·  FIRST TO %d" % [Settings.arena_name(Settings.arena).to_upper(),
		Settings.difficulty.to_upper(), Settings.wins], UI.PIXEL, 12, Color(1, 1, 1, 0.7), 4)
	summary.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	summary.position = Vector2(100, -52)
	s.add_child(summary)


# ---- Options -------------------------------------------------------------------------

func _panel(s: Control, title: String, w: float, h: float, accent: Color) -> VBoxContainer:
	var t := UI.gradient_title(title, 70)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	t.position = Vector2(-400, 26)
	t.size = Vector2(800, 90)
	s.add_child(t)
	var p := PanelContainer.new()
	var sb := UI.box(Color(0.06, 0.03, 0.14, 0.92), 22, accent, 3)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	sb.shadow_size = 26
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(w, h)
	p.position = Vector2(-w * 0.5, -h * 0.5 + 40)
	s.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v


func _build_options(s: Control) -> void:
	var v := _panel(s, "OPTIONS", 760, 470, UI.CYAN)
	var rows: Array = []
	var arena_get := func() -> String: return Settings.arena_name(Settings.arena).to_upper()
	var arena_set := func(d: int) -> void: Settings.arena = _cycle(Settings.ARENAS, Settings.arena, d)
	var diff_get := func() -> String: return Settings.difficulty.to_upper()
	var diff_set := func(d: int) -> void: Settings.difficulty = _cycle(Settings.DIFFICULTIES, Settings.difficulty, d)
	var wins_get := func() -> String: return str(Settings.wins)
	var wins_set := func(d: int) -> void: Settings.wins = _cycle(Settings.WINS, Settings.wins, d)
	var music_get := func() -> String: return "#%d" % Settings.music
	var music_set := func(d: int) -> void:
		Settings.music = clampi(Settings.music + d, 0, 10)
		Settings.apply_audio()
	var sfx_get := func() -> String: return "#%d" % Settings.sfx
	var sfx_set := func(d: int) -> void:
		Settings.sfx = clampi(Settings.sfx + d, 0, 10)
		Settings.apply_audio()
	rows.append(_option_row("ARENA", arena_get, arena_set, UI.LIME))
	rows.append(_option_row("DIFFICULTY", diff_get, diff_set, UI.YELLOW))
	rows.append(_option_row("ROUNDS TO WIN", wins_get, wins_set, UI.ORANGE))
	rows.append(_option_row("MUSIC", music_get, music_set, UI.PINK))
	rows.append(_option_row("SOUND FX", sfx_get, sfx_set, UI.PURPLE))
	for r in rows:
		v.add_child(r)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	var back := UI.button("BACK", UI.PINK, Vector2(260, 58), 28)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): show_screen("main"))
	v.add_child(back)
	rows[0].call_deferred("grab_focus")
	var hint := UI.label("◀ ▶  CHANGE      ESC / B  BACK", UI.PIXEL, 12, Color(1, 1, 1, 0.6), 4)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-220, -40)
	s.add_child(hint)


func _cycle(list: Array, cur, d: int):
	var i := list.find(cur)
	return list[posmod(i + d, list.size())]


## One option: name on the left, ◀ value ▶ on the right. Left/right (or a
## click on an arrow) changes it; it saves straight away.
func _option_row(title: String, get_text: Callable, change: Callable, col: Color) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 58)
	row.focus_mode = Control.FOCUS_ALL
	var plain := UI.box(Color(1, 1, 1, 0.04), 12)
	var hot := UI.box(Color(col.r, col.g, col.b, 0.18), 12, col, 0)
	hot.border_color = col
	hot.border_width_left = 7
	row.add_theme_stylebox_override("normal", plain)
	row.add_theme_stylebox_override("hover", hot)
	row.add_theme_stylebox_override("focus", hot)
	row.add_theme_stylebox_override("pressed", hot)
	var h := HBoxContainer.new()
	UI.full_rect(h)
	h.offset_left = 22
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var name_l := UI.label(title, UI.UI, 26, Color(1, 1, 1), 6)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_l)
	var left := _arrow("◀", col)
	h.add_child(left)
	var value := Control.new()
	value.custom_minimum_size = Vector2(250, 0)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(value)
	var right := _arrow("▶", col)
	h.add_child(right)
	var refresh := func():
		for c in value.get_children():
			c.queue_free()
		var t: String = get_text.call()
		if t.begins_with("#"):
			var bars := HBoxContainer.new()
			bars.add_theme_constant_override("separation", 5)
			bars.alignment = BoxContainer.ALIGNMENT_CENTER
			UI.full_rect(bars)
			bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lvl := int(t.substr(1))
			for k in 10:
				var seg := Panel.new()
				seg.custom_minimum_size = Vector2(17, 14 + k * 2)
				seg.size_flags_vertical = Control.SIZE_SHRINK_END
				seg.add_theme_stylebox_override("panel", UI.box(col if k < lvl else Color(1, 1, 1, 0.12), 3))
				seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
				bars.add_child(seg)
			bars.offset_top = 10
			bars.offset_bottom = -10
			value.add_child(bars)
		else:
			var l := UI.label(t, UI.TITLE, 32, col, 8)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			UI.full_rect(l)
			value.add_child(l)
			UI.pop(l, 1.18)
	var step := func(d: int):
		change.call(d)
		Settings.save()
		refresh.call()
		UI.play("ui_move")
	left.pressed.connect(func():
		row.grab_focus()
		step.call(-1))
	right.pressed.connect(func():
		row.grab_focus()
		step.call(1))
	row.pressed.connect(func(): step.call(1))
	row.gui_input.connect(func(e: InputEvent):
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			row.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			row.accept_event())
	row.mouse_entered.connect(func(): row.grab_focus())
	row.focus_entered.connect(func(): UI.play("ui_move"))
	refresh.call()
	return row


func _arrow(t: String, col: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 0)
	b.add_theme_font_override("font", UI.UI)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	return b


# ---- How to play ------------------------------------------------------------------

func _build_howto(s: Control) -> void:
	var v := _panel(s, "HOW TO PLAY", 1060, 430, UI.ORANGE)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	left.add_child(UI.label("CONTROLS", UI.TITLE, 34, UI.CYAN, 8))
	for row in [["MOVE", "WASD / ARROWS  ·  STICK  ·  DRAG LEFT SIDE"],
			["BOMB", "SPACE  ·  A  ·  TAP RIGHT SIDE"],
			["PAUSE", "ESC  ·  START"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var k := PanelContainer.new()
		var ksb := UI.box(UI.CYAN.darkened(0.55), 8, UI.CYAN, 2)
		ksb.content_margin_top = 4
		ksb.content_margin_bottom = 4
		k.add_theme_stylebox_override("panel", ksb)
		k.custom_minimum_size = Vector2(96, 0)
		var kl := UI.label(row[0], UI.PIXEL, 12, Color(1, 1, 1), 0)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		k.add_child(kl)
		h.add_child(k)
		var d := UI.label(row[1], UI.UI, 17, Color(1, 1, 1, 0.92), 4)
		h.add_child(d)
		left.add_child(h)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	left.add_child(gap)
	left.add_child(UI.label("THE GOAL", UI.TITLE, 34, UI.LIME, 8))
	var goal := UI.label("Blast the crates, grab power-ups and be the last one standing. "
		+ "When the crates run out the walls close in, so keep moving!", UI.UI, 18, Color(1, 1, 1, 0.92), 4)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.custom_minimum_size = Vector2(460, 0)
	left.add_child(goal)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	cols.add_child(right)
	right.add_child(UI.label("POWER-UPS", UI.TITLE, 34, UI.PINK, 8))
	for it in [["bomb", "BOMB UP", "One more bomb at a time"], ["fire", "FIRE UP", "Bigger blasts"],
			["speed", "SPEED", "Run faster for a while"], ["shield", "SHIELD", "Survive one blast"],
			["kick", "KICK", "Walk into a bomb to send it sliding"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.texture = UI.item_icon(s, it[0], 96)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(58, 58)
		h.add_child(icon)
		var t := VBoxContainer.new()
		t.add_theme_constant_override("separation", -4)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tint: Color = Art.PICKUP_TINT.get(it[0], Color.WHITE)
		t.add_child(UI.label(it[1], UI.UI, 20, tint.lightened(0.25), 5))
		t.add_child(UI.label(it[2], UI.UI, 16, Color(1, 1, 1, 0.85), 4))
		h.add_child(t)
		right.add_child(h)
	var back := UI.button("BACK", UI.PINK, Vector2(240, 54), 26)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): show_screen("main"))
	v.add_child(back)
	back.call_deferred("grab_focus")


# ---- Character select --------------------------------------------------------------

func _roster() -> Array:
	return game.ROSTER


func _build_select(s: Control) -> void:
	var roster := _roster()
	_sel_locked = false
	_sel_tiles.clear()
	_sel_time = SELECT_SECONDS
	_sel_i = 0
	for k in roster.size():
		if roster[k]["id"] == Settings.fighter:
			_sel_i = k
	var col0: Color = roster[_sel_i]["color"]
	_sel_back = UI.backdrop(col0, 1.0)
	s.add_child(_sel_back)
	var title := UI.gradient_title("SELECT YOUR FIGHTER", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-460, 14)
	title.size = Vector2(920, 80)
	s.add_child(title)
	var one := PanelContainer.new()
	var osb := UI.box(UI.PINK, 8, Color(1, 1, 1), 3, -0.2)
	osb.content_margin_top = 6
	osb.content_margin_bottom = 6
	one.add_theme_stylebox_override("panel", osb)
	one.add_child(UI.label("1P", UI.PIXEL, 22, Color(1, 1, 1), 6))
	one.position = Vector2(34, 30)
	s.add_child(one)
	var tbox := VBoxContainer.new()
	tbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tbox.position = Vector2(-150, 18)
	tbox.add_theme_constant_override("separation", 4)
	s.add_child(tbox)
	var tl := UI.label("TIME", UI.PIXEL, 14, UI.YELLOW, 4)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tbox.add_child(tl)
	_sel_time_lab = UI.label("%02d" % SELECT_SECONDS, UI.PIXEL, 40, Color(1, 1, 1), 8, Color(0.1, 0.02, 0.1), Vector2(0, 4))
	_sel_time_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_time_lab.custom_minimum_size = Vector2(110, 0)
	tbox.add_child(_sel_time_lab)

	# Left: the hovered fighter on a turntable in front of a light burst
	_sel_burst = UI.burst(col0, 18.0)
	_sel_burst.position = Vector2(20, 60)
	_sel_burst.size = Vector2(600, 600)
	s.add_child(_sel_burst)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(60, 96)
	svc.size = Vector2(520, 470)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(svc)
	_sel_vp = SubViewport.new()
	_sel_vp.own_world_3d = true
	_sel_vp.transparent_bg = true
	_sel_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_sel_vp)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.05, 3.9)
	_sel_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	UI.stage_lights(_sel_vp, col0, 1.1)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.8
	cyl.height = 0.08
	cyl.radial_segments = 48
	disc.mesh = cyl
	disc.position.y = -0.04
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.08, 0.06, 0.12)
	dm.metallic = 0.3
	dm.roughness = 0.55
	dm.emission_enabled = true
	dm.emission = col0.darkened(0.4)
	dm.emission_energy_multiplier = 0.25
	disc.mesh.surface_set_material(0, dm)
	disc.name = "Disc"
	_sel_vp.add_child(disc)

	# Name plate
	_sel_plate = PanelContainer.new()
	var psb := UI.box(col0.darkened(0.15), 14, Color(1, 1, 1), 4, -0.22)
	psb.shadow_color = Color(col0.r, col0.g, col0.b, 0.6)
	psb.shadow_size = 18
	psb.content_margin_left = 34
	psb.content_margin_right = 34
	psb.content_margin_top = 0
	psb.content_margin_bottom = 2
	_sel_plate.add_theme_stylebox_override("panel", psb)
	_sel_plate.position = Vector2(80, 548)
	_sel_plate.custom_minimum_size = Vector2(480, 0)
	s.add_child(_sel_plate)
	_sel_name = UI.label("", UI.TITLE, 62, Color(1, 1, 1), 12, Color(0.05, 0.02, 0.1), Vector2(0, 5))
	_sel_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_plate.add_child(_sel_name)
	_sel_blurb = UI.label("", UI.UI, 22, Color(1, 1, 1, 0.95), 6)
	_sel_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_blurb.position = Vector2(80, 640)
	_sel_blurb.size = Vector2(480, 30)
	s.add_child(_sel_blurb)
	_sel_ready = UI.gradient_title("READY!", 110, Color(1, 1, 1), Color(1.0, 0.85, 0.3), 16)
	_sel_ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_ready.position = Vector2(60, 230)
	_sel_ready.size = Vector2(520, 130)
	_sel_ready.pivot_offset = Vector2(260, 65)
	_sel_ready.visible = false
	s.add_child(_sel_ready)

	# Right: the 3x3 grid
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.position = Vector2(700, 110)
	s.add_child(grid)
	for k in roster.size():
		var tile := _make_tile(s, roster[k], k)
		grid.add_child(tile)
		_sel_tiles.append(tile)
		tile.modulate.a = 0.0
		tile.scale = Vector2(0.6, 0.6)
		var tw := tile.create_tween()
		tw.tween_interval(0.05 + k * 0.035)
		tw.set_parallel(true)
		tw.tween_property(tile, "modulate:a", 1.0, 0.15)
		tw.tween_property(tile, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var btns := HBoxContainer.new()
	btns.position = Vector2(712, 640)
	btns.add_theme_constant_override("separation", 18)
	s.add_child(btns)
	var back := UI.button("BACK", UI.PURPLE, Vector2(160, 52), 24)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): if not _sel_locked: show_screen("main"))
	btns.add_child(back)
	_fight_btn = UI.button("FIGHT!", UI.LIME, Vector2(300, 52), 28)
	_fight_btn.focus_mode = Control.FOCUS_NONE
	_fight_btn.add_theme_color_override("font_outline_color", Color(0.05, 0.25, 0.05))
	_fight_btn.pressed.connect(_lock_in)
	btns.add_child(_fight_btn)
	var pulse := _fight_btn.create_tween().set_loops()
	pulse.tween_property(_fight_btn, "modulate", Color(1.25, 1.25, 1.25), 0.45)
	pulse.tween_property(_fight_btn, "modulate", Color(1, 1, 1), 0.45)
	var hint := UI.label("ARROWS  CHOOSE    ENTER / A  FIGHT", UI.PIXEL, 11, Color(1, 1, 1, 0.7), 4)
	hint.position = Vector2(700, 606)
	hint.size = Vector2(500, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(hint)
	_hover(_sel_i, true)


func _make_tile(s: Control, info: Dictionary, k: int) -> Control:
	var col: Color = info["color"]
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(150, 150)
	tile.pivot_offset = Vector2(75, 75)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	var glow := Panel.new()
	glow.name = "Glow"
	var gsb := UI.box(Color(col.r, col.g, col.b, 0.0), 14)
	gsb.shadow_color = Color(col.r, col.g, col.b, 0.85)
	gsb.shadow_size = 24
	glow.add_theme_stylebox_override("panel", gsb)
	UI.full_rect(glow)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	tile.add_child(glow)
	var bg := Panel.new()
	bg.name = "Bg"
	bg.add_theme_stylebox_override("panel", _tile_box(col, false))
	UI.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	tile.add_child(bg)
	var shine := ColorRect.new()
	shine.color = Color(col.r, col.g, col.b, 0.35)
	shine.position = Vector2(0, 75)
	shine.size = Vector2(150, 75)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(shine)
	var pic := TextureRect.new()
	pic.texture = UI.portrait(s, info["id"], col, 192)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	UI.full_rect(pic)
	pic.offset_bottom = -22
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(pic)
	var strip := ColorRect.new()
	strip.color = col.darkened(0.55)
	strip.position = Vector2(0, 124)
	strip.size = Vector2(150, 26)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(strip)
	var nm := UI.label(String(info["name"]), UI.UI, 16, Color(1, 1, 1), 4)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(0, 125)
	nm.size = Vector2(150, 24)
	bg.add_child(nm)
	var tag := PanelContainer.new()
	tag.name = "Tag"
	var tsb := UI.box(UI.PINK, 6, Color(1, 1, 1), 2)
	tsb.content_margin_left = 6
	tsb.content_margin_right = 6
	tsb.content_margin_top = 3
	tsb.content_margin_bottom = 3
	tag.add_theme_stylebox_override("panel", tsb)
	tag.add_child(UI.label("1P", UI.PIXEL, 12, Color(1, 1, 1), 3))
	tag.position = Vector2(-10, -12)
	tag.visible = false
	tile.add_child(tag)
	tile.gui_input.connect(func(e: InputEvent):
		if _sel_locked or _busy:
			return
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed):
			if _sel_i == k:
				_lock_in()
			else:
				_hover(k))
	tile.mouse_entered.connect(func():
		if not _sel_locked and not DisplayServer.is_touchscreen_available() and _sel_i != k:
			_hover(k))
	return tile


func _tile_box(col: Color, hot: bool) -> StyleBoxFlat:
	var sb := UI.box(col.darkened(0.62), 12, Color(1, 1, 1) if hot else col.darkened(0.1), 5 if hot else 3)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


func _select_input(event: InputEvent) -> void:
	if _sel_locked:
		return
	var d := Vector2i.ZERO
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		d = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		d = Vector2i(1, 0)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		d = Vector2i(0, -1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		d = Vector2i(0, 1)
	if d != Vector2i.ZERO:
		get_viewport().set_input_as_handled()
		var n := _sel_tiles.size()
		var x := _sel_i % 3 + d.x
		var y := int(_sel_i / 3.0) + d.y
		var rows := int(ceil(n / 3.0))
		x = posmod(x, 3)
		y = posmod(y, rows)
		_hover(clampi(y * 3 + x, 0, n - 1))
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("bomb"):
		get_viewport().set_input_as_handled()
		_lock_in()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		UI.play("ui_back")
		show_screen("main")


func _hover(k: int, first := false) -> void:
	var roster := _roster()
	var old := _sel_i
	_sel_i = k
	for i in _sel_tiles.size():
		var t: Control = _sel_tiles[i]
		var on := i == k
		var c: Color = roster[i]["color"]
		(t.get_node("Bg") as Panel).add_theme_stylebox_override("panel", _tile_box(c, on))
		(t.get_node("Glow") as Control).visible = on
		(t.get_node("Tag") as Control).visible = on
		t.z_index = 1 if on else 0
		if not first:
			var tw := t.create_tween()
			tw.tween_property(t, "scale", Vector2(1.1, 1.1) if on else Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			t.scale = Vector2(1.1, 1.1) if on else Vector2.ONE
	var info: Dictionary = roster[k]
	var col: Color = info["color"]
	if not first and old != k:
		UI.play("ui_move")
	_sel_name.text = String(info["name"])
	_sel_name.label_settings.font_color = Color(1, 1, 1)
	_sel_blurb.text = BLURBS.get(info["id"], "")
	var psb := (_sel_plate.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	psb.bg_color = col.darkened(0.15)
	psb.shadow_color = Color(col.r, col.g, col.b, 0.6)
	_sel_plate.add_theme_stylebox_override("panel", psb)
	UI.pop(_sel_plate, 1.08)
	var bm := _sel_back.material as ShaderMaterial
	var from: Color = bm.get_shader_parameter("accent")
	var tw2 := create_tween()
	tw2.tween_method(func(c: Color): bm.set_shader_parameter("accent", c), from, col, 0.3)
	(_sel_burst.material as ShaderMaterial).set_shader_parameter("col", col)
	for n in _sel_vp.get_children():
		if n is DirectionalLight3D and (n as DirectionalLight3D).rotation_degrees.y > 150.0:
			(n as DirectionalLight3D).light_color = col.lightened(0.2)
	var disc := _sel_vp.get_node_or_null("Disc") as MeshInstance3D
	if disc:
		var dm := disc.mesh.surface_get_material(0) as StandardMaterial3D
		dm.emission = col.darkened(0.3)
	if _sel_show != null:
		_sel_show.queue_free()
	_sel_show = Showcase.new()
	_sel_show.setup(info["id"], col)
	_sel_show.spin = 0.55
	_sel_show.rotation.y = -0.6
	_sel_vp.add_child(_sel_show)
	_sel_show.scale = Vector3(0.6, 0.6, 0.6)
	var tw3 := _sel_show.create_tween()
	tw3.tween_property(_sel_show, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _lock_in() -> void:
	if _sel_locked or _busy or _screen != "select":
		return
	_sel_locked = true
	var roster := _roster()
	var info: Dictionary = roster[_sel_i]
	Settings.fighter = info["id"]
	Settings.save()
	UI.play("ui_lock")
	var t: Control = _sel_tiles[_sel_i]
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.9)
	UI.full_rect(flash)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.5)
	UI.pop(t, 1.25)
	if _sel_show:
		_sel_show.spin = 0.0
		var tw2 := _sel_show.create_tween()
		tw2.tween_property(_sel_show, "rotation:y", 0.0, 0.25)
		_sel_show.cheer()
	_sel_ready.visible = true
	_sel_ready.scale = Vector2(2.4, 2.4)
	_sel_ready.modulate.a = 0.0
	var tw3 := _sel_ready.create_tween()
	tw3.set_parallel(true)
	tw3.tween_property(_sel_ready, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw3.tween_property(_sel_ready, "modulate:a", 1.0, 0.12)
	for i in _sel_tiles.size():
		if i != _sel_i:
			var o: Control = _sel_tiles[i]
			o.create_tween().tween_property(o, "modulate", Color(0.45, 0.45, 0.5, 1.0), 0.3)
	_draw_match(info["id"])
	get_tree().create_timer(1.25, true, false, true).timeout.connect(func(): show_screen("vs"))


## Who you will face, and where: shown on the VS screen, played in the match.
func _draw_match(mine: String) -> void:
	var pool: Array = []
	for r in _roster():
		if r["id"] != mine:
			pool.append(r["id"])
	pool.shuffle()
	Settings.cast = [mine] + pool.slice(0, 3)
	if Settings.arena == "random":
		Settings.first_level = Levels.LIST[randi() % Levels.LIST.size()]["id"]
	else:
		Settings.first_level = Settings.arena


# ---- VS ---------------------------------------------------------------------------

func _info(id: String) -> Dictionary:
	for r in _roster():
		if r["id"] == id:
			return r
	return _roster()[0]


func _build_vs(s: Control) -> void:
	_set_dim(0.0, 1.6)
	if Settings.cast.size() < 4:
		_draw_match(Settings.fighter)
	var me := _info(Settings.cast[0])
	var me_col: Color = me["color"]
	var vp_size := get_viewport().get_visible_rect().size
	var w := vp_size.x
	var h := vp_size.y
	# Two halves meeting on a diagonal, sliding in from the sides
	var left := Polygon2D.new()
	left.polygon = PackedVector2Array([Vector2(0, 0), Vector2(w * 0.58, 0), Vector2(w * 0.44, h), Vector2(0, h)])
	left.vertex_colors = PackedColorArray([me_col.darkened(0.2), me_col.darkened(0.45), me_col.darkened(0.75), me_col.darkened(0.55)])
	left.position.x = -w
	s.add_child(left)
	var right := Polygon2D.new()
	right.polygon = PackedVector2Array([Vector2(w * 0.58, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.44, h)])
	right.vertex_colors = PackedColorArray([Color(0.3, 0.05, 0.12), Color(0.12, 0.02, 0.08), Color(0.05, 0.0, 0.05), Color(0.22, 0.03, 0.1)])
	right.position.x = w
	s.add_child(right)
	var seam := Line2D.new()
	seam.points = PackedVector2Array([Vector2(w * 0.58, -10), Vector2(w * 0.44, h + 10)])
	seam.width = 10
	seam.default_color = Color(1, 1, 1)
	seam.modulate.a = 0.0
	s.add_child(seam)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(left, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(right, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(seam, "modulate:a", 1.0, 0.2).set_delay(0.25)
	# You
	var burst := UI.burst(me_col.lightened(0.2), 16.0)
	burst.position = Vector2(w * 0.25 - 330, h * 0.5 - 330)
	burst.size = Vector2(660, 660)
	s.add_child(burst)
	var hero := TextureRect.new()
	hero.texture = UI.portrait(s, me["id"], me_col, 560, true, 0.45)
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.size = Vector2(560, 560)
	hero.position = Vector2(w * 0.25 - 280 - 500, h * 0.5 - 300)
	s.add_child(hero)
	s.create_tween().tween_property(hero, "position:x", w * 0.25 - 280, 0.4).set_delay(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var nm := UI.label(String(me["name"]), UI.TITLE, 78, Color(1, 1, 1), 14, Color(0.04, 0.02, 0.08), Vector2(0, 6))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size = Vector2(500, 90)
	nm.position = Vector2(w * 0.25 - 250, h - 150 + 200)
	s.add_child(nm)
	s.create_tween().tween_property(nm, "position:y", h - 150, 0.35).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var you := PanelContainer.new()
	var ysb := UI.box(UI.PINK, 8, Color(1, 1, 1), 3, -0.2)
	ysb.content_margin_top = 6
	ysb.content_margin_bottom = 6
	you.add_theme_stylebox_override("panel", ysb)
	you.add_child(UI.label("1P  YOU", UI.PIXEL, 18, Color(1, 1, 1), 5))
	you.position = Vector2(40, 30)
	you.modulate.a = 0.0
	s.add_child(you)
	s.create_tween().tween_property(you, "modulate:a", 1.0, 0.2).set_delay(0.5)
	# The three rivals, stacked on the right
	for i in 3:
		var info := _info(Settings.cast[i + 1])
		var c: Color = info["color"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var frame := PanelContainer.new()
		var fsb := UI.box(c.darkened(0.6), 14, c, 4)
		fsb.content_margin_left = 0
		fsb.content_margin_right = 0
		fsb.content_margin_top = 0
		fsb.content_margin_bottom = 0
		fsb.shadow_color = Color(c.r, c.g, c.b, 0.55)
		fsb.shadow_size = 14
		frame.add_theme_stylebox_override("panel", fsb)
		frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var pic := TextureRect.new()
		pic.texture = UI.portrait(s, info["id"], c, 192)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.custom_minimum_size = Vector2(150, 150)
		frame.add_child(pic)
		row.add_child(frame)
		var l := UI.label(String(info["name"]), UI.TITLE, 46, c.lightened(0.15), 10, Color(0.04, 0.02, 0.08), Vector2(0, 4))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var y := 40.0 + i * 186.0
		row.position = Vector2(w + 50, y)
		s.add_child(row)
		s.create_tween().tween_property(row, "position:x", w * 0.66 + 10 - i * 34, 0.36).set_delay(0.22 + i * 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# VS slams in on the seam with the sound's impact (0.45 s into it)
	var vs := UI.gradient_title("VS", 230, Color(1, 1, 1), Color(1.0, 0.75, 0.15), 22)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.size = Vector2(420, 260)
	vs.position = Vector2(w * 0.49 - 210, h * 0.5 - 150)
	vs.pivot_offset = Vector2(210, 130)
	vs.scale = Vector2(4, 4)
	vs.modulate.a = 0.0
	s.add_child(vs)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.0)
	UI.full_rect(flash)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(flash)
	game.audio.ui("vs_slam")
	var t2 := s.create_tween()
	t2.tween_interval(0.33)
	t2.set_parallel(true)
	t2.tween_property(vs, "modulate:a", 1.0, 0.08)
	t2.tween_property(vs, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t2.chain().tween_callback(func(): _shake(s, 18.0))
	t2.tween_property(flash, "color:a", 0.85, 0.04)
	t2.chain().tween_property(flash, "color:a", 0.0, 0.4)
	var pulse := vs.create_tween().set_loops()
	pulse.tween_interval(0.6)
	pulse.tween_property(vs, "scale", Vector2(1.06, 1.06), 0.25).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(vs, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	# Where and how long
	var info_box := PanelContainer.new()
	var isb := UI.box(Color(0.04, 0.02, 0.1, 0.85), 14, UI.YELLOW, 3, -0.2)
	info_box.add_theme_stylebox_override("panel", isb)
	var il := UI.label("STAGE: %s    ·    FIRST TO %d    ·    %s" % [Settings.arena_name(Settings.first_level).to_upper(),
		Settings.wins, Settings.difficulty.to_upper()], UI.PIXEL, 16, Color(1, 1, 1), 4)
	info_box.add_child(il)
	info_box.position = Vector2(w * 0.5 - 380, h + 20)
	info_box.custom_minimum_size = Vector2(760, 0)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(info_box)
	s.create_tween().tween_property(info_box, "position:y", h - 62, 0.3).set_delay(0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_vs_fade = ColorRect.new()
	_vs_fade.color = Color(0, 0, 0, 0)
	UI.full_rect(_vs_fade)
	_vs_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(_vs_fade)
	_vs_t = 0.0


func _shake(c: Control, amount: float) -> void:
	var tw := c.create_tween()
	for i in 6:
		var k := amount * (1.0 - i / 6.0)
		tw.tween_property(c, "position", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.035)
	tw.tween_property(c, "position", Vector2.ZERO, 0.05)


func _go_to_match() -> void:
	var tw := _vs_fade.create_tween()
	tw.tween_property(_vs_fade, "color:a", 1.0, 0.3)
	tw.tween_callback(func(): game.start_match())
