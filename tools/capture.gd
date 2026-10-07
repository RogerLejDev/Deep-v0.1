extends Node
## Screenshot harness for visual review and for catching shader errors that
## only surface on a real GPU.
##
##   godot --path . --rendering-driver opengl3 res://tools/Capture.tscn
##
## Writes PNGs to user://shots/. Not part of the game; it exists so the look of
## each depth band can be checked without a human at a keyboard.

const OUT_DIR: String = "user://shots"

var _root: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await get_tree().process_frame

	# --- title screen ---
	var menu := (load("res://scenes/ui/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _settle(30)
	await _shot("00_title")
	menu.queue_free()
	await _settle(4)

	# --- the game at several depths ---
	Game.new_run(20250101, 0)
	Game.pending_load = {}
	_root = (load("res://scenes/game/Game.tscn") as PackedScene).instantiate()
	add_child(_root)
	await _settle(40)
	await _shot("01_surface")

	# Give the player some materials so the panels have content to show.
	for id in ["copper_ore", "iron_ore", "crystal_shard", "deep_crystal_shard",
			"root_fibre", "glowcap", "plank", "stone_chunk", "torch", "salve"]:
		Game.inventory.add(id, 24)
	Game.inventory.add("lantern", 1)

	await _descend(26.0, "02_topsoil")
	await _descend(78.0, "03_caverns")
	await _descend(165.0, "04_deep")
	await _descend(275.0, "05_threshold")

	# --- creatures, lined up in front of the player ---
	await _creature_parade()
	_revive()

	# --- panels ---
	Game.codex.debug_unlock_all()
	await _panel("codex", "07_codex")
	await _panel("craft", "08_crafting")
	await _panel("inventory", "09_inventory")

	print("CAPTURE_DONE")
	get_tree().quit(0)


## The parade deliberately stands next to things that bite; keep the harness
## alive so the panel shots are not taken behind a death screen.
func _revive() -> void:
	get_tree().paused = false
	var pause = _root.get("pause_menu")
	if pause != null:
		pause.visible = false
	var player: Player = _root.get("player")
	if player != null:
		if player.is_dead():
			player.respawn_at(player.global_position)
		player.set_health(100.0)
	var spawner = _root.get("spawner")
	if spawner != null:
		for c in spawner.call("creatures"):
			if is_instance_valid(c):
				(c as Node).queue_free()


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	print("SHOT %s -> %s (%dx%d) err=%d" % [name, path, img.get_width(), img.get_height(), err])


func _descend(metres: float, name: String) -> void:
	var world: DeepWorld = _root.get("world")
	var player: Player = _root.get("player")
	if world == null or player == null:
		return
	var tx := GameConfig.world_to_tile(player.global_position).x
	var ty := int(GameConfig.metres_to_world_y(metres) / GameConfig.TILE_SIZE)
	# Load the destination first, then find somewhere open to stand.
	for _i in 40:
		world.stream_around(GameConfig.tile_centre(tx, ty))
		await get_tree().process_frame
	var open := world.find_open_ground(Vector2i(tx, ty), 26)
	if open.x < 0:
		for dy in range(-3, 3):
			for dx in range(-4, 5):
				world.set_tile(tx + dx, ty + dy, BlockDB.AIR)
		open = Vector2i(tx, ty)
	player.global_position = GameConfig.tile_centre(open.x, open.y)
	player.velocity = Vector2.ZERO
	var camera: CameraRig = _root.get("camera")
	if camera != null:
		camera.configure(player)
	await _settle(50)
	await _shot(name)


func _creature_parade() -> void:
	var world: DeepWorld = _root.get("world")
	var player: Player = _root.get("player")
	var spawner = _root.get("spawner")
	if world == null or spawner == null:
		return
	# Clear a room so every species is visible at once.
	var base := GameConfig.world_to_tile(player.global_position)
	for dy in range(-7, 5):
		for dx in range(-16, 17):
			world.set_tile(base.x + dx, base.y + dy, BlockDB.AIR)
	for dx in range(-16, 17):
		world.set_tile(base.x + dx, base.y + 4, BlockDB.DARK_STONE)
		world.set_tile(base.x + dx, base.y + 5, BlockDB.DARK_STONE)
	# A crystal seam for light and for the Kryx's spawn condition.
	for dx in [-14, -13, 12, 13]:
		world.set_tile(base.x + dx, base.y + 3, BlockDB.CRYSTAL)
	await _settle(10)

	var ids := CreatureDB.species_ids()
	var slot := 0
	for sid in ids:
		var data := CreatureDB.get_species(sid)
		var ox := -11 + slot * 4
		spawner.call("spawn", sid, data.default_variant_id(),
			GameConfig.tile_centre(base.x + ox, base.y + 2), false)
		slot += 1
	await _settle(40)
	await _shot("06_creatures")
	# Freeze the scene so nobody wanders out of frame mid-capture.
	for item in spawner.call("creatures"):
		var cc := item as Creature
		if cc != null:
			cc.set_physics_process(false)
	await _settle(2)


func _panel(which: String, name: String) -> void:
	if _root == null:
		return
	_root.call("_on_menu_requested", which)
	await _settle(30)
	await _shot(name)
	# Close whatever is open.
	_root.call("_close_panels")
	await _settle(6)
