class_name BaseCamp
extends Node2D
## The surface base: a workbench, a storage chest, a save beacon, and an
## inscription slab that opens the story.
##
## The camp is *built into the world* rather than floated on top of it: it
## levels a platform of placed planks, which are ordinary player-modification
## tiles. That means it survives regeneration, the player can extend it with
## their own blocks, and nothing about it is a special case for the renderer.

const PROP_SHADER: String = "res://shaders/ambient_lit.gdshader"
const INTERACT_RANGE: float = 46.0
const PLATFORM_HALF_WIDTH: int = 9

signal station_triggered(station: String)

var world: DeepWorld = null
var anchor: Vector2 = Vector2.ZERO

var _stations: Array[Dictionary] = []
var _current: String = ""
var _light: LightField.Source = null
var _beacon_sprite: Sprite2D = null
var _pulse: float = 0.0


func configure(p_world: DeepWorld) -> void:
	world = p_world
	var spawn := p_world.spawn_position()
	var tile := GameConfig.world_to_tile(spawn)
	_level_platform(tile)
	anchor = GameConfig.tile_centre(tile.x, tile.y + 2)
	global_position = Vector2.ZERO
	_build_props(tile)
	_build_light()


## Flatten and floor the spawn shelf so the camp always sits on solid ground.
func _level_platform(centre: Vector2i) -> void:
	var ground := centre.y + 3
	for dx in range(-PLATFORM_HALF_WIDTH, PLATFORM_HALF_WIDTH + 1):
		var tx := centre.x + dx
		# Clear headroom.
		for dy in range(-4, 3):
			var ty := ground + dy
			if BlockDB.is_solid(world.get_tile(tx, ty)):
				world.set_tile(tx, ty, BlockDB.AIR, false)
		# Lay a plank deck, and fill under it so nothing can fall through.
		world.set_tile(tx, ground, BlockDB.PLANK, false)
		if not BlockDB.is_solid(world.get_tile(tx, ground + 1)):
			world.set_tile(tx, ground + 1, BlockDB.DIRT, false)


func _build_props(centre: Vector2i) -> void:
	var ground_y := float(centre.y + 3) * GameConfig.TILE_SIZE

	_stations = []
	_add_prop("res://assets/svg/props/workbench.svg", 32,
		Vector2(float(centre.x - 5) * GameConfig.TILE_SIZE, ground_y - 16.0),
		"workbench", "CRAFT AT THE WORKBENCH")
	_add_prop("res://assets/svg/props/chest.svg", 26,
		Vector2(float(centre.x - 1) * GameConfig.TILE_SIZE, ground_y - 13.0),
		"chest", "OPEN THE CHEST")
	_beacon_sprite = _add_prop("res://assets/svg/props/beacon.svg", 44,
		Vector2(float(centre.x + 3) * GameConfig.TILE_SIZE, ground_y - 22.0),
		"beacon", "SAVE AND REST")
	_add_prop("res://assets/svg/props/sign.svg", 30,
		Vector2(float(centre.x + 7) * GameConfig.TILE_SIZE, ground_y - 15.0),
		"sign", "READ THE SLAB")


func _add_prop(
	art: String,
	height: int,
	position: Vector2,
	station: String,
	prompt: String
) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = SvgFactory.sprite(art, height)
	s.centered = true
	s.position = position
	s.z_index = 5
	var mat := ShaderMaterial.new()
	mat.shader = load(PROP_SHADER) as Shader
	mat.set_shader_parameter("squash", Vector2.ONE)
	mat.set_shader_parameter("ambient_floor", 0.22)
	if station == "beacon":
		mat.set_shader_parameter("emission_colour", Vector3(0.42, 0.82, 1.0))
		mat.set_shader_parameter("emission_strength", 0.55)
	elif station == "workbench":
		mat.set_shader_parameter("emission_colour", Vector3(1.0, 0.78, 0.45))
		mat.set_shader_parameter("emission_strength", 0.18)
	elif station == "sign":
		mat.set_shader_parameter("emission_colour", Vector3(0.35, 0.86, 0.78))
		mat.set_shader_parameter("emission_strength", 0.22)
	s.material = mat
	add_child(s)
	_stations.append({"station": station, "position": position, "prompt": prompt, "node": s})
	return s


func _build_light() -> void:
	if world == null:
		return
	_light = world.lights.add_dynamic(Color(1.0, 0.86, 0.62), 230.0, 0.62)
	# Centre the camp light on the beacon.
	if _beacon_sprite != null:
		_light.position = _beacon_sprite.position
	else:
		_light.position = anchor


func _exit_tree() -> void:
	if _light != null and world != null:
		world.lights.remove_dynamic(_light)
		_light = null


# --- Interaction -------------------------------------------------------------

func _process(delta: float) -> void:
	_pulse += delta
	if _beacon_sprite != null:
		# A slow breathe on the beacon so the base reads as "alive" from afar.
		var mat := _beacon_sprite.material as ShaderMaterial
		mat.set_shader_parameter("emission_strength", 0.45 + sin(_pulse * 1.4) * 0.14)

	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var nearest := ""
	var nearest_prompt := ""
	var best := INTERACT_RANGE
	for s in _stations:
		var d: float = player.global_position.distance_to(s["position"] as Vector2)
		if d < best:
			best = d
			nearest = str(s["station"])
			nearest_prompt = str(s["prompt"])

	if nearest != _current:
		_current = nearest
		EventBus.interact_prompt_changed.emit(
			"" if nearest.is_empty() else nearest_prompt + "   [ ✦ ]")

	if not _current.is_empty() and Input.is_action_just_pressed("interact"):
		station_triggered.emit(_current)


func current_station() -> String:
	return _current


func spawn_point() -> Vector2:
	return anchor + Vector2(0.0, -8.0)
