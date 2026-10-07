class_name CreatureDB
extends RefCounted
## Loads every species in data/creatures/ once, in a fixed order.
##
## The manifest is explicit rather than a directory scan so that Codex numbers
## and spawn-table ordering are identical on every platform and in every
## export, and so a malformed file is a loud, specific error.

const DIR: String = "res://data/creatures"
const MANIFEST: Array[String] = [
	"grib", "molo", "glowling", "kryx", "aberrant", "lumreaper",
]

static var _species: Dictionary = {}
static var _ids: Array[String] = []
static var _load_errors: Array[String] = []


static func _ensure() -> void:
	if not _species.is_empty():
		return
	for id in MANIFEST:
		var path := "%s/%s.json" % [DIR, id]
		var text := _read_text(path)
		if text.is_empty():
			_load_errors.append("missing or empty: " + path)
			push_error("DEEP: cannot read species file %s" % path)
			continue
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			_load_errors.append("invalid JSON: " + path)
			push_error("DEEP: %s is not a JSON object" % path)
			continue
		var data := CreatureData.from_dict(parsed)
		if data.id.is_empty():
			data.id = id
		if data.art_path.is_empty():
			_load_errors.append("no art: " + path)
		_species[data.id] = data
		_ids.append(data.id)
	_ids.sort_custom(func(a: String, b: String) -> bool:
		return (_species[a] as CreatureData).codex_number < (_species[b] as CreatureData).codex_number)


## JSON data files load either as an imported JSON resource or as plain text,
## depending on how the project was exported. Try both.
static func _read_text(path: String) -> String:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is JSON:
			return JSON.stringify((res as JSON).data)
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""


static func species_ids() -> Array[String]:
	_ensure()
	return _ids


static func has_species(id: String) -> bool:
	_ensure()
	return _species.has(id)


static func get_species(id: String) -> CreatureData:
	_ensure()
	if _species.has(id):
		return _species[id]
	# A defined-but-missing species must not crash the Codex; hand back a stub.
	var stub := CreatureData.new()
	stub.id = id
	stub.display_name = id.capitalize()
	return stub


static func all() -> Array[CreatureData]:
	_ensure()
	var out: Array[CreatureData] = []
	for id in _ids:
		out.append(_species[id])
	return out


static func get_variant(species_id: String, variant_id: String) -> CreatureVariant:
	return get_species(species_id).variant_by_id(variant_id)


## Species that may spawn naturally at this depth in this biome, with their
## effective weights already multiplied by the biome table and ecology.
static func spawn_candidates(
	depth_metres: float,
	zone: BiomeTable.Zone,
	dark: bool
) -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for id in _ids:
		var c: CreatureData = _species[id]
		if c.is_event_only():
			continue
		if depth_metres < c.depth_min or depth_metres > c.depth_max:
			continue
		if c.requires_darkness and not dark:
			continue
		if not c.biomes.is_empty() and not (zone.biome_id in c.biomes):
			continue
		var zone_weight: float = float(zone.spawn_weights.get(id, 0.0))
		if zone_weight <= 0.0:
			continue
		out.append({"id": id, "weight": c.spawn_weight * zone_weight})
	return out


static func load_errors() -> Array[String]:
	_ensure()
	return _load_errors


static func reload() -> void:
	_species.clear()
	_ids.clear()
	_load_errors.clear()
	_ensure()
