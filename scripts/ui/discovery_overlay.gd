extends Control
## NEW DISCOVERY.
##
## The single most important piece of feedback in the game: the moment a
## creature enters the Codex. It gets a time-dilated, staged reveal — rings,
## a rising plate, the silhouette resolving into the real art, the name
## typing in — and a separate, much louder treatment for a legendary.
##
## Deliberately non-blocking: the player keeps control, the game keeps running
## at reduced speed, and the card clears itself.

const ART_HEIGHT: int = 150
const SLOWDOWN: float = 0.35
const SLOWDOWN_SECONDS: float = 0.55

var _card: PanelContainer
var _kicker: Label
var _name_label: Label
var _rarity: Label
var _art: TextureRect
var _ring: Control
var _sub: Label

var _ring_t: float = 0.0
var _ring_active: bool = false
var _ring_colour: Color = UiKit.ACCENT
var _queue: Array[Dictionary] = []
var _busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	EventBus.codex_entry_discovered.connect(_on_discovered)


func _build() -> void:
	_ring = Control.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_rings)
	add_child(_ring)

	_card = UiKit.make_panel(Color(0.016, 0.027, 0.043, 0.95), UiKit.ACCENT)
	_card.anchor_left = 0.5
	_card.anchor_top = 0.5
	_card.anchor_right = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -196.0
	_card.offset_right = 196.0
	_card.offset_top = -152.0
	_card.offset_bottom = 152.0
	_card.modulate.a = 0.0
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(col)

	_kicker = UiKit.label("", 12, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_kicker)

	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(0, ART_HEIGHT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_art)

	_name_label = UiKit.label("", 30, UiKit.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_name_label)

	_rarity = UiKit.label("", 12, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_rarity)

	_sub = UiKit.label("ADDED TO CODEX", 10, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_sub)


# --- Queue -------------------------------------------------------------------

func _on_discovered(species_id: String, variant_id: String) -> void:
	_queue.append({"species": species_id, "variant": variant_id})
	if not _busy:
		_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var entry: Dictionary = _queue.pop_front()
	await _present(str(entry["species"]), str(entry["variant"]))
	_play_next()


func _present(species_id: String, variant_id: String) -> void:
	var data := CreatureDB.get_species(species_id)
	var variant := data.variant_by_id(variant_id)
	var legendary := variant.legendary or data.rarity == CreatureData.Rarity.LEGENDARY
	var colour := UiKit.rarity_colour(data.rarity)
	_ring_colour = colour

	_kicker.text = UiKit._tracked("A NEW FORM OF LIFE" if legendary else "NEW DISCOVERY")
	_kicker.add_theme_color_override("font_color", colour)
	_rarity.text = "%s  ·  %s" % [data.rarity_name(), UiKit.format_metres(
		Game.codex.first_depth(species_id))]
	_rarity.add_theme_color_override("font_color", colour)
	_sub.text = "CODEX %d / %d" % [Game.codex.discovered(), Game.codex.catalogued()]
	_name_label.text = ""
	_name_label.add_theme_color_override("font_color", colour if legendary else UiKit.TEXT_BRIGHT)

	var style := _card.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.border_color = colour
		style.set_border_width_all(2 if legendary else 1)

	# Start as the silhouette the player has been staring at, then resolve.
	if not data.art_path.is_empty():
		_art.texture = SvgFactory.silhouette(data.art_path, ART_HEIGHT, Color(0.1, 0.12, 0.17))

	_card.visible = true
	_card.scale = Vector2(0.9, 0.9)
	_card.pivot_offset = _card.size * 0.5
	_ring_t = 0.0
	_ring_active = true

	# Time dilation: brief, so it punctuates without interrupting.
	Engine.time_scale = SLOWDOWN
	var tree := get_tree()

	EventBus.screen_shake_requested.emit(6.0 if legendary else 2.4, 0.35)
	_spawn_particles(colour, legendary)
	Audio.play("discovery", 0.8 if legendary else 1.0, 0.0 if legendary else -4.0)

	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_card, "scale", Vector2.ONE, 0.34)
	await tree.create_timer(SLOWDOWN_SECONDS * SLOWDOWN, true, false, true).timeout
	Engine.time_scale = 1.0

	# Resolve the silhouette into the real creature.
	if not data.art_path.is_empty():
		var reveal := create_tween()
		reveal.tween_method(func(t: float) -> void:
			if t > 0.5 and _art.texture != null:
				_art.texture = SvgFactory.sprite(
					data.art_path, ART_HEIGHT,
					variant.hue_shift, variant.saturation, variant.value, variant.overlay)
			_art.modulate = Color(1.0 + (1.0 - t) * 1.6, 1.0 + (1.0 - t) * 1.6, 1.0 + (1.0 - t) * 1.6, 1.0)
			, 0.0, 1.0, 0.5)

	# Type the name in. Cheap, and it makes the reveal feel authored.
	var full := variant.display_name.to_upper() if variant.legendary else data.display_name.to_upper()
	for i in full.length():
		_name_label.text = full.substr(0, i + 1)
		if i % 2 == 0:
			Audio.play("ui_click", 1.5, -26.0)
		await tree.create_timer(0.035, true, false, true).timeout

	var hold: float = 2.6 if legendary else 1.7
	await tree.create_timer(hold, true, false, true).timeout

	var out := create_tween()
	out.tween_property(_card, "modulate:a", 0.0, 0.34)
	await out.finished
	_card.visible = false
	_ring_active = false
	_ring.queue_redraw()


func _spawn_particles(colour: Color, legendary: bool) -> void:
	var vfx := get_tree().get_first_node_in_group("vfx")
	if vfx == null or not vfx.has_method("spawn_discovery"):
		return
	if Game.player == null or not is_instance_valid(Game.player):
		return
	vfx.call("spawn_discovery", Game.player.global_position + Vector2(0, -16), colour)
	if legendary:
		vfx.call("spawn_discovery", Game.player.global_position + Vector2(0, -40), UiKit.LEGEND)


# --- Rings -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ring_active:
		return
	_ring_t += delta
	_ring.queue_redraw()
	if _ring_t > 2.2:
		_ring_active = false


func _draw_rings() -> void:
	if not _ring_active:
		return
	var centre := size * 0.5
	for i in 3:
		var phase: float = _ring_t - float(i) * 0.16
		if phase <= 0.0:
			continue
		var t: float = clampf(phase / 1.1, 0.0, 1.0)
		var radius: float = lerpf(40.0, 420.0, ease(t, 0.35))
		var alpha: float = (1.0 - t) * 0.45
		if alpha <= 0.0:
			continue
		_ring.draw_arc(centre, radius, 0.0, TAU, 64,
			Color(_ring_colour.r, _ring_colour.g, _ring_colour.b, alpha),
			lerpf(4.0, 1.0, t))
