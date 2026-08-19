extends RefCounted
## Implementation of the headless playthrough. Loaded at RUNTIME by
## tests/smoke_run.gd — autoloads (GameState, RNG, ...) are not resolvable at
## compile time from a --script main loop, so none of this can live there.

var tree: SceneTree = null
var game: Node = null
var frames := 0
var stage := "firstrun"
var errors: Array[String] = []
var notes: Array[String] = []
var sim_minutes := 0
func start() -> void:
	print("\n=== SMOKE RUN ===\n")
	GameState.start_new_career(20260819)
	var packed: PackedScene = load("res://scenes/Game.tscn")
	if packed == null:
		_fail("Game.tscn failed to load")
		return
	game = packed.instantiate()
	tree.root.add_child(game)
	print("booted")

func tick() -> bool:
	frames += 1
	# The briefing screen pauses the tree on open; drive things directly.
	tree.paused = false
	match stage:
		"firstrun":
			if frames > 6:
				_check_first_run()
				stage = "boot"
		"boot":
			if frames > 6:
				_check_boot()
				stage = "shift"
				if not GameState.clock_running:
					game.shift.clock_in()
		"shift":
			_run_shift_minute()
			if sim_minutes >= GameState.SHIFT_HOURS * 60:
				stage = "review"
		"review":
			_check_midshift()
			game.shift.end_shift()
			stage = "close"
		"close":
			var report: Dictionary = game.shift.clock_out()
			_check_report(report)
			stage = "nextday"
		"nextday":
			game.shift.next_day()
			# next_day() offers the three shifts and waits; pick one explicitly
			# so the smoke run also proves a shift that crosses midnight works.
			game.shift.begin_day("night")
			_check_next_day()
			stage = "done"
		"done":
			_report()
			return true
	if frames > 4000:
		# Hard stop so a stuck state can never hang CI.
		_fail("smoke run did not finish (stuck in stage '%s')" % stage)
		_report()
		return true
	return false

# ------------------------------------------------------------------ driving
func _run_shift_minute() -> void:
	# Advance the game clock manually rather than waiting on real time.
	for i in 8:
		GameState._advance_minute()
		sim_minutes += 1
		if GameState.shift_over():
			return

# ------------------------------------------------------------------ checks
func _fail(msg: String) -> void:
	errors.append(msg)

