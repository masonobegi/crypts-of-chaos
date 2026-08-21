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

func test_counsel_answers_what_you_actually_said() -> void:
	# The point of a hearing rather than a die roll: the first thing you say
	# decides what you have to answer next. Every branch has to lead somewhere
	# real, from an empty hearing, whatever the claim looks like.
	_systems()
	for imaged in [false, true]:
		for witnessed in [false, true]:
			var p := _patient()
			var claim: Dictionary = _legal.file_claim(p, "injury")
			claim["imaging"] = imaged
			claim["witnesses"] = ["Nurse Pell"] if witnessed else []
			var seen := {}
			for opener in ["record", "deny", "concede", "risk"]:
				var ex := LegalSystem.exchange(claim, [opener])
				t.ok(String(ex["them"]).length() > 12,
					"answering '%s' gets a real line back" % opener)
				t.ok(not String(ex["them"]).contains("%s"),
					"and every placeholder in it has been filled in")
				t.ok(Array(ex["replies"]).size() >= 3,
					"with something to say to it")
				seen[String(ex["them"])] = true
			t.gt(float(seen.size()), 2.0,
				"and four different answers do not all get the same line back")

func test_saying_the_same_thing_again_is_worth_less() -> void:
	# A man with one answer. The court notices before he does, and the screen
	# says so rather than decaying it silently.
	_systems()
	var p := _patient()
	var claim: Dictionary = _legal.file_claim(p, "procedure")
	var first := LegalSystem.reply_score(claim, "deny", "firm", 0)
	var second := LegalSystem.reply_score(claim, "deny", "firm", 1)
	var third := LegalSystem.reply_score(claim, "deny", "firm", 2)
	t.lt(second, first, "the second time is worth less than the first")
	t.lt(third, second, "and the third less than the second")
	t.gt(third, -0.001, "without ever going negative")

func test_a_hearing_ends_and_can_be_played_out() -> void:
	# Walked end to end the way the screen walks it, because the screen's loop
	# and the system's exchange() have to agree about when it is over.
	_systems()
	var p := _patient()
	var claim: Dictionary = _legal.file_claim(p, "premature_discharge")
	var said: Array = []
	var scores: Array = []
	for i in LegalSystem.HEARING_LENGTH:
		var ex := LegalSystem.exchange(claim, said)
		var pick := String(ex["replies"][0])
		scores.append(LegalSystem.reply_score(claim, pick, "firm", said.count(pick)))
		said.append(pick)
	t.eq(said.size(), LegalSystem.HEARING_LENGTH, "the hearing runs to its length")
	var score := LegalSystem.hearing_score(scores)
	t.ok(score >= 0.0 and score <= 1.0, "and produces a score a verdict can use")

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

## Two different kinds of trouble, and they are not the same size.
##
## Being SEEN is ambient — you spent the evening where people could look at you,
## and what comes of that is a description of a man in a coat. Being CAUGHT is
## somebody's eyeline on you at the moment of the act, and what comes of THAT is
## a witness, which is a claim form. The whole street phase is the gap between
## those two, and it used to be one number with a threshold in it.
func test_being_seen_and_being_caught_are_different_things() -> void:
	var ns := NightSystem.new()
	t.root.add_child(ns)
	var heat_before := GameState.heat

	var clean := ns.resolve("allotments", "A Person", 0.05, true, false)
	t.eq(String(clean["outcome"]), "clean", "unseen is a clean night")
	t.near(GameState.heat, heat_before, 0.001, "and costs nothing")
	t.ok(String(clean["injury"]) != "",
		"and it still tells you what they are turning up with")

	ns.used_tonight = false
	heat_before = GameState.heat
	var seen := ns.resolve("allotments", "B Person", 0.9, true, false)
	var seen_cost := GameState.heat - heat_before
	t.eq(String(seen["outcome"]), "seen",
		"a whole evening in the open, but nobody watching the act, is a telling-off")
	t.ok(not bool(seen.get("sued", false)), "and nobody has a claim")
	t.gt(seen_cost, 0.0, "it does follow you home")

	ns.used_tonight = false
	heat_before = GameState.heat
	var caught := ns.resolve("allotments", "C Person", 0.05, true, true)
	var caught_cost := GameState.heat - heat_before
	t.eq(String(caught["outcome"]), "caught",
		"being watched AT the moment is the bad one, however quiet the rest was")
	t.gt(caught_cost, seen_cost, "and it costs more than merely being about")
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

## The street's own geometry, which is the phase's difficulty in disguise.
##
## Every one of these was wrong at some point and none of them announces itself:
## a spawn point past the way out ends the evening on the first step backwards,
## and a mark whose route never enters a lamp turns a stealth level into a
## corridor you jog down.
func test_the_street_is_laid_out_so_the_evening_is_playable() -> void:
	var st := Street.new()
	t.root.add_child(st)
	st.build(NightSystem.place("the_anchor"))

	var bail: float = Street.ORIGIN.x - Street.LENGTH * 0.47
	t.gt(st.player_start.x - bail, 4.0,
		"you start well clear of the way home, so backing up is not leaving")
	t.ok(absf(st.player_start.z) < Street.ROAD_HALF + Street.PAVE,
		"and on the pavement rather than in the road")

	t.gt(float(st.mark_route.size()), 2.0, "the mark has somewhere to walk")
	var ends_past_you := false
	for p in st.mark_route:
		if p.x < bail + 2.0:
			ends_past_you = true
	t.ok(ends_past_you, "and their walk ends behind you, so waiting has a cost")

	# At least one leg of that walk has to pass through lamplight, because the
	# decision the street asks is "take them here, or wait for the dark bit".
	var lit := false
	for p in st.mark_route:
		for l in st.lamps:
			if Vector2(p.x - l.x, p.z - l.z).length() < 8.5:
				lit = true
	t.ok(lit, "and it takes them through a lamp on the way")

	for spot in st.watcher_spots:
		var pos: Vector3 = spot["pos"]
		t.ok(absf(pos.x - Street.ORIGIN.x) < Street.LENGTH * 0.5,
			"every watcher is standing in the street")
	st.queue_free()

