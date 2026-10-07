extends Node
## Autoload: EventBus
##
## The single place systems talk to each other. Keeps World / Player / UI /
## Codex decoupled so none of them needs a hard reference to another.
## Nothing here holds state — if you need state, it belongs in Game or a system.

# --- World -------------------------------------------------------------------
signal world_ready(seed_value: int)
signal chunk_activated(chunk_coord: Vector2i)
signal chunk_released(chunk_coord: Vector2i)
## Emitted after a tile actually changed. `old_block` / `new_block` are ids.
signal tile_changed(tile: Vector2i, old_block: int, new_block: int)
signal block_mined(tile: Vector2i, block_id: int, by_player: bool)
signal block_hit(tile: Vector2i, block_id: int, progress: float)
signal region_recovered(region_key: String)

# --- Player ------------------------------------------------------------------
signal player_spawned(player: Node2D)
signal player_depth_changed(metres: float)
signal player_health_changed(current: float, maximum: float)
signal player_died()
signal player_respawned()
signal player_damaged(amount: float, source: String)
signal depth_record_changed(metres: float)
signal biome_changed(biome_id: String)

# --- Inventory / crafting ----------------------------------------------------
signal inventory_changed()
signal item_collected(item_id: String, amount: int)
signal item_crafted(item_id: String, amount: int)
signal active_tool_changed(item_id: String)
signal craft_failed(reason: String)

# --- Creatures / codex -------------------------------------------------------
signal creature_spawned(creature: Node2D)
signal creature_despawned(creature: Node2D)
signal creature_sighted(species_id: String, variant_id: String)
signal creature_defeated(species_id: String, variant_id: String)
signal codex_entry_discovered(species_id: String, variant_id: String)
signal codex_field_unlocked(species_id: String, field: String)
signal codex_progress_changed(discovered: int, catalogued: int)
signal rare_event_started(event_id: String, position: Vector2)

# --- Meta / UI ---------------------------------------------------------------
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)
signal toast_requested(text: String, kind: String)
signal screen_shake_requested(strength: float, duration: float)
signal interact_prompt_changed(text: String)
signal station_opened(station: String)
signal debug_mode_changed(enabled: bool)
