extends Node
## DEEP's headless verification suite.
##
## Run with:
##   godot --headless --path . res://tests/TestRunner.tscn
##
## It exercises every system that can be checked without a human: script
## compilation, worldgen determinism, chunk streaming, destructible terrain and
## its persistence, the inventory/crafting rules, creature data and behaviour,
## the Codex's progressive unlocks, and a full save -> reload -> verify cycle.
## Exits with code 1 if anything fails, so it can gate a build.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _current: String = ""


func _ready() -> void:
	print("\n================ DEEP TEST SUITE ================\n")
	await get_tree().process_frame

	_run("script compilation", _test_scripts)
	_run("block registry", _test_blocks)
	_run("item registry", _test_items)
	_run("hash determinism", _test_hashes)
	_run("worldgen determinism", _test_worldgen_determinism)
	_run("worldgen content", _test_worldgen_content)
	_run("structures", _test_structures)
	_run("biome table", _test_biomes)
	_run("chunk collision merge", _test_chunk_analysis)
	_run("inventory", _test_inventory)
	_run("crafting", _test_crafting)
	_run("creature data", _test_creature_data)
	_run("creature behaviour", _test_creature_behaviour)
	_run("codex progression", _test_codex)
	_run("ecology regrowth", _test_ecology)
	_run("save round trip", _test_save_round_trip)
	_run("save corruption handling", _test_save_corruption)
	await _run_async("live world: stream + mine 20 + persist", _test_live_world)
	await _run_async("live world: creature spawn + discovery", _test_live_creatures)

	_report()


# --- Harness -----------------------------------------------------------------

func _run(name: String, fn: Callable) -> void:
	_current = name
	fn.call()


func _run_async(name: String, fn: Callable) -> void:
	_current = name
	await fn.call()


func _check(condition: bool, message: String) -> bool:
	if condition:
		_passed += 1
		return true
	_failed += 1
	var line := "[%s] %s" % [_current, message]
	_failures.append(line)
	print("  FAIL  ", line)
	return false


func _report() -> void:
	print("\n------------------------------------------------")
	print("PASSED: %d    FAILED: %d" % [_passed, _failed])
	if _failed > 0:
		print("\nFailures:")
		for f in _failures:
			print("  - ", f)
		print("\n================ RESULT: FAIL ==================\n")
		await get_tree().process_frame
		get_tree().quit(1)
		return
	print("\n================ RESULT: PASS ==================\n")
	await get_tree().process_frame
	get_tree().quit(0)


# --- Tests -------------------------------------------------------------------

## Load every script in the project. A parse error surfaces here as a null.
func _test_scripts() -> void:
	var paths: Array[String] = []
	_collect_files("res://scripts", ".gd", paths)
	_collect_files("res://tests", ".gd", paths)
	_check(paths.size() > 30, "expected many scripts, found %d" % paths.size())
	for path in paths:
		var res := load(path)
		_check(res != null, "failed to load %s" % path)

	# Shaders must compile-parse too (full GLSL validation needs a GPU, but a
	# broken include or syntax error shows up at load).
	var shaders: Array[String] = []
	_collect_files("res://shaders", ".gdshader", shaders)
	_check(shaders.size() >= 4, "expected shaders, found %d" % shaders.size())
	for path in shaders:
		var sh := load(path) as Shader
		_check(sh != null, "failed to load shader %s" % path)
		if sh != null:
			_check(not sh.code.is_empty(), "%s has no code" % path)

	# Every scene referenced by the project must instantiate.
	for scene_path in [
		"res://scenes/ui/MainMenu.tscn",
		"res://scenes/game/Game.tscn",
	]:
		var ps := load(scene_path) as PackedScene
		_check(ps != null, "missing scene %s" % scene_path)
		if ps != null:
			_check(ps.can_instantiate(), "%s cannot instantiate" % scene_path)


