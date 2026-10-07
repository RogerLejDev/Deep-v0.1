extends Control
## Pause menu: resume, manual save, audio toggle, debug toggle, quit to menu.
## Also doubles as the death screen, because the choices there are the same
## shape (respawn, or give up and go to the menu).

var _scrim: ColorRect
var _card: PanelContainer
var _title: Label
var _subtitle: Label
var _buttons: VBoxContainer
var _stats: Label
var _death_mode: bool = false

signal resumed()
signal respawn_requested()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	_scrim = UiKit.scrim(0.8)
	add_child(_scrim)

	_card = UiKit.make_panel(Color(0.024, 0.031, 0.047, 0.98), UiKit.EDGE)
	_card.anchor_left = 0.5
	_card.anchor_top = 0.5
	_card.anchor_right = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -200.0
	_card.offset_right = 200.0
	_card.offset_top = -176.0
	_card.offset_bottom = 186.0
	add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_card.add_child(col)

	_title = UiKit.label(UiKit._tracked("PAUSED"), 22, UiKit.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_title)
	_subtitle = UiKit.label("", 11, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_subtitle)
	col.add_child(UiKit.separator())

	_stats = UiKit.label("", 11, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_stats)
	col.add_child(UiKit.spacer(4))

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	col.add_child(_buttons)

	EventBus.player_died.connect(show_death)


func open() -> void:
	_death_mode = false
	visible = true
	get_tree().paused = true
	_title.text = UiKit._tracked("PAUSED")
	_subtitle.text = ""
	_refresh_stats()
	_build_buttons()


func show_death() -> void:
	_death_mode = true
	visible = true
	get_tree().paused = true
	_title.text = UiKit._tracked("YOU DID NOT SURFACE")
	var cache: Dictionary = Game.recovery_cache
	if cache.is_empty():
		_subtitle.text = "You were carrying nothing worth losing. Your tools and your Codex are intact."
	else:
		var n := 0
		for e in cache.get("items", []):
			n += int((e as Dictionary).get("n", 0))
		_subtitle.text = (
			"%d items are still lying at %s. Your tools, gear and all Codex progress came back with you — go and collect the rest."
				% [n, UiKit.format_metres(float(cache.get("depth", 0.0)))]
		)
	_refresh_stats()
	_build_buttons()


func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()


func _refresh_stats() -> void:
	_stats.text = "  ·  ".join([
		"DEPTH RECORD %s" % UiKit.format_metres(Game.deepest_metres),
		"CODEX %d/%d" % [Game.codex.discovered(), Game.codex.catalogued()],
		"BLOCKS %d" % int(Game.stats.get("blocks_mined", 0)),
		UiKit.format_playtime(Game.playtime),
	])


func _build_buttons() -> void:
	for c in _buttons.get_children():
		c.queue_free()

	if _death_mode:
		var respawn := UiKit.button("RETURN TO BASE CAMP")
		respawn.pressed.connect(func() -> void:
			visible = false
			get_tree().paused = false
			respawn_requested.emit())
		_buttons.add_child(respawn)
	else:
		var resume := UiKit.button("RESUME")
		resume.pressed.connect(close)
		_buttons.add_child(resume)

		var save := UiKit.button("SAVE NOW")
		save.pressed.connect(func() -> void:
			if Game.save_now():
				save.text = "SAVED"
			else:
				save.text = "SAVE FAILED")
		_buttons.add_child(save)

	var audio := UiKit.button("AUDIO: " + ("OFF" if Audio.muted else "ON"), 40.0)
	audio.pressed.connect(func() -> void:
		Audio.set_muted(not Audio.muted)
		audio.text = "AUDIO: " + ("OFF" if Audio.muted else "ON"))
	_buttons.add_child(audio)

	var debug := UiKit.button("DEBUG TOOLS: " + ("ON" if Dbg.enabled else "OFF"), 40.0)
	debug.pressed.connect(func() -> void:
		Dbg.toggle()
		debug.text = "DEBUG TOOLS: " + ("ON" if Dbg.enabled else "OFF"))
	_buttons.add_child(debug)

	var quit := UiKit.button("SAVE AND LEAVE", 40.0)
	quit.pressed.connect(func() -> void:
		Game.save_now()
		get_tree().paused = false
		Game.end_run()
		Router.to_menu())
	_buttons.add_child(quit)


func _input(event: InputEvent) -> void:
	if not visible or _death_mode:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			close()
			accept_event()
