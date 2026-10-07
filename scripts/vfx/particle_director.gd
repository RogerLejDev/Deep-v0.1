extends Node2D
## All gameplay VFX, pooled.
##
## Mining a block in DEEP fires chips, a dust puff, a flash of the material's
## own colour and (for crystal) a few bright sparks. That feedback is most of
## what makes digging feel good, so it gets a real system rather than one
## generic burst — but it is pooled and capped, because a phone cannot afford
## a fresh GPUParticles2D per swing.

const POOL_SIZE: int = 14
const MOTE_BUDGET: int = 110

var _pool: Array[GPUParticles2D] = []
var _cursor: int = 0
var _motes: GPUParticles2D = null
var _mote_material: ParticleProcessMaterial = null
var _camera: CameraRig = null


func _ready() -> void:
	add_to_group("vfx")
	z_index = 60
	for i in POOL_SIZE:
		var p := _make_burst()
		add_child(p)
		_pool.append(p)
	_motes = _make_motes()
	add_child(_motes)
	EventBus.item_collected.connect(_on_item_collected)


func configure(camera: CameraRig) -> void:
	_camera = camera


# --- Pool --------------------------------------------------------------------

func _make_burst() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.55
	p.explosiveness = 0.95
	p.local_coords = false
	p.texture = _chip_texture()

	var m := ParticleProcessMaterial.new()
	m.particle_flag_disable_z = true
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 5.0
	m.direction = Vector3(0, -1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 40.0
	m.initial_velocity_max = 140.0
	m.gravity = Vector3(0, 420, 0)
	m.damping_min = 20.0
	m.damping_max = 60.0
	m.angular_velocity_min = -420.0
	m.angular_velocity_max = 420.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	var tex_curve := CurveTexture.new()
	tex_curve.curve = curve
	m.scale_curve = tex_curve
	p.process_material = m
	return p


func _next() -> GPUParticles2D:
	var p := _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	return p


static func _chip_texture() -> ImageTexture:
	# A tiny angular chip rather than a soft dot, so debris reads as rock.
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 6:
		for x in 6:
			var inside := (x + y) >= 2 and (x + y) <= 8 and absi(x - y) <= 3
			if inside:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


# --- Public VFX --------------------------------------------------------------

## Small chips while a block is being worked.
func spawn_chips(position: Vector2, def: BlockDef, count: int = 4) -> void:
	var p := _next()
	p.global_position = position
	p.amount = maxi(2, count)
	p.lifetime = 0.42
	var m := p.process_material as ParticleProcessMaterial
	m.initial_velocity_min = 30.0
	m.initial_velocity_max = 95.0
	m.gravity = Vector3(0, 480, 0)
	p.modulate = _chip_colour(def)
	p.restart()


## The full break: more debris, a dust puff, and sparks for crystal.
func spawn_break(position: Vector2, def: BlockDef) -> void:
	var p := _next()
	p.global_position = position
	p.amount = 18
	p.lifetime = 0.62
	var m := p.process_material as ParticleProcessMaterial
	m.initial_velocity_min = 55.0
	m.initial_velocity_max = 170.0
	m.gravity = Vector3(0, 440, 0)
	p.modulate = _chip_colour(def)
	p.restart()

	# Dust: slow, upward, translucent.
	var d := _next()
	d.global_position = position
	d.amount = 10
	d.lifetime = 0.9
	var dm := d.process_material as ParticleProcessMaterial
	dm.initial_velocity_min = 8.0
	dm.initial_velocity_max = 38.0
	dm.gravity = Vector3(0, -40, 0)
	dm.scale_min = 1.4
	dm.scale_max = 3.0
	d.modulate = Color(def.colour.r, def.colour.g, def.colour.b, 0.35)
	d.restart()

	if def.emission > 0.2:
		var s := _next()
		s.global_position = position
		s.amount = 12
		s.lifetime = 0.8
		var sm := s.process_material as ParticleProcessMaterial
		sm.initial_velocity_min = 70.0
		sm.initial_velocity_max = 210.0
		sm.gravity = Vector3(0, 120, 0)
		sm.scale_min = 0.4
		sm.scale_max = 0.9
		s.modulate = Color(
			def.emission_colour.r, def.emission_colour.g, def.emission_colour.b, 1.0
		)
		s.restart()


func spawn_place(position: Vector2, def: BlockDef) -> void:
	var p := _next()
	p.global_position = position
	p.amount = 8
	p.lifetime = 0.4
	var m := p.process_material as ParticleProcessMaterial
	m.initial_velocity_min = 10.0
	m.initial_velocity_max = 50.0
	m.gravity = Vector3(0, -60, 0)
	p.modulate = Color(def.colour.r, def.colour.g, def.colour.b, 0.8)
	p.restart()


## Upward spark trail, used when the player picks something up.
func spawn_pickup(position: Vector2, colour: Color) -> void:
	var p := _next()
	p.global_position = position
	p.amount = 7
	p.lifetime = 0.5
	var m := p.process_material as ParticleProcessMaterial
	m.initial_velocity_min = 50.0
	m.initial_velocity_max = 120.0
	m.gravity = Vector3(0, -180, 0)
	m.scale_min = 0.4
	m.scale_max = 0.8
	p.modulate = colour
	p.restart()


func spawn_discovery(position: Vector2, colour: Color) -> void:
	var p := _next()
	p.global_position = position
	p.amount = 30
	p.lifetime = 1.3
	var m := p.process_material as ParticleProcessMaterial
	m.initial_velocity_min = 90.0
	m.initial_velocity_max = 240.0
	m.gravity = Vector3(0, -30, 0)
	m.scale_min = 0.5
	m.scale_max = 1.6
	m.damping_min = 60.0
	m.damping_max = 140.0
	p.modulate = colour
	p.restart()


static func _chip_colour(def: BlockDef) -> Color:
	if def.emission > 0.2:
		return def.emission_colour
	# Brighten the albedo a little; unlit debris is invisible in a dark cave.
	return Color(
		minf(1.0, def.colour.r * 1.5 + 0.1),
		minf(1.0, def.colour.g * 1.5 + 0.1),
		minf(1.0, def.colour.b * 1.5 + 0.1),
		1.0
	)


func _on_item_collected(item_id: String, _amount: int) -> void:
	if Game.player == null or not is_instance_valid(Game.player):
		return
	var def := ItemDB.get_item(item_id)
	var col := def.icon_glow if def.icon_glow.a > 0.0 else def.icon_primary
	spawn_pickup(Game.player.global_position + Vector2(0, -14), Color(col.r, col.g, col.b, 1.0))


# --- Ambient motes -----------------------------------------------------------

func _make_motes() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = MOTE_BUDGET
	p.lifetime = 6.5
	p.preprocess = 3.0
	p.local_coords = false
	p.texture = _mote_texture()
	var m := ParticleProcessMaterial.new()
	m.particle_flag_disable_z = true
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(380, 230, 1)
	m.direction = Vector3(0, -1, 0)
	m.spread = 60.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 14.0
	m.gravity = Vector3(3, -6, 0)
	m.scale_min = 0.3
	m.scale_max = 1.1
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.4
	m.turbulence_noise_scale = 2.0
	_mote_material = m
	p.process_material = m
	return p


static func _mote_texture() -> ImageTexture:
	var size := 8
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / (c + 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	if _camera == null or _motes == null:
		return
	_motes.global_position = _camera.get_screen_centre()
	if Game.player != null and is_instance_valid(Game.player):
		var depth := GameConfig.depth_metres(Game.player.global_position)
		var zone := BiomeTable.zone_for_depth(depth)
		_motes.amount_ratio = clampf(zone.motes * 0.7, 0.05, 1.0)
		_motes.modulate = zone.mote_colour
