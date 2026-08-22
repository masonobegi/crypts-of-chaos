extends ScreenBase
## The whiteboard behind the nurses' station.
##
## THE ONLY INFORMATION IN THE GAME THAT LIVES IN A PLACE. Everything else — the
## chart, a patient, the money — comes to you through a screen you can open from
## anywhere you happen to be standing. This is Adeyemi's plan for her day, in
## marker, on a wall in the station, and reading it costs the walk.
##
## It is a FORECAST, not the truth. She has been on since six and she writes down
## what she expects to happen. She is right about the rounds, because those are a
## rota. She is exactly as right about the patients as she is, and one of the two
## people on the second ward who is genuinely unwell is a man whose numbers have
## been coming down all week — so the board says he is going home.

func _build() -> void:
	pauses_world = true
	var w = ward()
	if w == null:
		close()
		return
	var v := card_shell(700, 640, "WARD C — TODAY",
		"Nurse Adeyemi's board. In marker, at the station.")

	# The rounds, stated rather than inferred. A player can work these out by
	# reading four charts and noticing the pattern; this is where the ward
	# simply tells you, because a nurse's rota is not a secret.
	v.add_child(UIKit.label("ROUNDS", 12, UIKit.INK_DIM))
	var times := PackedStringArray()
	for r in w.rounds_today():
		times.append(ChartEntry._hhmm(int(r)))
	v.add_child(UIKit.label("   ".join(times), 20, UIKit.ACCENT))
	if GameState.flag("watched", false):
		v.add_child(UIKit.label(
			"She has added two. Coding are looking at last night.", 12, UIKit.WARN,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	# When the registrar is on this ward rather than the other one.
	v.add_child(UIKit.label("%s IS ON THIS WARD" % WardDay.COLLEAGUE.to_upper(), 12, UIKit.INK_DIM))
	var slots := PackedStringArray()
	for hrs in WardDay.COLLEAGUE_HOURS:
		slots.append("%s – %s" % [ChartEntry._hhmm(int(hrs[0])), ChartEntry._hhmm(int(hrs[1]))])
	v.add_child(UIKit.label("   ".join(slots), 17,
		UIKit.GOOD if WardDay.colleague_available(w.minute) else UIKit.INK))
	v.add_child(UIKit.rule())

	v.add_child(UIKit.label("PLAN", 12, UIKit.INK_DIM))
	var box := UIKit.vbox(4)
	for c in Cases.roster():
		box.add_child(_row(w, c))
	v.add_child(box)

	v.add_child(UIKit.label(
		"She has been on since six and this is what she expects to happen. "
		+ "It is not a diagnosis and she does not pretend it is.",
		12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))

	card_footer(UIKit.button("Back", close))

## What nursing INTENDS for a bed, which is read off the chart they can see and
## not off the simulation. Deliberately derived the same way a nurse would derive
## it — from the last thing written — so the board is wrong about exactly the
## patients the chart is wrong about.
func _row(w, c: Dictionary) -> Control:
	var pid := String(c["id"])
	var last_stay = null
	var last_go = null
	for e in w.records.for_patient(pid):
		if e.author == ChartEntry.Author.YOU:
			continue          ## her plan, not yours
		if e.supports_stay():
			last_stay = e
		elif e.supports_discharge():
			last_go = e
	var plan := "for home"
	var tint := UIKit.GOOD
	if last_stay != null and (last_go == null or last_stay.stated_minute > last_go.stated_minute):
		plan = "staying"
		tint = UIKit.WARN
	if String(w.state[pid]["disposition"]) == "hold":
		plan = "you have kept them"
		tint = UIKit.ACCENT
	elif String(w.state[pid]["disposition"]) == "discharge":
		plan = "gone"
		tint = UIKit.INK_DIM
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 3)
	var row := UIKit.hbox(8)
	row.add_child(UIKit.label("%d." % int(c["bed"]), 14, UIKit.INK_DIM))
	var name_l := UIKit.label(String(c["name"]), 15, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	row.add_child(UIKit.label(plan, 14, tint, HORIZONTAL_ALIGNMENT_RIGHT))
	p.add_child(row)
	return p

func ward():
	return get_tree().get_first_node_in_group("ward_day")
