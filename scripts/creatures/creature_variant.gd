class_name CreatureVariant
extends RefCounted
## One visual/statistical variant of a species.
##
## A variant never gets its own art or its own script: it is a recolour plus a
## set of multipliers. That is deliberate — it means a species can ship six
## variants for the cost of six JSON objects, and the Codex can show them all
## as separate collectibles.

var id: String = "normal"
var display_name: String = ""
## Relative chance within the species. Not a percentage; weights are summed.
var weight: float = 100.0
var note: String = ""
## Flagged variants get the rare-sighting flourish instead of a plain toast.
var rare: bool = false
var legendary: bool = false

# --- Recolour ----------------------------------------------------------------
var hue_shift: float = 0.0
var saturation: float = 1.0
var value: float = 1.0
var overlay: Color = Color(0, 0, 0, 0)

# --- Multipliers -------------------------------------------------------------
var scale_mul: float = 1.0
var hp_mul: float = 1.0
var speed_mul: float = 1.0
var damage_mul: float = 1.0
var emission_mul: float = 1.0
## Extra loot rolls on death.
var loot_bonus: int = 0


static func from_dict(d: Dictionary) -> CreatureVariant:
	var v := CreatureVariant.new()
	v.id = str(d.get("id", "normal"))
	v.display_name = str(d.get("display_name", v.id.capitalize()))
	v.weight = float(d.get("weight", 100.0))
	v.note = str(d.get("note", ""))
	v.rare = bool(d.get("rare", false))
	v.legendary = bool(d.get("legendary", false))
	v.hue_shift = float(d.get("hue_shift", 0.0))
	v.saturation = float(d.get("saturation", 1.0))
	v.value = float(d.get("value", 1.0))
	var ov = d.get("overlay", null)
	if ov is Array and (ov as Array).size() >= 4:
		v.overlay = Color(float(ov[0]), float(ov[1]), float(ov[2]), float(ov[3]))
	v.scale_mul = float(d.get("scale_mul", 1.0))
	v.hp_mul = float(d.get("hp_mul", 1.0))
	v.speed_mul = float(d.get("speed_mul", 1.0))
	v.damage_mul = float(d.get("damage_mul", 1.0))
	v.emission_mul = float(d.get("emission_mul", 1.0))
	v.loot_bonus = int(d.get("loot_bonus", 0))
	return v


func is_special() -> bool:
	return rare or legendary
