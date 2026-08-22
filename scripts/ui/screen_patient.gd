extends ScreenBase
## What you can do about one person. Five verbs, none of them labelled dishonest.
##
## There is no "make it worse". Every action on this card is something a doctor
## does on a normal Tuesday. What makes one of them a crime is who it is done to,
## what time it is done, and what the chart already says.

var _pid := ""
var _said := ""

func _build() -> void:
	_pid = String(ctx.get("patient_id", ""))
	var c := Cases.by_id(_pid)
	var w = ward()
	if c.is_empty() or w == null:
		close()
		return
	var st: Dictionary = w.state[_pid]
	var disposition := String(st["disposition"])

	var v := card_shell(660, 700, String(c["name"]).to_upper(),
		"%s  ·  bed %d" % [String(c["condition"]), int(c["bed"])])

	v.add_child(UIKit.label("\"%s\"" % (_said if _said != "" else String(c["opening"])),
		16, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	# The money, stated flatly and without comment. It is not advice and it is
	# not labelled — two numbers, and the player can do what they like with them.
	var m := UIKit.panel(UIKit.NOTE, 4, 1, UIKit.MONEY)
	var mv := UIKit.vbox(2)
	mv.add_child(UIKit.row("Send them home", "+%s once" % UIKit.money_str(Cases.DISCHARGE_FEE), UIKit.INK_DIM))
	mv.add_child(UIKit.row("Every further night", "+%s to you"
		% UIKit.money_str(Cases.night_fee(int(c["tier"]))), UIKit.MONEY))
	mv.add_child(UIKit.row("Paying", Cases.tier_name(int(c["tier"])), UIKit.INK_DIM, 13))
	m.add_child(mv)
	v.add_child(m)

	v.add_child(UIKit.rule())
	var acts := UIKit.vbox(6)

	acts.add_child(_act("Read the chart",
		"Everything written about them today, and when it was written.",
		func(): _go("chart")))

	acts.add_child(_act("Ask how they have been",
		"An open question. Whatever they say goes no further unless you write it down.",
		func():
			_said = String(c["opening"])
			rebuild()))

	# The leading question. Phrased as a clinical enquiry, because that is what
	# it looks like from the outside — and from the inside, on a good day.
	acts.add_child(_act("Ask whether they have felt faint at all",
		"Some people will agree with anything. Not all of them remember agreeing.",
		func():
			var e = w.ask_patient(_pid, "feeling faint this evening")
			_said = ("\"...Now you mention it. Maybe. A bit.\"" if e != null
				else "\"No. Nothing like that.\"")
			rebuild()))

	acts.add_child(_act("Ask Adeyemi to review them",
		"She writes what she finds, in her own name. That is the point of asking.",
		func():
			w.nurse_check(_pid)
			_said = "\"I'll look in on him now, doctor.\""
			rebuild()))

	acts.add_child(_act("Order bloods and a lying/standing BP",
		"A result is a result. It will say what it says.",
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

func _act(title: String, sub: String, cb: Callable) -> Control:
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 3)
	var col := UIKit.vbox(1)
	var b := UIKit.button(title, cb, UIKit.PANEL_LIGHT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(b)
	col.add_child(UIKit.label("    " + sub, 12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	p.add_child(col)
	return p

func _go(what: String) -> void:
	EventBus.request_ui.emit(what, {"patient_id": _pid})

func ward():
	return get_tree().get_first_node_in_group("ward_day")
