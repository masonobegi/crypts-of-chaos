extends RefCounted
## Integration tests for the runtime systems. These actually construct the
## hospital in a headless tree — compilation passing is not the same as the
## floor being connected, and an unreachable ward would be invisible until an
## NPC silently failed to path there.
var t

var _h = null

func _hospital():
	if _h != null and is_instance_valid(_h):
		return _h
	var HospitalScript := load("res://scripts/world/hospital.gd")
	_h = HospitalScript.new()
	t.root.add_child(_h)
	_h.build()
	return _h

func test_hospital_builds_all_rooms() -> void:
	var h = _hospital()
	t.eq(h.rooms.size(), 15, "every room in LAYOUT is constructed")
	for key in ["corridor", "ward_101", "ward_105", "lobby", "station",
			"treatment", "supply", "bathroom", "office",
			"intake", "radiology", "day_room"]:
		t.ok(h.room(key) != null, "room exists: %s" % key)

func test_room_lookup_by_position() -> void:
	var h = _hospital()
	t.eq(h.room_at(Vector3(4.5, 0, 8.0)), "ward_101", "point inside ward 101")
	t.eq(h.room_at(Vector3(23.0, 0, 2.0)), "corridor", "point inside corridor")
	t.eq(h.room_at(Vector3(43.0, 0, -5.0)), "office", "point inside office")
	t.eq(h.room_at(Vector3(-40.0, 0, -40.0)), "", "point outside the floor")

func test_rooms_do_not_overlap() -> void:
	var h = _hospital()
	var list = h.room_list()
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Rect2 = list[i].rect
			var b: Rect2 = list[j].rect
			var overlap := a.intersection(b)
			t.lt(overlap.get_area(), 0.001, "%s and %s do not overlap" % [list[i].key, list[j].key])

func test_navigation_is_connected() -> void:
	var h = _hospital()
	t.gt(float(h.nav.cell_count()), 300.0, "nav grid has meaningful coverage")
	# Every OPEN room must be reachable from the lobby, or NPCs silently fail to
	# path. The annexe departments are deliberately sealed at career start and
	# are covered by test_a_sealed_department_is_genuinely_sealed.
	var from: Vector3 = h.point_in("lobby")
	for key in h.open_room_keys():
		var to = h.point_in(key)
		var path = h.nav.find_path(from, to)
		t.gt(float(path.size()), 0.0, "path exists from lobby to %s" % key)

## A shutter has to be a wall as far as navigation is concerned. If it is only
## a mesh, staff path into a department nobody has paid for and stand inside it.
func test_a_sealed_department_is_genuinely_sealed() -> void:
	var h = _hospital()
	var from: Vector3 = h.point_in("lobby")
	for key in ["intake", "radiology", "day_room"]:
		t.ok(not h.is_room_open(key), "%s starts sealed" % key)
		t.ok(not h.open_room_keys().has(key), "%s is not offered as somewhere to go" % key)
		t.eq(h.nav.find_path(from, h.point_in(key)).size(), 0,
			"nothing can path into %s while it is shut" % key)
	# The corridor still has to run past all three of them.
	t.gt(float(h.nav.find_path(h.point_in("office"), Vector3(-14.0, 0, 2.0)).size()), 0.0,
		"the corridor still runs the length of the annexe")

## And opening one has to actually open it — including for pathfinding, which is
## the half that would fail silently.
func test_buying_a_department_opens_its_shutter() -> void:
	# A fresh floor, not the shared one: opening a shutter is one-way by design,
	# so doing it to the cached hospital would silently change what every test
	# declared after this one is looking at.
	var owned := GameState.owned_upgrades.duplicate()
	GameState.owned_upgrades.append("dept_psych")
	var h = load("res://scripts/world/hospital.gd").new()
	t.root.add_child(h)
	h.build()
	t.ok(h.is_room_open("day_room"), "the shutter is up")
	t.gt(float(h.nav.find_path(h.point_in("lobby"), h.point_in("day_room")).size()), 0.0,
		"and staff can now walk into it")
	t.ok(not h.is_room_open("radiology"), "the ones you did not buy stay shut")

	# And buying one later opens it in place, without rebuilding the floor.
	GameState.owned_upgrades.append("dept_radiology")
	h.refresh_departments()
	t.ok(h.is_room_open("radiology"), "a shutter opens on purchase, mid-career")
	t.gt(float(h.nav.find_path(h.point_in("lobby"), h.point_in("radiology")).size()), 0.0,
		"and the floor re-connects without a rebuild")

	GameState.owned_upgrades = owned
	h.queue_free()

func test_ward_to_ward_paths_cross_the_corridor() -> void:
	var h = _hospital()
	var path = h.nav.find_path(h.point_in("ward_101"), h.point_in("ward_105"))
	t.gt(float(path.size()), 3.0, "cross-floor path has waypoints")
	var touched_corridor := false
	for p in path:
		if h.room_at(p) == "corridor":
			touched_corridor = true
	t.ok(touched_corridor, "ward-to-ward route goes through the corridor, not through walls")

