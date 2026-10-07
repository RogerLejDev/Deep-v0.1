class_name Creature
extends CharacterBody2D
## A live creature: body, procedurally animated visual, health, and the glue
## between CreatureBrain's decisions and the physics world.
##
## All art is one recoloured SVG sprite. Everything that makes it feel alive —
## breathing, leaning into a run, tendril sway, the hurt flinch — is code
## driving the sprite's squash uniform and rotation, which is why six species
## cost six image files and no animation data.

signal died(creature: Creature)

const GRAVITY: float = 820.0
const MAX_FALL: float = 560.0
const CONTACT_COOLDOWN: float = 0.85
const LIT_SHADER: String = "res://shaders/ambient_lit.gdshader"

var data: CreatureData = null
var variant: CreatureVariant = null
var species_id: String = ""
var variant_id: String = "normal"

var max_hp: float = 20.0
var hp: float = 20.0
var home: Vector2 = Vector2.ZERO
var is_event_spawn: bool = false
var sleeping: bool = false

var _brain: CreatureBrain = null
var _ctx: CreatureBrain.Context = null
var _world: DeepWorld = null
var _sprite: Sprite2D = null
var _shape: CollisionShape2D = null
var _material: ShaderMaterial = null
var _light: LightField.Source = null
var _contact_timer: float = 0.0
var _flash: float = 0.0
var _anim_time: float = 0.0
var _facing: int = 1
var _dead: bool = false
var _mine_progress: float = 0.0
var _mine_tile: Vector2i = Vector2i(-1, -1)
var _health_bar_alpha: float = 0.0
## Observation accumulates while the player can see this creature.
var observed_seconds: float = 0.0
var sighted: bool = false


func setup(
	p_data: CreatureData,
	p_variant: CreatureVariant,
	p_world: DeepWorld,
	spawn_seed: int
) -> void:
	data = p_data
	variant = p_variant
	species_id = data.id
	variant_id = variant.id
	_world = p_world
	_brain = CreatureBrain.new(spawn_seed)
	_ctx = CreatureBrain.Context.new()
	_ctx.data = data
	_ctx.variant = variant

	max_hp = data.hp * variant.hp_mul
	hp = max_hp
	home = global_position

	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED if not data.floats else CharacterBody2D.MOTION_MODE_FLOATING

	_build_visual()
	_build_body()
	_build_light()


func _build_visual() -> void:
	var height: int = maxi(4, int(round(float(data.size_px) * variant.scale_mul)))
	var tex := SvgFactory.sprite(
		data.art_path, height,
		variant.hue_shift, variant.saturation, variant.value, variant.overlay
	)
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.centered = true
	add_child(_sprite)

	_material = ShaderMaterial.new()
	_material.shader = load(LIT_SHADER) as Shader
	var em := data.light_colour * data.light_intensity * variant.emission_mul
	_material.set_shader_parameter("emission_colour", Vector3(em.r, em.g, em.b))
	_material.set_shader_parameter("emission_strength", clampf(data.light_intensity * variant.emission_mul, 0.0, 2.0))
	_material.set_shader_parameter("tint", Color.WHITE)
	_material.set_shader_parameter("squash", Vector2.ONE)
	# Enough self-visibility to read a shape in an unlit cave — the "what was
	# that?" moment — but not enough to identify one without light.
	_material.set_shader_parameter("ambient_floor", 0.15)
	_sprite.material = _material


func _build_body() -> void:
	var h: float = float(data.size_px) * variant.scale_mul
	_shape = CollisionShape2D.new()
	var box := RectangleShape2D.new()
	# Slightly narrower than the art so creatures slip through their own
	# tunnels instead of catching on corners.
	box.size = Vector2(h * 0.62, h * 0.80)
	_shape.shape = box
	add_child(_shape)


func _build_light() -> void:
	if data.light_radius <= 0.0 or _world == null:
		return
	var intensity: float = clampf(data.light_intensity * variant.emission_mul, 0.0, 1.0)
	_light = _world.lights.add_dynamic(data.light_colour, data.light_radius * variant.scale_mul, intensity)
	_light.position = global_position


func _exit_tree() -> void:
	if _light != null and _world != null:
		_world.lights.remove_dynamic(_light)
		_light = null


