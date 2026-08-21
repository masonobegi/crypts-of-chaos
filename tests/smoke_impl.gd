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
			_check_the_morning_only_happens_once()
			_check_every_indicated_treatment_can_be_given()
			_check_a_wrong_site_can_be_revised()
			_check_the_ward_sleeps_at_night()
			_check_the_tutorial_can_advance()
			_check_a_family_row_keeps_going()
			_check_your_cut_moves_while_you_play()
			_check_the_money_is_visible_in_the_building()
			game.shift.end_shift()
			_check_the_day_can_still_end()
			stage = "close"
		"close":
			var report: Dictionary = game.shift.clock_out()
			_check_report(report)
			_check_phase_is_not_a_dead_end("statement")
			_check_the_evening_and_the_post_lead_somewhere()
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

## Nothing is standing inside anything else.
##
## The playtest note was "a couple of weird rendering things where things are
## phasing through". That is not a renderer problem — it is two objects placed
## at overlapping positions by two different pieces of code that do not know
## about each other, and it is exactly the failure mode of adding a decoration
## pass on top of a furniture pass on top of a floor plan.
##
## So this walks every free-standing object in the building — anything with a
## mesh, small enough not to be architecture — and fails on any pair whose boxes
## genuinely interpenetrate. The threshold is deliberately generous: a chair
## tucked under a table shares space and is fine; a shelf unit occupying the
## same cubic metre as a desk is not.
const OVERLAP_MIN := 0.10          ## metres of interpenetration on EVERY axis
const ARCHITECTURE := 3.4          ## anything bigger than this on two axes is a wall
## What fraction of the smaller object has to be inside the bigger one before
## this is a bug rather than carpentry.
##
## The first version measured raw overlap and immediately failed on the CT
## gantry, whose pillars stand IN its plinth — which is how a machine is built.
## A pillar in a plinth is a tenth of the pillar; a bin standing inside the
## nurses' station counter is two thirds of the bin. The difference between an
## assembly and a mistake is what proportion of the thing has disappeared.
const OVERLAP_FRACTION := 0.30

func _check_nothing_is_inside_anything_else() -> void:
	if game.hospital == null:
		return
	var boxes: Array = []
	for child in game.hospital.get_children():
		if not (child is Node3D):
			continue
		var aabb := _world_aabb(child)
		if aabb.size == Vector3.ZERO:
			continue
		var big := 0
		for axis in 3:
			if aabb.size[axis] > ARCHITECTURE:
				big += 1
		# A wall with a doorway in it is only 2.1m tall, so "big on two axes"
		# let every one of them into the audit and the report was mostly
		# fittings correctly attached to walls.
		if big >= 2 or (big >= 1 and aabb.size.y >= 2.0):
			continue
		# Physics props are excluded: a mop resting in a bucket overlaps it, and
		# where a rigid body has rolled to is the solver's business. This audit
		# is about geometry somebody PLACED.
		if child is RigidBody3D:
			continue
		boxes.append({"name": _describe(child), "aabb": aabb})

	var clashes: Array[String] = []
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a: AABB = boxes[i]["aabb"]
			var b: AABB = boxes[j]["aabb"]
			if not a.intersects(b):
				continue
			var over := a.intersection(b)
			if over.size.x < OVERLAP_MIN or over.size.y < OVERLAP_MIN \
					or over.size.z < OVERLAP_MIN:
				continue
			var vol: float = over.size.x * over.size.y * over.size.z
			var smallest: float = minf(
				a.size.x * a.size.y * a.size.z, b.size.x * b.size.y * b.size.z)
			if smallest <= 0.0 or vol / smallest < OVERLAP_FRACTION:
				continue
			clashes.append("%s@(%.2f,%.2f,%.2f)%.2fx%.2fx%.2f ∩ %s@(%.2f,%.2f,%.2f)%.2fx%.2fx%.2f" % [
				boxes[i]["name"], a.get_center().x, a.get_center().y, a.get_center().z,
				a.size.x, a.size.y, a.size.z,
				boxes[j]["name"], b.get_center().x, b.get_center().y, b.get_center().z,
				b.size.x, b.size.y, b.size.z])
	if clashes.is_empty():
		_ok(true, "nothing in the building is standing inside anything else")
	else:
		for c in clashes:
			notes.append("overlap: " + c)
		_ok(false, "%d pairs of objects interpenetrate (first: %s)" % [
			clashes.size(), clashes[0]])

