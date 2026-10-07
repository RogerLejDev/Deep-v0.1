extends Control
## The in-game HUD. Minimal on purpose: vitality, depth, the equipped tool,
## and a quick bar. Everything else lives behind a panel.

const QUICK_SLOTS: int = 5

var _health_bar: ProgressBar
var _health_label: Label
var _depth_label: Label
var _depth_record: Label
var _zone_label: Label
var _tool_icon: TextureRect
var _tool_label: Label
var _codex_label: Label
var _quick_row: HBoxContainer
var _quick_buttons: Array[Button] = []
var _toast_box: VBoxContainer
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_phase: Label
var _prompt_label: Label
var _effect_row: HBoxContainer

var _tracked_boss: Creature = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_left()
	_build_depth()
	_build_quickbar()
	_build_toasts()
	_build_boss()
	_build_prompt()

	EventBus.player_health_changed.connect(_on_health)
	EventBus.player_depth_changed.connect(_on_depth)
	EventBus.depth_record_changed.connect(_on_record)
	EventBus.active_tool_changed.connect(func(_id: String) -> void: _refresh_tool())
	EventBus.inventory_changed.connect(_refresh_quickbar)
	EventBus.codex_progress_changed.connect(_on_codex_progress)
	EventBus.toast_requested.connect(show_toast)
	EventBus.interact_prompt_changed.connect(_on_prompt)
	EventBus.creature_spawned.connect(_on_creature_spawned)
	EventBus.biome_changed.connect(func(_z: String) -> void: _refresh_zone())

	_refresh_tool()
	_refresh_quickbar()
	_refresh_zone()
	if Game.codex != null:
		_on_codex_progress(Game.codex.discovered(), Game.codex.catalogued())


# --- Build -------------------------------------------------------------------

func _build_left() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_top = 0.0
	box.anchor_right = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = 14.0
	box.offset_top = 12.0
	box.offset_right = 254.0
	box.offset_bottom = 96.0
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 7)
	health_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(health_row)

	_health_label = UiKit.label("100", 13, UiKit.TEXT_BRIGHT)
	_health_label.custom_minimum_size.x = 30.0
	health_row.add_child(_health_label)

	_health_bar = UiKit.progress_bar(9.0, UiKit.GOOD)
	_health_bar.custom_minimum_size.x = 172.0
	health_row.add_child(_health_bar)

	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 7)
	tool_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tool_row)

	_tool_icon = TextureRect.new()
	_tool_icon.custom_minimum_size = Vector2(26, 26)
	_tool_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tool_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tool_row.add_child(_tool_icon)

	_tool_label = UiKit.label("", 12, UiKit.TEXT_DIM)
	tool_row.add_child(_tool_label)

	_effect_row = HBoxContainer.new()
	_effect_row.add_theme_constant_override("separation", 6)
	_effect_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_effect_row)


func _build_depth() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = -140.0
	box.offset_right = 140.0
	box.offset_top = 10.0
	box.offset_bottom = 92.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_depth_label = UiKit.label("0 m", 26, UiKit.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_depth_label)

	_zone_label = UiKit.label("", 10, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_zone_label)

	var meta := HBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 12)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(meta)

	_depth_record = UiKit.label("BEST 0 m", 10, UiKit.TEXT_DIM)
	meta.add_child(_depth_record)

	_codex_label = UiKit.label("CODEX 0/0", 10, UiKit.TEXT_DIM)
	meta.add_child(_codex_label)


func _build_quickbar() -> void:
	_quick_row = HBoxContainer.new()
	_quick_row.anchor_left = 0.5
	_quick_row.anchor_right = 0.5
	_quick_row.anchor_top = 1.0
	_quick_row.anchor_bottom = 1.0
	_quick_row.offset_left = -float(QUICK_SLOTS) * 29.0
	_quick_row.offset_right = float(QUICK_SLOTS) * 29.0
	_quick_row.offset_top = -62.0
	_quick_row.offset_bottom = -10.0
	_quick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_quick_row.add_theme_constant_override("separation", 6)
	add_child(_quick_row)

	for i in QUICK_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.035, 0.047, 0.067, 0.72), UiKit.EDGE))
		b.add_theme_stylebox_override("hover", UiKit.panel_style(Color(0.055, 0.082, 0.11, 0.85), UiKit.EDGE_HOT))
		b.add_theme_stylebox_override("pressed", UiKit.panel_style(Color(0.055, 0.153, 0.196, 0.95), UiKit.ACCENT))
		var idx := i
		b.pressed.connect(func() -> void: _on_quick_pressed(idx))
		_quick_row.add_child(b)
		_quick_buttons.append(b)


