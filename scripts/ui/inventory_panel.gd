extends ModalPanel
## The pack. Tap a slot to inspect it; tap a second slot to move the stack.
## Touch-first: no drag required, every action is a tap on a 56px target.

const COLUMNS: int = 8

var _grid: GridContainer = null
var _slots: Array[ItemSlot] = []
var _detail_icon: TextureRect = null
var _detail_name: Label = null
var _detail_kind: Label = null
var _detail_body: RichTextLabel = null
var _detail_stats: Label = null
var _action_row: HBoxContainer = null
var _chest_note: Label = null

var _selected: int = -1
var _inventory: Inventory = null
var _chest_mode: bool = false


func build_content() -> void:
	set_titles("Pack", "")

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)

	# --- grid ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	_chest_note = UiKit.label("", 11, UiKit.TEXT_DIM)
	left.add_child(_chest_note)

	# --- detail ---
	var right := UiKit.make_panel(Color(0.02, 0.027, 0.043, 0.9), UiKit.EDGE)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 300.0
	columns.add_child(right)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	right.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)

	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(60, 60)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_detail_icon)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 1)
	head.add_child(names)
	_detail_name = UiKit.label("NOTHING SELECTED", 15, UiKit.TEXT_BRIGHT)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_detail_name)
	_detail_kind = UiKit.label("", 10, UiKit.ACCENT)
	names.add_child(_detail_kind)

	col.add_child(UiKit.separator())

	_detail_body = UiKit.body("Tap a slot to inspect it.", 12, UiKit.TEXT)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_detail_body)

	_detail_stats = UiKit.label("", 11, UiKit.TEXT_DIM)
	_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_detail_stats)

	col.add_child(UiKit.spacer(6))
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 6)
	col.add_child(_action_row)


func bind(inv: Inventory, chest_mode: bool = false) -> void:
	_inventory = inv
	_chest_mode = chest_mode
	_selected = -1
	_rebuild_grid()


func on_opened() -> void:
	if _inventory == null:
		_inventory = Game.inventory
	_rebuild_grid()
	_refresh_detail()


func _rebuild_grid() -> void:
	if _inventory == null:
		return
	# Only rebuild the slot nodes when the capacity actually changed.
	if _slots.size() != _inventory.capacity:
		for s in _slots:
			s.queue_free()
		_slots.clear()
		for i in _inventory.capacity:
			var slot := ItemSlot.new(i)
			slot.slot_activated.connect(_on_slot)
			_grid.add_child(slot)
			_slots.append(slot)
	for i in _slots.size():
		_slots[i].refresh(_inventory)
		_slots[i].set_selected(i == _selected)
	set_titles(
		"Chest" if _chest_mode else "Pack",
		"%d / %d SLOTS USED" % [_inventory.used_slots(), _inventory.capacity])
	_chest_note.text = (
		"Tap a slot, then tap another to move the stack."
		if not _chest_mode else
		"Chest storage. Items here are safe from death drops."
	)


func _on_slot(index: int) -> void:
	Audio.play("ui_click", 1.05, -14.0)
	if _selected >= 0 and _selected != index:
		# Second tap = move/merge.
		if not _inventory.is_empty_slot(_selected):
			_inventory.move(_selected, index)
			_selected = index
			_rebuild_grid()
			_refresh_detail()
			return
	_selected = -1 if _selected == index else index
	_rebuild_grid()
	_refresh_detail()


func _refresh_detail() -> void:
	for c in _action_row.get_children():
		c.queue_free()

	if _selected < 0 or _inventory == null or _inventory.is_empty_slot(_selected):
		_detail_icon.texture = null
		_detail_name.text = "NOTHING SELECTED"
		_detail_kind.text = ""
		_detail_body.text = "Tap a slot to inspect it."
		_detail_stats.text = ""
		return

	var id := _inventory.item_at(_selected)
	var def := ItemDB.get_item(id)
	_detail_icon.texture = IconFactory.icon_for(id, 72)
	_detail_name.text = def.display_name.to_upper()
	_detail_kind.text = "%s  ·  x%d" % [def.category_name(), _inventory.count_at(_selected)]
	_detail_body.text = def.description

	var stats: Array[String] = []
	if def.is_tool():
		stats.append("Mining power %.2f" % def.tool_power)
		stats.append("Breaks tier %d materials" % def.tool_tier)
		stats.append("Melee %d" % int(def.tool_damage))
	if def.is_placeable():
		stats.append("Places: " + BlockDB.get_block(def.place_block).display_name)
	if def.heal > 0.0:
		stats.append("Restores %d vitality" % int(def.heal))
	if def.effect_seconds > 0.0:
		stats.append("Lasts %d seconds" % int(def.effect_seconds))
	if def.light_radius > 0.0:
		stats.append("Light radius +%d" % int(def.light_radius))
	_detail_stats.text = "\n".join(stats)

	_build_actions(id, def)


func _build_actions(id: String, def: ItemDef) -> void:
	if _chest_mode:
		var take := UiKit.button("TAKE", 40.0)
		take.pressed.connect(func() -> void: _transfer(Game.chest, Game.inventory))
		_action_row.add_child(take)
		return

	if def.is_tool():
		var equip := UiKit.button("EQUIP", 40.0)
		equip.disabled = (id == Game.active_tool)
		equip.pressed.connect(func() -> void:
			Game.set_active_tool(id)
			_refresh_detail())
		_action_row.add_child(equip)

	if def.is_placeable():
		var sel := UiKit.button("SELECT", 40.0)
		sel.pressed.connect(func() -> void:
			Game.selected_placeable = id
			EventBus.toast_requested.emit("PLACING " + def.display_name.to_upper(), "info")
			EventBus.inventory_changed.emit())
		_action_row.add_child(sel)

	if def.category == ItemDef.Category.CONSUMABLE:
		var use := UiKit.button("USE", 40.0)
		use.pressed.connect(func() -> void: _use(id, def))
		_action_row.add_child(use)

	if Game.chest != null and not def.is_tool():
		var store := UiKit.button("STORE", 40.0)
		store.pressed.connect(func() -> void: _transfer(Game.inventory, Game.chest))
		_action_row.add_child(store)


func _use(id: String, def: ItemDef) -> void:
	if Game.inventory.remove(id, 1) <= 0:
		return
	if def.heal > 0.0 and Game.player != null:
		Game.player.heal(def.heal)
	if def.effect_seconds > 0.0:
		Game.apply_effect(id, def.effect_seconds)
	_rebuild_grid()
	_refresh_detail()


func _transfer(from: Inventory, to: Inventory) -> void:
	if _selected < 0 or from == null or to == null:
		return
	var id := from.item_at(_selected)
	var n := from.count_at(_selected)
	if id.is_empty() or n <= 0:
		return
	var leftover := to.add(id, n)
	from.remove_at(_selected, n - leftover)
	if leftover > 0:
		EventBus.toast_requested.emit("DESTINATION FULL", "warn")
	_selected = -1
	_rebuild_grid()
	_refresh_detail()
