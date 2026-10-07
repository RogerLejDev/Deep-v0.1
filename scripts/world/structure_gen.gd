class_name StructureGen
extends RefCounted
## Deterministic structure overlay.
##
## The world is divided into fixed "site cells". Each cell hashes to at most one
## structure, so `block_at` can answer for any tile without generating
## neighbours first — which is what keeps chunk streaming order-independent.
##
## Adding a structure type = one entry in `_site_kind` plus one `_carve_*`.

## Sentinel meaning "generation should continue normally here".
const NO_OVERRIDE: int = -1

const SITE: int = 48

const KIND_NONE: int = 0
const KIND_ROOT_HOLLOW: int = 1
const KIND_CRYSTAL_CHAMBER: int = 2
const KIND_ANCIENT_VAULT: int = 3

var world_seed: int = 0

## Vector2i cell -> [kind, centre]. Deciding a cell costs several hashes, and
## every tile used to re-decide the nine cells around it. Caching turns chunk
## generation from thousands of hashes into a few dozen.
var _cells: Dictionary = {}


func _init(p_seed: int) -> void:
	world_seed = p_seed


func block_at(tx: int, ty: int, surf: int) -> int:
	# Check the owning cell plus neighbours, since a structure may overhang.
	var cx := floori(float(tx) / SITE)
	var cy := floori(float(ty) / SITE)
	for ny in range(cy - 1, cy + 2):
		for nx in range(cx - 1, cx + 2):
			var r := _query_site(nx, ny, tx, ty, surf)
			if r != NO_OVERRIDE:
				return r
	return NO_OVERRIDE


## Cached {kind, centre} for one site cell.
func _cell(cx: int, cy: int) -> Array:
	var key := Vector2i(cx, cy)
	var hit = _cells.get(key)
	if hit != null:
		return hit
	var kind := _site_kind(cx, cy)
	var entry: Array = [kind, _site_centre(cx, cy) if kind != KIND_NONE else Vector2i.ZERO]
	_cells[key] = entry
	return entry


func _site_kind(cx: int, cy: int) -> int:
	var depth := cy * SITE - GameConfig.SURFACE_ROW
	var h := RngUtil.hash3(world_seed, cx, cy * 5701)
	var roll := RngUtil.to_unit(h)
	if depth < 24:
		return KIND_NONE
	if depth < 140:
		return KIND_ROOT_HOLLOW if roll < 0.34 else KIND_NONE
	if depth < 420:
		if roll < 0.26:
			return KIND_CRYSTAL_CHAMBER
		return KIND_ROOT_HOLLOW if roll < 0.40 else KIND_NONE
	if roll < 0.30:
		return KIND_ANCIENT_VAULT
	return KIND_CRYSTAL_CHAMBER if roll < 0.52 else KIND_NONE


func _site_centre(cx: int, cy: int) -> Vector2i:
	var hx := RngUtil.hash3(world_seed, cx * 131, cy * 17)
	var hy := RngUtil.hash3(world_seed, cx * 29, cy * 719)
	return Vector2i(
		cx * SITE + RngUtil.range_int(hx, 12, SITE - 12),
		cy * SITE + RngUtil.range_int(hy, 12, SITE - 12)
	)


func _query_site(cx: int, cy: int, tx: int, ty: int, surf: int) -> int:
	var entry := _cell(cx, cy)
	var kind: int = entry[0]
	if kind == KIND_NONE:
		return NO_OVERRIDE
	var centre: Vector2i = entry[1]
	# Cheap rejection before any carve maths: every structure fits inside this
	# radius of its centre.
	if absi(tx - centre.x) > 26 or absi(ty - centre.y) > 20:
		return NO_OVERRIDE
	# Never punch a structure through the surface.
	if centre.y < surf + 16:
		return NO_OVERRIDE
	match kind:
		KIND_ROOT_HOLLOW:
			return _carve_root_hollow(cx, cy, centre, tx, ty)
		KIND_CRYSTAL_CHAMBER:
			return _carve_crystal_chamber(cx, cy, centre, tx, ty)
		KIND_ANCIENT_VAULT:
			return _carve_ancient_vault(cx, cy, centre, tx, ty)
	return NO_OVERRIDE


