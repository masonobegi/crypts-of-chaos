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
			if tool == "" or tool.begins_with("machine_"):
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
