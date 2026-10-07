class_name WorldGen
extends RefCounted
## Deterministic, seed-driven terrain generator.
##
## `block_at(tx, ty)` is a pure function of (seed, tx, ty): the same seed always
## rebuilds the same world, which is what lets DEEP save only a seed plus the
## player's own edits. Nothing in here looks at runtime state.
##
## Layering, outermost first:
##   1. world shell (bedrock border)
##   2. structures  (StructureGen overlay — vaults, crystal chambers, hollows)
##   3. caves       (two-noise tunnel intersection + large deep caverns)
##   4. strata      (dirt / clay / stone / deepstone by depth)
##   5. deposits    (ore + crystal pockets, root veins, glowcap patches)

var world_seed: int = 0
var spawn_tile_x: int = GameConfig.WORLD_TILES_X / 2

var _n_surface := FastNoiseLite.new()
var _n_surface_detail := FastNoiseLite.new()
var _n_cave_a := FastNoiseLite.new()
var _n_cave_b := FastNoiseLite.new()
var _n_cavern := FastNoiseLite.new()
var _n_strata := FastNoiseLite.new()
var _n_pocket := FastNoiseLite.new()
var _n_root := FastNoiseLite.new()
var _structures: StructureGen

## Cached surface heights, one entry per world column.
var _surface_cache: PackedInt32Array = PackedInt32Array()


func _init(p_seed: int = 0) -> void:
	configure(p_seed)


func configure(p_seed: int) -> void:
	world_seed = p_seed

	_setup(_n_surface, p_seed + 11, FastNoiseLite.TYPE_SIMPLEX, 0.0075)
	_setup(_n_surface_detail, p_seed + 23, FastNoiseLite.TYPE_SIMPLEX, 0.035)

	_setup(_n_cave_a, p_seed + 101, FastNoiseLite.TYPE_PERLIN, 0.028)
	_n_cave_a.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_cave_a.fractal_octaves = 2

	_setup(_n_cave_b, p_seed + 211, FastNoiseLite.TYPE_PERLIN, 0.028)
	_n_cave_b.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_cave_b.fractal_octaves = 2

	_setup(_n_cavern, p_seed + 307, FastNoiseLite.TYPE_SIMPLEX, 0.0105)
	_n_cavern.fractal_octaves = 2

	_setup(_n_strata, p_seed + 419, FastNoiseLite.TYPE_SIMPLEX, 0.022)
	_setup(_n_pocket, p_seed + 523, FastNoiseLite.TYPE_SIMPLEX, 0.075)
	_setup(_n_root, p_seed + 631, FastNoiseLite.TYPE_SIMPLEX, 0.045)
	_n_root.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_root.fractal_octaves = 2

	_structures = StructureGen.new(p_seed)

	# Spawn sits a little off-centre so the world never looks mirrored.
	var h := RngUtil.hash2(p_seed, 7777)
	spawn_tile_x = GameConfig.WORLD_TILES_X / 2 + int(RngUtil.to_unit(h) * 40.0) - 20

	_surface_cache = PackedInt32Array()
	_surface_cache.resize(GameConfig.WORLD_TILES_X)
	for i in GameConfig.WORLD_TILES_X:
		_surface_cache[i] = -1


func _setup(n: FastNoiseLite, s: int, type: int, freq: float) -> void:
	n.seed = s
	n.noise_type = type as FastNoiseLite.NoiseType
	n.frequency = freq
	n.fractal_octaves = 1


# --- Surface -----------------------------------------------------------------

## Topmost solid row for a column. Cached: called constantly by generation,
## spawning and the parallax horizon.
func surface_row(tx: int) -> int:
	if tx < 0 or tx >= GameConfig.WORLD_TILES_X:
		return GameConfig.SURFACE_ROW
	var cached := _surface_cache[tx]
	if cached >= 0:
		return cached
	var base := _n_surface.get_noise_2d(float(tx), 0.0) * 13.0
	var detail := _n_surface_detail.get_noise_2d(float(tx), 0.0) * 3.5
	var row := GameConfig.SURFACE_ROW + int(round(base + detail))
	# Flatten a landing pad around spawn so the player never starts in a pit.
	var d := absi(tx - spawn_tile_x)
	if d < 16:
		var pad := _flat_row()
		var t := 1.0 - float(d) / 16.0
		row = int(round(lerpf(float(row), float(pad), t * t)))
	row = clampi(row, 24, GameConfig.SURFACE_ROW + 30)
	_surface_cache[tx] = row
	return row


