extends Control
## Debug overlay. Hidden unless Dbg.enabled, and never required to play.
##
## Toggle with F3, or with five rapid taps in the top-left corner on a phone
## (which is also how a tester enables it on a device with no keyboard).

const CORNER_SIZE: float = 64.0
const TAP_WINDOW: float = 1.6
const TAPS_NEEDED: int = 5

var _panel: PanelContainer
var _readout: Label
var _tools: VBoxContainer
var _taps: int = 0
var _tap_timer: float = 0.0
var _accum: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = UiKit.make_panel(Color(0.004, 0.008, 0.016, 0.86), Color(0.2, 0.9, 0.5, 0.5))
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 10.0
	_panel.offset_top = 70.0
	_panel.offset_right = 318.0
	_panel.visible = false
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	col.add_child(UiKit.label("DEBUG", 11, Color(0.3, 1.0, 0.6)))
	_readout = UiKit.label("", 11, Color(0.68, 0.82, 0.72))
	col.add_child(_readout)
	col.add_child(UiKit.separator(Color(0.2, 0.5, 0.35)))

	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 4)
	col.add_child(_tools)
	_build_tools()

	EventBus.debug_mode_changed.connect(func(on: bool) -> void: _panel.visible = on)


func _build_tools() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_tools.add_child(grid)

	for metres in [0, 60, 140, 220, 300]:
		var b := UiKit.button("%dm" % metres, 30.0)
		b.add_theme_font_size_override("font_size", 11)
		var m := float(metres)
		b.pressed.connect(func() -> void: Dbg.teleport_to_depth(m))
		grid.add_child(b)

	var kit := UiKit.button("GIVE KIT", 30.0)
	kit.add_theme_font_size_override("font_size", 11)
	kit.pressed.connect(Dbg.give_test_kit)
	grid.add_child(kit)

	var row2 := GridContainer.new()
	row2.columns = 3
	row2.add_theme_constant_override("h_separation", 4)
	row2.add_theme_constant_override("v_separation", 4)
	_tools.add_child(row2)

	for sid in CreatureDB.species_ids():
		var b := UiKit.button(sid.substr(0, 5).to_upper(), 30.0)
		b.add_theme_font_size_override("font_size", 10)
		var id := sid
		b.pressed.connect(func() -> void: Dbg.spawn_creature(id))
		row2.add_child(b)

	var row3 := GridContainer.new()
	row3.columns = 3
	row3.add_theme_constant_override("h_separation", 4)
	row3.add_theme_constant_override("v_separation", 4)
	_tools.add_child(row3)

	var unlock := UiKit.button("CODEX ALL", 30.0)
	unlock.add_theme_font_size_override("font_size", 10)
	unlock.pressed.connect(Dbg.unlock_codex)
	row3.add_child(unlock)

	var signal_btn := UiKit.button("SIGNAL", 30.0)
	signal_btn.add_theme_font_size_override("font_size", 10)
	signal_btn.pressed.connect(Dbg.force_rare_event)
	row3.add_child(signal_btn)

	var heal := UiKit.button("HEAL", 30.0)
	heal.add_theme_font_size_override("font_size", 10)
	heal.pressed.connect(Dbg.heal_player)
	row3.add_child(heal)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_F3:
			Dbg.toggle()
			accept_event()
		return
	# Corner tap gesture for touch devices.
	var pos := Vector2(-1, -1)
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		pos = (event as InputEventMouseButton).position
	if pos.x < 0.0:
		return
	if pos.x <= CORNER_SIZE and pos.y <= CORNER_SIZE:
		_taps += 1
		_tap_timer = TAP_WINDOW
		if _taps >= TAPS_NEEDED:
			_taps = 0
			Dbg.toggle()


func _process(delta: float) -> void:
	if _tap_timer > 0.0:
		_tap_timer -= delta
		if _tap_timer <= 0.0:
			_taps = 0
	if not Dbg.enabled:
		return
	_accum += delta
	if _accum < 0.2:
		return
	_accum = 0.0
	_readout.text = _compose()


func _compose() -> String:
	var lines: Array[String] = []
	lines.append("FPS %d   ·   %s" % [
		int(Engine.get_frames_per_second()),
		"%.1f MB" % (float(OS.get_static_memory_usage()) / 1048576.0)])
	lines.append("SEED %d" % Game.world_seed)
	if Game.player != null and is_instance_valid(Game.player):
		var p: Vector2 = Game.player.global_position
		var t := GameConfig.world_to_tile(p)
		var c := GameConfig.tile_to_chunk(t)
		lines.append("POS %.0f, %.0f" % [p.x, p.y])
		lines.append("TILE %d, %d   CHUNK %d, %d" % [t.x, t.y, c.x, c.y])
		lines.append("DEPTH %.1f m   STATE %s" % [
			GameConfig.depth_metres(p), Game.player.state_name()])
		var mc: Node = Game.player.mining_controller
		if mc != null:
			var tt: Vector2i = mc.call("target_tile")
			var blocked: String = mc.call("blocked_reason")
			lines.append("TARGET %d,%d %s %s" % [
				tt.x, tt.y,
				BlockDB.get_block(Game.world.get_tile(tt.x, tt.y)).key if Game.world != null else "-",
				("[" + blocked + "]") if not blocked.is_empty() else ""])
	lines.append("ZONE %s" % str(Dbg.get_counter("zone")))
	lines.append("AMBIENT %s   LIGHTS %s" % [
		str(Dbg.get_counter("ambient")),
		str(Game.world.lights.active_count) if Game.world != null else "-"])
	if Game.world != null:
		lines.append("CHUNKS LIVE %d   MODS %d" % [
			Game.world.live_chunk_count(), Game.world.modification_count()])
		lines.append("REGROW PENDING %d   RECOVERED %d" % [
			Game.world.ecology.pending_regrowth(), Game.world.ecology.recovered_count()])
	lines.append("CREATURES %s   OBSERVING %s" % [
		str(Dbg.get_counter("creatures", 0)), str(Dbg.get_counter("observing", 0))])
	lines.append("SIGNAL dwell %s   cd %s" % [
		str(Dbg.get_counter("signal_dwell", "-")), str(Dbg.get_counter("signal_cooldown", "-"))])
	return "\n".join(lines)