func test_beds_exist_in_every_ward() -> void:
	var h = _hospital()
	var beds: Array = h.get_tree().get_nodes_in_group("bed")
	t.gt(float(beds.size()), 4.0, "a bed per ward")
	for w in h.wards():
		var found := false
		for b in beds:
			if b.room_key == w.key:
				found = true
		t.ok(found, "ward %s has a bed" % w.key)

func test_room_comfort_responds_to_environment() -> void:
	var h = _hospital()
	var r = h.room("ward_102")
	r.temperature = 21.0
	r.lights_on = true
	r.cleanliness = 1.0
	var base: float = r.comfort()
	t.gt(base, 0.95, "a comfortable room does not slow recovery")
	r.temperature = 9.0
	t.lt(r.comfort(), base * 0.85, "a freezing room slows recovery")
	r.temperature = 21.0
	r.lights_on = false
	t.lt(r.comfort(), base, "darkness slows recovery")
	r.lights_on = true
	r.cleanliness = 0.0
	t.lt(r.comfort(), base, "filth slows recovery")

func test_open_window_cools_the_room() -> void:
	var h = _hospital()
	var r = h.room("ward_103")
	r.temperature = 21.0
	r.window_open = true
	for i in 200:
		r._drift_temperature(1.0)
	t.lt(r.temperature, 15.0, "an open window genuinely chills the ward")
	t.ok(r.complaints().size() > 0, "and people in it have something to say about that")

func test_machine_normal_setting_is_clean() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp")
	p.condition_id = "spleen_torque"      # humour_rebalance is correct for this
	m.set_prescribed_for(p)
	m.dial = m.prescribed
	var res: Dictionary = m.run_cycle(p)
	t.eq(res["band"], "normal", "on-prescription is the normal band")
	t.gt(float(res["recovery"]), 0.2, "and actually treats the patient")
	t.near(float(res["visual"]), 0.0, 0.001, "and looks like nothing at all")
	t.eq(String(res["complication"]), "", "with no complication")
	m.queue_free()

func test_machine_extreme_setting_is_visible_and_harmful() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp2")
	p.condition_id = "spleen_torque"
	m.set_prescribed_for(p)
	m.dial = clampi(m.prescribed + 6, 0, 11)
	if absi(m.dial - m.prescribed) < 5:
		m.dial = clampi(m.prescribed - 6, 0, 11)
	var res: Dictionary = m.run_cycle(p)
	t.eq(res["band"], "extreme", "far off-prescription is the extreme band")
	t.lt(float(res["recovery"]), 0.0, "and actively harms recovery")
	t.gt(float(res["visual"]), 0.4, "and is very visible to anyone watching")
	t.ok(String(res["complication"]) != "", "and guarantees a complication")
	m.queue_free()

## The dial turns both ways, and only reports where it STOPS.
##
## It used to climb only and wrap at 11, so the sole route from 9 down to 4 ran
## 10, 11, 0, 1, 2, 3, 4 — five of those stops four or more off prescription,
## each firing a witness roll. Turning a dial DOWN was the most incriminating
## act in the building and nothing in the interface said so. And the event fired
## on every click, so overshooting by one and correcting published two extreme
## readings instead of none.
func test_the_dial_turns_both_ways_and_only_reports_where_it_stops() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	m.prescribed = 5
	m.dial = 9

	# Down from 9 reaches 4 in five clicks, not seven.
	var clicks := 0
	while m.dial != 4 and clicks < 20:
		m.dial = TreatmentMachine.DIAL_MAX if m.dial <= TreatmentMachine.DIAL_MIN else m.dial - 1
		clicks += 1
	t.eq(clicks, 5, "nine down to four is five clicks")

	# And nothing is announced until the dial has been left alone. A machine
	# that has just been built and never touched must be silent, however far
	# from prescription it happens to be sitting.
	m.dial = 11
	m._dial_settle = 1.0
	m._announced_dial = 11
	m._process(0.1)
	t.eq(m._announced_dial, 11, "a settled dial re-announces nothing")

	# Moving it restarts the clock; a value passed through is never announced.
	m._dial_settle = 0.0
	m.dial = 0
	m._process(0.2)
	t.eq(m._announced_dial, 11, "still nothing at 0.2s — the dial is still turning")
	m._process(0.6)
	t.eq(m._announced_dial, 0, "and it reports 0 once it has come to rest")
	m.queue_free()

