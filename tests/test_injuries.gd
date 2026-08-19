extends RefCounted
## Injuries, and the arrival-versus-discharge gap that makes them findable.
##
## The absurd half of the catalogue (Chronic Beige, Ambient Dread) is deniable
## because nobody can say what caused it. An injury is the opposite: everybody
## can see it, everybody knows roughly how it happens, and the only question in
## the record is when.
var t

func _patient(cond := "chronic_beige") -> Patient:
	var p := Patient.new("inj_%s" % cond)
	p.display_name = "Mr Test"
	p.condition_id = cond
	p.presenting_complaint = DB.condition_name(cond)
	p.chart.presenting_complaint = p.presenting_complaint
	return p

func _acquire(p: Patient, comp_id: String, cause := "examination") -> Complication:
	var spec: Dictionary = DB.COMPLICATIONS[comp_id]
	var c := Complication.new()
	c.id = comp_id
	c.display_name = String(spec["name"])
	c.severity = float(spec["sev"])
	c.true_cause = cause
	c.is_injury = true
	c.body_part = String(spec.get("part", ""))
	c.acquired_here = true
	c.plausible_causes = PackedStringArray(Array(spec.get("causes", [])))
	p.add_complication(c)
	return c

func test_the_same_injury_exists_as_an_arrival_and_as_an_acquisition() -> void:
	# A fractured wrist has to read identically on the chart whether they walked
	# in with it or got it here. If the two were different content, "which one
	# is this" would be answerable from the name, and the whole pattern would be
	# free to spot.
	for id in DB.injury_ids():
		t.ok(DB.CONDITIONS.has(id), "%s is also something you can arrive with" % id)
		t.eq(String(DB.CONDITIONS[id]["name"]), String(DB.COMPLICATIONS[id]["name"]),
			"%s reads the same either way" % id)
		t.eq(DB.body_part(id), String(DB.COMPLICATIONS[id]["part"]),
			"%s knows what part of a person it is" % id)

func test_an_injury_can_only_be_blamed_on_things_a_chart_accepts() -> void:
	for id in DB.injury_ids():
		var causes: Array = Array(DB.COMPLICATIONS[id].get("causes", []))
		t.gt(float(causes.size()), 1.0, "%s has more than one story available" % id)
		for c in causes:
			t.ok(not DB.is_truth_only(String(c)),
				"%s cannot be filed as '%s', which is a truth the form has no box for" % [id, c])

func test_examining_gently_is_a_good_thing_to_do() -> void:
	# If the honest setting were useless the dial would be a button that only
	# exists for crime, and the player would read it that way immediately.
	t.eq(TreatmentSystem.injury_chance(TreatmentSystem.EXAM_INDICATED), 0.0,
		"an examination at the indicated pressure never hurts anybody")
	t.eq(TreatmentSystem.injury_chance(TreatmentSystem.EXAM_INDICATED + 1), 0.0,
		"and nor does a slightly firm one")
	t.lt(TreatmentSystem.exam_visibility(TreatmentSystem.EXAM_INDICATED), 0.1,
		"a normal examination is not worth looking up from your work for")

func test_leaning_on_it_is_a_curve_rather_than_a_switch() -> void:
	var last := -1.0
	for pressure in range(TreatmentSystem.EXAM_INDICATED + 2, TreatmentSystem.EXAM_DIAL_MAX + 1):
		var c := TreatmentSystem.injury_chance(pressure)
		t.gt(c, last, "pressure %d is riskier than the one below it" % pressure)
		last = c
	t.lt(TreatmentSystem.injury_chance(TreatmentSystem.EXAM_DIAL_MAX), 1.0,
		"even the top of the dial is not a certainty")
	# And it is visible in proportion, so the safe version of this is the one
	# nobody can see you doing.
	t.gt(TreatmentSystem.exam_visibility(TreatmentSystem.EXAM_DIAL_MAX),
		TreatmentSystem.exam_visibility(TreatmentSystem.EXAM_INDICATED + 2),
		"leaning harder is more obvious to anybody watching")

func test_one_unexplained_injury_is_a_finding() -> void:
	var p := _patient()
	t.eq(p.chart.audit(p.actual_treatments, p.complications).size(), 0,
		"a clean admission audits clean")
	_acquire(p, "fractured_wrist")
	var kinds := _kinds(p)
	t.ok(kinds.has("unexplained_injury"), "an injury with no mechanism is a finding")
	t.ok(not kinds.has("injury_pattern"), "one is not yet a pattern")

