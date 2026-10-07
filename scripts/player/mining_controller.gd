extends Node2D
## Mining, block placing, and the target reticle.
##
## Mobile targeting works the way the design asked for: tapping or dragging on
## the world picks the tile you want, and *holding* the mine button works it.
## If you hold mine without having picked anything, it auto-targets the most
## sensible tile in front of you, so one-thumb play still works.

## Reticle colours.
const COL_OK := Color(0.68, 0.92, 1.0, 0.85)
const COL_BUSY := Color(1.0, 0.86, 0.45, 0.95)
const COL_BAD := Color(1.0, 0.36, 0.32, 0.8)
const COL_PLACE := Color(0.62, 1.0, 0.72, 0.8)

var world: DeepWorld = null
var player: Player = null

## Set by TouchControls / keyboard.
var mine_held: bool = false
var place_requested: bool = false
## Explicit target chosen by touching the world; (-1,-1) means "auto".
var manual_target: Vector2i = Vector2i(-1, -1)

var _target: Vector2i = Vector2i(-1, -1)
var _progress: float = 0.0
var _target_hardness: float = 1.0
var _blocked_reason: String = ""
var _hit_accum: float = 0.0
var _particles: Node = null


func _ready() -> void:
	z_index = 40
	set_process_input(true)


func configure(p_world: DeepWorld, p_player: Player) -> void:
	world = p_world
	player = p_player
	_particles = get_tree().get_first_node_in_group("vfx")


