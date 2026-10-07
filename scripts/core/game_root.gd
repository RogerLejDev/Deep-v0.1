extends Node2D
## The Game scene root: builds the world, the player, the camera, the creature
## systems, the atmosphere and the whole UI stack, then owns the interactions
## between them that do not belong to any one system.

const STORY_SLAB := [
	"THE SLAB IS WORKED STONE. SOMEONE CUT IT.",
	"Four marks, deeper than the rest, and a line drawn downward.",
	"You did not bring it here. Neither did anyone you know of.",
]

var world: DeepWorld = null
var player: Player = null
var camera: CameraRig = null
var spawner: Node2D = null
var observation: Node = null
var ambience: Ambience = null
var vfx: Node2D = null
var base_camp: BaseCamp = null
var recovery_marker: Node2D = null

var hud: Control = null
var touch: Control = null
var inventory_panel: ModalPanel = null
var crafting_panel: ModalPanel = null
var codex_panel: ModalPanel = null
var discovery: Control = null
var pause_menu: Control = null
var debug_overlay: Control = null

var _ui_layer: CanvasLayer = null
var _slab_index: int = 0


func _ready() -> void:
	_build_world()
	_build_player()
	_build_camera()
	_build_atmosphere()
	_build_creatures()
	_build_ui()
	_restore_or_start()
	_connect_signals()


# --- Construction ------------------------------------------------------------

func _build_world() -> void:
	world = DeepWorld.new()
	world.name = "World"
	add_child(world)
	var seed_value: int = Game.world_seed if Game.world_seed != 0 else 20250101
	var mods: Dictionary = {}
	if not Game.pending_load.is_empty():
		mods = DeepWorld.parse_modifications(Game.pending_load.get("world_mods", {}))
	world.initialize(seed_value, mods)
	Game.world = world
	if not Game.pending_load.is_empty():
		world.ecology.from_dict(Game.pending_load.get("ecology", {}))
	# Stream the spawn area before anything is placed in it.
	world.stream_around(world.spawn_position())
	for _i in 30:
		world.stream_around(world.spawn_position())


func _build_player() -> void:
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = world.spawn_position()
	player.configure(world)


func _build_camera() -> void:
	camera = CameraRig.new()
	camera.name = "Camera"
	add_child(camera)
	camera.configure(player)
	camera.make_current()


func _build_atmosphere() -> void:
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.configure(camera)

	vfx = preload("res://scripts/vfx/particle_director.gd").new()
	vfx.name = "VFX"
	add_child(vfx)
	vfx.call("configure", camera)

	base_camp = BaseCamp.new()
	base_camp.name = "BaseCamp"
	add_child(base_camp)
	base_camp.configure(world)


func _build_creatures() -> void:
	spawner = preload("res://scripts/creatures/creature_spawner.gd").new()
	spawner.name = "CreatureSpawner"
	add_child(spawner)
	spawner.call("configure", world)

	observation = preload("res://scripts/codex/observation_tracker.gd").new()
	observation.name = "ObservationTracker"
	add_child(observation)
	observation.call("configure", spawner, camera)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	_ui_layer.name = "UI"
	add_child(_ui_layer)

	hud = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	_ui_layer.add_child(hud)

	touch = preload("res://scripts/ui/touch_controls.gd").new()
	touch.name = "TouchControls"
	_ui_layer.add_child(touch)
	touch.call("configure", player)
	touch.connect("menu_requested", _on_menu_requested)

	inventory_panel = preload("res://scripts/ui/inventory_panel.gd").new()
	inventory_panel.name = "InventoryPanel"
	_ui_layer.add_child(inventory_panel)

	crafting_panel = preload("res://scripts/ui/crafting_panel.gd").new()
	crafting_panel.name = "CraftingPanel"
	_ui_layer.add_child(crafting_panel)

	codex_panel = preload("res://scripts/ui/codex_panel.gd").new()
	codex_panel.name = "CodexPanel"
	_ui_layer.add_child(codex_panel)

	discovery = preload("res://scripts/ui/discovery_overlay.gd").new()
	discovery.name = "DiscoveryOverlay"
	_ui_layer.add_child(discovery)

	pause_menu = preload("res://scripts/ui/pause_menu.gd").new()
	pause_menu.name = "PauseMenu"
	_ui_layer.add_child(pause_menu)
	pause_menu.connect("respawn_requested", _on_respawn)

	debug_overlay = preload("res://scripts/ui/debug_overlay.gd").new()
	debug_overlay.name = "DebugOverlay"
	_ui_layer.add_child(debug_overlay)

	# Panels hide the thumb controls while they are up.
	for panel in [inventory_panel, crafting_panel, codex_panel]:
		panel.closed.connect(func() -> void: touch.call("set_controls_visible", true))