## Calibration sabotage and log-wiping both existed with no way in.
##
## open_panel() and clear_log() had no callers anywhere in the shipping game, so
## `calibration` was always exactly 1.0, `is_miscalibrated()` could never return
## true, and the branch of run_cycle that reads it never fired — while the class
## docstring and SPOILERS.md both describe calibration sabotage as a headline
## mechanic. This drives the real interact() path rather than calling the
## private helpers, because calling them directly is exactly what hid it.
func test_the_maintenance_panel_can_actually_be_opened() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var wrench = Items.spawn("wrench")
	t.root.add_child(wrench)

	t.near(m.calibration, 1.0, 0.001, "a machine starts correctly calibrated")
	t.eq(m.use_seconds(null, wrench), 0.0, "a wrench is a tap, not a hold")
	m.interact(null, wrench)
	t.ok(m._panel_open, "a wrench opens the maintenance panel")
	m.interact(null, wrench)
	t.lt(m.calibration, 1.0, "and turning the screw genuinely miscalibrates it")
	for i in 6:
		m.interact(null, wrench)
	t.ok(m.is_miscalibrated(), "far enough that is_miscalibrated() can be true at all")

	# Hands free, the same open panel is how a log gets wiped — and it is a
	# hold, because it is the one act here you have to stand and do.
	m.log_entries.append({"deviation": 5})
	m.log_entries.append({"deviation": 0})
	t.gt(m.use_seconds(null, null), 1.0, "wiping the log is a hold")
	m.interact(null, null)
	t.eq(m.log_entries.size(), 0, "empty-handed at an open panel wipes the device log")
	t.eq(m.log_cleared_count, 1, "and the machine remembers that it was wiped")
	t.ok(not m._panel_open, "which also shuts the panel behind you")
	wrench.queue_free()
	m.queue_free()

## Substituting the contents of a container had no risk and no undo.
##
## Decanting worked and produced a container that says one thing and holds
## another — and is_mislabelled(), commented "what an observant nurse spots",
## had exactly one reader in the repository: a unit test. Nothing in the game
## looked at it, and relabel() had no caller at all. So the single most useful
## verb in the game was completely free, which is not a mechanic.
func test_a_mislabelled_container_is_both_noticeable_and_fixable() -> void:
	var syringe = Items.spawn("syringe")
	var canister = Items.spawn("dread_canister")
	var form = Items.spawn("blank_form")
	for n in [syringe, canister, form]:
		t.root.add_child(n)

	syringe.contents = "chalkinol"
	syringe.label = "Chalkinol"
	t.ok(not syringe.is_mislabelled(), "an honest syringe is honest")

	# Decant the canister into it. The label is deliberately left alone.
	syringe.interact(null, canister)
	t.eq(syringe.contents, canister.contents, "the syringe now holds what the canister did")
	t.ok(syringe.is_mislabelled(), "and it is now lying about it")
	t.gt(syringe.use_seconds(null, form), 1.0,
		"paperwork in hand offers to rewrite the label, as a hold")

	# Rewriting it makes it honest again — the tidying-up half of the trick.
	syringe.interact(null, form)
	t.ok(not syringe.is_mislabelled(), "rewriting the label makes it true again")
	t.eq(syringe.use_seconds(null, form), 0.0,
		"and there is nothing left to rewrite")

	for n in [syringe, canister, form]:
		n.queue_free()

## And the site is legible on the patient, not only on a screen.
func test_every_operable_site_can_be_marked_on_a_body() -> void:
	var marks: Dictionary = load("res://scripts/npc/patient_npc.gd").SITE_MARKS
	var missing: Array[String] = []
	for site in TreatmentSystem.SURGERY_SITES:
		if String(site) == "general":
			continue      # nothing to point at
		if not marks.has(String(site)):
			missing.append(String(site))
	t.ok(missing.is_empty(),
		"every operable site has somewhere on the body to mark%s" % (
			"" if missing.is_empty() else ": " + ", ".join(missing)))

func test_machine_keeps_an_auditable_log() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp3")
	p.condition_id = "spleen_torque"
	p.display_name = "Greg"
	m.set_prescribed_for(p)
	m.dial = m.prescribed
	m.run_cycle(p)
	t.eq(m.suspicious_log_entries().size(), 0, "a by-the-book cycle leaves nothing to find")
	m.dial = clampi(m.prescribed + 4, 0, 11)
	if absi(m.dial - m.prescribed) < 3:
		m.dial = clampi(m.prescribed - 4, 0, 11)
	m.run_cycle(p)
	t.eq(m.suspicious_log_entries().size(), 1, "a deviation is recorded against your name")
	t.eq(m.log_entries.size(), 2, "the log keeps everything")
	m.clear_log()
	t.eq(m.log_entries.size(), 0, "wiping works")
	t.eq(m.log_cleared_count, 1, "and is itself recorded, which is the point")
	m.queue_free()

func test_miscalibration_is_persistent_and_invisible() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp4")
	p.condition_id = "spleen_torque"
	m.set_prescribed_for(p)
	m.dial = m.prescribed
	var healthy: float = float(m.run_cycle(p)["recovery"])
	m.open_panel()
	for i in 4:
		m._nudge_calibration()
	m.close_panel()
	var sabotaged: float = float(m.run_cycle(p)["recovery"])
	t.lt(sabotaged, healthy * 0.75, "miscalibration steals effectiveness from every cycle")
	t.ok(m.is_miscalibrated(), "and persists until someone services it")
	t.eq(m.suspicious_log_entries().size(), 0, "while leaving the dial log spotless")
	m.queue_free()