func _ok(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
	else:
		notes.append("  ok: " + msg)

## THE PATH A REAL PLAYER TAKES, which nothing had ever walked.
##
## Every other harness sets `tutorial_done` before booting, so all of them
## skipped straight past the only route a stranger can actually take. Pressing
## New Career opened the briefing, then opened the tutorial on top of it — and
## `open()` closes whatever is already up, so the briefing was destroyed before
## a frame was drawn. The tutorial's button said "Clock in" and did not clock
## anybody in; the sole caller of clock_in() in the entire game was the button
## on the briefing that had just been thrown away. The result was a hospital
## frozen in PRE_SHIFT with a clock stuck at 8:00 AM and no input anywhere that
## could start the day. The game was unplayable from the main menu and 1526
## assertions were green.
func _check_first_run() -> void:
	_ok(not GameState.flag("tutorial_done", false), "a fresh career has not seen the tutorial")
	_ok(game.ui != null and game.ui.current != null, "something is on screen at boot")
	_ok(game.ui != null and game.ui.current_id == "tutorial",
		"and it is the tutorial (got '%s')" % (game.ui.current_id if game.ui else "<no ui>"))

	_ok(_press_button("brief"), "the tutorial has a button that moves you on")
	_ok(game.ui.current_id == "briefing",
		"which opens the morning brief (got '%s')" % game.ui.current_id)

	_ok(_press_button("Clock in"), "the brief has a Clock in button")
	_ok(GameState.phase == GameState.Phase.SHIFT,
		"pressing it actually starts the shift (phase %d)" % int(GameState.phase))
	_ok(GameState.clock_running, "and the clock is running")
	_ok(game.ui.current == null, "with nothing left in the way")

## Find a button by a fragment of its label and press it, the way a player does.
func _press_button(fragment: String) -> bool:
	if game.ui == null or game.ui.current == null:
		return false
	var b := _find_button(game.ui.current, fragment)
	if b == null:
		return false
	b.emit_signal("pressed")
	return true

func _find_button(n: Node, fragment: String) -> Button:
	if n is Button and String((n as Button).text).to_lower().contains(fragment.to_lower()):
		return n
	for c in n.get_children():
		var f := _find_button(c, fragment)
		if f != null:
			return f
	return null

func _check_boot() -> void:
	_ok(game.hospital != null and game.hospital.rooms.size() == 15, "hospital built with 15 rooms")
	# The three annexe departments are built but shuttered on day one.
	_ok(game.hospital != null and game.hospital.open_room_keys().size() == 12,
		"twelve of them are open at career start")
	_ok(game.player != null, "player spawned")
	_ok(game.player.global_position.y > -5.0, "player is not under the floor")
	_ok(tree.get_nodes_in_group("staff").size() >= 3, "staff spawned")
	_ok(game.patient_system != null, "patient system exists")
	_ok(game.patient_system.active_count() > 0, "patients admitted at briefing (%d)"
		% game.patient_system.active_count())
	_ok(tree.get_nodes_in_group("patient_npc").size() > 0, "patient bodies spawned")
	# Five ward beds and three Intake trolleys, which are beds in every sense
	# that matters — they are in the group, they take an occupant, and they roll.
	var ward_beds := 0
	var trolleys := 0
	for b in tree.get_nodes_in_group("bed"):
		if b.room_key == "intake":
			trolleys += 1
		else:
			ward_beds += 1
	_ok(ward_beds == 5, "five ward beds exist (%d)" % ward_beds)
	_ok(trolleys == 3, "three Intake trolleys exist (%d)" % trolleys)
	_ok(tree.get_nodes_in_group("fixture").size() > 10, "fixtures placed")
	_ok(game.suspicion != null and game.suspicion.minds.size() >= 4, "minds registered")
	# Every patient must have a body, a chart and a bed.
	for p in game.patient_system.active():
		_ok(game.patient_system.get_body(p.id) != null, "%s has a body" % p.display_name)
		_ok(game.patient_system.charts.has(p.id), "%s has a chart" % p.display_name)

func _check_midshift() -> void:
	var ps = game.patient_system
	_ok(GameState.shift_over(), "shift clock reached the end of the day")
	var recovered := false
	for p in ps.active():
		if p.recovery > 0.05:
			recovered = true
	_ok(recovered, "patients recovered over the shift")
	_ok(GameState.career_minutes > 400, "career clock advanced")

	# Exercise the sabotage path end to end: dial a machine off-prescription,
	# run it, and confirm the truth layer, the log and the evidence all move.
	var machine: TreatmentMachine = null
	for f in tree.get_nodes_in_group("fixture"):
		if f is TreatmentMachine and f.room_key.begins_with("ward"):
			machine = f
			break
	if machine == null:
		_fail("no ward machine found")
		return
	var victim: Patient = null
	for p in ps.active():
		if p.room == machine.room_key:
			victim = p
	if victim == null:
		victim = ps.active()[0] if not ps.active().is_empty() else null
	if victim == null:
		_fail("no patient to test treatment on")
		return

	machine.set_prescribed_for(victim)
	var before_recovery: float = victim.recovery
	var before_comps: int = victim.complications.size()
	machine.dial = clampi(machine.prescribed + 6, 0, 11)
	if absi(machine.dial - machine.prescribed) < 5:
		machine.dial = clampi(machine.prescribed - 6, 0, 11)
	game.treatment.run_machine(machine, victim)
	_ok(victim.recovery < before_recovery, "extreme machine setting harmed recovery")
	_ok(victim.complications.size() > before_comps, "and produced a complication")
	_ok(machine.suspicious_log_entries().size() > 0, "and left an entry in the device log")

	# Documenting it cleanly should cost nothing; leaving it should be findable.
	var comp: Complication = victim.complications.back()
	var findings_before: int = game.records.pending_findings().size()
	_ok(findings_before > 0, "an undocumented complication is a findable record gap")
	var cause: String = String(comp.plausible_causes[0]) if comp.plausible_causes.size() > 0 else "idiopathic"
	var res: Dictionary = game.records.document_complication(comp_owner(victim), comp, cause,
		true, Vector3.ZERO, victim.room)
	_ok(bool(res.get("plausible", false)), "a plausible cause was accepted")
	_ok(game.records.pending_findings().size() < findings_before,
		"documenting it removed the finding")

	# Phantom billing must show up in the audit.
	var money_before: int = GameState.hospital_money
	game.records.log_phantom_treatment(victim, "rest", true, Vector3.ZERO, victim.room)
	_ok(GameState.hospital_money > money_before, "phantom billing pays")
	var kinds: Array = []
	for f in game.records.pending_findings():
		kinds.append(String(f["kind"]))
	_ok(kinds.has("phantom_billing"), "and is visible to an auditor")

	# The economy has to actually bill occupied beds.
	_ok(ps.total_daily_revenue() > 0, "ward generates revenue")

	_check_supply_shelf()
	_check_examination(ps)
	_check_intake_overflow(ps)

## You have to be able to pick up a syringe.
##
## Every shelf in the building was a dead end: tap was unreachable because
## use_seconds() returned a hold time, and the hold path cycled instead of
## dispensing. No treatment tool could be obtained by any input, so no patient
## could be treated by hand, and the tutorial pointed straight at it.
func _check_supply_shelf() -> void:
	var shelf: SupplyShelf = null
	for f in tree.get_nodes_in_group("fixture"):
		if f is SupplyShelf and f.items.size() > 1:
			shelf = f
			break
	if shelf == null:
		_fail("no stocked supply shelf in the building")
		return
	_ok(shelf.use_seconds(null, null) == 0.0,
		"a shelf is a tap, not a hold — a hold can never reach the tap branch")
	var before := tree.get_nodes_in_group("prop").size()
	shelf.interact(game.player, null)
	var after := tree.get_nodes_in_group("prop").size()
	_ok(after > before, "tapping a shelf actually puts an object in the world (%d -> %d)" % [before, after])

## The examination, end to end: the honest setting is safe and useful, and
## leaning on somebody produces a real injury that lands in the record as a gap.
func _check_examination(ps) -> void:
	var p = null
	for q in ps.active():
		if q.acquired_injuries().is_empty():
			p = q
			break
	if p == null:
		_fail("no patient to examine")
		return
	var before: int = p.complications.size()
	game.treatment.examine(p, "wrist", TreatmentSystem.EXAM_INDICATED, Vector3.ZERO)
	_ok(p.complications.size() == before, "an examination at the indicated pressure harms nobody")
	_ok(p.examined_at > -99999, "and does tell you something")

	# Top of the dial, repeatedly, so this does not hang on one roll.
	var got := ""
	for i in 12:
		var res: Dictionary = game.treatment.examine(p, "ankle",
			TreatmentSystem.EXAM_DIAL_MAX, Vector3.ZERO)
		if String(res.get("injury", "")) != "":
			got = String(res["injury"])
			break
	_ok(got == "fractured_ankle", "leaning on an ankle breaks the ankle (%s)" % got)
	var acquired: Array = p.acquired_injuries()
	_ok(acquired.size() == 1, "and it is recorded as having happened here")
	_ok(acquired[0].true_cause == "examination", "with the truth attached to it")
	_ok(acquired[0].staff_present == DB.staff_on(GameState.shift_kind),
		"and a note of how many people could possibly have done it")
	var kinds: Array = []
	for f in p.chart.audit(p.actual_treatments, p.complications):
		kinds.append(String(f["kind"]))
	_ok(kinds.has("unexplained_injury"), "an unexplained injury is findable in the chart")

## With Emergency open and every ward full, an admission lands on a trolley in
## Intake instead of disappearing into an invisible waiting list — and a ward
## coming free takes them off it again.
func _check_intake_overflow(ps) -> void:
	if not GameState.owned_upgrades.has("dept_emergency"):
		GameState.owned_upgrades.append("dept_emergency")
	game.hospital.refresh_departments()
	_ok(game.hospital.is_room_open("intake"), "Intake opened when it was bought")

	var guard := 0
	while not ps.free_wards().is_empty() and guard < 10:
		guard += 1
		ps.admit(ps.generate())
	_ok(ps.free_wards().is_empty(), "every ward is full")

	var trolleys_before: int = ps.free_trolleys()
	var overflow = ps.generate()
	_ok(ps.admit(overflow), "a full ward still admits somebody")
	_ok(overflow.room == "intake", "and they are on a trolley, not on a list")
	_ok(ps.free_trolleys() == trolleys_before - 1,
		"the trolley is occupied (%d free)" % ps.free_trolleys())

	# Free a ward and the longest-waiting trolley patient should end up in it.
	var victim = null
	for p in ps.active():
		if p.room != "intake":
			victim = p
			break
	if victim == null:
		_fail("no ward patient to discharge")
		return
	var freed: String = victim.room
	ps.discharge(victim, "recovered")
	ps._relieve_intake(freed)
	_ok(overflow.room == freed, "a ward coming free gets them off the trolley")
	_ok(ps.free_trolleys() == trolleys_before, "and the trolley is free again")

	_check_wheeling(ps)

## Beds are on wheels, so which room a patient is in is a question about where
## their bed ended up. Doing it on purpose is the ramping strategy; the game has
## to actually notice.
func _check_wheeling(ps) -> void:
	var p = null
	for q in ps.active():
		if q.room != "intake" and ps.get_body(q.id) != null and ps.get_body(q.id).bed != null:
			p = q
			break
	if p == null:
		_fail("no ward patient with a bed to wheel")
		return
	var home: String = p.room
	var body = ps.get_body(p.id)
	var bed = body.bed
	var seen: Array[String] = []
	var probe := func(evt): seen.append(String(evt.kind))
	EventBus.world_event.connect(probe)
	var had_room: bool = not ps.free_wards().is_empty()
	bed.global_position = Vector3(-8.0, 0.4, 7.0)
	body.global_position = bed.global_position + Vector3(0, 0.5, 0)
	GameState.active_covers.erase("bed_shortage")
	ps._reconcile_room(p, body)
	EventBus.world_event.disconnect(probe)
	_ok(p.room == "intake", "wheeling a bed into Intake moves the patient with it")
	# Ramping is an observable act with the player as its actor, so it goes
	# through perception like anything else you do.
	_ok(seen.has("patient_moved_to_corridor"), "and everybody in the room can see it happen")
	# Defensible only when there was genuinely nowhere else to put them.
	_ok(GameState.has_cover("bed_shortage") != had_room,
		"a bed shortage excuses it and a free ward does not (free ward: %s)" % str(had_room))
	_ok(not ps.free_wards().has(home),
		"the ward they left is empty, but an empty room is not a free bed")

	# Push a spare trolley into the vacated ward and it counts again. Ramping a
	# patient out to free their room is a two-part physical job, which is the
	# right amount of effort for what it buys.
	var spare = null
	for b in tree.get_nodes_in_group("bed"):
		if b != bed and (b.occupant == null or not is_instance_valid(b.occupant)):
			spare = b
			break
	if spare == null:
		_fail("no spare trolley to swap in")
		return
	spare.global_position = ps.hospital.bed_position(home) + Vector3(0, 0.4, 0)
	_ok(ps.free_wards().has(home), "wheeling a trolley in makes it a bed again")

func comp_owner(p: Patient) -> Patient:
	return p

func _check_report(report: Dictionary) -> void:
	var st: Dictionary = report.get("statement", {})
	_ok(int(st.get("revenue", 0)) > 0, "shift billed revenue (%s)" % str(st.get("revenue", 0)))
	_ok(st.has("take_home"), "statement has a take-home figure")
	_ok(String(report.get("headline", "")) != "", "a headline was generated")
	_ok(SaveSystem.has_save(SaveSystem.AUTOSAVE), "the shift autosaved")

func _check_next_day() -> void:
	_ok(GameState.day == 2, "day advanced to 2 (got %d)" % GameState.day)
	_ok(GameState.phase == GameState.Phase.PRE_SHIFT, "next day begins in pre-shift")
	_ok(GameState.shift_kind == "night", "the chosen shift is the one that starts")
	_ok(GameState.minute_of_day == 0, "and the clock is set to its start hour (00:00)")
	_ok(not GameState.shift_over(), "a shift that begins at midnight is not instantly over")
	# The rota has to actually empty the building.
	var on := 0
	for n in tree.get_nodes_in_group("staff"):
		if n.on_duty:
			on += 1
	_ok(on == DB.staff_on("night"), "only the night roster is in the building (%d)" % on)

	# Device logs are evidence; losing them on load would quietly delete a paper
	# trail the player deliberately created.
	var machine: TreatmentMachine = null
	var thermo: Thermostat = null
	for f in tree.get_nodes_in_group("fixture"):
		if machine == null and f is TreatmentMachine:
			machine = f
		elif thermo == null and f is Thermostat:
			thermo = f
	if thermo != null:
		thermo.setting = 21
		while thermo.setting > 12:
			thermo.interact(null, null)
	var machine_log_before: int = machine.log_entries.size() if machine else 0
	var thermo_log_before: int = thermo.log_entries.size() if thermo else 0
	var thermo_setting_before: int = thermo.setting if thermo else 0

	# Everything the shift loop added has to survive a save, and most of it is
	# the kind of state that fails silently: a lost `admitted` flag turns every
	# walk-in into an inpatient on load, and a lost theatre record deletes the
	# one document in the game the player cannot write.
	var ps = game.patient_system
	var subject = null
	for q in ps.active():
		subject = q
		break
	var walkin = ps.book_walkin()
	if subject != null:
		subject.presenting_complaint = "Round-Trip Complaint"
		subject.chart.presenting_complaint = subject.presenting_complaint
		subject.examined_at = GameState.career_minutes
		subject.read_bias = 0.171
		subject.corridor_minutes = 321.0
		subject.chart.log_surgery("knee", PackedStringArray(["expedited"]),
			GameState.day, "torn_knee", 2, "wrist")
		subject.chart.prescription = "placebex_takehome"
		subject.chart.prescription_indicated = false
		ps.add_complication(subject, "fractured_wrist", "examination")

	# Save/load must survive a full round trip with live patients.
	var before_count: int = game.patient_system.active_count()
	var before_money: int = GameState.personal_money
	var walkin_id: String = walkin.id
	var subject_id: String = subject.id if subject != null else ""
	SaveSystem.save_game("smoke")
	GameState.personal_money = -99999
	var loaded: bool = SaveSystem.load_game("smoke")
	_ok(loaded, "save round-tripped")
	_ok(GameState.personal_money == before_money, "money restored")
	_ok(game.patient_system.active_count() == before_count, "patients restored (%d)" % before_count)
	_ok(machine == null or machine.log_entries.size() == machine_log_before,
		"machine log survives the round trip (%d entries)" % machine_log_before)
	_ok(thermo == null or thermo.log_entries.size() == thermo_log_before,
		"thermostat log survives the round trip (%d entries)" % thermo_log_before)
	_ok(thermo == null or thermo.setting == thermo_setting_before,
		"thermostat setting is restored (%d)" % thermo_setting_before)

	var back = ps.get_patient(walkin_id)
	_ok(back != null and not back.admitted,
		"a walk-in is still a walk-in after a save, not an inpatient")
	_ok(ps.walkins().size() >= 1, "and is still sitting in the treatment bay")
	var sub = ps.get_patient(subject_id)
	if sub == null:
		_fail("the round-trip subject did not survive at all")
	else:
		_ok(sub.presenting_complaint == "Round-Trip Complaint",
			"what they arrived with survives")
		_ok(sub.chart.presenting_complaint == "Round-Trip Complaint",
			"and the chart's copy of it does too")
		_ok(absf(sub.read_bias - 0.171) < 0.001, "your read on them is the same read")
		_ok(sub.examined_at > -99999, "having examined them is remembered")
		_ok(absf(sub.corridor_minutes - 321.0) < 0.5, "trolley time is not forgiven by a save")
		_ok(sub.chart.surgery_log.size() == 1, "the theatre record survives")
		_ok(sub.chart.surgery_log.size() == 1
			and String(sub.chart.surgery_log[0]["indicated"]) == "wrist",
			"including which site was actually indicated")
		_ok(sub.chart.prescription == "placebex_takehome", "the pharmacy record survives")
		_ok(not sub.chart.prescription_indicated, "and remembers it was not indicated")
		var inj: Array = sub.acquired_injuries()
		_ok(inj.size() == 1, "the injury survives (%d)" % inj.size())
		_ok(inj.size() == 1 and inj[0].true_cause == "examination",
			"with the truth still attached")
		_ok(inj.size() == 1 and inj[0].acquired_here,
			"and still marked as having happened here")
		_ok(inj.size() == 1 and inj[0].staff_present == DB.staff_on(GameState.shift_kind),
			"and still knows how many people could have done it")
	SaveSystem.delete_save("smoke")

func _report() -> void:
	for n in notes:
		print(n)
	print("\n--------------------------------------")
	if errors.is_empty():
		print("SMOKE RUN PASSED — %d checks" % notes.size())
	else:
		print("SMOKE RUN FAILED — %d problem(s):" % errors.size())
		for e in errors:
			printerr("  " + e)
	print("--------------------------------------\n")