# --- Simulation --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _world == null or data == null:
		return

	var player := Game.player
	var player_pos: Vector2 = player.global_position if player != null and is_instance_valid(player) else global_position
	var dist := global_position.distance_to(player_pos)

	# Far-away creatures stop thinking entirely. This is the single biggest
	# mobile saving: twenty creatures, only the near ones simulated.
	sleeping = dist > GameConfig.CREATURE_SLEEP_DISTANCE
	if sleeping:
		velocity = Vector2.ZERO
		if _light != null:
			_light.enabled = false
		return
	if _light != null:
		_light.enabled = true

	_anim_time += delta
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_flash = maxf(0.0, _flash - delta * 5.0)

	_fill_context(delta, player_pos, dist)
	_brain.tick(_ctx)
	_consume_cue()
	_apply_motion(delta)
	_handle_digging(delta)
	_handle_contact(player, dist)
	_animate(delta)

	if _light != null:
		_light.position = global_position
		# The Lumreaper's flare is a light event, not just a colour change.
		if data.behaviour == "apex":
			var boost := 2.1 if _ctx.state == "flare" else (0.35 if _ctx.state == "exposed" else 1.0)
			_light.intensity = clampf(data.light_intensity * variant.emission_mul * boost, 0.0, 1.4)
			_light.radius = data.light_radius * variant.scale_mul * (1.5 if _ctx.state == "flare" else 1.0)


func _fill_context(delta: float, player_pos: Vector2, dist: float) -> void:
	_ctx.position = global_position
	_ctx.home = home
	_ctx.player_position = player_pos
	_ctx.player_distance = dist
	_ctx.player_visible = dist < 620.0
	_ctx.on_floor = is_on_floor() if not data.floats else true
	_ctx.hp_ratio = hp / maxf(max_hp, 1.0)
	_ctx.delta = delta
	_ctx.time = _anim_time
	_ctx.light_level = _light_level_here()
	_ctx.desired_velocity = Vector2.ZERO
	_ctx.want_jump = false
	_ctx.mine_tile = Vector2i(-1, -1)
	_ctx.invulnerable = false
	_ctx.cue = ""

	var ahead := Vector2(float(_facing) * (float(data.size_px) * 0.55 + 6.0), 0.0)
	_ctx.blocked_ahead = _world.is_solid_at(global_position + ahead)
	# A ledge is open ground ahead *and* nothing to stand on beyond it.
	_ctx.ledge_ahead = (
		not data.floats
		and not _ctx.blocked_ahead
		and not _world.is_solid_at(global_position + ahead + Vector2(0.0, float(data.size_px) * 0.6 + 14.0))
	)


## Rough estimate of how lit this creature's position is, used by light-averse
## behaviours. Based on the player's lantern plus nearby emissive tiles.
func _light_level_here() -> float:
	var level := 0.0
	var player := Game.player
	if player != null and is_instance_valid(player):
		var r := Game.light_radius()
		var d := global_position.distance_to(player.global_position)
		level += clampf(1.0 - d / maxf(r, 1.0), 0.0, 1.0)
	var t := GameConfig.world_to_tile(global_position)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var def := BlockDB.get_block(_world.get_tile(t.x + dx, t.y + dy))
			if def.emission > 0.3:
				level += 0.22
	return clampf(level, 0.0, 1.0)


func _apply_motion(delta: float) -> void:
	if data.floats:
		velocity = velocity.lerp(_ctx.desired_velocity, clampf(delta * 3.4, 0.0, 1.0))
	else:
		velocity.x = move_toward(velocity.x, _ctx.desired_velocity.x, 900.0 * delta)
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
		if _ctx.want_jump and is_on_floor() and data.jump_velocity > 0.0:
			velocity.y = -data.jump_velocity
	move_and_slide()

	if absf(velocity.x) > 2.0:
		_facing = signi(int(velocity.x))

	# Floating creatures must not sink into rock if they get pushed.
	if data.floats and _world.is_solid_at(global_position):
		var open := _world.find_open_ground(GameConfig.world_to_tile(global_position), 6)
		if open.x >= 0:
			global_position = GameConfig.tile_centre(open.x, open.y - 1)