# ==================================================================== deals
func _mind_with_evidence(arch := "corrupt") -> Mind:
	var m := DB.make_mind("n_deal", "Nurse Test", "nurse", arch)
	var e := Evidence.new()
	e.kind = "machine_extreme_dial"
	e.about_actor = "player"
	e.source = Evidence.Source.WITNESSED
	e.time = GameState.career_minutes
	e.base_weight = 0.6
	e.certainty = 1.0
	m.add_evidence(e)
	return m

func test_paying_off_a_witness_buys_real_silence() -> void:
	GameState.start_new_career(4)
	GameState.personal_money = 5000
	var m := _mind_with_evidence()
	m.deal_state = "offered"
	m.deal_price = 400
	var before := m.suspicion(GameState.career_minutes)
	t.gt(before, 0.0, "the witness starts out suspicious")

	var opts: Array = Dialogue.options_for(m, null)
	t.eq(opts.size(), 4, "a live offer replaces the normal conversation")
	var pay = opts[0]
	var res: Dictionary = Dialogue.resolve(m, pay, null)
	t.ok(bool(res.get("success", false)), "the payment lands")
	t.eq(m.deal_state, "paid", "the deal is recorded as paid")
	t.eq(GameState.personal_money, 4600, "and it actually costs money")
	t.lt(m.suspicion(GameState.career_minutes), before * 0.4,
		"a bought witness stops being a problem")
	t.lt(m.escalation, 0.1, "and stops escalating")
	t.eq(int(GameState.flag("corrupt_staff_count", 0)), 1,
		"and counts toward the Medical Mafia ending")

func test_cannot_pay_a_bribe_you_cannot_afford() -> void:
	GameState.start_new_career(5)
	GameState.personal_money = 50
	var m := _mind_with_evidence()
	m.deal_state = "offered"
	m.deal_price = 400
	var res: Dictionary = Dialogue.resolve(m, Dialogue.options_for(m, null)[0], null)
	t.ok(not bool(res.get("success", true)), "you cannot buy what you cannot afford")
	t.eq(GameState.personal_money, 50, "and no money changes hands")
	t.eq(m.deal_state, "offered", "the offer stays open")

func test_threatening_a_blackmailer_backfires() -> void:
	GameState.start_new_career(6)
	var m := _mind_with_evidence()
	m.deal_state = "offered"
	m.deal_price = 400
	var before := m.suspicion(GameState.career_minutes)
	var opts: Array = Dialogue.options_for(m, null)
	var res: Dictionary = Dialogue.resolve(m, opts[1], null)
	t.ok(not bool(res.get("success", true)), "threatening them does not work")
	t.gt(m.suspicion(GameState.career_minutes), before,
		"it makes them more suspicious, not less")
	t.gt(m.escalation, 0.3, "and much more likely to report you")

func test_only_staff_with_something_on_you_come_over() -> void:
	var quiet := DB.make_mind("n_quiet", "Nurse Quiet", "nurse", "corrupt")
	t.eq(quiet.strongest(GameState.career_minutes), null,
		"a nurse who saw nothing has nothing to trade")
	var loaded := _mind_with_evidence()
	t.ok(loaded.strongest(GameState.career_minutes) != null,
		"a nurse who saw something does")

# ==================================================================== investigators
func test_missing_chart_is_worse_than_a_bad_one() -> void:
	# A chart full of inconsistencies is bad. A chart that isn't there is worse,
	# which is what stops "grab the chart and run" being a free answer.
	var chart := PatientChart.new()
	var comp := Complication.new()
	comp.display_name = "Ambient Dread"
	comp.plausible_causes = PackedStringArray(["idiopathic"])
	comp.documented_cause = "dietary"          # impossible cause
	var bad_findings := chart.audit([], [comp])
	var bad_weight := 0.0
	for f in bad_findings:
		bad_weight += float(f["weight"])

	var shredded := PatientChart.new()
	shredded.shredded = true
	var missing_findings := shredded.audit([], [])
	var missing_weight := 0.0
	for f in missing_findings:
		missing_weight += float(f["weight"])
	t.gt(missing_weight, bad_weight, "a missing chart weighs more than a wrong one")

func test_investigation_threshold_scales_with_legal_retainer() -> void:
	GameState.start_new_career(7)
	t.near(Upgrades.investigation_threshold_scale(), 1.0, 0.001, "no retainer, no protection")
	GameState.owned_upgrades.append("legal_retainer")
	t.gt(Upgrades.investigation_threshold_scale(), 1.3,
		"a retainer means findings need to be much stronger to stick")

func test_cameras_only_record_covered_rooms() -> void:
	GameState.start_new_career(8)
	t.eq(Upgrades.camera_rooms().size(), 0, "no cameras by default")
	GameState.owned_upgrades.append("security_cameras")
	var covered := Upgrades.camera_rooms()
	t.ok(covered.has("corridor"), "cameras cover the corridor")
	t.ok(not covered.has("ward_101"), "but never inside a patient room")

