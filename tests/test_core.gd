extends RefCounted
var t

func test_db_lookups() -> void:
	t.eq(DB.condition_name("funny_bone"), "Inflamed Funny Bone", "condition name lookup")
	t.eq(DB.treatment_name("chalkinol"), "Chalkinol", "treatment name lookup")
	t.eq(DB.cause_name("idiopathic"), "idiopathic (no identified cause)", "cause name lookup")
	t.ok(DB.is_correct_treatment("funny_bone", "percussive_realign"), "correct treatment recognised")
	t.ok(not DB.is_correct_treatment("funny_bone", "colour_therapy"), "wrong treatment rejected")
	t.near(DB.insurance_multiplier("excellent"), 2.4, 0.001, "insurance multiplier")

func test_traits_fallback() -> void:
	t.near(DB.trait_of("paranoid", "observance"), 0.75, 0.001, "declared trait")
	t.near(DB.trait_of("paranoid", "visit_rate"), 0.5, 0.001, "undeclared trait falls back")
	t.near(DB.trait_of("nonexistent_arch", "skepticism"), 0.5, 0.001, "unknown archetype falls back")

func test_patient_stay_math() -> void:
	var p := Patient.new("p1")
	p.expected_stay_days = 2.0
	p.admitted_on_day = 3
	t.near(p.total_stay_days(), 2.0, 0.001, "base stay")
	var c := Complication.new()
	c.days_added = 1.5
	p.complications.append(c)
	t.near(p.total_stay_days(), 3.5, 0.001, "complication extends stay")
	t.eq(p.projected_discharge_day(), 7, "projected discharge day")
	c.resolved = true
	t.near(p.total_stay_days(), 2.0, 0.001, "resolved complication stops counting")

func test_patient_revenue() -> void:
	var p := Patient.new("p2")
	p.base_daily_revenue = 1000
	p.insurance = "standard"
	t.eq(p.daily_revenue(), 1000, "base revenue")
	p.insurance = "excellent"
	t.eq(p.daily_revenue(), 2400, "insurance multiplier applied")
	var c := Complication.new()
	p.complications.append(c)
	t.eq(p.daily_revenue(), int(round(1000 * 2.4 * 1.26)), "complication is billable")

func test_acuity_escalation() -> void:
	# A long complicated stay gets recoded as complex and bills more per day.
	# This, plus the admission cost, is what makes duration beat turnover.
	var p := Patient.new("acuity")
	p.base_daily_revenue = 1000
	p.insurance = "standard"
	p.expected_stay_days = 2.0
	var flat := p.daily_revenue()
	p.complications.append(Complication.new())
	var with_comp := p.daily_revenue()
	t.gt(float(with_comp), float(flat), "a complication raises the daily rate")
	p.days_admitted = 8.0
	t.gt(float(p.daily_revenue()), float(with_comp), "and a long complex stay raises it further")
	p.days_admitted = 40.0
	t.lt(float(p.daily_revenue()), float(with_comp) * 1.5, "but the escalation is capped")

func test_no_acuity_escalation_without_complications() -> void:
	# Simply sitting on a healthy patient must NOT pay more — the extra money
	# has to come from a documented complication, not from stalling.
	var p := Patient.new("stall")
	p.base_daily_revenue = 1000
	p.expected_stay_days = 2.0
	var base := p.daily_revenue()
	p.days_admitted = 12.0
	t.eq(p.daily_revenue(), base, "an uncomplicated overstay bills the flat rate")

