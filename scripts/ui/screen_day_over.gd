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
	var short: bool = w != null and w.cash < 0

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
	mv.add_child(UIKit.row("Owed tonight",
		UIKit.money_str(w.debt_tonight if w else Cases.DEBT_DUE), UIKit.INK_DIM))
	mv.add_child(UIKit.row("Left over" if not short else "Still owed",
		UIKit.money_str(absi(w.cash) if w else 0),
		UIKit.MONEY if not short else UIKit.BAD, 18))
	m.add_child(mv)
	v.add_child(m)

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("TOMORROW", 12, UIKit.INK_DIM))
	for line in _consequences(verdict, short):
		v.add_child(UIKit.label("· " + String(line), 14, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))

	var foot := UIKit.vbox(6)
	foot.add_child(UIKit.button("Work tomorrow", func():
		_carry(verdict, short)
		close()
		EventBus.request_ui.emit("morning", {})))
	foot.add_child(UIKit.button("Main menu", func():
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
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
		ReviewSystem.OUTCOME_FLAGGED:
			out.append("Coding are looking at last night. Adeyemi has started writing her rounds up twice.")
			out.append("Every note you make tomorrow is read by somebody who is already curious.")
		ReviewSystem.OUTCOME_ESCALATED:
			out.append("There is an auditor on the ward tomorrow. She is not there to help.")
			out.append("You will be asked to put things in writing while somebody watches you do it.")
	# The beds she could not stand up, by name. This is the part that carries
	# regardless of the stamp: a "noted" day still puts somebody on a list.
	var remembered := PackedStringArray(ctx.get("remembered", PackedStringArray()))
	for pid in remembered:
		out.append("%s's file has a note on it now. It will be read closely."
			% Cases.name_of(String(pid)))
	# THE ONE THAT IS NOT ABOUT PAPERWORK. Somebody is coming back, and it is
	# nothing to do with what the reviewer thought of your notes.
	for pid in PackedStringArray(GameState.flag(Cases.READMIT_FLAG, [])):
		out.append("%s is back on the ward in the morning. They did not make it through the night at home."
			% Cases.name_of(String(pid)))
	if short:
		out.append("Vinnie was short. He says he will call in — it is on his way.")
	return out

## The one place a verdict becomes state. Read by WardDay when the next day
## starts, so a bad night is a harder ward rather than a paragraph.
func _carry(verdict: String, short: bool) -> void:
	GameState.set_flag("watched", verdict == ReviewSystem.OUTCOME_FLAGGED
		or verdict == ReviewSystem.OUTCOME_ESCALATED)
	GameState.set_flag("auditor_present", verdict == ReviewSystem.OUTCOME_ESCALATED)
	GameState.set_flag("vinnie_visits", short)
	# The beds she could not corroborate, by name. They open tomorrow with a
	# note on the file, which is the only reason "noted" costs anything.
	# The per-bed carry is gone: the wards alternate, so a note on a patient's
	# file was a note on somebody who would not be on the ward again before it
	# was overwritten. What carries is the doctor's record, and `WardDay` writes
	# that at the handover rather than here.
	GameState.set_flag("remembered_beds", PackedStringArray())
	GameState.set_flag("carried_debt", absi(ward().cash) if short and ward() else 0)
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

func ward():
	return get_tree().get_first_node_in_group("ward_day")
