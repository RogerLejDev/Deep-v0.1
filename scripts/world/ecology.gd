class_name Ecology
extends RefCounted
## Makes a visited region recover instead of staying strip-mined.
##
## Two abstractions, both deliberately cheap enough to run while most of the
## world is unloaded:
##
##   HARVEST LEDGER  Every resource tile the player removes is logged with the
##                   playtime at which it happened. After a cooldown the
##                   override is simply *forgotten*, so the seed's original
##                   material reappears. Tunnels and placed blocks are never
##                   logged, so the shape the player carved is permanent while
##                   the veins inside it come back.
##
##   POPULATION      Each region (a 4x4 block of chunks) carries one float per
##                   species: 1.0 = untouched, 0.0 = hunted out. Killing a
##                   creature pushes its region's value down and lifts its
##                   predators' prey pressure; the value recovers over time.
##                   The spawner multiplies spawn weights by it, so over-
##                   hunting an area visibly thins it out for a while.

const REGION_CHUNKS: int = 4
## Only these materials are treated as renewable. Stone and dirt are not: a
## tunnel you dug stays dug.
const RENEWABLE := [
	BlockDB.COPPER_ORE, BlockDB.IRON_ORE, BlockDB.CRYSTAL, BlockDB.DEEP_CRYSTAL,
	BlockDB.MUSHROOM, BlockDB.GLOW_MOSS, BlockDB.ROOT,
]

var _world: DeepWorld
## Array of { tile: Vector2i, block: int, at: float }
var _ledger: Array[Dictionary] = []
## "rx,ry" -> { species_id: float }
var _population: Dictionary = {}
var _playtime: float = 0.0
var _tick_accum: float = 0.0
var _recovered_this_session: int = 0


func _init(p_world: DeepWorld) -> void:
	_world = p_world


func reset() -> void:
	_ledger.clear()
	_population.clear()
	_playtime = 0.0
	_tick_accum = 0.0
	_recovered_this_session = 0


func advance(delta: float) -> void:
	_playtime += delta
	_tick_accum += delta
	if _tick_accum < GameConfig.ECOLOGY_TICK_SECONDS:
		return
	_tick_accum = 0.0
	_recover_resources()
	_recover_populations()


func playtime() -> float:
	return _playtime


func set_playtime(t: float) -> void:
	_playtime = t


# --- Resources ---------------------------------------------------------------

func note_harvest(tile: Vector2i, block_id: int) -> void:
	if not RENEWABLE.has(block_id):
		return
	_ledger.append({"tile": tile, "block": block_id, "at": _playtime})


func _recover_resources() -> void:
	if _ledger.is_empty():
		return
	var survivors: Array[Dictionary] = []
	var recovered := 0
	for entry in _ledger:
		var age: float = _playtime - float(entry["at"])
		if age < GameConfig.ORE_REGROW_SECONDS:
			survivors.append(entry)
			continue
		var tile: Vector2i = entry["tile"]
		# Only restore if the player has not since built here, and the tile is
		# still an empty hole.
		if _world.get_tile(tile.x, tile.y) == BlockDB.AIR:
			_world.clear_modification(tile.x, tile.y)
			recovered += 1
		# Either way the ledger entry is done with.
	_ledger = survivors
	if recovered > 0:
		_recovered_this_session += recovered
		EventBus.region_recovered.emit("resources:%d" % recovered)


func pending_regrowth() -> int:
	return _ledger.size()


func recovered_count() -> int:
	return _recovered_this_session


# --- Populations -------------------------------------------------------------

static func region_key(tile: Vector2i) -> String:
	var span := GameConfig.CHUNK_TILES * REGION_CHUNKS
	return "%d,%d" % [floori(float(tile.x) / span), floori(float(tile.y) / span)]


## 0..1 multiplier applied to a species' spawn weight in this region.
func population_factor(tile: Vector2i, species_id: String) -> float:
	var key := region_key(tile)
	if not _population.has(key):
		return 1.0
	var r: Dictionary = _population[key]
	return clampf(float(r.get(species_id, 1.0)), 0.0, 1.0)


func note_kill(tile: Vector2i, species_id: String) -> void:
	var key := region_key(tile)
	var r: Dictionary = _population.get(key, {})
	var cur: float = float(r.get(species_id, 1.0))
	# Each kill removes a slice of the local population. Six or seven kills in
	# one region makes that species noticeably scarce there.
	r[species_id] = maxf(0.08, cur - 0.14)
	_population[key] = r


func _recover_populations() -> void:
	var drained: Array[String] = []
	for key: String in _population.keys():
		var r: Dictionary = _population[key]
		var all_full := true
		for sid: String in r.keys():
			var v: float = minf(1.0, float(r[sid]) + 0.06)
			r[sid] = v
			if v < 0.999:
				all_full = false
		if all_full:
			drained.append(key)
	for key in drained:
		_population.erase(key)
		EventBus.region_recovered.emit("population:" + key)


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	var ledger: Array = []
	for e in _ledger:
		var t: Vector2i = e["tile"]
		ledger.append([t.x, t.y, int(e["block"]), float(e["at"])])
	return {
		"playtime": _playtime,
		"ledger": ledger,
		"population": _population.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	reset()
	_playtime = float(d.get("playtime", 0.0))
	for row in d.get("ledger", []):
		if row is Array and (row as Array).size() == 4:
			_ledger.append({
				"tile": Vector2i(int(row[0]), int(row[1])),
				"block": int(row[2]),
				"at": float(row[3]),
			})
	var pop: Dictionary = d.get("population", {})
	for key in pop.keys():
		var inner: Dictionary = {}
		for sid in (pop[key] as Dictionary).keys():
			inner[str(sid)] = float((pop[key] as Dictionary)[sid])
		_population[str(key)] = inner
