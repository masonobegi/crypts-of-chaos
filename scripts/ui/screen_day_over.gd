extends ScreenBase
## The end of the day, and the only place the verdict means anything.
##
## For three iterations the review printed a stamp and nothing read it: signed
## off and referred were mechanically identical, which made the entire risk side
## of the risk/reward frontier decorative. What a verdict does now is decide what
## tomorrow's ward is like, and this screen says so in plain words before the
## player chooses whether to work it.

func _build() -> void:
	pauses_world = true
	var verdict := String(ctx.get("verdict", ReviewSystem.OUTCOME_CLEAR))
	var w = ward()
	# FROM THE DAY, NOT RECOMPUTED. `w.cash < 0` can never be true now that
	# Vinnie takes what there is and no more, so this silently overwrote
	# end_day's own finding every single night.
	var short: bool = w != null and bool(w.end_day().get("short", false))

	# THE CAREER ENDS HERE OR IT DOES NOT END AT ALL. A probe that played seven
	# days found a player being referred on six consecutive nights and simply
	# carrying on, because there was nothing to carry on TO.
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("_refresh_money"):
		hud.call("_refresh_money")
	var ending := GameState.ending()
	if ending != "":
		_ending_card(ending)
		return

	# THE VERDICT MAKES A SOUND. This card — the stamp, what Vinnie wanted, what
	# he got, what tomorrow is like — arrived in total silence, and so did both
	# ending cards, which are the last thing anybody sees. A rubber stamp is the
	# one object in this game that has an obvious noise.
	AudioMgr.play("stamp", -6.0,
		0.82 if verdict == ReviewSystem.OUTCOME_ESCALATED else 1.0)
	var v := card_shell(720, 620, "END OF SHIFT",
		"Day %d  ·  Ward C" % GameState.day)

	var tint := UIKit.GOOD
	if verdict == ReviewSystem.OUTCOME_ESCALATED:
		tint = UIKit.BAD
	elif verdict == ReviewSystem.OUTCOME_FLAGGED:
		tint = UIKit.WARN
	v.add_child(UIKit.stamp(verdict.to_upper(), tint))

	# The money, flatly.
	var m := UIKit.panel(UIKit.NOTE, 4, 1, UIKit.BAD if short else UIKit.MONEY)
	var mv := UIKit.vbox(2)
	var res: Dictionary = w.end_day() if w != null else {}
	mv.add_child(UIKit.row("He wanted",
		UIKit.money_str(int(res.get("wanted", Cases.DEBT_DUE))), UIKit.INK_DIM))
	mv.add_child(UIKit.row("He got",
		UIKit.money_str(int(res.get("paid", 0))),
		UIKit.MONEY if not short else UIKit.BAD, 18))
	# The line that stops this reading as theft.
	var interest := int(res.get("interest", 0))
	if interest > 0:
		mv.add_child(UIKit.row("Interest, 10%% a night on the balance",
			"+" + UIKit.money_str(interest), UIKit.BAD))
	mv.add_child(UIKit.rule())
	mv.add_child(UIKit.row("Still owed",
		UIKit.money_str(GameState.debt_remaining()), UIKit.BAD, 18))
	m.add_child(mv)
	v.add_child(m)

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("TOMORROW", 12, UIKit.INK_DIM))
	var standing := String(DoctorRecord.load_from_state().standing())
	if standing != "":
		v.add_child(UIKit.label("· " + standing, 14, UIKit.BAD,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	for line in _consequences(verdict, short):
		v.add_child(UIKit.label("· " + String(line), 14, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))

	var foot := UIKit.vbox(6)
	foot.add_child(UIKit.button("Work tomorrow", func():
		_carry(verdict, short)
		close()
		EventBus.request_ui.emit("morning", {})))
	foot.add_child(UIKit.button("Main menu", func():
		_leave("res://scenes/MainMenu.tscn")))
	card_footer(foot)

## What last night actually costs you, said out loud rather than stored in a
## flag nobody reads.
func _consequences(verdict: String, short: bool) -> Array:
	var out: Array = []
	match verdict:
		ReviewSystem.OUTCOME_CLEAR:
			out.append("Nothing was queried. Adeyemi is on again and so are you.")
		ReviewSystem.OUTCOME_QUESTIONS:
			out.append("Sister Nkemelu has made a note. She will read your charts first tomorrow.")
		# THE SAME TWO CONSEQUENCES, because the auditor is gated on FLAGGED
		# now and not on REFERRED — she was expensive content behind a trigger
		# the money-optimal play never once reached. The screen has to say what
		# the game does; the reverse of that mismatch is what the last audit
		# caught, and this is the same error the other way up.
		ReviewSystem.OUTCOME_FLAGGED:
			out.append("Coding are looking at last night. Adeyemi has started writing her rounds up twice.")
			out.append("Ms Ferrand from Coding is on the ward for the next two shifts. She is not there to help.")
			out.append("Your office has somebody in it. Anything you write, you write in front of her.")
		ReviewSystem.OUTCOME_ESCALATED:
			out.append("This is going upstairs. Adeyemi is writing her rounds up twice and Coding are here for two shifts.")
			out.append("Your office has somebody in it. Anything you write, you write in front of her.")
	# The beds she could not stand up, by name. This is the part that carries
	# regardless of the stamp: a "noted" day still puts somebody on a list.
	var remembered := PackedStringArray(ctx.get("remembered", PackedStringArray()))
	for pid in remembered:
		out.append("%s's file has a note on it now. It will be read closely."
			% Cases.name_of(String(pid)))
	# THE ONE THAT IS NOT ABOUT PAPERWORK. Somebody is coming back, and it is
	# nothing to do with what the reviewer thought of your notes.
	for pid in PackedStringArray(GameState.flag(Cases.READMIT_FLAG, [])):
		out.append("%s is back on the ward in the morning — they did not make it through the night at home."
			% Cases.name_of(String(pid)))
	if short:
		out.append("Vinnie was short. He says he will call in — it is on his way.")
	return out

## The one place a verdict becomes state. Read by WardDay when the next day
## starts, so a bad night is a harder ward rather than a paragraph.
func _carry(verdict: String, short: bool) -> void:
	GameState.set_flag("watched", verdict == ReviewSystem.OUTCOME_FLAGGED
		or verdict == ReviewSystem.OUTCOME_ESCALATED)
	# GATED ON FLAGGED, NOT REFERRED, AND IT LASTS. Coding is the state the
	# money-optimal play never once reached, so the auditor — a whole person,
	# and the answer to the promise this screen prints — was expensive content
	# behind a trigger that never fired. And recomputing it from last night
	# meant one clean shift made her vanish; she is booked for two.
	var bad: bool = verdict == ReviewSystem.OUTCOME_FLAGGED \
		or verdict == ReviewSystem.OUTCOME_ESCALATED
	var shifts_left: int = maxi(int(GameState.flag("auditor_shifts", 0)) - 1, 0)
	if bad:
		shifts_left = 2
	GameState.set_flag("auditor_shifts", shifts_left)
	GameState.set_flag("auditor_present", shifts_left > 0)
	GameState.set_flag("vinnie_visits", short)
	# The beds she could not corroborate, by name. They open tomorrow with a
	# note on the file, which is the only reason "noted" costs anything.
	# The per-bed carry and the nightly shortfall are both gone — the wards
	# alternate, so a note on a patient's file was a note on somebody who would
	# not be back before it was overwritten; and a short night now compounds the
	# total rather than inflating tomorrow. What carries is the doctor's record,
	# which `ReviewSystem.commit` writes at the handover.
	GameState.day += 1
	var w = ward()
	if w != null:
		w.start()
	# THE HUD STILL SAID DAY ONE ON THE SECOND WARD. `day` is a plain field;
	# the only thing that tells anybody it changed is `start_day`, and nothing
	# on this path called it — so the corner of the screen was a day behind for
	# the whole of every day after the first, and the clock never restarted.
	GameState.start_day()
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps != null and ps.has_method("reset_day"):
		ps.reset_day()
	# THE ONLY POINT A SAVE IS HONEST. A day is one sitting; what survives it is
	# the day number, the money, and what the ward sister remembers — all of
	# which are in GameState by the time this runs.
	SaveSystem.save_game(SaveSystem.AUTOSAVE)

## THE TWO WAYS OUT.
##
## Neither existed until this session: `game_over` was a signal connected to a
## handler and emitted by nobody, and the debt was a constant the loan shark
## asked for every night forever. A game whose worst outcome is "denser nurse
## rounds, indefinitely" has nothing at the top of its own risk curve.
func _ending_card(ending: String) -> void:
	var won: bool = ending == GameState.ENDING_PAID
	# Paying it off is the only good news in the game and it deserves the one
	# rising tone in the bank. Being struck off gets the low one.
	AudioMgr.play("money" if won else "error", -4.0, 1.0 if won else 0.7)
	var v := card_shell(760, 640, "THE END OF IT",
		"Day %d  ·  Ward C" % GameState.day)
	v.add_child(UIKit.stamp("PAID" if won else "STRUCK OFF",
		UIKit.GOOD if won else UIKit.BAD))
	var rec := DoctorRecord.load_from_state()

	if won:
		v.add_child(UIKit.label(
			"Vinnie counts it twice, the way he always does, and then he shakes your "
			+ "hand. He says you were never any trouble. On the way back up you pass "
			+ "the board and somebody has already rubbed your name off it.",
			15, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		v.add_child(UIKit.label(
			"It is not a hearing. It is a letter, and a woman from Coding who does "
			+ "not look up, and a form asking you to confirm the address they should "
			+ "send things to. Vinnie will find you either way; that was never the "
			+ "part that depended on this.",
			15, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("%d SHIFTS" % rec.nights, 12, UIKit.INK_DIM))
	var stats := UIKit.vbox(2)
	stats.add_child(UIKit.row("Signed off", str(rec.clean_nights), UIKit.GOOD))
	stats.add_child(UIKit.row("Queried or flagged", str(rec.flagged_nights), UIKit.WARN))
	stats.add_child(UIKit.row("Referred", str(rec.referrals), UIKit.BAD))
	stats.add_child(UIKit.row("Against your name",
		"%d of %d" % [rec.strikes, DoctorRecord.STRIKES_TO_STRIKE_OFF], UIKit.BAD))
	stats.add_child(UIKit.row("Still owed",
		UIKit.money_str(GameState.debt_remaining()),
		UIKit.MONEY if won else UIKit.BAD))
	v.add_child(stats)

	# WHAT SHE WROTE DOWN ABOUT YOU. The only score the game keeps, and it is
	# a description rather than a number.
	var tally: Array = rec.summary_lines()
	if not tally.is_empty():
		v.add_child(UIKit.rule())
		v.add_child(UIKit.label("ON YOUR RECORD", 12, UIKit.INK_DIM))
		for line in tally:
			v.add_child(UIKit.label("· " + String(line), 13, UIKit.INK,
				HORIZONTAL_ALIGNMENT_LEFT, true))
	elif won:
		v.add_child(UIKit.rule())
		v.add_child(UIKit.label(
			"Nothing on your record at all. She never once had to ask you twice.",
			14, UIKit.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))

	var foot := UIKit.vbox(6)
	foot.add_child(UIKit.button("Start again", func():
		GameState.start_new_career()
		_leave("res://scenes/Game.tscn")))
	foot.add_child(UIKit.button("Main menu", func():
		_leave("res://scenes/MainMenu.tscn")))
	card_footer(foot)

func ward():
	return get_tree().get_first_node_in_group("ward_day")

## LEAVING A SCREEN THAT STOPPED THE WORLD.
##
## This card pauses the tree, and all three of its exits called
## `change_scene_to_file` directly — so the main menu loaded with
## `SceneTree.paused` still true and every button on it was inert. The player
## finished a career, chose "Main menu", and arrived at a title screen that did
## not respond to anything. `UIRoot`'s own pause menu had always got this right;
## the ending cards never did.
##
## The mouse goes back too. It is captured for the first-person view and a menu
## you cannot point at is the same dead end by a different route.
func _leave(scene_path: String) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(scene_path)