## The curve that keeps reckless play from being the best-paid play.
##
## A flat, uncapped bonus per complication meant fifteen of them on one person
## billed nearly five times base, and a balance run measured the result: careless
## butchery earned $8,379 a day against careful practice's $2,778. Nobody pays
## five times the daily rate for one man who keeps falling over — they ask why
## he keeps falling over.
func test_stacked_complications_pay_less_and_less() -> void:
	var p := Patient.new("stack")
	p.base_daily_revenue = 1000
	p.insurance = "standard"
	p.expected_stay_days = 99.0      # keep acuity escalation out of it
	var last := p.daily_revenue()
	var first_step := 0
	var steps: Array[int] = []
	for i in 8:
		p.complications.append(Complication.new())
		var now := p.daily_revenue()
		steps.append(now - last)
		last = now
	first_step = steps[0]
	t.gt(float(first_step), 200.0, "the first complication is worth real money")
	for i in range(1, steps.size()):
		t.ok(steps[i] <= steps[i - 1],
			"complication %d pays no more than the one before it" % (i + 1))
	t.lt(float(steps[steps.size() - 1]), float(first_step) * 0.25,
		"and by the eighth it is nearly nothing")
	t.lt(float(p.daily_revenue()), 1000.0 * (1.0 + Patient.COMPLICATION_CEILING) + 1.0,
		"the whole stack is capped")

## What an insurer can see is the CHART, not the truth. Days a documented
## complication accounts for are days nobody has a question about; days nothing
## accounts for are the entire signal the statistical review reads.
##
## Measuring every extra day against the original projection punished the exact
## behaviour the game is built to reward — causing a complication and filing it
## correctly made your length-of-stay figures worse — and made "touch nobody,
## file nothing, just wait" the most profitable strategy in the game.
func test_overstay_is_measured_against_the_record() -> void:
	var p := Patient.new("los")
	p.expected_stay_days = 3.0
	p.days_admitted = 7.0
	t.near(p.unexplained_overstay(), 4.0, 0.001, "four days nothing explains")

	var c := Complication.new()
	c.days_added = 3.0
	p.complications.append(c)
	t.near(p.unexplained_overstay(), 4.0, 0.001,
		"an UNDOCUMENTED complication explains nothing — that is the risk of not filing")

	c.documented_cause = "examination"
	t.near(p.unexplained_overstay(), 1.0, 0.001,
		"filed, it accounts for the days it added")

	c.resolved = true
	t.near(p.unexplained_overstay(), 4.0, 0.001,
		"and stops accounting for them once it is resolved")

func test_recovery_suppression() -> void:
	var a := Patient.new("a")
	a.recovery_rate = 0.5
	a.tick(1.0)
	t.near(a.recovery, 0.5, 0.001, "clean recovery for one day")

	var b := Patient.new("b")
	b.recovery_rate = 0.5
	var c := Complication.new()
	c.severity = 0.5
	b.complications.append(c)
	b.tick(1.0)
	t.lt(b.recovery, 0.5, "complication suppresses recovery rate")
	t.gt(b.recovery, 0.0, "but does not stop it entirely")

func test_chart_audit_phantom_billing() -> void:
	var chart := PatientChart.new()
	chart.log_treatment("chalkinol", 100, false)
	chart.log_treatment("rest", 120, true)
	var actual: Array[Dictionary] = [{"id": "rest", "time": 120, "quality": 1.0}]
	var findings := chart.audit(actual, [])
	var kinds: Array = []
	for f in findings:
		kinds.append(f["kind"])
	t.ok(kinds.has("phantom_billing"), "phantom billing detected")
	t.ok(not kinds.has("undocumented_treatment"), "matched treatment not flagged")

func test_chart_audit_impossible_cause() -> void:
	var chart := PatientChart.new()
	var comp := Complication.new()
	comp.display_name = "Ferrous Aura"
	comp.plausible_causes = PackedStringArray(["equipment_variance", "idiopathic"])
	comp.documented_cause = "dietary"
	var findings := chart.audit([], [comp])
	t.eq(findings.size(), 1, "one finding for impossible cause")
	t.eq(findings[0]["kind"], "impossible_cause", "flagged as impossible cause")

func test_complication_clean_kill() -> void:
	var c := Complication.new()
	c.plausible_causes = PackedStringArray(["underlying", "idiopathic"])
	c.severity = 0.5
	t.near(c.paper_suspicion(), 0.5, 0.001, "undocumented complication is suspicious")
	c.documented_cause = "idiopathic"
	c.documented_at = 100
	c.noticed_time = -1
	t.ok(c.is_clean(), "documented before anyone noticed = clean")
	t.near(c.paper_suspicion(), 0.0, 0.001, "clean complication costs nothing")
	c.noticed_time = 50
	t.ok(not c.is_clean(), "documenting after it was noticed is not clean")

