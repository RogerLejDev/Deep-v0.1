class_name IconFactory
extends RefCounted
## Item icons, composed as SVG markup from a shape family plus the item's
## palette and rasterised at runtime.
##
## This is why adding a new resource to ItemDB needs no art: pick one of the
## shape families below, give it two colours and an optional glow, and the
## icon is generated. The families are deliberately silhouette-distinct so a
## 48px slot on a phone is still readable at a glance.

const SHAPES: Array[String] = [
	"clod", "ore", "shard", "fibre", "cap", "relic",
	"pick", "plank", "torch", "flask", "lantern",
]


static func icon_for(item_id: String, size_px: int = 48) -> ImageTexture:
	var def := ItemDB.get_item(item_id)
	var markup := _markup(def)
	return SvgFactory.from_markup(markup, item_id, size_px, 64.0)


static func _markup(def: ItemDef) -> String:
	var p := def.icon_primary.to_html(false)
	var s := def.icon_secondary.to_html(false)
	var glow := def.icon_glow
	var head := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
	var defs := _defs(p, s, glow)
	var body := ""
	match def.icon_shape:
		"ore": body = _ore()
		"shard": body = _shard()
		"fibre": body = _fibre()
		"cap": body = _cap()
		"relic": body = _relic()
		"pick": body = _pick()
		"plank": body = _plank()
		"torch": body = _torch()
		"flask": body = _flask()
		"lantern": body = _lantern()
		_: body = _clod()
	var halo := ""
	if glow.a > 0.0 and (glow.r + glow.g + glow.b) > 0.05:
		halo = '<circle cx="32" cy="32" r="30" fill="url(#g_halo)"/>'
	return head + defs + halo + body + "</svg>"


static func _defs(p: String, s: String, glow: Color) -> String:
	var gh := glow.to_html(false)
	return (
		'<defs>'
		+ '<linearGradient id="g_main" x1="0.15" y1="0" x2="0.85" y2="1">'
		+ '<stop offset="0%%" stop-color="#%s"/>' % p
		+ '<stop offset="62%%" stop-color="#%s"/>' % p
		+ '<stop offset="100%%" stop-color="#%s"/></linearGradient>' % s
		+ '<linearGradient id="g_alt" x1="0" y1="0" x2="0.6" y2="1">'
		+ '<stop offset="0%%" stop-color="#%s"/>' % s
		+ '<stop offset="100%%" stop-color="#%s"/></linearGradient>' % p
		+ '<radialGradient id="g_halo" cx="50%" cy="50%" r="50%">'
		+ '<stop offset="30%%" stop-color="#%s" stop-opacity="0.45"/>' % gh
		+ '<stop offset="100%%" stop-color="#%s" stop-opacity="0"/></radialGradient>' % gh
		+ '<radialGradient id="g_spark" cx="50%" cy="50%" r="50%">'
		+ '<stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.95"/>'
		+ '<stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
		+ '</defs>'
	)


# --- Shape families ----------------------------------------------------------

static func _clod() -> String:
	# Three irregular lumps. Reads as "loose material".
	return (
		'<path d="M14 44 q-4 -11 6 -15 q12 -5 20 2 q9 7 3 15 q-11 6 -29 -2 z" fill="url(#g_main)"/>'
		+ '<path d="M19 33 q7 -6 15 -3 q-6 4 -15 3 z" fill="#FFFFFF" opacity="0.16"/>'
		+ '<path d="M38 20 q9 -3 12 4 q-5 5 -12 1 z" fill="url(#g_alt)"/>'
		+ '<path d="M12 24 q6 -4 9 1 q-4 4 -9 0 z" fill="url(#g_alt)" opacity="0.85"/>'
		+ '<ellipse cx="26" cy="47" rx="14" ry="3" fill="#000000" opacity="0.22"/>'
	)


static func _ore() -> String:
	# Rock matrix (secondary) with bright metallic nodules (primary).
	return (
		'<path d="M11 42 q-3 -13 8 -18 q14 -6 24 2 q10 8 3 17 q-13 7 -35 -1 z" fill="url(#g_alt)"/>'
		+ '<circle cx="23" cy="31" r="6" fill="url(#g_main)"/>'
		+ '<circle cx="21.5" cy="29" r="2" fill="#FFFFFF" opacity="0.55"/>'
		+ '<circle cx="36" cy="36" r="4.6" fill="url(#g_main)"/>'
		+ '<circle cx="35" cy="34.6" r="1.5" fill="#FFFFFF" opacity="0.45"/>'
		+ '<circle cx="31" cy="24" r="3.1" fill="url(#g_main)"/>'
		+ '<circle cx="44" cy="28" r="2.4" fill="url(#g_main)" opacity="0.9"/>'
		+ '<ellipse cx="27" cy="46" rx="15" ry="3" fill="#000000" opacity="0.22"/>'
	)


