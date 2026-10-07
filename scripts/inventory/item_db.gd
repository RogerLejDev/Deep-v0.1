class_name ItemDB
extends RefCounted
## Static item registry. One `_add` line per item; icons are derived from the
## shape + palette fields, so a new resource needs no art pipeline.

static var _items: Dictionary = {}
static var _order: Array[String] = []


static func _ensure() -> void:
	if not _items.is_empty():
		return

	# --- raw materials -------------------------------------------------------
	var dirt := _add("dirt_clod", "Dirt Clod", ItemDef.Category.RESOURCE,
		"Loose topsoil, still smelling of the surface.",
		"clod", Color(0.42, 0.31, 0.21), Color(0.26, 0.19, 0.13))
	dirt.place_block = BlockDB.DIRT

	var clay := _add("clay_lump", "Clay Lump", ItemDef.Category.RESOURCE,
		"Cold, grey, and holds a shape.",
		"clod", Color(0.49, 0.46, 0.43), Color(0.30, 0.28, 0.26))
	clay.place_block = BlockDB.CLAY

	var stone := _add("stone_chunk", "Stone Chunk", ItemDef.Category.RESOURCE,
		"Common rock. Useful for closing a hole behind you.",
		"clod", Color(0.36, 0.38, 0.44), Color(0.20, 0.21, 0.26))
	stone.place_block = BlockDB.STONE

	_add("root_fibre", "Root Fibre", ItemDef.Category.RESOURCE,
		"Tough strands from a root that is still, faintly, warm.",
		"fibre", Color(0.52, 0.40, 0.24), Color(0.30, 0.22, 0.14))

	_add("copper_ore", "Copper Ore", ItemDef.Category.RESOURCE,
		"Dull green crust over bright metal.",
		"ore", Color(0.78, 0.46, 0.25), Color(0.32, 0.45, 0.33))

	_add("iron_ore", "Iron Ore", ItemDef.Category.RESOURCE,
		"Heavy, grey, and worth the extra weight.",
		"ore", Color(0.74, 0.77, 0.80), Color(0.28, 0.30, 0.34))

	var shard := _add("crystal_shard", "Lumen Shard", ItemDef.Category.RESOURCE,
		"It keeps glowing in your pack. Nobody knows why.",
		"shard", Color(0.47, 0.85, 0.95), Color(0.14, 0.34, 0.45))
	shard.icon_glow = Color(0.42, 0.82, 1.0)

	var deep_shard := _add("deep_crystal_shard", "Abyssal Shard", ItemDef.Category.RESOURCE,
		"Cold to hold. The light inside it moves on its own.",
		"shard", Color(0.72, 0.54, 1.0), Color(0.24, 0.15, 0.40))
	deep_shard.icon_glow = Color(0.68, 0.45, 1.0)

	var cap := _add("glowcap", "Glowcap", ItemDef.Category.RESOURCE,
		"Bioluminescent flesh. Bitter, but it closes wounds.",
		"cap", Color(0.82, 0.57, 0.92), Color(0.34, 0.22, 0.38))
	cap.icon_glow = Color(0.85, 0.52, 0.95)

	var relic := _add("ancient_fragment", "Ancient Fragment", ItemDef.Category.RESOURCE,
		"Worked stone. Someone cut this, a very long time ago.",
		"relic", Color(0.42, 0.56, 0.54), Color(0.16, 0.22, 0.22))
	relic.icon_glow = Color(0.35, 0.86, 0.78)

	# --- tools ---------------------------------------------------------------
	var p0 := _add("pick_starter", "Scrap Pick", ItemDef.Category.TOOL,
		"Barely a tool. It will get you through soil, slowly.",
		"pick", Color(0.52, 0.42, 0.30), Color(0.30, 0.24, 0.18))
	p0.stack_size = 1
	p0.tool_power = 0.80
	p0.tool_tier = 0
	p0.tool_damage = 4.0

	var p1 := _add("pick_copper", "Copper Pick", ItemDef.Category.TOOL,
		"Twice the bite. Stone stops being a wall and becomes a floor.",
		"pick", Color(0.80, 0.48, 0.26), Color(0.34, 0.22, 0.14))
	p1.stack_size = 1
	p1.tool_power = 1.55
	p1.tool_tier = 1
	p1.tool_damage = 7.0

	var p2 := _add("pick_iron", "Iron Pick", ItemDef.Category.TOOL,
		"Cuts deepstone and iron. The deep strata open up.",
		"pick", Color(0.76, 0.79, 0.83), Color(0.26, 0.28, 0.33))
	p2.stack_size = 1
	p2.tool_power = 2.45
	p2.tool_tier = 2
	p2.tool_damage = 11.0

	var p3 := _add("pick_crystal", "Lumen Pick", ItemDef.Category.TOOL,
		"Compressed rock yields. So does whatever the ancients sealed.",
		"pick", Color(0.52, 0.88, 0.97), Color(0.16, 0.36, 0.47))
	p3.stack_size = 1
	p3.tool_power = 3.70
	p3.tool_tier = 3
	p3.tool_damage = 16.0
	p3.icon_glow = Color(0.42, 0.82, 1.0)

	# --- placeables ----------------------------------------------------------
	var plank := _add("plank", "Root Plank", ItemDef.Category.PLACEABLE,
		"A board of pressed fibre. Bridges, platforms, shelter.",
		"plank", Color(0.52, 0.38, 0.25), Color(0.30, 0.21, 0.14))
	plank.place_block = BlockDB.PLANK

	var torch := _add("torch", "Torch", ItemDef.Category.PLACEABLE,
		"Light you can leave behind. The only way to find your way back.",
		"torch", Color(0.92, 0.66, 0.32), Color(0.38, 0.26, 0.16))
	torch.place_block = BlockDB.TORCH
	torch.icon_glow = Color(1.0, 0.72, 0.38)

	# --- consumables ---------------------------------------------------------
	var salve := _add("salve", "Glowcap Salve", ItemDef.Category.CONSUMABLE,
		"Restores 40 vitality. Tastes like wet stone.",
		"flask", Color(0.62, 0.88, 0.56), Color(0.20, 0.34, 0.22))
	salve.heal = 40.0
	salve.stack_size = 20
	salve.icon_glow = Color(0.52, 0.95, 0.60)

	var flask := _add("lumen_flask", "Lumen Flask", ItemDef.Category.CONSUMABLE,
		"Burns bright for 45 seconds. Doubles your lantern's reach.",
		"flask", Color(0.56, 0.86, 0.98), Color(0.16, 0.34, 0.46))
	flask.effect_seconds = 45.0
	flask.stack_size = 10
	flask.icon_glow = Color(0.42, 0.82, 1.0)

	# --- gear ----------------------------------------------------------------
	var lantern := _add("lantern", "Deep Lantern", ItemDef.Category.GEAR,
		"A caged shard on a hook. Permanently widens your light.",
		"lantern", Color(0.84, 0.72, 0.46), Color(0.28, 0.24, 0.18))
	lantern.stack_size = 1
	lantern.light_radius = 95.0
	lantern.light_colour = Color(1.0, 0.86, 0.62)
	lantern.icon_glow = Color(1.0, 0.82, 0.50)


static func _add(
	id: String,
	name: String,
	cat: int,
	desc: String,
	shape: String,
	primary: Color,
	secondary: Color
) -> ItemDef:
	var d := ItemDef.new(id, name, cat)
	d.description = desc
	d.icon_shape = shape
	d.icon_primary = primary
	d.icon_secondary = secondary
	_items[id] = d
	_order.append(id)
	return d


static func get_item(id: String) -> ItemDef:
	_ensure()
	if _items.has(id):
		return _items[id]
	return ItemDef.new(id, id.capitalize())


static func has(id: String) -> bool:
	_ensure()
	return _items.has(id)


static func ids() -> Array[String]:
	_ensure()
	return _order


static func all_tools() -> Array[ItemDef]:
	_ensure()
	var out: Array[ItemDef] = []
	for id in _order:
		var d: ItemDef = _items[id]
		if d.is_tool():
			out.append(d)
	return out
