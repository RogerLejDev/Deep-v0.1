class_name BlockDB
extends RefCounted
## Static registry of terrain materials, built once and shared.
##
## Adding a material means adding one `_def(...)` line here plus (optionally)
## a worldgen rule. Nothing else in the codebase hardcodes a block id except
## the AIR / BEDROCK sentinels below.

const AIR: int = 0
const DIRT: int = 1
const GRASS: int = 2
const CLAY: int = 3
const ROOT: int = 4
const STONE: int = 5
const DARK_STONE: int = 6
const HARD_ROCK: int = 7
const COPPER_ORE: int = 8
const IRON_ORE: int = 9
const CRYSTAL: int = 10
const DEEP_CRYSTAL: int = 11
const MUSHROOM: int = 12
const ANCIENT_STONE: int = 13
const BEDROCK: int = 14
const PLANK: int = 15
const TORCH: int = 16
const GLOW_MOSS: int = 17

const COUNT: int = 18

static var _defs: Array[BlockDef] = []
static var _by_key: Dictionary = {}


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	_defs.resize(COUNT)

	var air := _def(AIR, "air", "Air", Color(0, 0, 0, 0), 0.0, 0)
	air.solid = false

	_def(DIRT, "dirt", "Packed Dirt", Color(0.337, 0.243, 0.169), 0.28, 0,
		"dirt_clod", Color(0.42, 0.31, 0.21), 0.30)
	var grass := _def(GRASS, "grass", "Rooted Soil", Color(0.247, 0.329, 0.196), 0.30, 0,
		"dirt_clod", Color(0.36, 0.47, 0.25), 0.34)
	grass.organic = true
	_def(CLAY, "clay", "Grey Clay", Color(0.388, 0.361, 0.333), 0.42, 0,
		"clay_lump", Color(0.46, 0.43, 0.40), 0.22)

	var root := _def(ROOT, "root", "Living Root", Color(0.278, 0.204, 0.157), 0.52, 0,
		"root_fibre", Color(0.42, 0.33, 0.22), 0.45)
	root.organic = true
	root.colour_variance = 0.16
	root.emission = 0.04
	root.emission_colour = Color(0.55, 0.78, 0.45)

	_def(STONE, "stone", "Stone", Color(0.251, 0.267, 0.306), 0.85, 0,
		"stone_chunk", Color(0.32, 0.34, 0.39), 0.26)
	_def(DARK_STONE, "dark_stone", "Deepstone", Color(0.157, 0.169, 0.212), 1.30, 1,
		"stone_chunk", Color(0.22, 0.24, 0.30), 0.30)

	var hard := _def(HARD_ROCK, "hard_rock", "Compressed Rock", Color(0.173, 0.192, 0.224), 2.60, 2,
		"stone_chunk", Color(0.30, 0.33, 0.38), 0.40)
	hard.drop_max = 2

	var copper := _def(COPPER_ORE, "copper_ore", "Copper Vein", Color(0.286, 0.278, 0.290), 1.10, 0,
		"copper_ore", Color(0.776, 0.455, 0.247), 0.55)
	copper.emission = 0.06
	copper.emission_colour = Color(1.0, 0.62, 0.34)

	var iron := _def(IRON_ORE, "iron_ore", "Iron Vein", Color(0.263, 0.271, 0.298), 1.60, 1,
		"iron_ore", Color(0.733, 0.757, 0.788), 0.50)
	iron.emission = 0.03
	iron.emission_colour = Color(0.78, 0.84, 0.92)

	var crystal := _def(CRYSTAL, "crystal", "Lumen Crystal", Color(0.251, 0.471, 0.573), 2.10, 1,
		"crystal_shard", Color(0.47, 0.85, 0.95), 0.60)
	crystal.emission = 0.85
	crystal.emission_colour = Color(0.42, 0.82, 1.0)
	crystal.crystalline = true
	crystal.drop_max = 2

	var deep_crystal := _def(DEEP_CRYSTAL, "deep_crystal", "Abyssal Crystal", Color(0.361, 0.263, 0.549), 3.00, 2,
		"deep_crystal_shard", Color(0.70, 0.52, 1.0), 0.62)
	deep_crystal.emission = 1.0
	deep_crystal.emission_colour = Color(0.68, 0.45, 1.0)
	deep_crystal.crystalline = true
	deep_crystal.drop_max = 2

	var mush := _def(MUSHROOM, "mushroom", "Glowcap Flesh", Color(0.329, 0.259, 0.325), 0.34, 0,
		"glowcap", Color(0.78, 0.55, 0.90), 0.45)
	mush.emission = 0.55
	mush.emission_colour = Color(0.85, 0.52, 0.95)
	mush.organic = true

	var ancient := _def(ANCIENT_STONE, "ancient_stone", "Ancient Masonry", Color(0.216, 0.235, 0.247), 4.00, 3,
		"ancient_fragment", Color(0.35, 0.47, 0.46), 0.42)
	ancient.emission = 0.18
	ancient.emission_colour = Color(0.35, 0.86, 0.78)

	var bedrock := _def(BEDROCK, "bedrock", "World Shell", Color(0.082, 0.090, 0.110), 999.0, 9)
	bedrock.unbreakable = true
	bedrock.colour_variance = 0.06

	var plank := _def(PLANK, "plank", "Root Plank", Color(0.420, 0.302, 0.196), 0.30, 0,
		"plank", Color(0.52, 0.38, 0.25), 0.35)
	plank.placeable = true
	plank.organic = true

	var torch := _def(TORCH, "torch", "Torch", Color(0.90, 0.62, 0.30), 0.08, 0, "torch")
	torch.solid = false
	torch.placeable = true
	torch.emission = 1.0
	torch.emission_colour = Color(1.0, 0.72, 0.38)

	var moss := _def(GLOW_MOSS, "glow_moss", "Lumen Moss", Color(0.34, 0.64, 0.52), 0.10, 0, "glowcap")
	moss.solid = false
	moss.organic = true
	moss.emission = 0.6
	moss.emission_colour = Color(0.46, 0.95, 0.72)


