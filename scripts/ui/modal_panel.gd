class_name ModalPanel
extends Control
## Shared chrome for the three full-screen panels (pack, crafting, Codex):
## scrim, framed card, tracked title, close button, and an open/close
## animation. Subclasses fill `content` and override `on_opened`.

signal closed()

var content: VBoxContainer = null
var title_label: Label = null
var subtitle_label: Label = null

var _card: PanelContainer = null
var _scrim: ColorRect = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	_scrim = UiKit.scrim(0.74)
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_card = UiKit.make_panel(Color(0.027, 0.035, 0.055, 0.985), UiKit.EDGE)
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.offset_left = 44.0
	_card.offset_right = -44.0
	_card.offset_top = 26.0
	_card.offset_bottom = -26.0
	add_child(_card)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_card.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	title_label = UiKit.label("", 19, UiKit.TEXT_BRIGHT)
	titles.add_child(title_label)
	subtitle_label = UiKit.label("", 11, UiKit.TEXT_DIM)
	titles.add_child(subtitle_label)

	var close := UiKit.round_button("✕", 44.0, UiKit.TEXT_DIM)
	close.pressed.connect(close_panel)
	header.add_child(close)

	root.add_child(UiKit.separator())

	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	root.add_child(content)

	build_content()


## Subclasses build their widgets here.
func build_content() -> void:
	pass


## Subclasses refresh live data here.
func on_opened() -> void:
	pass


func set_titles(title: String, subtitle: String) -> void:
	title_label.text = UiKit._tracked(title.to_upper())
	subtitle_label.text = subtitle


func open_panel() -> void:
	if visible:
		return
	visible = true
	on_opened()
	Audio.play("ui_click", 0.9, -10.0)
	_card.scale = Vector2(0.985, 0.985)
	_card.pivot_offset = _card.size * 0.5
	modulate.a = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.14)
	tw.parallel().tween_property(_card, "scale", Vector2.ONE, 0.18)


func close_panel() -> void:
	if not visible:
		return
	Audio.play("ui_click", 0.7, -14.0)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit())


func toggle_panel() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func _on_scrim_input(event: InputEvent) -> void:
	# Tapping outside the card closes, which is what a thumb expects.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_panel()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		close_panel()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			close_panel()
			accept_event()
