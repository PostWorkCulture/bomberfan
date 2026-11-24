extends Control
## Phone controls: a floating thumbstick anywhere on the left half of the
## screen, and a bomb button that fires on any touch in the right half.

const RADIUS := 80.0
const BUTTON_RADIUS := 78.0

var vector := Vector2.ZERO
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _bomb_index := -1
var _bomb_pressed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func consume_bomb() -> bool:
	var b := _bomb_pressed
	_bomb_pressed = false
	return b


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var half := size.x * 0.5
		if event.pressed:
			if event.position.x < half and _stick_index == -1:
				_stick_index = event.index
				_stick_origin = event.position
				vector = Vector2.ZERO
			elif event.position.x >= half:
				_bomb_index = event.index
				_bomb_pressed = true
		else:
			if event.index == _stick_index:
				_stick_index = -1
				vector = Vector2.ZERO
			if event.index == _bomb_index:
				_bomb_index = -1
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_index:
		var d: Vector2 = event.position - _stick_origin
		if d.length() > RADIUS:
			_stick_origin += d - d.normalized() * RADIUS   # the stick follows your thumb
			d = event.position - _stick_origin
		vector = d / RADIUS
		queue_redraw()


func _bomb_centre() -> Vector2:
	return Vector2(size.x - 140.0, size.y - 140.0)


func _draw() -> void:
	var bc := _bomb_centre()
	var held := _bomb_index != -1
	draw_circle(bc, BUTTON_RADIUS, Color(1.0, 0.33, 0.2, 0.6 if held else 0.35))
	draw_arc(bc, BUTTON_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.7), 4.0)
	draw_string(ThemeDB.fallback_font, bc + Vector2(-60, 10), "BOMB",
		HORIZONTAL_ALIGNMENT_CENTER, 120, 28, Color(1, 1, 1, 0.95))
	var origin := _stick_origin if _stick_index != -1 else Vector2(150.0, size.y - 150.0)
	draw_arc(origin, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.55 if _stick_index != -1 else 0.25), 3.0)
	var knob := origin + vector.limit_length(1.0) * RADIUS
	draw_circle(knob, 34.0, Color(1, 1, 1, 0.5 if _stick_index != -1 else 0.2))