## Something a person could act on: the node's own name if it has been given
## one, otherwise its class and what it calls itself in the fiction.
func _describe(n: Node) -> String:
	var nm := String(n.name)
	if not nm.begins_with("@"):
		return nm
	if n.has_method("get_item_id"):
		return "prop:%s" % String(n.call("get_item_id"))
	var disp = n.get("fixture_name")
	if disp != null and String(disp) != "":
		return "fixture:%s" % String(disp)
	var scr = n.get_script()
	if scr != null:
		return "%s(%s)" % [n.get_class(), String(scr.resource_path).get_file()]
	return n.get_class()

## The world-space box of everything a node draws. Built from its mesh
## descendants rather than from a collision shape, because most of what is
## being audited here is decoration and has no collider at all.
func _world_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D) or n.mesh == null:
			continue
		var local: AABB = n.mesh.get_aabb()
		var xf: Transform3D = (n as Node3D).global_transform
		var world := xf * local
		if first:
			out = world
			first = false
		else:
			out = out.merge(world)
	return out

func _check_boot() -> void:
	_ok(game.hospital != null and game.hospital.rooms.size() == 15, "hospital built with 15 rooms")
	# The three annexe departments are built but shuttered on day one.
	_ok(game.hospital != null and game.hospital.open_room_keys().size() == 12,
		"twelve of them are open at career start")
	_ok(game.player != null, "player spawned")
	_ok(game.player.global_position.y > -5.0, "player is not under the floor")
	_ok(tree.get_nodes_in_group("staff").size() >= 3, "staff spawned")
	_check_nothing_is_inside_anything_else()
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
	# Any machine: the wards no longer have one. What used to be a bedside box
	# with a knob on it is a prescription now, and the only device left in the
	# building is the imaging bench — which is still the sabotage path this is
	# actually testing, because a miscalibrated one writes a wrong, timestamped,
	# uneditable observation into a chart that turns up in court.
	var machine: TreatmentMachine = null
	for f in tree.get_nodes_in_group("fixture"):
		if f is TreatmentMachine:
			machine = f
			break
	if machine == null:
		_fail("no treatment machine found anywhere in the building")
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

## Which room a patient is in is a question about where the PATIENT is, and an
## admitted patient standing in Emergency Intake is being ramped. The ward has
## to notice, and whether it is defensible depends on whether there was anywhere
## else to put them.
func _check_wheeling(ps) -> void:
	var p = null
	for q in ps.active():
		if q.room != "intake" and ps.get_body(q.id) != null and ps.get_body(q.id).bed != null:
			p = q
			break
	if p == null:
		_fail("no ward patient with a chair of their own")
		return
	var home: String = p.room
	var body = ps.get_body(p.id)
	var seen: Array[String] = []
	var probe := func(evt): seen.append(String(evt.kind))
	EventBus.world_event.connect(probe)
	var had_room: bool = not ps.free_wards().is_empty()
	# The patient walks, rather than the bed being wheeled: there are no beds
	# any more and the chair does not move. Ending up parked in Intake is still
	# ramping and still has to be noticed.
	body.state = PatientNPC.State.WANDERING
	body.global_position = Vector3(-8.0, 0.0, 7.0)
	GameState.active_covers.erase("bed_shortage")
	ps._reconcile_room(p, body)
	EventBus.world_event.disconnect(probe)
	_ok(p.room == "intake", "a patient left standing in Intake is recorded as being in Intake")
	# Ramping is an observable act with the player as its actor, so it goes
	# through perception like anything else you do.
	_ok(seen.has("patient_moved_to_corridor"), "and everybody in the room can see it happen")
	# Defensible only when there was genuinely nowhere else to put them.
	_ok(GameState.has_cover("bed_shortage") != had_room,
		"a bed shortage excuses it and a free ward does not (free ward: %s)" % str(had_room))
	_ok(ps.free_wards().has(home),
		"and the room they left is available again, because the chair is still in it")

	# Walk them back and the ward is theirs again. Ramping is reversible, which
	# is what makes it a tactic rather than a mistake.
	body.global_position = ps.hospital.bed_position(home)
	ps._reconcile_room(p, body)
	_ok(p.room == home, "and walking them back puts them where they started")
	_ok(not ps.free_wards().has(home), "so the room is occupied again")

