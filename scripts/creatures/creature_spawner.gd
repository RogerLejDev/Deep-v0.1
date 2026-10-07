extends Node2D
## Populates the live world with creatures, and keeps the population honest.
##
## Spawning is intentionally invisible: candidates are placed in a ring that is
## outside the camera but inside the loaded chunks, so creatures always walk
## into view rather than popping into it. Despawning is distance-based and
## never touches a creature the player can see.

const CREATURE_SCRIPT: String = "res://scripts/creatures/creature.gd"
## Spawn ring, in pixels from the player.
const RING_MIN: float = 300.0
const RING_MAX: float = 620.0
const PLACEMENT_ATTEMPTS: int = 14

var world: DeepWorld = null

var _accum: float = 0.0
var _rare: RareEventDirector = null
var _rng := RandomNumberGenerator.new()
var _creatures: Array[Creature] = []


func _ready() -> void:
	_rng.randomize()
	_rare = RareEventDirector.new()


func configure(p_world: DeepWorld) -> void:
	world = p_world
	_rng.seed = RngUtil.hash2(p_world.world_seed, 0x5EED)
	_rare.configure(p_world)


func active_count() -> int:
	return _creatures.size()


func creatures() -> Array[Creature]:
	return _creatures


func _process(delta: float) -> void:
	if world == null or Game.player == null or not is_instance_valid(Game.player):
		return
	_prune()
	_rare.update(delta, self)
	_accum += delta
	if _accum < GameConfig.CREATURE_SPAWN_INTERVAL:
		return
	_accum = 0.0
	if _creatures.size() >= GameConfig.MAX_ACTIVE_CREATURES:
		return
	_try_natural_spawn()
	Dbg.set_counter("creatures", _creatures.size())


# --- Lifecycle ---------------------------------------------------------------

func _prune() -> void:
	var player_pos: Vector2 = Game.player.global_position
	var survivors: Array[Creature] = []
	for c in _creatures:
		if c == null or not is_instance_valid(c):
			continue
		# Event creatures (the Lumreaper) are never culled for distance; they
		# are the encounter, and the player may legitimately run away.
		if not c.is_event_spawn and player_pos.distance_to(c.global_position) > GameConfig.CREATURE_DESPAWN_DISTANCE:
			EventBus.creature_despawned.emit(c)
			c.queue_free()
			continue
		survivors.append(c)
	_creatures = survivors


func _try_natural_spawn() -> void:
	var player_pos: Vector2 = Game.player.global_position
	var depth := GameConfig.depth_metres(player_pos)
	var zone := BiomeTable.zone_for_depth(depth)
	var dark := BiomeTable.ambient_for_depth(depth).v < 0.34

	var candidates := CreatureDB.spawn_candidates(depth, zone, dark)
	if candidates.is_empty():
		return

	var spot := _find_spawn_spot(player_pos)
	if spot.x < 0:
		return

	# Ecology thins out species the player has over-hunted in this region.
	var total := 0.0
	var weighted: Array[Dictionary] = []
	for entry in candidates:
		var sid := str(entry["id"])
		var w := float(entry["weight"]) * world.ecology.population_factor(spot, sid)
		if w <= 0.0:
			continue
		total += w
		weighted.append({"id": sid, "w": w})
	if total <= 0.0:
		return

	var pick := _rng.randf() * total
	var chosen := ""
	for entry in weighted:
		pick -= float(entry["w"])
		if pick <= 0.0:
			chosen = str(entry["id"])
			break
	if chosen.is_empty():
		return

	var data := CreatureDB.get_species(chosen)
	if not _placement_valid(data, spot):
		return

	var group: int = _rng.randi_range(data.group_min, data.group_max)
	group = mini(group, GameConfig.MAX_ACTIVE_CREATURES - _creatures.size())
	for i in group:
		var tile := spot
		if i > 0:
			tile += Vector2i(_rng.randi_range(-4, 4), _rng.randi_range(-2, 2))
			if not _placement_valid(data, tile):
				continue
		spawn(chosen, data.roll_variant(_rng).id, GameConfig.tile_centre(tile.x, tile.y), false)


func _find_spawn_spot(player_pos: Vector2) -> Vector2i:
	for _i in PLACEMENT_ATTEMPTS:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(RING_MIN, RING_MAX)
		var p := player_pos + Vector2(cos(angle), sin(angle)) * radius
		var tile := GameConfig.world_to_tile(p)
		if not GameConfig.in_bounds(tile.x, tile.y):
			continue
		# Only spawn inside loaded chunks; otherwise collision does not exist
		# yet and ground creatures fall through the world.
		if not world.is_chunk_live(GameConfig.tile_to_chunk(tile)):
			continue
		if BlockDB.is_solid(world.get_tile(tile.x, tile.y)):
			continue
		return tile
	return Vector2i(-1, -1)


func _placement_valid(data: CreatureData, tile: Vector2i) -> bool:
	if BlockDB.is_solid(world.get_tile(tile.x, tile.y)):
		return false
	# Headroom.
	if BlockDB.is_solid(world.get_tile(tile.x, tile.y - 1)):
		return false
	if data.needs_floor:
		var ground := world.first_solid_below(tile.x, tile.y, 4)
		if ground < 0:
			return false
	if data.near_block >= 0:
		if not _block_within(tile, data.near_block, data.near_block_radius):
			return false
	return true


func _block_within(tile: Vector2i, block_id: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if world.get_tile(tile.x + dx, tile.y + dy) == block_id:
				return true
	return false


# --- Spawning ----------------------------------------------------------------

func spawn(species_id: String, variant_id: String, position: Vector2, event_spawn: bool) -> Creature:
	var data := CreatureDB.get_species(species_id)
	if data.art_path.is_empty():
		push_warning("DEEP: species '%s' has no art; not spawning." % species_id)
		return null
	var variant := data.variant_by_id(variant_id)

	var c := Creature.new()
	c.name = "Creature_%s_%d" % [species_id, _creatures.size()]
	add_child(c)
	c.global_position = position
	c.is_event_spawn = event_spawn
	c.setup(data, variant, world, int(_rng.randi()))
	c.died.connect(_on_creature_died)
	_creatures.append(c)
	EventBus.creature_spawned.emit(c)
	return c


func _on_creature_died(c: Creature) -> void:
	_creatures.erase(c)


# --- Debug hooks -------------------------------------------------------------

func debug_force_spawn(species_id: String) -> void:
	if Game.player == null or world == null:
		return
	if not CreatureDB.has_species(species_id):
		EventBus.toast_requested.emit("NO SUCH SPECIES: " + species_id, "warn")
		return
	var data := CreatureDB.get_species(species_id)
	var base := GameConfig.world_to_tile(Game.player.global_position)
	var tile := world.find_open_ground(base + Vector2i(4, 0), 12)
	if tile.x < 0:
		tile = base + Vector2i(3, -1)
	spawn(species_id, data.roll_variant(_rng).id, GameConfig.tile_centre(tile.x, tile.y), false)
	EventBus.toast_requested.emit("SPAWNED " + data.display_name.to_upper(), "info")


func debug_force_rare_event() -> void:
	_rare.force_trigger(self)
