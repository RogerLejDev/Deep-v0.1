class_name Player
extends CharacterBody2D
## The player: movement, health, death/recovery, and the lantern light.
##
## Input arrives through an abstraction (`move_axis`, `jump_pressed`, …) that
## TouchControls and the keyboard both write to, so the same code runs on a
## phone and on a desktop test build.

const MAX_HEALTH: float = 100.0
const INVULN_SECONDS: float = 0.75
## Share of each *resource* stack left behind on death. Tools and gear are
## never dropped.
const DEATH_DROP_SHARE: float = 0.5

var health: float = MAX_HEALTH
var facing: int = 1
var mining: bool = false

# --- Input surface, written by TouchControls / keyboard ----------------------
var move_axis: float = 0.0
var want_jump: bool = false
var want_run: bool = false

var visual: PlayerVisual = null
var mining_controller: Node = null

var _world: DeepWorld = null
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _invuln: float = 0.0
var _was_on_floor: bool = true
var _peak_fall: float = 0.0
var _light: LightField.Source = null
var _last_depth_report: float = -99999.0
var _state: String = "idle"
var _dead: bool = false
var _step_accum: float = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	floor_snap_length = 6.0
	# A shallow max slope keeps the player from climbing vertical tunnel walls.
	floor_max_angle = deg_to_rad(46.0)

	var shape := CollisionShape2D.new()
	var caps := CapsuleShape2D.new()
	caps.radius = 5.0
	caps.height = 26.0
	shape.shape = caps
	shape.position = Vector2(0.0, -13.0)
	add_child(shape)

	visual = PlayerVisual.new()
	visual.name = "Visual"
	add_child(visual)

	mining_controller = preload("res://scripts/player/mining_controller.gd").new()
	mining_controller.name = "MiningController"
	add_child(mining_controller)


func configure(p_world: DeepWorld) -> void:
	_world = p_world
	_light = p_world.lights.add_dynamic(Game.light_colour(), Game.light_radius(), 0.95)
	_light.position = global_position
	mining_controller.call("configure", p_world, self)
	Game.player = self
	EventBus.player_spawned.emit(self)
	EventBus.player_health_changed.emit(health, MAX_HEALTH)


func _exit_tree() -> void:
	if _light != null and _world != null:
		_world.lights.remove_dynamic(_light)
		_light = null
	if Game.player == self:
		Game.player = null


# --- Movement ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_read_keyboard()
	_invuln = maxf(0.0, _invuln - delta)

	var on_floor := is_on_floor()
	if on_floor:
		_coyote = GameConfig.COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - delta)

	if want_jump:
		_jump_buffer = GameConfig.JUMP_BUFFER
		want_jump = false
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

	_apply_horizontal(delta, on_floor)
	_apply_vertical(delta, on_floor)

	var before := velocity.y
	move_and_slide()
	_handle_landing(on_floor, before)

	_update_state(on_floor)
	_update_light()
	_report_depth()
	_footsteps(delta, on_floor)

	visual.animate(delta, _state, velocity, facing, mining)


func _read_keyboard() -> void:
	# Keyboard is additive on top of whatever the touch stick wrote, so a
	# desktop test build and a phone build share one code path.
	var kb := Input.get_axis("move_left", "move_right")
	if absf(kb) > 0.01:
		move_axis = kb
		want_run = true
	if Input.is_action_just_pressed("jump"):
		want_jump = true


func _apply_horizontal(delta: float, on_floor: bool) -> void:
	var axis: float = clampf(move_axis, -1.0, 1.0)
	var top_speed: float = GameConfig.PLAYER_RUN_SPEED if want_run else GameConfig.PLAYER_WALK_SPEED
	# An analogue stick at half deflection should walk, not run.
	top_speed = lerpf(GameConfig.PLAYER_WALK_SPEED, top_speed, clampf(absf(axis) * 1.25, 0.0, 1.0))
	var target := axis * top_speed
	var control: float = 1.0 if on_floor else GameConfig.PLAYER_AIR_CONTROL
	if absf(axis) > 0.05:
		velocity.x = move_toward(velocity.x, target, GameConfig.PLAYER_ACCEL * control * delta)
		facing = signi(int(axis * 100.0))
	else:
		velocity.x = move_toward(velocity.x, 0.0, GameConfig.PLAYER_FRICTION * control * delta)
	move_axis = 0.0
	want_run = false


func _apply_vertical(delta: float, _on_floor: bool) -> void:
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = GameConfig.PLAYER_JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		Audio.play("jump", randf_range(0.95, 1.1), -10.0)
	var gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 1100.0))
	# Shorter rise when the jump is released early would need a hold flag; the
	# fixed arc here is deliberate so touch taps feel identical every time.
	velocity.y = minf(velocity.y + gravity * delta, GameConfig.PLAYER_MAX_FALL)
	_peak_fall = maxf(_peak_fall, velocity.y)