func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.anchor_top = 0.0
	_toast_box.anchor_bottom = 0.0
	_toast_box.offset_left = -220.0
	_toast_box.offset_right = 220.0
	_toast_box.offset_top = 96.0
	_toast_box.offset_bottom = 220.0
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)


func _build_boss() -> void:
	_boss_panel = UiKit.make_panel(Color(0.031, 0.027, 0.047, 0.88), Color(0.45, 0.33, 0.62))
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	_boss_panel.anchor_top = 1.0
	_boss_panel.anchor_bottom = 1.0
	_boss_panel.offset_left = -220.0
	_boss_panel.offset_right = 220.0
	_boss_panel.offset_top = -126.0
	_boss_panel.offset_bottom = -72.0
	_boss_panel.visible = false
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_boss_panel.add_child(col)

	_boss_name = UiKit.label("", 13, UiKit.LEGEND, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_boss_name)
	_boss_bar = UiKit.progress_bar(7.0, Color(0.72, 0.45, 1.0))
	col.add_child(_boss_bar)
	_boss_phase = UiKit.label("", 10, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_boss_phase)


func _build_prompt() -> void:
	_prompt_label = UiKit.label("", 13, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = -220.0
	_prompt_label.offset_right = 220.0
	_prompt_label.offset_top = -152.0
	_prompt_label.offset_bottom = -130.0
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt_label)


# --- Updates -----------------------------------------------------------------

func _on_health(current: float, maximum: float) -> void:
	var ratio: float = current / maxf(maximum, 1.0)
	_health_bar.value = ratio
	_health_label.text = str(int(round(current)))
	var fill := UiKit.GOOD
	if ratio < 0.3:
		fill = UiKit.DANGER
	elif ratio < 0.6:
		fill = UiKit.ACCENT_WARM
	var sb := _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if sb != null:
		sb.bg_color = fill


func _on_depth(metres: float) -> void:
	_depth_label.text = UiKit.format_metres(metres)
	_refresh_zone()


func _on_record(metres: float) -> void:
	_depth_record.text = "BEST %s" % UiKit.format_metres(metres)


func _refresh_zone() -> void:
	if Game.player == null or not is_instance_valid(Game.player):
		return
	var zone := BiomeTable.zone_for_depth(Game.player.depth_metres())
	_zone_label.text = zone.display_name


func _on_codex_progress(discovered: int, catalogued: int) -> void:
	_codex_label.text = "CODEX %d/%d" % [discovered, catalogued]


func _refresh_tool() -> void:
	var def := Game.tool_def()
	_tool_icon.texture = IconFactory.icon_for(def.id, 40)
	_tool_label.text = "%s  ·  POWER %.1f" % [def.display_name.to_upper(), def.tool_power]


func _refresh_quickbar() -> void:
	if Game.inventory == null:
		return
	# The quick bar mirrors the first few occupied slots: tools first, then
	# whatever else is to hand. No separate hotbar to manage.
	var picks: Array[int] = []
	for i in Game.inventory.slots.size():
		var id := Game.inventory.item_at(i)
		if id.is_empty():
			continue
		if ItemDB.get_item(id).is_tool():
			picks.append(i)
	for i in Game.inventory.slots.size():
		if picks.size() >= QUICK_SLOTS:
			break
		var id := Game.inventory.item_at(i)
		if id.is_empty() or i in picks:
			continue
		var def := ItemDB.get_item(id)
		if def.is_placeable() or def.category == ItemDef.Category.CONSUMABLE:
			picks.append(i)

	for s in QUICK_SLOTS:
		var b := _quick_buttons[s]
		if s >= picks.size():
			b.icon = null
			b.text = ""
			b.tooltip_text = ""
			b.set_meta("slot", -1)
			b.modulate.a = 0.45
			continue
		var slot := picks[s]
		var item := Game.inventory.item_at(slot)
		var d := ItemDB.get_item(item)
		b.icon = IconFactory.icon_for(item, 44)
		b.expand_icon = true
		var n := Game.inventory.count_at(slot)
		b.text = "" if d.is_tool() else str(n)
		b.add_theme_font_size_override("font_size", 11)
		b.tooltip_text = d.display_name
		b.set_meta("slot", slot)
		b.modulate.a = 1.0
		var selected := (item == Game.active_tool) or (item == Game.selected_placeable)
		b.add_theme_stylebox_override("normal", UiKit.panel_style(
			Color(0.055, 0.153, 0.196, 0.9) if selected else Color(0.035, 0.047, 0.067, 0.72),
			UiKit.ACCENT if selected else UiKit.EDGE))
	_refresh_effects()


