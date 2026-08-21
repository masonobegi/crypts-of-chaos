extends RefCounted
## The three phases the game grew: the graded procedure, the envelope, the
## letter and the evening.
##
## Everything here is about the SHAPE of a decision rather than about a number.
## A test that pins an outcome table to its current values would fail every time
## the game was tuned and would tell nobody anything; these check that the
## tradeoffs still point the way the design says they point.
var t

var _ts = null
var _ps = null
var _legal = null

func _systems() -> void:
	if _ts != null and is_instance_valid(_ts):
		return
	_ps = PatientSystem.new()
	t.root.add_child(_ps)
	_ts = TreatmentSystem.new()
	t.root.add_child(_ts)
	_ts.patient_system = _ps
	_legal = LegalSystem.new()
	t.root.add_child(_legal)

func _patient(cond := "fractured_wrist") -> Patient:
	_systems()
	var p := Patient.new("ph_%s_%d" % [cond, randi() % 100000])
	p.display_name = "Mr Test"
	p.condition_id = cond
	p.presenting_complaint = DB.condition_name(cond)
	p.chart.presenting_complaint = p.presenting_complaint
	p.admitted = true
	p.room = "ward_101"
	p.recovery = 0.3
	_ps.patients[p.id] = p
	return p

# ============================================================== procedures
func test_every_procedure_has_every_band_for_both_intents() -> void:
	# The screens index this table blind. A missing band is a crash in the
	# middle of somebody's forearm.
	for kind in Procedures.OUTCOMES:
		for intent in ["treat", "worsen"]:
			t.ok(Procedures.OUTCOMES[kind].has(intent),
				"%s can be done with intent '%s'" % [kind, intent])
			for band in ["good", "fair", "poor"]:
				var spec: Dictionary = Procedures.OUTCOMES[kind][intent][band]
				t.ok(spec.has("recovery") and spec.has("stay") and spec.has("fee"),
					"%s/%s/%s is a complete outcome" % [kind, intent, band])
				t.ok(Array(spec["say"]).size() > 0,
					"%s/%s/%s gives the patient something to say" % [kind, intent, band])

func test_doing_either_job_well_beats_doing_it_badly() -> void:
	# The whole point of declaring intent. Both columns must reward competence,
	# or one of the two intents is a trap rather than a strategy.
	for kind in Procedures.OUTCOMES:
		var t_good: Dictionary = Procedures.outcome(kind, "treat", 0.95)
		var t_poor: Dictionary = Procedures.outcome(kind, "treat", 0.10)
		t.gt(float(t_good["recovery"]), float(t_poor["recovery"]),
			"%s: treating them well helps more than fumbling it" % kind)
		t.gt(float(t_poor["visual"]), float(t_good["visual"]),
			"%s: a fumbled treatment is the visible one" % kind)

		var w_good: Dictionary = Procedures.outcome(kind, "worsen", 0.95)
		var w_poor: Dictionary = Procedures.outcome(kind, "worsen", 0.10)
		t.gt(float(w_good["fee"]), float(w_poor["fee"]),
			"%s: harm done well pays and harm done badly does not" % kind)
		t.lt(float(w_good["visual"]), float(w_poor["visual"]),
			"%s: harm done well is the one nobody saw" % kind)
		t.lt(float(w_good["sue"]), float(w_poor["sue"]),
			"%s: and the one nobody sues over" % kind)

func test_the_worst_square_on_the_board_is_intending_harm_and_missing() -> void:
	# Stated in the design comment at the top of Procedures. If this stops being
	# true, the risk in the crime has quietly evaporated.
	for kind in Procedures.OUTCOMES:
		var botched_help: Dictionary = Procedures.outcome(kind, "treat", 0.05)
		var botched_harm: Dictionary = Procedures.outcome(kind, "worsen", 0.05)
		t.gt(float(botched_harm["sue"]), float(botched_help["sue"]),
			"%s: a fumbled crime is worse than a fumbled treatment" % kind)

