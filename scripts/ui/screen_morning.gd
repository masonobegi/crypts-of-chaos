extends ScreenBase
## The first thing a stranger sees, and the only place the premise is stated.
##
## Thirty seconds is all this gets. It says who is on the ward, what is owed,
## when it is owed, and what you have — and then it stops. It does not explain
## what to do about the gap. The gap IS the game, and a player who works it out
## for themselves in the first ten minutes has had the good version of it.

func _build() -> void:
	var w = get_tree().get_first_node_in_group("ward_day")
	# Taller: the money panel gained a line when the debt got a total, and the
	# last of the three numbers was sitting under the fold.
	var v := card_shell(720, 700, "WARD C",
		"%s  ·  five beds  ·  you are the only doctor on" % GameState.time_string())

	v.add_child(UIKit.label(
		"Adeyemi has been on since six. She has written her morning round already.",
		14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	var box := UIKit.vbox(4)
	for c in Cases.roster():
		var row := UIKit.panel(UIKit.NOTE, 3)
		var col := UIKit.vbox(1)
		col.add_child(UIKit.row("%d.  %s" % [int(c["bed"]), String(c["name"])],
			Cases.tier_name(int(c["tier"])), UIKit.INK, 15))
		col.add_child(UIKit.label("      " + String(c["condition"]), 12, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(col)
		box.add_child(row)
	v.add_child(box)

	v.add_child(UIKit.rule())

	# The two numbers, flat, with no advice attached and no arrow between them.
	var m := UIKit.panel(UIKit.NOTE, 4, 1, UIKit.BAD)
	var mv := UIKit.vbox(3)
	mv.add_child(UIKit.label("THIS EVENING", 11, UIKit.INK_DIM))
	# THE NUMBERS THE DAY ACTUALLY STARTS WITH, not the constants it usually
	# starts with. After a short night both of these are wrong by whatever
	# Vinnie did not get, and this card is the only place the player is told
	# what they owe before they start making decisions about it.
	mv.add_child(UIKit.row("Vinnie, in person, at eight",
		UIKit.money_str(w.debt_tonight if w != null else Cases.DEBT_DUE), UIKit.BAD, 17))
	mv.add_child(UIKit.row("Still owed, all in",
		UIKit.money_str(GameState.debt_remaining()), UIKit.BAD, 15))
	mv.add_child(UIKit.row("In your account",
		UIKit.money_str(w.cash if w != null else Cases.STARTING_CASH),
		UIKit.MONEY, 17))
	mv.add_child(UIKit.label(
		"A discharge pays %s. A night in a bed pays more, and the difference depends on who is paying for the bed."
			% UIKit.money_str(Cases.DISCHARGE_FEE),
		12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	# THE ONLY PLACE THE INTEREST IS STATED BEFORE IT IS CHARGED. The morning
	# card calls itself the place the premise is stated, and it left out the
	# compounding — which is the single mechanism that decides whether a career
	# ends in PAID or STRUCK OFF.
	mv.add_child(UIKit.label(
		"Whatever is still owed at the end of the night grows by %d%% before the next one."
			% int(round(Cases.DEBT_INTEREST * 100.0)),
		12, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	m.add_child(mv)
	v.add_child(m)

	card_footer(UIKit.button("Start the round", func():
		GameState.start_day()
		# The day owns the objective from here: it changes as beds are decided,
		# and it carries a place as well as a sentence.
		# `w` is the ward this whole card is describing, taken at the top.
		if w != null:
			w._update_objective()
		close()))