func test_private_rooms_reduce_witness_quality() -> void:
	GameState.start_new_career(9)
	t.near(Upgrades.witness_scale(), 1.0, 0.001, "open ward, full visibility")
	GameState.owned_upgrades.append("private_rooms")
	t.lt(Upgrades.witness_scale(), 0.8, "private rooms genuinely reduce what witnesses get")

# ==================================================================== obstruction
func test_blocking_a_doorway_actually_breaks_pathing() -> void:
	# The whole point of shoving a cart into a doorway is that staff genuinely
	# cannot get through it. If nav ignores the block, it is just a visual gag.
	var h = _hospital()
	var from: Vector3 = h.point_in("corridor")
	var to: Vector3 = h.point_in("ward_101")
	t.gt(float(h.nav.find_path(from, to).size()), 0.0, "ward 101 is reachable to begin with")

	var door_rect := Rect2(4.5 - 0.9, 4.0 - 0.7, 1.8, 1.4)   # ward_101's doorway
	var cells = h.nav.block_area(door_rect)
	t.gt(float(cells.size()), 0.0, "blocking the doorway disables nav cells")
	t.eq(h.nav.find_path(from, to).size(), 0, "and nothing can path through it")

	# Other wards must be unaffected — blocking one door must not sever the floor.
	t.gt(float(h.nav.find_path(from, h.point_in("ward_103")).size()), 0.0,
		"other rooms are still reachable")

	h.nav.unblock_cells(cells)
	t.gt(float(h.nav.find_path(from, to).size()), 0.0, "clearing the doorway restores the route")

func test_block_and_unblock_are_balanced() -> void:
	# Two things in one doorway then one removed must NOT clear the block.
	var h = _hospital()
	var door_rect := Rect2(13.5 - 0.9, 4.0 - 0.7, 1.8, 1.4)
	var a = h.nav.block_area(door_rect)
	var b = h.nav.block_area(door_rect)
	h.nav.unblock_cells(a)
	t.eq(h.nav.find_path(h.point_in("corridor"), h.point_in("ward_102")).size(), 0,
		"still blocked while a second obstruction remains")
	h.nav.unblock_cells(b)
	t.gt(float(h.nav.find_path(h.point_in("corridor"), h.point_in("ward_102")).size()), 0.0,
		"clear once everything is removed")

# ==================================================================== decanting
func test_decanting_changes_contents_but_not_the_label() -> void:
	var source := Items.spawn("pill_bottle")
	var target := Items.spawn("syringe")
	t.root.add_child(source)
	t.root.add_child(target)
	source.contents = "saline_plus"        # does nothing at all
	var label_before: String = target.label
	t.eq(target.contents, "chalkinol", "the syringe starts out honest")

	var p: Array = target.prompt_with_item(null, source)
	t.ok(String(p[0]).begins_with("Decant"), "decanting is offered")
	target.interact(null, source)
	t.eq(target.contents, "saline_plus", "the contents changed")
	t.eq(target.label, label_before, "the label did not")
	t.ok(target.is_mislabelled(), "and the two now disagree")
	source.queue_free()
	target.queue_free()

func test_a_substituted_syringe_does_nothing() -> void:
	# The payoff of the whole substitution mechanic: it looks identical and it
	# treats nothing.
	t.eq(Items.substance_effect("chalkinol"), "chalkinol", "real drug maps to a real treatment")
	t.eq(Items.substance_effect("saline_plus"), "", "Saline Plus maps to nothing whatsoever")

func test_you_cannot_decant_into_a_mallet() -> void:
	var mallet := Items.spawn("mallet")
	var syringe := Items.spawn("syringe")
	t.root.add_child(mallet)
	t.root.add_child(syringe)
	var p: Array = mallet.prompt_with_item(null, syringe)
	t.eq(String(p[0]), "", "solid objects do not accept contents")
	mallet.queue_free()
	syringe.queue_free()

func test_subtitles_are_scoped_to_earshot() -> void:
	# A patient muttering at the far end of the floor should not be captioned.
	var h = _hospital()
	var npc := NPCBody.new()
	npc.display = "Test Patient"
	t.root.add_child(npc)
	npc.global_position = h.point_in("ward_105")

	var heard := [false]
	var conn := func(_speaker: String, _text: String, _secs: float): heard[0] = true
	EventBus.subtitle.connect(conn)

	# With no player in the tree the line must still come through, so headless
	# tooling and cutscenes do not silently lose dialogue.
	npc.say("audible with nobody about", 0.1)
	t.ok(heard[0], "with no player present, lines are not swallowed")

	EventBus.subtitle.disconnect(conn)
	npc.queue_free()

func test_earshot_uses_distance_and_room() -> void:
	var h = _hospital()
	var npc := NPCBody.new()
	t.root.add_child(npc)
	npc.global_position = h.point_in("ward_105")
	t.gt(float(NPCBody.SUBTITLE_RANGE), 5.0, "earshot is generous enough to be useful")
	t.lt(float(NPCBody.SUBTITLE_RANGE), 30.0, "but well short of the whole floor")
	npc.queue_free()

