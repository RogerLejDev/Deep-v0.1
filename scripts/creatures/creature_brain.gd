class_name CreatureBrain
extends RefCounted
## Named behaviour profiles.
##
## The brain never touches the scene tree. It reads a Context the Creature
## fills in and writes a decision back into it. That keeps AI testable without
## a running game, keeps Creature free of a dozen behaviour branches, and means
## adding a behaviour is adding one `_tick_*` method plus a name in the data.

class Context extends RefCounted:
	# --- inputs ---
	var data: CreatureData = null
	var variant: CreatureVariant = null
	var position: Vector2 = Vector2.ZERO
	var home: Vector2 = Vector2.ZERO
	var player_position: Vector2 = Vector2.ZERO
	var player_distance: float = INF
	var player_visible: bool = false
	## How brightly lit the creature's own tile is, 0..1.
	var light_level: float = 0.0
	var on_floor: bool = false
	var hp_ratio: float = 1.0
	var blocked_ahead: bool = false
	var ledge_ahead: bool = false
	var delta: float = 0.016
	var time: float = 0.0

	# --- outputs ---
	var desired_velocity: Vector2 = Vector2.ZERO
	var want_jump: bool = false
	var facing: int = 1
	var state: String = "idle"
	## 0..1 fade used by phantom-style creatures.
	var dissolve: float = 0.0
	## Set when the creature wants to chew the tile it is facing.
	var mine_tile: Vector2i = Vector2i(-1, -1)
	## Apex phases set this so the Creature can refuse damage.
	var invulnerable: bool = false
	## Request a one-off visual/audio beat, consumed by the Creature.
	var cue: String = ""


var _wander_dir: int = 1
var _timer: float = 0.0
var _phase_timer: float = 0.0
var _phase: int = 0
var _rng := RandomNumberGenerator.new()
var _dissolving: bool = false
var _dissolve_t: float = 0.0


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value
	_wander_dir = 1 if _rng.randf() > 0.5 else -1


func tick(ctx: Context) -> void:
	_timer -= ctx.delta
	match ctx.data.behaviour:
		"skittish": _tick_skittish(ctx)
		"burrower": _tick_burrower(ctx)
		"drifter": _tick_drifter(ctx)
		"aggressive": _tick_aggressive(ctx)
		"phantom": _tick_phantom(ctx)
		"apex": _tick_apex(ctx)
		_: _tick_wander(ctx)
	if absf(ctx.desired_velocity.x) > 1.0:
		ctx.facing = signi(int(ctx.desired_velocity.x))


# --- Ground helpers ----------------------------------------------------------

func _repick_wander(ctx: Context, min_t: float, max_t: float) -> void:
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(min_t, max_t)
	# Bias back toward home so a creature never drifts out of its habitat.
	var away := ctx.position.x - ctx.home.x
	if absf(away) > ctx.data.wander_range:
		_wander_dir = -1 if away > 0.0 else 1
	elif _rng.randf() < 0.42:
		_wander_dir = -_wander_dir


## Turn around at walls and at the edge of a drop, so walkers never fall into
## their own tunnels or grind against a wall forever.
func _avoid_hazards(ctx: Context) -> void:
	if ctx.blocked_ahead or ctx.ledge_ahead:
		_wander_dir = -_wander_dir
		_timer = _rng.randf_range(0.5, 1.4)


# --- Profiles ----------------------------------------------------------------

func _tick_wander(ctx: Context) -> void:
	_repick_wander(ctx, 1.2, 3.0)
	_avoid_hazards(ctx)
	var speed := ctx.data.speed * ctx.variant.speed_mul * 0.55
	ctx.desired_velocity.x = float(_wander_dir) * speed
	ctx.state = "walk"


