extends Node
## Autoload: Game
##
## Owns the current run: seed, inventory, codex, equipment, progression flags
## and statistics. Scene nodes (World, Player) register themselves here so UI
## and systems have one well-typed place to find them without reaching through
## the scene tree.
##
## Everything here is serialisable. SaveManager only ever talks to this object.

const DEFAULT_TOOL: String = "pick_starter"

var world_seed: int = 0
var current_slot: int = 0
var inventory: Inventory = null
var chest: Inventory = null
var codex: Codex = null

var active_tool: String = DEFAULT_TOOL
## Item id the place button will use. Empty means "first placeable in the pack".
var selected_placeable: String = ""
## Permanent progression flags: zones reached, boss defeated, story beats.
var progress: Dictionary = {}
var stats: Dictionary = {}

## Set by the Game scene on load.
var world: DeepWorld = null
var player: Node2D = null

var deepest_metres: float = 0.0
var playtime: float = 0.0
var run_active: bool = false

## Timed consumable effects: id -> seconds remaining.
var effects: Dictionary = {}

var _autosave_accum: float = 0.0
## Where the player's dropped pack is waiting, if they died.
var recovery_cache: Dictionary = {}
## Set by the main menu when continuing a save; consumed by the Game scene.
var pending_load: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_containers()
	EventBus.player_depth_changed.connect(_on_depth_changed)


func _reset_containers() -> void:
	inventory = Inventory.new(24)
	chest = Inventory.new(30)
	codex = Codex.new()
	progress = {
		"zones_reached": ["rootlands_surface"],
		"bosses_defeated": [],
		"story_beats": [],
		"recipes_seen": [],
	}
	stats = {
		"blocks_mined": 0,
		"creatures_sighted": 0,
		"creatures_defeated": 0,
		"items_crafted": 0,
		"deaths": 0,
		"expeditions": 0,
	}
	effects = {}
	recovery_cache = {}
	active_tool = DEFAULT_TOOL
	selected_placeable = ""
	deepest_metres = 0.0
	playtime = 0.0


# --- Run lifecycle -----------------------------------------------------------

func new_run(p_seed: int, slot: int) -> void:
	_reset_containers()
	world_seed = p_seed
	current_slot = slot
	# The starting kit: a bad pick and nothing else. Everything the player uses
	# after this, they dug up themselves.
	inventory.add("pick_starter", 1)
	inventory.add("torch", 3)
	active_tool = "pick_starter"
	run_active = true
	_autosave_accum = 0.0


func end_run() -> void:
	run_active = false
	world = null
	player = null


func _process(delta: float) -> void:
	if not run_active:
		return
	playtime += delta
	_tick_effects(delta)
	if world != null:
		world.ecology.advance(delta)
	_autosave_accum += delta
	if _autosave_accum >= GameConfig.AUTOSAVE_SECONDS:
		_autosave_accum = 0.0
		autosave()


func autosave() -> void:
	if not run_active:
		return
	if SaveManager.write_slot(current_slot, build_payload()):
		EventBus.toast_requested.emit("PROGRESS SAVED", "save")


func save_now() -> bool:
	if not run_active:
		return false
	var ok := SaveManager.write_slot(current_slot, build_payload())
	if ok:
		EventBus.toast_requested.emit("PROGRESS SAVED", "save")
	return ok


# --- Equipment / effects -----------------------------------------------------

func tool_def() -> ItemDef:
	return ItemDB.get_item(active_tool)


func set_active_tool(id: String) -> void:
	if id == active_tool:
		return
	if not ItemDB.get_item(id).is_tool():
		return
	active_tool = id
	EventBus.active_tool_changed.emit(id)


## Current mining power, including any temporary effects.
func mining_power() -> float:
	return tool_def().tool_power


func mining_tier() -> int:
	return tool_def().tool_tier


## Light radius in pixels: base vision, plus the lantern if owned, doubled
## while a Lumen Flask is burning.
func light_radius() -> float:
	var r := 132.0
	if inventory != null and inventory.has("lantern"):
		r += ItemDB.get_item("lantern").light_radius
	if effects.has("lumen_flask"):
		r *= 1.9
	return r


func light_colour() -> Color:
	if effects.has("lumen_flask"):
		return Color(0.62, 0.88, 1.0)
	if inventory != null and inventory.has("lantern"):
		return Color(1.0, 0.86, 0.62)
	return Color(1.0, 0.78, 0.54)