func comp_owner(p: Patient) -> Patient:
	return p

## The chart review offers "Go and fix it", which closes it. Everything that
## ends a day has to survive that.
##
## It did not. clock_out() had exactly one caller in the whole shipping game —
## the review screen's other button — and end_shift() cannot run twice, because
## it sets CHART_REVIEW, which stops the clock, which is the only thing that
## calls end_shift(). Taking the game up on its own offer ended the career: no
## report, no pay, no next day, and no object anywhere in the building that
## could finish the shift. Nothing caught it because every harness, including
## this one, called end_shift() and clock_out() back to back.
func _check_the_day_can_still_end() -> void:
	_ok(not game.shift.last_review.is_empty(),
		"the chart review is kept, so closing it is not the end of the career")
	_check_phase_is_not_a_dead_end("review")
	# The player walks away and comes back to it.
	if game.ui != null:
		game.ui.close()
	var term = null
	for f in tree.get_nodes_in_group("fixture"):
		if f is RecordsTerminal and f.mode == "admin":
			term = f
	_ok(term != null, "there is an admin terminal to sign off at")
	if term == null:
		return
	var p: Array = term.prompt(game.player)
	_ok(String(p[0]) == "Finish the shift",
		"and after the review it offers to end the day (%s)" % String(p[0]))

## With nothing on screen, every phase that can only be left through a screen
## has to be able to put that screen back.
##
## Three of the five could not. PRE_SHIFT is left by the briefing's Clock in,
## CHART_REVIEW by the review's Clock out, POST_SHIFT by the statement's Go
## home — and all three screens could be dismissed with Escape, or in the
## review's case by its own second button. Each one ended the career silently:
## a running game, a stopped clock, and no input anywhere that could advance
## the day.
## The join between the three phases must always lead somewhere.
##
## `after_statement()` is the only thing standing between the end of a day and
## the beginning of the next one, and it has three exits: a claim to answer, an
## evening to spend, or tomorrow. A career that fell into it and stopped would
## be unrecoverable and completely silent, which is the worst class of bug this
## game can have — so both branches are walked here, on a real career, with the
## real screens.
func _check_the_evening_and_the_post_lead_somewhere() -> void:
	var legal = game.get("legal")
	var night = game.get("night")
	if legal == null or night == null:
		_fail("the legal and night systems did not spawn")
		return

	# Branch one: a letter. File a claim on somebody real and check the court
	# screen is what comes up.
	var pool: Array = game.patient_system.active()
	if not pool.is_empty():
		var claim: Dictionary = legal.file_claim(pool[0], "premature_discharge")
		claim["day_filed"] = GameState.day
		_ok(legal.due_claims().size() > 0, "a served claim is due to be answered")
		if game.ui != null:
			game.ui.close()
		game.shift.after_statement()
		_ok(game.ui != null and game.ui.current_id == "court",
			"a served claim opens the courtroom rather than being skipped")
		# Answering it must clear it out of the way.
		legal.settle(claim)
		_ok(legal.due_claims().is_empty(), "and settling it takes it off the list")
		if game.ui != null:
			game.ui.close()

	# Branch two: no letters, so the evening is offered.
	night.used_tonight = false
	game.shift.after_statement()
	_ok(game.ui != null and game.ui.current_id == "night",
		"with nothing to answer, the evening is offered")
	if game.ui != null:
		game.ui.close()

	# Branch three: an evening already spent falls through to tomorrow. Checked
	# by state rather than by calling next_day(), which the harness does itself
	# one stage later.
	night.used_tonight = true
	_ok(not night.available(), "an evening already spent is not offered twice")