func _on_quick_pressed(index: int) -> void:
	var b := _quick_buttons[index]
	var slot := int(b.get_meta("slot", -1))
	if slot < 0:
		return
	var item := Game.inventory.item_at(slot)
	if item.is_empty():
		return
	var def := ItemDB.get_item(item)
	Audio.play("ui_click", 1.0, -12.0)
	if def.is_tool():
		Game.set_active_tool(item)
	elif def.is_placeable():
		Game.selected_placeable = item
		EventBus.toast_requested.emit("PLACING " + def.display_name.to_upper(), "info")
	elif def.category == ItemDef.Category.CONSUMABLE:
		_consume(item, def)
	_refresh_quickbar()


func _consume(item: String, def: ItemDef) -> void:
	if Game.inventory.remove(item, 1) <= 0:
		return
	if def.heal > 0.0 and Game.player != null:
		Game.player.heal(def.heal)
	if def.effect_seconds > 0.0:
		Game.apply_effect(item, def.effect_seconds)
		EventBus.toast_requested.emit(def.display_name.to_upper() + " ACTIVE", "info")


func _refresh_effects() -> void:
	for child in _effect_row.get_children():
		child.queue_free()
	if Game.effects == null:
		return
	for id: String in Game.effects.keys():
		var chip := UiKit.label(
			"%s %ds" % [ItemDB.get_item(id).display_name.to_upper(), int(float(Game.effects[id]))],
			10, UiKit.ACCENT)
		_effect_row.add_child(chip)


func _on_prompt(text: String) -> void:
	_prompt_label.text = text


# --- Toasts ------------------------------------------------------------------

func show_toast(text: String, kind: String = "info") -> void:
	var colour := UiKit.toast_colour(kind)
	var size := 20 if kind == "legendary" else 14
	var l := UiKit.label(text, size, colour, HORIZONTAL_ALIGNMENT_CENTER)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	_toast_box.add_child(l)
	# Keep the stack short; the oldest toast goes first.
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()

	var hold: float = 2.6 if kind == "legendary" else 1.5
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.14)
	tw.parallel().tween_property(l, "position:y", l.position.y - 6.0, 0.14)
	tw.tween_interval(hold)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


# --- Boss bar ----------------------------------------------------------------

func _on_creature_spawned(c: Node2D) -> void:
	var creature := c as Creature
	if creature == null or not creature.is_boss():
		return
	_tracked_boss = creature
	_boss_name.text = creature.data.display_name.to_upper()
	_boss_panel.visible = true
	_boss_panel.modulate.a = 0.0
	var tw := _boss_panel.create_tween()
	tw.tween_property(_boss_panel, "modulate:a", 1.0, 0.5)
	creature.died.connect(func(_x: Creature) -> void: _hide_boss())
	creature.tree_exiting.connect(func() -> void: _hide_boss())


func _hide_boss() -> void:
	_tracked_boss = null
	if _boss_panel == null:
		return
	var tw := _boss_panel.create_tween()
	tw.tween_property(_boss_panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: _boss_panel.visible = false)


func _process(_delta: float) -> void:
	if _tracked_boss != null and is_instance_valid(_tracked_boss):
		_boss_bar.value = _tracked_boss.hp_ratio()
		_boss_phase.text = _tracked_boss.apex_phase_name()
	if Game.effects != null and not Game.effects.is_empty():
		_refresh_effects()
