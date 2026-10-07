extends ModalPanel
## CREATURE CODEX.
##
## The design rule this UI exists to express: *seeing is not knowing*. An
## undiscovered species is a numbered silhouette with no name. A discovered one
## opens its page, but every field is `???` until the player has actually
## watched that species long enough to learn it. The observation meter on the
## right is therefore the real progress bar of the game.

const ILLUSTRATION_HEIGHT: int = 168
const ROW_ART_HEIGHT: int = 44

var _entry_list: VBoxContainer = null
var _progress_bar: ProgressBar = null
var _progress_label: Label = null

var _art: TextureRect = null
var _name_label: Label = null
var _number_label: Label = null
var _rarity_label: Label = null
var _obs_bar: ProgressBar = null
var _obs_label: Label = null
var _fields_box: VBoxContainer = null
var _variant_box: HBoxContainer = null
var _stats_label: Label = null

var _selected: String = ""
var _rows: Dictionary = {}


func build_content() -> void:
	set_titles("Creature Codex", "")

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	content.add_child(head)
	_progress_label = UiKit.label("0 / 0 DISCOVERED", 12, UiKit.ACCENT)
	head.add_child(_progress_label)
	_progress_bar = UiKit.progress_bar(5.0, UiKit.ACCENT)
	head.add_child(_progress_bar)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)

	# --- entry list ---
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 288.0
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)

	_entry_list = VBoxContainer.new()
	_entry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_entry_list)

	# --- detail page ---
	var page := UiKit.make_panel(Color(0.016, 0.024, 0.039, 0.92), UiKit.EDGE)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(page)

	var page_scroll := ScrollContainer.new()
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(page_scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	page_scroll.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)

	# The plate the illustration sits on, so art always has a frame.
	var plate := UiKit.make_panel(Color(0.027, 0.047, 0.059, 0.9), UiKit.EDGE)
	plate.custom_minimum_size = Vector2(216, ILLUSTRATION_HEIGHT + 40)
	top.add_child(plate)
	# A margin inside the plate, so wide art (the Lumreaper is 96 units across
	# a 64-unit frame) is never clipped by the frame it sits in.
	var art_margin := MarginContainer.new()
	art_margin.add_theme_constant_override("margin_left", 8)
	art_margin.add_theme_constant_override("margin_right", 8)
	art_margin.add_theme_constant_override("margin_top", 8)
	art_margin.add_theme_constant_override("margin_bottom", 8)
	plate.add_child(art_margin)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.custom_minimum_size = Vector2(180, ILLUSTRATION_HEIGHT)
	art_margin.add_child(_art)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 3)
	top.add_child(titles)

	_number_label = UiKit.label("", 11, UiKit.TEXT_DIM)
	titles.add_child(_number_label)
	_name_label = UiKit.label("SELECT AN ENTRY", 24, UiKit.TEXT_BRIGHT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_name_label)
	_rarity_label = UiKit.label("", 11, UiKit.TEXT_DIM)
	titles.add_child(_rarity_label)

	titles.add_child(UiKit.spacer(5))
	_obs_label = UiKit.label("OBSERVATION", 10, UiKit.TEXT_DIM)
	titles.add_child(_obs_label)
	_obs_bar = UiKit.progress_bar(5.0, UiKit.ACCENT_WARM)
	titles.add_child(_obs_bar)

	titles.add_child(UiKit.spacer(5))
	_stats_label = UiKit.label("", 11, UiKit.TEXT_DIM)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_stats_label)

	col.add_child(UiKit.separator())

	_fields_box = VBoxContainer.new()
	_fields_box.add_theme_constant_override("separation", 7)
	col.add_child(_fields_box)

	col.add_child(UiKit.separator())
	col.add_child(UiKit.heading("variants", 11))
	_variant_box = HBoxContainer.new()
	_variant_box.add_theme_constant_override("separation", 8)
	col.add_child(_variant_box)


func on_opened() -> void:
	_rebuild_list()
	if _selected.is_empty():
		var ids := CreatureDB.species_ids()
		# Open on the first discovered entry if there is one.
		for id in ids:
			if Game.codex.is_sighted(id):
				_selected = id
				break
		if _selected.is_empty() and not ids.is_empty():
			_selected = ids[0]
	_show_entry(_selected)