static func _def(
	id: int,
	key: String,
	name: String,
	colour: Color = Color(0, 0, 0, 0),
	hardness: float = 1.0,
	tier: int = 0,
	drop: String = "",
	speckle: Color = Color(0, 0, 0, 0),
	speckle_amount: float = 0.0
) -> BlockDef:
	var d := BlockDef.new(id, key, name)
	d.colour = colour
	d.hardness = hardness
	d.required_tier = tier
	d.drop_item = drop
	d.speckle = speckle
	d.speckle_amount = speckle_amount
	_defs[id] = d
	_by_key[key] = d
	return d


static func get_block(id: int) -> BlockDef:
	_ensure()
	if id < 0 or id >= _defs.size():
		return _defs[AIR]
	return _defs[id]


static func by_key(key: String) -> BlockDef:
	_ensure()
	return _by_key.get(key, _defs[AIR])


static func all() -> Array[BlockDef]:
	_ensure()
	return _defs


static func is_solid(id: int) -> bool:
	return get_block(id).solid


static func is_air(id: int) -> bool:
	return id == AIR


## Packed lookup table the terrain shader needs: one row per material.
## Returned as an ImageTexture so the shader can index it by material id.
static func build_palette_texture() -> ImageTexture:
	_ensure()
	var img := Image.create(COUNT, 3, false, Image.FORMAT_RGBAF)
	for i in COUNT:
		var d: BlockDef = _defs[i]
		img.set_pixel(i, 0, Color(d.colour.r, d.colour.g, d.colour.b, d.colour_variance))
		img.set_pixel(i, 1, Color(d.speckle.r, d.speckle.g, d.speckle.b, d.speckle_amount))
		var flags := 0.0
		if d.organic:
			flags += 1.0
		if d.crystalline:
			flags += 2.0
		img.set_pixel(i, 2, Color(
			d.emission_colour.r * d.emission,
			d.emission_colour.g * d.emission,
			d.emission_colour.b * d.emission,
			flags
		))
	return ImageTexture.create_from_image(img)