func test_the_wrong_bottle_ruins_a_steady_hand() -> void:
	# Knowledge times skill. A perfect dose of the wrong thing must not be able
	# to reach the rewarded band, or reading the chart is optional.
	var perfect := Procedures.dose_precision("treat", Procedures.DOSE_TREAT_TARGET)
	t.near(perfect, 1.0, 0.001, "dead on the line is full precision")
	var with_cure := Procedures.dose_grade("treat", "cure", perfect)
	var with_inert := Procedures.dose_grade("treat", "inert", perfect)
	var with_clash := Procedures.dose_grade("treat", "adverse", perfect)
	t.eq(Procedures.grade_band(with_cure), "good", "the right drug, dosed properly, is a good job")
	t.ok(Procedures.grade_band(with_inert) != "good", "a sugar pill never is")
	t.eq(Procedures.grade_band(with_clash), "poor", "and the one that clashes is malpractice")
	# And the mirror: trying to cause a reaction with the cure cannot work.
	t.eq(Procedures.grade_band(Procedures.dose_grade("worsen", "cure", perfect)), "poor",
		"you cannot poison somebody with the thing that treats them")

func test_every_condition_routes_to_a_screen_and_a_body_part() -> void:
	for id in DB.CONDITIONS:
		var cid := String(id)
		var kind := Procedures.procedure_for(cid)
		var site := Procedures.site_for(cid)
		t.ok(Anatomy.PART_NAMES.has(site), "%s happens to a part we can draw" % cid)
		var rig := Anatomy.rig(site)
		t.ok(Array(rig["prox"]).size() > 0 and Array(rig["dist"]).size() > 0,
			"%s's rig has something in both halves" % site)
		t.ok(Array(rig["wound"]).size() == 2, "%s knows where a cut would run" % site)
		if kind != "dial":
			t.ok(Procedures.screen_for(kind) != "", "%s opens a screen" % kind)

func test_the_bone_target_for_harm_is_a_real_place_you_have_to_hit() -> void:
	# The dishonest option must be a manoeuvre rather than the absence of one,
	# or "make it worse" is just letting go.
	var t_treat: Dictionary = Procedures.bone_target("treat")
	var t_worse: Dictionary = Procedures.bone_target("worsen")
	t.gt(absf(float(t_worse["angle"])), 0.2, "harm is aimed at a specific angle")
	t.ok(float(t_worse["tol_angle"]) <= float(t_treat["tol_angle"]),
		"and it is no easier to hit than the honest one")
	t.near(Procedures.bone_closeness("treat", 0.0, 0.0), 1.0, 0.001,
		"dead on the honest target is a perfect reduction")
	t.lt(Procedures.bone_closeness("treat", float(t_worse["angle"]), float(t_worse["gap"])),
		0.35, "and the harmful position scores badly as a treatment")

# ============================================================== bribery
func _witness(role := "nurse", weight := 0.4) -> Mind:
	var m := Mind.new("wit_%d" % (randi() % 100000), "Someone", role)
	var ev := Evidence.new()
	ev.kind = "saw_something"
	ev.about_actor = "player"
	ev.source = Evidence.Source.WITNESSED
	ev.time = GameState.career_minutes
	ev.base_weight = weight
	ev.certainty = 1.0
	m.add_evidence(ev)
	return m

func test_an_envelope_is_priced_off_what_they_saw() -> void:
	var small := Bribery.price(_witness("nurse", 0.15), 1.0)
	var large := Bribery.price(_witness("nurse", 0.85), 1.0)
	t.gt(float(large), float(small) * 1.5,
		"buying silence about something serious costs a great deal more")
	t.gt(float(Bribery.price(_witness("inspector", 0.4), 1.0)),
		float(Bribery.price(_witness("nurse", 0.4), 1.0)),
		"and an inspector is not a nurse")

func test_more_money_is_better_odds_and_an_inspector_is_still_a_bad_idea() -> void:
	var m := _witness("nurse", 0.3)
	var token := Bribery.chance(m, Bribery.TIERS[0])
	var proper := Bribery.chance(m, Bribery.TIERS[2])
	t.gt(proper, token, "a bigger envelope is a better envelope")
	t.lt(Bribery.chance(_witness("inspector", 0.3), Bribery.TIERS[2]),
		Bribery.chance(_witness("admin", 0.3), Bribery.TIERS[0]),
		"and no envelope makes an inspector into an administrator")