# --- Entry list --------------------------------------------------------------

func _rebuild_list() -> void:
	for c in _entry_list.get_children():
		c.queue_free()
	_rows.clear()

	var codex := Game.codex
	var discovered := codex.discovered()
	var catalogued := codex.catalogued()
	_progress_label.text = "%d / %d DISCOVERED    ·    ARCHIVE SLOTS %d" % [
		discovered, catalogued, codex.planned_slots()
	]
	_progress_bar.value = float(discovered) / maxf(float(catalogued), 1.0)

	for id in CreatureDB.species_ids():
		var row := _make_row(id)
		_entry_list.add_child(row)
		_rows[id] = row

	_entry_list.add_child(UiKit.spacer(6))
	var note := UiKit.label(
		"This build catalogues %d of a planned %d archive slots. Entries fill in as you observe."
			% [catalogued, codex.planned_slots()],
		10, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entry_list.add_child(note)


func _make_row(species_id: String) -> Control:
	var data := CreatureDB.get_species(species_id)
	var codex := Game.codex
	var known := codex.is_sighted(species_id)
	var completion := codex.completion(species_id)

	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 58)
	b.focus_mode = Control.FOCUS_NONE
	var selected := species_id == _selected
	b.add_theme_stylebox_override("normal", UiKit.panel_style(
		Color(0.047, 0.098, 0.125, 0.9) if selected else Color(0.024, 0.031, 0.047, 0.8),
		UiKit.ACCENT if selected else UiKit.EDGE, 2 if selected else 1))
	b.add_theme_stylebox_override("hover", UiKit.panel_style(
		Color(0.055, 0.106, 0.133, 0.95), UiKit.EDGE_HOT, 2 if selected else 1))
	b.add_theme_stylebox_override("pressed", UiKit.panel_style(
		Color(0.055, 0.153, 0.196, 1.0), UiKit.ACCENT, 2))
	b.pressed.connect(func() -> void: _on_row(species_id))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8.0
	row.offset_right = -8.0
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(44, 44)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if data.art_path.is_empty():
		thumb.texture = null
	elif known:
		thumb.texture = SvgFactory.sprite(data.art_path, ROW_ART_HEIGHT)
	else:
		thumb.texture = SvgFactory.silhouette(data.art_path, ROW_ART_HEIGHT, Color(0.11, 0.13, 0.18))
	row.add_child(thumb)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)

	var label_text := data.display_name.to_upper() if known else "???"
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 7)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(name_row)
	name_row.add_child(UiKit.label("%03d" % data.codex_number, 11, UiKit.TEXT_DIM))
	name_row.add_child(UiKit.label(label_text, 13,
		UiKit.TEXT_BRIGHT if known else UiKit.TEXT_DIM))

	if known:
		var bar := UiKit.progress_bar(3.0, UiKit.rarity_colour(data.rarity))
		bar.value = completion
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(bar)
		mid.add_child(UiKit.label("%d%% COMPLETE" % int(completion * 100.0), 9, UiKit.TEXT_DIM))
	else:
		mid.add_child(UiKit.label("UNRECORDED SPECIMEN", 9, UiKit.TEXT_DIM))

	return b


func _on_row(species_id: String) -> void:
	Audio.play("ui_click", 1.0, -13.0)
	_selected = species_id
	_rebuild_list()
	_show_entry(species_id)


# --- Detail page -------------------------------------------------------------