func _handle_landing(was_on_floor: bool, impact_speed: float) -> void:
	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor:
		var ratio: float = clampf(impact_speed / GameConfig.PLAYER_MAX_FALL, 0.0, 1.0)
		visual.note_landing(ratio)
		Audio.play("land", 1.0 - ratio * 0.2, -14.0 + ratio * 8.0)
		if ratio > 0.1:
			EventBus.screen_shake_requested.emit(ratio * 3.2, 0.12)
		if _peak_fall > GameConfig.FALL_DAMAGE_THRESHOLD:
			var over := _peak_fall - GameConfig.FALL_DAMAGE_THRESHOLD
			take_damage(over * 0.22, "the fall", global_position)
		_peak_fall = 0.0
	if not now_on_floor and was_on_floor:
		_peak_fall = maxf(_peak_fall, 0.0)
	_was_on_floor = now_on_floor


func _update_state(on_floor: bool) -> void:
	if not on_floor:
		_state = "jump" if velocity.y < -10.0 else "fall"
	elif absf(velocity.x) > GameConfig.PLAYER_WALK_SPEED * 1.05:
		_state = "run"
	elif absf(velocity.x) > 6.0:
		_state = "walk"
	else:
		_state = "idle"


func _update_light() -> void:
	if _light == null:
		return
	_light.position = global_position + Vector2(0.0, -14.0)
	_light.radius = Game.light_radius()
	_light.colour = Game.light_colour()


func _report_depth() -> void:
	var d := GameConfig.depth_metres(global_position)
	if absf(d - _last_depth_report) < 0.25:
		return
	_last_depth_report = d
	EventBus.player_depth_changed.emit(d)
	var zone := BiomeTable.zone_for_depth(d)
	if not Game.has_zone(zone.id):
		Game.note_zone(zone.id)
		EventBus.biome_changed.emit(zone.id)


func _footsteps(delta: float, on_floor: bool) -> void:
	if not on_floor or absf(velocity.x) < 20.0:
		_step_accum = 0.0
		return
	_step_accum += delta * absf(velocity.x) * 0.012
	if _step_accum >= 1.0:
		_step_accum = 0.0
		Audio.play("pick_tap", randf_range(0.5, 0.65), -22.0)


# --- Health ------------------------------------------------------------------

func get_health() -> float:
	return health


func set_health(value: float) -> void:
	health = clampf(value, 0.0, MAX_HEALTH)
	EventBus.player_health_changed.emit(health, MAX_HEALTH)


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	set_health(health + amount)
	EventBus.toast_requested.emit("+%d VITALITY" % int(amount), "heal")


func take_damage(amount: float, source: String = "", from: Vector2 = Vector2.ZERO) -> void:
	if _dead or amount <= 0.0 or _invuln > 0.0:
		return
	_invuln = INVULN_SECONDS
	health = maxf(0.0, health - amount)
	visual.note_hurt()
	EventBus.player_health_changed.emit(health, MAX_HEALTH)
	EventBus.player_damaged.emit(amount, source)
	EventBus.screen_shake_requested.emit(clampf(amount * 0.35, 1.5, 7.0), 0.22)
	# Knock the player away from the source so contact damage is escapable.
	if from != Vector2.ZERO:
		var away := (global_position - from).normalized()
		velocity = Vector2(away.x * 150.0, -170.0)
	if health <= 0.0:
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	mining = false
	velocity = Vector2.ZERO
	Game.bump_stat("deaths")
	_cache_dropped_items()
	EventBus.player_died.emit()
	Audio.play("hurt", 0.6, 0.0)
	EventBus.screen_shake_requested.emit(9.0, 0.6)


## The expedition risk: half of every resource stack stays where you fell, in a
## cache you can walk back and collect. Tools, gear and all progression are
## kept, so a death costs you a trip rather than your run.
func _cache_dropped_items() -> void:
	var dropped: Array[Dictionary] = []
	for i in Game.inventory.slots.size():
		var id := Game.inventory.item_at(i)
		if id.is_empty():
			continue
		var def := ItemDB.get_item(id)
		if def.category == ItemDef.Category.TOOL or def.category == ItemDef.Category.GEAR:
			continue
		var n := Game.inventory.count_at(i)
		var take: int = int(floor(float(n) * DEATH_DROP_SHARE))
		if take <= 0:
			continue
		Game.inventory.remove_at(i, take)
		dropped.append({"id": id, "n": take})
	if dropped.is_empty():
		Game.recovery_cache = {}
		return
	Game.recovery_cache = {
		"x": global_position.x,
		"y": global_position.y,
		"items": dropped,
		"depth": GameConfig.depth_metres(global_position),
	}


func respawn_at(position: Vector2) -> void:
	_dead = false
	health = MAX_HEALTH
	velocity = Vector2.ZERO
	global_position = position
	_invuln = 1.5
	_peak_fall = 0.0
	_was_on_floor = true
	set_physics_process(true)
	EventBus.player_health_changed.emit(health, MAX_HEALTH)
	EventBus.player_respawned.emit()


func is_dead() -> bool:
	return _dead


func state_name() -> String:
	return _state


func depth_metres() -> float:
	return GameConfig.depth_metres(global_position)
