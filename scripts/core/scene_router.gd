extends Node
## Autoload: Router
##
## Scene changes with a fade, plus a lightweight loading card. Deliberately
## tiny: DEEP only has three screens (menu, game, and the in-game overlays).

signal transition_finished()

const FADE_IN: float = 0.22
const FADE_OUT: float = 0.30

var _layer: CanvasLayer
var _veil: ColorRect
var _label: Label
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)

	_veil = ColorRect.new()
	_veil.color = Color(0.016, 0.020, 0.031, 1.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	_veil.visible = false
	_layer.add_child(_veil)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = "DESCENDING…"
	_label.modulate = Color(0.62, 0.78, 0.86, 0.0)
	_label.add_theme_font_size_override("font_size", 22)
	_veil.add_child(_label)


func is_busy() -> bool:
	return _busy


## Fade to black, swap scene, fade back in.
func go_to(scene_path: String, caption: String = "DESCENDING…") -> void:
	if _busy:
		return
	_busy = true
	_label.text = caption
	_veil.visible = true
	_veil.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(_veil, "modulate:a", 1.0, FADE_IN)
	tw.parallel().tween_property(_label, "modulate:a", 0.9, FADE_IN)
	await tw.finished

	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("DEEP: failed to load scene %s (%d)" % [scene_path, err])
	# One idle frame so the new scene's _ready work happens behind the veil.
	await get_tree().process_frame
	await get_tree().process_frame

	var tw2 := create_tween()
	tw2.tween_property(_label, "modulate:a", 0.0, 0.12)
	tw2.parallel().tween_property(_veil, "modulate:a", 0.0, FADE_OUT)
	await tw2.finished
	_veil.visible = false
	_busy = false
	transition_finished.emit()


func to_game() -> void:
	go_to("res://scenes/game/Game.tscn", "DESCENDING…")


func to_menu() -> void:
	go_to("res://scenes/ui/MainMenu.tscn", "SURFACING…")