func test_serialization_roundtrip() -> void:
	var p := Patient.new("rt")
	p.display_name = "Greg Pumbleton"
	p.condition_id = "funny_bone"
	p.recovery = 0.42
	p.insurance = "good"
	var c := Complication.new()
	c.id = "ambient_dread"
	c.display_name = "Ambient Dread"
	c.documented_cause = "weather"
	p.complications.append(c)
	p.chart.log_treatment("chalkinol", 5, true)
	p.mind = DB.make_mind("rt", "Greg", "patient", "paranoid")

	var back := Patient.from_dict(p.to_dict())
	t.eq(back.display_name, "Greg Pumbleton", "name survives roundtrip")
	t.near(back.recovery, 0.42, 0.0001, "recovery survives roundtrip")
	t.eq(back.complications.size(), 1, "complications survive roundtrip")
	t.eq(back.complications[0].documented_cause, "weather", "documented cause survives")
	t.eq(back.chart.logged_treatments.size(), 1, "chart survives roundtrip")
	t.eq(back.mind.archetype, "paranoid", "mind survives roundtrip")

func test_every_condition_has_reachable_treatments() -> void:
	# A condition whose indicated treatments need a tool that does not exist is
	# unwinnable and would only show up as a patient who never gets better.
	for cid in DB.CONDITIONS:
		var treats: Array = DB.correct_treatments(String(cid))
		t.gt(float(treats.size()), 0.0, "%s has indicated treatments" % cid)
		for tid in treats:
			var spec: Dictionary = DB.treatment(String(tid))
			t.ok(not spec.is_empty(), "%s references a real treatment (%s)" % [cid, tid])
			var tool := String(spec.get("tool", ""))
			if tool == "":
				continue
			# The blanket "machine_" skip is why sixteen conditions shipped with
			# a correct treatment that could not be performed in the building.
			# It was written when every machine existed; three of them were
			# later removed and nothing here noticed. A device is now checked
			# against the devices that get installed.
			if tool.begins_with("machine_"):
				t.ok(TreatmentMachine.INSTALLED.has(tool),
					"treatment %s for %s needs device '%s', which must actually be in the hospital" % [
						tid, cid, tool])
				continue
			t.ok(Items.SPECS.has(tool),
				"treatment %s needs tool '%s', which must be a real item" % [tid, tool])

func test_every_complication_has_at_least_one_plausible_cause() -> void:
	for cid in DB.COMPLICATIONS:
		var causes: Array = Array(DB.COMPLICATIONS[cid].get("causes", []))
		t.gt(float(causes.size()), 0.0, "%s can be attributed to something" % cid)
		for c in causes:
			t.ok(DB.CAUSES.has(String(c)), "%s uses a real cause tag (%s)" % [cid, c])

func test_every_machine_treatment_is_indicated_somewhere() -> void:
	# A machine whose treatment is correct for no condition is a trap with no
	# legitimate use, which is not the same as a tempting one.
	for tid in DB.TREATMENTS:
		var tool := String(DB.treatment(String(tid)).get("tool", ""))
		if not tool.begins_with("machine_"):
			continue
		var indicated := false
		for cid in DB.CONDITIONS:
			if DB.is_correct_treatment(String(cid), String(tid)):
				indicated = true
		t.ok(indicated, "machine treatment %s is indicated for some condition" % tid)