static func _shard() -> String:
	# Tall faceted crystal with an internal highlight.
	return (
		'<path d="M32 6 l13 20 l-6 30 l-15 0 l-7 -29 z" fill="url(#g_main)"/>'
		+ '<path d="M32 6 l13 20 l-13 5 z" fill="#FFFFFF" opacity="0.32"/>'
		+ '<path d="M32 6 l-15 21 l15 4 z" fill="#FFFFFF" opacity="0.12"/>'
		+ '<path d="M32 11 l0 44" stroke="#FFFFFF" stroke-width="1.6" opacity="0.35"/>'
		+ '<path d="M48 18 l5 9 l-3 12 l-5 -1 z" fill="url(#g_alt)" opacity="0.9"/>'
		+ '<circle cx="32" cy="24" r="7" fill="url(#g_spark)"/>'
	)


static func _fibre() -> String:
	# A bound coil of strands.
	return (
		'<path d="M10 20 q22 -10 44 4" fill="none" stroke="url(#g_main)" stroke-width="5" stroke-linecap="round"/>'
		+ '<path d="M9 30 q24 -8 46 3" fill="none" stroke="url(#g_main)" stroke-width="5" stroke-linecap="round"/>'
		+ '<path d="M11 40 q22 -6 42 5" fill="none" stroke="url(#g_alt)" stroke-width="5" stroke-linecap="round"/>'
		+ '<path d="M13 49 q20 -4 38 4" fill="none" stroke="url(#g_alt)" stroke-width="4" stroke-linecap="round"/>'
		+ '<path d="M27 14 q6 20 2 42 l8 0 q4 -22 -2 -41 z" fill="url(#g_alt)" opacity="0.95"/>'
		+ '<path d="M28 20 q7 1 8 3" fill="none" stroke="#FFFFFF" stroke-width="1" opacity="0.3"/>'
	)


static func _cap() -> String:
	# Mushroom: dome, gills, stalk.
	return (
		'<path d="M14 36 q0 -22 18 -22 q18 0 18 22 q-18 7 -36 0 z" fill="url(#g_main)"/>'
		+ '<path d="M20 20 q8 -5 14 -1 q-7 3 -14 1 z" fill="#FFFFFF" opacity="0.24"/>'
		+ '<circle cx="24" cy="26" r="2.6" fill="#FFFFFF" opacity="0.3"/>'
		+ '<circle cx="38" cy="23" r="2" fill="#FFFFFF" opacity="0.25"/>'
		+ '<path d="M14 36 q18 7 36 0 q-18 5 -36 0 z" fill="#000000" opacity="0.3"/>'
		+ '<path d="M27 37 q5 1 10 0 l-2 17 l-6 0 z" fill="url(#g_alt)"/>'
		+ '<ellipse cx="32" cy="55" rx="9" ry="2.6" fill="#000000" opacity="0.22"/>'
	)


static func _relic() -> String:
	# Cut masonry fragment with glyphs.
	return (
		'<path d="M16 12 l30 3 l4 32 l-16 7 l-20 -8 z" fill="url(#g_alt)"/>'
		+ '<path d="M20 17 l22 2 l3 25 l-12 5 l-15 -6 z" fill="none" stroke="url(#g_main)" stroke-width="1.6" opacity="0.8"/>'
		+ '<path d="M24 24 l14 1 M24 31 l10 1 M24 38 l15 1" stroke="url(#g_main)" stroke-width="2.2" opacity="0.9"/>'
		+ '<circle cx="41" cy="31" r="2" fill="url(#g_main)"/>'
		+ '<path d="M16 12 l30 3 l-4 4 l-24 -2 z" fill="#FFFFFF" opacity="0.12"/>'
	)


