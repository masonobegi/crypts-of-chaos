extends ScreenBase
## The first thing a stranger sees, and the only place the premise is stated.
##
## Thirty seconds is all this gets. It says who is on the ward, what is owed,
## when it is owed, and what you have — and then it stops. It does not explain
## what to do about the gap. The gap IS the game, and a player who works it out
## for themselves in the first ten minutes has had the good version of it.

func _build() -> void:
	var w = get_tree().get_first_node_in_group("ward_day")
	# TALLER, AND — ALONE AMONG THE CARDS — WIDER, AND THE WIDTH IS THE ONE THAT
	# MATTERED.
	#
	# Height first: the money panel gained a line when the debt got a total, so
	# this asks for the cap (`viewport - 136`, 764 at the pinned 1600x900)
	# rather than a number, exactly as the End of Shift card does.
	#
	# Then LAST NIGHT put up to five sentences above the ward list, and at 720
	# every one of them wrapped to two rows: measured in the real window
	# (gotcha 28, because under `--headless` the root Window is 64 pixels tall
	# and every layout reading off it is fiction) that is 31% of the card below
	# the fold on a five-bed morning, with the whole money panel — the premise,
	# and the only place the interest is stated before it is charged — under the
	# line. Two cheaper fixes were tried and measured first and both were worth
	# almost nothing: dropping the lines to 12pt and dim, and trimming the eight
	# longest of them, together moved 32% to 31%, because the constraint is
	# ROWS and a 130-character sentence is two rows at either size.
	#
	# 860 puts four of the five on ONE row and takes it to 24%. The other cards
	# stay at 720 and 780 and should: this is the only one that is a LIST, and a
	# ward list is a wider document than a verdict.
	var v := card_shell(860, 780, "WARD C",
		"%s  ·  five beds  ·  you are the only doctor on" % GameState.time_string())

	v.add_child(UIKit.label(
		"Adeyemi has been on since six. She has written her morning round already.",
		14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	# THE SHAPE OF A DAY, BEFORE ANY OF IT IS SPENT. Every verb costs minutes off
	# one clock and the whole design rests on the day not being long enough — and
	# the player was never told there was a budget until they were already inside
	# it, watching a number in the corner move for reasons nobody had named.
	# States the budget and its unit and not what to spend it on, which is what
	# this card is careful about everywhere else. Built from the constants,
	# because a second copy of a tuned number is how this project loses
	# afternoons.
	v.add_child(UIKit.label(
		"You are on until %s. Reading one chart is %d minutes of it."
			% [ChartEntry._hhmm(Cases.DEBT_DUE_MINUTE), WardDay.READ_COST],
		14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))

	# WHAT LAST NIGHT WAS, FOR THE BEDS YOU KEPT.
	#
	# Only a MISTAKE ever came back from a previous shift: somebody you sent
	# home who was not fit to go is in a bed this morning with an audit flag on
	# them and a line on the tannoy, and somebody you kept out of decency was
	# never mentioned by anybody again. The whole investigation layer exists to
	# find the one person who genuinely needs the bed, and the reward for
	# finding them was that the ward sister did not ask a question about it.
	#
	# Written the night before by `screen_day_over._carry`, because the day has
	# not turned over until "Work tomorrow" is pressed and an id resolved after
	# that is resolved against a different ward (gotcha 30). What is stored here
	# is finished sentences.
	#
	# Every held bed, not only the ones that needed holding — prose for the
	# right decisions and silence for the rest is a score in fancy dress, and
	# nothing in this game grades the player's choice for them.
	#
	# Dim and a point down on the ward list: this is what happened, and the beds
	# below it are what you have to decide. See the width note at the top for
	# what that costs and what it does not.
	var last_night: Array = GameState.flag(Cases.OVERNIGHT_FLAG, [])
	if not last_night.is_empty():
		v.add_child(UIKit.rule())
		v.add_child(UIKit.label("LAST NIGHT", 11, UIKit.INK_DIM))
		for line in last_night:
			v.add_child(UIKit.label("· " + String(line), 12, UIKit.INK_DIM,
				HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	var box := UIKit.vbox(4)
	for c in Cases.roster():
		var row := UIKit.panel(UIKit.NOTE, 3)
		var col := UIKit.vbox(1)
		# THE RATE, ON THE ROW. Who is paying is on this card and what they pay
		# is not, so "PREMIUM" and "STATE" were two words with no numbers behind
		# them until the player had opened five patient cards one at a time.
		col.add_child(UIKit.row("%d.  %s" % [int(c["bed"]), String(c["name"])],
			"%s  ·  %s a night" % [Cases.tier_name(int(c["tier"])),
				UIKit.money_str(Cases.night_fee(int(c["tier"])))], UIKit.INK, 15))
		col.add_child(UIKit.label("      " + String(c["condition"]), 12, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(col)
		box.add_child(row)
	v.add_child(box)

	v.add_child(UIKit.rule())

	# AND WHAT NIGHT THIS IS, in the one voice the game had never used.
	#
	# Nothing anywhere in `scripts/` was keyed on how long the career had run —
	# grepping `GameState.day` finds the HUD label, a save log line and the ward
	# rotation, and that is all of it. So night seven opened exactly like night
	# one: the same card, five beds, and a different number in a red box that
	# nobody in the fiction ever remarked on. One authored line, banded off the
	# balance, in two registers depending on whether Vinnie went short last
	# night — which is the only part of the compounding a player FEELS, because
	# it is the morning the figure is bigger after they handed over real money.
	#
	# `vinnie_visits` is the existing flag for that and it is written by
	# `_carry` from last night's `short`, so this is a pure read and adds no
	# state. It goes above the money rather than inside it: the panel is what
	# the ward owes, and this is what it is doing to somebody.
	v.add_child(UIKit.label(
		Cases.debt_thread(GameState.debt_remaining(),
			bool(GameState.flag("vinnie_visits", false))),
		13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))

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
	# AND IT WAS FALSE FOR A STATE BED. "A night pays more" is true at $850 and
	# $450 and not at $180, because the bed you empty takes the next admission
	# as well — $650 against $180. The player was told the opposite of the
	# arithmetic on a third of the beds in the game, on the card whose whole job
	# is to state the premise. Every figure here is read from the constants, so
	# it cannot drift the way that sentence did.
	mv.add_child(UIKit.label(
		("A discharge pays %s, and the empty bed takes the next admission at %s. "
			+ "A night pays %s, %s or %s, depending on who is paying for it.")
			% [UIKit.money_str(Cases.DISCHARGE_FEE),
				UIKit.money_str(Cases.ADMISSION_FEE),
				UIKit.money_str(Cases.NIGHT_FEE[Cases.Tier.PREMIUM]),
				UIKit.money_str(Cases.NIGHT_FEE[Cases.Tier.STANDARD]),
				UIKit.money_str(Cases.NIGHT_FEE[Cases.Tier.STATE])],
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
