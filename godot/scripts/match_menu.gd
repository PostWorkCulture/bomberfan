extends CanvasLayer
## In-match menus (2026-11-27): PAUSED (Esc / Start / the touch pause button)
## and the end-of-match results with Rematch, Change Fighter and Main Menu.
## Runs while the tree is paused.

const UI := preload("res://scripts/ui_kit.gd")

var game = null
var _panel: Control = null
var mode := ""          # "", "pause" or "over"
var _touch_btn: Button = null


func setup(g) -> void:
	game = g
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	UI.sound = func(n: String): game.audio.ui(n)
	if DisplayServer.is_touchscreen_available():
		_touch_btn = Button.new()
		_touch_btn.text = "II"
		_touch_btn.focus_mode = Control.FOCUS_NONE
		_touch_btn.add_theme_font_override("font", UI.UI)
		_touch_btn.add_theme_font_size_override("font_size", 24)
		_touch_btn.add_theme_stylebox_override("normal", UI.box(Color(0.05, 0.03, 0.1, 0.7), 30, Color(1, 1, 1, 0.6), 2))
		_touch_btn.add_theme_stylebox_override("pressed", UI.box(UI.PINK, 30, Color(1, 1, 1), 2))
		_touch_btn.add_theme_stylebox_override("hover", UI.box(Color(0.05, 0.03, 0.1, 0.7), 30, Color(1, 1, 1, 0.6), 2))
		_touch_btn.custom_minimum_size = Vector2(60, 60)
		_touch_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_touch_btn.position = Vector2(150, 12)
		_touch_btn.pressed.connect(func():
			if mode == "":
				open_pause())
		add_child(_touch_btn)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (mode == "pause" and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		if mode == "pause":
			resume()
		elif mode == "" and game.can_pause():
			open_pause()


func open_pause() -> void:
	mode = "pause"
	get_tree().paused = true
	game.audio.ui("ui_back")
	var v := _build_panel("PAUSED", UI.CYAN, 520)
	var first := _add_button(v, "RESUME", UI.LIME, resume)
	_add_button(v, "RESTART MATCH", UI.YELLOW, func(): game.leave("rematch"))
	_add_button(v, "CHANGE FIGHTER", UI.CYAN, func(): game.leave("select"))
	_add_button(v, "MAIN MENU", UI.PINK, func(): game.leave("main"))
	first.call_deferred("grab_focus")


func resume() -> void:
	mode = ""
	_close()
	get_tree().paused = false
	game.audio.ui("ui_select")


## The match is decided: who won, the final score, and where next.
func open_over(winner, fighters: Array, wins: Array, human_pid: int) -> void:
	mode = "over"
	var you_won: bool = winner != null and winner.pid == human_pid
	var title := "VICTORY!" if you_won else ("%s WINS" % String(winner.display_name) if winner != null else "DRAW")
	var accent: Color = UI.YELLOW if you_won else (winner.color if winner != null else UI.CYAN)
	var v := _build_panel(title, accent, 620)
	var order: Array = range(fighters.size())
	order.sort_custom(func(a, b): return wins[a] > wins[b])
	for k in order:
		var f = fighters[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var badge := PanelContainer.new()
		var bsb := UI.box(f.color.darkened(0.55), 8, f.color, 3)
		bsb.content_margin_left = 0
		bsb.content_margin_right = 0
		bsb.content_margin_top = 0
		bsb.content_margin_bottom = 0
		badge.add_theme_stylebox_override("panel", bsb)
		badge.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var pic := TextureRect.new()
		pic.texture = UI.portrait(self, f.char_id, f.color, 96)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.custom_minimum_size = Vector2(52, 52)
		badge.add_child(pic)
		row.add_child(badge)
		var nm := UI.label(String(f.display_name) + ("  (YOU)" if k == human_pid else ""), UI.UI, 24,
			f.color.lightened(0.2), 6)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nm)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 6)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in game.wins_needed:
			var p := Panel.new()
			p.custom_minimum_size = Vector2(22, 22)
			var on: bool = i < wins[k]
			p.add_theme_stylebox_override("panel", UI.box(f.color if on else Color(1, 1, 1, 0.15), 11, Color(1, 1, 1, 0.8), 2))
			pips.add_child(p)
		row.add_child(pips)
		v.add_child(row)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	var first := _add_button(v, "REMATCH", UI.LIME, func(): game.leave("rematch"))
	_add_button(v, "CHANGE FIGHTER", UI.CYAN, func(): game.leave("select"))
	_add_button(v, "MAIN MENU", UI.PINK, func(): game.leave("main"))
	first.call_deferred("grab_focus")
	game.audio.ui("ui_lock" if you_won else "ui_back")


func _close() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


func _build_panel(title: String, accent: Color, w: float) -> VBoxContainer:
	_close()
	var root := Control.new()
	UI.full_rect(root)
	add_child(root)
	_panel = root
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.62)
	UI.full_rect(dim)
	root.add_child(dim)
	var center := CenterContainer.new()
	UI.full_rect(center)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var t := UI.gradient_title(title, 84)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var p := PanelContainer.new()
	var sb := UI.box(Color(0.06, 0.03, 0.14, 0.94), 22, accent, 3)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
	sb.shadow_size = 26
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(w, 0)
	col.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	root.modulate.a = 0.0
	t.pivot_offset = Vector2(w * 0.5, 50)
	t.scale = Vector2(1.6, 1.6)
	var tw := root.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	tw.tween_property(t, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return v


func _add_button(v: VBoxContainer, text: String, col: Color, cb: Callable) -> Button:
	var b := UI.button(text, col, Vector2(400, 60), 28)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	v.add_child(b)
	return b
