class_name LightField
extends RefCounted
## Builds the shared 16x2 light texture every lit shader reads.
##
## Candidates come from two places: static emissive clusters baked into each
## active ChunkData, and dynamic sources registered by entities (the player's
## lantern, a Glowling, a torch VFX). Each frame we keep the strongest
## candidates nearest the camera and upload them. Anything that misses the cut
## still self-illuminates through the material's emission term, so a crystal
## seam never visibly switches off — it just stops casting.

const MAX_LIGHTS: int = 16

class Source extends RefCounted:
	var position: Vector2 = Vector2.ZERO
	var colour: Color = Color.WHITE
	var radius: float = 120.0
	var intensity: float = 0.6
	var phase: float = 0.0
	var enabled: bool = true

	func _init(p_colour: Color = Color.WHITE, p_radius: float = 120.0, p_intensity: float = 0.6) -> void:
		colour = p_colour
		radius = p_radius
		intensity = p_intensity
		phase = randf()

var _image: Image
var _texture: ImageTexture
var _dynamic: Array[Source] = []
var _static_cache: Array[Dictionary] = []
var _scratch: Array[Dictionary] = []
var active_count: int = 0


func _init() -> void:
	_image = Image.create(MAX_LIGHTS, 2, false, Image.FORMAT_RGBAF)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set("deep_light_data", _texture)
	RenderingServer.global_shader_parameter_set("deep_light_count", 0)


## Register a light that moves or switches (player lantern, creature glow).
## The caller keeps the returned Source and mutates it directly.
func add_dynamic(colour: Color, radius: float, intensity: float) -> Source:
	var s := Source.new(colour, radius, intensity)
	_dynamic.append(s)
	return s


func remove_dynamic(s: Source) -> void:
	_dynamic.erase(s)


## Replace the baked static set. Called when the active chunk set changes.
func set_static_sources(sources: Array[Dictionary]) -> void:
	_static_cache = sources


func update(camera_centre: Vector2, time: float) -> void:
	_scratch.clear()

	for d in _dynamic:
		if not d.enabled or d.intensity <= 0.001:
			continue
		_scratch.append({
			"pos": d.position,
			"colour": d.colour,
			"radius": d.radius,
			"intensity": d.intensity,
			"phase": d.phase,
			"score": _score(d.position, camera_centre, d.intensity, d.radius) + 400.0,
		})

	for s in _static_cache:
		var p: Vector2 = s["pos"]
		_scratch.append({
			"pos": p,
			"colour": s["colour"],
			"radius": s["radius"],
			"intensity": s["intensity"],
			"phase": fposmod(p.x * 0.013 + p.y * 0.029, 1.0),
			"score": _score(p, camera_centre, s["intensity"], s["radius"]),
		})

	_scratch.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))

	var n: int = mini(_scratch.size(), MAX_LIGHTS)
	for i in MAX_LIGHTS:
		if i < n:
			var e: Dictionary = _scratch[i]
			var p: Vector2 = e["pos"]
			var c: Color = e["colour"]
			_image.set_pixel(i, 0, Color(p.x, p.y, float(e["radius"]), float(e["intensity"])))
			_image.set_pixel(i, 1, Color(c.r, c.g, c.b, float(e["phase"])))
		else:
			_image.set_pixel(i, 0, Color(0, 0, 0, 0))
			_image.set_pixel(i, 1, Color(0, 0, 0, 0))

	active_count = n
	_texture.update(_image)
	RenderingServer.global_shader_parameter_set("deep_light_count", n)
	RenderingServer.global_shader_parameter_set("deep_time", time)


## Nearer and brighter wins. Lights whose reach cannot touch the view at all
## score below zero and are effectively never chosen.
func _score(pos: Vector2, centre: Vector2, intensity: float, radius: float) -> float:
	var d := pos.distance_to(centre)
	return (radius + 520.0) * intensity - d * 0.55
