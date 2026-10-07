class_name RareEventDirector
extends RefCounted
## UNKNOWN SIGNAL — the system that keeps a "finished" region unfinished.
##
## The design problem: once a player has catalogued everything in the
## Rootlands, the Rootlands stop being interesting. The answer is that the
## apex species is not resident anywhere. It is not on a spawn table and no
## amount of exploring will find it. It *arrives*, rarely, under conditions the
## player cannot farm:
##
##   * deep enough (120 m+) and genuinely dark;
##   * the player has been down here a while this expedition;
##   * a long cooldown since the last signal;
##   * and then a small per-check roll.
##
## The result is a region that can read 100% complete and still, twenty hours
## later, produce something the player has never seen. Everything here is
## probability-gated, never scripted, so it cannot become a timed reward.

const CHECK_INTERVAL: float = 6.0
## Minimum real seconds between two signals, whatever the rolls say.
const COOLDOWN: float = 1500.0
## Minimum uninterrupted time below the depth threshold before a roll happens.
const DWELL_REQUIRED: float = 75.0
const MIN_DEPTH: float = 120.0
## Per-check probability once every condition is met.
const BASE_CHANCE: float = 0.018

var _world: DeepWorld = null
var _check_accum: float = 0.0
var _dwell: float = 0.0
var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()
var _active_event: String = ""


func configure(p_world: DeepWorld) -> void:
	_world = p_world
	_rng.seed = RngUtil.hash2(p_world.world_seed, 0x516E41)
	# Never fire in the first minutes of a brand-new save.
	_cooldown = 240.0


func update(delta: float, spawner: Node) -> void:
	if _world == null or Game.player == null or not is_instance_valid(Game.player):
		return
	_cooldown = maxf(0.0, _cooldown - delta)

	var depth := GameConfig.depth_metres(Game.player.global_position)
	if depth >= MIN_DEPTH:
		_dwell += delta
	else:
		# Surfacing resets the dwell timer: you cannot camp the trigger.
		_dwell = maxf(0.0, _dwell - delta * 2.0)

	Dbg.set_counter("signal_dwell", "%.0f/%.0f" % [_dwell, DWELL_REQUIRED])
	Dbg.set_counter("signal_cooldown", "%.0f" % _cooldown)

	_check_accum += delta
	if _check_accum < CHECK_INTERVAL:
		return
	_check_accum = 0.0

	if not _active_event.is_empty():
		return
	if _cooldown > 0.0 or _dwell < DWELL_REQUIRED or depth < MIN_DEPTH:
		return
	var ambient := BiomeTable.ambient_for_depth(depth)
	if ambient.v > 0.22:
		return

	# Deeper is slightly more likely, and a player who has already driven one
	# off is a little more likely to attract another.
	var chance := BASE_CHANCE
	chance *= lerpf(1.0, 2.2, clampf((depth - MIN_DEPTH) / 180.0, 0.0, 1.0))
	if Game.boss_defeated("lumreaper"):
		chance *= 1.35
	if _rng.randf() > chance:
		return

	trigger(spawner, "unknown_signal")


func force_trigger(spawner: Node) -> void:
	trigger(spawner, "unknown_signal")


func trigger(spawner: Node, event_id: String) -> void:
	if Game.player == null or _world == null:
		return
	_active_event = event_id
	_cooldown = COOLDOWN
	_dwell = 0.0

	var origin: Vector2 = Game.player.global_position
	EventBus.rare_event_started.emit(event_id, origin)
	EventBus.toast_requested.emit("UNKNOWN SIGNAL", "legendary")
	EventBus.screen_shake_requested.emit(3.0, 1.2)
	Audio.play("discovery", 0.55, -2.0)
	Game.note_story("heard_unknown_signal")

	# Give the player a beat to realise something changed before it arrives.
	var tree := spawner.get_tree()
	if tree != null:
		await tree.create_timer(3.2).timeout
	if Game.player == null or not is_instance_valid(Game.player):
		_active_event = ""
		return

	var species := _event_species(event_id)
	if species.is_empty():
		_active_event = ""
		return
	var data := CreatureDB.get_species(species)
	var tile := _arrival_tile(Game.player.global_position)
	var variant := data.roll_variant(_rng)
	var c = spawner.call("spawn", species, variant.id, GameConfig.tile_centre(tile.x, tile.y), true)
	if c == null:
		_active_event = ""
		return

	EventBus.screen_shake_requested.emit(7.0, 0.8)
	Audio.play("crystal_break", 0.45, 0.0)
	if c is Creature:
		(c as Creature).died.connect(func(_x: Creature) -> void: _active_event = "")


func _event_species(event_id: String) -> String:
	for data in CreatureDB.all():
		if data.legendary_event == event_id:
			return data.id
	return ""


## Carve a small arrival pocket so a 58px apex creature never materialises
## inside solid rock.
func _arrival_tile(player_pos: Vector2) -> Vector2i:
	var base := GameConfig.world_to_tile(player_pos)
	for _i in 18:
		var offset := Vector2i(_rng.randi_range(-18, 18), _rng.randi_range(-8, 4))
		var t := base + offset
		if absi(offset.x) < 7:
			continue
		if not GameConfig.in_bounds(t.x, t.y):
			continue
		if _space_clear(t, 3):
			return t
	var fallback := base + Vector2i(10, -2)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			_world.set_tile(fallback.x + dx, fallback.y + dy, BlockDB.AIR, true)
	return fallback


func _space_clear(t: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if BlockDB.is_solid(_world.get_tile(t.x + dx, t.y + dy)):
				return false
	return true


func active_event() -> String:
	return _active_event
