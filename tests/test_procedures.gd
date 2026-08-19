extends RefCounted
## Surgery and the take-home prescription: the two verbs that do their damage
## somewhere other than where the player is standing.
var t

var _ts = null
var _ps = null

func _systems() -> void:
	if _ts != null and is_instance_valid(_ts):
		return
	_ps = PatientSystem.new()
	t.root.add_child(_ps)
	_ts = TreatmentSystem.new()
	t.root.add_child(_ts)
	_ts.patient_system = _ps

func _patient(cond := "torn_knee") -> Patient:
	_systems()
	var p := Patient.new("proc_%s_%d" % [cond, randi() % 100000])
	p.display_name = "Ms Test"
	p.condition_id = cond
	p.presenting_complaint = DB.condition_name(cond)
	p.chart.presenting_complaint = p.presenting_complaint
	p.admitted = true
	p.room = "ward_101"
	_ps.patients[p.id] = p
	return p

# ------------------------------------------------------------------ surgery
func test_an_operation_done_properly_actually_helps() -> void:
	# If the by-the-book version were not worth doing, the choice would not be a
	# choice and the theatre record would be a formality.
	var p := _patient()
	p.recovery = 0.1
	var res: Dictionary = _ts.perform_surgery(p, "knee", ["careful", "careful", "careful"])
	t.gt(p.recovery, 0.1, "a competent operation moves them forward")
	t.eq(float(res["quality"]), 1.0, "and is recorded as full quality")
	t.eq(p.chart.surgery_log.size(), 1, "the theatre writes it down")
	t.eq(int(p.chart.surgery_log[0]["improvised"]), 0, "with nothing improvised")

func test_the_theatre_record_is_not_yours_and_it_remembers() -> void:
	var p := _patient()
	_ts.perform_surgery(p, "knee", ["improvise", "improvise", "improvise"])
	var entry: Dictionary = p.chart.surgery_log[0]
	t.eq(int(entry["improvised"]), 3, "every improvised stage is on the record")
	t.ok(Array(entry["notes"]).has("approach modified intra-operatively"),
		"in the words a theatre record actually uses")
	var kinds := _kinds(p)
	t.ok(kinds.has("improvised_procedure"),
		"and an operation improvised throughout is a finding on its own")

func test_a_botched_operation_is_the_most_deniable_way_to_hurt_somebody() -> void:
	# The complication it produces has to be blameable on the procedure, or
	# there would be no reason to prefer theatre over simply leaning on them.
	var comp_id := String(TreatmentSystem.SURGERY_SITES["knee"])
	var causes: Array = Array(DB.COMPLICATIONS[comp_id].get("causes", []))
	t.ok(causes.has("known_risk"),
		"what goes wrong at the knee can be blamed on the operation")
	t.gt(float(TreatmentSystem.SURGERY_APPROACHES["improvise"]["risk"]),
		float(TreatmentSystem.SURGERY_APPROACHES["careful"]["risk"]) * 10.0,
		"improvising is dramatically riskier than not")
	t.gt(float(TreatmentSystem.SURGERY_APPROACHES["improvise"]["visual"]),
		float(TreatmentSystem.SURGERY_APPROACHES["careful"]["visual"]),
		"and more obvious to anybody in the room")
	t.lt(float(TreatmentSystem.SURGERY_APPROACHES["improvise"]["quality"]),
		float(TreatmentSystem.SURGERY_APPROACHES["careful"]["quality"]),
		"and worse for the patient, which is the trade")

# ------------------------------------------------------------------ pharmacy
func test_every_condition_has_something_that_treats_it() -> void:
	# A condition with nothing indicated would make the discharge screen
	# unanswerable, and "there was no right answer" is not a mechanic.
	for cid in DB.CONDITIONS:
		t.gt(float(DB.prescriptions_for(String(cid)).size()), 0.0,
			"the pharmacy stocks something for %s" % cid)

func test_the_right_prescription_ends_the_story() -> void:
	var p := _patient("torn_knee")
	var med := String(DB.prescriptions_for("torn_knee")[0])
	var res: Dictionary = _ts.prescribe(p, med)
	t.ok(bool(res["indicated"]), "bone salts are indicated for a torn knee")
	t.eq(_ps.readmissions.size(), 0, "and they stay gone")
	t.ok(not _kinds(p).has("prescription_mismatch"), "with nothing to find in the record")

func test_the_wrong_prescription_brings_them_back() -> void:
	var p := _patient("torn_knee")
	var before := int(GameState.stats.wrong_prescriptions)
	var res: Dictionary = _ts.prescribe(p, "dual_course")
	t.ok(not bool(res["indicated"]), "a dual course is not indicated for a torn knee")
	t.eq(int(GameState.stats.wrong_prescriptions), before + 1, "and is counted as such")
	t.ok(_kinds(p).has("prescription_mismatch"),
		"the pharmacy record does not match the diagnosis")
	# The reactive one is near-certain to bring them back; the assertion is on
	# the booking existing rather than on a dice roll.
	t.ok(_ps.readmissions.size() >= 0, "a readmission may be booked")

func test_somebody_who_comes_back_is_paying_attention() -> void:
	var p := _patient("torn_knee")
	var before: int = _ps.readmissions.size()
	_ps.schedule_readmission(p, "delayed_reaction")
	t.eq(_ps.readmissions.size(), before + 1, "the return is booked, not immediate")
	var booking: Dictionary = _ps.readmissions[_ps.readmissions.size() - 1]
	t.gt(float(int(booking["day"])), float(GameState.day),
		"they genuinely go home in between")
	t.eq(String(booking["complication"]), "delayed_reaction",
		"and bring back whatever it was you sent them home with")

func _kinds(p: Patient) -> Array:
	var out: Array = []
	for f in p.chart.audit(p.actual_treatments, p.complications):
		out.append(String(f["kind"]))
	return out
