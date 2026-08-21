class_name ScreenBase
extends Control
## Shared chrome for modal screens.

var ctx: Dictionary = {}
var ui = null
var body: VBoxContainer = null

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

func close() -> void:
	if ui:
		ui.close()

func patient_system():
	return get_tree().get_first_node_in_group("patient_system")

func records():
	return get_tree().get_first_node_in_group("records_system")

func suspicion():
	return get_tree().get_first_node_in_group("suspicion_system")

func shift_system():
	return get_tree().get_first_node_in_group("shift_system")

func player():
	return get_tree().get_first_node_in_group("player")

func treatment_system():
	return get_tree().get_first_node_in_group("treatment_system")

## Where the act happened, for the witnessing pass. A procedure performed at a
## bedside is seen from the doorway; the same procedure is not seen at all if
## the door is shut, which is the whole reason doors matter.
func player_position() -> Vector3:
	var p = player()
	return p.global_position if p != null else Vector3.ZERO

## Say what you are about to do, before you do it.
##
## Every hand-procedure asks this first, and the reason is that the grade at the
## end is measured against the ANSWER. Doing either job well is rewarded and
## doing either one badly is punished, so there is no coasting: declaring a
## treatment and then fumbling it is malpractice in front of witnesses, and
## declaring harm and fumbling it is worse than both.
##
## It is also the only screen in the game where the player is allowed to say the
## quiet part, which is why it is phrased plainly instead of in ward euphemism.
## Nobody else can hear this. The euphemisms start again on the chart.
func intent_gate(v: VBoxContainer, treat_note: String, worsen_note: String,
		cb: Callable) -> void:
	v.add_child(UIKit.label("Before you touch them, decide what this is.",
		15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.spacer(4))
	v.add_child(_intent_option("treat", treat_note, UIKit.GOOD, cb))
	v.add_child(_intent_option("worsen", worsen_note, UIKit.BAD, cb))
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.label(
		"Whichever you pick, you are marked on how well you do it.",
		13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER, true))
	v.add_child(UIKit.button("Leave them for now", close))

func _intent_option(intent: String, note: String, tint: Color, cb: Callable) -> Control:
	var spec: Dictionary = Procedures.INTENTS[intent]
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 6, 2, tint)
	var bv := UIKit.vbox(3)
	bv.add_child(UIKit.label(String(spec["label"]), 19, tint))
	bv.add_child(UIKit.label(note, 14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	bv.add_child(UIKit.button("Begin", func(): cb.call(intent)))
	p.add_child(bv)
	return p

## A sentence the first time a phase of the game happens to you, and never
## again. Kept here rather than in the tutorial system because the tutorial runs
## on day one and these can arrive on day nine — what matters is that the first
## letter and the first evening are things the game told you about rather than
## things that happened to you.
func first_time_note(v: VBoxContainer, key: String) -> void:
	var flag := "seen_phase_" + key
	if GameState.flag(flag, false):
		return
	GameState.set_flag(flag, true)
	var text := String(TutorialSystem.PHASE_NOTES.get(key, ""))
	if text == "":
		return
	var box := UIKit.panel(UIKit.NOTE, 6, 1, UIKit.ACCENT)
	box.add_child(UIKit.label(text, 15, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(box)

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
