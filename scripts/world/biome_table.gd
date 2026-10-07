class_name BiomeTable
extends RefCounted
## Depth bands inside ROOTLANDS, plus the atmosphere that goes with them.
##
## V0.1 ships one biome split into four readable depth zones. The table is the
## only place that maps depth -> mood, so adding MYCELIUM or ABYSSAL later
## means appending rows here (and giving them a horizontal extent) rather than
## touching the renderer, the spawner or the HUD.

class Zone extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var biome_id: String = "rootlands"
	## Inclusive lower bound in metres. Zones are sorted ascending.
	var from_metres: float = 0.0
	## Ambient light multiplier applied to terrain, entities and background.
	var ambient: Color = Color.WHITE
	## Distance fog / haze tint drawn over the world.
	var haze: Color = Color(0, 0, 0, 0)
	var ambience_cue: String = "amb_surface"
	## Floating mote density multiplier.
	var motes: float = 0.4
	var mote_colour: Color = Color(1, 1, 1, 0.25)
	## Species ids allowed to spawn, mapped to relative weight.
	var spawn_weights: Dictionary = {}

	func _init(p_id: String, p_name: String, p_from: float) -> void:
		id = p_id
		display_name = p_name
		from_metres = p_from


static var _zones: Array[Zone] = []


static func _ensure() -> void:
	if not _zones.is_empty():
		return

	var surface := Zone.new("rootlands_surface", "ROOTLANDS · SURFACE", -999.0)
	surface.ambient = Color(0.94, 0.93, 0.90)
	surface.haze = Color(0.62, 0.74, 0.78, 0.06)
	surface.ambience_cue = "amb_surface"
	surface.motes = 0.5
	surface.mote_colour = Color(1.0, 0.95, 0.72, 0.30)
	surface.spawn_weights = {"grib": 10.0, "molo": 1.0}
	_zones.append(surface)

	var topsoil := Zone.new("rootlands_topsoil", "ROOTLANDS · TOPSOIL", 10.0)
	topsoil.ambient = Color(0.46, 0.50, 0.56)
	topsoil.haze = Color(0.24, 0.27, 0.30, 0.14)
	topsoil.ambience_cue = "amb_shallow"
	topsoil.motes = 0.7
	topsoil.mote_colour = Color(0.78, 0.86, 0.70, 0.26)
	topsoil.spawn_weights = {"grib": 6.0, "molo": 4.0, "glowling": 2.0}
	_zones.append(topsoil)

	var caverns := Zone.new("rootlands_caverns", "ROOTLANDS · CAVERNS", 50.0)
	caverns.ambient = Color(0.20, 0.23, 0.31)
	caverns.haze = Color(0.14, 0.18, 0.26, 0.22)
	caverns.ambience_cue = "amb_shallow"
	caverns.motes = 1.0
	caverns.mote_colour = Color(0.55, 0.82, 0.95, 0.30)
	caverns.spawn_weights = {"glowling": 7.0, "molo": 4.0, "kryx": 3.0, "grib": 1.0}
	_zones.append(caverns)

	var deep := Zone.new("rootlands_deep", "ROOTLANDS · DEEP STRATA", 150.0)
	deep.ambient = Color(0.115, 0.125, 0.185)
	deep.haze = Color(0.07, 0.08, 0.15, 0.30)
	deep.ambience_cue = "amb_deep"
	deep.motes = 1.3
	deep.mote_colour = Color(0.62, 0.52, 0.95, 0.32)
	deep.spawn_weights = {"glowling": 4.0, "kryx": 7.0, "molo": 2.0, "aberrant": 0.35}
	_zones.append(deep)

	var abyss := Zone.new("rootlands_threshold", "ROOTLANDS · THRESHOLD", 265.0)
	abyss.ambient = Color(0.075, 0.075, 0.125)
	abyss.haze = Color(0.05, 0.05, 0.12, 0.38)
	abyss.ambience_cue = "amb_deep"
	abyss.motes = 1.5
	abyss.mote_colour = Color(0.72, 0.45, 1.0, 0.36)
	abyss.spawn_weights = {"kryx": 7.0, "glowling": 2.0, "aberrant": 1.2, "lumreaper": 0.08}
	_zones.append(abyss)


static func zones() -> Array[Zone]:
	_ensure()
	return _zones


static func zone_for_depth(metres: float) -> Zone:
	_ensure()
	var found: Zone = _zones[0]
	for z in _zones:
		if metres >= z.from_metres:
			found = z
		else:
			break
	return found


static func zone_by_id(id: String) -> Zone:
	_ensure()
	for z in _zones:
		if z.id == id:
			return z
	return _zones[0]


## Smoothly blended ambient colour, so crossing a zone line is a gradient
## rather than a visible step.
## Metres over which one zone's mood cross-fades into the next. The fade is
## anchored to the *upcoming* boundary rather than spread across the whole
## zone, so each zone has a stable look with a distinct threshold between
## them — which is what makes "I am somewhere else now" legible.
const BLEND_METRES: float = 14.0


static func ambient_for_depth(metres: float) -> Color:
	_ensure()
	var idx := _index_for(metres)
	var cur: Zone = _zones[idx]
	if idx + 1 >= _zones.size():
		return cur.ambient
	var nxt: Zone = _zones[idx + 1]
	return cur.ambient.lerp(nxt.ambient, _blend(metres, nxt))


static func haze_for_depth(metres: float) -> Color:
	_ensure()
	var idx := _index_for(metres)
	var cur: Zone = _zones[idx]
	if idx + 1 >= _zones.size():
		return cur.haze
	var nxt: Zone = _zones[idx + 1]
	return cur.haze.lerp(nxt.haze, _blend(metres, nxt))


static func _blend(metres: float, nxt: Zone) -> float:
	var start: float = nxt.from_metres - BLEND_METRES
	var t: float = clampf((metres - start) / BLEND_METRES, 0.0, 1.0)
	return smoothstep(0.0, 1.0, t)


static func _index_for(metres: float) -> int:
	var idx := 0
	for i in _zones.size():
		if metres >= _zones[i].from_metres:
			idx = i
	return idx
