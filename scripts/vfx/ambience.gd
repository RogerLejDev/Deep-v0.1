class_name Ambience
extends Node
## Drives everything that makes depth *feel* different: the global ambient
## light every lit shader multiplies by, the parallax backdrop, the depth haze,
## and which ambience loop is playing.
##
## One node owns all of it so the surface-to-deep transition is a single
## interpolation rather than five systems guessing independently.

const BACKDROP_SHADER: String = "res://shaders/backdrop.gdshader"
const HAZE_SHADER: String = "res://shaders/haze.gdshader"

var camera: CameraRig = null

var _backdrop_layer: CanvasLayer
var _backdrop: ColorRect
var _backdrop_mat: ShaderMaterial
var _haze_layer: CanvasLayer
var _haze: ColorRect
var _haze_mat: ShaderMaterial
var _drift: float = 0.0
var _ambient: Color = Color.WHITE
var _current_cue: String = ""


func _ready() -> void:
	_backdrop_layer = CanvasLayer.new()
	_backdrop_layer.layer = -10
	add_child(_backdrop_layer)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = load(BACKDROP_SHADER) as Shader
	_backdrop.material = _backdrop_mat
	_backdrop_layer.add_child(_backdrop)

	_haze_layer = CanvasLayer.new()
	# Above the world, below every piece of UI.
	_haze_layer.layer = 1
	add_child(_haze_layer)
	_haze = ColorRect.new()
	_haze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = load(HAZE_SHADER) as Shader
	_haze.material = _haze_mat
	_haze_layer.add_child(_haze)

	_backdrop_mat.set_shader_parameter(
		"surface_y", float(GameConfig.SURFACE_ROW * GameConfig.TILE_SIZE))
	_backdrop_mat.set_shader_parameter(
		"world_bottom_y", float(GameConfig.WORLD_TILES_Y * GameConfig.TILE_SIZE))


func configure(p_camera: CameraRig) -> void:
	camera = p_camera


func _process(delta: float) -> void:
	_drift += delta
	var focus: Vector2 = Vector2.ZERO
	var view := Rect2(Vector2.ZERO, Vector2(1280, 720))
	if camera != null:
		view = camera.view_rect()
		focus = camera.get_screen_centre()
	elif Game.player != null and is_instance_valid(Game.player):
		focus = Game.player.global_position

	var depth := GameConfig.depth_metres(focus)
	_ambient = BiomeTable.ambient_for_depth(depth)
	var haze := BiomeTable.haze_for_depth(depth)
	var zone := BiomeTable.zone_for_depth(depth)

	# The one global every lit shader reads.
	RenderingServer.global_shader_parameter_set(
		"deep_ambient", Vector3(_ambient.r, _ambient.g, _ambient.b))

	_backdrop_mat.set_shader_parameter("view_origin", view.position)
	_backdrop_mat.set_shader_parameter("view_size", view.size)
	_backdrop_mat.set_shader_parameter("ambient_light", Vector3(_ambient.r, _ambient.g, _ambient.b))
	_backdrop_mat.set_shader_parameter("drift", _drift)
	_backdrop_mat.set_shader_parameter(
		"zone_tint", Vector3(haze.r * 2.6 + 0.08, haze.g * 2.6 + 0.09, haze.b * 2.6 + 0.13))
	# Cross-fade sky to cavern across the first twelve metres of soil.
	_backdrop_mat.set_shader_parameter("underground", clampf(depth / 12.0, 0.0, 1.0))

	_haze_mat.set_shader_parameter("view_origin", view.position)
	_haze_mat.set_shader_parameter("view_size", view.size)
	_haze_mat.set_shader_parameter("haze_colour", haze)
	_haze_mat.set_shader_parameter("drift", _drift)

	if zone.ambience_cue != _current_cue:
		_current_cue = zone.ambience_cue
		Audio.set_ambience(_current_cue)

	Dbg.set_counter("ambient", "%.2f" % _ambient.v)
	Dbg.set_counter("zone", zone.display_name)


func current_ambient() -> Color:
	return _ambient