# ==================================================================== thermostat
func test_thermostat_drives_the_room_and_leaves_a_record() -> void:
	# Quieter than an open window — no physical tell in the room — but it is a
	# device with a setting, and the setting is the cost.
	var h = _hospital()
	var r = h.room("ward_104")
	r.window_open = false
	r.temperature = 21.0
	r.target_override = -1.0

	var thermo: Thermostat = null
	for f in h.get_tree().get_nodes_in_group("fixture"):
		if f is Thermostat and f.room_key == "ward_104":
			thermo = f
	t.ok(thermo != null, "every ward has a thermostat")
	if thermo == null:
		return

	t.eq(thermo.suspicious_log_entries().size(), 0, "an untouched thermostat has nothing on file")
	while thermo.setting > 12:
		thermo.interact(null, null)
	for i in 300:
		r._drift_temperature(1.0)
	t.lt(r.temperature, 15.0, "the ward genuinely gets cold")
	t.gt(float(thermo.suspicious_log_entries().size()), 0.0,
		"and a setting that far off is on the record")

func test_moderate_thermostat_settings_leave_nothing_behind() -> void:
	var h = _hospital()
	var thermo: Thermostat = null
	for f in h.get_tree().get_nodes_in_group("fixture"):
		if f is Thermostat and f.room_key == "ward_102":
			thermo = f
	if thermo == null:
		return
	thermo.log_entries.clear()
	thermo.setting = 21
	thermo.interact(null, null)     # 19 — comfortable enough
	t.eq(thermo.suspicious_log_entries().size(), 0,
		"a small adjustment is not worth an inspector's time")

func test_patients_react_to_chaos_and_it_is_not_free() -> void:
	# Noise is the distraction economy's currency, but a ward full of startled
	# patients is unsettled, and unsettled patients are less satisfied.
	var npc := PatientNPC.new()
	t.root.add_child(npc)
	var p := Patient.new("chaos")
	p.display_name = "Test"
	p.archetype = "paranoid"
	p.satisfaction = 0.8
	npc.bind(p, null)

	var evt := WorldEvent.new("prop_noise", "")
	evt.pos = npc.global_position
	evt.hear_radius = 12.0
	npc.on_heard_noise(evt)
	t.lt(p.satisfaction, 0.8, "a crash next door costs a little satisfaction")
	t.gt(p.satisfaction, 0.7, "but only a little — it is not a punishment")
	npc.queue_free()

func test_distant_noise_matters_less_than_close_noise() -> void:
	var far := Patient.new("far")
	far.satisfaction = 0.8
	var near := Patient.new("near")
	near.satisfaction = 0.8

	var a := PatientNPC.new()
	var b := PatientNPC.new()
	t.root.add_child(a)
	t.root.add_child(b)
	a.bind(far, null)
	b.bind(near, null)
	a.global_position = Vector3(20, 0, 0)
	b.global_position = Vector3(1, 0, 0)

	var evt := WorldEvent.new("prop_noise", "")
	evt.pos = Vector3.ZERO
	evt.hear_radius = 24.0
	a.on_heard_noise(evt)
	b.on_heard_noise(evt)
	t.lt(near.satisfaction, far.satisfaction, "closer is worse")
	a.queue_free()
	b.queue_free()

func test_sending_a_nurse_away_actually_moves_them() -> void:
	# The dialogue option existed but its effect was never handled, so asking a
	# nurse to check the far end succeeded and did nothing at all.
	var h = _hospital()
	var nurse := NurseNPC.new()
	nurse.npc_id = "errand_nurse"
	nurse.archetype = "loyal"
	t.root.add_child(nurse)
	nurse.global_position = h.point_in("station")

	var near_ward: String = nurse.farthest_ward_from(h.room("ward_101").center())
	t.ok(near_ward != "ward_101", "they are sent away from where you are, not toward it")
	t.ok(near_ward.begins_with("ward"), "and to an actual ward")

	var from_other_end: String = nurse.farthest_ward_from(h.room("ward_105").center())
	t.ok(from_other_end != near_ward,
		"the destination genuinely depends on where you are standing")
	nurse.queue_free()

func test_the_errand_option_reports_that_it_did_something() -> void:
	var m := DB.make_mind("n_err", "Nurse Test", "nurse", "loyal")
	m.trust = 0.95
	var opt = Dialogue.Option.new("Could you go and check the far end?", "authority",
		"", 0.15, "delay")
	var sent := false
	for i in 30:
		var res: Dictionary = Dialogue.resolve(m, opt, null)
		if bool(res.get("send_away", false)):
			sent = true
			break
	t.ok(sent, "a trusted nurse eventually agrees, and the result says so")