func _flat_row() -> int:
	var base := _n_surface.get_noise_2d(float(spawn_tile_x), 0.0) * 13.0
	return clampi(GameConfig.SURFACE_ROW + int(round(base)), 28, GameConfig.SURFACE_ROW + 18)


## World position the player spawns / respawns at.
func spawn_position() -> Vector2:
	var row := surface_row(spawn_tile_x)
	return Vector2(
		float(spawn_tile_x) * GameConfig.TILE_SIZE + GameConfig.TILE_SIZE * 0.5,
		float(row - 3) * GameConfig.TILE_SIZE
	)


# --- Main query --------------------------------------------------------------

func block_at(tx: int, ty: int) -> int:
	if not GameConfig.in_bounds(tx, ty):
		return BlockDB.BEDROCK

	# 1. World shell.
	if tx <= 1 or tx >= GameConfig.WORLD_TILES_X - 2 or ty >= GameConfig.WORLD_TILES_Y - 3:
		return BlockDB.BEDROCK

	var surf := surface_row(tx)
	if ty < surf:
		return _above_surface(tx, ty, surf)

	# 2. Structures win over natural generation.
	var s := _structures.block_at(tx, ty, surf)
	if s != StructureGen.NO_OVERRIDE:
		return s

	var depth := ty - GameConfig.SURFACE_ROW

	# 3. Carved space.
	if _is_cave(tx, ty, depth, surf):
		return _cave_decoration(tx, ty, depth)

	# 4/5. Solid rock, then deposits.
	return _solid_material(tx, ty, depth, surf)


func _above_surface(tx: int, ty: int, surf: int) -> int:
	# Ground cover and low root growth along the skyline. Everything here must
	# be anchored to the column's own surface, never floating: an isolated tile
	# in open sky reads as a rendering bug, not as scenery.
	var height_above := surf - ty
	if height_above <= 0 or height_above > 3:
		return BlockDB.AIR
	if height_above == 1:
		var r := RngUtil.to_unit(RngUtil.hash3(world_seed, tx, 9001))
		if r > 0.80:
			return BlockDB.GLOW_MOSS
	var rr := _n_root.get_noise_2d(float(tx) * 2.2, float(ty) * 1.4)
	# Taller root growth needs root below it, so a clump is always a clump.
	if rr > 0.74:
		if height_above == 1:
			return BlockDB.ROOT
		if _n_root.get_noise_2d(float(tx) * 2.2, float(ty + 1) * 1.4) > 0.74:
			return BlockDB.ROOT
	return BlockDB.AIR


# --- Caves -------------------------------------------------------------------

func _is_cave(tx: int, ty: int, depth: int, surf: int) -> bool:
	# Guaranteed descent: a seeded cave mouth near spawn so the first minute of
	# play always has somewhere obvious to go down.
	if _in_starter_shaft(tx, ty, surf):
		return true

	# No caves in the first few tiles of soil — keeps the surface walkable.
	if ty < surf + 4:
		return false

	var fx := float(tx)
	var fy := float(ty)

	# Tunnel system: the intersection of two perlin fields near zero traces
	# long, winding, connected corridors rather than noise blobs.
	var width := lerpf(0.055, 0.125, clampf(float(depth) / 520.0, 0.0, 1.0))
	var a: float = absf(_n_cave_a.get_noise_2d(fx, fy * 1.45))
	var b: float = absf(_n_cave_b.get_noise_2d(fx, fy * 1.45))
	if a < width and b < width:
		return true

	# Large caverns, only once we are properly underground.
	if depth > 120:
		var cav := _n_cavern.get_noise_2d(fx, fy * 1.25)
		var threshold := lerpf(0.52, 0.30, clampf(float(depth - 120) / 460.0, 0.0, 1.0))
		if cav > threshold:
			return true

	return false


## A sloping tunnel from the surface near spawn down into the first cave layer.
func _in_starter_shaft(tx: int, ty: int, surf: int) -> bool:
	var mouth_x := spawn_tile_x + (20 if (world_seed & 1) == 0 else -20)
	var top := surface_row(mouth_x)
	var bottom := top + 46
	if ty < top - 1 or ty > bottom:
		return false
	var t := float(ty - top) / float(bottom - top)
	# Gentle S-curve so it reads as a natural fissure, not a drilled hole.
	var centre := float(mouth_x) + sin(t * PI * 1.35) * 11.0 + t * 6.0
	var radius := lerpf(2.6, 4.2, t)
	var dist: float = absf(float(tx) - centre)
	if dist > radius:
		return false
	# Do not eat the surface itself more than a mouth's worth.
	if ty < surf:
		return dist < radius * 0.55
	return true


