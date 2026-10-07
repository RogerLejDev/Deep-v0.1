extends Control
## Title screen and save-slot select.
##
## Everything is local: three slots on disk, a seed you can type, no accounts,
## no network. The background is the same procedural backdrop shader the game
## uses, slowly drifting, so the title screen already sells the mood.

const BACKDROP_SHADER: String = "res://shaders/backdrop.gdshader"

var _backdrop_mat: ShaderMaterial
var _slot_rows: VBoxContainer
var _seed_field: LineEdit
var _drift: float = 0.0
var _selected_slot: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_layout()
	RenderingServer.global_shader_parameter_set("deep_ambient", Vector3(1.0, 1.0, 1.0))
	RenderingServer.global_shader_parameter_set("deep_light_count", 0)
	Audio.set_ambience("amb_surface")


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = load(BACKDROP_SHADER) as Shader
	_backdrop_mat.set_shader_parameter("surface_y", 1024.0)
	_backdrop_mat.set_shader_parameter("world_bottom_y", 11264.0)
	_backdrop_mat.set_shader_parameter("underground", 0.0)
	_backdrop_mat.set_shader_parameter("ambient_light", Vector3(0.95, 0.96, 1.0))
	_backdrop_mat.set_shader_parameter("zone_tint", Vector3(0.22, 0.30, 0.40))
	_backdrop_mat.set_shader_parameter("view_size", Vector2(1280, 720))
	bg.material = _backdrop_mat
	add_child(bg)

	# Vignette so the text block always has contrast over the art.
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.008, 0.012, 0.024, 0.55)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