func apply_effect(id: String, seconds: float) -> void:
	effects[id] = maxf(float(effects.get(id, 0.0)), seconds)


func _tick_effects(delta: float) -> void:
	if effects.is_empty():
		return
	var expired: Array[String] = []
	for id: String in effects.keys():
		var left: float = float(effects[id]) - delta
		if left <= 0.0:
			expired.append(id)
		else:
			effects[id] = left
	for id in expired:
		effects.erase(id)
		EventBus.toast_requested.emit(ItemDB.get_item(id).display_name.to_upper() + " FADED", "info")


# --- Progression -------------------------------------------------------------

func note_zone(zone_id: String) -> void:
	var reached: Array = progress.get("zones_reached", [])
	if zone_id in reached:
		return
	reached.append(zone_id)
	progress["zones_reached"] = reached
	var z := BiomeTable.zone_by_id(zone_id)
	EventBus.toast_requested.emit(z.display_name, "zone")


func has_zone(zone_id: String) -> bool:
	return zone_id in (progress.get("zones_reached", []) as Array)


func note_boss(boss_id: String) -> void:
	var list: Array = progress.get("bosses_defeated", [])
	if boss_id in list:
		return
	list.append(boss_id)
	progress["bosses_defeated"] = list


func boss_defeated(boss_id: String) -> bool:
	return boss_id in (progress.get("bosses_defeated", []) as Array)


func note_story(beat: String) -> void:
	var list: Array = progress.get("story_beats", [])
	if beat in list:
		return
	list.append(beat)
	progress["story_beats"] = list


func bump_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func _on_depth_changed(metres: float) -> void:
	if metres > deepest_metres:
		deepest_metres = metres
		EventBus.depth_record_changed.emit(metres)


# --- Serialisation -----------------------------------------------------------

func build_payload() -> Dictionary:
	var pos := Vector2.ZERO
	var health := 100.0
	if player != null and is_instance_valid(player):
		pos = player.global_position
		if player.has_method("get_health"):
			health = float(player.call("get_health"))
	return {
		"format": GameConfig.SAVE_FORMAT_VERSION,
		"seed": world_seed,
		"saved_at": Time.get_unix_time_from_system(),
		"playtime": playtime,
		"player": {
			"x": pos.x,
			"y": pos.y,
			"health": health,
			"active_tool": active_tool,
		},
		"inventory": inventory.to_dict(),
		"chest": chest.to_dict(),
		"codex": codex.to_dict(),
		"progress": progress.duplicate(true),
		"stats": stats.duplicate(true),
		"deepest_metres": deepest_metres,
		"effects": effects.duplicate(true),
		"recovery": recovery_cache.duplicate(true),
		"world_mods": world.export_modifications() if world != null else {},
		"ecology": world.ecology.to_dict() if world != null else {},
	}


## Restore everything except the world itself (the Game scene does that, since
## it needs the seed first). Returns the saved player position.
func apply_payload(d: Dictionary, slot: int) -> Vector2:
	_reset_containers()
	current_slot = slot
	world_seed = int(d.get("seed", 0))
	playtime = float(d.get("playtime", 0.0))
	deepest_metres = float(d.get("deepest_metres", 0.0))

	var p: Dictionary = d.get("player", {})
	active_tool = str(p.get("active_tool", DEFAULT_TOOL))
	if not ItemDB.get_item(active_tool).is_tool():
		active_tool = DEFAULT_TOOL

	inventory.from_dict(d.get("inventory", {}))
	chest.from_dict(d.get("chest", {}))
	codex.from_dict(d.get("codex", {}))

	var prog: Dictionary = d.get("progress", {})
	for key in prog.keys():
		progress[str(key)] = prog[key]
	var st: Dictionary = d.get("stats", {})
	for key in st.keys():
		stats[str(key)] = st[key]

	var fx: Dictionary = d.get("effects", {})
	for key in fx.keys():
		effects[str(key)] = float(fx[key])
	recovery_cache = (d.get("recovery", {}) as Dictionary).duplicate(true)

	run_active = true
	_autosave_accum = 0.0
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))


func stored_health(d: Dictionary) -> float:
	return float((d.get("player", {}) as Dictionary).get("health", 100.0))