## Non-solid fill for carved space: mostly air, with glowcaps and moss clinging
## to the floor so caves are never visually empty.
func _cave_decoration(tx: int, ty: int, depth: int) -> int:
	# Only decorate tiles that have rock directly beneath them.
	if _is_cave(tx, ty + 1, depth + 1, surface_row(tx)):
		return BlockDB.AIR
	var h := RngUtil.to_unit(RngUtil.hash3(world_seed, tx * 31 + ty, 4421))
	if depth > 90 and h > 0.955:
		return BlockDB.MUSHROOM
	if depth > 40 and h < 0.030:
		return BlockDB.GLOW_MOSS
	return BlockDB.AIR


# --- Strata and deposits -----------------------------------------------------

func _solid_material(tx: int, ty: int, depth: int, surf: int) -> int:
	var below_surface := ty - surf

	# Topsoil.
	if below_surface == 0:
		return BlockDB.GRASS
	if below_surface < 5:
		return BlockDB.DIRT

	var strata := _n_strata.get_noise_2d(float(tx) * 0.8, float(ty) * 1.6)

	# Base rock by depth, with a noisy transition band so layers interlock.
	var base: int = BlockDB.STONE
	if depth < 26:
		base = BlockDB.DIRT if strata > -0.15 else BlockDB.CLAY
	elif depth < 54:
		base = BlockDB.DIRT if strata > 0.34 else BlockDB.STONE
	elif depth < 300:
		base = BlockDB.CLAY if strata > 0.56 else BlockDB.STONE
	elif depth < 340:
		base = BlockDB.STONE if strata > 0.0 else BlockDB.DARK_STONE
	else:
		base = BlockDB.DARK_STONE
		if strata > 0.45:
			base = BlockDB.HARD_ROCK

	# Root veins run through the whole Rootlands column, thickest up high.
	var root_strength := _n_root.get_noise_2d(float(tx) * 1.1, float(ty) * 0.8)
	var root_cut := lerpf(0.62, 0.90, clampf(float(depth) / 420.0, 0.0, 1.0))
	if depth > 6 and root_strength > root_cut:
		return BlockDB.ROOT

	var deposit := _deposit_at(tx, ty, depth)
	if deposit != BlockDB.AIR:
		return deposit

	return base


## Ore / crystal pockets. Clustered by a mid-frequency pocket noise so veins
## read as deliberate deposits, then thinned by a per-tile hash so the inside
## of a vein is still mixed with host rock.
func _deposit_at(tx: int, ty: int, depth: int) -> int:
	if depth < 12:
		return BlockDB.AIR
	var pocket := _n_pocket.get_noise_2d(float(tx) * 1.0, float(ty) * 1.0)
	if pocket < 0.42:
		return BlockDB.AIR
	var density := inverse_lerp(0.42, 1.0, pocket)
	var h := RngUtil.to_unit(RngUtil.hash3(world_seed, tx, ty * 7919))
	if h > density * 0.72:
		return BlockDB.AIR

	# Which ore a pocket yields is decided per-pocket, not per-tile, so you do
	# not get copper and crystal speckled together.
	var pocket_id := RngUtil.hash3(world_seed, tx / 11, ty / 11)
	var roll := RngUtil.to_unit(pocket_id)

	if depth < 100:
		return BlockDB.COPPER_ORE if roll < 0.86 else BlockDB.IRON_ORE
	if depth < 200:
		if roll < 0.46:
			return BlockDB.COPPER_ORE
		if roll < 0.90:
			return BlockDB.IRON_ORE
		return BlockDB.CRYSTAL
	if depth < 400:
		if roll < 0.22:
			return BlockDB.COPPER_ORE
		if roll < 0.60:
			return BlockDB.IRON_ORE
		if roll < 0.95:
			return BlockDB.CRYSTAL
		return BlockDB.DEEP_CRYSTAL
	if roll < 0.30:
		return BlockDB.IRON_ORE
	if roll < 0.72:
		return BlockDB.CRYSTAL
	return BlockDB.DEEP_CRYSTAL


# --- Bulk generation ---------------------------------------------------------

## Fill a chunk's tile ids. `out` must be CHUNK_TILES² bytes.
func generate_chunk(cx: int, cy: int, out: PackedByteArray) -> void:
	var cs := GameConfig.CHUNK_TILES
	var ox := cx * cs
	var oy := cy * cs
	var i := 0
	for ly in cs:
		var ty := oy + ly
		for lx in cs:
			out[i] = block_at(ox + lx, ty)
			i += 1