func test_every_ending_is_reachable() -> void:
	# An ending nothing can produce is dead content. Drive each one's conditions
	# and confirm the evaluator actually selects it.
	var cases := {
		"prison": func(): GameState.sanction_level = 9,
		"license_revoked": func(): GameState.sanction_level = 8,
		"whistleblower": func(): GameState.set_flag("whistleblew", true),
		"bankrupt": func(): GameState.personal_money = -5000,
		"legendary": func():
			GameState.stats.forged_entries = 14
			GameState.adjust_rep("doctor", 0.4)
			GameState.heat = 0.05,
		"medical_mafia": func(): GameState.set_flag("corrupt_staff_count", 4),
		"fraud_king": func():
			GameState.stats.forged_entries = 25
			GameState.stats.personal_earned = 40000,
		"tycoon": func(): GameState.stats.personal_earned = 30000,
		"saint": func():
			GameState.stats.patients_cured = 20
			GameState.stats.complications_caused = 0
			GameState.adjust_rep("patient_sat", 0.3),
		"butcher": func(): GameState.stats.injuries_caused = 18,
		"recognised_risk": func(): GameState.stats.surgeries_botched = 7,
		"revolving_door": func(): GameState.stats.readmissions = 10,
	}
	for id in cases:
		GameState.start_new_career(1)
		(cases[id] as Callable).call()
		t.eq(Endings.evaluate(GameState.stats), id, "ending '%s' is reachable" % id)
	# And nothing can be added to the catalogue without one, which is how the
	# three endings written for the injury loop nearly shipped unreachable.
	for id in Endings.ENDINGS:
		t.ok(cases.has(String(id)),
			"ending '%s' has a case proving something produces it" % id)
	GameState.start_new_career(1)

func test_headline_generator_never_returns_empty() -> void:
	for i in 20:
		GameState.stats.longest_stay_name = "Greg Pumbleton" if i % 2 == 0 else ""
		GameState.stats.longest_stay = float(i)
		t.ok(Endings.headline(GameState.stats).length() > 8, "headline %d is real text" % i)

# ==================================================================== departments
func test_department_conditions_are_gated_until_unlocked() -> void:
	GameState.start_new_career(41)
	t.eq(GameState.unlocked_departments, ["ward"] as Array, "only the ward to begin with")
	for cid in DB.CONDITIONS:
		var dept := String(DB.CONDITIONS[cid].get("dept", "ward"))
		if dept == "ward":
			continue
		t.ok(not GameState.unlocked_departments.has(dept),
			"%s condition '%s' is locked at career start" % [dept, cid])
	# Departments are late-game purchases; fund the hospital rather than
	# assuming they are affordable on day one.
	t.ok(not Upgrades.can_afford("dept_emergency"),
		"a department is well out of reach at career start")
	GameState.add_hospital(Upgrades.cost("dept_emergency"), "test")
	t.ok(Upgrades.purchase("dept_emergency"), "and affordable once the ward is profitable")
	t.ok(GameState.unlocked_departments.has("emergency"),
		"buying the department unlocks its condition pool")

func test_imaging_makes_vitals_exact() -> void:
	# The one thing in the game that tells you the truth, and the one thing that
	# writes that truth into the record.
	GameState.start_new_career(42)
	var p := Patient.new("img")
	p.condition_id = "opaque_torso"
	p.recovery = 0.5
	var noisy_spread := 0.0
	for i in 6:
		GameState.career_minutes = i * 40
		var v: Dictionary = p.vitals()
		noisy_spread += absf(float(v["humour_balance"]) - (28.0 + 0.5 * 62.0))
	p.imaged_at = GameState.career_minutes
	var exact: Dictionary = p.vitals()
	t.near(float(exact["humour_balance"]), 28.0 + 0.5 * 62.0, 0.001,
		"imaged vitals report the truth exactly")
	t.gt(noisy_spread, 0.5, "and un-imaged vitals genuinely are noisy")

func test_imaging_makes_later_lies_contradictory() -> void:
	var chart := PatientChart.new()
	chart.imaging_done = true
	chart.imaging_clear = true
	chart.imaging_day = 3
	var comp := Complication.new()
	comp.display_name = "Ambient Dread"
	comp.plausible_causes = PackedStringArray(["underlying", "idiopathic"])
	comp.documented_cause = "underlying"
	comp.documented_at = 500
	var kinds: Array = []
	for f in chart.audit([], [comp]):
		kinds.append(String(f["kind"]))
	t.ok(kinds.has("contradicts_imaging"),
		"blaming an underlying cause after imaging ruled one out is a finding")

	# The same claim without imaging on file is perfectly plausible.
	var clean := PatientChart.new()
	var kinds2: Array = []
	for f in clean.audit([], [comp]):
		kinds2.append(String(f["kind"]))
	t.ok(not kinds2.has("contradicts_imaging"), "and is unremarkable without it")