# ==================================================================== noticing
func test_noticing_a_complication_closes_the_window() -> void:
	# The central mechanic: filing a plausible cause is only CLEAN if you get
	# there before somebody walks in. noticed_time was read by the records
	# system and set by nothing at all, so that clause was free.
	var h = _hospital()
	var ps = h.get_tree().get_first_node_in_group("patient_system")
	var standalone := ps == null
	if standalone:
		ps = load("res://scripts/systems/patient_system.gd").new()
		t.root.add_child(ps)

	var p := Patient.new("notice")
	p.display_name = "Greg"
	var c := Complication.new()
	c.display_name = "Ambient Dread"
	c.plausible_causes = PackedStringArray(["idiopathic"])
	c.severity = 0.4
	p.complications.append(c)

	t.eq(c.noticed_time, -1, "nobody has seen it yet")
	t.eq(ps.unnoticed_complications(p).size(), 1, "and it is listed as unnoticed")

	# Filing now is clean.
	c.documented_cause = "idiopathic"
	c.documented_at = 100
	t.ok(c.is_clean(), "documented before anyone noticed is clean")
	t.near(c.paper_suspicion(), 0.0, 0.001, "and costs nothing")

	# Same paperwork, filed after somebody saw it, is not.
	c.documented_cause = ""
	c.documented_at = -1
	GameState.career_minutes = 200
	ps.notice_complication(p, c, "nurse_0", "Nurse Test")
	t.eq(c.noticed_time, 200, "the moment it was seen is recorded")
	t.eq(ps.unnoticed_complications(p).size(), 0, "and it stops being unnoticed")
	c.documented_cause = "idiopathic"
	c.documented_at = 300
	t.ok(not c.is_clean(), "filing it afterwards is not clean")
	t.gt(c.paper_suspicion(), 0.0, "and now costs something")
	if standalone:
		ps.queue_free()

func test_only_the_first_witness_sets_the_clock() -> void:
	var ps = load("res://scripts/systems/patient_system.gd").new()
	t.root.add_child(ps)
	var p := Patient.new("first")
	var c := Complication.new()
	p.complications.append(c)

	GameState.career_minutes = 500
	ps.notice_complication(p, c, "nurse_0", "A")
	GameState.career_minutes = 900
	ps.notice_complication(p, c, "nurse_1", "B")
	t.eq(c.noticed_time, 500, "the clock is set by whoever got there first")
	t.eq(c.noticed_by.size(), 2, "but every witness is recorded")

	ps.notice_complication(p, c, "nurse_0", "A")
	t.eq(c.noticed_by.size(), 2, "and the same person cannot notice it twice")
	ps.queue_free()

func test_resolved_complications_cannot_be_noticed() -> void:
	var ps = load("res://scripts/systems/patient_system.gd").new()
	t.root.add_child(ps)
	var p := Patient.new("res")
	var c := Complication.new()
	c.resolved = true
	p.complications.append(c)
	ps.notice_complication(p, c, "nurse_0", "A")
	t.eq(c.noticed_time, -1, "something already dealt with is not a discovery")
	ps.queue_free()

## Imaging is the only entry in the record the player does not write, so it has
## to actually say what the simulation knows rather than what the chart claims.
func test_imaging_writes_the_true_cause_into_the_record() -> void:
	var p := Patient.new("img1")
	p.condition_id = "beige_lung"
	var c := Complication.new()
	c.id = "ferrous_aura"
	c.display_name = "Ferrous Aura"
	c.true_cause = "machine_deviation"
	c.plausible_causes = PackedStringArray(["underlying", "idiopathic"])
	p.add_complication(c)
	# Filed as something plausible: clean, until somebody points a scanner at it.
	c.documented_cause = "idiopathic"
	c.documented_at = 10
	t.eq(p.chart.audit(p.actual_treatments, p.complications).size(), 0,
		"a plausibly filed complication passes an audit")

	p.chart.imaging_findings.append({
		"id": "ferrous_aura", "name": "Ferrous Aura",
		"cause": "machine_deviation", "day": 4,
	})
	var findings := p.chart.audit(p.actual_treatments, p.complications)
	t.eq(findings.size(), 1, "and stops passing the moment imaging disagrees")
	t.eq(String(findings[0]["kind"]), "contradicts_imaging", "the finding names imaging")

## And the aperture is the counterplay: off its setting, the scan records
## nothing, which is the entire reason to run it badly on purpose.
func test_a_degraded_scan_records_nothing() -> void:
	var p := Patient.new("img2")
	p.condition_id = "beige_lung"
	var c := Complication.new()
	c.id = "ferrous_aura"
	c.display_name = "Ferrous Aura"
	c.true_cause = "machine_deviation"
	p.add_complication(c)
	p.imaging_requested_by = "doctor_0"
	p.imaging_requested_day = 1

	var ts = load("res://scripts/systems/treatment_system.gd").new()
	t.root.add_child(ts)
	ts._record_imaging(p, 3)
	t.ok(p.chart.imaging_findings.is_empty(), "an artefact scan writes no findings")
	t.ok(not p.chart.imaging_done, "and does not count as having been imaged")
	t.ok(not p.imaging_requested(), "but it does satisfy the request that was made")

	ts._record_imaging(p, 0)
	t.eq(p.chart.imaging_findings.size(), 1, "run properly, it records what is there")
	t.ok(p.chart.imaging_done, "and counts")
	ts.queue_free()