func _handle_digging(delta: float) -> void:
	if _ctx.mine_tile.x < 0:
		_mine_progress = 0.0
		_mine_tile = Vector2i(-1, -1)
		return
	if _ctx.mine_tile != _mine_tile:
		_mine_tile = _ctx.mine_tile
		_mine_progress = 0.0
	var id := _world.get_tile(_mine_tile.x, _mine_tile.y)
	var def := BlockDB.get_block(id)
	# A Molo only eats soft material; it cannot chew crystal or masonry.
	if def.unbreakable or def.hardness > 1.0 or not def.solid:
		_mine_progress = 0.0
		return
	_mine_progress += delta
	if _mine_progress >= def.hardness * 2.2:
		_mine_progress = 0.0
		# Creature-made holes are natural, so ecology may heal them later.
		_world.set_tile(_mine_tile.x, _mine_tile.y, BlockDB.AIR, true)
		EventBus.block_mined.emit(_mine_tile, id, false)


func _handle_contact(player: Node2D, dist: float) -> void:
	if data.damage <= 0.0 or player == null or not is_instance_valid(player):
		return
	var reach: float = float(data.size_px) * variant.scale_mul * 0.5 + 12.0
	if dist > reach or _contact_timer > 0.0:
		return
	if not player.has_method("take_damage"):
		return
	_contact_timer = CONTACT_COOLDOWN
	var dmg: float = data.damage * variant.damage_mul
	player.call("take_damage", dmg, data.display_name, global_position)


# --- Procedural animation ----------------------------------------------------

func _animate(delta: float) -> void:
	if _sprite == null:
		return
	_sprite.scale.x = -absf(_sprite.scale.x) if _facing < 0 else absf(_sprite.scale.x)

	var moving: float = clampf(absf(velocity.x) / maxf(data.speed, 1.0), 0.0, 1.6)
	var squash := Vector2.ONE
	var rot := 0.0

	match data.behaviour:
		"drifter", "phantom", "apex":
			# Bell pulse: wide-and-short, then tall-and-thin.
			var pulse: float = sin(_anim_time * 2.6) * 0.09
			squash = Vector2(1.0 - pulse, 1.0 + pulse)
			rot = sin(_anim_time * 1.3) * 0.08 + velocity.x * 0.0006
		"burrower":
			var waddle: float = sin(_anim_time * 7.0) * 0.05 * moving
			squash = Vector2(1.0 + waddle, 1.0 - waddle)
			rot = sin(_anim_time * 7.0) * 0.05 * moving
			if _ctx.state == "dig":
				rot += sin(_anim_time * 24.0) * 0.12
		_:
			# Ground gait: a bounce, plus a lean into the direction of travel.
			var bounce: float = absf(sin(_anim_time * (7.0 + moving * 6.0))) * 0.10 * moving
			squash = Vector2(1.0 - bounce * 0.6, 1.0 + bounce)
			rot = float(_facing) * moving * 0.10
			if not is_on_floor():
				squash = Vector2(0.92, 1.12)

	# Hurt flinch overrides the gait.
	if _flash > 0.01:
		var f := _flash
		squash = squash.lerp(Vector2(1.22, 0.80), f)

	_material.set_shader_parameter("squash", squash)
	_sprite.rotation = lerp_angle(_sprite.rotation, rot, clampf(delta * 11.0, 0.0, 1.0))
	_material.set_shader_parameter("flash", _flash * 0.75)
	_material.set_shader_parameter("dissolve", _ctx.dissolve)

	if _health_bar_alpha > 0.0:
		_health_bar_alpha = maxf(0.0, _health_bar_alpha - delta * 0.4)
		queue_redraw()


func _consume_cue() -> void:
	match _ctx.cue:
		"chirp":
			Audio.play("creature_chirp", 1.0 + randf_range(-0.2, 0.2), -14.0)
		"fade":
			EventBus.screen_shake_requested.emit(1.5, 0.15)
		"relocate":
			_relocate()
		"flare":
			EventBus.screen_shake_requested.emit(4.0, 0.4)
			Audio.play("crystal_break", 0.6, -2.0)
		"expose":
			Audio.play("rock_break", 0.7, -6.0)
		"hunt":
			EventBus.screen_shake_requested.emit(2.5, 0.25)


