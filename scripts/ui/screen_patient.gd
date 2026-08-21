extends ScreenBase
## Seeing a patient: one card, four choices, and what each one does.
##
## The playtest note was "it plays super clunky, there are almost too many
## dialogue options and I don't know the outcome of what happens when I see
## them — a three-year-old should be able to understand". Both halves of that
## were true. Walking up to somebody opened a conversation screen carrying an
## evidence box, a stay counter, a procedure button, an examine button, a
## theatre button, a discharge button, a list of no-equipment treatments, eleven
## things to say, and a bribery panel. Nine of those are things you do rarely
## and one is the thing you came to do.
##
## So: this. Who they are, what is wrong with them in plain words, and FOUR
## buttons, each with one line underneath saying what happens if you press it.
## Everything rare lives behind "Talk to them", which is where it always
## belonged — talking is a thing you choose to do, not the lobby you arrive in.
##
## The rule for the outcome lines: say what HAPPENS, never a number and never a
## judgement. "They go home and the bed stops earning" is a fact. "Risky" is an
## opinion, and this game does not have opinions about what you do.

var _patient = null
var _mind: Mind = null

func _init() -> void:
	# They stay in the room with you.
	pauses_world = false

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return
	var sus = suspicion()
	_mind = sus.mind_of(_patient.id) if sus != null else null

	# Tall on purpose: card_shell caps it against the window, and four choices
	# with a sentence each plus the complaint box is more than 690px of card.
	# Anything that has to be scrolled to is a choice the player did not make.
	var v := card_shell(580, 820, _patient.display_name, _subtitle())
	if _patient.admitted and _patient.ready_for_discharge():
		v.add_child(UIKit.stamp("fit to go home", UIKit.GOOD))
	elif not _patient.acquired_injuries().is_empty():
		v.add_child(UIKit.stamp("injured on the ward", UIKit.BAD))
	v.add_child(_the_complaint())
	v.add_child(UIKit.spacer(4))

	# The one thing their ailment actually calls for, first and biggest.
	var kind := Procedures.procedure_for(_patient.condition_id)
	var screen := Procedures.screen_for(kind)
	if screen != "":
		v.add_child(_choice(Procedures.procedure_name(kind), _procedure_line(kind),
			UIKit.ACCENT, func(): _go(screen)))
	else:
		v.add_child(_choice("It needs a machine", 
			"Their chart names the machine. It is in the treatment bay, or beside the bed.",
			UIKit.INK_DIM, Callable()))

	v.add_child(_choice("Examine them", _examine_line(), UIKit.INK,
		func(): _go("exam")))

	if _patient.admitted:
		v.add_child(_choice("Discharge them", _discharge_line(),
			UIKit.GOOD if _patient.ready_for_discharge() else UIKit.WARN,
			func(): _go("prescribe")))
	else:
		var ps = patient_system()
		var free: int = ps.free_wards().size() if ps != null else 0
		v.add_child(_choice("Admit them", 
			"They take a room and start paying for it. %s" % (
				"%d of five free." % free if free > 0 else "Every room is full."),
			UIKit.GOOD if free > 0 else UIKit.INK_DIM,
			(func(): _admit()) if free > 0 else Callable()))
		v.add_child(_choice("Send them home",
			"They leave now. Nothing is billed and nothing happens to them.",
			UIKit.INK, func(): _send_home()))

	v.add_child(_choice("Talk to them", _talk_line(), UIKit.INK,
		func(): _go("dialogue")))
	card_footer(UIKit.button("Leave them be", close))

# ------------------------------------------------------------------ the header
func _subtitle() -> String:
	if not _patient.admitted:
		return "Waiting to be seen"
	var bits := PackedStringArray()
	bits.append(_room_name())
	bits.append("day %d of %d" % [int(ceil(_patient.days_admitted)),
		maxi(1, int(ceil(_patient.expected_stay_days)))])
	bits.append("%s a night" % UIKit.money_str(_patient.daily_revenue()))
	return "  ·  ".join(bits)

## What is wrong with them, as a person would say it. The name of the condition
## is a label; the tell is the thing you can see from the doorway.
## "Room 103", not "ward_103". The floor plan knows what each room is called.
func _room_name() -> String:
	var h = get_tree().get_first_node_in_group("hospital")
	if h != null:
		var r = h.room(_patient.room)
		if r != null:
			return String(r.display)
	return _patient.room.capitalize().replace("_", " ")

