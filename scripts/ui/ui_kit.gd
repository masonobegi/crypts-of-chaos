class_name UIKit
extends RefCounted
## Tiny procedural UI toolkit. Every screen in the game is built from these, so
## there are no .tscn UI files to keep in sync with the code.

## PAPER.
##
## Every menu in the game used to be the same dark blue-grey box, and the
## playtest note was simply "the menus are still really boring — spice it up,
## make it doctory". They are paperwork now: manila card, black ink, a red
## margin rule down the left and a ruled header band across the top, because
## that is what everything in a hospital that is not a person is.
##
## The HUD stays dark and keeps its own explicit colours — it is an overlay on
## a lit 3D room, and paper floating in front of a ward reads as a bug.
const BG := Color(0.09, 0.11, 0.13, 0.96)
const BG_SOLID := Color(0.09, 0.11, 0.13, 1.0)
const PANEL := Color(0.93, 0.91, 0.85, 1.0)          ## manila
const PANEL_LIGHT := Color(0.975, 0.966, 0.938, 1.0) ## a fresh sheet
const INK := Color(0.12, 0.13, 0.15)
const INK_DIM := Color(0.40, 0.42, 0.45)
const ACCENT := Color(0.05, 0.40, 0.40)
const GOOD := Color(0.10, 0.45, 0.23)
const WARN := Color(0.66, 0.41, 0.04)
const BAD := Color(0.68, 0.13, 0.12)
const MONEY := Color(0.10, 0.40, 0.21)
const SUS := Color(0.42, 0.18, 0.52)
## The HUD, and anything painted onto the 3D world, keeps the old light-on-dark
## palette. Paper belongs in a modal; a manila readout floating in front of a
## lit ward reads as a bug.
const HUD_INK := Color(0.90, 0.93, 0.92)
const HUD_DIM := Color(0.62, 0.67, 0.68)
const HUD_ACCENT := Color(0.35, 0.78, 0.72)
const HUD_GOOD := Color(0.42, 0.80, 0.52)
const HUD_WARN := Color(0.94, 0.70, 0.28)
const HUD_BAD := Color(0.90, 0.36, 0.32)
const HUD_MONEY := Color(0.55, 0.85, 0.60)
const HUD_SUS := Color(0.80, 0.55, 0.90)

## The margin rule down every form in the world.
const MARGIN_RED := Color(0.78, 0.30, 0.28)
## Tinted paper for the boxes inside a form. Which one a box gets is decided by
## what it is telling you, not by a colour picked per screen — that is how
## twenty-eight hand-mixed dark greys happened in the first place.
const NOTE := Color(0.895, 0.876, 0.812, 1.0)
const NOTE_GOOD := Color(0.855, 0.900, 0.845, 1.0)
const NOTE_WARN := Color(0.955, 0.905, 0.775, 1.0)
const NOTE_BAD := Color(0.955, 0.862, 0.845, 1.0)

static func stylebox(color: Color, radius := 3, border := 0, border_color := ACCENT) -> StyleBoxFlat:
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

## A box on a form. Radius is deliberately small everywhere — paper does not
## have rounded corners, and an 8px radius on a manila card reads as a phone.
static func panel(color := PANEL, radius := 3, border := 0, border_color := ACCENT) -> PanelContainer:
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

## A button is a slip of card with an ink rule round it and a coloured tab down
## the left, like the tab on a divider in a filing drawer.
static func button(text: String, cb: Callable, color := PANEL_LIGHT, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	# Ink on paper is the default and is right for the pale buttons the paper
	# theme is made of. A caller who hands in a DARK colour is asking for the
	# one emphatic button on the page, and ink on dark teal is the least
	# readable control on a screen full of readable ones — so the text flips.
	var dark: bool = color.get_luminance() < 0.42
	var ink: Color = Color(0.95, 0.99, 0.97) if dark else INK
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1) if dark else ACCENT)
	b.add_theme_color_override("font_pressed_color", ink)
	b.add_theme_color_override("font_focus_color", ink)
	b.add_theme_stylebox_override("normal", _slip(color, ACCENT, 4))
	b.add_theme_stylebox_override("hover", _slip(color.lightened(0.06), ACCENT, 8))
	b.add_theme_stylebox_override("pressed", _slip(color.darkened(0.10), ACCENT, 8))
	b.add_theme_stylebox_override("disabled", _slip(color.darkened(0.05), INK_DIM, 4))
	b.add_theme_color_override("font_disabled_color", INK_DIM)
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	# Every button in the game makes a noise now, and a different one under the
	# cursor. Asked for by name after the second playtest — "sound effects for
	# all the things I can do" — and it is the single cheapest piece of game
	# feel available: a menu with no click is a menu you are not sure you
	# pressed.
	b.pressed.connect(func(): AudioMgr.play("beep", -20.0, 1.18))
	b.mouse_entered.connect(func(): AudioMgr.play("tick", -30.0, 1.45))
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

