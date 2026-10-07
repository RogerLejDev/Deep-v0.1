class_name ItemSlot
extends Button
## One inventory cell: icon, stack count, rarity-ish tint, selection ring.

signal slot_activated(index: int)

const SIZE: float = 56.0

var index: int = -1
var _count_label: Label = null
var _selected: bool = false


func _init(p_index: int = -1) -> void:
	index = p_index
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_style(false)


func _ready() -> void:
	_count_label = UiKit.label("", 11, UiKit.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_count_label.anchor_left = 0.0
	_count_label.anchor_top = 1.0
	_count_label.anchor_right = 1.0
	_count_label.anchor_bottom = 1.0
	_count_label.offset_left = 4.0
	_count_label.offset_top = -17.0
	_count_label.offset_right = -4.0
	_count_label.offset_bottom = -3.0
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)
	pressed.connect(func() -> void: slot_activated.emit(index))


func refresh(inv: Inventory) -> void:
	var id := inv.item_at(index)
	if id.is_empty():
		icon = null
		_count_label.text = ""
		tooltip_text = ""
		return
	var def := ItemDB.get_item(id)
	icon = IconFactory.icon_for(id, 48)
	var n := inv.count_at(index)
	_count_label.text = str(n) if n > 1 else ""
	tooltip_text = "%s\n%s" % [def.display_name, def.description]


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_apply_style(value)


func _apply_style(selected: bool) -> void:
	var fill := Color(0.055, 0.153, 0.196, 0.95) if selected else Color(0.035, 0.047, 0.067, 0.85)
	var edge := UiKit.ACCENT if selected else UiKit.EDGE
	add_theme_stylebox_override("normal", UiKit.panel_style(fill, edge, 2 if selected else 1))
	add_theme_stylebox_override("hover", UiKit.panel_style(
		Color(0.071, 0.106, 0.145, 0.95), UiKit.EDGE_HOT, 2 if selected else 1))
	add_theme_stylebox_override("pressed", UiKit.panel_style(
		Color(0.055, 0.153, 0.196, 1.0), UiKit.ACCENT, 2))