func _the_complaint() -> Control:
	var spec: Dictionary = DB.condition(_patient.condition_id)
	var box := UIKit.panel(UIKit.NOTE, 6, 1, UIKit.ACCENT)
	var bv := UIKit.vbox(3)
	bv.add_child(UIKit.label(_patient.condition_name(), 19, UIKit.INK))
	bv.add_child(UIKit.label(String(spec.get("tell", "")), 14, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	# How they are, in words. A percentage would be a lie — you have not
	# measured anything yet.
	bv.add_child(UIKit.label(_how_they_are(), 15, _how_they_are_colour()))
	var hurt: Array = _patient.acquired_injuries()
	if not hurt.is_empty():
		var names := PackedStringArray()
		for c in hurt:
			names.append(c.display_name)
		bv.add_child(UIKit.label("Also, since they arrived: %s." % ", ".join(names),
			13, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(bv)
	return box

func _how_they_are() -> String:
	if not _patient.read_is_fresh() and _patient.admitted:
		return "You have not looked at them today."
	if _patient.ready_for_discharge():
		return "Fit to go home."
	if _patient.recovery >= 0.6:
		return "Nearly there."
	if _patient.recovery >= 0.25:
		return "Coming along."
	if _patient.recovery >= 0.0:
		return "In a bad way."
	return "Worse than when they arrived."

func _how_they_are_colour() -> Color:
	if not _patient.read_is_fresh() and _patient.admitted:
		return UIKit.INK_DIM
	if _patient.ready_for_discharge():
		return UIKit.GOOD
	if _patient.recovery < 0.0:
		return UIKit.BAD
	return UIKit.INK

# ------------------------------------------------------------------ the lines
## One sentence per button, saying what happens. Never a number, never a
## judgement — the game does not have an opinion about what you do.
func _procedure_line(kind: String) -> String:
	match kind:
		"set_bone":
			return "You say what you mean to do, then hold the break in place with your hands."
		"suture":
			return "You say what you mean to do, then put six stitches down the cut."
		"prescribe":
			return "You say what you mean to do, then pick a bottle and draw up a dose."
		"manipulate":
			return "You say what you mean to do, then take the joint round the arc."
	return "Their chart says what is indicated."

func _examine_line() -> String:
	if _patient.read_is_fresh():
		return "You have already looked today. Doing it again tells you nothing new."
	return "You find out how they actually are, and their chart says what to give them."

func _discharge_line() -> String:
	if _patient.ready_for_discharge():
		return "They go home well. The bed stops earning and you keep your name."
	return "They go home early. The bed stops earning, and people who go home "  \
		+ "before they are better sometimes come back with a solicitor."

func _talk_line() -> String:
	if _mind == null:
		return "Ask how they are."
	var worst := _mind.strongest(GameState.career_minutes)
	if worst != null and not worst.neutralized:
		return "They have something to say about what they saw. You could explain it, or settle it."
	if _patient.is_overdue():
		return "They want to know when they are going home."
	return "Ask how they are. It is worth more than it sounds."

# ------------------------------------------------------------------ chrome
## Every choice looks the same: a title, a sentence about what happens, and a
## button. Four of these, and nothing else on the screen.
func _choice(title: String, outcome: String, tint: Color, cb: Callable) -> Control:
	var live: bool = cb.is_valid()
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 3, 2 if live else 0, tint)
	var bv := UIKit.vbox(4)
	if live:
		# The button IS the title. Naming the choice twice — once as a heading
		# and again on the button under it — is how a four-choice card became a
		# nine-line card.
		var b := UIKit.button(title, cb, UIKit.PANEL_LIGHT)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_color_override("font_color", tint)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bv.add_child(b)
	else:
		bv.add_child(UIKit.label(title, 19, UIKit.INK_DIM))
	bv.add_child(UIKit.label(outcome, 14, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	p.add_child(bv)
	return p

func _go(screen: String) -> void:
	var pid: String = _patient.id
	close()
	EventBus.request_ui.emit(screen, {"patient_id": pid, "npc_id": pid})

func _admit() -> void:
	var ps = patient_system()
	if ps == null:
		close()
		return
	if not ps.admit(_patient):
		EventBus.toast.emit("There is nowhere to put them.", "bad")
		return
	AudioMgr.play("trolley", -12.0)
	close()

func _send_home() -> void:
	var ps = patient_system()
	if ps != null:
		ps.send_home(_patient, "cleared")
	AudioMgr.play("door", -14.0)
	close()
