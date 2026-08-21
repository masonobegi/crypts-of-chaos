extends ScreenBase
## What happened, afterwards.
##
## The fight itself is not here any more — it happens in the room, between two
## bodies, because "the 2D minigame was pretty lame" and it was. This is the
## card that tells you what it cost, which is the one part of it that genuinely
## wants to be a piece of paper.

var _patient = null
var _result: Dictionary = {}
var _won := false

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	_result = Dictionary(ctx.get("result", {}))
	_won = bool(ctx.get("won", false))
	if _patient == null or _result.is_empty():
		close()
		return
	_build_after()

func _build_after() -> void:
	var tint: Color = UIKit.WARN if _won else UIKit.BAD
	var v := shell(760, 480, String(_result.get("label", "It is over")),
		_patient.display_name)
	v.add_child(UIKit.stamp("won" if _won else "lost", tint))
	var box := UIKit.panel(UIKit.NOTE, 4, 2, tint)
	var bv := UIKit.vbox(4)
	bv.add_child(UIKit.label(String(_result.get("line", "")), 16, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	if _won:
		bv.add_child(UIKit.field("Their stay", "+%d days" % int(
			ceil(float(_result.get("stay", 0.0)))), UIKit.MONEY))
		bv.add_child(UIKit.field("What they remember", "nothing", UIKit.GOOD))
	else:
		bv.add_child(UIKit.field("Billed to you",
			UIKit.money_str(int(_result.get("bill", 0))), UIKit.BAD))
		bv.add_child(UIKit.field("The rest of today", "gone", UIKit.BAD))
		bv.add_child(UIKit.field("Tonight", "you are in no state", UIKit.BAD))
	box.add_child(bv)
	v.add_child(box)
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.button("Right", close))