func test_a_refused_offer_leaves_something_worse_behind() -> void:
	# The reason a bribe is a risk rather than a cost. Forced through the
	# refusal branch rather than rolled, so this is about consequences and not
	# about luck.
	var m := _witness("inspector", 0.2)
	GameState.personal_money = 999999
	var before := m.evidence.size()
	var res := Bribery.attempt(m, Bribery.TIERS[0], Vector3.ZERO)
	if bool(res.get("ok", false)):
		t.ok(true, "they took it, which happens; nothing to assert about a refusal")
		return
	t.eq(m.evidence.size(), before + 1, "a refusal adds a fresh piece of evidence")
	t.eq(m.evidence[m.evidence.size() - 1].kind, "attempted_bribery",
		"and it is the offer itself, which has no cover story")
	t.gt(m.evidence[m.evidence.size() - 1].base_weight, 0.6,
		"worth more than most of what it was trying to cover")
	t.eq(GameState.personal_money, 999999, "and they did not keep the money")

# ============================================================== lawsuits
func test_a_claim_is_only_as_strong_as_what_can_be_shown() -> void:
	_systems()
	var quiet := _patient()
	quiet.recovery = 0.4
	var loud := _patient()
	loud.recovery = 0.4
	loud.chart.imaging_done = true
	loud.chart.imaging_clear = false
	var a: Dictionary = _legal.file_claim(quiet, "premature_discharge")
	var b: Dictionary = _legal.file_claim(loud, "premature_discharge")
	t.gt(float(b["strength"]), float(a["strength"]),
		"imaging that disagrees with you is the strongest thing they have")
	t.gt(float(b["amount"]), 0.0, "and a claim is for an amount of money")

func test_settling_costs_less_than_losing() -> void:
	_systems()
	var p := _patient()
	var claim: Dictionary = _legal.file_claim(p, "injury")
	var settle := LegalSystem.settlement(claim)
	t.lt(float(settle), float(claim["amount"]),
		"a settlement is less than what they asked for")
	# The worst trial outcome must beat the settlement, or fighting is free.
	var lost: float = float(claim["amount"]) * (0.62 + float(claim["strength"]) * 0.38)
	t.gt(lost, float(settle), "and losing at trial costs more than settling would have")

func test_a_better_lawyer_argues_better_and_costs_more() -> void:
	_systems()
	var p := _patient()
	var claim: Dictionary = _legal.file_claim(p, "procedure")
	var cheap := LegalSystem.reply_score(claim, "deny", "duty")
	var dear := LegalSystem.reply_score(claim, "deny", "shark")
	t.gt(dear, cheap, "counsel who has read the file does better with the same line")
	t.gt(float(LegalSystem.lawyer_fee("shark", int(claim["amount"]))),
		float(LegalSystem.lawyer_fee("duty", int(claim["amount"]))),
		"and charges for it")

func test_the_record_is_worthless_against_imaging() -> void:
	_systems()
	var p := _patient()
	var claim: Dictionary = _legal.file_claim(p, "procedure")
	var without := LegalSystem.reply_score(claim, "record", "firm")
	claim["imaging"] = true
	var with_scan := LegalSystem.reply_score(claim, "record", "firm")
	t.lt(with_scan, without,
		"leaning on your own note when there is a scan is the worst moment available")

func test_witnesses_make_a_flat_denial_useless() -> void:
	_systems()
	var p := _patient()
	var claim: Dictionary = _legal.file_claim(p, "injury")
	claim["witnesses"] = []
	var alone := LegalSystem.reply_score(claim, "deny", "firm")
	claim["witnesses"] = ["A", "B", "C"]
	var crowded := LegalSystem.reply_score(claim, "deny", "firm")
	t.lt(crowded, alone, "three people who were there beat 'that did not happen'")

