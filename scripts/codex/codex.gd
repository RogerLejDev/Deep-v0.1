class_name Codex
extends RefCounted
## The player's knowledge of the world's life.
##
## Seeing a creature is not the same as knowing it. A sighting opens the entry
## and reveals its name and silhouette; everything else — habitat, behaviour,
## diet, what it drops, what hurts it, and finally the narrative note — stays
## `???` until the player has spent enough time *watching* that species.
## Observation only accumulates while the creature is alive and on screen,
## which is what turns "a monster ran past" into "I followed it for a while".

## Field order matters: it is the order they unlock and the order the UI lists.
const FIELDS: Array[String] = [
	"habitat", "behaviour", "diet", "resource", "weakness", "lore",
]
## Observation seconds required per field.
const FIELD_THRESHOLDS := {
	"habitat": 1.5,
	"behaviour": 3.0,
	"diet": 4.5,
	"resource": 6.0,
	"weakness": 7.5,
	"lore": 9.0,
}

## species_id -> entry dictionary
var entries: Dictionary = {}


func _init() -> void:
	entries = {}


# --- Queries -----------------------------------------------------------------

func catalogued() -> int:
	return CreatureDB.species_ids().size()


func planned_slots() -> int:
	return GameConfig.CODEX_PLANNED_SLOTS


func discovered() -> int:
	return entries.size()


func is_sighted(species_id: String) -> bool:
	return entries.has(species_id)


func entry(species_id: String) -> Dictionary:
	return entries.get(species_id, {})


func observation(species_id: String) -> float:
	return float(entry(species_id).get("observation", 0.0))


func is_field_known(species_id: String, field: String) -> bool:
	var e := entry(species_id)
	if e.is_empty():
		return false
	return (e.get("fields", {}) as Dictionary).has(field)


func known_variants(species_id: String) -> Array[String]:
	var e := entry(species_id)
	var out: Array[String] = []
	for v in (e.get("variants", {}) as Dictionary).keys():
		out.append(str(v))
	return out


func sighting_count(species_id: String) -> int:
	return int(entry(species_id).get("sightings", 0))


func first_depth(species_id: String) -> float:
	return float(entry(species_id).get("first_depth", 0.0))


## 0..1 — how complete this species' page is, counting fields and variants.
func completion(species_id: String) -> float:
	if not is_sighted(species_id):
		return 0.0
	var data := CreatureDB.get_species(species_id)
	var total := float(FIELDS.size() + data.variants.size())
	var have := float((entry(species_id).get("fields", {}) as Dictionary).size())
	have += float((entry(species_id).get("variants", {}) as Dictionary).size())
	return clampf(have / maxf(total, 1.0), 0.0, 1.0)


## 0..1 across the whole catalogue, used for the Codex header bar.
func overall_completion() -> float:
	var ids := CreatureDB.species_ids()
	if ids.is_empty():
		return 0.0
	var sum := 0.0
	for id in ids:
		sum += completion(id)
	return sum / float(ids.size())


# --- Recording ---------------------------------------------------------------

## Returns true if this was a brand-new species (worth a full-screen reveal).
func note_sighting(species_id: String, variant_id: String, depth_metres: float) -> bool:
	var brand_new := not entries.has(species_id)
	if brand_new:
		entries[species_id] = {
			"observation": 0.0,
			"fields": {},
			"variants": {},
			"sightings": 0,
			"defeated": 0,
			"first_depth": depth_metres,
			"min_depth": depth_metres,
			"max_depth": depth_metres,
			"first_seen_at": Time.get_unix_time_from_system(),
		}
	var e: Dictionary = entries[species_id]
	e["sightings"] = int(e.get("sightings", 0)) + 1
	e["min_depth"] = minf(float(e.get("min_depth", depth_metres)), depth_metres)
	e["max_depth"] = maxf(float(e.get("max_depth", depth_metres)), depth_metres)

	var new_variant := false
	if not variant_id.is_empty():
		var vars_seen: Dictionary = e.get("variants", {})
		if not vars_seen.has(variant_id):
			new_variant = true
		vars_seen[variant_id] = int(vars_seen.get(variant_id, 0)) + 1
		e["variants"] = vars_seen

	entries[species_id] = e

	if brand_new:
		EventBus.codex_entry_discovered.emit(species_id, variant_id)
	elif new_variant:
		EventBus.toast_requested.emit(
			"VARIANT RECORDED · " + CreatureDB.get_variant(species_id, variant_id).display_name.to_upper(),
			"variant")
	_emit_progress()
	return brand_new


