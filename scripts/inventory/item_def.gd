class_name ItemDef
extends RefCounted
## One inventory item. Pure data; ItemDB is the registry.

enum Category { RESOURCE, TOOL, PLACEABLE, CONSUMABLE, GEAR }

var id: String = ""
var display_name: String = ""
var category: int = Category.RESOURCE
var description: String = ""
var stack_size: int = 999
## Icon generation: shape family + palette, rasterised from SVG at runtime.
var icon_shape: String = "clod"
var icon_primary: Color = Color(0.6, 0.6, 0.6)
var icon_secondary: Color = Color(0.3, 0.3, 0.3)
var icon_glow: Color = Color(0, 0, 0, 0)

# --- Tools -------------------------------------------------------------------
## Mining speed multiplier. Block break time = hardness / power.
var tool_power: float = 0.0
## Highest block tier this tool can damage at all.
var tool_tier: int = -1
## Melee damage when swung at a creature.
var tool_damage: float = 0.0

# --- Placeables --------------------------------------------------------------
var place_block: int = -1

# --- Consumables / gear ------------------------------------------------------
var heal: float = 0.0
## Seconds of effect, for timed consumables.
var effect_seconds: float = 0.0
## Permanent lantern radius bonus in pixels, for GEAR.
var light_radius: float = 0.0
var light_colour: Color = Color(1, 1, 1)


func _init(p_id: String = "", p_name: String = "", p_cat: int = Category.RESOURCE) -> void:
	id = p_id
	display_name = p_name
	category = p_cat


func is_tool() -> bool:
	return category == Category.TOOL


func is_placeable() -> bool:
	return place_block >= 0


func category_name() -> String:
	match category:
		Category.RESOURCE: return "RESOURCE"
		Category.TOOL: return "TOOL"
		Category.PLACEABLE: return "PLACEABLE"
		Category.CONSUMABLE: return "CONSUMABLE"
		Category.GEAR: return "GEAR"
	return "ITEM"
