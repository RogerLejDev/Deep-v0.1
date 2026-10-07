extends Node2D
## The pack you dropped when you died.
##
## This is the whole of DEEP's death penalty: half your resources wait for you
## where you fell, visible and collectable, and everything else — tools, gear,
## Codex, depth record — came back with you. It costs a trip, not a run.

const PROP_SHADER: String = "res://shaders/ambient_lit.gdshader"
const COLLECT_RANGE: float = 34.0

var world: DeepWorld = null
var payload: Dictionary = {}

var _sprite: Sprite2D = null
var _light: LightField.Source = null
var _pulse: float = 0.0
var _collected: bool = false


func configure(p_world: DeepWorld, p_payload: Dictionary) -> void:
	world = p_world
	payload = p_payload
	global_position = Vector2(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)))

	_sprite = Sprite2D.new()
	_sprite.texture = SvgFactory.sprite("res://assets/svg/props/chest.svg", 22, 24.0, 1.3, 1.1)
	_sprite.centered = true
	var mat := ShaderMaterial.new()
	mat.shader = load(PROP_SHADER) as Shader
	mat.set_shader_parameter("emission_colour", Vector3(1.0, 0.72, 0.36))
	mat.set_shader_parameter("emission_strength", 0.6)
	mat.set_shader_parameter("squash", Vector2.ONE)
	mat.set_shader_parameter("ambient_floor", 0.25)
	_sprite.material = mat
	add_child(_sprite)
	z_index = 6

	_light = world.lights.add_dynamic(Color(1.0, 0.72, 0.36), 140.0, 0.55)
	_light.position = global_position


func _exit_tree() -> void:
	if _light != null and world != null:
		world.lights.remove_dynamic(_light)
		_light = null


func _process(delta: float) -> void:
	if _collected:
		return
	_pulse += delta
	_sprite.position.y = sin(_pulse * 2.2) * 2.0
	var mat := _sprite.material as ShaderMaterial
	mat.set_shader_parameter("emission_strength", 0.45 + sin(_pulse * 3.1) * 0.22)

	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	if player.global_position.distance_to(global_position) > COLLECT_RANGE:
		return
	_collect()


func _collect() -> void:
	_collected = true
	var recovered := 0
	var remaining: Array = []

	for entry in payload.get("items", []):
		var e: Dictionary = entry
		var id := str(e.get("id", ""))
		var n := int(e.get("n", 0))
		if id.is_empty() or n <= 0:
			continue
		var leftover := Game.inventory.add(id, n)
		var got := n - leftover
		if got > 0:
			recovered += got
			EventBus.item_collected.emit(id, got)
		if leftover > 0:
			remaining.append({"id": id, "n": leftover})

	if not remaining.is_empty():
		# A full pack must not destroy the cache: keep exactly what did not
		# fit and leave the marker standing.
		payload["items"] = remaining
		Game.recovery_cache = payload
		_collected = false
		if recovered > 0:
			EventBus.toast_requested.emit(
				"RECOVERED %d — PACK FULL, CACHE STILL HERE" % recovered, "warn")
		else:
			EventBus.toast_requested.emit("PACK FULL", "warn")
		return

	Game.recovery_cache = {}
	EventBus.toast_requested.emit("RECOVERED %d ITEMS" % recovered, "save")
	Audio.play("discovery", 1.3, -6.0)
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", Vector2(1.5, 0.4), 0.3)
	tw.parallel().tween_property(_sprite, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
