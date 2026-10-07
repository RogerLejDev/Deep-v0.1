class_name ChunkNode
extends Node2D
## Scene-tree representation of one chunk: one draw call for the terrain plus
## one static body carrying the merged collision rectangles.
##
## The node never generates terrain itself. World hands it a ChunkData and a
## `tile_lookup` callable (used only to read the one-tile border from the
## neighbouring chunks so edges and lighting are seamless). Keeping the
## dependency as a Callable rather than a World reference avoids a cyclic
## class dependency between the two scripts.

const PAD: int = 1

static var _unit_texture: Texture2D = null

var data: ChunkData = null

var _tile_lookup: Callable = Callable()
var _material: ShaderMaterial = null
var _colour_image: Image = null
var _extra_image: Image = null
var _colour_tex: ImageTexture = null
var _extra_tex: ImageTexture = null
var _body: StaticBody2D = null
var _shapes: Array[CollisionShape2D] = []


static func _unit() -> Texture2D:
	# A 1x1 opaque texture, drawn stretched over the chunk purely so the
	# terrain shader gets a quad with UV spanning 0..1. Costs nothing and
	# avoids QuadMesh's flipped-Y convention.
	if _unit_texture == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		_unit_texture = ImageTexture.create_from_image(img)
	return _unit_texture


func _ready() -> void:
	z_index = 0
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)


func setup(p_data: ChunkData, p_lookup: Callable, shader: Shader) -> void:
	data = p_data
	_tile_lookup = p_lookup
	position = data.origin_px()

	var dim := GameConfig.CHUNK_TILES + PAD * 2
	_colour_image = Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	_extra_image = Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	_colour_tex = ImageTexture.create_from_image(_colour_image)
	_extra_tex = ImageTexture.create_from_image(_extra_image)

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("tex_colour", _colour_tex)
	_material.set_shader_parameter("tex_extra", _extra_tex)
	_material.set_shader_parameter("tiles", float(GameConfig.CHUNK_TILES))
	_material.set_shader_parameter("tile_px", float(GameConfig.TILE_SIZE))
	_material.set_shader_parameter("chunk_origin", data.origin_px())
	var depth_ratio := clampf(
		float(data.coord.y * GameConfig.CHUNK_TILES - GameConfig.SURFACE_ROW)
			/ float(GameConfig.WORLD_TILES_Y - GameConfig.SURFACE_ROW),
		0.0, 1.0)
	_material.set_shader_parameter("depth_ratio", depth_ratio)
	material = _material
	rebuild()


## Re-upload textures and rebuild collision. Called on activation and whenever
## the player edits a tile in this chunk (or in a neighbour, for the border).
func rebuild() -> void:
	if data == null:
		return
	if not data.analysed:
		data.analyse()
	_fill_images()
	_colour_tex.update(_colour_image)
	_extra_tex.update(_extra_image)
	_rebuild_collision()
	data.dirty = false
	queue_redraw()


func _fill_images() -> void:
	var cs := GameConfig.CHUNK_TILES
	var dim := cs + PAD * 2
	var origin := data.origin_tile()

	# Read the padded region once into a flat array. Everything below then
	# indexes that array instead of calling back through World for each
	# neighbour lookup, which is what made meshing a chunk expensive.
	var ids := PackedByteArray()
	ids.resize(dim * dim)
	for py in dim:
		var ty := origin.y + py - PAD
		var row := py * dim
		for px in dim:
			if px >= PAD and py >= PAD and px < cs + PAD and py < cs + PAD:
				ids[row + px] = data.get_local(px - PAD, py - PAD)
			else:
				ids[row + px] = int(_tile_lookup.call(origin.x + px - PAD, ty))

	for py in dim:
		var ty := origin.y + py - PAD
		for px in dim:
			_write_tile(px, py, origin.x + px - PAD, ty, ids[py * dim + px], ids, dim)


