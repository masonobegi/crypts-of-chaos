extends ScreenBase
## Ten past eight. She has the folder.
##
## Every question names the two documents that produced it, and the closing
## summary names the one that decided it. Nobody should ever leave this screen
## wondering what happened to them.

var _rv: ReviewSystem = null
var _last := ""
var _done := false

func _build() -> void:
	var w = ward()
	if w == null:
		close()
		return
	if _rv == null:
		_rv = ReviewSystem.new()
		_rv.begin(w.review_findings())
	pauses_world = true

	var v := card_shell(780, 700, "HANDOVER",
		"Sister Nkemelu has last night's folder")

	if _done or _rv.finished():
		_closing(v, w)
		return

	var f = _rv.current()
	v.add_child(UIKit.label("She turns a page.", 12, UIKit.INK_DIM))
	v.add_child(UIKit.label("\"%s\"" % f.question, 18, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.label("— looking at %s" % f.axis, 12, UIKit.INK_DIM))
	if _last != "":
		v.add_child(UIKit.rule())
		v.add_child(UIKit.label(_last, 14, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	var held: Array = w.held_ids()
	var opts := UIKit.vbox(6)
	for o in _rv.options(f, w.records):
		var choice: int = o["a"]
		opts.add_child(UIKit.button(String(o["text"]),
			func():
				var r := _rv.answer(choice, held)
				_last = String(r.get("effect", ""))
				if _rv.finished():
					_done = true
				rebuild(),
			UIKit.PANEL_LIGHT))
	v.add_child(UIKit.scroll(opts))

## The part that has to be legible. Verdict, the line that caused it, and the
## whole conversation underneath so it can be read back.
func _closing(v: VBoxContainer, w) -> void:
	var o := _rv.outcome()
	var verdict := String(o["verdict"])
	var tint := UIKit.GOOD
	if verdict == ReviewSystem.OUTCOME_ESCALATED:
		tint = UIKit.BAD
	elif verdict == ReviewSystem.OUTCOME_FLAGGED:
		tint = UIKit.WARN

	v.add_child(UIKit.label(ReviewSystem.closing(verdict), 17, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.stamp(verdict.to_upper(), tint))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("WHAT DECIDED IT", 12, UIKit.INK_DIM))
	v.add_child(UIKit.label(String(o["because"]), 15, tint,
		HORIZONTAL_ALIGNMENT_LEFT, true))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("THE CONVERSATION", 12, UIKit.INK_DIM))
	var box := UIKit.vbox(4)
	for t in Array(o["transcript"]):
		var row := UIKit.vbox(1)
		row.add_child(UIKit.label("\"%s\"" % String(t["question"]), 13, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		row.add_child(UIKit.label("   %s" % String(t["effect"]), 12,
			UIKit.GOOD if bool(t["cleared"]) else UIKit.WARN,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(row)
	v.add_child(UIKit.scroll(box))
	card_footer(UIKit.button("Go home", func():
		EventBus.request_ui.emit("day_over", {"verdict": verdict})
		close()))

func ward():
	return get_tree().get_first_node_in_group("ward_day")
