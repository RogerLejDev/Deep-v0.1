extends Node
## Turns "a creature was on screen" into Codex knowledge.
##
## A sighting requires the creature to be inside the camera rectangle, within
## a believable identification range, and actually *visible* — lit by the
## player's lantern, by a crystal seam, or self-luminous. That last condition
## is what makes the lantern a progression item: in the deep strata you cannot
## complete entries you cannot light up.

## Identification range in pixels. Beyond this it is a shape, not a sighting.
const IDENTIFY_RANGE: float = 310.0
## Visibility (0..1) needed to register and to keep observing.
const VISIBILITY_THRESHOLD: float = 0.14
## Screen-rect padding so a creature half off-screen still counts.
const VIEW_PADDING: float = 48.0

var spawner: Node = null
var camera: Camera2D = null

var _visible_now: Dictionary = {}


func configure(p_spawner: Node, p_camera: Camera2D) -> void:
	spawner = p_spawner
	camera = p_camera


func _process(delta: float) -> void:
	if spawner == null or camera == null:
		return
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return

	var view := _view_rect()
	var player_pos: Vector2 = player.global_position
	var depth := GameConfig.depth_metres(player_pos)
	var lantern := Game.light_radius()
	var ambient := BiomeTable.ambient_for_depth(depth).v

	_visible_now.clear()
	var list: Array = spawner.call("creatures")
	for item in list:
		var c := item as Creature
		if c == null or not is_instance_valid(c) or c.data == null:
			continue
		var pos: Vector2 = c.global_position
		if not view.has_point(pos):
			continue
		var dist := player_pos.distance_to(pos)
		if dist > IDENTIFY_RANGE:
			continue

		var visibility := _visibility(c, dist, lantern, ambient)
		if visibility < VISIBILITY_THRESHOLD:
			continue

		_visible_now[c.species_id] = true

		if not c.sighted:
			c.sighted = true
			var was_new := Game.codex.note_sighting(c.species_id, c.variant_id, depth)
			Game.bump_stat("creatures_sighted")
			if not was_new and c.variant.is_special():
				EventBus.screen_shake_requested.emit(1.2, 0.2)

		# Observation only accrues for species already in the Codex, scaled by
		# how clearly you can see it.
		c.accumulate_observation(delta * clampf(visibility, 0.0, 1.0))

	Dbg.set_counter("observing", _visible_now.size())


func _view_rect() -> Rect2:
	var vp := camera.get_viewport_rect().size
	var zoom := camera.zoom
	var half := Vector2(vp.x / maxf(zoom.x, 0.01), vp.y / maxf(zoom.y, 0.01)) * 0.5
	half += Vector2(VIEW_PADDING, VIEW_PADDING)
	var centre: Vector2 = camera.global_position
	if camera.has_method("get_screen_centre"):
		centre = camera.call("get_screen_centre")
	return Rect2(centre - half, half * 2.0)


## 0..1 estimate of how well the player can make this creature out.
func _visibility(c: Creature, dist: float, lantern_radius: float, ambient_value: float) -> float:
	# Ambient light in the current zone.
	var v: float = clampf(ambient_value * 1.6, 0.0, 1.0)
	# The player's own light.
	v += clampf(1.0 - dist / maxf(lantern_radius * 1.35, 1.0), 0.0, 1.0)
	# Self-luminous creatures identify themselves.
	v += clampf(c.data.light_intensity * c.variant.emission_mul * 1.4, 0.0, 1.0)
	# Nearby glowing terrain.
	if Game.world != null:
		var t := GameConfig.world_to_tile(c.global_position)
		for dy in range(-3, 4, 2):
			for dx in range(-3, 4, 2):
				if BlockDB.get_block(Game.world.get_tile(t.x + dx, t.y + dy)).emission > 0.3:
					v += 0.18
	# Distance always costs a little clarity.
	v *= lerpf(1.0, 0.55, clampf(dist / IDENTIFY_RANGE, 0.0, 1.0))
	return clampf(v, 0.0, 1.0)


func species_in_view() -> Array[String]:
	var out: Array[String] = []
	for k: String in _visible_now.keys():
		out.append(k)
	return out