## A pocket wrapped in a cage of living root, with glowcaps on the floor.
func _carve_root_hollow(cx: int, cy: int, c: Vector2i, tx: int, ty: int) -> int:
	var h := RngUtil.hash3(world_seed, cx + 51, cy + 83)
	var rx := 7.0 + RngUtil.to_unit(h) * 5.0
	var ry := 5.0 + RngUtil.to_unit(RngUtil.mix(h)) * 3.0
	var d := _ellipse(tx, ty, c, rx, ry)
	# Wobble the rim so it is not a clean oval.
	var wob := RngUtil.to_signed(RngUtil.hash3(world_seed, tx * 13, ty * 7)) * 0.10
	d += wob
	if d > 1.18:
		return NO_OVERRIDE
	if d > 0.96:
		return BlockDB.ROOT
	if d > 0.88:
		return BlockDB.DIRT
	# Interior: air, with a floor fringe.
	if _ellipse(tx, ty + 1, c, rx, ry) + wob > 0.96:
		var r := RngUtil.to_unit(RngUtil.hash3(world_seed, tx * 3, ty * 29))
		if r > 0.62:
			return BlockDB.MUSHROOM
		if r > 0.40:
			return BlockDB.GLOW_MOSS
	return BlockDB.AIR


## Open chamber lined with lumen crystal — the first real "wow" landmark.
func _carve_crystal_chamber(cx: int, cy: int, c: Vector2i, tx: int, ty: int) -> int:
	var h := RngUtil.hash3(world_seed, cx + 907, cy + 211)
	var rx := 9.0 + RngUtil.to_unit(h) * 7.0
	var ry := 7.0 + RngUtil.to_unit(RngUtil.mix(h)) * 5.0
	var wob := RngUtil.to_signed(RngUtil.hash3(world_seed, tx * 19, ty * 11)) * 0.12
	var d := _ellipse(tx, ty, c, rx, ry) + wob
	if d > 1.22:
		return NO_OVERRIDE
	if d > 1.02:
		return BlockDB.DARK_STONE
	if d > 0.90:
		var deep := (ty - GameConfig.SURFACE_ROW) > 380
		var r := RngUtil.to_unit(RngUtil.hash3(world_seed, tx * 7, ty * 23))
		if r > 0.45:
			return BlockDB.DEEP_CRYSTAL if (deep and r > 0.86) else BlockDB.CRYSTAL
		return BlockDB.STONE
	return BlockDB.AIR


## A rectangular ruin: evidence that something built down here first.
func _carve_ancient_vault(cx: int, cy: int, c: Vector2i, tx: int, ty: int) -> int:
	var h := RngUtil.hash3(world_seed, cx + 3301, cy + 1709)
	var hw := 8 + RngUtil.range_int(h, 0, 5)
	var hh := 5 + RngUtil.range_int(RngUtil.mix(h), 0, 3)
	var dx := tx - c.x
	var dy := ty - c.y
	if absi(dx) > hw + 1 or absi(dy) > hh + 1:
		return NO_OVERRIDE
	# Outer shell.
	if absi(dx) > hw or absi(dy) > hh:
		return BlockDB.ANCIENT_STONE
	# Interior pillars every 5 tiles.
	if absi(dy) < hh and (dx + hw) % 5 == 0 and absi(dy) > hh - 4:
		return BlockDB.ANCIENT_STONE
	# A seam of deep crystal embedded in the back wall.
	if dy == -hh + 1 and absi(dx) < 3:
		return BlockDB.DEEP_CRYSTAL
	return BlockDB.AIR


static func _ellipse(tx: int, ty: int, c: Vector2i, rx: float, ry: float) -> float:
	var dx := (float(tx) - float(c.x)) / rx
	var dy := (float(ty) - float(c.y)) / ry
	return sqrt(dx * dx + dy * dy)


## Structure sites near a point, for the map / debug overlay.
func sites_near(tile: Vector2i, cells: int = 2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cx := floori(float(tile.x) / SITE)
	var cy := floori(float(tile.y) / SITE)
	for ny in range(cy - cells, cy + cells + 1):
		for nx in range(cx - cells, cx + cells + 1):
			var entry := _cell(nx, ny)
			if int(entry[0]) == KIND_NONE:
				continue
			out.append({"kind": int(entry[0]), "centre": entry[1] as Vector2i})
	return out
