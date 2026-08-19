class_name UIKit
extends RefCounted
## Tiny procedural UI toolkit. Every screen in the game is built from these, so
## there are no .tscn UI files to keep in sync with the code.

const BG := Color(0.09, 0.11, 0.13, 0.96)
const BG_SOLID := Color(0.09, 0.11, 0.13, 1.0)
const PANEL := Color(0.14, 0.17, 0.20, 0.97)
const PANEL_LIGHT := Color(0.19, 0.23, 0.27, 1.0)
const INK := Color(0.90, 0.93, 0.92)
const INK_DIM := Color(0.62, 0.67, 0.68)
const ACCENT := Color(0.35, 0.78, 0.72)
const GOOD := Color(0.42, 0.80, 0.52)
const WARN := Color(0.94, 0.70, 0.28)
const BAD := Color(0.90, 0.36, 0.32)
const MONEY := Color(0.55, 0.85, 0.60)
const SUS := Color(0.80, 0.55, 0.90)

static func stylebox(color: Color, radius := 6, border := 0, border_color := ACCENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if border > 0:
		sb.border_width_left = border
		sb.border_width_right = border
		sb.border_width_top = border
		sb.border_width_bottom = border
		sb.border_color = border_color
	return sb

static func panel(color := PANEL, radius := 8, border := 0, border_color := ACCENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(color, radius, border, border_color))
	return p

## `wrap` is opt-in on purpose. A Label with autowrap inside a container that
## has no explicit width collapses to one character per line — which is exactly
## what the HUD clock did before this was a parameter. Only turn it on for text
## that has a width to wrap within.
static func label(text: String, size := 16, color := INK,
		align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l

static func title(text: String, size := 30, color := INK) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

static func rich(text: String, size := 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", INK)
	return r

static func button(text: String, cb: Callable, color := PANEL_LIGHT, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_stylebox_override("normal", stylebox(color, 6))
	b.add_theme_stylebox_override("hover", stylebox(color.lightened(0.12), 6, 2, ACCENT))
	b.add_theme_stylebox_override("pressed", stylebox(color.darkened(0.2), 6))
	b.add_theme_stylebox_override("disabled", stylebox(color.darkened(0.35), 6))
	b.add_theme_color_override("font_disabled_color", INK_DIM)
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func spacer(min_size := 0.0, vertical := true) -> Control:
	var c := Control.new()
	if vertical:
		c.custom_minimum_size.y = min_size
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL if min_size == 0.0 else 0
	else:
		c.custom_minimum_size.x = min_size
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL if min_size == 0.0 else 0
	return c

static func rule(color := Color(1, 1, 1, 0.12)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.y = 1
	return r

## A label/value row — the workhorse of every panel in the game.
static func row(key: String, value: String, value_color := INK, size := 15) -> HBoxContainer:
	var h := hbox(8)
	var k := label(key, size, INK_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := label(value, size, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	h.add_child(k)
	h.add_child(v)
	return h

## A 0..1 bar. Used for reputations, exposure and suspicion.
static func bar(value: float, color := ACCENT, width := 180.0, height := 8.0) -> Control:
	var back := PanelContainer.new()
	back.custom_minimum_size = Vector2(width, height)
	back.add_theme_stylebox_override("panel", stylebox(Color(1, 1, 1, 0.10), 3))
	var fill := ColorRect.new()
	fill.color = color
	fill.custom_minimum_size = Vector2(maxf(2.0, width * clampf(value, 0.0, 1.0)), height)
	fill.size_flags_horizontal = 0
	back.add_child(fill)
	return back

static func money_str(amount: int) -> String:
	var neg := amount < 0
	var s := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if neg else "$") + out

## Anchor a control to a screen edge with explicit offsets.
##
## Setting `position` on a Control that has non-zero anchors does NOT do what it
## looks like: the rect is derived from the offsets, so the node ends up with
## zero size and never draws. Several HUD blocks were invisible for exactly this
## reason. Always go through here.
## Anchors are set explicitly rather than via set_anchors_preset(), whose
## keep_offsets behaviour recomputes offsets from the node's current (zero) rect
## and quietly leaves the control unsized.
static func place(node: Control, preset: int, left: float, top: float,
		width: float, height: float) -> Control:
	var ax := 0.0
	var ay := 0.0
	match preset:
		Control.PRESET_TOP_RIGHT: ax = 1.0
		Control.PRESET_CENTER_TOP: ax = 0.5
		Control.PRESET_CENTER: ax = 0.5; ay = 0.5
		Control.PRESET_CENTER_BOTTOM: ax = 0.5; ay = 1.0
		Control.PRESET_BOTTOM_LEFT: ay = 1.0
		Control.PRESET_BOTTOM_RIGHT: ax = 1.0; ay = 1.0
	node.anchor_left = ax
	node.anchor_right = ax
	node.anchor_top = ay
	node.anchor_bottom = ay
	node.offset_left = left
	node.offset_top = top
	node.offset_right = left + width
	node.offset_bottom = top + height
	return node

static func full_screen(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node

static func center_panel(width: float, height: float) -> PanelContainer:
	var p := panel(BG_SOLID, 10, 2, Color(1, 1, 1, 0.10))
	place(p, Control.PRESET_CENTER, -width * 0.5, -height * 0.5, width, height)
	p.custom_minimum_size = Vector2(width, height)
	return p

static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

static func scroll_horizontal(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size.y = 44
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

static func dim_background(alpha := 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r

static func tier_color(tier: int) -> Color:
	return [INK_DIM, Color(0.90, 0.86, 0.55), WARN, Color(0.94, 0.52, 0.34), BAD][clampi(tier, 0, 4)]

static func rep_color(track: String, value: float) -> Color:
	# Government scrutiny is the one where high is bad.
	if track == "gov_scrutiny":
		return BAD if value > 0.4 else (WARN if value > 0.2 else GOOD)
	return GOOD if value > 0.6 else (WARN if value > 0.35 else BAD)
