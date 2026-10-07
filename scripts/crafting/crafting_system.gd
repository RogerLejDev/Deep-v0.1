class_name CraftingSystem
extends RefCounted
## Stateless rules layer over Inventory + RecipeDB.

enum Result { OK, MISSING_INPUTS, WRONG_STATION, NO_ROOM, UNKNOWN_RECIPE }


static func can_craft(inv: Inventory, recipe: RecipeDB.Recipe, station: String) -> int:
	if recipe == null:
		return Result.UNKNOWN_RECIPE
	if not recipe.station.is_empty() and recipe.station != station:
		return Result.WRONG_STATION
	for entry in recipe.input_list():
		if not inv.has(str(entry["id"]), int(entry["n"])):
			return Result.MISSING_INPUTS
	# Refuse rather than destroy inputs when the pack cannot hold the output.
	if inv.is_full() and inv.count(recipe.output_id) == 0:
		return Result.NO_ROOM
	return Result.OK


static func craft(inv: Inventory, recipe: RecipeDB.Recipe, station: String) -> int:
	var check := can_craft(inv, recipe, station)
	if check != Result.OK:
		EventBus.craft_failed.emit(reason_text(check))
		return check
	for entry in recipe.input_list():
		inv.remove(str(entry["id"]), int(entry["n"]))
	var leftover := inv.add(recipe.output_id, recipe.output_count)
	EventBus.item_crafted.emit(recipe.output_id, recipe.output_count - leftover)
	return Result.OK


static func reason_text(result: int) -> String:
	match result:
		Result.MISSING_INPUTS: return "NOT ENOUGH MATERIALS"
		Result.WRONG_STATION: return "REQUIRES A WORKBENCH"
		Result.NO_ROOM: return "PACK IS FULL"
		Result.UNKNOWN_RECIPE: return "UNKNOWN RECIPE"
	return "OK"


## Best tool in the pack, by mining power. Used to auto-equip after crafting.
static func best_tool(inv: Inventory) -> String:
	var best := ""
	var best_power := -1.0
	for i in inv.slots.size():
		var id := inv.item_at(i)
		if id.is_empty():
			continue
		var def := ItemDB.get_item(id)
		if not def.is_tool():
			continue
		if def.tool_power > best_power:
			best_power = def.tool_power
			best = id
	return best