func _restore_or_start() -> void:
	if Game.pending_load.is_empty():
		Game.bump_stat("expeditions")
		_show_opening()
		return

	var payload := Game.pending_load
	Game.pending_load = {}
	var pos := Vector2(
		float((payload.get("player", {}) as Dictionary).get("x", 0.0)),
		float((payload.get("player", {}) as Dictionary).get("y", 0.0))
	)
	# Make sure the saved position is actually loaded and not inside rock a
	# later worldgen change may have put there.
	world.stream_around(pos)
	for _i in 30:
		world.stream_around(pos)
	if world.is_solid_at(pos):
		var open := world.find_open_ground(GameConfig.world_to_tile(pos), 16)
		if open.x >= 0:
			pos = GameConfig.tile_centre(open.x, open.y)
		else:
			pos = world.spawn_position()
	player.global_position = pos
	player.set_health(Game.stored_health(payload))
	camera.configure(player)
	EventBus.active_tool_changed.emit(Game.active_tool)
	EventBus.inventory_changed.emit()
	EventBus.codex_progress_changed.emit(Game.codex.discovered(), Game.codex.catalogued())
	EventBus.player_depth_changed.emit(player.depth_metres())
	EventBus.depth_record_changed.emit(Game.deepest_metres)
	_spawn_recovery_marker()
	EventBus.game_loaded.emit(Game.current_slot)
	EventBus.toast_requested.emit("EXPEDITION RESUMED", "info")


func _show_opening() -> void:
	# The opening is three lines, no tutorial. The world teaches the rest.
	EventBus.toast_requested.emit("ROOTLANDS", "zone")
	await get_tree().create_timer(1.6).timeout
	EventBus.toast_requested.emit("THERE IS AN OPENING IN THE GROUND NEARBY.", "info")
	await get_tree().create_timer(3.0).timeout
	EventBus.toast_requested.emit("HOLD ⛏ TO DIG.  GO DOWN.", "info")


func _connect_signals() -> void:
	base_camp.station_triggered.connect(_on_station)
	EventBus.block_mined.connect(_on_block_mined)
	EventBus.rare_event_started.connect(_on_rare_event)


# --- Interaction -------------------------------------------------------------

func _on_menu_requested(which: String) -> void:
	match which:
		"inventory": _open_inventory()
		"craft": _open_crafting(base_camp.current_station())
		"codex": _open_codex()
		"pause": pause_menu.call("open")


func _open_inventory(chest: bool = false) -> void:
	_close_panels()
	touch.call("set_controls_visible", false)
	inventory_panel.call("bind", Game.chest if chest else Game.inventory, chest)
	inventory_panel.open_panel()


func _open_crafting(station: String) -> void:
	_close_panels()
	touch.call("set_controls_visible", false)
	crafting_panel.call("set_station", station)
	crafting_panel.open_panel()


func _open_codex() -> void:
	_close_panels()
	touch.call("set_controls_visible", false)
	codex_panel.open_panel()


func _close_panels() -> void:
	for p in [inventory_panel, crafting_panel, codex_panel]:
		if p.visible:
			p.visible = false


func _on_station(station: String) -> void:
	match station:
		"workbench":
			_open_crafting("workbench")
		"chest":
			_open_inventory(true)
		"beacon":
			if Game.save_now():
				if player != null:
					player.heal(Player.MAX_HEALTH)
				EventBus.toast_requested.emit("RESTED AT THE BEACON", "save")
		"sign":
			EventBus.toast_requested.emit(STORY_SLAB[_slab_index], "info")
			_slab_index = (_slab_index + 1) % STORY_SLAB.size()
			Game.note_story("read_surface_slab")


func _on_block_mined(_tile: Vector2i, block_id: int, by_player: bool) -> void:
	if not by_player:
		return
	# First ancient fragment is a story beat; the world starts answering back.
	if block_id == BlockDB.ANCIENT_STONE and not Game.progress.get("story_beats", []).has("broke_masonry"):
		Game.note_story("broke_masonry")
		EventBus.toast_requested.emit("THIS WAS BUILT. SOMETHING BUILT THIS.", "legendary")


func _on_rare_event(event_id: String, _position: Vector2) -> void:
	if event_id != "unknown_signal":
		return
	# Freeze the ambience into something wrong for a moment.
	EventBus.toast_requested.emit("SOMETHING IS COMING UP FROM BELOW", "legendary")


# --- Death and recovery ------------------------------------------------------

func _on_respawn() -> void:
	player.respawn_at(base_camp.spawn_point())
	world.stream_around(player.global_position)
	camera.configure(player)
	_spawn_recovery_marker()
	Game.bump_stat("expeditions")
	Game.autosave()


## A visible, collectable cache at the place the player died.
func _spawn_recovery_marker() -> void:
	if recovery_marker != null and is_instance_valid(recovery_marker):
		recovery_marker.queue_free()
		recovery_marker = null
	if Game.recovery_cache.is_empty():
		return
	var marker := preload("res://scripts/world/recovery_cache.gd").new()
	marker.name = "RecoveryCache"
	add_child(marker)
	marker.call("configure", world, Game.recovery_cache)
	recovery_marker = marker


# --- Per-frame ---------------------------------------------------------------

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	world.stream_around(player.global_position)
	world.lights.update(camera.get_screen_centre(), float(Time.get_ticks_msec()) * 0.001)

	if Input.is_action_just_pressed("ui_inventory"):
		_open_inventory()
	elif Input.is_action_just_pressed("ui_craft"):
		_open_crafting(base_camp.current_station())
	elif Input.is_action_just_pressed("ui_codex"):
		_open_codex()
	elif Input.is_action_just_pressed("ui_cancel") and not pause_menu.visible:
		if inventory_panel.visible or crafting_panel.visible or codex_panel.visible:
			_close_panels()
			touch.call("set_controls_visible", true)
		else:
			pause_menu.call("open")


func _notification(what: int) -> void:
	# Android sends this when the app is backgrounded; save immediately,
	# because the process may never get another chance.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if Game.run_active:
			Game.autosave()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
