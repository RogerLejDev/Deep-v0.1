extends Node
## Autoload: SaveManager
##
## Local-only, three-slot save system. No network, no cloud, no account.
##
## Robustness strategy, in order of importance:
##   1. Atomic writes. Everything is written to `<slot>.tmp` and only renamed
##      over the live file once the bytes are on disk, so a crash or a killed
##      Android process can never leave a half-written save.
##   2. One generation of backup. The previous file is kept as `<slot>.bak`
##      and loaded automatically if the live file fails validation.
##   3. Schema validation before use. A save missing required keys, or with a
##      newer format version, is rejected rather than crashing the game.
##   4. A checksum over the payload catches silent corruption.

const DIR: String = "user://saves"
const EXT: String = ".deep"
const REQUIRED_KEYS: Array[String] = ["format", "seed", "player", "inventory", "codex"]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func slot_path(slot: int) -> String:
	return "%s/slot_%d%s" % [DIR, slot, EXT]


func backup_path(slot: int) -> String:
	return "%s/slot_%d%s.bak" % [DIR, slot, EXT]


func temp_path(slot: int) -> String:
	return "%s/slot_%d%s.tmp" % [DIR, slot, EXT]


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(backup_path(slot))


# --- Write -------------------------------------------------------------------

func write_slot(slot: int, payload: Dictionary) -> bool:
	if slot < 0 or slot >= GameConfig.SAVE_SLOTS:
		EventBus.save_failed.emit("Invalid slot %d" % slot)
		return false
	DirAccess.make_dir_recursive_absolute(DIR)

	# The payload is embedded as a *string*, not as a nested object, so the
	# checksum covers the exact bytes we wrote. Re-serialising a parsed
	# object would not reproduce them (JSON does not preserve int/float
	# distinctions), which would make every checksum fail on read.
	var body := JSON.stringify(payload)
	var envelope := {
		"magic": "DEEP",
		"format": GameConfig.SAVE_FORMAT_VERSION,
		"checksum": body.sha256_text(),
		"payload_json": body,
	}
	var text := JSON.stringify(envelope)

	var tmp := temp_path(slot)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		EventBus.save_failed.emit("Cannot open %s (%d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(text)
	f.flush()
	f.close()

	# Verify the temp file reads back before we let it replace the live save.
	var check := _read_file(tmp)
	if check.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		EventBus.save_failed.emit("Write verification failed")
		return false

	var dir := DirAccess.open(DIR)
	if dir == null:
		EventBus.save_failed.emit("Cannot open save directory")
		return false
	var live_name := "slot_%d%s" % [slot, EXT]
	if dir.file_exists(live_name):
		dir.remove(live_name + ".bak")
		dir.rename(live_name, live_name + ".bak")
	var err := dir.rename(live_name + ".tmp", live_name)
	if err != OK:
		EventBus.save_failed.emit("Rename failed (%d)" % err)
		return false

	EventBus.game_saved.emit(slot)
	return true


# --- Read --------------------------------------------------------------------

## Returns the payload, or {} if the slot is unusable.
func read_slot(slot: int) -> Dictionary:
	var primary := _read_file(slot_path(slot))
	if not primary.is_empty():
		return primary
	var backup := _read_file(backup_path(slot))
	if not backup.is_empty():
		push_warning("DEEP: slot %d fell back to its backup." % slot)
		return backup
	return {}


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	if text.strip_edges().is_empty():
		return {}

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("DEEP: %s is not valid JSON." % path)
		return {}
	var envelope: Dictionary = parsed
	if str(envelope.get("magic", "")) != "DEEP":
		push_warning("DEEP: %s is not a DEEP save." % path)
		return {}
	if int(envelope.get("format", 0)) > GameConfig.SAVE_FORMAT_VERSION:
		push_warning("DEEP: %s was written by a newer version." % path)
		return {}
	var body := str(envelope.get("payload_json", ""))
	if body.is_empty():
		push_warning("DEEP: %s carries no payload." % path)
		return {}

	var expected := str(envelope.get("checksum", ""))
	if not expected.is_empty() and body.sha256_text() != expected:
		push_warning("DEEP: checksum mismatch in %s." % path)
		return {}

	var payload = JSON.parse_string(body)
	if not (payload is Dictionary):
		push_warning("DEEP: payload in %s is not an object." % path)
		return {}
	if not validate(payload):
		return {}
	return payload


## Structural check. Cheap, and the difference between a clear "save damaged"
## message and a crash on a null dereference deep in the loading path.
func validate(payload: Dictionary) -> bool:
	for key in REQUIRED_KEYS:
		if not payload.has(key):
			push_warning("DEEP: save missing required key '%s'." % key)
			return false
	if not (payload.get("player") is Dictionary):
		return false
	if not (payload.get("inventory") is Dictionary):
		return false
	if not (payload.get("codex") is Dictionary):
		return false
	var mods = payload.get("world_mods", {})
	if mods != null and not (mods is Dictionary):
		return false
	return true


# --- Slot summaries for the main menu ----------------------------------------

func slot_summary(slot: int) -> Dictionary:
	var d := read_slot(slot)
	if d.is_empty():
		return {"exists": false, "slot": slot}
	var codex: Dictionary = d.get("codex", {})
	var discovered: int = (codex.get("entries", {}) as Dictionary).size()
	return {
		"exists": true,
		"slot": slot,
		"seed": int(d.get("seed", 0)),
		"playtime": float(d.get("playtime", 0.0)),
		"deepest_metres": float(d.get("deepest_metres", 0.0)),
		"discovered": discovered,
		"saved_at": int(d.get("saved_at", 0)),
		"tool": str((d.get("player", {}) as Dictionary).get("active_tool", "")),
	}


func all_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in GameConfig.SAVE_SLOTS:
		out.append(slot_summary(i))
	return out


func delete_slot(slot: int) -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var name := "slot_%d%s" % [slot, EXT]
	dir.remove(name)
	dir.remove(name + ".bak")
	dir.remove(name + ".tmp")
