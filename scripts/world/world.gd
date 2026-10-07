class_name DeepWorld
extends Node2D
## The world: chunk streaming, tile access, and the player-modification layer.
##
## Two distinct things make up any tile:
##   WORLD BASE          what the seed generates — never stored, always
##                       recomputable, so a save file stays tiny.
##   PLAYER MODIFICATION an explicit override the player caused — stored, and
##                       re-applied every time its chunk is regenerated.
##
## Keeping them separate is what lets a region both "come back to life"
## (resource overrides are allowed to expire) and stay permanently shaped by
## the player (tunnels and built blocks never expire).

const TERRAIN_SHADER: String = "res://shaders/terrain.gdshader"
## Hard cap on cached chunk tile data. Well above the live set so pacing back
## and forth over a chunk border never re-generates.
const CACHE_LIMIT: int = 180

var gen: WorldGen = null
var lights: LightField = null
var ecology: Ecology = null

var world_seed: int = 0

var _shader: Shader = null
var _chunk_root: Node2D = null
## Vector2i -> ChunkData
var _cache: Dictionary = {}
var _cache_order: Array[Vector2i] = []
## Vector2i -> ChunkNode
var _live: Dictionary = {}
## Vector2i -> { local_index: block_id }
var _mods: Dictionary = {}
var _pending_builds: Array[Vector2i] = []
var _focus_chunk: Vector2i = Vector2i(-9999, -9999)
var _static_lights_dirty: bool = true
var _lookup: Callable = Callable()


func _ready() -> void:
	_shader = load(TERRAIN_SHADER) as Shader
	_chunk_root = Node2D.new()
	_chunk_root.name = "Chunks"
	add_child(_chunk_root)
	_lookup = Callable(self, "get_tile")
	lights = LightField.new()
	ecology = Ecology.new(self)


func initialize(p_seed: int, mods: Dictionary = {}) -> void:
	world_seed = p_seed
	gen = WorldGen.new(p_seed)
	_mods = mods.duplicate(true)
	_cache.clear()
	_cache_order.clear()
	for coord in _live.keys():
		(_live[coord] as ChunkNode).release()
	_live.clear()
	_pending_builds.clear()
	_focus_chunk = Vector2i(-9999, -9999)
	_static_lights_dirty = true
	ecology.reset()
	EventBus.world_ready.emit(p_seed)


# --- Tile access -------------------------------------------------------------

func get_tile(tx: int, ty: int) -> int:
	if not GameConfig.in_bounds(tx, ty):
		return BlockDB.BEDROCK
	var coord := GameConfig.tile_to_chunk(Vector2i(tx, ty))
	var data := _resolve(coord)
	var origin := coord * GameConfig.CHUNK_TILES
	return data.get_local(tx - origin.x, ty - origin.y)


func get_tile_v(t: Vector2i) -> int:
	return get_tile(t.x, t.y)


func is_solid_at(world_pos: Vector2) -> bool:
	var t := GameConfig.world_to_tile(world_pos)
	return BlockDB.is_solid(get_tile(t.x, t.y))


## Write a tile and persist it as a player modification.
## `natural` marks the change as something ecology may later undo.
func set_tile(tx: int, ty: int, id: int, natural: bool = false) -> bool:
	if not GameConfig.in_bounds(tx, ty):
		return false
	var old := get_tile(tx, ty)
	if old == id:
		return false
	if BlockDB.get_block(old).unbreakable and id == BlockDB.AIR:
		return false

	var coord := GameConfig.tile_to_chunk(Vector2i(tx, ty))
	var origin := coord * GameConfig.CHUNK_TILES
	var lx := tx - origin.x
	var ly := ty - origin.y
	var idx := ChunkData.local_index(lx, ly)

	var data := _resolve(coord)
	data.set_local(lx, ly, id)

	# Record (or clear) the override. If the new value matches what the seed
	# would produce anyway, drop the entry instead of storing a no-op.
	var chunk_mods: Dictionary = _mods.get(coord, {})
	if gen.block_at(tx, ty) == id:
		chunk_mods.erase(idx)
		if chunk_mods.is_empty():
			_mods.erase(coord)
		else:
			_mods[coord] = chunk_mods
	else:
		chunk_mods[idx] = id
		_mods[coord] = chunk_mods

	if natural and id == BlockDB.AIR:
		ecology.note_harvest(Vector2i(tx, ty), old)

	_mark_dirty(coord)
	# A tile on a chunk seam is part of its neighbour's border texture too.
	if lx == 0:
		_mark_dirty(coord + Vector2i(-1, 0))
	elif lx == GameConfig.CHUNK_TILES - 1:
		_mark_dirty(coord + Vector2i(1, 0))
	if ly == 0:
		_mark_dirty(coord + Vector2i(0, -1))
	elif ly == GameConfig.CHUNK_TILES - 1:
		_mark_dirty(coord + Vector2i(0, 1))
	if lx == 0 or lx == GameConfig.CHUNK_TILES - 1:
		if ly == 0 or ly == GameConfig.CHUNK_TILES - 1:
			_mark_dirty(coord + Vector2i(signi(lx * 2 - GameConfig.CHUNK_TILES), signi(ly * 2 - GameConfig.CHUNK_TILES)))

	_static_lights_dirty = true
	EventBus.tile_changed.emit(Vector2i(tx, ty), old, id)
	return true