func _input(event: InputEvent) -> void:
	if world == null or player == null:
		return
	# Picking a target by touching the world. UI consumes its own events first,
	# so anything reaching here is a world touch.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_set_target_from_screen(mb.position)
				mine_held = true
			else:
				mine_held = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_set_target_from_screen(mb.position)
			place_requested = true
	elif event is InputEventMouseMotion and mine_held:
		_set_target_from_screen((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_set_target_from_screen(st.position)
	elif event is InputEventScreenDrag:
		_set_target_from_screen((event as InputEventScreenDrag).position)


func _set_target_from_screen(screen_pos: Vector2) -> void:
	var canvas_xform := get_viewport().get_canvas_transform()
	var world_pos := canvas_xform.affine_inverse() * screen_pos
	manual_target = GameConfig.world_to_tile(world_pos)


func _process(delta: float) -> void:
	if world == null or player == null:
		return
	if player.is_dead():
		player.mining = false
		mine_held = false
		_progress = 0.0
		queue_redraw()
		return

	if Input.is_action_just_pressed("place"):
		place_requested = true

	_resolve_target()

	if place_requested:
		place_requested = false
		_try_place()

	var working := mine_held and _target.x >= 0 and _blocked_reason.is_empty()
	player.mining = working

	if working:
		_advance_mining(delta)
	else:
		if _progress > 0.0:
			_progress = maxf(0.0, _progress - delta * 1.6)
		_hit_accum = 0.0

	queue_redraw()


# --- Targeting ---------------------------------------------------------------

func _resolve_target() -> void:
	_blocked_reason = ""
	var reach := GameConfig.MINING_REACH_TILES * float(GameConfig.TILE_SIZE)
	var origin := player.global_position + Vector2(0.0, -12.0)

	var candidate := manual_target
	if candidate.x >= 0:
		var centre := GameConfig.tile_centre(candidate.x, candidate.y)
		if origin.distance_to(centre) > reach:
			# Out of reach: keep showing it, but refuse to work it.
			_target = candidate
			_blocked_reason = "OUT OF REACH"
			return
		if not BlockDB.is_solid(world.get_tile_v(candidate)):
			# Tapped empty space — fall through to auto-aim so holding mine
			# still does something useful.
			candidate = Vector2i(-1, -1)

	if candidate.x < 0:
		candidate = _auto_target(origin)

	if candidate.x < 0:
		_target = Vector2i(-1, -1)
		_blocked_reason = "NO TARGET"
		return

	if candidate != _target:
		_target = candidate
		_progress = 0.0

	var id := world.get_tile_v(_target)
	var def := BlockDB.get_block(id)
	_target_hardness = def.hardness
	if def.unbreakable:
		_blocked_reason = "IMPENETRABLE"
	elif not def.is_minable_with(Game.mining_tier()):
		_blocked_reason = "NEEDS A BETTER TOOL"


## Auto-aim: prefer the tile the player is facing at chest height, then feet,
## then straight down. That covers "dig forward" and "dig down" with one hold.
func _auto_target(origin: Vector2) -> Vector2i:
	var base := GameConfig.world_to_tile(player.global_position + Vector2(0.0, -8.0))
	var f := player.facing
	var order: Array[Vector2i] = [
		base + Vector2i(f, 0),
		base + Vector2i(f, 1),
		base + Vector2i(f, -1),
		base + Vector2i(0, 2),
		base + Vector2i(f * 2, 0),
	]
	for t in order:
		if not GameConfig.in_bounds(t.x, t.y):
			continue
		var def := BlockDB.get_block(world.get_tile_v(t))
		if not def.solid or def.unbreakable:
			continue
		if origin.distance_to(GameConfig.tile_centre(t.x, t.y)) > GameConfig.MINING_REACH_TILES * GameConfig.TILE_SIZE:
			continue
		return t
	return Vector2i(-1, -1)


# --- Mining ------------------------------------------------------------------

func _advance_mining(delta: float) -> void:
	var id := world.get_tile_v(_target)
	var def := BlockDB.get_block(id)
	var seconds := def.break_seconds(Game.mining_power())
	if seconds <= 0.0 or is_inf(seconds):
		return
	_progress += delta / seconds

	# Hit feedback at a fixed cadence rather than per frame.
	_hit_accum += delta
	if _hit_accum >= 0.14:
		_hit_accum = 0.0
		EventBus.block_hit.emit(_target, id, clampf(_progress, 0.0, 1.0))
		EventBus.screen_shake_requested.emit(0.5, 0.05)
		_spawn_hit_vfx(def)

	if _progress < 1.0:
		return

	_progress = 0.0
	_break_block(_target, id, def)


func _break_block(tile: Vector2i, id: int, def: BlockDef) -> void:
	# Mark as `natural` so ecology may regrow the vein later. The hole itself
	# is permanent either way — only resource overrides expire.
	if not world.set_tile(tile.x, tile.y, BlockDB.AIR, true):
		return
	Game.bump_stat("blocks_mined")
	EventBus.block_mined.emit(tile, id, true)
	EventBus.screen_shake_requested.emit(1.3, 0.1)

	if not def.drop_item.is_empty():
		var n := randi_range(def.drop_min, def.drop_max)
		var leftover := Game.inventory.add(def.drop_item, n)
		var got := n - leftover
		if got > 0:
			EventBus.item_collected.emit(def.drop_item, got)
		if leftover > 0:
			EventBus.toast_requested.emit("PACK FULL", "warn")

	_spawn_break_vfx(tile, def)


func _spawn_hit_vfx(def: BlockDef) -> void:
	if _particles == null or not _particles.has_method("spawn_chips"):
		return
	_particles.call("spawn_chips", GameConfig.tile_centre(_target.x, _target.y), def, 3)


func _spawn_break_vfx(tile: Vector2i, def: BlockDef) -> void:
	if _particles == null or not _particles.has_method("spawn_break"):
		return
	_particles.call("spawn_break", GameConfig.tile_centre(tile.x, tile.y), def)


# --- Placing -----------------------------------------------------------------

func _try_place() -> void:
	var item := _selected_placeable()
	if item.is_empty():
		EventBus.toast_requested.emit("NOTHING PLACEABLE SELECTED", "warn")
		return
	var def := ItemDB.get_item(item)
	var tile := manual_target
	if tile.x < 0:
		tile = GameConfig.world_to_tile(player.global_position + Vector2(float(player.facing) * 18.0, 0.0))
	if not GameConfig.in_bounds(tile.x, tile.y):
		return
	var origin := player.global_position + Vector2(0.0, -12.0)
	if origin.distance_to(GameConfig.tile_centre(tile.x, tile.y)) > GameConfig.PLACE_REACH_TILES * GameConfig.TILE_SIZE:
		EventBus.toast_requested.emit("OUT OF REACH", "warn")
		return
	if world.get_tile_v(tile) != BlockDB.AIR:
		EventBus.toast_requested.emit("SPACE OCCUPIED", "warn")
		return
	# Refuse to brick the player inside a solid block.
	if BlockDB.get_block(def.place_block).solid:
		var body_tiles := [
			GameConfig.world_to_tile(player.global_position + Vector2(0, -6)),
			GameConfig.world_to_tile(player.global_position + Vector2(0, -20)),
		]
		if tile in body_tiles:
			EventBus.toast_requested.emit("YOU ARE STANDING THERE", "warn")
			return

	if Game.inventory.remove(item, 1) <= 0:
		return
	world.set_tile(tile.x, tile.y, def.place_block, false)
	Audio.play("craft", 1.25, -8.0)
	if _particles != null and _particles.has_method("spawn_place"):
		_particles.call("spawn_place", GameConfig.tile_centre(tile.x, tile.y), BlockDB.get_block(def.place_block))


func _selected_placeable() -> String:
	var sel: String = Game.selected_placeable
	if not sel.is_empty() and Game.inventory.has(sel):
		return sel
	# Fall back to the first placeable in the pack.
	for i in Game.inventory.slots.size():
		var id := Game.inventory.item_at(i)
		if id.is_empty():
			continue
		if ItemDB.get_item(id).is_placeable():
			return id
	return ""


# --- Reticle -----------------------------------------------------------------

func _draw() -> void:
	if _target.x < 0 or player == null:
		return
	var ts := float(GameConfig.TILE_SIZE)
	var top_left := Vector2(_target) * ts - global_position
	var rect := Rect2(top_left, Vector2(ts, ts))

	var col := COL_OK
	if not _blocked_reason.is_empty():
		col = COL_BAD
	elif _progress > 0.0:
		col = COL_BUSY

	# Corner brackets rather than a full box: much easier to read over busy
	# terrain on a small screen.
	var c := ts * 0.32
	var w := 1.6
	var pts := [
		[rect.position, Vector2(c, 0.0), Vector2(0.0, c)],
		[rect.position + Vector2(ts, 0.0), Vector2(-c, 0.0), Vector2(0.0, c)],
		[rect.position + Vector2(0.0, ts), Vector2(c, 0.0), Vector2(0.0, -c)],
		[rect.position + Vector2(ts, ts), Vector2(-c, 0.0), Vector2(0.0, -c)],
	]
	for p in pts:
		draw_line(p[0], p[0] + p[1], col, w)
		draw_line(p[0], p[0] + p[2], col, w)

	# Progress ring, drawn as a thickening arc around the tile.
	if _progress > 0.001:
		var centre := rect.position + rect.size * 0.5
		draw_arc(centre, ts * 0.62, -PI * 0.5, -PI * 0.5 + TAU * _progress, 22, COL_BUSY, 2.2)

	if _blocked_reason == "NEEDS A BETTER TOOL":
		var centre2 := rect.position + rect.size * 0.5
		draw_line(centre2 + Vector2(-4, -4), centre2 + Vector2(4, 4), COL_BAD, 1.8)
		draw_line(centre2 + Vector2(4, -4), centre2 + Vector2(-4, 4), COL_BAD, 1.8)


func target_tile() -> Vector2i:
	return _target


func blocked_reason() -> String:
	return _blocked_reason


func progress() -> float:
	return _progress
