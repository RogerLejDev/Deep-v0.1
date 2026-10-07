class_name UiKit
extends RefCounted
## DEEP's visual language for UI, in one place.
##
## No Godot default widgets survive to the screen: every panel, button and bar
## is built from these helpers so the whole interface reads as one designed
## thing. Everything is generated — no theme resource, no font files.

# --- Palette -----------------------------------------------------------------
const INK := Color(0.039, 0.051, 0.078, 0.94)
const INK_SOLID := Color(0.027, 0.035, 0.055, 1.0)
const EDGE := Color(0.165, 0.231, 0.278, 1.0)
const EDGE_HOT := Color(0.435, 0.847, 0.949, 0.9)
const TEXT := Color(0.788, 0.839, 0.871)
const TEXT_DIM := Color(0.424, 0.498, 0.549)
const TEXT_BRIGHT := Color(0.937, 0.969, 0.98)
const ACCENT := Color(0.435, 0.847, 0.949)
const ACCENT_WARM := Color(1.0, 0.698, 0.361)
const DANGER := Color(0.918, 0.357, 0.306)
const GOOD := Color(0.569, 0.843, 0.431)
const LEGEND := Color(1.0, 0.851, 0.361)

# --- Metrics -----------------------------------------------------------------
## Minimum touch target. 46 logical px at the 1280x720 base size is a
## comfortable thumb target on a 5" phone.
const TOUCH_MIN: float = 46.0
const RADIUS: int = 5


static func panel_style(
	fill: Color = INK,
	border: Color = EDGE,
	border_width: int = 1,
	radius: int = RADIUS
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func make_panel(fill: Color = INK, border: Color = EDGE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(fill, border))
	return p


static func label(
	text: String,
	size: int = 14,
	colour: Color = TEXT,
	align: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = align as HorizontalAlignment
	return l


## Small-caps-ish section heading with wide tracking.
static func heading(text: String, size: int = 13) -> Label:
	var l := label(_tracked(text.to_upper()), size, ACCENT)
	return l


static func body(text: String, size: int = 13, colour: Color = TEXT) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", colour)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _tracked(s: String) -> String:
	# Godot has no letter-spacing property for Label, so wide tracking on
	# headings is done with thin spaces. Cheap, and it reads right.
	var out := ""
	for i in s.length():
		out += s[i]
		if i < s.length() - 1:
			out += " "
	return out


static func button(text: String, min_height: float = TOUCH_MIN) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, min_height)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(0.29, 0.33, 0.37))
	b.add_theme_stylebox_override("normal", panel_style(Color(0.071, 0.094, 0.133, 0.9), EDGE))
	b.add_theme_stylebox_override("hover", panel_style(Color(0.106, 0.149, 0.196, 0.95), EDGE_HOT))
	b.add_theme_stylebox_override("pressed", panel_style(Color(0.055, 0.153, 0.196, 1.0), ACCENT))
	b.add_theme_stylebox_override("disabled", panel_style(Color(0.047, 0.059, 0.078, 0.7), Color(0.12, 0.15, 0.18)))
	return b


## The round action buttons on the right thumb cluster.
static func round_button(glyph: String, diameter: float, accent: Color = ACCENT) -> Button:
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(diameter * 0.30))
	b.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.92))
	b.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	var normal := panel_style(Color(0.055, 0.075, 0.106, 0.62), Color(accent.r, accent.g, accent.b, 0.45), 2, int(diameter * 0.5))
	var pressed := panel_style(Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.35, 0.85), accent, 2, int(diameter * 0.5))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", panel_style(Color(0.04, 0.05, 0.06, 0.4), Color(0.14, 0.16, 0.19), 2, int(diameter * 0.5)))
	return b


static func progress_bar(height: float, fill: Color, track: Color = Color(0.067, 0.086, 0.11, 0.9)) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(0.0, height)
	p.show_percentage = false
	p.max_value = 1.0
	p.value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = track
	bg.set_corner_radius_all(int(height * 0.5))
	bg.border_color = Color(0, 0, 0, 0.45)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(int(height * 0.5))
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p


static func separator(colour: Color = EDGE) -> Control:
	var c := ColorRect.new()
	c.color = colour
	c.custom_minimum_size = Vector2(0.0, 1.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Full-screen dim used behind modal panels.
static func scrim(alpha: float = 0.72) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.008, 0.012, 0.02, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


static func rarity_colour(rarity: int) -> Color:
	match rarity:
		CreatureData.Rarity.COMMON: return Color(0.62, 0.70, 0.64)
		CreatureData.Rarity.UNCOMMON: return ACCENT
		CreatureData.Rarity.RARE: return Color(0.72, 0.56, 0.98)
		CreatureData.Rarity.VERY_RARE: return ACCENT_WARM
		CreatureData.Rarity.LEGENDARY: return LEGEND
	return TEXT


static func toast_colour(kind: String) -> Color:
	match kind:
		"warn": return ACCENT_WARM
		"save": return GOOD
		"heal": return GOOD
		"zone": return ACCENT
		"variant": return Color(0.72, 0.56, 0.98)
		"legendary": return LEGEND
	return TEXT


static func format_metres(m: float) -> String:
	if m < 0.0:
		return "SURFACE"
	return "%d m" % int(round(m))


static func format_playtime(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var mi := (total % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, mi]
	return "%dm" % mi
