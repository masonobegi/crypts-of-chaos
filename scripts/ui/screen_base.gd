class_name ScreenBase
extends Control
## Shared chrome for modal screens.

## Does this screen stop the world while it is up?
##
## True for anything that takes your whole attention — the morning handover.
## False for a card you read while standing in front of somebody, so that they
## carry on being a person while you decide what to do about them.
var pauses_world := true

var ctx: Dictionary = {}
var ui = null
var body: VBoxContainer = null
var _card_outer: VBoxContainer = null

## Every modal screen is a sheet of paper on a clipboard.
##
## The red margin rule down the left is doing most of the work: it is the one
## mark that says "form" before a single word has been read, and it costs three
## pixels. Above it goes a coloured band and the heading in capitals over a
## double rule, which is what the top of every printed record in the world
## looks like.
func shell(width: float, height: float, heading: String, subheading := "") -> VBoxContainer:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background())
	var panel := UIKit.center_panel(width, height)
	add_child(panel)

	var sheet := UIKit.hbox(0)
	panel.add_child(sheet)
	var margin := ColorRect.new()
	margin.color = UIKit.MARGIN_RED
	margin.custom_minimum_size.x = 3
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(margin)
	sheet.add_child(UIKit.spacer(14, false))

	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_child(v)
	if heading != "":
		v.add_child(UIKit.chart_header(heading))
	if subheading != "":
		v.add_child(UIKit.label(subheading, 14, UIKit.INK_DIM))
	body = v
	return v

## The same sheet, pinned to the right, with the world left visible behind it.
##
## "I still want the patient's physical body in front of me — I'm just saying
## the actions and dialogue should be on a card so it is easier to handle."
## Exactly right, and the dimmer was the problem: it replaced the person you had
## just walked up to with a menu about them. No dimmer here, and the form sits
## off to one side so they are still in shot, still breathing, still reacting.
func card_shell(width: float, height: float, heading: String, subheading := "") -> VBoxContainer:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A PanelContainer grows past its minimum size to fit its content, so a card
	# with one option too many simply ran off the bottom of the screen and took
	# its last button with it. Cap it against the window and scroll the body.
	# Clear of the HUD plates, which are about ninety tall, and no more. The old
	# margin of 116 left fifty pixels of nothing above and below a card that had
	# a row of itself under the fold.
	# ...AND THE 52px THE PLACER NUDGES IT DOWN.
	#
	# `UIKit.place` offsets a side panel by `-height * 0.5 + 52.0`, so a card
	# capped at exactly `viewport - 84` finished 10px BELOW the bottom of the
	# window on every machine — the viewport is pinned at 1600x900 with
	# canvas_items stretch, so it was identical on every monitor rather than a
	# stray-resolution bug. The patient card is the only one that reaches the
	# cap, and it is the screen the player lives in: its bottom border, its
	# content margin and the last button's corner all fell off the screen.
	height = minf(height, get_viewport_rect().size.y - 84.0 - 52.0)
	var panel := UIKit.side_panel(width, height)
	add_child(panel)

	var sheet := UIKit.hbox(0)
	panel.add_child(sheet)
	var margin := ColorRect.new()
	margin.color = UIKit.MARGIN_RED
	margin.custom_minimum_size.x = 3
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(margin)
	sheet.add_child(UIKit.spacer(12, false))

	var v := UIKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_child(v)
	if heading != "":
		v.add_child(UIKit.chart_header(heading))
	if subheading != "":
		v.add_child(UIKit.label(subheading, 14, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	# The header stays put; everything the screen adds goes in the scrolling
	# part, so `body` is the inner box rather than `v`.
	var inner := UIKit.vbox(8)
	v.add_child(UIKit.scroll(inner))
	_card_outer = v
	body = inner
	return inner

## Pin a control below the scrolling part of a card.
##
## The way out of a screen must never be the thing you have to scroll to find.
func card_footer(c: Control) -> void:
	if _card_outer == null:
		body.add_child(c)
		return
	_card_outer.add_child(UIKit.spacer(6))
	_card_outer.add_child(c)

func close() -> void:
	if ui:
		ui.close()

func patient_system():
	return get_tree().get_first_node_in_group("patient_system")

func suspicion():
	return get_tree().get_first_node_in_group("suspicion_system")

func player():
	return get_tree().get_first_node_in_group("player")

# The accessors for the records, shift and treatment systems went with those
# systems, and so did the intent gate every hand-procedure opened with. What a
# screen used to ask those systems for it now asks the ward day, which each
# screen reaches for itself.

## Rebuild the whole screen in place — simpler and less bug-prone than trying to
## patch individual widgets after an action changes the underlying data.
func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	body = null
	call_deferred("_build")

func _ready() -> void:
	_build()

func _build() -> void:
	pass