## The scenario the whole system exists for: in with a broken ankle, out with a
## broken ankle, a broken wrist and a concussion.
func test_arriving_with_one_thing_and_leaving_with_three_is_a_paragraph() -> void:
	var p := _patient("fractured_ankle")
	_acquire(p, "fractured_wrist")
	_acquire(p, "concussion")
	var findings := p.chart.audit(p.actual_treatments, p.complications)
	var pattern := {}
	for f in findings:
		if String(f["kind"]) == "injury_pattern":
			pattern = f
	t.ok(not pattern.is_empty(), "two acquired injuries is a pattern finding")
	t.ok(String(pattern["text"]).contains("Fractured Ankle"),
		"and it names what they actually came in with")
	t.ok(String(pattern["text"]).contains("Concussion"), "and what they did not")
	t.gt(float(pattern["weight"]), 0.8, "a pattern outweighs any single injury")

## Documenting them is supposed to work. Being a careful liar has to be better
## than being a careless one or there is no game.
func test_a_filed_mechanism_removes_the_gap_but_not_the_pattern() -> void:
	var p := _patient("fractured_ankle")
	var a := _acquire(p, "fractured_wrist")
	var b := _acquire(p, "concussion")
	for c in [a, b]:
		c.documented_cause = "fall"
		c.documented_at = 10
	var kinds := _kinds(p)
	t.ok(not kinds.has("unexplained_injury"), "a filed mechanism closes the gap")
	t.ok(kinds.has("injury_pattern"),
		"but three injuries in one admission is still three injuries in one admission")

## The one mechanism the dates themselves refuse.
func test_blaming_it_on_admission_contradicts_the_record() -> void:
	var p := _patient()
	var c := _acquire(p, "cracked_ribs")
	c.documented_cause = "pre_existing"
	c.documented_at = 10
	c.onset_time = GameState.MINUTES_PER_DAY * 3
	t.ok(_kinds(p).has("injury_predated"),
		"something that first appears on day four was not present on admission")

func _kinds(p: Patient) -> Array:
	var out: Array = []
	for f in p.chart.audit(p.actual_treatments, p.complications):
		out.append(String(f["kind"]))
	return out

## Attribution: how sure a witness is depends on how many other people could
## have done it. This is the entire reason the night shift is a trade rather
## than a free win.
func test_a_quiet_shift_is_a_short_list_of_suspects() -> void:
	var nurse := NurseNPC.new()
	t.root.add_child(nurse)
	nurse.mind = DB.make_mind("attr_nurse", "Nurse Attribution", "nurse", "gossip")
	nurse.mind.observance = 1.0

	var busy := _patient("fractured_ankle")
	for id in ["fractured_wrist", "concussion"]:
		var c := _acquire(busy, id)
		c.staff_present = DB.staff_on("day")
	nurse._note_injury_pattern(busy)
	var day_certainty := nurse.mind.evidence[0].certainty
	nurse.mind.evidence.clear()

	var quiet := _patient("fractured_ankle")
	quiet.display_name = "Mr Night"
	for id in ["fractured_wrist", "concussion"]:
		var c := _acquire(quiet, id)
		c.staff_present = DB.staff_on("night")
	nurse._note_injury_pattern(quiet)
	var night_certainty := nurse.mind.evidence[0].certainty

	t.gt(night_certainty, day_certainty,
		"an injury acquired on a shift with one nurse on it points somewhere specific")
	t.eq(nurse.mind.evidence[0].cover_tag, "",
		"and there is no cover story for arithmetic")
	nurse.queue_free()

## One is bad luck. The nurse only starts doing sums at two.
func test_a_single_injury_is_not_yet_arithmetic() -> void:
	var nurse := NurseNPC.new()
	t.root.add_child(nurse)
	nurse.mind = DB.make_mind("attr_nurse2", "Nurse Two", "nurse", "gossip")
	nurse.mind.observance = 1.0
	var p := _patient("chronic_beige")
	_acquire(p, "fractured_wrist")
	nurse._note_injury_pattern(p)
	t.eq(nurse.mind.evidence.size(), 0, "one injury is a thing that happened")
	_acquire(p, "cracked_ribs")
	nurse._note_injury_pattern(p)
	t.eq(nurse.mind.evidence.size(), 1, "two is a thing somebody is doing")
	nurse.queue_free()
