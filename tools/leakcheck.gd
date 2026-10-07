extends Node
## Measures resident memory across the operations most likely to grow it:
## chunk churn from streaming and carving, the discovery reveal queue, and the
## Codex panel (which rasterises and recolours every species and variant).
##
##   godot --headless --path . res://tools/LeakCheck.tscn

var _root: Node = null


func _ready() -> void:
	# Uncapped headless frame rates are not a realistic workload and make any
	# per-frame allocation look like a leak. Measure at a device-like rate.
	Engine.max_fps = 60
	await get_tree().process_frame
	_mark("boot")

	Game.new_run(20250101, 0)
	Game.pending_load = {}
	_root = (load("res://scenes/game/Game.tscn") as PackedScene).instantiate()
	add_child(_root)
	for _i in 20:
		await get_tree().process_frame
	_mark("game scene up")

	var world: DeepWorld = _root.get("world")
	var player: Player = _root.get("player")

	# Idle.
	await _wait(3.0)
	_mark("3 s idle")

	# Streaming churn: repeated long descents and returns.
	for pass_i in 3:
		for depth in [30, 120, 240, 60]:
			var tx := GameConfig.world_to_tile(player.global_position).x
			var ty := int(GameConfig.metres_to_world_y(float(depth)) / GameConfig.TILE_SIZE)
			for _i in 20:
				world.stream_around(GameConfig.tile_centre(tx, ty))
				await get_tree().process_frame
			player.global_position = GameConfig.tile_centre(tx, ty)
	_mark("12 long descents")

	# Terrain churn: carve and refill a large room repeatedly.
	var base := GameConfig.world_to_tile(player.global_position)
	for pass_i in 4:
		for dy in range(-8, 8):
			for dx in range(-16, 16):
				world.set_tile(base.x + dx, base.y + dy,
					BlockDB.AIR if pass_i % 2 == 0 else BlockDB.STONE, false)
		for _i in 20:
			await get_tree().process_frame
	_mark("4x 1024-tile edits")

	# Creatures.
	var spawner = _root.get("spawner")
	for round_i in 3:
		for sid in CreatureDB.species_ids():
			var tile := world.find_open_ground(base + Vector2i(4, 0), 16)
			if tile.x < 0:
				continue
			spawner.call("spawn", sid, CreatureDB.get_species(sid).default_variant_id(),
				GameConfig.tile_centre(tile.x, tile.y), false)
		await _wait(2.0)
		for c in spawner.call("creatures"):
			if is_instance_valid(c):
				(c as Node).queue_free()
		await _wait(0.5)
	_mark("3x spawn+free all species")

	# The discovery reveal queue, which was the suspect.
	Game.codex.debug_unlock_all()
	await _wait(1.0)
	_mark("codex unlocked (reveals queued)")
	await _wait(30.0)
	_mark("reveal queue drained")

	# The Codex panel: every species and variant rasterised and recoloured.
	for i in 6:
		_root.call("_on_menu_requested", "codex")
		await _wait(1.2)
		_root.call("_close_panels")
		await _wait(0.3)
	_mark("6x open Codex panel")

	for i in 6:
		_root.call("_on_menu_requested", "craft")
		await _wait(0.6)
		_root.call("_close_panels")
		_root.call("_on_menu_requested", "inventory")
		await _wait(0.6)
		_root.call("_close_panels")
	_mark("6x open craft + pack")

	await _wait(3.0)
	_mark("settled")
	print("LEAK_DONE")
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await get_tree().process_frame


func _mark(label: String) -> void:
	print("%-32s  rss %7.1f MB   static %6.1f MB   objects %6d   orphans %4d" % [
		label,
		float(_rss_kb()) / 1024.0,
		float(OS.get_static_memory_usage()) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
	])


## Godot's FileAccess cannot read procfs (those files report size 0), so ask
## the OS for our own resident set instead.
func _rss_kb() -> int:
	var out: Array = []
	var code := OS.execute("ps", ["-o", "rss=", "-p", str(OS.get_process_id())], out, false)
	if code != 0 or out.is_empty():
		return 0
	return int(str(out[0]).strip_edges())