## Phantom reappearance: somewhere nearby, out of the player's immediate line.
func _relocate() -> void:
	var t := GameConfig.world_to_tile(global_position)
	for _attempt in 12:
		var offset := Vector2i(randi_range(-14, 14), randi_range(-8, 8))
		var candidate := t + offset
		if not GameConfig.in_bounds(candidate.x, candidate.y):
			continue
		if BlockDB.is_solid(_world.get_tile(candidate.x, candidate.y)):
			continue
		global_position = GameConfig.tile_centre(candidate.x, candidate.y)
		hp = maxf(hp, max_hp * 0.66)
		return


# --- Damage ------------------------------------------------------------------

func take_damage(amount: float, _source: String = "player") -> void:
	if _dead or _ctx == null:
		return
	if _ctx.invulnerable:
		EventBus.toast_requested.emit("SHIELDED", "warn")
		Audio.play("ui_click", 0.6, -8.0)
		return
	hp -= amount
	_flash = 1.0
	_health_bar_alpha = 1.6
	queue_redraw()
	Audio.play("hurt", 1.4, -12.0)
	if hp <= 0.0:
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	_drop_loot()
	Game.codex.note_defeat(species_id)
	Game.bump_stat("creatures_defeated")
	if _world != null:
		_world.ecology.note_kill(GameConfig.world_to_tile(global_position), species_id)
	EventBus.creature_defeated.emit(species_id, variant_id)
	if variant.legendary:
		Game.note_boss(species_id)
		Game.note_story("defeated_" + species_id)
		EventBus.toast_requested.emit(data.display_name.to_upper() + " DRIVEN OFF", "legendary")
		EventBus.screen_shake_requested.emit(8.0, 0.7)
	died.emit(self)
	_death_effect()


func _death_effect() -> void:
	set_physics_process(false)
	if _shape != null:
		_shape.disabled = true
	if _light != null:
		_light.enabled = false
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		if _material != null:
			_material.set_shader_parameter("dissolve", v)
			_material.set_shader_parameter("flash", 1.0 - v)
		, 0.0, 1.0, 0.45)
	tw.parallel().tween_property(self, "scale", Vector2(1.25, 0.65), 0.45)
	tw.tween_callback(queue_free)


func _drop_loot() -> void:
	var rolls: int = 1 + variant.loot_bonus
	var granted: Dictionary = {}
	for _i in rolls:
		for entry in data.loot:
			if randf() > float(entry["chance"]):
				continue
			var n := randi_range(int(entry["min"]), int(entry["max"]))
			if n <= 0:
				continue
			var item := str(entry["item"])
			granted[item] = int(granted.get(item, 0)) + n
	for item: String in granted.keys():
		var leftover := Game.inventory.add(item, int(granted[item]))
		var got: int = int(granted[item]) - leftover
		if got > 0:
			EventBus.item_collected.emit(item, got)


# --- Health bar --------------------------------------------------------------

func _draw() -> void:
	if _health_bar_alpha <= 0.01 or _dead:
		return
	var w: float = maxf(18.0, float(data.size_px) * variant.scale_mul * 0.9)
	var y: float = -float(data.size_px) * variant.scale_mul * 0.62 - 6.0
	var a: float = clampf(_health_bar_alpha, 0.0, 1.0)
	var ratio: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(-w * 0.5 - 1.0, y - 1.0, w + 2.0, 4.0), Color(0, 0, 0, 0.55 * a))
	var col := Color(0.86, 0.32, 0.30, a) if ratio < 0.4 else Color(0.74, 0.86, 0.42, a)
	draw_rect(Rect2(-w * 0.5, y, w * ratio, 2.0), col)


# --- Observation -------------------------------------------------------------

## Called by ObservationTracker while this creature is visible on screen.
func accumulate_observation(delta: float) -> void:
	if _dead:
		return
	observed_seconds += delta
	Game.codex.add_observation(species_id, delta)


func brain_state() -> String:
	return _ctx.state if _ctx != null else "-"


func apex_phase_name() -> String:
	if _brain == null or data == null or data.behaviour != "apex":
		return ""
	return _brain.phase_name()


func is_boss() -> bool:
	return data != null and data.behaviour == "apex"


func hp_ratio() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
