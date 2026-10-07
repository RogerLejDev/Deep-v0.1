class_name PlayerVisual
extends Node2D
## The player character, assembled from four SVG parts and animated entirely in
## code: body, two legs, an arm, and the held tool.
##
## Procedural animation rather than spritesheets because it keeps the art
## budget at four files while still giving distinct idle / walk / run / jump /
## fall / mine states, and because the tool in hand can change colour with the
## equipped pick without new art.

const BODY: String = "res://assets/svg/player/body.svg"
const LEG: String = "res://assets/svg/player/leg.svg"
const ARM: String = "res://assets/svg/player/arm.svg"
const PICK: String = "res://assets/svg/player/pick.svg"
const LIT_SHADER: String = "res://shaders/ambient_lit.gdshader"

const BODY_HEIGHT: int = 30
const LEG_HEIGHT: int = 13
const ARM_HEIGHT: int = 12
const PICK_HEIGHT: int = 18

var facing: int = 1

var _root: Node2D
var _body: Sprite2D
var _leg_back: Sprite2D
var _leg_front: Sprite2D
var _arm: Sprite2D
var _pick: Sprite2D
var _body_mat: ShaderMaterial

var _t: float = 0.0
var _swing: float = 0.0
var _land_squash: float = 0.0
var _hurt_flash: float = 0.0
var _tool_id: String = ""


func _ready() -> void:
	_root = Node2D.new()
	add_child(_root)

	_leg_back = _make_sprite(LEG, LEG_HEIGHT, Vector2(-1.0, 2.0), 0.6)
	_leg_front = _make_sprite(LEG, LEG_HEIGHT, Vector2(2.0, 2.0), 1.0)
	_body = _make_sprite(BODY, BODY_HEIGHT, Vector2(0.0, -9.0), 1.0)
	_pick = _make_sprite(PICK, PICK_HEIGHT, Vector2(6.0, -4.0), 1.0)
	_arm = _make_sprite(ARM, ARM_HEIGHT, Vector2(4.0, -6.0), 1.0)

	# Legs and arm rotate around their attachment point, not their centre.
	_leg_back.offset = Vector2(0.0, LEG_HEIGHT * 0.5)
	_leg_front.offset = Vector2(0.0, LEG_HEIGHT * 0.5)
	_arm.offset = Vector2(0.0, ARM_HEIGHT * 0.5)
	_pick.offset = Vector2(0.0, PICK_HEIGHT * 0.25)

	_body_mat = _body.material as ShaderMaterial
	EventBus.active_tool_changed.connect(_on_tool_changed)
	_apply_tool(Game.active_tool)


func _make_sprite(path: String, height: int, offset: Vector2, dim: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = SvgFactory.sprite(path, height)
	s.centered = true
	s.position = offset
	var mat := ShaderMaterial.new()
	mat.shader = load(LIT_SHADER) as Shader
	mat.set_shader_parameter("tint", Color(dim, dim, dim, 1.0))
	mat.set_shader_parameter("squash", Vector2.ONE)
	# The avatar must stay readable at any depth.
	mat.set_shader_parameter("ambient_floor", 0.30)
	s.material = mat
	_root.add_child(s)
	return s


func _on_tool_changed(id: String) -> void:
	_apply_tool(id)


## The held pick is recoloured to the equipped tool's palette, so progression
## is visible on the character without extra art.
func _apply_tool(id: String) -> void:
	if id == _tool_id:
		return
	_tool_id = id
	var def := ItemDB.get_item(id)
	var hue := 0.0
	var sat := 1.0
	var val := 1.0
	match id:
		"pick_copper":
			hue = -18.0
			sat = 1.5
			val = 1.05
		"pick_iron":
			hue = 0.0
			sat = 0.25
			val = 1.15
		"pick_crystal":
			hue = 150.0
			sat = 1.3
			val = 1.2
		_:
			hue = 12.0
			sat = 0.7
			val = 0.85
	_pick.texture = SvgFactory.sprite(PICK, PICK_HEIGHT, hue, sat, val)
	var glow := def.icon_glow
	var mat := _pick.material as ShaderMaterial
	if glow.a > 0.0 and (glow.r + glow.g + glow.b) > 0.1:
		mat.set_shader_parameter("emission_colour", Vector3(glow.r, glow.g, glow.b))
		mat.set_shader_parameter("emission_strength", 0.30)
	else:
		mat.set_shader_parameter("emission_strength", 0.0)


# --- Animation ---------------------------------------------------------------

## `state` is one of: idle, walk, run, jump, fall, mine.
func animate(
	delta: float,
	state: String,
	velocity: Vector2,
	p_facing: int,
	mining: bool
) -> void:
	_t += delta
	facing = p_facing
	_root.scale.x = -1.0 if facing < 0 else 1.0
	_land_squash = maxf(0.0, _land_squash - delta * 4.0)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 3.2)

	var speed_ratio: float = clampf(absf(velocity.x) / GameConfig.PLAYER_RUN_SPEED, 0.0, 1.4)
	var stride: float = 9.0 + speed_ratio * 7.0
	var leg_swing: float = 0.0
	var bob: float = 0.0

	match state:
		"walk", "run":
			leg_swing = sin(_t * stride) * (0.42 + speed_ratio * 0.38)
			bob = absf(sin(_t * stride)) * (1.1 + speed_ratio * 1.4)
		"jump":
			leg_swing = -0.55
			bob = -1.4
		"fall":
			leg_swing = 0.38
			bob = 0.8
		_:
			# Idle: a slow breathing bob and a barely-there weight shift.
			leg_swing = sin(_t * 1.4) * 0.05
			bob = sin(_t * 1.9) * 0.55

	_leg_front.rotation = leg_swing
	_leg_back.rotation = -leg_swing * 0.9
	_body.position.y = -9.0 + bob * 0.4
	_body.rotation = lerp_angle(_body.rotation, speed_ratio * 0.09, clampf(delta * 8.0, 0.0, 1.0))

	# Mining swing: wind up behind the shoulder, then chop through.
	if mining:
		_swing += delta * 7.5
		var phase: float = fposmod(_swing, TAU)
		var chop: float = -0.9 + (1.0 - cos(phase)) * 1.25
		_arm.rotation = chop
		_pick.rotation = chop * 1.15 + 0.5
		_pick.position = Vector2(6.0, -4.0) + Vector2(cos(chop) * 4.0, sin(chop) * 4.0)
		_pick.visible = true
	else:
		_swing = 0.0
		var rest: float = leg_swing * -0.45
		_arm.rotation = lerp_angle(_arm.rotation, rest, clampf(delta * 10.0, 0.0, 1.0))
		_pick.rotation = lerp_angle(_pick.rotation, 0.55 + rest, clampf(delta * 10.0, 0.0, 1.0))
		_pick.position = _pick.position.lerp(Vector2(6.0, -4.0), clampf(delta * 10.0, 0.0, 1.0))

	# Landing squash and hurt flash ride on the body only.
	var squash := Vector2(1.0 + _land_squash * 0.22, 1.0 - _land_squash * 0.24)
	if state == "jump":
		squash = Vector2(0.94, 1.08)
	_body_mat.set_shader_parameter("squash", squash)
	_body_mat.set_shader_parameter("flash", _hurt_flash * 0.8)


func note_landing(impact_ratio: float) -> void:
	_land_squash = clampf(impact_ratio, 0.2, 1.0)


func note_hurt() -> void:
	_hurt_flash = 1.0