## Grib: forages, panics, then creeps back out of curiosity.
func _tick_skittish(ctx: Context) -> void:
	var speed := ctx.data.speed * ctx.variant.speed_mul
	if ctx.player_distance < ctx.data.flee_range:
		var away: int = 1 if ctx.position.x > ctx.player_position.x else -1
		_wander_dir = away
		ctx.desired_velocity.x = float(away) * speed
		ctx.state = "flee"
		# Hop over anything in the way rather than cornering itself.
		if (ctx.blocked_ahead or ctx.ledge_ahead) and ctx.on_floor:
			ctx.want_jump = true
		if _timer <= 0.0:
			_timer = 0.6
			ctx.cue = "chirp"
		return
	if ctx.player_distance < ctx.data.flee_range * 2.4:
		# Watching the player from a safe distance: freeze, then edge closer.
		_repick_wander(ctx, 0.8, 1.8)
		ctx.desired_velocity.x = 0.0
		ctx.state = "alert"
		return
	_repick_wander(ctx, 1.0, 2.6)
	_avoid_hazards(ctx)
	ctx.desired_velocity.x = float(_wander_dir) * speed * 0.42
	ctx.state = "walk"


## Molo: plods, and eats through soft rock, genuinely widening tunnels.
func _tick_burrower(ctx: Context) -> void:
	var speed := ctx.data.speed * ctx.variant.speed_mul
	# Retaliate only while hurt and the player is close.
	if ctx.hp_ratio < 0.999 and ctx.player_distance < ctx.data.aggro_range * 3.0:
		var towards: int = 1 if ctx.player_position.x > ctx.position.x else -1
		ctx.desired_velocity.x = float(towards) * speed * 1.4
		ctx.state = "charge"
		return
	_repick_wander(ctx, 2.4, 5.0)
	ctx.desired_velocity.x = float(_wander_dir) * speed
	ctx.state = "walk"
	# A blocked Molo digs instead of turning. This is what carves the side
	# passages the player later finds.
	if ctx.blocked_ahead:
		var t := GameConfig.world_to_tile(ctx.position + Vector2(float(_wander_dir) * 12.0, 0.0))
		ctx.mine_tile = t
		ctx.state = "dig"
	if ctx.ledge_ahead and not ctx.blocked_ahead:
		_wander_dir = -_wander_dir


## Glowling: floats, and treats light as the thing to avoid.
func _tick_drifter(ctx: Context) -> void:
	var speed := ctx.data.speed * ctx.variant.speed_mul
	var bob: float = sin(ctx.time * 1.9 + ctx.home.x * 0.01) * 0.45
	var drift := Vector2.ZERO

	if ctx.light_level > 0.26 or ctx.player_distance < ctx.data.flee_range:
		# Retreat from the lit area, but slowly — it reads as reluctance.
		drift = (ctx.position - ctx.player_position).normalized() * speed * 0.9
		ctx.state = "retreat"
	else:
		_repick_wander(ctx, 1.6, 3.4)
		drift = Vector2(float(_wander_dir) * speed * 0.5, bob * speed * 0.3)
		ctx.state = "drift"
		# Gentle pull home so a shoal stays a shoal.
		var home_pull := (ctx.home - ctx.position)
		if home_pull.length() > ctx.data.wander_range:
			drift += home_pull.normalized() * speed * 0.5

	drift.y += bob * 14.0
	ctx.desired_velocity = drift


## Kryx: guards a seam, commits to a charge, goes home when it loses you.
func _tick_aggressive(ctx: Context) -> void:
	var speed := ctx.data.speed * ctx.variant.speed_mul
	var leash: float = ctx.data.wander_range * 2.2

	if ctx.player_distance < ctx.data.aggro_range and ctx.position.distance_to(ctx.home) < leash:
		var towards: int = 1 if ctx.player_position.x > ctx.position.x else -1
		ctx.desired_velocity.x = float(towards) * speed
		ctx.state = "charge"
		# Jump at the player if they are above, or if the path is blocked.
		if ctx.on_floor and (ctx.blocked_ahead or ctx.player_position.y < ctx.position.y - 20.0):
			ctx.want_jump = true
		if _timer <= 0.0:
			_timer = 1.1
			ctx.cue = "chirp"
		return

	if ctx.position.distance_to(ctx.home) > leash:
		var back: int = 1 if ctx.home.x > ctx.position.x else -1
		ctx.desired_velocity.x = float(back) * speed * 0.8
		ctx.state = "return"
		if ctx.on_floor and ctx.blocked_ahead:
			ctx.want_jump = true
		return

	_repick_wander(ctx, 0.9, 2.2)
	_avoid_hazards(ctx)
	ctx.desired_velocity.x = float(_wander_dir) * speed * 0.35
	ctx.state = "patrol"