func _check_phase_is_not_a_dead_end(want: String) -> void:
	if game.ui == null:
		return
	game.ui.close()
	var owed: Dictionary = game.ui._owed_screen()
	_ok(String(owed.get("id", "")) == want,
		"with nothing on screen, %s offers its way out (%s)" % [
			GameState.Phase.keys()[GameState.phase], String(owed.get("id", "nothing"))])

## Every treatment the chart can print as INDICATED must be performable.
##
## Two ways it was not. Splinting and Sling Support name `splint` and `sling` as
## their tool; both items existed, meshed and priced, and were stocked nowhere
## in the building — so the only two treatments for a fracture could not be
## given by anybody, while the chart listed them and named the tool. And six
## treatments have no tool at all, which the chart renders as "no equipment" —
## the item-in-hand grammar had no way to express those, so they had no input
## path either.
## Running the morning twice for the same day must be a no-op.
##
## `Game._start()` calls begin_day() straight after loading a save, and the
## autosave is written inside clock_out() with the day just worked still
## current. So pressing Continue re-settled the debts, re-rolled the morning's
## events, re-ran the investigation checks and rebuilt the appointment list for
## a shift that was already over. The player was charged a second day of rent
## for loading their own game.
func _check_the_morning_only_happens_once() -> void:
	var money := GameState.personal_money
	var hosp := GameState.hospital_money
	var census: int = game.patient_system.active_count()
	var slots: int = game.appointments.list.size() if game.appointments else 0
	game.shift.begin_day()
	_ok(GameState.personal_money == money and GameState.hospital_money == hosp,
		"running the morning again charges nothing (%d/%d -> %d/%d)" % [
			money, hosp, GameState.personal_money, GameState.hospital_money])
	_ok(game.patient_system.active_count() == census,
		"and admits nobody a second time")
	_ok(game.appointments == null or game.appointments.list.size() == slots,
		"and does not rebuild a list that is already half worked")
	# begin_day() sets PRE_SHIFT; the shift was in progress, so put it back.
	GameState.set_phase(GameState.Phase.SHIFT)

## A wrong site has to be a situation the player can respond to.
##
## Opening a part of somebody that was not the problem is catastrophic and stays
## catastrophic — but before this the only thing left to do about it was press
## Close, and a mistake you cannot respond to is not a mistake, it is a
## punishment. A surgeon who realises mid-list does the indicated procedure as
## well: a second operation, a second set of risks, and a theatre record with
## two sites on it that no auditor reads charitably.
## The three shifts have to be different in something the player DOES, not only
## in five numbers on a selection screen.
##
## At night most of the ward is asleep and a sleeping patient witnesses nothing,
## so the five people who would normally be lying there watching you work are
## five people who are not. It is not free: they wake to a bang, so the
## distraction that moved the nurse also wakes the man in the next bed.
## Does the number the player is actually trying to survive on ever move?
##
## It did not: across four scripted playstyle runs the personal-money readout
## was identical at 8:00 and at 3:59, because the crime pays at clock-out and
## nowhere else. The take is now accrued as the ward bills, so keeping somebody
## another night is something you watch rather than something you infer.
func _check_your_cut_moves_while_you_play() -> void:
	var eco = game.economy
	var before: int = eco.take_so_far()
	eco.bill_interval()
	eco.bill_interval()
	var after: int = eco.take_so_far()
	_ok(after > before, "your cut of the shift grows while the shift is running (%d -> %d)"
		% [before, after])
	eco.bill_procedure("Smoke Test Procedure", 900)
	_ok(eco.take_so_far() > after, "and a procedure you performed lands on it immediately")

