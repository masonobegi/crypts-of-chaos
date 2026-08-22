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
		_rv.begin(w.review_findings(), w.records.entries, w.review_truth())
	pauses_world = true

	var v := card_shell(780, 700, "HANDOVER",
		"Sister Nkemelu has last night's folder")

	if _done or _rv.finished():
		_closing(v, w)
		return

	var f = _rv.current()
	# WHOSE FOLDER SHE HAS OPEN. Without the name, every question in the room
	# was about an unnamed patient and an unnamed line, and the most important
	# screen in the game read as an abstraction — the player could answer five
	# questions without once knowing which bed was being discussed.
	var who := String(Cases.by_id(f.patient_id).get("name", ""))
	v.add_child(UIKit.label("She turns to %s's folder."
		% (who if who != "" else "the ward's notes"), 12, UIKit.INK_DIM))
	v.add_child(UIKit.label("\"%s\"" % f.question, 18, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.label("— looking at %s" % f.axis, 12, UIKit.INK_DIM))

	# AND THE LINES SHE IS ACTUALLY HOLDING, exactly as they read on the chart.
	# The player is being asked to defend specific writing; they should be able
	# to see the writing. This is also the only way the review teaches — you
	# learn what a reviewer notices by being shown the two lines side by side.
	var cited := UIKit.vbox(3)
	var shown := 0
	for eid in f.entries:
		var e = w.records.by_id(String(eid))
		if e == null:
			continue
		shown += 1
		var slip := UIKit.panel(UIKit.NOTE, 3)
		var sv := UIKit.vbox(0)
		sv.add_child(UIKit.label(e.as_line(), 14, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		sv.add_child(UIKit.label(e.metadata_line(), 11,
			UIKit.BAD if e.is_backdated() else UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		slip.add_child(sv)
		cited.add_child(slip)
	if shown > 0:
		v.add_child(UIKit.spacer(2))
		v.add_child(cited)
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
				# She turns a page whatever you say. Whether it worked is the
				# difference between a page and a page and a pen.
				AudioMgr.play("page", -13.0)
				if not bool(r.get("cleared", false)):
					AudioMgr.play("beep_low", -16.0)
				_last = String(r.get("effect", ""))
				if _rv.finished():
					_done = true
				rebuild(),
			UIKit.PANEL_LIGHT))
	# NOT wrapped in another scroll: card_shell already scrolls `body`, and a
	# ScrollContainer inside a ScrollContainer has a minimum height of zero.
	v.add_child(opts)

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
	AudioMgr.play("stamp", -6.0,
		0.7 if verdict != ReviewSystem.OUTCOME_CLEAR else 1.0)
	v.add_child(UIKit.stamp(verdict.to_upper(), tint))

	# The money, and what it did or did not cover. Vinnie came at eight; this is
	# what he found. Being short is not a game over — it is tomorrow being worse.
	v.add_child(UIKit.rule())
	var short: bool = w.cash < 0
	var m := UIKit.panel(UIKit.NOTE, 4, 1, UIKit.BAD if short else UIKit.MONEY)
	var mv := UIKit.vbox(2)
	mv.add_child(UIKit.row("Owed", UIKit.money_str(w.debt_tonight), UIKit.INK_DIM))
	mv.add_child(UIKit.row("Left over" if not short else "Still owed",
		UIKit.money_str(absi(w.cash)), UIKit.MONEY if not short else UIKit.BAD, 17))
	if short:
		mv.add_child(UIKit.label(
			"He took what there was and said he would come to the ward tomorrow, "
			+ "since it is on his way. He has never once said where he works.",
			13, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	m.add_child(mv)
	v.add_child(m)
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
	# NOT wrapped in another scroll: card_shell already scrolls `body`, and a
	# ScrollContainer inside a ScrollContainer has a minimum height of zero.
	v.add_child(box)
	card_footer(UIKit.button("Go home", func():
		EventBus.request_ui.emit("day_over", {"verdict": verdict,
			"remembered": o.get("remembered", PackedStringArray())})
		close()))

func ward():
	return get_tree().get_first_node_in_group("ward_day")
