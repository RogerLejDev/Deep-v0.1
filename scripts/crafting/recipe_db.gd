class_name RecipeDB
extends RefCounted
## Static recipe list. `station` gates where a recipe can be used:
##   ""           anywhere, by hand
##   "workbench"  only at the base camp bench
##
## Adding a recipe is one `_add` call. Nothing else needs to change.

class Recipe extends RefCounted:
	var id: String = ""
	var output_id: String = ""
	var output_count: int = 1
	## item_id -> amount
	var inputs: Dictionary = {}
	var station: String = ""
	var category: String = "misc"
	## Shown in the crafting panel to explain *why* you want this.
	var unlock_note: String = ""

	func _init(p_id: String, p_out: String, p_n: int) -> void:
		id = p_id
		output_id = p_out
		output_count = p_n

	func input_list() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for k: String in inputs.keys():
			out.append({"id": k, "n": int(inputs[k])})
		return out


static var _recipes: Array[Recipe] = []


static func _ensure() -> void:
	if not _recipes.is_empty():
		return

	_add("plank", "plank", 2, {"root_fibre": 2}, "", "building",
		"Platforms and bridges. Place them to cross a shaft.")
	_add("torch", "torch", 3, {"root_fibre": 1, "glowcap": 1}, "", "light",
		"Leave a trail of light. You will want it on the way back up.")
	_add("salve", "salve", 2, {"glowcap": 2, "root_fibre": 1}, "", "survival",
		"Field medicine. Craftable without a bench.")

	_add("pick_copper", "pick_copper", 1,
		{"copper_ore": 8, "root_fibre": 4}, "workbench", "tools",
		"Roughly double your dig speed. Stone stops being a barrier.")
	_add("pick_iron", "pick_iron", 1,
		{"iron_ore": 10, "copper_ore": 2, "plank": 4}, "workbench", "tools",
		"Cuts deepstone. Required to pass 150 m.")
	_add("pick_crystal", "pick_crystal", 1,
		{"crystal_shard": 8, "iron_ore": 6, "deep_crystal_shard": 2}, "workbench", "tools",
		"Cuts compressed rock and ancient masonry.")

	_add("lantern", "lantern", 1,
		{"crystal_shard": 4, "copper_ore": 6, "root_fibre": 2}, "workbench", "gear",
		"Permanent light upgrade. The single biggest change to how deep you can go.")
	_add("lumen_flask", "lumen_flask", 2,
		{"glowcap": 3, "crystal_shard": 2}, "workbench", "light",
		"45 seconds of doubled light. For crossing one bad room.")


static func _add(
	id: String,
	out_id: String,
	out_n: int,
	inputs: Dictionary,
	station: String,
	category: String,
	note: String
) -> Recipe:
	var r := Recipe.new(id, out_id, out_n)
	r.inputs = inputs
	r.station = station
	r.category = category
	r.unlock_note = note
	_recipes.append(r)
	return r


static func all() -> Array[Recipe]:
	_ensure()
	return _recipes


static func for_station(station: String) -> Array[Recipe]:
	_ensure()
	var out: Array[Recipe] = []
	for r in _recipes:
		# A station can always do hand recipes too.
		if r.station.is_empty() or r.station == station:
			out.append(r)
	return out


static func by_id(id: String) -> Recipe:
	_ensure()
	for r in _recipes:
		if r.id == id:
			return r
	return null