## A labelled slider with its value written out beside it.
##
## `fmt` is a Callable(float) -> String so a volume can read "70%", a
## sensitivity "1.00x" and a field of view "78" without three widgets.
static func slider(text: String, value: float, min_v: float, max_v: float,
		step: float, on_change: Callable, fmt := Callable()) -> Control:
	var row_box := hbox(10)
	row_box.custom_minimum_size.y = 34
	var name_label := label(text, 15, INK, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size.x = 200
	row_box.add_child(name_label)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(220, 24)
	row_box.add_child(sl)

	var readout := label("", 15, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	readout.custom_minimum_size.x = 76
	row_box.add_child(readout)

	var write := func(v: float) -> void:
		readout.text = (fmt.call(v) if fmt.is_valid() else "%.2f" % v)
	write.call(value)
	sl.value_changed.connect(func(v: float) -> void:
		write.call(v)
		on_change.call(v))
	return row_box

## A labelled on/off switch. A CheckButton rather than a checkbox because at a
## glance "is this on" should be readable without reading.
static func toggle(text: String, value: bool, on_change: Callable) -> Control:
	var row_box := hbox(10)
	row_box.custom_minimum_size.y = 34
	var name_label := label(text, 15, INK, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size.x = 200
	row_box.add_child(name_label)
	var spacer_ctl := Control.new()
	spacer_ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(spacer_ctl)
	# A labelled button rather than a CheckButton. Godot's default CheckButton
	# theme draws the OFF state as a small grey dot with no track, which at a
	# glance is indistinguishable from a bullet point — the first screenshot of
	# this screen had "Invert look" and "Fullscreen" reading as decoration.
	# ON and OFF in words, in colour, cannot be misread.
	var state := value
	var b := button("", Callable(), PANEL_LIGHT, 96)
	var paint := func() -> void:
		b.text = "ON" if state else "OFF"
		b.add_theme_color_override("font_color", GOOD if state else INK_DIM)
		b.add_theme_stylebox_override("normal",
			stylebox(Color(0.16, 0.30, 0.24) if state else Color(0.20, 0.21, 0.24), 6))
	paint.call()
	b.pressed.connect(func() -> void:
		state = not state
		paint.call()
		on_change.call(state))
	row_box.add_child(b)
	return row_box

static func rule(color := Color(INK.r, INK.g, INK.b, 0.22)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.y = 1
	return r

## A label/value row — the workhorse of every panel in the game.
## `key_color` exists because this is used for two different things: a label and
## its value ("Shifts worked ... 0"), where the label is the quiet half, and a
## heading with a price on the end of it, where the heading is the loud half and
## a dim one made the most important word on the row the faintest.
static func row(key: String, value: String, value_color := INK, size := 15,
		key_color := INK_DIM) -> HBoxContainer:
	var h := hbox(8)
	var k := label(key, size, key_color)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := label(value, size, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	h.add_child(k)
	h.add_child(v)
	return h

## A 0..1 bar. Used for reputations, exposure and suspicion.
## A 0..1 bar. Built from two ColorRects inside a fixed-size Control rather than
## a PanelContainer: a PanelContainer in a VBox stretches to the full row width,
## which made a nearly-empty bar read as an empty text field.
static func bar(value: float, color := ACCENT, width := 180.0, height := 8.0) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(width, height)
	root.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.10)
	back.position = Vector2.ZERO
	back.size = Vector2(width, height)
	root.add_child(back)

	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2.ZERO
	fill.size = Vector2(maxf(2.0, width * clampf(value, 0.0, 1.0)), height)
	root.add_child(fill)
	return root

## "3h 20m", "45m", "now". Used everywhere a deadline is shown, so that the
## shift clock, the appointment list and the tablet all count down in the same
## words.
static func span_str(minutes: int) -> String:
	if minutes <= 0:
		return "now"
	if minutes < 60:
		return "%dm" % minutes
	if minutes % 60 == 0:
		return "%dh" % int(minutes / 60)
	return "%dh %02dm" % [int(minutes / 60), minutes % 60]

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
		# Missing until a card needed to sit against the right-hand edge, at
		# which point it silently anchored top-left and placed itself six
		# hundred pixels off the side of the screen.
		Control.PRESET_CENTER_LEFT: ay = 0.5
		Control.PRESET_CENTER_RIGHT: ax = 1.0; ay = 0.5
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
	var p := panel(PANEL, 3, 2, Color(0.22, 0.23, 0.25))
	place(p, Control.PRESET_CENTER, -width * 0.5, -height * 0.5, width, height)
	p.custom_minimum_size = Vector2(width, height)
	return p

## A form pinned to one side of the screen, leaving the world visible.
##
## Used for anything you do while standing in front of a person: the whole point
## of walking up to somebody is that they are there, and a centred modal with a
## dimmer behind it replaces them with a menu. The card goes to the right, they
## stay in the middle, and you can watch them react to what you pick.
static func side_panel(width: float, height: float) -> PanelContainer:
	var p := panel(PANEL, 3, 2, Color(0.22, 0.23, 0.25))
	# A PanelContainer grows past its minimum to fit its content in BOTH
	# directions, and the width had no cap: one row of four wide buttons pushed
	# the whole card off the right-hand edge of the screen and took its author
	# column with it. Clip the child instead — a row that will not fit is a
	# layout to fix, not a card to lose.
	p.clip_contents = true
	# Nudged down so the top of the card clears the money panel in the corner.
	place(p, Control.PRESET_CENTER_RIGHT, -width - 36.0, -height * 0.5 + 52.0, width, height)
	p.custom_minimum_size = Vector2(width, height)
	return p

## A scrolling region.
##
## THE MINIMUM HEIGHT IS LOAD-BEARING. A ScrollContainer's own minimum size is
## zero, so putting one inside another gives the inner one exactly that — it
## renders as nothing, silently, and every control in it disappears while the
## screen around it looks entirely normal. The redesigned patient card, chart
## and handover all did that, and the shipped game had two verbs instead of six,
## an unreachable chart, and a handover that asked a question with no answers.
## A scrolling region.
##
## THE MINIMUM HEIGHT IS LOAD-BEARING. A ScrollContainer's own minimum size is
## zero, so nesting one inside another gives the inner one exactly that: it
## renders as nothing while the screen around it looks entirely normal, and — as
## this project found the hard way — a ScrollContainer CLIPS its child rather
## than resizing it, so every hidden control still reports a perfectly healthy
## size. The shipped patient card had five of its six verbs invisible, the chart
## was unreachable and the handover asked a question with no answers on screen.
static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.custom_minimum_size.y = 120.0

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

## The card-with-a-tab stylebox every button uses.
static func _slip(color: Color, tab: Color, tab_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.border_width_left = tab_w
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = tab
	sb.set_border_width(SIDE_TOP, 1)
	sb.set_border_width(SIDE_RIGHT, 1)
	sb.set_border_width(SIDE_BOTTOM, 1)
	sb.set_border_width(SIDE_LEFT, tab_w)
	return sb

## The band across the top of a form: a coloured bar, the title in capitals,
## and the double rule underneath that every printed record in the world has.
static func chart_header(text: String, tint := ACCENT) -> Control:
	var v := vbox(0)
	var band := ColorRect.new()
	band.color = tint
	band.custom_minimum_size.y = 7
	v.add_child(band)
	v.add_child(spacer(6))
	var t := Label.new()
	t.text = text.to_upper()
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", INK)
	v.add_child(t)
	v.add_child(spacer(4))
	var thick := ColorRect.new()
	thick.color = INK
	thick.custom_minimum_size.y = 2
	v.add_child(thick)
	v.add_child(spacer(2))
	var thin := ColorRect.new()
	thin.color = Color(INK.r, INK.g, INK.b, 0.45)
	thin.custom_minimum_size.y = 1
	v.add_child(thin)
	return v

## A rubber stamp: capitals in a box, at an angle, in one flat colour. Used for
## the handful of statuses that ought to hit you before you have read anything.
static func stamp(text: String, tint := BAD) -> Control:
	# LET THE CONTAINER DO THE LAYOUT.
	#
	# This used to be a PanelContainer parented to a plain Control, positioned
	# and sized by hand. A plain Control is not a container, so nothing ever laid
	# the panel out: it kept a zero size, the Label inside it sat at (0,0) on the
	# top border, and the border was drawn through the middle of the letters with
	# the final T of "FLAGGED FOR AUDIT" outside the box. That is the payoff
	# image of an entire shift and it is seen twice a night.
	#
	# Three rounds of measuring the string by hand and positioning the label by
	# hand each got closer and none got it right, because everything about a
	# Control's size outside the tree is a guess. Returned as a bare
	# PanelContainer instead: it goes straight into the card's VBox, which is a
	# real container, so Godot sizes it from the Label's own minimum size the way
	# it sizes everything else on the card. SHRINK_BEGIN so the VBox does not
	# stretch it to the full width — a stamp is the width of what it says.
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, 0.10)
	sb.border_color = tint
	sb.set_border_width_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", tint)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	# The tilt is what makes it read as a rubber stamp rather than a button.
	# Rotation is not touched by container layout, so this survives.
	p.rotation = -0.055
	p.pivot_offset = Vector2(40, 17)
	return p

## A form field: a label, a dotted leader, and a value. The leader is what makes
## a row of these read as a document rather than as a settings screen.
static func field(key: String, value: String, value_color := INK, size := 15) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(label(key, size, INK_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var leader := label(" " + ". ".repeat(60), size, Color(INK.r, INK.g, INK.b, 0.28))
	leader.clip_text = true
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(leader)
	h.add_child(label(value, size, value_color, HORIZONTAL_ALIGNMENT_RIGHT))
	return h