func _build_layout() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 64.0
	root.offset_right = -64.0
	root.offset_top = 48.0
	root.offset_bottom = -40.0
	root.add_theme_constant_override("separation", 42)
	add_child(root)

	# --- title block ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 2)
	root.add_child(left)

	var title := UiKit.label(UiKit._tracked("DEEP"), 88, UiKit.TEXT_BRIGHT)
	left.add_child(title)
	var tagline := UiKit.label(UiKit._tracked("GO DEEPER. FIND LIFE."), 15, UiKit.ACCENT)
	left.add_child(tagline)
	left.add_child(UiKit.spacer(14))
	var blurb := UiKit.body(
		"Something is living under the Rootlands.\n"
		+ "Dig, descend, and record every form of it you can survive long enough to watch.",
		13, UiKit.TEXT_DIM)
	blurb.custom_minimum_size.x = 400.0
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(blurb)
	left.add_child(UiKit.spacer(10))
	left.add_child(UiKit.label("V0.1  ·  OFFLINE  ·  LOCAL SAVES", 10, Color(0.35, 0.41, 0.46)))

	# Slow drift on the title so the screen is never fully static.
	var tw := create_tween().set_loops()
	tw.tween_property(tagline, "modulate:a", 0.55, 2.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(tagline, "modulate:a", 1.0, 2.4).set_trans(Tween.TRANS_SINE)

	# --- slots ---
	var card := UiKit.make_panel(Color(0.016, 0.024, 0.039, 0.9), UiKit.EDGE)
	card.custom_minimum_size.x = 420.0
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	col.add_child(UiKit.heading("expeditions", 13))
	col.add_child(UiKit.separator())

	_slot_rows = VBoxContainer.new()
	_slot_rows.add_theme_constant_override("separation", 7)
	col.add_child(_slot_rows)

	col.add_child(UiKit.spacer(4))
	col.add_child(UiKit.heading("world seed", 11))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	col.add_child(seed_row)

	_seed_field = LineEdit.new()
	_seed_field.placeholder_text = "leave blank for a random world"
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_field.custom_minimum_size.y = 40.0
	_seed_field.add_theme_stylebox_override("normal",
		UiKit.panel_style(Color(0.031, 0.043, 0.059, 0.9), UiKit.EDGE))
	_seed_field.add_theme_stylebox_override("focus",
		UiKit.panel_style(Color(0.039, 0.067, 0.086, 0.95), UiKit.ACCENT))
	_seed_field.add_theme_color_override("font_color", UiKit.TEXT)
	_seed_field.add_theme_color_override("font_placeholder_color", Color(0.3, 0.35, 0.4))
	seed_row.add_child(_seed_field)

	var dice := UiKit.button("RANDOM", 40.0)
	dice.custom_minimum_size.x = 92.0
	dice.pressed.connect(func() -> void:
		_seed_field.text = str(randi() % 100000000))
	seed_row.add_child(dice)

	col.add_child(UiKit.spacer(2))
	var quit := UiKit.button("QUIT", 40.0)
	quit.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(quit)

	_refresh_slots()


func _refresh_slots() -> void:
	for c in _slot_rows.get_children():
		c.queue_free()
	for summary in SaveManager.all_summaries():
		_slot_rows.add_child(_make_slot_row(summary))


func _make_slot_row(summary: Dictionary) -> Control:
	var slot := int(summary["slot"])
	var exists := bool(summary.get("exists", false))

	var panel := UiKit.make_panel(
		Color(0.024, 0.035, 0.051, 0.9) if exists else Color(0.016, 0.02, 0.028, 0.75),
		UiKit.EDGE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	info.add_child(UiKit.label("SLOT %d" % (slot + 1), 13, UiKit.TEXT_BRIGHT))
	if exists:
		info.add_child(UiKit.label(
			"%s  ·  CODEX %d  ·  %s" % [
				UiKit.format_metres(float(summary.get("deepest_metres", 0.0))),
				int(summary.get("discovered", 0)),
				UiKit.format_playtime(float(summary.get("playtime", 0.0)))],
			11, UiKit.TEXT_DIM))
		info.add_child(UiKit.label("SEED %d" % int(summary.get("seed", 0)), 10, Color(0.32, 0.38, 0.43)))
	else:
		info.add_child(UiKit.label("EMPTY", 11, UiKit.TEXT_DIM))

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	row.add_child(actions)

	if exists:
		var cont := UiKit.button("CONTINUE", 36.0)
		cont.custom_minimum_size.x = 112.0
		cont.add_theme_font_size_override("font_size", 12)
		cont.pressed.connect(func() -> void: _load_slot(slot))
		actions.add_child(cont)

		var fresh := UiKit.button("NEW WORLD", 28.0)
		fresh.add_theme_font_size_override("font_size", 10)
		fresh.pressed.connect(func() -> void: _confirm_overwrite(slot))
		actions.add_child(fresh)
	else:
		var start := UiKit.button("DESCEND", 36.0)
		start.custom_minimum_size.x = 112.0
		start.add_theme_font_size_override("font_size", 12)
		start.pressed.connect(func() -> void: _new_slot(slot))
		actions.add_child(start)

	return panel


func _parse_seed() -> int:
	var text := _seed_field.text.strip_edges()
	if text.is_empty():
		return int(randi()) ^ int(Time.get_ticks_usec() & 0x7FFFFFFF)
	if text.is_valid_int():
		return absi(int(text))
	# Any text is a valid seed; hash it so "rootlands" is a world.
	return absi(text.hash())


func _new_slot(slot: int) -> void:
	var seed_value := _parse_seed()
	Game.new_run(seed_value, slot)
	SaveManager.delete_slot(slot)
	Router.to_game()


func _confirm_overwrite(slot: int) -> void:
	# A second tap within the confirm window actually overwrites.
	if _selected_slot == slot:
		_selected_slot = -1
		_new_slot(slot)
		return
	_selected_slot = slot
	EventBus.toast_requested.emit("TAP NEW WORLD AGAIN TO OVERWRITE SLOT %d" % (slot + 1), "warn")
	_flash_warning(slot)


func _flash_warning(slot: int) -> void:
	var label := UiKit.label(
		"Slot %d will be erased. Tap NEW WORLD again to confirm." % (slot + 1),
		11, UiKit.ACCENT_WARM, HORIZONTAL_ALIGNMENT_CENTER)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -260.0
	label.offset_right = 260.0
	label.offset_top = -56.0
	label.offset_bottom = -32.0
	add_child(label)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void:
		if _selected_slot == slot:
			_selected_slot = -1
		label.queue_free())


func _load_slot(slot: int) -> void:
	var payload := SaveManager.read_slot(slot)
	if payload.is_empty():
		EventBus.toast_requested.emit("SLOT %d IS DAMAGED AND CANNOT BE READ" % (slot + 1), "warn")
		_flash_warning(slot)
		return
	Game.apply_payload(payload, slot)
	Game.pending_load = payload
	Router.to_game()


func _process(delta: float) -> void:
	_drift += delta
	if _backdrop_mat == null:
		return
	_backdrop_mat.set_shader_parameter("drift", _drift)
	# Slowly pan the backdrop so the menu breathes.
	_backdrop_mat.set_shader_parameter("view_origin", Vector2(_drift * 7.0, 760.0 + sin(_drift * 0.13) * 30.0))
	_backdrop_mat.set_shader_parameter("view_size", size)