static func _pick() -> String:
	# Pickaxe: haft plus asymmetric head.
	return (
		'<path d="M18 54 l26 -30 l6 4 l-26 30 z" fill="url(#g_alt)"/>'
		+ '<path d="M18 54 l7 -8 l6 4 l-7 8 z" fill="#241A10"/>'
		+ '<path d="M41 18 q16 -9 24 3 q-14 1 -19 9 z" fill="url(#g_main)"/>'
		+ '<path d="M41 18 q-12 -7 -9 -14 q11 1 15 8 z" fill="url(#g_main)"/>'
		+ '<path d="M38 15 l11 7 l-4 6 l-11 -7 z" fill="#FFFFFF" opacity="0.18"/>'
		+ '<path d="M44 10 q10 -2 15 5" fill="none" stroke="#FFFFFF" stroke-width="1.6" opacity="0.4"/>'
	)


static func _plank() -> String:
	# Two stacked boards.
	return (
		'<path d="M6 22 l52 -4 l0 12 l-52 4 z" fill="url(#g_main)"/>'
		+ '<path d="M6 22 l52 -4 l0 2.6 l-52 4 z" fill="#FFFFFF" opacity="0.22"/>'
		+ '<path d="M6 38 l52 -4 l0 12 l-52 4 z" fill="url(#g_alt)"/>'
		+ '<path d="M6 38 l52 -4 l0 2.6 l-52 4 z" fill="#FFFFFF" opacity="0.14"/>'
		+ '<path d="M18 20 l0 12 M36 18.6 l0 12 M18 36 l0 12 M40 34.6 l0 12" stroke="#000000" stroke-width="0.9" opacity="0.25"/>'
	)


static func _torch() -> String:
	# Stick plus flame, with the glow halo doing the heavy lifting.
	return (
		'<path d="M29 32 l6 0 l-1 26 l-4 0 z" fill="url(#g_alt)"/>'
		+ '<path d="M27 30 l10 0 l0 4 l-10 0 z" fill="#3A2B1B"/>'
		+ '<path d="M32 4 q10 10 8 18 q-2 8 -8 9 q-6 -1 -8 -9 q-2 -8 8 -18 z" fill="url(#g_main)"/>'
		+ '<path d="M32 12 q5 7 4 12 q-1 4 -4 5 q-3 -1 -4 -5 q-1 -5 4 -12 z" fill="#FFF6D8" opacity="0.9"/>'
		+ '<circle cx="32" cy="22" r="10" fill="url(#g_spark)" opacity="0.5"/>'
	)


static func _flask() -> String:
	# Round-bottomed flask with a stopper and a liquid line.
	return (
		'<path d="M27 10 l10 0 l0 8 q12 6 12 20 q0 14 -17 14 q-17 0 -17 -14 q0 -14 12 -20 z" fill="url(#g_alt)" opacity="0.55"/>'
		+ '<path d="M18 36 q14 -6 28 0 q2 14 -14 14 q-16 0 -14 -14 z" fill="url(#g_main)"/>'
		+ '<path d="M22 38 q10 -4 20 0" fill="none" stroke="#FFFFFF" stroke-width="1.4" opacity="0.45"/>'
		+ '<circle cx="26" cy="43" r="2" fill="#FFFFFF" opacity="0.4"/>'
		+ '<circle cx="36" cy="46" r="1.4" fill="#FFFFFF" opacity="0.3"/>'
		+ '<path d="M25 6 l14 0 l0 6 l-14 0 z" fill="#3A2B1B"/>'
	)


static func _lantern() -> String:
	# Caged shard on a hook.
	return (
		'<path d="M32 4 q8 0 8 7 l-4 0 q0 -3 -4 -3 q-4 0 -4 3 l-4 0 q0 -7 8 -7 z" fill="url(#g_alt)"/>'
		+ '<path d="M18 16 l28 0 l-3 6 l-22 0 z" fill="url(#g_alt)"/>'
		+ '<path d="M21 22 l22 0 l3 26 l-28 0 z" fill="url(#g_alt)" opacity="0.5"/>'
		+ '<path d="M26 26 l12 0 l2 18 l-16 0 z" fill="url(#g_main)"/>'
		+ '<path d="M32 27 l5 8 l-2 9 l-6 0 l-2 -9 z" fill="#FFF8E0" opacity="0.92"/>'
		+ '<path d="M21 48 l22 0 l2 6 l-26 0 z" fill="url(#g_alt)"/>'
		+ '<path d="M27 22 l1 26 M37 22 l-1 26" stroke="#000000" stroke-width="1.2" opacity="0.35"/>'
		+ '<circle cx="32" cy="36" r="11" fill="url(#g_spark)" opacity="0.45"/>'
	)
