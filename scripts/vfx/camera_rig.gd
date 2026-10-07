class_name CameraRig
extends Camera2D
## Follow camera with look-ahead, trauma-based shake, and a depth-reactive
## zoom. Deliberately understated: on a phone the world has to stay readable,
## so the camera leads the player a little and never swings.

const BASE_ZOOM: float = 2.15
## How far ahead of the player, in pixels at full run speed.
const LOOKAHEAD_X: float = 52.0
const LOOKAHEAD_Y: float = 34.0
const FOLLOW_SMOOTH: float = 6.5
const LOOKAHEAD_SMOOTH: float = 2.6
## Trauma decays to zero; shake magnitude is trauma squared, which makes small
## hits subtle and big ones alarming.
const TRAUMA_DECAY: float = 2.2

var target: Node2D = null

var _trauma: float = 0.0
var _lookahead: Vector2 = Vector2.ZERO
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0
var _base_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	zoom = Vector2(BASE_ZOOM, BASE_ZOOM)
	position_smoothing_enabled = false
	_noise.seed = randi()
	_noise.frequency = 0.9
	EventBus.screen_shake_requested.connect(add_trauma)


func configure(p_target: Node2D) -> void:
	target = p_target
	if target != null:
		_base_position = target.global_position
		global_position = _base_position


func add_trauma(strength: float, _duration: float = 0.2) -> void:
	# Duration is implicit in the decay rate; strength just adds trauma.
	_trauma = clampf(_trauma + strength * 0.11, 0.0, 1.0)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var desired := target.global_position + Vector2(0.0, -16.0)

	# Look-ahead from velocity, so descending reveals what is below sooner.
	var vel := Vector2.ZERO
	if target is CharacterBody2D:
		vel = (target as CharacterBody2D).velocity
	var want := Vector2(
		clampf(vel.x / GameConfig.PLAYER_RUN_SPEED, -1.0, 1.0) * LOOKAHEAD_X,
		clampf(vel.y / GameConfig.PLAYER_MAX_FALL, -0.6, 1.0) * LOOKAHEAD_Y
	)
	_lookahead = _lookahead.lerp(want, clampf(delta * LOOKAHEAD_SMOOTH, 0.0, 1.0))

	_base_position = _base_position.lerp(desired + _lookahead, clampf(delta * FOLLOW_SMOOTH, 0.0, 1.0))

	# Shake.
	var offset := Vector2.ZERO
	if _trauma > 0.001:
		_noise_t += delta * 34.0
		var amount: float = _trauma * _trauma * 11.0
		offset = Vector2(
			_noise.get_noise_2d(_noise_t, 0.0),
			_noise.get_noise_2d(0.0, _noise_t)
		) * amount
		_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * delta)

	global_position = _base_position + offset

	# Pull the camera back very slightly in the deep strata so the big caverns
	# read as big.
	var depth := GameConfig.depth_metres(target.global_position)
	var z: float = lerpf(BASE_ZOOM, BASE_ZOOM * 0.92, clampf(depth / 300.0, 0.0, 1.0))
	zoom = zoom.lerp(Vector2(z, z), clampf(delta * 1.2, 0.0, 1.0))


## Centre of the camera's view in world space, excluding shake.
func get_screen_centre() -> Vector2:
	return _base_position


## The world-space rectangle currently visible.
func view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var half := Vector2(vp.x / maxf(zoom.x, 0.01), vp.y / maxf(zoom.y, 0.01)) * 0.5
	return Rect2(_base_position - half, half * 2.0)