func _show_entry(species_id: String) -> void:
	for c in _fields_box.get_children():
		c.queue_free()
	for c in _variant_box.get_children():
		c.queue_free()

	if species_id.is_empty():
		return
	var data := CreatureDB.get_species(species_id)
	var codex := Game.codex
	var known := codex.is_sighted(species_id)

	_number_label.text = "SPECIMEN %03d  ·  ROOTLANDS" % data.codex_number
	_name_label.text = data.display_name.to_upper() if known else "???"
	_name_label.add_theme_color_override("font_color",
		UiKit.TEXT_BRIGHT if known else UiKit.TEXT_DIM)

	if data.art_path.is_empty():
		_art.texture = null
	elif known:
		_art.texture = SvgFactory.sprite(data.art_path, ILLUSTRATION_HEIGHT)
	else:
		_art.texture = SvgFactory.silhouette(data.art_path, ILLUSTRATION_HEIGHT, Color(0.09, 0.11, 0.16))
	# Nudge wide species down a size so they sit inside the plate rather than
	# against its edges.
	if _art.texture != null and _art.texture.get_width() > 190:
		var shrunk: int = int(round(float(ILLUSTRATION_HEIGHT) * 190.0 / float(_art.texture.get_width())))
		_art.texture = (SvgFactory.sprite(data.art_path, shrunk) if known
			else SvgFactory.silhouette(data.art_path, shrunk, Color(0.09, 0.11, 0.16)))

	if known:
		_rarity_label.text = data.rarity_name()
		_rarity_label.add_theme_color_override("font_color", UiKit.rarity_colour(data.rarity))
	else:
		_rarity_label.text = "RARITY ???"
		_rarity_label.add_theme_color_override("font_color", UiKit.TEXT_DIM)

	var obs := codex.observation(species_id)
	_obs_bar.value = obs / GameConfig.OBSERVATION_FULL
	_obs_label.text = "OBSERVATION  %.1f / %.1f s" % [obs, GameConfig.OBSERVATION_FULL]

	if known:
		var e := codex.entry(species_id)
		_stats_label.text = "\n".join([
			"Sightings: %d" % int(e.get("sightings", 0)),
			"Depth range seen: %s – %s" % [
				UiKit.format_metres(float(e.get("min_depth", 0.0))),
				UiKit.format_metres(float(e.get("max_depth", 0.0)))],
			"Specimens defeated: %d" % int(e.get("defeated", 0)),
		])
	else:
		_stats_label.text = "Sightings: 0\nDepth range seen: ???\nSpecimens defeated: 0"

	# --- progressive fields ---
	for field in Codex.FIELDS:
		_fields_box.add_child(_make_field(species_id, data, field, known))

	# --- variants ---
	var seen := codex.known_variants(species_id)
	for v in data.variants:
		_variant_box.add_child(_make_variant_chip(data, v, v.id in seen and known))


func _make_field(species_id: String, data: CreatureData, field: String, known: bool) -> Control:
	var unlocked := known and Game.codex.is_field_known(species_id, field)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	header.add_child(UiKit.heading(field, 10))
	if not unlocked:
		var need: float = float(Codex.FIELD_THRESHOLDS.get(field, 0.0))
		header.add_child(UiKit.label("OBSERVE %.1fs" % need, 9, UiKit.TEXT_DIM))

	var text := data.codex_field(field) if unlocked else "???"
	var body := UiKit.body(text, 12, UiKit.TEXT if unlocked else UiKit.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	return box


func _make_variant_chip(data: CreatureData, v: CreatureVariant, seen: bool) -> Control:
	var card := UiKit.make_panel(
		Color(0.031, 0.047, 0.067, 0.9) if seen else Color(0.02, 0.024, 0.031, 0.7),
		UiKit.LEGEND if (seen and v.legendary) else (UiKit.ACCENT if seen else UiKit.EDGE))
	card.custom_minimum_size = Vector2(104, 112)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(84, 62)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if data.art_path.is_empty():
		thumb.texture = null
	elif seen:
		thumb.texture = SvgFactory.sprite(
			data.art_path, 62, v.hue_shift, v.saturation, v.value, v.overlay)
	else:
		thumb.texture = SvgFactory.silhouette(data.art_path, 62, Color(0.08, 0.09, 0.13))
	col.add_child(thumb)

	col.add_child(UiKit.label(
		v.display_name.to_upper() if seen else "???", 9,
		UiKit.TEXT_BRIGHT if seen else UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	if seen and not v.note.is_empty():
		card.tooltip_text = v.note
	if v.legendary:
		col.add_child(UiKit.label("LEGENDARY", 8, UiKit.LEGEND, HORIZONTAL_ALIGNMENT_CENTER))
	elif v.rare:
		col.add_child(UiKit.label("RARE", 8, Color(0.72, 0.56, 0.98), HORIZONTAL_ALIGNMENT_CENTER))
	return card


## Jump straight to an entry, used by the discovery overlay's "VIEW" action.
func focus_species(species_id: String) -> void:
	_selected = species_id
	if visible:
		_rebuild_list()
		_show_entry(species_id)
