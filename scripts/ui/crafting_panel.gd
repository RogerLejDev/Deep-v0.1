extends ModalPanel
## Crafting. Every recipe is always listed, including ones you cannot make yet,
## because seeing "Iron Pick — needs 10 iron ore" is the thing that sends a
## player back down.

var station: String = ""

var _list: VBoxContainer = null
var _rows: Array[Dictionary] = []


func build_content() -> void:
	set_titles("Fabrication", "")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_list)


func set_station(value: String) -> void:
	station = value


func on_opened() -> void:
	set_titles(
		"Fabrication",
		("AT THE WORKBENCH — FULL RECIPE LIST" if station == "workbench"
			else "IN THE FIELD — BENCH RECIPES NEED THE BASE WORKBENCH"))
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()

	var by_category: Dictionary = {}
	for r in RecipeDB.all():
		var arr: Array = by_category.get(r.category, [])
		arr.append(r)
		by_category[r.category] = arr

	for category: String in ["tools", "gear", "light", "building", "survival", "misc"]:
		if not by_category.has(category):
			continue
		_list.add_child(UiKit.heading(category, 12))
		for item in by_category[category]:
			_list.add_child(_make_row(item as RecipeDB.Recipe))
		_list.add_child(UiKit.spacer(4))


func _make_row(recipe: RecipeDB.Recipe) -> Control:
	var status := CraftingSystem.can_craft(Game.inventory, recipe, station)
	var ok := status == CraftingSystem.Result.OK

	var card := UiKit.make_panel(
		Color(0.031, 0.043, 0.059, 0.85) if ok else Color(0.024, 0.028, 0.035, 0.7),
		UiKit.EDGE_HOT if ok else UiKit.EDGE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	card.add_child(row)

	var out_def := ItemDB.get_item(recipe.output_id)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(46, 46)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = IconFactory.icon_for(recipe.output_id, 48)
	icon.modulate.a = 1.0 if ok else 0.45
	row.add_child(icon)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)

	var title := "%s" % out_def.display_name.to_upper()
	if recipe.output_count > 1:
		title += "  ×%d" % recipe.output_count
	mid.add_child(UiKit.label(title, 14, UiKit.TEXT_BRIGHT if ok else UiKit.TEXT_DIM))

	# Ingredient line, with held/needed counts coloured per ingredient.
	var ing := HBoxContainer.new()
	ing.add_theme_constant_override("separation", 10)
	mid.add_child(ing)
	for entry in recipe.input_list():
		var need := int(entry["n"])
		var iid := str(entry["id"])
		var have := Game.inventory.count(iid)
		var enough := have >= need
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		var ii := TextureRect.new()
		ii.custom_minimum_size = Vector2(18, 18)
		ii.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ii.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ii.texture = IconFactory.icon_for(iid, 24)
		ii.modulate.a = 1.0 if enough else 0.5
		chip.add_child(ii)
		chip.add_child(UiKit.label(
			"%d/%d" % [have, need], 11,
			UiKit.GOOD if enough else UiKit.DANGER))
		ing.add_child(chip)

	var note := UiKit.label(recipe.unlock_note, 10, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(note)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size.x = 124.0
	row.add_child(right)

	var btn := UiKit.button("CRAFT" if ok else CraftingSystem.reason_text(status), 42.0)
	btn.disabled = not ok
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(func() -> void: _craft(recipe))
	right.add_child(btn)

	if not recipe.station.is_empty():
		right.add_child(UiKit.label(recipe.station.to_upper(), 9, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	_rows.append({"recipe": recipe, "card": card})
	return card


func _craft(recipe: RecipeDB.Recipe) -> void:
	var result := CraftingSystem.craft(Game.inventory, recipe, station)
	if result != CraftingSystem.Result.OK:
		EventBus.toast_requested.emit(CraftingSystem.reason_text(result), "warn")
		_rebuild()
		return
	Game.bump_stat("items_crafted")
	var def := ItemDB.get_item(recipe.output_id)
	EventBus.toast_requested.emit("CRAFTED " + def.display_name.to_upper(), "save")
	# A better pick is always what you wanted; equip it immediately.
	if def.is_tool() and def.tool_power > Game.tool_def().tool_power:
		Game.set_active_tool(recipe.output_id)
		EventBus.toast_requested.emit("EQUIPPED " + def.display_name.to_upper(), "info")
	_rebuild()
