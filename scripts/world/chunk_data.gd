class_name ChunkData
extends RefCounted
## The tile contents of one chunk, plus everything derived from it that the
## renderer and physics need. Deliberately plain data: ChunkNode owns the
## scene-tree side, World owns the lifecycle.

var coord: Vector2i = Vector2i.ZERO
## CHUNK_TILES² block ids, row-major.
var tiles: PackedByteArray = PackedByteArray()
## Rectangles (in tile space, local to the chunk) covering all solid tiles.
var collision_rects: Array[Rect2i] = []
## Clustered emissive hot-spots, in world pixels: {pos, colour, radius, intensity}.
var light_sources: Array[Dictionary] = []
## Set when tiles changed and textures / collision need rebuilding.
var dirty: bool = true
## True once collision_rects and light_sources have been computed.
var analysed: bool = false


func _init(p_coord: Vector2i) -> void:
	coord = p_coord
	tiles = PackedByteArray()
	tiles.resize(GameConfig.CHUNK_TILES * GameConfig.CHUNK_TILES)


static func local_index(lx: int, ly: int) -> int:
	return ly * GameConfig.CHUNK_TILES + lx


func get_local(lx: int, ly: int) -> int:
	if lx < 0 or ly < 0 or lx >= GameConfig.CHUNK_TILES or ly >= GameConfig.CHUNK_TILES:
		return BlockDB.AIR
	return tiles[local_index(lx, ly)]


func set_local(lx: int, ly: int, id: int) -> void:
	tiles[local_index(lx, ly)] = id
	dirty = true
	analysed = false


func origin_tile() -> Vector2i:
	return coord * GameConfig.CHUNK_TILES


func origin_px() -> Vector2:
	return Vector2(coord) * float(GameConfig.CHUNK_PX)


## Greedy rectangle decomposition of the solid tiles.
##
## A naive one-box-per-tile body would be ~1000 shapes per chunk; merging runs
## horizontally and then vertically typically gets that to a few dozen, which
## is what makes a fully destructible world affordable on a phone.
func analyse() -> void:
	collision_rects.clear()
	light_sources.clear()
	var cs := GameConfig.CHUNK_TILES
	var claimed := PackedByteArray()
	claimed.resize(cs * cs)

	for y in cs:
		for x in cs:
			var i := local_index(x, y)
			if claimed[i] == 1:
				continue
			if not BlockDB.is_solid(tiles[i]):
				continue
			# Extend right along the row.
			var w := 1
			while x + w < cs:
				var j := local_index(x + w, y)
				if claimed[j] == 1 or not BlockDB.is_solid(tiles[j]):
					break
				w += 1
			# Extend down while the whole w-wide span stays solid.
			var h := 1
			while y + h < cs:
				var ok := true
				for k in w:
					var j := local_index(x + k, y + h)
					if claimed[j] == 1 or not BlockDB.is_solid(tiles[j]):
						ok = false
						break
				if not ok:
					break
				h += 1
			for yy in h:
				for xx in w:
					claimed[local_index(x + xx, y + yy)] = 1
			collision_rects.append(Rect2i(x, y, w, h))

	_cluster_lights()
	analysed = true


## Emissive tiles are bucketed into a 2x2 grid over the chunk and each bucket
## becomes at most one light. Keeps the global light budget meaningful without
## a crystal seam costing sixteen light slots.
func _cluster_lights() -> void:
	var cs := GameConfig.CHUNK_TILES
	var buckets := 2
	var span := cs / buckets
	var acc_pos: Array[Vector2] = []
	var acc_col: Array[Color] = []
	var acc_n: Array[int] = []
	var acc_strength: Array[float] = []
	for _i in buckets * buckets:
		acc_pos.append(Vector2.ZERO)
		acc_col.append(Color(0, 0, 0))
		acc_n.append(0)
		acc_strength.append(0.0)

	for y in cs:
		for x in cs:
			var def := BlockDB.get_block(tiles[local_index(x, y)])
			if def.emission < 0.25:
				continue
			var b := mini(y / span, buckets - 1) * buckets + mini(x / span, buckets - 1)
			acc_pos[b] += Vector2(float(x) + 0.5, float(y) + 0.5)
			acc_col[b] = Color(
				acc_col[b].r + def.emission_colour.r,
				acc_col[b].g + def.emission_colour.g,
				acc_col[b].b + def.emission_colour.b
			)
			acc_strength[b] += def.emission
			acc_n[b] += 1

	var base := origin_px()
	for b in buckets * buckets:
		var n := acc_n[b]
		if n == 0:
			continue
		var centre: Vector2 = base + (acc_pos[b] / float(n)) * float(GameConfig.TILE_SIZE)
		var col := Color(acc_col[b].r / n, acc_col[b].g / n, acc_col[b].b / n)
		# More tiles in a cluster = a wider, stronger pool of light.
		var radius: float = clampf(46.0 + sqrt(float(n)) * 26.0, 46.0, 230.0)
		var intensity: float = clampf(0.22 + (acc_strength[b] / float(n)) * 0.55, 0.0, 0.95)
		light_sources.append({
			"pos": centre,
			"colour": col,
			"radius": radius,
			"intensity": intensity,
		})
