extends Node
## Times the operations a player waits on: building the art for every creature
## and variant, generating every item icon, opening each panel, and generating
## and meshing a chunk. These are the things that stutter on a phone.

func _ready() -> void:
	Engine.max_fps = 60
	await get_tree().process_frame

	_time("all creature sprites (game size)", func() -> void:
		for data in CreatureDB.all():
			for v in data.variants:
				SvgFactory.sprite(data.art_path, data.size_px,
					v.hue_shift, v.saturation, v.value, v.overlay))

	_time("all Codex art (168px + 62px + 44px)", func() -> void:
		for data in CreatureDB.all():
			SvgFactory.sprite(data.art_path, 168)
			SvgFactory.silhouette(data.art_path, 168)
			SvgFactory.sprite(data.art_path, 44)
			SvgFactory.silhouette(data.art_path, 44)
			for v in data.variants:
				SvgFactory.sprite(data.art_path, 62,
					v.hue_shift, v.saturation, v.value, v.overlay)
				SvgFactory.silhouette(data.art_path, 62))

	_time("all item icons", func() -> void:
		for id in ItemDB.ids():
			IconFactory.icon_for(id, 48)
			IconFactory.icon_for(id, 72))

	_time("cached re-fetch of all the above", func() -> void:
		for data in CreatureDB.all():
			SvgFactory.sprite(data.art_path, 168)
		for id in ItemDB.ids():
			IconFactory.icon_for(id, 48))

	var gen := WorldGen.new(20250101)
	var buf := PackedByteArray()
	buf.resize(GameConfig.CHUNK_TILES * GameConfig.CHUNK_TILES)
	_time("generate 25 chunks", func() -> void:
		for i in 25:
			gen.generate_chunk(4 + i % 5, 20 + i / 5, buf))

	var data := ChunkData.new(Vector2i(4, 20))
	gen.generate_chunk(4, 20, data.tiles)
	_time("analyse 25 chunks (collision + lights)", func() -> void:
		for i in 25:
			data.analysed = false
			data.analyse())

	# End-to-end cost of bringing chunks on screen, which is what the player
	# actually feels as a hitch while walking.
	var world := DeepWorld.new()
	add_child(world)
	world.initialize(20250101)
	var focus := world.spawn_position()
	_time("activate the spawn chunk set (cold)", func() -> void:
		for i in 60:
			world.stream_around(focus))
	var deep := Vector2(focus.x, GameConfig.metres_to_world_y(180.0))
	_time("stream to 180 m (cold, 60 steps)", func() -> void:
		for i in 60:
			world.stream_around(deep))
	_time("stream back to spawn (warm)", func() -> void:
		for i in 60:
			world.stream_around(focus))
	_time("4096 tile reads", func() -> void:
		var t := GameConfig.world_to_tile(focus)
		for i in 4096:
			world.get_tile(t.x + i % 64, t.y + i / 64))
	world.queue_free()

	print("PERF_DONE")
	get_tree().quit(0)


func _time(label: String, fn: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	fn.call()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("%-42s %8.1f ms" % [label, ms])
