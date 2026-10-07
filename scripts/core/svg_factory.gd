class_name SvgFactory
extends RefCounted
## Turns the project's SVG art into exactly-sized, optionally recoloured
## textures, and caches the results.
##
## Two sources are supported:
##   * imported .svg files (creatures, player parts, props) — rasterised by
##     Godot at 4x the viewBox, then resized here to the precise pixel size a
##     sprite needs, so nothing is ever scaled by the renderer;
##   * SVG markup composed in code (item icons) — rasterised on demand through
##     `Image.load_svg_from_string`, which is why a new resource item needs a
##     palette and a shape name rather than an artist.
##
## Variant recolouring is an HSV rotation applied to the rasterised pixels.
## That preserves every gradient and highlight in the source art, which a flat
## shader tint would flatten.

static var _tex_cache: Dictionary = {}
static var _src_cache: Dictionary = {}


## Load (and cache) the raw rasterised image for an imported SVG.
static func source_image(path: String) -> Image:
	if _src_cache.has(path):
		return _src_cache[path]
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("DEEP: missing art '%s'." % path)
		var fallback := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(1, 0, 1, 1))
		_src_cache[path] = fallback
		return fallback
	var img := tex.get_image()
	if img == null:
		img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 0, 1, 1))
	else:
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	_src_cache[path] = img
	return img


## A texture whose height is exactly `target_height` pixels, with the source
## aspect ratio preserved.
##
## `hue_shift`   degrees, -180..180
## `saturation`  multiplier
## `value`       multiplier
## `overlay`     colour blended over the result by `overlay.a`
static func sprite(
	path: String,
	target_height: int,
	hue_shift: float = 0.0,
	saturation: float = 1.0,
	value: float = 1.0,
	overlay: Color = Color(0, 0, 0, 0)
) -> ImageTexture:
	var key := "%s|%d|%.1f|%.2f|%.2f|%s" % [
		path, target_height, hue_shift, saturation, value, overlay.to_html(true)
	]
	if _tex_cache.has(key):
		return _tex_cache[key]

	var img := (source_image(path).duplicate() as Image)

	# Resize BEFORE recolouring, never after. The sources rasterise at 4x the
	# viewBox (256px), so recolouring first would mean ~65k pixel conversions
	# per variant in GDScript — which is what made opening the Codex, with its
	# twenty-odd variant thumbnails, take seconds. On the resized image it is
	# a few thousand, and the result is visually identical because an HSV
	# rotation and a resample commute closely enough at these sizes.
	if target_height > 0 and img.get_height() != target_height:
		var ratio := float(img.get_width()) / float(maxi(img.get_height(), 1))
		var w: int = maxi(1, int(round(float(target_height) * ratio)))
		img.resize(w, target_height, Image.INTERPOLATE_LANCZOS)

	if _needs_recolour(hue_shift, saturation, value, overlay):
		_recolour(img, hue_shift, saturation, value, overlay)

	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func _needs_recolour(hue_shift: float, saturation: float, value: float, overlay: Color) -> bool:
	return (
		absf(hue_shift) > 0.01
		or absf(saturation - 1.0) > 0.01
		or absf(value - 1.0) > 0.01
		or overlay.a > 0.004
	)


static func from_markup(markup: String, cache_key: String, height: int, view_height: float = 64.0) -> ImageTexture:
	var key := "markup:%s|%d" % [cache_key, height]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.new()
	var scale: float = maxf(0.05, float(height) / maxf(view_height, 1.0))
	var err := img.load_svg_from_string(markup, scale)
	if err != OK or img.is_empty():
		push_error("DEEP: could not rasterise generated SVG '%s' (%d)." % [cache_key, err])
		img = Image.create(maxi(height, 2), maxi(height, 2), false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.2, 0.7, 1.0))
	else:
		img.convert(Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func _recolour(img: Image, hue_shift: float, saturation: float, value: float, overlay: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var shift := hue_shift / 360.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.003:
				continue
			if absf(shift) > 0.0001 or absf(saturation - 1.0) > 0.001 or absf(value - 1.0) > 0.001:
				var hue := fposmod(c.h + shift, 1.0)
				var sat: float = clampf(c.s * saturation, 0.0, 1.0)
				var val: float = clampf(c.v * value, 0.0, 1.0)
				var out := Color.from_hsv(hue, sat, val, c.a)
				c = out
			if overlay.a > 0.004:
				c = Color(
					lerpf(c.r, overlay.r, overlay.a),
					lerpf(c.g, overlay.g, overlay.a),
					lerpf(c.b, overlay.b, overlay.a),
					c.a
				)
			img.set_pixel(x, y, c)


## Pure-black silhouette of a sprite, used by the Codex for unknown species.
static func silhouette(path: String, target_height: int, tint: Color = Color(0.08, 0.09, 0.13)) -> ImageTexture:
	var key := "sil:%s|%d|%s" % [path, target_height, tint.to_html(true)]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := (source_image(path).duplicate() as Image)
	if target_height > 0 and img.get_height() != target_height:
		var ratio := float(img.get_width()) / float(maxi(img.get_height(), 1))
		img.resize(maxi(1, int(round(float(target_height) * ratio))), target_height,
			Image.INTERPOLATE_LANCZOS)
	# Flatten to the tint, keeping only the alpha shape.
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		if data[i + 3] == 0:
			continue
		data[i] = int(tint.r * 255.0)
		data[i + 1] = int(tint.g * 255.0)
		data[i + 2] = int(tint.b * 255.0)
	var flat := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(flat)
	_tex_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_tex_cache.clear()
	_src_cache.clear()
