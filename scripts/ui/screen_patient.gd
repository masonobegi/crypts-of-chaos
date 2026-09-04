extends ScreenBase
## What you can do about one person. Five verbs, none of them labelled dishonest.
##
## There is no "make it worse". Every action on this card is something a doctor
## does on a normal Tuesday. What makes one of them a crime is who it is done to,
## what time it is done, and what the chart already says.

var _pid := ""
var _said := ""

func _build() -> void:
	# THE PERSON STAYS ALIVE WHILE YOU READ ABOUT THEM.
	#
	# `pauses_world` defaults to true and this screen stopped overriding it, so
	# opening a card froze the entire tree. Both cards are deliberately drawn as
	# an undimmed side panel — `card_shell` exists so the patient stays in shot —
	# and the whole point is that the clock keeps costing you while you read.
	# The `_init()` that set this was lost in a rewrite; the terminal screen four
	# metres away had it right.
	pauses_world = false
	_pid = String(ctx.get("patient_id", ""))
	var c := Cases.by_id(_pid)
	var w = ward()
	if c.is_empty() or w == null:
		close()
		return
	var st: Dictionary = w.state[_pid]
	var disposition := String(st["disposition"])

	# Who is paying belongs in the header beside the bed number rather than as a
	# third row in the money panel: it is an attribute of the person, it never
	# changes during the day, and it was costing the fifth verb its place on
	# the screen.
	# WIDER, because six verbs is a lot of card. At 660 in a 1600-wide window
	# every subtitle wrapped onto a second line and the last two verbs sat
	# below the fold; the window has the room and the card was not using it.
	# THE CLOCK GOES ON THE CARD. Every verb below now states what it costs, and
	# a price is unusable without the balance: the skill in this game is fitting
	# an action into the gap between Adeyemi's rounds and getting a test back
	# before you have to decide. The time was on the HUD behind the card, which
	# is the one place the player is not looking while choosing a verb.
	var v := card_shell(820, 830, String(c["name"]).to_upper(),
		"%s  ·  bed %d  ·  %s  ·  %s" % [String(c["condition"]), int(c["bed"]),
			Cases.tier_name(int(c["tier"])), ChartEntry._hhmm(w.minute)])

	v.add_child(UIKit.label("\"%s\"" % (_said if _said != "" else String(c["opening"])),
		16, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	# The money, stated flatly and without comment. It is not advice and it is
	# not labelled — two numbers, and the player can do what they like with them.
	var m := UIKit.panel(UIKit.NOTE, 4, 1, UIKit.MONEY)
	var mv := UIKit.vbox(2)
	if disposition == "":
		mv.add_child(UIKit.row("Send them home",
			"+%s once" % UIKit.money_str(Cases.DISCHARGE_FEE), UIKit.INK_DIM))
	mv.add_child(UIKit.row(
		"Every further night" if disposition != "discharge" else "You sent them home",
		"+%s to you" % UIKit.money_str(Cases.night_fee(int(c["tier"]))
			if disposition != "discharge" else Cases.DISCHARGE_FEE), UIKit.MONEY))
	m.add_child(mv)
	v.add_child(m)

	v.add_child(UIKit.rule())
	var acts := UIKit.vbox(4)

	# TWO KINDS OF VERB, and the card should say so. Three of these tell you
	# something and go in no notes; four of them put something on the record in
	# somebody's name. Which group a verb is in is the whole decision, and six
	# undifferentiated rows did not say it.
	acts.add_child(UIKit.label("FINDING OUT", 11, UIKit.INK_DIM))

	acts.add_child(_act("Read the chart",
		"%d min  ·  everything written today, and when it was written." % WardDay.READ_COST,
		func(): _go("chart")))

	acts.add_child(_act("Ask how they have been",
		"free  ·  whatever they say goes no further unless you write it down.",
		func():
			_said = w.what_they_say(_pid)
			rebuild()))

	# EXAMINE THEM. The only verb that tells you the truth, and the only one
	# that cannot be done from a terminal — so it is gated on actually standing
	# there. Peter Lomax on the second ward is the whole argument for it: every
	# document about him says improving, and he is not.
	if w.has_examined(_pid):
		acts.add_child(_note("You examined them.", String(w.examination_of(_pid))))
	else:
		acts.add_child(_act("Examine them",
			"%d min  ·  curtains round. It goes in no notes — but you will know." % WardDay.EXAMINE_COST,
			func():
				_said = w.examine(_pid)
				rebuild()))

	acts.add_child(UIKit.spacer(4))
	acts.add_child(UIKit.label("PUTTING IT ON THE RECORD", 11, UIKit.INK_DIM))

	# ASK THE REGISTRAR. He is in the second group: he writes, in his own name.
	if WardDay.colleague_available(w.minute):
		acts.add_child(_act("Ask %s for a second opinion" % WardDay.COLLEAGUE,
			"%d min  ·  a peer, in his own name. He reads the whole chart first." % WardDay.COLLEAGUE_COST,
			func():
				var e = w.ask_colleague(_pid)
				_said = ("\"Agreed. I wouldn't send him anywhere today.\""
					if e != null and e.supports_stay()
					else "\"There's nothing here. I'd have had him out this morning.\"")
				rebuild()))
	else:
		var nxt: int = WardDay.colleague_next(w.minute)
		acts.add_child(_note("%s is on the other ward." % WardDay.COLLEAGUE,
			("Back at %s." % ChartEntry._hhmm(nxt)) if nxt > 0
				else "Gone for the day. You are the doctor on this ward."))


	# The leading question. Phrased as a clinical enquiry, because that is what
	# it looks like from the outside — and from the inside, on a good day.
	acts.add_child(_act("Ask whether they have felt faint at all",
		"%d min  ·  some people agree with anything. Not all of them remember agreeing." % WardDay.ASK_COST,
		func():
			var e = w.ask_patient(_pid, "feeling faint this evening")
			_said = ("\"...Now you mention it. Maybe. A bit.\"" if e != null
				else "\"No. Nothing like that.\"")
			rebuild()))

	acts.add_child(_act("Ask Adeyemi to review them",
		"%d min  ·  she writes what she finds, in her own name. That is the point." % WardDay.NURSE_COST,
		func():
			w.nurse_check(_pid)
			_said = "\"I'll look in on him now, doctor.\""
			rebuild()))

	acts.add_child(_act("Order bloods and a lying/standing BP",
		"%d min to order, %d to come back  ·  a result is a result." % [
			WardDay.ORDER_COST, WardDay.TEST_TURNAROUND],
		func():
			var o = w.order_test(_pid, "lying and standing BP")
			_said = "\"Someone will be along for that.\""
			rebuild()))

	# NOT wrapped in another scroll: card_shell already scrolls `body`, and a
	# ScrollContainer inside a ScrollContainer has a minimum height of zero.
	v.add_child(acts)
	# PINNED, not scrolled. These are the two decisions the whole day is made of
	# and they were sitting below the fold underneath five optional actions —
	# the way out of a screen must never be the thing you scroll to find, and
	# neither must the point of it.
	var foot := UIKit.vbox(6)
	var d := UIKit.hbox(8)
	d.add_child(UIKit.button(
		"Keeping them in" if disposition == "hold" else "Keep them in overnight",
		func(): w.set_disposition(_pid, "hold"); _said = String(c["on_hold"]); rebuild(),
		UIKit.WARN.darkened(0.45) if disposition == "hold" else UIKit.PANEL_LIGHT))
	d.add_child(UIKit.button(
		"Going home" if disposition == "discharge" else "Send them home",
		func(): w.set_disposition(_pid, "discharge"); _said = String(c["on_discharge"]); rebuild(),
		UIKit.GOOD.darkened(0.45) if disposition == "discharge" else UIKit.PANEL_LIGHT))
	foot.add_child(d)
	foot.add_child(UIKit.button("Leave them be", close))
	card_footer(foot)

## A VERB YOU CANNOT USE IS NOT A BUTTON. Six full-height panels — a title, a
## subtitle and a border each — put a third of this card below the fold, and the
## third that went was the half you came here for. Anything that is unavailable
## or already done collapses to one dim line, which is all it has to say.
func _note(title: String, sub: String) -> Control:
	var col := UIKit.vbox(0)
	col.add_child(UIKit.label(title, 14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	if sub != "":
		col.add_child(UIKit.label("   " + sub, 12, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	return col

## ...AND THE BORDER IS NOT DRAWN TWICE.
##
## Each verb was a PanelContainer wrapping a VBox wrapping a Button — and
## `UIKit.button` already carries its own bordered slip, so every row had two
## frames round it and the outer one's padding on top. Six of those is most of
## the reason a third of this card was still below the fold after the last go
## at it: the fix then was to collapse the verbs you CANNOT use, which does
## nothing at eight in the morning when all six are live.
##
## One frame, and the cost sits on the button's own line rather than under it —
## "12 min" is what you are deciding about, so it belongs where the decision is.
func _act(title: String, sub: String, cb: Callable) -> Control:
	var col := UIKit.vbox(0)
	var b := UIKit.button(title, cb, UIKit.PANEL_LIGHT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(b)
	var l := UIKit.label("    " + sub, 12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	col.add_child(l)
	return col

func _go(what: String) -> void:
	EventBus.request_ui.emit(what, {"patient_id": _pid})

func ward():
	return get_tree().get_first_node_in_group("ward_day")
