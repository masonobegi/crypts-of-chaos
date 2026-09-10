extends ScreenBase
## THE WARD'S RECORDS, FROM A TERMINAL.
##
## This screen did not exist. Both public EHR terminals — the one standing in
## the middle of the bay facing all five beds, and the one on the nurses'
## counter — are modelled, lit, labelled EHR in glowing green and offer the
## prompt "Read the ward's notes · in full view of the ward". Pressing E played
## the affirmative beep and opened nothing, because `request_ui.emit("records")`
## reached a router with no "records" in it, logged a warning nobody sees and
## returned. Two of the three terminals in the building were furniture.
##
## Worse than a dead object: it made the game's central mechanic unreachable.
## `_written_in_front_of_them` is the finding that makes this a first-person
## game — a note claiming somebody is unwell, typed where they can watch you
## type it, is a note the reviewer can check by walking four metres — and going
## somewhere private to write it is the crime the game is about. But the ONLY
## route to the chart was the "Read the chart" row on a patient's card, and that
## card only opens within a few metres of the patient. You could never write
## anywhere except standing over them. The private office, the whole reason the
## office exists, could not be used.
##
## So: the terminal lists the ward and opens any record from where you are
## standing, and says out loud who can see you doing it. That sentence is the
## only place the game teaches the mechanic before grading you on it.

func _build() -> void:
	# The world keeps running while you read at a terminal, exactly as it does
	# at a bedside. Standing here IS the exposure.
	pauses_world = false
	# ...AND THE HEADING SAYS WHICH OF THE TWO THINGS THIS SCREEN IS. From the
	# nurses' station it is the ward's notes; from your own office at the end of
	# the shift it is where the day ends, and calling it WARD RECORDS there sent
	# the player looking for a different screen.
	var v := card_shell(720, 660,
		"SIGN OFF" if _in_office() else "WARD RECORDS", _where())
	var watchers := _who_can_see()
	var seen_by_someone: bool = not watchers.is_empty()
	var note := UIKit.panel(UIKit.NOTE, 4, 1,
		UIKit.WARN if seen_by_someone else UIKit.GOOD)
	var nv := UIKit.vbox(2)
	if seen_by_someone:
		nv.add_child(UIKit.label("Anything you write here, you write in front of %s."
			% _list(watchers), 14, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		nv.add_child(UIKit.label("There is nobody in the room. Nobody sees what you type.",
			14, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	note.add_child(nv)
	v.add_child(note)

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("OPEN A RECORD", 12, UIKit.INK_DIM))
	var w = ward()
	for c in Cases.roster():
		var pid := String(c["id"])
		var decided := ""
		if w != null and w.state.has(pid):
			match String(w.state[pid]["disposition"]):
				"hold": decided = "  ·  staying"
				"discharge": decided = "  ·  going home"
		var row := UIKit.button("%s  —  bed %d%s" % [String(c["name"]),
			int(c["bed"]), decided],
			func():
				close()
				EventBus.request_ui.emit("chart", {"patient_id": pid}))
		v.add_child(row)
		v.add_child(UIKit.label("    " + String(c["condition"]), 12, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true))

	var foot := UIKit.vbox(6)
	# THE ONLY PLACE THE SHIFT ENDS, AND IT SAYS WHAT IT IS ABOUT TO DO.
	# Only from the private machine, because "sign off in your office before
	# eight" is the objective the whole day is pointed at.
	if _in_office() and w != null and not w.ended:
		var undecided := 0
		for c in Cases.roster():
			if String(w.state[String(c["id"])]["disposition"]) == "":
				undecided += 1
		if undecided > 0:
			foot.add_child(UIKit.label(
				"%d bed%s still undecided. Signing off sends %s home."
					% [undecided, "" if undecided == 1 else "s",
						"them" if undecided > 1 else "them"],
				13, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
		foot.add_child(UIKit.button("Sign off for the night", func():
			w.sign_off()
			EventBus.request_ui.emit("review", {}),
			Color(0.30, 0.16, 0.16)))
	foot.add_child(UIKit.button("Close", func(): close()))
	card_footer(foot)

func _in_office() -> bool:
	var p = player()
	var h = get_tree().get_first_node_in_group("hospital")
	if p == null or h == null or not h.has_method("room_at"):
		return false
	return String(h.room_at(p.global_position)) == "office"

## Which machine this is, in words the player can act on.
func _where() -> String:
	var p = player()
	var h = get_tree().get_first_node_in_group("hospital")
	if p == null or h == null or not h.has_method("room_at"):
		return "the ward terminal"
	match String(h.room_at(p.global_position)):
		"station": return "the nurses' station  ·  the ward can see the screen"
		"office": return "your office  ·  the door is shut"
	return "the ward terminal  ·  in full view of the beds"

## Everyone who would end up on `seen_by` if you wrote something right now.
##
## THE SAME FUNCTION the audit reads, not a copy of it. This used to be its own
## loop over the same rooms and perception cones, with a comment saying it had
## to stay in step with `WardDay._who_can_see_me` — which is gotcha 48's shape on
## the one pair in this game where a divergence is a LIE TO THE PLAYER. The
## screen that promises "you write in front of Nurse Adeyemi and 2 others" and
## the record that promise is about now cannot disagree, because there is one
## answer and both of them ask for it.
func _who_can_see() -> Array:
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus == null or not sus.has_method("who_can_see_the_player"):
		return []
	return sus.who_can_see_the_player()

static func _list(names: Array) -> String:
	if names.size() == 1:
		return String(names[0])
	if names.size() == 2:
		return "%s and %s" % [String(names[0]), String(names[1])]
	return "%s and %d others" % [String(names[0]), names.size() - 1]

func ward():
	return get_tree().get_first_node_in_group("ward_day")
