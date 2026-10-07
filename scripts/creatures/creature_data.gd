class_name CreatureData
extends RefCounted
## A species, loaded from data/creatures/<id>.json.
##
## Behaviour is named, not scripted: `behaviour` selects one of the profiles in
## CreatureBrain. Adding a species therefore needs a JSON file and an SVG, and
## only needs new code if it wants a behaviour that does not exist yet.

enum Rarity { COMMON, UNCOMMON, RARE, VERY_RARE, LEGENDARY }

var id: String = ""
var codex_number: int = 0
var display_name: String = ""
var art_path: String = ""
## On-screen height in world pixels.
var size_px: int = 20
var rarity: int = Rarity.COMMON
var behaviour: String = "wander"

# --- Stats -------------------------------------------------------------------
var hp: float = 20.0
var speed: float = 60.0
var damage: float = 0.0
var jump_velocity: float = 0.0

# --- Senses ------------------------------------------------------------------
var flee_range: float = 0.0
var aggro_range: float = 0.0
var wander_range: float = 160.0

# --- Spawning ----------------------------------------------------------------
var depth_min: float = -999.0
var depth_max: float = 999.0
var spawn_weight: float = 1.0
var biomes: Array[String] = []
var needs_floor: bool = true
var floats: bool = false
var group_min: int = 1
var group_max: int = 1
var night_only: bool = false
var requires_darkness: bool = false
## Spawn only within `near_block_radius` tiles of this block id (-1 = ignore).
var near_block: int = -1
var near_block_radius: int = 6
## Non-empty means this species only appears through a named rare event.
var legendary_event: String = ""

# --- Light -------------------------------------------------------------------
var light_colour: Color = Color.WHITE
var light_radius: float = 0.0
var light_intensity: float = 0.0

# --- Loot / codex ------------------------------------------------------------
var loot: Array[Dictionary] = []
var codex_text: Dictionary = {}
var variants: Array[CreatureVariant] = []


static func from_dict(d: Dictionary) -> CreatureData:
	var c := CreatureData.new()
	c.id = str(d.get("id", ""))
	c.codex_number = int(d.get("codex_number", 0))
	c.display_name = str(d.get("display_name", c.id.capitalize()))
	c.art_path = str(d.get("art", ""))
	c.size_px = int(d.get("size_px", 20))
	c.rarity = _parse_rarity(str(d.get("rarity", "common")))
	c.behaviour = str(d.get("behaviour", "wander"))

	var st: Dictionary = d.get("stats", {})
	c.hp = float(st.get("hp", 20.0))
	c.speed = float(st.get("speed", 60.0))
	c.damage = float(st.get("damage", 0.0))
	c.jump_velocity = float(st.get("jump", 0.0))

	var se: Dictionary = d.get("senses", {})
	c.flee_range = float(se.get("flee_range", 0.0))
	c.aggro_range = float(se.get("aggro_range", 0.0))
	c.wander_range = float(se.get("wander_range", 160.0))

	var sp: Dictionary = d.get("spawn", {})
	c.depth_min = float(sp.get("depth_min", -999.0))
	c.depth_max = float(sp.get("depth_max", 999.0))
	c.spawn_weight = float(sp.get("weight", 1.0))
	for b in sp.get("biomes", ["rootlands"]):
		c.biomes.append(str(b))
	c.needs_floor = bool(sp.get("needs_floor", true))
	c.floats = bool(sp.get("floats", false))
	c.group_min = maxi(1, int(sp.get("group_min", 1)))
	c.group_max = maxi(c.group_min, int(sp.get("group_max", 1)))
	c.night_only = bool(sp.get("night_only", false))
	c.requires_darkness = bool(sp.get("requires_darkness", false))
	c.near_block = int(sp.get("near_block", -1))
	c.near_block_radius = int(sp.get("near_block_radius", 6))
	c.legendary_event = str(sp.get("legendary_event", ""))

	var li: Dictionary = d.get("light", {})
	var col = li.get("colour", [1, 1, 1])
	if col is Array and (col as Array).size() >= 3:
		c.light_colour = Color(float(col[0]), float(col[1]), float(col[2]))
	c.light_radius = float(li.get("radius", 0.0))
	c.light_intensity = float(li.get("intensity", 0.0))

	for entry in d.get("loot", []):
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		c.loot.append({
			"item": str(e.get("item", "")),
			"chance": float(e.get("chance", 1.0)),
			"min": int(e.get("min", 1)),
			"max": int(e.get("max", 1)),
		})

	var cx: Dictionary = d.get("codex", {})
	for key in cx.keys():
		c.codex_text[str(key)] = str(cx[key])

	for entry in d.get("variants", []):
		if entry is Dictionary:
			c.variants.append(CreatureVariant.from_dict(entry))
	if c.variants.is_empty():
		c.variants.append(CreatureVariant.from_dict({"id": "normal", "display_name": c.display_name}))

	return c


static func _parse_rarity(s: String) -> int:
	match s.to_lower():
		"common": return Rarity.COMMON
		"uncommon": return Rarity.UNCOMMON
		"rare": return Rarity.RARE
		"very_rare": return Rarity.VERY_RARE
		"legendary": return Rarity.LEGENDARY
	return Rarity.COMMON


func rarity_name() -> String:
	match rarity:
		Rarity.COMMON: return "COMMON"
		Rarity.UNCOMMON: return "UNCOMMON"
		Rarity.RARE: return "RARE"
		Rarity.VERY_RARE: return "VERY RARE"
		Rarity.LEGENDARY: return "LEGENDARY"
	return "UNKNOWN"


func rarity_colour() -> Color:
	match rarity:
		Rarity.COMMON: return Color(0.62, 0.70, 0.64)
		Rarity.UNCOMMON: return Color(0.44, 0.80, 0.92)
		Rarity.RARE: return Color(0.72, 0.56, 0.98)
		Rarity.VERY_RARE: return Color(0.98, 0.62, 0.34)
		Rarity.LEGENDARY: return Color(1.0, 0.85, 0.36)
	return Color.WHITE


func is_event_only() -> bool:
	return not legendary_event.is_empty()


func default_variant_id() -> String:
	return variants[0].id if not variants.is_empty() else "normal"


func variant_by_id(vid: String) -> CreatureVariant:
	for v in variants:
		if v.id == vid:
			return v
	return variants[0]


## Weighted variant roll. `rng` keeps this reproducible in tests.
func roll_variant(rng: RandomNumberGenerator) -> CreatureVariant:
	var total := 0.0
	for v in variants:
		total += maxf(0.0, v.weight)
	if total <= 0.0:
		return variants[0]
	var pick := rng.randf() * total
	for v in variants:
		pick -= maxf(0.0, v.weight)
		if pick <= 0.0:
			return v
	return variants[variants.size() - 1]


func codex_field(field: String) -> String:
	return str(codex_text.get(field, "No record."))