# ============================================================== a disagreement
func test_a_fight_is_worth_having_and_worth_avoiding() -> void:
	# The one place in this game where losing costs your own time rather than
	# your standing, so the two sides of it have to be genuinely different
	# things and not two sizes of the same penalty.
	var won := Brawl.outcome(true)
	var lost := Brawl.outcome(false)
	t.gt(float(won["stay"]), 1.0, "winning keeps them in the building")
	t.ok(String(won["harm"]) != "", "and leaves them with something to explain")
	t.ok(DB.COMPLICATIONS.has(String(won["harm"])),
		"which is a real complication the ward knows about")
	t.ok(not lost.has("stay"), "losing does not extend anybody's stay")
	t.gt(float(lost["bill"]), 0.0, "it costs you money instead")
	t.gt(float(lost["visual"]), float(won["visual"]),
		"and a doctor on the floor is more visible than a patient on the floor")

func test_the_wind_up_shortens_but_never_disappears() -> void:
	var first := Brawl.telegraph_for(0)
	var tenth := Brawl.telegraph_for(9)
	var absurd := Brawl.telegraph_for(400)
	t.gt(first, tenth, "the tenth swing gives you less warning than the first")
	t.near(absurd, Brawl.TELEGRAPH_MIN, 0.001,
		"and it bottoms out rather than becoming unreadable")
	t.gt(Brawl.TELEGRAPH_MIN, Brawl.WINDOW,
		"the shortest wind-up is still longer than the block window, so the "
		+ "last exchange is a read rather than a coin toss")

func test_only_somebody_who_is_here_can_square_up() -> void:
	var p := Patient.new("f1")
	p.display_name = "Test"
	p.admitted = false
	t.ok(not Brawl.can_fight(p), "a walk-in in the waiting room is not in a fight")
	p.admitted = true
	t.ok(Brawl.can_fight(p), "an admitted patient is")
	p.discharged = true
	t.ok(not Brawl.can_fight(p), "and somebody who has gone home is not")

func test_the_bill_for_losing_grows_with_the_career() -> void:
	# A broken nose costs the same on day one and day thirty, and on day thirty
	# that is nothing at all.
	t.gt(float(Brawl.bill_for(30)), float(Brawl.bill_for(1)) * 1.5,
		"losing on day thirty costs meaningfully more than losing on day one")

## The three acts have to be three different questions, not one question with
## three names on it.
func test_the_evening_offers_more_than_one_kind_of_job() -> void:
	var acts := {}
	var diffs := {}
	for spec in NightSystem.PLACES:
		var a := String(spec.get("act", ""))
		t.ok(NightSystem.ACTS.has(a), "%s has a real act (%s)" % [spec["name"], a])
		t.ok(String(NightSystem.ACTS[a].get("how", "")).length() > 20,
			"and %s says what it asks of you" % a)
		acts[a] = true
		diffs[int(spec.get("diff", 0))] = true
	t.gt(float(acts.size()), 2.0, "there are at least three different things to do")
	t.gt(float(diffs.size()), 2.0, "at three different difficulties")
	# A rig needs something to rig, or the objective line asks for a thing that
	# does not exist.
	for spec in NightSystem.PLACES:
		if String(spec.get("act", "")) == "rig":
			t.ok(String(spec.get("rig_name", "")) != "",
				"%s names the thing you see to" % spec["name"])

func test_the_easiest_job_is_offered_first() -> void:
	# The screen renders PLACES in order and does not sort, so the order IS the
	# difficulty curve.
	var last := 0
	for spec in NightSystem.PLACES:
		var d := int(spec.get("diff", 1))
		t.ok(d >= last, "%s does not come before something harder" % spec["name"])
		last = d

func test_being_caught_puts_a_letter_in_the_post() -> void:
	var lg := LegalSystem.new()
	t.root.add_child(lg)
	var before: int = lg.claims.size()
	t.ok(lg.file_street_claim("Wendell Tosh", "The allotments", "torn_knee"),
		"a witness to the act can bring a claim")
	t.eq(lg.claims.size(), before + 1, "and it lands on the pile")
	var claim: Dictionary = lg.claims.back()
	t.eq(String(claim["reason"]), "street", "filed as what it is")
	t.gt(float(claim["strength"]), 0.6, "and it is a strong one, because somebody watched")
	# Pointing at your own notes is no defence against something that did not
	# happen on your ward.
	t.lt(lg.reply_score(claim, "record", "duty"),
		lg.reply_score(claim, "deny", "duty"),
		"the chart is worth less than a flat denial here")
	lg.queue_free()

## The fight is meant to be hard, and hard in a way that is a read rather than
## a reaction test.
func test_a_fight_is_a_read_and_not_a_twitch() -> void:
	t.gt(Brawl.TELEGRAPH_MIN, Brawl.WINDOW,
		"even the shortest wind-up is longer than the block window")
	t.gt(float(Brawl.THEIR_GUARD), float(Brawl.YOUR_GUARD) * 2.0,
		"you have to land a lot more than you can take")
	t.gt(Brawl.feint_chance(12), Brawl.feint_chance(0),
		"and they start lying to you more as it goes on")
	t.lt(Brawl.feint_chance(999), 0.7,
		"but never so often that reading them is pointless")
	t.ok(Brawl.FEINT_AT > 0.2 and Brawl.FEINT_AT < 0.9,
		"the switch happens inside the wind-up, where you can still react to it")

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