func test_psychiatric_recovery_tracks_satisfaction() -> void:
	# These patients recover on how they are treated, not on equipment — which
	# makes a cold, dark, miserable ward the most effective way to hold one.
	var happy := Patient.new("h")
	happy.condition_id = "recursive_worry"
	happy.recovery_rate = 0.5
	happy.satisfaction = 0.95
	happy.tick(1.0)

	var miserable := Patient.new("m")
	miserable.condition_id = "recursive_worry"
	miserable.recovery_rate = 0.5
	miserable.satisfaction = 0.1
	miserable.tick(1.0)
	t.gt(happy.recovery, miserable.recovery * 1.5,
		"a contented psychiatric patient recovers far faster than a miserable one")

	# A ward patient is unaffected by satisfaction.
	var a := Patient.new("a")
	a.condition_id = "funny_bone"
	a.recovery_rate = 0.5
	a.satisfaction = 0.95
	a.tick(1.0)
	var b := Patient.new("b")
	b.condition_id = "funny_bone"
	b.recovery_rate = 0.5
	b.satisfaction = 0.1
	b.tick(1.0)
	t.near(a.recovery, b.recovery, 0.0001, "ward conditions do not care how you feel")

func test_emergency_conditions_are_short_and_lucrative() -> void:
	for cid in DB.CONDITIONS:
		var c: Dictionary = DB.CONDITIONS[cid]
		if String(c.get("dept", "ward")) != "emergency":
			continue
		t.lt(float(c["base_days"]), 2.0, "%s is a short stay" % cid)
		t.gt(float(c["revenue"]), 2000.0, "%s bills heavily per day" % cid)

func test_clinical_impression_is_relative_to_expected_progress() -> void:
	# Absolute bands made every freshly-admitted patient read "not great", which
	# is true and useless. The question that matters — to a doctor and to a
	# player checking whether their interference worked — is "on track?".
	var fresh := Patient.new("f")
	fresh.expected_stay_days = 4.0
	fresh.days_admitted = 0.1
	fresh.recovery = 0.0
	t.eq(fresh.apparent_state(), "just admitted", "day one is not a diagnosis")

	var on_track := Patient.new("t")
	on_track.expected_stay_days = 4.0
	on_track.days_admitted = 2.0
	on_track.recovery = 0.5
	t.eq(on_track.apparent_state(), "coming along as expected", "halfway through, halfway better")

	var stalled := Patient.new("s")
	stalled.expected_stay_days = 4.0
	stalled.days_admitted = 2.0
	stalled.recovery = 0.1
	t.eq(stalled.apparent_state(), "not coming along at all", "a stalled patient reads as stalled")

	var quick := Patient.new("q")
	quick.expected_stay_days = 4.0
	quick.days_admitted = 1.0
	quick.recovery = 0.8
	t.eq(quick.apparent_state(), "ahead of schedule", "and a fast one reads as fast")

	var done := Patient.new("d")
	done.days_admitted = 3.0
	done.recovery = 1.0
	t.eq(done.apparent_state(), "ready to go home", "recovered beats everything else")

	var worse := Patient.new("w")
	worse.days_admitted = 3.0
	worse.recovery = -0.1
	t.eq(worse.apparent_state(), "worse than on arrival", "and going backwards is unmistakable")

# ==================================================================== audio
func test_every_sound_synthesises_to_real_audio() -> void:
	# All audio is generated at runtime, so a bad recipe produces silence rather
	# than a missing-file error — which is much harder to notice.
	for name in AudioMgr.RECIPES:
		var st: AudioStreamWAV = AudioMgr._build(String(name))
		t.ok(st != null, "%s builds a stream" % name)
		t.gt(float(st.data.size()), 100.0, "%s has samples" % name)
		var peak := 0
		for i in range(0, st.data.size(), 2):
			var v: int = st.data[i] | (st.data[i + 1] << 8)
			if v > 32767:
				v -= 65536
			peak = maxi(peak, absi(v))
		t.gt(float(peak), 1000.0, "%s is audible rather than silence" % name)