## Remove the override on a tile so the generated material returns.
## This is how ecology regrows a mined-out vein without touching tunnels.
func clear_modification(tx: int, ty: int) -> void:
	var coord := GameConfig.tile_to_chunk(Vector2i(tx, ty))
	if not _mods.has(coord):
		return
	var origin := coord * GameConfig.CHUNK_TILES
	var idx := ChunkData.local_index(tx - origin.x, ty - origin.y)
	var chunk_mods: Dictionary = _mods[coord]
	if not chunk_mods.has(idx):
		return
	chunk_mods.erase(idx)
	if chunk_mods.is_empty():
		_mods.erase(coord)
	var regenerated := gen.block_at(tx, ty)
	if _cache.has(coord):
		var data: ChunkData = _cache[coord]
		data.set_local(tx - origin.x, ty - origin.y, regenerated)
	_mark_dirty(coord)
	_static_lights_dirty = true
	EventBus.tile_changed.emit(Vector2i(tx, ty), BlockDB.AIR, regenerated)


func has_modification(tx: int, ty: int) -> bool:
	var coord := GameConfig.tile_to_chunk(Vector2i(tx, ty))
	if not _mods.has(coord):
		return false
	var origin := coord * GameConfig.CHUNK_TILES
	return (_mods[coord] as Dictionary).has(ChunkData.local_index(tx - origin.x, ty - origin.y))


# --- Queries used by gameplay ------------------------------------------------

func surface_row(tx: int) -> int:
	return gen.surface_row(tx)


func spawn_position() -> Vector2:
	return gen.spawn_position()


## First solid tile at or below `from_ty` in column `tx`, or -1.
func first_solid_below(tx: int, from_ty: int, limit: int = 64) -> int:
	for i in limit:
		var ty := from_ty + i
		if not GameConfig.in_bounds(tx, ty):
			return -1
		if BlockDB.is_solid(get_tile(tx, ty)):
			return ty
	return -1


## Nearest open tile with solid ground under it — used for spawning creatures
## and for un-sticking the player after a load.
func find_open_ground(near: Vector2i, radius: int = 10) -> Vector2i:
	for r in radius:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t := near + Vector2i(dx, dy)
				if not GameConfig.in_bounds(t.x, t.y):
					continue
				if BlockDB.is_solid(get_tile(t.x, t.y)):
					continue
				if BlockDB.is_solid(get_tile(t.x, t.y - 1)):
					continue
				if BlockDB.is_solid(get_tile(t.x, t.y + 1)):
					return t
	return Vector2i(-1, -1)


func is_chunk_live(coord: Vector2i) -> bool:
	return _live.has(coord)


func live_chunk_count() -> int:
	return _live.size()


# --- Streaming ---------------------------------------------------------------

## Keep the live chunk set centred on `focus` (normally the player).
func stream_around(focus: Vector2) -> void:
	if gen == null:
		return
	var centre := GameConfig.tile_to_chunk(GameConfig.world_to_tile(focus))
	if centre != _focus_chunk:
		_focus_chunk = centre
		_refresh_desired_set()
	_process_build_queue()


func _refresh_desired_set() -> void:
	var want: Dictionary = {}
	for dy in range(-GameConfig.CHUNK_LOAD_RADIUS_Y, GameConfig.CHUNK_LOAD_RADIUS_Y + 1):
		for dx in range(-GameConfig.CHUNK_LOAD_RADIUS_X, GameConfig.CHUNK_LOAD_RADIUS_X + 1):
			var c := _focus_chunk + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= GameConfig.CHUNKS_X or c.y >= GameConfig.CHUNKS_Y:
				continue
			want[c] = true

	# Release anything outside the keep ring.
	var keep := GameConfig.CHUNK_LOAD_RADIUS_X + GameConfig.CHUNK_KEEP_RADIUS
	for coord in _live.keys():
		var d: Vector2i = coord - _focus_chunk
		if absi(d.x) > keep or absi(d.y) > keep + GameConfig.CHUNK_KEEP_RADIUS:
			(_live[coord] as ChunkNode).release()
			_live.erase(coord)
			EventBus.chunk_released.emit(coord)
			_static_lights_dirty = true

	_pending_builds.clear()
	var pending: Array[Vector2i] = []
	for coord: Vector2i in want.keys():
		if not _live.has(coord):
			pending.append(coord)
	# Nearest first, so the chunk you are standing in always appears first.
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _focus_chunk).length_squared() < (b - _focus_chunk).length_squared())
	_pending_builds = pending