## Called every frame a sighted creature is visible and alive.
func add_observation(species_id: String, seconds: float) -> void:
	if not entries.has(species_id) or seconds <= 0.0:
		return
	var e: Dictionary = entries[species_id]
	var before := float(e.get("observation", 0.0))
	if before >= GameConfig.OBSERVATION_FULL:
		return
	var after: float = minf(GameConfig.OBSERVATION_FULL, before + seconds)
	e["observation"] = after
	var fields: Dictionary = e.get("fields", {})
	for field in FIELDS:
		var need: float = float(FIELD_THRESHOLDS[field])
		if after >= need and not fields.has(field):
			fields[field] = true
			EventBus.codex_field_unlocked.emit(species_id, field)
	e["fields"] = fields
	entries[species_id] = e
	_emit_progress()


## Killing something teaches you what it is made of and where it is soft.
func note_defeat(species_id: String) -> void:
	if not entries.has(species_id):
		return
	var e: Dictionary = entries[species_id]
	e["defeated"] = int(e.get("defeated", 0)) + 1
	var fields: Dictionary = e.get("fields", {})
	for field in ["resource", "weakness"]:
		if not fields.has(field):
			fields[field] = true
			EventBus.codex_field_unlocked.emit(species_id, field)
	e["fields"] = fields
	# A dissection is worth a couple of seconds of watching.
	e["observation"] = minf(GameConfig.OBSERVATION_FULL, float(e.get("observation", 0.0)) + 2.0)
	entries[species_id] = e
	_emit_progress()


func _emit_progress() -> void:
	EventBus.codex_progress_changed.emit(discovered(), catalogued())


func debug_unlock_all() -> void:
	for id in CreatureDB.species_ids():
		var data := CreatureDB.get_species(id)
		note_sighting(id, data.default_variant_id(), data.depth_min)
		for v in data.variants:
			note_sighting(id, (v as CreatureVariant).id, data.depth_min)
		add_observation(id, GameConfig.OBSERVATION_FULL)


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	entries = {}
	var raw: Dictionary = d.get("entries", {})
	for key in raw.keys():
		var sid := str(key)
		# Silently drop species that no longer exist in the data, so an old
		# save never breaks the Codex UI.
		if not CreatureDB.has_species(sid):
			continue
		var src: Dictionary = raw[key]
		var fields: Dictionary = {}
		for f in (src.get("fields", {}) as Dictionary).keys():
			if str(f) in FIELDS:
				fields[str(f)] = true
		var vars_seen: Dictionary = {}
		for v in (src.get("variants", {}) as Dictionary).keys():
			vars_seen[str(v)] = int((src.get("variants", {}) as Dictionary)[v])
		entries[sid] = {
			"observation": clampf(float(src.get("observation", 0.0)), 0.0, GameConfig.OBSERVATION_FULL),
			"fields": fields,
			"variants": vars_seen,
			"sightings": int(src.get("sightings", 1)),
			"defeated": int(src.get("defeated", 0)),
			"first_depth": float(src.get("first_depth", 0.0)),
			"min_depth": float(src.get("min_depth", 0.0)),
			"max_depth": float(src.get("max_depth", 0.0)),
			"first_seen_at": int(src.get("first_seen_at", 0)),
		}
	_emit_progress()