func _write_tile(
	px: int, py: int, tx: int, ty: int, id: int,
	ids: PackedByteArray, dim: int
) -> void:
	var def := BlockDB.get_block(id)
	var solid := def.solid

	# A non-solid tile still needs a plausible colour, because the shader's
	# anti-aliased silhouette samples colour from the tile the pixel falls in.
	# Inheriting the nearest solid neighbour's look is what keeps rims from
	# fringing to black.
	var source := def
	if not solid:
		source = _nearest_solid_def(px, py, ids, dim)

	var seed_h := RngUtil.hash3(tx * 73856093, ty * 19349663, 0x5F3759)
	var r1 := RngUtil.to_signed(seed_h)
	var r2 := RngUtil.to_signed(RngUtil.mix(seed_h))
	var r3 := RngUtil.to_unit(RngUtil.mix(RngUtil.mix(seed_h)))

	var base := source.colour
	# A minority of tiles carry a vein of the material's secondary colour.
	# Kept rare and shallow on purpose: strong per-tile recolouring turns a
	# rock face into a patchwork quilt instead of a rock face.
	if source.speckle_amount > 0.0 and r3 < source.speckle_amount * 0.28:
		base = base.lerp(source.speckle, 0.22 + r3 * 0.25)

	# Per-tile jitter is value-dominant: brightness varies clearly, hue barely
	# at all. That reads as uneven rock rather than as different materials,
	# while still ensuring no two tiles are identical.
	var v := source.colour_variance
	var value_shift := 1.0 + r1 * v
	var hue_shift := r2 * v * 0.22
	var colour := Color(
		clampf(base.r * (value_shift + hue_shift), 0.0, 1.0),
		clampf(base.g * value_shift, 0.0, 1.0),
		clampf(base.b * (value_shift - hue_shift), 0.0, 1.0),
		1.0 if solid else 0.0
	)
	_colour_image.set_pixel(px, py, colour)

	# Emission is taken from the *actual* tile (so a torch in open air glows)
	# but flags come from the material we are shading.
	var em := def.emission_colour * def.emission
	var flags := 0
	if source.organic:
		flags += 1
	if source.crystalline:
		flags += 2
	# Pack flags (0..3) in the high bits and a per-tile seed in the low bits.
	var packed := float(flags * 64 + int(r3 * 63.0)) / 255.0
	_extra_image.set_pixel(px, py, Color(
		clampf(em.r, 0.0, 1.0),
		clampf(em.g, 0.0, 1.0),
		clampf(em.b, 0.0, 1.0),
		packed
	))


const NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]

## Material an empty tile borrows its look from, so anti-aliased rims do not
## fringe to black. Reads the pre-fetched padded array, never the World.
func _nearest_solid_def(px: int, py: int, ids: PackedByteArray, dim: int) -> BlockDef:
	for o in NEIGHBOUR_OFFSETS:
		var nx := px + o.x
		var ny := py + o.y
		if nx < 0 or ny < 0 or nx >= dim or ny >= dim:
			continue
		var d := BlockDB.get_block(ids[ny * dim + nx])
		if d.solid:
			return d
	return BlockDB.get_block(BlockDB.STONE)


func _rebuild_collision() -> void:
	var needed := data.collision_rects.size()
	# Reuse existing shape nodes; churning hundreds of nodes per edit is the
	# single easiest way to make a destructible world stutter.
	while _shapes.size() < needed:
		var cs := CollisionShape2D.new()
		cs.shape = RectangleShape2D.new()
		_body.add_child(cs)
		_shapes.append(cs)
	for i in _shapes.size():
		var node := _shapes[i]
		if i >= needed:
			node.disabled = true
			node.visible = false
			continue
		var r: Rect2i = data.collision_rects[i]
		var rect := node.shape as RectangleShape2D
		rect.size = Vector2(r.size) * float(GameConfig.TILE_SIZE)
		node.position = (Vector2(r.position) + Vector2(r.size) * 0.5) * float(GameConfig.TILE_SIZE)
		node.disabled = false
		node.visible = true


func _draw() -> void:
	draw_texture_rect(
		_unit(),
		Rect2(Vector2.ZERO, Vector2.ONE * float(GameConfig.CHUNK_PX)),
		false
	)


func release() -> void:
	data = null
	_tile_lookup = Callable()
	queue_free()
