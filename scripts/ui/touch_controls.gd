extends Control
## The mobile control layer: movement stick on the left, action cluster on the
## right, menu chips along the top-right.
##
## Landscape-only by design. The stick and buttons sit in the bottom corners
## where thumbs rest, and the middle of the screen is left completely clear so
## the world stays visible — which is the whole point of a 2D exploration game
## on a phone.

signal menu_requested(which: String)

const JUMP_DIAMETER: float = 74.0
const SMALL_DIAMETER: float = 58.0

var player: Player = null

var _joystick: DeepJoystick = null
var _mine: Button = null
var _jump: Button = null
var _place: Button = null
var _interact: Button = null
var _axis: float = 0.0
var _mine_held: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_stick()
	_build_actions()
	_build_menu_chips()
	EventBus.inventory_changed.connect(_refresh_place_button)
	_refresh_place_button()


func configure(p_player: Player) -> void:
	player = p_player


# --- Layout ------------------------------------------------------------------

func _build_stick() -> void:
	_joystick = DeepJoystick.new()
	_joystick.name = "Joystick"
	# Left third of the screen, bottom two-thirds: a generous thumb region.
	_joystick.anchor_left = 0.0
	_joystick.anchor_top = 0.28
	_joystick.anchor_right = 0.34
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 0.0
	_joystick.offset_top = 0.0
	_joystick.offset_right = 0.0
	_joystick.offset_bottom = 0.0
	_joystick.axis_changed.connect(_on_axis)
	add_child(_joystick)


func _build_actions() -> void:
	var cluster := Control.new()
	cluster.name = "ActionCluster"
	cluster.anchor_left = 1.0
	cluster.anchor_top = 1.0
	cluster.anchor_right = 1.0
	cluster.anchor_bottom = 1.0
	cluster.offset_left = 0.0
	cluster.offset_top = 0.0
	cluster.offset_right = 0.0
	cluster.offset_bottom = 0.0
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cluster)

	# MINE is the primary verb, so it gets the largest, lowest button.
	_mine = UiKit.round_button("⛏", JUMP_DIAMETER + 10.0, UiKit.ACCENT_WARM)
	_mine.tooltip_text = "Hold to mine"
	_mine.position = Vector2(-JUMP_DIAMETER - 108.0, -JUMP_DIAMETER - 56.0)
	_mine.button_down.connect(func() -> void: _mine_held = true)
	_mine.button_up.connect(func() -> void: _mine_held = false)
	cluster.add_child(_mine)

	_jump = UiKit.round_button("▲", JUMP_DIAMETER, UiKit.ACCENT)
	_jump.tooltip_text = "Jump"
	_jump.position = Vector2(-JUMP_DIAMETER - 20.0, -JUMP_DIAMETER - 124.0)
	_jump.pressed.connect(_on_jump)
	cluster.add_child(_jump)

	_place = UiKit.round_button("＋", SMALL_DIAMETER, UiKit.GOOD)
	_place.tooltip_text = "Place selected block"
	_place.position = Vector2(-SMALL_DIAMETER - 26.0, -SMALL_DIAMETER - 24.0)
	_place.pressed.connect(_on_place)
	cluster.add_child(_place)

	_interact = UiKit.round_button("✦", SMALL_DIAMETER, UiKit.LEGEND)
	_interact.tooltip_text = "Interact"
	_interact.position = Vector2(-SMALL_DIAMETER - 160.0, -SMALL_DIAMETER - 150.0)
	_interact.pressed.connect(_on_interact)
	cluster.add_child(_interact)


func _build_menu_chips() -> void:
	var row := HBoxContainer.new()
	row.name = "MenuChips"
	row.anchor_left = 1.0
	row.anchor_top = 0.0
	row.anchor_right = 1.0
	row.anchor_bottom = 0.0
	row.offset_left = -344.0
	row.offset_top = 12.0
	row.offset_right = -12.0
	row.offset_bottom = 54.0
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	add_child(row)

	for spec in [
		{"id": "inventory", "glyph": "PACK"},
		{"id": "craft", "glyph": "CRAFT"},
		{"id": "codex", "glyph": "CODEX"},
		{"id": "pause", "glyph": "☰"},
	]:
		var b := UiKit.button(str(spec["glyph"]), 38.0)
		b.custom_minimum_size.x = 56.0 if str(spec["id"]) == "pause" else 74.0
		b.add_theme_font_size_override("font_size", 12)
		var id := str(spec["id"])
		b.pressed.connect(func() -> void: menu_requested.emit(id))
		row.add_child(b)


# --- Input routing -----------------------------------------------------------

func _on_axis(value: float) -> void:
	_axis = value


func _on_jump() -> void:
	if player != null:
		player.want_jump = true


func _on_place() -> void:
	if player != null and player.mining_controller != null:
		player.mining_controller.set("place_requested", true)


func _on_interact() -> void:
	# The Game scene listens for this through the interact action, so the
	# touch button and the E key go down exactly the same path.
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if absf(_axis) > 0.001:
		player.move_axis = _axis
		# Past half deflection the player runs. Gives the stick two gears
		# without a separate run button.
		player.want_run = absf(_axis) > 0.55
	if player.mining_controller != null:
		player.mining_controller.set("mine_held", _mine_held or Input.is_action_pressed("mine"))


func _refresh_place_button() -> void:
	if _place == null:
		return
	var has_placeable := false
	if Game.inventory != null:
		for i in Game.inventory.slots.size():
			var id := Game.inventory.item_at(i)
			if not id.is_empty() and ItemDB.get_item(id).is_placeable():
				has_placeable = true
				break
	_place.disabled = not has_placeable
	_place.modulate.a = 1.0 if has_placeable else 0.45


func set_controls_visible(value: bool) -> void:
	visible = value
	if not value:
		_mine_held = false
		_axis = 0.0