## Being bad at your job is its own failure state. This path needs nobody to
## suspect anything: a patient who has been kept too long, or left on a trolley,
## eventually complains about their care, and a complaint is heat.
func test_an_unhappy_patient_complains_without_suspecting_anything() -> void:
	var sus := SuspicionSystem.new()
	t.root.add_child(sus)
	var ps = load("res://scripts/systems/patient_system.gd").new()
	t.root.add_child(ps)

	var p := Patient.new("unhappy1")
	p.display_name = "Mrs Fed Up"
	p.mind = DB.make_mind("unhappy1", "Mrs Fed Up", "patient", "confrontational")
	sus.register(p.mind)
	p.satisfaction = 0.5

	var before: int = GameState.stats.complaints
	ps._maybe_complain(p)
	t.eq(GameState.stats.complaints, before, "a middling stay is not a complaint")

	p.satisfaction = 0.05
	ps._maybe_complain(p)
	t.eq(GameState.stats.complaints, before + 1, "a miserable one is")
	t.ok(p.complained, "and it is recorded on the patient")

	# One person files one complaint. Being hated twice by the same patient is
	# not twice the problem.
	ps._maybe_complain(p)
	t.eq(GameState.stats.complaints, before + 1, "they do not file it twice")

	ps.queue_free()
	sus.queue_free()

## The tutorial teaches the legitimate job and nothing else, which is the whole
## trick: you are told what a good doctor does, handed a debt schedule a good
## doctor cannot service, and left to draw your own conclusions.
func test_the_tutorial_never_mentions_the_other_thing() -> void:
	var banned := ["suspicion", "witness", "caught", "cover", "hurt", "injure",
		"money", "earn", "profit", "fraud"]
	for step in TutorialSystem.STEPS:
		var text := String(step["text"]).to_lower()
		for word in banned:
			t.ok(not text.contains(word),
				"tutorial step '%s' says nothing about %s" % [step["id"], word])

## And it covers the verbs a first shift actually consists of, including the two
## that arrived with the shift loop. A tutorial that stops at "read a chart"
## leaves a new player with a booked list they have no idea they have.
func test_the_tutorial_covers_the_shift_loop() -> void:
	var ids: Array = []
	for step in TutorialSystem.STEPS:
		ids.append(String(step["id"]))
	for required in ["list", "chart", "examine", "treat", "records", "shift"]:
		t.ok(ids.has(required), "the first shift teaches '%s'" % required)
	t.lt(float(ids.find("list")), float(ids.find("examine")),
		"you are shown the list before you are sent to see anybody")
	t.eq(ids[ids.size() - 1], "shift", "and clocking out is the last thing")

## You have to be able to walk down your own corridor.
##
## The shove impulse used to be scaled by post-slide velocity, and
## move_and_slide zeroes velocity along the axis you are blocked on — so the
## instant a prop actually stopped you, you could no longer push it. A play run
## spent sixty seconds wedged on a wet floor sign in the middle of the corridor
## and could only get past by sprinting, because sprinting left enough residual
## speed to generate an impulse. Walking pace could not.
func test_a_blocked_walker_can_still_shove_what_is_blocking_them() -> void:
	var light: float = Items.SPECS["wet_floor_sign"]["mass"]
	# The state that used to be fatal: pinned against something, velocity zero,
	# still asking to walk forward.
	t.gt(Player.shove_impulse(light, Player.WALK_SPEED), 0.5,
		"somebody walking into a light prop shifts it")
	t.gt(Player.shove_impulse(light, Player.CROUCH_SPEED), 0.2,
		"and even creeping shifts it eventually")
	# Heavier things give way more slowly, so a cart in a doorway still costs
	# you something. The comparison has to be on the SPEED CHANGE, not on the
	# impulse: an impulse that did not grow with mass was the original bug —
	# it put 1.9 N·s into a twenty-kilo wheelchair, a tenth of a metre per
	# second, and a play run lost twenty-one seconds to a chair in a doorway.
	var cart := 26.0
	var v_light := Player.shove_impulse(light, Player.WALK_SPEED) / light
	var v_cart := Player.shove_impulse(cart, Player.WALK_SPEED) / cart
	t.lt(v_cart, v_light, "a loaded cart gives way slower than a plastic sign")
	t.gt(v_cart, 0.2, "but it does move, and visibly")
	# ...and nothing you shove ever ends up going faster than you are.
	t.lt(Player.shove_impulse(light, Player.WALK_SPEED) / light,
		Player.WALK_SPEED + 0.001,
		"and nothing you nudge outruns you")
	t.eq(Player.shove_impulse(light, 0.0), 0.0,
		"and standing still shoves nothing")
