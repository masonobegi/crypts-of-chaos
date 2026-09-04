extends ScreenBase
## Ten past eight. She has the folder.
##
## Every question names the two documents that produced it, and the closing
## summary names the one that decided it. Nobody should ever leave this screen
## wondering what happened to them.

var _rv: ReviewSystem = null
var _last := ""
var _done := false
var _committed := false

func _build() -> void:
	# She opens the folder. The handover is the climax of a shift and it began
	# in silence.
	if not _committed:
		AudioMgr.play("paper", -10.0, 0.9)
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

	# WHAT SHE ALREADY KNOWS ABOUT YOU, before she opens it. Blank for the first
	# few days, which is the point — she has no reason to open with anything
	# until there is a shape to open with.
	var opener := String(_rv.record.opening_line()) if _rv.record != null else ""
	if opener != "":
		# NOT near-black on dark brown. INK is (0.12,0.13,0.15) and that
		# background was (0.30,0.22,0.16): a contrast ratio of about 1.5:1, on
		# the single most dramatic line in the game and the one place the player
		# learns the ward sister has been keeping score. It was effectively
		# invisible. The card's own warning paper is 12.9:1.
		var pre := UIKit.panel(UIKit.NOTE_WARN, 4, 1, UIKit.WARN)
		pre.add_child(UIKit.label("\"%s\"" % opener, 15, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(pre)

	if _done or _rv.finished():
		_closing(v, w)
		return

	var f = _rv.current()
	# WHOSE FOLDER SHE HAS OPEN. Without the name, every question in the room
	# was about an unnamed patient and an unnamed line, and the most important
	# screen in the game read as an abstraction — the player could answer five
	# questions without once knowing which bed was being discussed.
	var who := Cases.name_of(f.patient_id) if f.patient_id != "" else ""
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
	# `w.cash` is `in_hand - min(in_hand, debt_remaining)` and can never be
	# negative, so this was false on every night that has ever been played: a
	# night $300 short printed "Left over $0" in the GREEN money border and the
	# authored paragraph for coming up short could not render. The end-of-shift
	# card documents this exact bug being fixed there and not here.
	var short: bool = bool(w.end_day().get("short", false))
	# WHAT HE WANTED AGAINST WHAT HE GOT, not "left over".
	#
	# `w.cash` is `in_hand - min(in_hand, debt_remaining)` — Vinnie takes
	# everything up to what he is owed against a $15,500 debt — so it is exactly
	# zero on every night of every career except the last. The panel read
	# "Owed $2,200 / Left over $0" whether the night made $600 or $5,000, on the
	# screen where the money is supposed to land.
	var res: Dictionary = w.end_day()
	var m := UIKit.panel(UIKit.NOTE, 4, 1, UIKit.BAD if short else UIKit.MONEY)
	var mv := UIKit.vbox(2)
	mv.add_child(UIKit.row("He wanted", UIKit.money_str(w.debt_tonight), UIKit.INK_DIM))
	mv.add_child(UIKit.row("He got", UIKit.money_str(int(res.get("paid", 0))),
		UIKit.MONEY if not short else UIKit.BAD, 17))
	mv.add_child(UIKit.row("Still owed",
		UIKit.money_str(int(res.get("still_owed", GameState.debt_remaining()))),
		UIKit.BAD))
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

	# HER RUNNING TALLY, in plain words. She is not hiding it and the player
	# should be able to see the ladder they are climbing before the rung breaks.
	if _rv.record != null:
		var tally: Array = _rv.record.summary_lines()
		if not tally.is_empty():
			v.add_child(UIKit.rule())
			v.add_child(UIKit.label("ON YOUR RECORD, SO FAR", 12, UIKit.INK_DIM))
			for line in tally:
				v.add_child(UIKit.label("· " + String(line), 13, UIKit.WARN,
					HORIZONTAL_ALIGNMENT_LEFT, true))
			# HOW NEAR THE EDGE, in words. A threshold the player cannot see
			# coming is a threshold that feels arbitrary when it lands.
			var standing := String(_rv.record.standing())
			if standing != "":
				v.add_child(UIKit.label("· " + standing, 13, UIKit.BAD,
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
	# The night goes on the record when she closes the folder, once.
	if not _committed:
		_committed = true
		_rv.commit(w.review_findings())
	# NO close() AFTER THE REQUEST. `UIRoot.open()` closes whatever is currently
	# up before it builds the next screen, and `request_ui` is a plain signal, so
	# it runs to completion inline: by the time this lambda continues, `current`
	# is already the End of Shift card — and `close()` then freed it.
	#
	# The only button that ends the first shift threw the whole shift away. The
	# card flashed and vanished, the player was dumped back into a ward with a
	# dead clock, and "Work tomorrow" — the one caller of `_carry()`, which is
	# what increments the day, pays Vinnie's balance forward and saves — could
	# never be pressed. No career could reach day two.
	card_footer(UIKit.button("Go home", func():
		EventBus.request_ui.emit("day_over", {"verdict": verdict,
			"remembered": o.get("remembered", PackedStringArray())})))

func ward():
	return get_tree().get_first_node_in_group("ward_day")
