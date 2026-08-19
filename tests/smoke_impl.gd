extends RefCounted
## Implementation of the headless playthrough. Loaded at RUNTIME by
## tests/smoke_run.gd — autoloads (GameState, RNG, ...) are not resolvable at
## compile time from a --script main loop, so none of this can live there.

var tree: SceneTree = null
var game: Node = null
var frames := 0
var stage := "boot"
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
		"boot":
			if frames > 6:
				_check_boot()
				stage = "shift"
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

	_check_intake_overflow(ps)

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

	# Save/load must survive a full round trip with live patients.
	var before_count: int = game.patient_system.active_count()
	var before_money: int = GameState.personal_money
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