## Eighteen upgrades and the only one you could SEE was a shutter rolling up.
## This asserts the fittings exist, that they track ownership rather than being
## built once, and that they survive the rebuild a save-load triggers — a career
## restored from disk finding a bare ward would read as having lost the money.
func _check_the_money_is_visible_in_the_building() -> void:
	var h = game.hospital
	var owned_before: Array = GameState.owned_upgrades.duplicate()

	GameState.owned_upgrades.clear()
	h.refresh_fittings()
	var bare: int = h.get_node("Fittings").get_child_count()
	_ok(bare == 0, "a ward nobody has spent anything on has no fittings in it")

	for id in ["security_cameras", "private_rooms", "shred_bin", "board_appointment"]:
		GameState.owned_upgrades.append(id)
	h.refresh_fittings()
	var kitted: int = h.get_node("Fittings").get_child_count()
	_ok(kitted > bare, "buying things puts things in the building (%d)" % kitted)

	# Twice in a row must not stack: this runs on build, on purchase AND on load.
	h.refresh_fittings()
	_ok(h.get_node("Fittings").get_child_count() == kitted,
		"and refreshing again does not build a second set of them")

	GameState.owned_upgrades.assign(owned_before)
	h.refresh_fittings()

## A family dispute is supposed to be a day-long condition of the ward, not a
## single WorldEvent thirty seconds into the morning. Both halves of the row
## used to walk out of the building on their first physics frame, and nothing
## re-emitted the noise afterwards, so the one event whose entire promise is
## "nobody is watching anything else" had never distracted anybody at all.
func _check_a_family_row_keeps_going() -> void:
	var ev = game.get_node_or_null("RandomEvents")
	if ev == null:
		ev = tree.get_first_node_in_group("random_events")
	if ev == null:
		_ok(false, "there is a random-event system to fire an event from")
		return

	var heard: Array = []
	var probe := func(e): if e.kind == "argument": heard.append(e.pos)
	EventBus.world_event.connect(probe)

	ev.apply("family_dispute")
	_ok(heard.size() == 1, "a family dispute makes a noise when it starts")

	var arguing := 0
	for v in tree.get_nodes_in_group("visitor"):
		if String(v.npc_id).begins_with("argument_"):
			arguing += 1
	_ok(arguing == 2, "and puts two people in the corridor to make it (%d)" % arguing)

	# Roll the clock past one period. The row should flare up again on its own.
	GameState.career_minutes += ev.ROW_PERIOD + 1
	ev._on_clock_tick(GameState.minute_of_day)
	_ok(heard.size() == 2, "and it is still going twenty minutes later")

	# ...and not more often than that, or it is a siren rather than an argument.
	ev._on_clock_tick(GameState.minute_of_day)
	_ok(heard.size() == 2, "but it does not go off every single minute")

	# Both parties leaving is the one thing that ends it.
	for v in tree.get_nodes_in_group("visitor"):
		if String(v.npc_id).begins_with("argument_"):
			v.queue_free()
	await_free_hack(ev)
	GameState.career_minutes += ev.ROW_PERIOD + 1
	ev._on_clock_tick(GameState.minute_of_day)
	_ok(not bool(GameState.flag("families_arguing", false)),
		"and it stops when both of them finally go home")

	EventBus.world_event.disconnect(probe)

## queue_free() lands at the end of the frame; the row's guarded accessor has to
## see the freed nodes, so drop them from its list the way the tree eventually
## will. Reading them into a TYPED local here would abort this function outright
## (CLAUDE.md #11), which is precisely the hazard the accessor exists to survive.
func await_free_hack(ev) -> void:
	var live: Array = []
	for entry in ev._row:
		var b = entry
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			live.append(b)
	ev._row = live