func test_room_tone_loops_seamlessly() -> void:
	# The hum has to loop without a click. That needs whole cycles inside the
	# buffer, not a cross-fade.
	var hum: AudioStreamWAV = AudioMgr._build_hum()
	t.eq(hum.loop_mode, AudioStreamWAV.LOOP_FORWARD, "the bed is loop-enabled")
	t.eq(hum.loop_begin, 0, "loops from the start")
	t.eq(hum.loop_end, int(AudioMgr.HUM_SECONDS * AudioMgr.SR), "to the very end")
	# Whole cycles in the buffer means the ends line up.
	for freq in [50.0, 74.0]:
		var cycles: float = freq * AudioMgr.HUM_SECONDS
		t.near(cycles - floor(cycles), 0.0, 0.0001,
			"%.0fHz fits a whole number of cycles in the loop" % freq)

func test_recovered_dread_goes_back_in() -> void:
	# The extractor has to put what it took SOMEWHERE, and nothing stops you
	# carrying that somewhere back to a patient.
	t.eq(Items.substance_effect("ambient_dread"), "",
		"recovered dread treats precisely nothing")
	t.eq(Items.substance_complication("ambient_dread"), "ambient_dread",
		"but reliably causes what it was extracted from")
	t.eq(Items.substance_complication("saline_plus"), "",
		"whereas Saline Plus really is inert")
	t.eq(Items.substance_complication("mop_water"), "reactive_shivers",
		"and mop water is its own kind of specific")

func test_every_substance_complication_is_real() -> void:
	for id in Items.SUBSTANCES:
		var comp := Items.substance_complication(String(id))
		if comp == "":
			continue
		t.ok(DB.COMPLICATIONS.has(comp),
			"substance '%s' causes a real complication ('%s')" % [id, comp])

func test_every_substance_effect_is_a_real_treatment() -> void:
	for id in Items.SUBSTANCES:
		var eff := Items.substance_effect(String(id))
		if eff == "":
			continue
		t.ok(DB.TREATMENTS.has(eff),
			"substance '%s' maps to a real treatment ('%s')" % [id, eff])

## A complication nothing can produce is not content, it is a dictionary entry.
## Every source that can create one is data rather than a match statement
## specifically so this test can add them up.
func test_no_complication_is_unreachable() -> void:
	var reachable := {}
	for k in TreatmentMachine.COMPLICATION_POOLS:
		for id in TreatmentMachine.COMPLICATION_POOLS[k]:
			reachable[String(id)] = true
	for k in TreatmentSystem.WRONG_TREATMENT_COMPLICATIONS:
		reachable[String(TreatmentSystem.WRONG_TREATMENT_COMPLICATIONS[k])] = true
	for k in PatientSystem.ENVIRONMENTAL_COMPLICATIONS:
		reachable[String(PatientSystem.ENVIRONMENTAL_COMPLICATIONS[k])] = true
	for k in TreatmentSystem.EXAM_PARTS:
		reachable[String(TreatmentSystem.EXAM_PARTS[k])] = true
	for k in Items.SUBSTANCES:
		var c := Items.substance_complication(String(k))
		if c != "":
			reachable[c] = true
	# Hand-procedures produce their own. Walked rather than listed, so adding a
	# band to a procedure cannot quietly point at a complication that is not in
	# the catalogue — which is exactly how wound_dehiscence got caught.
	# A fight is not a procedure and does not live in that table, but it leaves
	# somebody with something they did not arrive with, so it is a source.
	for k in Brawl.OUTCOMES:
		var bh := String(Brawl.OUTCOMES[k].get("harm", ""))
		if bh != "":
			reachable[bh] = true
	for kind in Procedures.OUTCOMES:
		for intent in Procedures.OUTCOMES[kind]:
			for band in Procedures.OUTCOMES[kind][intent]:
				var harm := String(Procedures.OUTCOMES[kind][intent][band].get("harm", ""))
				if harm != "":
					reachable[harm] = true

	for cid in DB.COMPLICATIONS:
		t.ok(reachable.has(String(cid)),
			"something in the game can actually cause %s" % cid)
	# And nothing points at a complication that does not exist.
	for cid in reachable:
		t.ok(DB.COMPLICATIONS.has(String(cid)),
			"%s is referenced as a complication and is one" % cid)