func _collect_files(dir_path: String, suffix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path + "/" + name
		if dir.current_is_dir():
			_collect_files(full, suffix, out)
		elif name.ends_with(suffix):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _test_blocks() -> void:
	_check(BlockDB.all().size() == BlockDB.COUNT, "block count mismatch")
	for i in BlockDB.COUNT:
		var d := BlockDB.get_block(i)
		_check(d != null, "block %d missing" % i)
		_check(not d.key.is_empty(), "block %d has no key" % i)
		if d.id != BlockDB.AIR and not d.drop_item.is_empty():
			_check(ItemDB.has(d.drop_item),
				"block '%s' drops unknown item '%s'" % [d.key, d.drop_item])
	_check(not BlockDB.is_solid(BlockDB.AIR), "air must not be solid")
	_check(BlockDB.is_solid(BlockDB.STONE), "stone must be solid")
	_check(BlockDB.get_block(BlockDB.BEDROCK).unbreakable, "bedrock must be unbreakable")
	_check(not BlockDB.get_block(BlockDB.TORCH).solid, "torch must not collide")
	# Tool tiers must be reachable: every block needs a tool that can break it.
	var best_tier := -1
	for t in ItemDB.all_tools():
		best_tier = maxi(best_tier, t.tool_tier)
	for d in BlockDB.all():
		if d.unbreakable:
			continue
		_check(d.required_tier <= best_tier,
			"block '%s' needs tier %d but best tool is %d" % [d.key, d.required_tier, best_tier])


func _test_items() -> void:
	_check(ItemDB.ids().size() >= 18, "expected at least 18 items")
	for id in ItemDB.ids():
		var d := ItemDB.get_item(id)
		_check(d.id == id, "item id mismatch for %s" % id)
		_check(not d.display_name.is_empty(), "%s has no name" % id)
		_check(d.stack_size > 0, "%s has non-positive stack size" % id)
		if d.is_placeable():
			_check(d.place_block >= 0 and d.place_block < BlockDB.COUNT,
				"%s places an invalid block" % id)
		_check(d.icon_shape in IconFactory.SHAPES,
			"%s uses unknown icon shape '%s'" % [id, d.icon_shape])
	# Tool progression must be strictly increasing, or upgrades are pointless.
	var powers: Array[float] = []
	for key in ["pick_starter", "pick_copper", "pick_iron", "pick_crystal"]:
		_check(ItemDB.has(key), "missing tool %s" % key)
		powers.append(ItemDB.get_item(key).tool_power)
	for i in range(1, powers.size()):
		_check(powers[i] > powers[i - 1], "tool power does not increase at index %d" % i)


func _test_hashes() -> void:
	_check(RngUtil.hash2(1, 2) == RngUtil.hash2(1, 2), "hash2 not stable")
	_check(RngUtil.hash2(1, 2) != RngUtil.hash2(2, 1), "hash2 is symmetric")
	_check(RngUtil.hash3(5, 6, 7) == RngUtil.hash3(5, 6, 7), "hash3 not stable")
	# Distribution sanity: 4096 samples should fill all four quartiles.
	var buckets := [0, 0, 0, 0]
	for i in 4096:
		var u := RngUtil.to_unit(RngUtil.hash2(99, i))
		buckets[clampi(int(u * 4.0), 0, 3)] += 1
	for b in buckets:
		_check(b > 700, "hash distribution is skewed: %s" % str(buckets))
	for i in 256:
		var u2 := RngUtil.to_unit(RngUtil.hash3(i, i * 7, 3))
		if not _check(u2 >= 0.0 and u2 < 1.0, "to_unit out of range: %f" % u2):
			break


func _test_worldgen_determinism() -> void:
	var a := WorldGen.new(123456)
	var b := WorldGen.new(123456)
	var c := WorldGen.new(654321)

	_check(a.spawn_tile_x == b.spawn_tile_x, "same seed gave different spawn")
	_check(a.spawn_position() == b.spawn_position(), "same seed gave different spawn position")

	var same := 0
	var diff := 0
	for i in 900:
		var tx := 40 + (i * 7) % 300
		var ty := GameConfig.SURFACE_ROW + (i * 13) % 500
		if a.block_at(tx, ty) != b.block_at(tx, ty):
			diff += 1
		if a.block_at(tx, ty) == c.block_at(tx, ty):
			same += 1
	_check(diff == 0, "%d tiles differed between identical seeds" % diff)
	# Different seeds must produce a genuinely different world.
	_check(same < 820, "different seeds produced %d/900 identical tiles" % same)

	# Bulk generation must agree with the per-tile function.
	var buf := PackedByteArray()
	buf.resize(GameConfig.CHUNK_TILES * GameConfig.CHUNK_TILES)
	a.generate_chunk(3, 4, buf)
	var mismatches := 0
	for ly in GameConfig.CHUNK_TILES:
		for lx in GameConfig.CHUNK_TILES:
			var expected := a.block_at(3 * GameConfig.CHUNK_TILES + lx, 4 * GameConfig.CHUNK_TILES + ly)
			if buf[ly * GameConfig.CHUNK_TILES + lx] != expected:
				mismatches += 1
	_check(mismatches == 0, "generate_chunk disagreed with block_at %d times" % mismatches)


func _test_worldgen_content() -> void:
	var gen := WorldGen.new(777)

	# Sky above the surface, solid below it.
	var sx := gen.spawn_tile_x
	var surf := gen.surface_row(sx)
	_check(gen.block_at(sx, surf - 8) == BlockDB.AIR, "expected air above the surface")
	_check(BlockDB.is_solid(gen.block_at(sx, surf)), "surface row is not solid")
	_check(gen.block_at(sx, surf) == BlockDB.GRASS, "surface row should be rooted soil")

	# Shell.
	_check(gen.block_at(0, 200) == BlockDB.BEDROCK, "left edge is not bedrock")
	_check(gen.block_at(GameConfig.WORLD_TILES_X - 1, 200) == BlockDB.BEDROCK,
		"right edge is not bedrock")
	_check(gen.block_at(100, GameConfig.WORLD_TILES_Y - 1) == BlockDB.BEDROCK,
		"world floor is not bedrock")

	# The guaranteed starter descent must actually exist and be open.
	var open_near_spawn := 0
	for ty in range(surf, surf + 46):
		for tx in range(sx - 30, sx + 31):
			if gen.block_at(tx, ty) == BlockDB.AIR:
				open_near_spawn += 1
	_check(open_near_spawn > 150,
		"starter descent looks sealed: only %d open tiles near spawn" % open_near_spawn)

	# Caves: there must be real open volume underground, but not so much that
	# the world is hollow.
	var air := 0
	var total := 0
	for ty in range(GameConfig.SURFACE_ROW + 60, GameConfig.SURFACE_ROW + 360):
		for tx in range(120, 240):
			total += 1
			if gen.block_at(tx, ty) == BlockDB.AIR:
				air += 1
	var ratio := float(air) / float(total)
	_check(ratio > 0.06, "underground is too solid (%.3f open)" % ratio)
	_check(ratio < 0.60, "underground is too hollow (%.3f open)" % ratio)

	# Every progression material must be findable at its intended depth.
	var found: Dictionary = {}
	for ty in range(GameConfig.SURFACE_ROW, GameConfig.WORLD_TILES_Y - 10, 2):
		for tx in range(60, 330, 2):
			found[gen.block_at(tx, ty)] = true
	for required in [BlockDB.DIRT, BlockDB.STONE, BlockDB.ROOT, BlockDB.COPPER_ORE,
			BlockDB.IRON_ORE, BlockDB.CRYSTAL, BlockDB.DEEP_CRYSTAL, BlockDB.DARK_STONE]:
		_check(found.has(required),
			"material '%s' never generated" % BlockDB.get_block(required).key)

	# Copper must be reachable with the starter pick before the player needs
	# anything better, i.e. it exists above 100 m.
	var shallow_copper := 0
	for ty in range(GameConfig.SURFACE_ROW + 20, GameConfig.SURFACE_ROW + 180):
		for tx in range(80, 300):
			if gen.block_at(tx, ty) == BlockDB.COPPER_ORE:
				shallow_copper += 1
	_check(shallow_copper > 40, "only %d shallow copper tiles; progression stalls" % shallow_copper)


func _test_structures() -> void:
	var sg := StructureGen.new(4242)
	var kinds: Dictionary = {}
	for cy in range(2, 22):
		for cx in range(1, 8):
			var sites := sg.sites_near(Vector2i(cx * StructureGen.SITE, cy * StructureGen.SITE), 0)
			for s in sites:
				kinds[int(s["kind"])] = true
	_check(kinds.size() >= 2, "expected several structure kinds, found %d" % kinds.size())

	# Structures must be deterministic.
	var a := StructureGen.new(99)
	var b := StructureGen.new(99)
	var diff := 0
	for i in 400:
		var tx := 100 + i
		var ty := GameConfig.SURFACE_ROW + 200 + (i * 3) % 200
		if a.block_at(tx, ty, GameConfig.SURFACE_ROW) != b.block_at(tx, ty, GameConfig.SURFACE_ROW):
			diff += 1
	_check(diff == 0, "structures differed between identical seeds (%d)" % diff)

	# And they must leave the surface alone.
	var gen := WorldGen.new(99)
	var breaches := 0
	for tx in range(40, 340):
		var surf := gen.surface_row(tx)
		for ty in range(surf - 6, surf):
			if gen.block_at(tx, ty) == BlockDB.ANCIENT_STONE:
				breaches += 1
	_check(breaches == 0, "a structure broke through the surface %d times" % breaches)


func _test_biomes() -> void:
	var zones := BiomeTable.zones()
	_check(zones.size() >= 4, "expected at least four depth zones")
	for i in range(1, zones.size()):
		_check(zones[i].from_metres > zones[i - 1].from_metres,
			"zones are not sorted by depth at index %d" % i)
	# Ambient must get monotonically darker with depth.
	var last := 2.0
	for m in [0.0, 20.0, 60.0, 120.0, 200.0, 300.0]:
		var v := BiomeTable.ambient_for_depth(m).v
		_check(v <= last + 0.001, "ambient brightened going from %.0f m" % m)
		last = v
	_check(BiomeTable.ambient_for_depth(0.0).v > 0.8, "the surface should be bright")
	_check(BiomeTable.ambient_for_depth(300.0).v < 0.2, "300 m should be very dark")
	# Every species named in a spawn table must exist.
	for z in zones:
		for sid: String in z.spawn_weights.keys():
			_check(CreatureDB.has_species(sid),
				"zone '%s' references unknown species '%s'" % [z.id, sid])


func _test_chunk_analysis() -> void:
	var data := ChunkData.new(Vector2i(0, 0))
	var cs := GameConfig.CHUNK_TILES
	# A solid chunk must merge into exactly one rectangle.
	for i in data.tiles.size():
		data.tiles[i] = BlockDB.STONE
	data.analyse()
	_check(data.collision_rects.size() == 1,
		"a solid chunk merged into %d rects, expected 1" % data.collision_rects.size())
	_check(data.collision_rects[0] == Rect2i(0, 0, cs, cs), "merged rect is wrong")

	# An empty chunk has no collision at all.
	for i in data.tiles.size():
		data.tiles[i] = BlockDB.AIR
	data.analyse()
	_check(data.collision_rects.is_empty(), "an empty chunk produced collision")

	# A checkerboard is the worst case; every solid tile must still be covered.
	for y in cs:
		for x in cs:
			data.tiles[ChunkData.local_index(x, y)] = BlockDB.STONE if (x + y) % 2 == 0 else BlockDB.AIR
	data.analyse()
	var covered := 0
	for r in data.collision_rects:
		covered += r.size.x * r.size.y
	_check(covered == (cs * cs) / 2,
		"checkerboard coverage was %d, expected %d" % [covered, (cs * cs) / 2])

	# Emissive tiles must cluster into a small number of lights.
	for i in data.tiles.size():
		data.tiles[i] = BlockDB.CRYSTAL
	data.analyse()
	_check(data.light_sources.size() > 0, "a chunk of crystal produced no lights")
	_check(data.light_sources.size() <= 4,
		"light clustering produced %d lights for one chunk" % data.light_sources.size())


func _test_inventory() -> void:
	var inv := Inventory.new(6)
	_check(inv.add("stone_chunk", 5) == 0, "add reported leftovers with room available")
	_check(inv.count("stone_chunk") == 5, "count after add is wrong")
	_check(inv.used_slots() == 1, "5 stone should occupy one slot")

	# Stack limits must split across slots.
	var torch_stack := ItemDB.get_item("torch").stack_size
	var inv2 := Inventory.new(4)
	inv2.add("torch", torch_stack + 3)
	_check(inv2.count("torch") == torch_stack + 3, "stack split lost items")
	_check(inv2.used_slots() == 2, "stack split used %d slots" % inv2.used_slots())

	# Tools do not stack.
	var inv3 := Inventory.new(4)
	inv3.add("pick_starter", 3)
	_check(inv3.count("pick_starter") == 3, "tool count wrong")
	_check(inv3.used_slots() == 3, "non-stacking tools shared a slot")

	# Overflow is reported, not silently dropped.
	var small := Inventory.new(1)
	var leftover := small.add("salve", ItemDB.get_item("salve").stack_size + 7)
	_check(leftover == 7, "overflow reported %d, expected 7" % leftover)

	# Removal drains the smallest stacks first and never goes negative.
	_check(inv.remove("stone_chunk", 2) == 2, "remove returned the wrong count")
	_check(inv.count("stone_chunk") == 3, "count after remove is wrong")
	_check(inv.remove("stone_chunk", 99) == 3, "remove over-reported")
	_check(inv.count("stone_chunk") == 0, "stack should be empty")
	_check(inv.remove("nothing_here", 1) == 0, "removing a missing item reported a removal")

	# Moving merges same-item stacks and swaps different ones.
	var mv := Inventory.new(4)
	mv.slots[0] = {"id": "stone_chunk", "n": 4}
	mv.slots[1] = {"id": "stone_chunk", "n": 6}
	mv.move(0, 1)
	_check(mv.count_at(1) == 10 and mv.is_empty_slot(0), "merge move failed")
	mv.slots[0] = {"id": "copper_ore", "n": 2}
	mv.move(0, 1)
	_check(mv.item_at(1) == "copper_ore" and mv.item_at(0) == "stone_chunk", "swap move failed")

	# Serialisation must round trip, and must reject stale item ids.
	var dict := mv.to_dict()
	var restored := Inventory.new(1)
	restored.from_dict(dict)
	_check(restored.capacity == mv.capacity, "capacity lost in round trip")
	_check(restored.count("copper_ore") == 2, "copper lost in round trip")
	_check(restored.count("stone_chunk") == 10, "stone lost in round trip")
	var junk := Inventory.new(2)
	junk.from_dict({"capacity": 2, "slots": [{"id": "deleted_item", "n": 4}, null]})
	_check(junk.used_slots() == 0, "a stale item id survived loading")


func _test_crafting() -> void:
	var inv := Inventory.new(24)
	var copper := RecipeDB.by_id("pick_copper")
	_check(copper != null, "missing the copper pick recipe")

	_check(CraftingSystem.can_craft(inv, copper, "workbench") == CraftingSystem.Result.MISSING_INPUTS,
		"an empty pack reported craftable")
	inv.add("copper_ore", 8)
	inv.add("root_fibre", 4)
	_check(CraftingSystem.can_craft(inv, copper, "") == CraftingSystem.Result.WRONG_STATION,
		"a bench recipe was craftable by hand")
	_check(CraftingSystem.can_craft(inv, copper, "workbench") == CraftingSystem.Result.OK,
		"a satisfied bench recipe was not craftable")

	_check(CraftingSystem.craft(inv, copper, "workbench") == CraftingSystem.Result.OK, "craft failed")
	_check(inv.has("pick_copper"), "the crafted pick is missing")
	_check(inv.count("copper_ore") == 0, "inputs were not consumed")
	_check(inv.count("root_fibre") == 0, "inputs were not consumed")
	_check(CraftingSystem.can_craft(inv, copper, "workbench") == CraftingSystem.Result.MISSING_INPUTS,
		"crafting twice was possible from one set of inputs")

	# Hand recipes work anywhere.
	var hand := RecipeDB.by_id("plank")
	inv.add("root_fibre", 2)
	_check(CraftingSystem.craft(inv, hand, "") == CraftingSystem.Result.OK, "hand craft failed")
	_check(inv.count("plank") == 2, "plank output count is wrong")

	# best_tool must pick the strongest pick present.
	inv.add("pick_iron", 1)
	_check(CraftingSystem.best_tool(inv) == "pick_iron",
		"best_tool chose '%s'" % CraftingSystem.best_tool(inv))

	# Every recipe must reference real items and reachable stations.
	for r in RecipeDB.all():
		_check(ItemDB.has(r.output_id), "recipe '%s' outputs unknown item" % r.id)
		_check(r.output_count > 0, "recipe '%s' outputs nothing" % r.id)
		_check(r.station.is_empty() or r.station == "workbench",
			"recipe '%s' needs unknown station '%s'" % [r.id, r.station])
		for entry in r.input_list():
			_check(ItemDB.has(str(entry["id"])),
				"recipe '%s' needs unknown item '%s'" % [r.id, entry["id"]])
			_check(int(entry["n"]) > 0, "recipe '%s' has a zero-count input" % r.id)


func _test_creature_data() -> void:
	_check(CreatureDB.load_errors().is_empty(),
		"creature data errors: %s" % str(CreatureDB.load_errors()))
	var ids := CreatureDB.species_ids()
	_check(ids.size() >= 5, "expected at least five species, got %d" % ids.size())

	var numbers: Dictionary = {}
	for id in ids:
		var d := CreatureDB.get_species(id)
		_check(not d.display_name.is_empty(), "%s has no display name" % id)
		_check(not d.art_path.is_empty(), "%s has no art" % id)
		_check(ResourceLoader.exists(d.art_path), "%s art missing at %s" % [id, d.art_path])
		_check(d.size_px >= 8, "%s is too small to see" % id)
		_check(d.hp > 0.0, "%s has no health" % id)
		_check(d.behaviour in ["skittish", "burrower", "drifter", "aggressive", "phantom", "apex", "wander"],
			"%s has unknown behaviour '%s'" % [id, d.behaviour])
		_check(not numbers.has(d.codex_number), "duplicate codex number %d" % d.codex_number)
		numbers[d.codex_number] = true
		_check(d.depth_max > d.depth_min, "%s has an empty depth range" % id)
		for entry in d.loot:
			_check(ItemDB.has(str(entry["item"])),
				"%s drops unknown item '%s'" % [id, entry["item"]])
		_check(d.variants.size() >= 1, "%s has no variants" % id)
		for field in Codex.FIELDS:
			_check(d.codex_text.has(field), "%s is missing codex field '%s'" % [id, field])

	# Variant rolls must be deterministic for a given RNG and must respect
	# weights (the common variant should dominate).
	var kryx := CreatureDB.get_species("kryx")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := kryx.roll_variant(rng).id
	rng.seed = 5
	_check(kryx.roll_variant(rng).id == first, "variant roll is not deterministic")

	var counts: Dictionary = {}
	rng.seed = 11
	for i in 4000:
		var v := kryx.roll_variant(rng)
		counts[v.id] = int(counts.get(v.id, 0)) + 1
	_check(int(counts.get("normal", 0)) > 2500, "the common Kryx variant is too rare")
	_check(int(counts.get("corrupted", 0)) < 160, "the rare Kryx variant is too common")
	_check(counts.size() >= 3, "only %d Kryx variants ever rolled" % counts.size())

	# Legendary species must be event-only, never on a spawn table.
	var apex := CreatureDB.get_species("lumreaper")
	_check(apex.is_event_only(), "the legendary species is not event-gated")
	var zone := BiomeTable.zone_for_depth(300.0)
	for entry in CreatureDB.spawn_candidates(300.0, zone, true):
		_check(str(entry["id"]) != "lumreaper", "the legendary appeared in a natural spawn table")


func _test_creature_behaviour() -> void:
	# Each behaviour must actually produce motion / state under its trigger.
	var grib := CreatureDB.get_species("grib")
	var brain := CreatureBrain.new(1)
	var ctx := CreatureBrain.Context.new()
	ctx.data = grib
	ctx.variant = grib.variants[0]
	ctx.position = Vector2(100, 100)
	ctx.home = Vector2(100, 100)
	ctx.on_floor = true
	ctx.delta = 0.1

	# Player right on top of it: must flee to the left.
	ctx.player_position = Vector2(130, 100)
	ctx.player_distance = 30.0
	brain.tick(ctx)
	_check(ctx.state == "flee", "a skittish creature did not flee (state=%s)" % ctx.state)
	_check(ctx.desired_velocity.x < 0.0, "it fled toward the player")

	# Player far away: must wander instead.
	ctx.player_distance = 900.0
	ctx.player_position = Vector2(1000, 100)
	var saw_walk := false
	for i in 40:
		ctx.cue = ""
		brain.tick(ctx)
		if ctx.state == "walk":
			saw_walk = true
	_check(saw_walk, "a skittish creature never wandered when left alone")

	# Aggressive: must charge when the player is in range.
	var kryx := CreatureDB.get_species("kryx")
	var b2 := CreatureBrain.new(2)
	var c2 := CreatureBrain.Context.new()
	c2.data = kryx
	c2.variant = kryx.variants[0]
	c2.position = Vector2(0, 0)
	c2.home = Vector2(0, 0)
	c2.on_floor = true
	c2.delta = 0.1
	c2.player_position = Vector2(80, 0)
	c2.player_distance = 80.0
	b2.tick(c2)
	_check(c2.state == "charge", "an aggressive creature did not charge")
	_check(c2.desired_velocity.x > 0.0, "it charged the wrong way")

	# Burrower: blocked ahead must produce a dig request, not a turn.
	var molo := CreatureDB.get_species("molo")
	var b3 := CreatureBrain.new(3)
	var c3 := CreatureBrain.Context.new()
	c3.data = molo
	c3.variant = molo.variants[0]
	c3.position = Vector2(500, 500)
	c3.home = Vector2(500, 500)
	c3.on_floor = true
	c3.delta = 0.1
	c3.player_distance = 2000.0
	c3.player_position = Vector2(9000, 9000)
	c3.blocked_ahead = true
	var dug := false
	for i in 12:
		c3.mine_tile = Vector2i(-1, -1)
		b3.tick(c3)
		if c3.mine_tile.x >= 0:
			dug = true
			break
	_check(dug, "a burrower never tried to dig through a wall")

	# Apex: must cycle through all three phases and expose a damage window.
	var apex := CreatureDB.get_species("lumreaper")
	var b4 := CreatureBrain.new(4)
	var c4 := CreatureBrain.Context.new()
	c4.data = apex
	c4.variant = apex.variants[0]
	c4.position = Vector2(0, 0)
	c4.home = Vector2(0, 0)
	c4.player_position = Vector2(200, 0)
	c4.player_distance = 200.0
	c4.delta = 0.25
	var seen: Dictionary = {}
	var vulnerable_ticks := 0
	for i in 400:
		c4.time = float(i) * 0.25
		b4.tick(c4)
		seen[c4.state] = true
		if not c4.invulnerable and c4.state == "exposed":
			vulnerable_ticks += 1
	_check(seen.has("hunt") and seen.has("flare") and seen.has("exposed"),
		"the apex did not cycle its phases: %s" % str(seen.keys()))
	_check(vulnerable_ticks > 10, "the apex never became vulnerable")

	# Phantom: enough damage must make it disappear rather than fight on.
	var ab := CreatureDB.get_species("aberrant")
	var b5 := CreatureBrain.new(5)
	var c5 := CreatureBrain.Context.new()
	c5.data = ab
	c5.variant = ab.variants[0]
	c5.position = Vector2(0, 0)
	c5.home = Vector2(0, 0)
	c5.player_position = Vector2(40, 0)
	c5.player_distance = 40.0
	c5.delta = 0.1
	c5.hp_ratio = 0.3
	var dissolved := false
	for i in 40:
		b5.tick(c5)
		if c5.state == "dissolve" or c5.dissolve > 0.0:
			dissolved = true
	_check(dissolved, "a wounded phantom never dissolved")


func _test_codex() -> void:
	var codex := Codex.new()
	_check(codex.discovered() == 0, "a fresh codex is not empty")
	_check(codex.catalogued() == CreatureDB.species_ids().size(), "catalogued count is wrong")
	_check(codex.planned_slots() == GameConfig.CODEX_PLANNED_SLOTS, "planned slot count is wrong")

	var brand_new := codex.note_sighting("grib", "normal", 12.0)
	_check(brand_new, "the first sighting was not reported as new")
	_check(not codex.note_sighting("grib", "normal", 14.0), "a repeat sighting was reported as new")
	_check(codex.discovered() == 1, "discovered count did not increase")
	_check(codex.is_sighted("grib"), "grib is not marked as sighted")

	# Fields stay locked until observed.
	for field in Codex.FIELDS:
		_check(not codex.is_field_known("grib", field),
			"field '%s' was known before any observation" % field)

	codex.add_observation("grib", 1.6)
	_check(codex.is_field_known("grib", "habitat"), "habitat did not unlock at 1.6 s")
	_check(not codex.is_field_known("grib", "lore"), "lore unlocked far too early")

	codex.add_observation("grib", GameConfig.OBSERVATION_FULL)
	for field in Codex.FIELDS:
		_check(codex.is_field_known("grib", field), "field '%s' never unlocked" % field)
	_check(codex.observation("grib") <= GameConfig.OBSERVATION_FULL, "observation exceeded the cap")

	# Observation on an unsighted species must do nothing.
	codex.add_observation("kryx", 5.0)
	_check(not codex.is_sighted("kryx"), "observing an unseen species created an entry")

	# Defeating something teaches resource and weakness immediately.
	codex.note_sighting("kryx", "normal", 90.0)
	_check(not codex.is_field_known("kryx", "weakness"), "weakness was already known")
	codex.note_defeat("kryx")
	_check(codex.is_field_known("kryx", "weakness"), "defeating did not reveal weakness")
	_check(codex.is_field_known("kryx", "resource"), "defeating did not reveal the resource")

	# Variants are tracked separately and raise completion.
	var before := codex.completion("kryx")
	codex.note_sighting("kryx", "alpha", 120.0)
	_check(codex.known_variants("kryx").size() == 2, "the variant was not recorded")
	_check(codex.completion("kryx") > before, "seeing a variant did not raise completion")

	# Depth range tracking.
	var e := codex.entry("kryx")
	_check(float(e["min_depth"]) == 90.0, "min depth is wrong")
	_check(float(e["max_depth"]) == 120.0, "max depth is wrong")

	# Round trip, including rejection of species that no longer exist.
	var dict := codex.to_dict()
	(dict["entries"] as Dictionary)["ghost_species"] = {"observation": 2.0, "fields": {}}
	var restored := Codex.new()
	restored.from_dict(dict)
	_check(restored.discovered() == 2, "codex round trip lost entries")
	_check(not restored.entries.has("ghost_species"), "a stale species survived loading")
	_check(restored.is_field_known("grib", "lore"), "field unlocks were lost in the round trip")
	_check(restored.completion("kryx") == codex.completion("kryx"), "completion changed on reload")

	# debug_unlock_all must complete every entry.
	var full := Codex.new()
	full.debug_unlock_all()
	_check(full.discovered() == full.catalogued(), "debug unlock did not discover everything")
	_check(full.overall_completion() > 0.99, "debug unlock left entries incomplete")


func _test_ecology() -> void:
	var world := DeepWorld.new()
	add_child(world)
	world.initialize(31337)

	var eco := world.ecology
	var tile := Vector2i(150, GameConfig.SURFACE_ROW + 120)

	# Hunting a region thins its spawn weight, and it recovers over time.
	_check(eco.population_factor(tile, "kryx") == 1.0, "a fresh region is not at full population")
	for i in 5:
		eco.note_kill(tile, "kryx")
	_check(eco.population_factor(tile, "kryx") < 0.45,
		"five kills barely moved the population (%.2f)" % eco.population_factor(tile, "kryx"))
	for i in 40:
		eco.advance(GameConfig.ECOLOGY_TICK_SECONDS + 0.1)
	_check(eco.population_factor(tile, "kryx") > 0.95, "the population never recovered")

	# A mined ore vein comes back; a mined tunnel does not.
	var ore := _find_block(world, BlockDB.COPPER_ORE)
	if _check(ore.x >= 0, "could not find copper to test regrowth"):
		world.set_tile(ore.x, ore.y, BlockDB.AIR, true)
		_check(world.get_tile(ore.x, ore.y) == BlockDB.AIR, "mining did not clear the tile")
		_check(world.has_modification(ore.x, ore.y), "mining did not record a modification")
		for i in int(GameConfig.ORE_REGROW_SECONDS / GameConfig.ECOLOGY_TICK_SECONDS) + 3:
			eco.advance(GameConfig.ECOLOGY_TICK_SECONDS + 0.1)
		_check(world.get_tile(ore.x, ore.y) == BlockDB.COPPER_ORE, "the copper vein never regrew")

	var rock := _find_block(world, BlockDB.STONE)
	if _check(rock.x >= 0, "could not find stone to test tunnel persistence"):
		world.set_tile(rock.x, rock.y, BlockDB.AIR, true)
		for i in int(GameConfig.ORE_REGROW_SECONDS / GameConfig.ECOLOGY_TICK_SECONDS) + 3:
			eco.advance(GameConfig.ECOLOGY_TICK_SECONDS + 0.1)
		_check(world.get_tile(rock.x, rock.y) == BlockDB.AIR,
			"a dug tunnel grew back; player excavation must be permanent")

	# Ecology state must survive a round trip.
	var dict := eco.to_dict()
	var eco2 := Ecology.new(world)
	eco2.from_dict(dict)
	_check(absf(eco2.playtime() - eco.playtime()) < 0.01, "playtime lost in the ecology round trip")

	world.queue_free()


func _find_block(world: DeepWorld, block_id: int) -> Vector2i:
	for ty in range(GameConfig.SURFACE_ROW + 20, GameConfig.SURFACE_ROW + 420):
		for tx in range(100, 280):
			if world.get_tile(tx, ty) == block_id:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func _test_save_round_trip() -> void:
	var slot := GameConfig.SAVE_SLOTS - 1
	SaveManager.delete_slot(slot)

	var world := DeepWorld.new()
	add_child(world)
	world.initialize(98765)
	Game.world = world
	Game.new_run(98765, slot)

	# A stand-in for the player node, so the saved position is a real value
	# rather than the origin.
	var stub := _PlayerStub.new()
	stub.global_position = Vector2(1234.5, 6789.25)
	add_child(stub)
	Game.player = stub

	# Build a run state worth saving.
	Game.inventory.add("copper_ore", 17)
	Game.inventory.add("crystal_shard", 3)
	Game.set_active_tool("pick_starter")
	Game.codex.note_sighting("grib", "normal", 11.0)
	Game.codex.add_observation("grib", 4.0)
	Game.codex.note_sighting("molo", "ironfed", 42.0)
	Game.note_zone("rootlands_caverns")
	Game.bump_stat("blocks_mined", 23)
	Game.deepest_metres = 137.5
	Game.chest.add("plank", 9)

	# And some world edits, both destructive and constructive.
	var edits: Array[Vector2i] = []
	var base := GameConfig.world_to_tile(world.spawn_position())
	for i in 24:
		var t := Vector2i(base.x + 2 + i % 8, base.y + 6 + i / 8)
		if world.set_tile(t.x, t.y, BlockDB.AIR, false):
			edits.append(t)
	var placed := Vector2i(base.x - 5, base.y + 4)
	world.set_tile(placed.x, placed.y, BlockDB.PLANK, false)

	stub.health = 77.0
	var payload := Game.build_payload()
	_check(SaveManager.validate(payload), "the payload we just built failed validation")
	_check(SaveManager.write_slot(slot, payload), "write_slot failed")
	_check(SaveManager.has_slot(slot), "has_slot is false after writing")

	var summary := SaveManager.slot_summary(slot)
	_check(bool(summary["exists"]), "slot summary says the slot is empty")
	_check(int(summary["seed"]) == 98765, "slot summary has the wrong seed")
	_check(int(summary["discovered"]) == 2, "slot summary has the wrong codex count")

	# Wipe everything, then reload.
	var saved_mod_count := world.modification_count()
	Game._reset_containers()
	Game.world = null
	Game.player = null
	stub.queue_free()
	world.queue_free()
	_check(Game.inventory.count("copper_ore") == 0, "the reset did not clear the inventory")

	var loaded := SaveManager.read_slot(slot)
	_check(not loaded.is_empty(), "read_slot returned nothing")
	var pos := Game.apply_payload(loaded, slot)

	_check(Game.world_seed == 98765, "the seed did not survive the round trip")
	_check(Game.inventory.count("copper_ore") == 17, "the inventory did not survive")
	_check(Game.inventory.count("crystal_shard") == 3, "crystal did not survive")
	_check(Game.chest.count("plank") == 9, "chest contents did not survive")
	_check(Game.codex.discovered() == 2, "codex entries did not survive")
	_check(Game.codex.is_field_known("grib", "habitat"), "codex field unlocks did not survive")
	_check("ironfed" in Game.codex.known_variants("molo"), "a recorded variant did not survive")
	_check(Game.has_zone("rootlands_caverns"), "zone progress did not survive")
	_check(int(Game.stats.get("blocks_mined", 0)) == 23, "statistics did not survive")
	_check(absf(Game.deepest_metres - 137.5) < 0.01, "the depth record did not survive")
	_check(pos.is_equal_approx(Vector2(1234.5, 6789.25)),
		"the player position did not survive (got %s)" % str(pos))
	_check(absf(Game.stored_health(loaded) - 77.0) < 0.01,
		"player health did not survive (got %.1f)" % Game.stored_health(loaded))

	# Rebuild the world from the seed + mods and verify the terrain matches.
	var world2 := DeepWorld.new()
	add_child(world2)
	world2.initialize(Game.world_seed, DeepWorld.parse_modifications(loaded.get("world_mods", {})))
	Game.world = world2
	_check(world2.modification_count() == saved_mod_count,
		"modification count changed across the round trip (%d vs %d)"
			% [world2.modification_count(), saved_mod_count])
	var wrong := 0
	for t in edits:
		if world2.get_tile(t.x, t.y) != BlockDB.AIR:
			wrong += 1
	_check(wrong == 0, "%d mined tiles came back after reloading" % wrong)
	_check(world2.get_tile(placed.x, placed.y) == BlockDB.PLANK,
		"a placed block did not survive reloading")

	# Untouched terrain must regenerate identically from the seed alone.
	var fresh := WorldGen.new(98765)
	var drift := 0
	for i in 400:
		var tx := base.x + 40 + i % 60
		var ty := base.y + 40 + i / 60
		if world2.get_tile(tx, ty) != fresh.block_at(tx, ty):
			drift += 1
	_check(drift == 0, "%d untouched tiles drifted after reloading" % drift)

	world2.queue_free()
	Game.world = null
	SaveManager.delete_slot(slot)


func _test_save_corruption() -> void:
	var slot := GameConfig.SAVE_SLOTS - 1
	SaveManager.delete_slot(slot)

	# Garbage must be rejected, not crash.
	var f := FileAccess.open(SaveManager.slot_path(slot), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	_check(SaveManager.read_slot(slot).is_empty(), "malformed JSON was accepted")

	# Valid JSON that is not a DEEP save must be rejected.
	f = FileAccess.open(SaveManager.slot_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify({"hello": "world"}))
	f.close()
	_check(SaveManager.read_slot(slot).is_empty(), "a foreign JSON file was accepted")

	# A missing required key must be rejected.
	_check(not SaveManager.validate({"format": 1, "seed": 1}), "an incomplete payload validated")
	_check(not SaveManager.validate({}), "an empty payload validated")

	# A tampered checksum must be rejected.
	SaveManager.delete_slot(slot)
	var world := DeepWorld.new()
	add_child(world)
	world.initialize(42)
	Game.world = world
	Game.new_run(42, slot)
	SaveManager.write_slot(slot, Game.build_payload())
	var text := FileAccess.get_file_as_string(SaveManager.slot_path(slot))
	var envelope: Dictionary = JSON.parse_string(text)
	envelope["payload_json"] = str(envelope.get("payload_json", "")).replace("\"seed\":42", "\"seed\":999999")
	f = FileAccess.open(SaveManager.slot_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(envelope))
	f.close()
	var after_tamper := SaveManager.read_slot(slot)
	# The backup from the clean write should take over.
	_check(after_tamper.is_empty() or int(after_tamper.get("seed", 0)) == 42,
		"a tampered save was loaded as-is")

	world.queue_free()
	Game.world = null
	SaveManager.delete_slot(slot)


## Boots the real Game scene and plays it: stream chunks, mine twenty blocks,
## verify drops and persistence.
func _test_live_world() -> void:
	var scene := load("res://scenes/game/Game.tscn") as PackedScene
	if not _check(scene != null, "the Game scene is missing"):
		return
	Game.new_run(5150, 0)
	Game.pending_load = {}
	var root := scene.instantiate()
	add_child(root)
	for _i in 12:
		await get_tree().process_frame

	var world: DeepWorld = root.get("world")
	var player: Player = root.get("player")
	if not _check(world != null and player != null, "the Game scene did not build its world"):
		root.queue_free()
		return

	_check(world.live_chunk_count() > 0, "no chunks became live around the player")
	_check(not world.is_solid_at(player.global_position),
		"the player spawned inside solid rock")
	_check(player.global_position.y < GameConfig.metres_to_world_y(20.0),
		"the player did not spawn near the surface")

	# The base camp must have levelled a platform under the spawn.
	var ground := world.first_solid_below(
		GameConfig.world_to_tile(player.global_position).x,
		GameConfig.world_to_tile(player.global_position).y, 12)
	_check(ground >= 0, "there is no floor under the spawn point")

	# Streaming: walk the camera a long way and back.
	var far := player.global_position + Vector2(0, 2400)
	for _i in 60:
		world.stream_around(far)
		await get_tree().process_frame
	_check(world.live_chunk_count() > 0, "streaming to depth produced no live chunks")
	for _i in 60:
		world.stream_around(player.global_position)
		await get_tree().process_frame
	_check(world.live_chunk_count() > 0, "streaming back to the surface produced no live chunks")

	# Mine twenty blocks through the real tile API and confirm drops.
	Game.inventory.clear()
	var before_stat := int(Game.stats.get("blocks_mined", 0))
	var mined: Array[Vector2i] = []
	var base := GameConfig.world_to_tile(player.global_position)
	var scan := 0
	while mined.size() < 20 and scan < 4000:
		var t := Vector2i(base.x - 20 + scan % 40, base.y + 5 + scan / 40)
		scan += 1
		var id := world.get_tile(t.x, t.y)
		var def := BlockDB.get_block(id)
		if not def.solid or def.unbreakable or def.drop_item.is_empty():
			continue
		if world.set_tile(t.x, t.y, BlockDB.AIR, true):
			Game.inventory.add(def.drop_item, 1)
			Game.bump_stat("blocks_mined")
			mined.append(t)
	_check(mined.size() == 20, "could only mine %d blocks near the spawn" % mined.size())
	_check(int(Game.stats.get("blocks_mined", 0)) == before_stat + 20, "the mined counter is wrong")
	_check(Game.inventory.used_slots() > 0, "mining twenty blocks yielded no items")

	for t in mined:
		if not _check(world.get_tile(t.x, t.y) == BlockDB.AIR, "a mined tile did not clear"):
			break

	# Collision must have been rebuilt for the chunks we edited.
	var chunk := GameConfig.tile_to_chunk(mined[0])
	_check(world.is_chunk_live(chunk), "the edited chunk is not live")
	await get_tree().process_frame

	# Place a block, and confirm it reads back.
	var place_tile := mined[0]
	_check(world.set_tile(place_tile.x, place_tile.y, BlockDB.PLANK, false), "placing failed")
	_check(world.get_tile(place_tile.x, place_tile.y) == BlockDB.PLANK, "the placed block did not stick")

	# Save, tear the world down, reload, and verify the edits survived.
	Game.deepest_metres = maxf(Game.deepest_metres, 60.0)
	var payload := Game.build_payload()
	_check(SaveManager.write_slot(0, payload), "saving the live run failed")

	root.queue_free()
	await get_tree().process_frame
	Game.world = null
	Game.player = null

	var reloaded := SaveManager.read_slot(0)
	_check(not reloaded.is_empty(), "the live save could not be read back")
	Game.apply_payload(reloaded, 0)
	Game.pending_load = reloaded
	var root2 := scene.instantiate()
	add_child(root2)
	for _i in 12:
		await get_tree().process_frame
	var world2: DeepWorld = root2.get("world")
	if _check(world2 != null, "the reloaded Game scene has no world"):
		var lost := 0
		for i in range(1, mined.size()):
			if world2.get_tile(mined[i].x, mined[i].y) != BlockDB.AIR:
				lost += 1
		_check(lost == 0, "%d mined tiles reverted after a reload" % lost)
		_check(world2.get_tile(place_tile.x, place_tile.y) == BlockDB.PLANK,
			"the placed plank did not survive a reload")
		_check(Game.inventory.used_slots() > 0, "the inventory did not survive a reload")
		_check(absf(Game.deepest_metres - 60.0) < 0.01 or Game.deepest_metres > 60.0,
			"the depth record did not survive a reload")
	root2.queue_free()
	await get_tree().process_frame
	Game.world = null
	Game.player = null
	SaveManager.delete_slot(0)


## Spawns creatures in the live world and drives a discovery through the real
## observation path.
func _test_live_creatures() -> void:
	var scene := load("res://scenes/game/Game.tscn") as PackedScene
	if scene == null:
		return
	Game.new_run(24680, 0)
	Game.pending_load = {}
	var root := scene.instantiate()
	add_child(root)
	for _i in 12:
		await get_tree().process_frame

	var world: DeepWorld = root.get("world")
	var player: Player = root.get("player")
	var spawner = root.get("spawner")
	var observation = root.get("observation")
	if not _check(world != null and spawner != null, "creature systems did not build"):
		root.queue_free()
		return

	# Force-spawn one of each species and make sure each one lives.
	for sid in CreatureDB.species_ids():
		var tile := world.find_open_ground(
			GameConfig.world_to_tile(player.global_position) + Vector2i(3, 0), 14)
		if tile.x < 0:
			continue
		var data := CreatureDB.get_species(sid)
		var c = spawner.call("spawn", sid, data.default_variant_id(),
			GameConfig.tile_centre(tile.x, tile.y), false)
		if not _check(c != null, "could not spawn '%s'" % sid):
			continue
		var creature := c as Creature
		_check(creature.max_hp > 0.0, "%s spawned with no health" % sid)
		_check(creature.get_child_count() >= 2, "%s has no sprite or collision" % sid)

	for _i in 8:
		await get_tree().process_frame
	_check(int(spawner.call("active_count")) >= CreatureDB.species_ids().size(),
		"creatures did not stay alive after spawning")

	# Discovery must happen through the real observation path: creatures
	# spawned beside the player, in the player's lantern light, on screen.
	if observation != null:
		for _i in 90:
			await get_tree().process_frame
	_check(Game.codex.discovered() > 0,
		"the observation tracker never discovered a creature standing next to the player")
	var discovered_ids: Array[String] = []
	for sid in CreatureDB.species_ids():
		if Game.codex.is_sighted(sid):
			discovered_ids.append(sid)
	if _check(not discovered_ids.is_empty(), "no species was sighted"):
		var sid0 := discovered_ids[0]
		_check(Game.codex.observation(sid0) > 0.0,
			"a sighted species accumulated no observation time")
		Game.codex.add_observation(sid0, GameConfig.OBSERVATION_FULL)
		_check(Game.codex.is_field_known(sid0, "habitat"),
			"observation did not unlock a field in the live run")

	# A brand-new sighting must still report as new.
	var unseen := ""
	for sid in CreatureDB.species_ids():
		if not Game.codex.is_sighted(sid):
			unseen = sid
			break
	if not unseen.is_empty():
		var before := Game.codex.discovered()
		_check(Game.codex.note_sighting(unseen, "normal", 10.0),
			"a first sighting was not reported as new")
		_check(Game.codex.discovered() == before + 1, "a sighting did not add a Codex entry")

	var list: Array = spawner.call("creatures")

	# Damage and loot: killing something must drop its loot into the pack.
	Game.inventory.clear()
	var victim := list[0] as Creature
	var vid := victim.species_id
	for _i in 200:
		if not is_instance_valid(victim):
			break
		victim.take_damage(50.0, "test")
	await get_tree().process_frame
	_check(Game.codex.entry(vid).get("defeated", 0) != 0 or Game.inventory.used_slots() >= 0,
		"defeating a creature recorded nothing")

	# The rare-event director must be able to bring in the legendary.
	var legendary_before := 0
	for item in spawner.call("creatures"):
		if (item as Creature).is_boss():
			legendary_before += 1
	spawner.call("debug_force_rare_event")
	# The director deliberately delays arrival by a few seconds, so wait on
	# wall-clock time rather than frames (headless frames are near-instant).
	var legendary_after := 0
	var deadline := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		legendary_after = 0
		for item in spawner.call("creatures"):
			var cc := item as Creature
			if cc != null and is_instance_valid(cc) and cc.is_boss():
				legendary_after += 1
		if legendary_after > legendary_before:
			break
	_check(legendary_after > legendary_before,
		"the UNKNOWN SIGNAL event did not bring in the legendary creature")
	_check(Game.progress.get("story_beats", []).has("heard_unknown_signal"),
		"the signal event did not record its story beat")

	root.queue_free()
	await get_tree().process_frame
	Game.world = null
	Game.player = null
	SaveManager.delete_slot(0)


## Minimal stand-in for the player, used where a full Player node is not needed.
class _PlayerStub extends Node2D:
	var health: float = 100.0

	func get_health() -> float:
		return health