func _process_build_queue() -> void:
	var budget := GameConfig.CHUNK_BUILDS_PER_FRAME
	while budget > 0 and not _pending_builds.is_empty():
		var coord: Vector2i = _pending_builds.pop_front()
		if _live.has(coord):
			continue
		_activate(coord)
		budget -= 1
	# Rebuild any live chunk whose tiles changed.
	for coord in _live.keys():
		var node: ChunkNode = _live[coord]
		if node.data != null and node.data.dirty:
			node.rebuild()
			_static_lights_dirty = true
	if _static_lights_dirty:
		_recollect_static_lights()


func _activate(coord: Vector2i) -> void:
	var data := _resolve(coord)
	var node := ChunkNode.new()
	node.name = "Chunk_%d_%d" % [coord.x, coord.y]
	_chunk_root.add_child(node)
	node.setup(data, _lookup, _shader)
	_live[coord] = node
	_static_lights_dirty = true
	EventBus.chunk_activated.emit(coord)


func _mark_dirty(coord: Vector2i) -> void:
	if _cache.has(coord):
		(_cache[coord] as ChunkData).dirty = true
		(_cache[coord] as ChunkData).analysed = false


func _recollect_static_lights() -> void:
	var all: Array[Dictionary] = []
	for coord in _live.keys():
		var node: ChunkNode = _live[coord]
		if node.data == null:
			continue
		if not node.data.analysed:
			node.data.analyse()
		for s in node.data.light_sources:
			all.append(s)
	lights.set_static_sources(all)
	_static_lights_dirty = false


# --- Chunk data resolution ---------------------------------------------------

func _resolve(coord: Vector2i) -> ChunkData:
	if _cache.has(coord):
		var hit: ChunkData = _cache[coord]
		_touch(coord)
		return hit
	var data := ChunkData.new(coord)
	gen.generate_chunk(coord.x, coord.y, data.tiles)
	# Re-apply the player's overrides on top of the freshly generated base.
	if _mods.has(coord):
		var m: Dictionary = _mods[coord]
		for idx: int in m.keys():
			if idx >= 0 and idx < data.tiles.size():
				data.tiles[idx] = int(m[idx])
	data.dirty = true
	data.analysed = false
	_cache[coord] = data
	_cache_order.append(coord)
	_evict_if_needed()
	return data


func _touch(coord: Vector2i) -> void:
	var i := _cache_order.find(coord)
	if i >= 0:
		_cache_order.remove_at(i)
	_cache_order.append(coord)


func _evict_if_needed() -> void:
	while _cache_order.size() > CACHE_LIMIT:
		var victim: Vector2i = _cache_order.pop_front()
		if _live.has(victim):
			# Never evict something currently on screen; re-queue it instead.
			_cache_order.append(victim)
			if _cache_order.size() <= CACHE_LIMIT:
				return
			continue
		_cache.erase(victim)


# --- Save / load -------------------------------------------------------------

## JSON-safe snapshot of player modifications: "cx,cy" -> { "index": block }.
func export_modifications() -> Dictionary:
	var out: Dictionary = {}
	for coord: Vector2i in _mods.keys():
		var m: Dictionary = _mods[coord]
		if m.is_empty():
			continue
		var inner: Dictionary = {}
		for idx: int in m.keys():
			inner[str(idx)] = int(m[idx])
		out["%d,%d" % [coord.x, coord.y]] = inner
	return out


static func parse_modifications(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in raw.keys():
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var coord := Vector2i(int(parts[0]), int(parts[1]))
		var inner: Dictionary = {}
		var src: Dictionary = raw[key]
		for idx_key in src.keys():
			inner[int(str(idx_key))] = int(src[idx_key])
		if not inner.is_empty():
			out[coord] = inner
	return out


func modification_count() -> int:
	var n := 0
	for coord: Vector2i in _mods.keys():
		n += (_mods[coord] as Dictionary).size()
	return n