## Aberrant: approaches without hurrying, and leaves when hurt.
func _tick_phantom(ctx: Context) -> void:
	var speed := ctx.data.speed * ctx.variant.speed_mul

	if _dissolving:
		_dissolve_t += ctx.delta * 1.6
		ctx.dissolve = clampf(_dissolve_t, 0.0, 1.0)
		ctx.desired_velocity = Vector2.ZERO
		ctx.state = "dissolve"
		ctx.invulnerable = true
		if _dissolve_t >= 1.0:
			# Reappear somewhere else nearby; the Creature performs the move.
			ctx.cue = "relocate"
			_dissolving = false
			_dissolve_t = 0.0
			ctx.dissolve = 0.0
		return

	# Being hurt is what makes it leave, not losing the fight.
	if ctx.hp_ratio < 0.65 and not _dissolving:
		_dissolving = true
		ctx.cue = "fade"
		return

	if ctx.player_distance < ctx.data.aggro_range:
		var dir := (ctx.player_position - ctx.position).normalized()
		# Strong light makes it keep its distance without stopping.
		var reluctance: float = 1.0 - clampf(ctx.light_level * 1.3, 0.0, 0.75)
		ctx.desired_velocity = dir * speed * reluctance
		# A slow orbit rather than a straight line. Much more unsettling.
		ctx.desired_velocity += dir.orthogonal() * sin(ctx.time * 0.8) * speed * 0.45
		ctx.state = "stalk"
		return

	_repick_wander(ctx, 2.0, 4.0)
	ctx.desired_velocity = Vector2(
		float(_wander_dir) * speed * 0.35,
		sin(ctx.time * 1.1) * 18.0
	)
	ctx.state = "drift"


## Lumreaper: the Rootlands' apex event. Three phases, on a loop.
##   HUNT       fast passes at the player
##   FLARE      stationary, invulnerable, floods the room with light
##   EXPOSED    crown dim, slow, and the only window to damage it
const APEX_HUNT: int = 0
const APEX_FLARE: int = 1
const APEX_EXPOSED: int = 2

func _tick_apex(ctx: Context) -> void:
	var speed := ctx.data.speed * ctx.variant.speed_mul
	_phase_timer -= ctx.delta

	if _phase_timer <= 0.0:
		match _phase:
			APEX_HUNT:
				_phase = APEX_FLARE
				_phase_timer = 2.6
				ctx.cue = "flare"
			APEX_FLARE:
				_phase = APEX_EXPOSED
				# The window shrinks as it gets hurt, so the fight tightens.
				_phase_timer = lerpf(4.2, 2.4, 1.0 - ctx.hp_ratio)
				ctx.cue = "expose"
			_:
				_phase = APEX_HUNT
				_phase_timer = lerpf(6.0, 4.0, 1.0 - ctx.hp_ratio)
				ctx.cue = "hunt"

	match _phase:
		APEX_HUNT:
			var dir := (ctx.player_position - ctx.position)
			# Aim slightly above the player so the pass sweeps through them.
			dir.y -= 14.0
			ctx.desired_velocity = dir.normalized() * speed * 1.35
			ctx.state = "hunt"
			ctx.invulnerable = false
		APEX_FLARE:
			ctx.desired_velocity = Vector2(0.0, sin(ctx.time * 3.0) * 12.0)
			ctx.state = "flare"
			ctx.invulnerable = true
		_:
			# Exposed: it drifts, dimmed, and can be hit.
			ctx.desired_velocity = Vector2(
				cos(ctx.time * 0.6) * speed * 0.3,
				sin(ctx.time * 0.9) * 16.0
			)
			ctx.state = "exposed"
			ctx.invulnerable = false


func apex_phase() -> int:
	return _phase


func phase_name() -> String:
	match _phase:
		APEX_HUNT: return "HUNTING"
		APEX_FLARE: return "FLARE — SHIELDED"
		APEX_EXPOSED: return "CROWN DIM — VULNERABLE"
	return ""
