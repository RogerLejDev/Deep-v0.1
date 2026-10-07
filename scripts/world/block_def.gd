class_name BlockDef
extends RefCounted
## One terrain material. Pure data — see BlockDB for the registry.

var id: int = 0
var key: String = "air"
var display_name: String = "Air"
## Base albedo. The terrain shader perturbs this per tile so no two tiles
## of the same material read identically.
var colour: Color = Color(0, 0, 0, 0)
## How far per-tile hue/value jitter may wander from `colour`.
var colour_variance: float = 0.11
## Secondary colour used for speckles / veins inside the material.
var speckle: Color = Color(0, 0, 0, 0)
var speckle_amount: float = 0.0
## Seconds to break with a tool of power 1.0.
var hardness: float = 1.0
## Minimum tool tier able to damage this at all. 0 = starter pickaxe.
var required_tier: int = 0
var drop_item: String = ""
var drop_min: int = 1
var drop_max: int = 1
## 0 = unlit, 1 = full bioluminescent glow. Drives both shader emission and
## whether a chunk spawns a PointLight2D for this tile.
var emission: float = 0.0
var emission_colour: Color = Color(1, 1, 1)
var solid: bool = true
var placeable: bool = false
## Organic materials get a soft, fibrous shader treatment instead of rock.
var organic: bool = false
## Crystalline materials get faceted highlights and sparkle.
var crystalline: bool = false
var unbreakable: bool = false


func _init(
	p_id: int = 0,
	p_key: String = "air",
	p_name: String = "Air"
) -> void:
	id = p_id
	key = p_key
	display_name = p_name


func is_minable_with(tier: int) -> bool:
	return not unbreakable and tier >= required_tier


func break_seconds(tool_power: float) -> float:
	if unbreakable or tool_power <= 0.0:
		return INF
	return hardness / tool_power
