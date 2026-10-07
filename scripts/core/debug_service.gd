extends Node
## Autoload: Dbg
##
## Debug tooling, off by default and never required to play. The overlay and
## every cheat below are gated behind `enabled`, which only the F3 key (or the
## five-tap corner gesture on touch) can turn on.

var enabled: bool = false
## Extra per-frame counters the overlay reads.
var counters: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	EventBus.debug_mode_changed.emit(enabled)
	EventBus.toast_requested.emit("DEBUG " + ("ON" if enabled else "OFF"), "info")


func toggle() -> void:
	set_enabled(not enabled)


func set_counter(key: String, value: Variant) -> void:
	counters[key] = value


func get_counter(key: String, fallback: Variant = "-") -> Variant:
	return counters.get(key, fallback)


# --- Cheats. All no-ops unless `enabled`. ------------------------------------

func teleport_to_depth(metres: float) -> void:
	if not enabled or Game.player == null or Game.world == null:
		return
	var tx := GameConfig.world_to_tile(Game.player.global_position).x
	var ty := int(GameConfig.metres_to_world_y(metres) / GameConfig.TILE_SIZE)
	var open := Game.world.find_open_ground(Vector2i(tx, ty), 24)
	if open.x < 0:
		# Nothing open nearby: carve a small pocket so we never land in rock.
		for dy in range(-2, 2):
			for dx in range(-2, 2):
				Game.world.set_tile(tx + dx, ty + dy, BlockDB.AIR)
		open = Vector2i(tx, ty)
	Game.player.global_position = GameConfig.tile_centre(open.x, open.y)
	EventBus.toast_requested.emit("TELEPORT %d m" % int(metres), "info")


func give(item_id: String, amount: int = 1) -> void:
	if not enabled or Game.inventory == null:
		return
	if not ItemDB.has(item_id):
		EventBus.toast_requested.emit("NO SUCH ITEM: " + item_id, "warn")
		return
	Game.inventory.add(item_id, amount)
	EventBus.toast_requested.emit("+%d %s" % [amount, ItemDB.get_item(item_id).display_name], "info")


func give_test_kit() -> void:
	if not enabled:
		return
	for id in ["copper_ore", "iron_ore", "crystal_shard", "deep_crystal_shard",
			"root_fibre", "glowcap", "plank", "stone_chunk"]:
		Game.inventory.add(id, 40)
	EventBus.toast_requested.emit("TEST KIT GRANTED", "info")


func unlock_codex() -> void:
	if not enabled or Game.codex == null:
		return
	Game.codex.debug_unlock_all()
	EventBus.toast_requested.emit("CODEX UNLOCKED", "info")


func spawn_creature(species_id: String) -> void:
	if not enabled:
		return
	var spawner := _find_spawner()
	if spawner == null:
		return
	spawner.debug_force_spawn(species_id)


func force_rare_event() -> void:
	if not enabled:
		return
	var spawner := _find_spawner()
	if spawner == null:
		return
	spawner.debug_force_rare_event()


func heal_player() -> void:
	if not enabled or Game.player == null:
		return
	if Game.player.has_method("heal"):
		Game.player.call("heal", 9999.0)


func _find_spawner() -> Node:
	if Game.world == null:
		return null
	var parent := Game.world.get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("CreatureSpawner")