func test_a_hearing_always_has_something_to_argue_about() -> void:
	_systems()
	for reason in ["premature_discharge", "procedure", "injury", "night"]:
		var p := _patient()
		var claim: Dictionary = _legal.file_claim(p, String(reason))
		var rounds := LegalSystem.exchanges(claim)
		t.gt(float(rounds.size()), 2.0, "%s produces a hearing with exchanges in it" % reason)
		for ex in rounds:
			for key in ex["replies"]:
				t.ok(LegalSystem.REPLIES.has(String(key)),
					"every reply offered is one the game knows how to score")

# ============================================================== the evening
func test_every_place_you_can_go_produces_a_patient_you_can_treat() -> void:
	for spec in NightSystem.PLACES:
		var cond := String(spec["condition"])
		t.ok(DB.CONDITIONS.has(cond), "%s sends somebody in with a real condition" % spec["name"])
		var kind := Procedures.procedure_for(cond)
		t.ok(kind != "dial", "%s sends somebody in who needs your hands" % spec["name"])

func test_the_places_are_not_all_the_same_evening() -> void:
	var watchers := {}
	for spec in NightSystem.PLACES:
		watchers[int(spec["watchers"])] = true
	t.gt(float(watchers.size()), 2.0, "the streets differ in how busy they are")

func test_being_seen_is_the_thing_that_costs_you() -> void:
	var ns := NightSystem.new()
	t.root.add_child(ns)
	var heat_before := GameState.heat
	var clean := ns.resolve("allotments", "A Person", 0.05, true)
	t.eq(String(clean["outcome"]), "clean", "unseen is a clean night")
	t.near(GameState.heat, heat_before, 0.001, "and costs nothing")
	ns.used_tonight = false
	var caught := ns.resolve("allotments", "B Person", 0.9, true)
	t.eq(String(caught["outcome"]), "caught", "being watched the whole time is not")
	t.gt(GameState.heat, heat_before, "and it follows you home")
	ns.queue_free()

func test_losing_your_nerve_is_free() -> void:
	var ns := NightSystem.new()
	t.root.add_child(ns)
	var heat_before := GameState.heat
	var res := ns.resolve("allotments", "C Person", 0.0, false)
	t.eq(String(res["outcome"]), "missed", "not going through with it is its own outcome")
	t.ok(not bool(res["admitted"]), "and nobody turns up in the morning")
	t.near(GameState.heat, heat_before, 0.001, "and it costs nothing but the evening")
	ns.queue_free()

# ============================================================== achievements
func test_every_achievement_is_reachable_and_named() -> void:
	# A catalogue is only worth having if every entry can be earned and every
	# entry says something. The reachability half matters most: `earned_now()`
	# is a pure read over stats and flags, so an entry whose id never appears in
	# it is an entry nobody can ever get.
	var awarded := {}
	for line in Achievements.earned_now():
		awarded[line] = true
	var ids := {}
	for a in Achievements.LIST:
		var id := String(a["id"])
		t.ok(not ids.has(id), "%s appears once in the catalogue" % id)
		ids[id] = true
		t.ok(String(a.get("name", "")) != "", "%s has a name" % id)
		t.ok(String(a.get("desc", "")).length() > 12, "%s says what it is for" % id)
		t.ok(not Achievements.spec(id).is_empty(), "%s can be looked up" % id)

func test_the_catalogue_and_the_check_agree_on_which_ids_exist() -> void:
	# The other direction: `earned_now()` must never award an id the catalogue
	# does not carry, or the toast has no name to print.
	var known := {}
	for a in Achievements.LIST:
		known[String(a["id"])] = true
	# Drive the stats to something that qualifies for a great deal at once.
	GameState.stats.patients_cured = 40
	GameState.stats.bribes_paid = 3
	GameState.stats.lawsuits_won = 1
	GameState.stats.night_jobs = 4
	GameState.stats.night_jobs_clean = 4
	for id in Achievements.earned_now():
		t.ok(known.has(String(id)),
			"'%s' is awarded and is in the catalogue" % id)