func _check_the_ward_sleeps_at_night() -> void:
	var pool: Array = game.patient_system.active()
	if pool.is_empty():
		return
	var body = game.patient_system.get_body(pool[0].id)
	if body == null:
		_ok(false, "there is a patient body to put to sleep")
		return
	body.set_asleep(true)
	_ok(body.asleep, "a patient can be asleep")
	_ok(body.perception != null and body.perception.attention == 0.0,
		"and an asleep patient's attention is genuinely zero, not merely dimmed")

	# A noise in the room wakes them, which is what stops night being a free pass.
	body.on_heard_noise(WorldEvent.new("test_clatter", "").at(
		body.global_position, pool[0].room).heard(0.0, 20.0))
	_ok(not body.asleep, "and a noise nearby wakes them")
	_ok(body.perception.attention > 0.0, "with their attention back")

	# Every shift has to declare a sleep rate, or a new shift silently gets the
	# day-time one and nobody notices for a year.
	var missing: Array[String] = []
	for kind in DB.SHIFT_ORDER:
		if not PatientNPC.SLEEP_CHANCE.has(String(kind)):
			missing.append(String(kind))
	_ok(missing.is_empty(), "every shift says how much of the ward is asleep%s" % (
		"" if missing.is_empty() else ": " + ", ".join(missing)))

func _check_a_wrong_site_can_be_revised() -> void:
	var pool: Array = game.patient_system.active()
	if pool.is_empty():
		return
	# The LAST patient on the ward, not the first. The save/load round-trip
	# further down authors a theatre record on active()[0] and then asserts its
	# exact contents, so operating on the same person here rewrites the thing
	# that check is checking.
	var p = pool[pool.size() - 1]
	var right: String = TreatmentSystem.indicated_site_for(p)
	var wrong := "knee" if right != "knee" else "wrist"
	var before := int(GameState.stats.surgeries)

	var bad: Dictionary = game.treatment.perform_surgery(p, wrong,
		["careful", "careful", "careful"])
	_ok(bool(bad.get("wrong_site", false)),
		"operating somewhere other than the indicated site is recorded as one")
	_ok(String(bad.get("indicated", "")) == right,
		"and the outcome names the site that should have been opened (%s)" % right)

	# The revision: same patient, correct site, on a body already opened once.
	var fixed: Dictionary = game.treatment.perform_surgery(p, right,
		["improvise", "improvise", "improvise"])
	_ok(not bool(fixed.get("wrong_site", true)),
		"going back for the indicated site is not itself a wrong site")
	_ok(int(GameState.stats.surgeries) == before + 2,
		"and the record shows both operations, not one")
	_ok(p.chart.surgery_log.size() >= 2,
		"with both sites on the theatre record for anybody who reads it")

func _check_every_indicated_treatment_can_be_given() -> void:
	var obtainable := {}
	for f in tree.get_nodes_in_group("fixture"):
		if f is SupplyShelf:
			for id in f.items:
				obtainable[String(id)] = true
	for pr in tree.get_nodes_in_group("prop"):
		obtainable[String(pr.get_item_id())] = true

	var missing: Array[String] = []
	var handsfree := 0
	for tid in DB.TREATMENTS:
		var tool_id := String(DB.TREATMENTS[tid].get("tool", ""))
		if tool_id == "":
			handsfree += 1
			continue
		if not Items.SPECS.has(tool_id):
			continue      # a machine, not a carryable
		if not obtainable.has(tool_id):
			missing.append("%s needs %s" % [String(tid), tool_id])
	_ok(missing.is_empty(),
		"every hand tool a treatment names is somewhere in the building%s" % (
			"" if missing.is_empty() else ": " + ", ".join(missing)))
	_ok(handsfree > 0, "and the no-equipment treatments exist to be offered (%d)" % handsfree)

## The tutorial has six steps and could only ever complete zero of them.
##
## Step 1 is "check your list", completed by opening the tablet — and the
## tutorial listened for `request_ui`, which is a REQUEST. The tablet is opened
## straight from the input handler and from the pause menu, both of which call
## the router directly. So the first step never completed, and because the
## tutorial advances strictly in order, neither did the other five.
func _check_the_tutorial_can_advance() -> void:
	var tut = tree.get_first_node_in_group("tutorial")
	if tut == null:
		_ok(false, "there is a tutorial system")
		return
	tut._active = true
	tut._index = 0
	if game.ui != null:
		game.ui.open("tablet", {})
		game.ui.close()
	_ok(tut._index > 0,
		"opening the tablet advances the tutorial off step 1 (index %d)" % tut._index)
	tut._active = false

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
