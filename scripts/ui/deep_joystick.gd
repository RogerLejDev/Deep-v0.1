class_name DeepJoystick
extends Control
## Left-thumb movement stick.
##
## Behaves the way good mobile sticks do: the whole left region is the touch
## zone, the stick re-centres wherever your thumb lands, and the knob can be
## dragged beyond the ring (clamped) so you never lose full deflection by
## sliding. Returns a signed axis; the player treats >0.55 as running.

signal axis_changed(axis: float)

const RING_RADIUS: float = 58.0
const KNOB_RADIUS: float = 25.0
const DEADZONE: float = 0.14

var axis: float = 0.0

var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO
var _active: bool = false
var _fade: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _touch_index < 0:
			_begin(st.index, st.position)
			accept_event()
		elif not st.pressed and st.index == _touch_index:
			_end()
			accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch_index:
			_move(sd.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin(-2, mb.position)
			else:
				_end()
			accept_event()
	elif event is InputEventMouseMotion and _active and _touch_index == -2:
		_move((event as InputEventMouseMotion).position)
		accept_event()


func _begin(index: int, local_pos: Vector2) -> void:
	_touch_index = index
	_active = true
	_origin = local_pos
	_knob = local_pos
	_update_axis()
	queue_redraw()


func _move(local_pos: Vector2) -> void:
	_knob = local_pos
	_update_axis()
	queue_redraw()


func _end() -> void:
	_touch_index = -1
	_active = false
	axis = 0.0
	axis_changed.emit(0.0)
	queue_redraw()


func _update_axis() -> void:
	var delta := _knob - _origin
	var clamped := delta.limit_length(RING_RADIUS)
	_knob = _origin + clamped
	var raw: float = clamped.x / RING_RADIUS
	if absf(raw) < DEADZONE:
		axis = 0.0
	else:
		# Rescale past the deadzone so the first millimetre of travel is not
		# dead *and* the stick still reaches 1.0.
		var sign_v: float = signf(raw)
		axis = sign_v * clampf((absf(raw) - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	axis_changed.emit(axis)


func _process(delta: float) -> void:
	var target := 1.0 if _active else 0.0
	if absf(_fade - target) > 0.01:
		_fade = move_toward(_fade, target, delta * 4.0)
		queue_redraw()


func _draw() -> void:
	# Resting hint so a first-time player knows where the stick lives.
	var rest := Vector2(RING_RADIUS + 24.0, size.y - RING_RADIUS - 24.0)
	var centre := _origin if _active else rest
	var a: float = lerpf(0.16, 0.5, _fade)

	draw_circle(centre, RING_RADIUS, Color(0.03, 0.05, 0.07, a * 0.55))
	draw_arc(centre, RING_RADIUS, 0.0, TAU, 48, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, a * 0.75), 2.0)
	# Tick marks give the ring a built feel rather than a plain circle.
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(centre + d * (RING_RADIUS - 6.0), centre + d * RING_RADIUS,
			Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, a * 0.4), 1.2)

	var knob := _knob if _active else rest
	draw_circle(knob, KNOB_RADIUS, Color(0.08, 0.14, 0.18, lerpf(0.35, 0.85, _fade)))
	draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 32,
		Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, lerpf(0.4, 1.0, _fade)), 2.0)
	# Direction chevrons on the knob.
	var chev := Color(UiKit.TEXT_BRIGHT.r, UiKit.TEXT_BRIGHT.g, UiKit.TEXT_BRIGHT.b, lerpf(0.25, 0.8, _fade))
	draw_line(knob + Vector2(-9, -5), knob + Vector2(-14, 0), chev, 1.8)
	draw_line(knob + Vector2(-9, 5), knob + Vector2(-14, 0), chev, 1.8)
	draw_line(knob + Vector2(9, -5), knob + Vector2(14, 0), chev, 1.8)
	draw_line(knob + Vector2(9, 5), knob + Vector2(14, 0), chev, 1.8)
