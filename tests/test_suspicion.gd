extends RefCounted
var t

func _mk_evidence(kind: String, w: float, src := Evidence.Source.WITNESSED, time := 0) -> Evidence:
	var e := Evidence.new()
	e.kind = kind
	e.base_weight = w
	e.source = src
	e.time = time
	e.certainty = 1.0
	return e

func test_suspicion_is_derived_not_stored() -> void:
	var m := DB.make_mind("n1", "Nurse Sarah", "nurse", "suspicious")
	t.near(m.suspicion(0), 0.0, 0.001, "no evidence means no suspicion")
	m.add_evidence(_mk_evidence("machine_overdial", 0.5))
	t.gt(m.suspicion(0), 0.0, "evidence produces suspicion")

func test_trust_buffers_suspicion() -> void:
	var trusting := DB.make_mind("a", "A", "nurse", "loyal")
	var wary := DB.make_mind("b", "B", "nurse", "suspicious")
	trusting.add_evidence(_mk_evidence("chart_forged", 0.6))
	wary.add_evidence(_mk_evidence("chart_forged", 0.6))
	t.lt(trusting.suspicion(0), wary.suspicion(0), "loyal nurse is less suspicious than suspicious one")

func test_source_matters() -> void:
	var seen := Mind.new("a", "A", "nurse")
	var told := Mind.new("b", "B", "nurse")
	seen.add_evidence(_mk_evidence("chart_forged", 0.6, Evidence.Source.WITNESSED))
	told.add_evidence(_mk_evidence("chart_forged", 0.6, Evidence.Source.GOSSIP))
	t.gt(seen.suspicion(0), told.suspicion(0), "witnessing beats hearsay")

func test_corroboration_is_superlinear() -> void:
	var solo := _mk_evidence("machine_overdial", 0.5)
	var pair := _mk_evidence("machine_overdial", 0.5)
	pair.corroborators = PackedStringArray(["nurse_2"])
	var trio := _mk_evidence("machine_overdial", 0.5)
	trio.corroborators = PackedStringArray(["nurse_2", "nurse_3"])
	var w1 := solo.current_weight(0)
	var w2 := pair.current_weight(0)
	var w3 := trio.current_weight(0)
	t.gt(w2, w1, "second witness increases weight")
	t.gt(w3 - w2, 0.0, "third witness increases it further")
	t.near(w2 - w1, w3 - w2, 0.0001, "corroboration scales linearly per witness on weight")

func test_evidence_decays_but_records_do_not() -> void:
	var witnessed := _mk_evidence("machine_overdial", 0.6, Evidence.Source.WITNESSED, 0)
	var record := _mk_evidence("chart_forged", 0.6, Evidence.Source.RECORD, 0)
	var ten_days := GameState.MINUTES_PER_DAY * 10
	t.lt(witnessed.current_weight(ten_days), witnessed.current_weight(0) * 0.5,
		"witnessed evidence fades substantially in ten days")
	t.gt(record.current_weight(ten_days), record.current_weight(0) * 0.85,
		"records barely fade")

func test_cover_story_discounts_evidence() -> void:
	var e := _mk_evidence("machine_overdial", 0.6)
	e.cover_tag = "equipment_variance"
	t.lt(e.current_weight(0, true), e.current_weight(0, false) * 0.3,
		"an active cover story heavily discounts matching evidence")

func test_neutralized_evidence_leaves_residue() -> void:
	var e := _mk_evidence("chart_forged", 0.8)
	var before := e.current_weight(0)
	e.neutralized = true
	var after := e.current_weight(0)
	t.lt(after, before * 0.2, "explaining it away mostly works")
	t.gt(after, 0.0, "but never fully — residue remains for investigators")

func test_duplicate_evidence_merges() -> void:
	var m := Mind.new("n", "N", "nurse")
	m.add_evidence(_mk_evidence("machine_overdial", 0.4, Evidence.Source.WITNESSED, 100))
	m.add_evidence(_mk_evidence("machine_overdial", 0.4, Evidence.Source.WITNESSED, 120))
	t.eq(m.evidence.size(), 1, "same act seen twice merges into one memory")
	t.gt(m.evidence[0].certainty, 0.99, "but certainty goes up")

func test_seeing_it_again_reopens_neutralized() -> void:
	var m := Mind.new("n", "N", "nurse")
	var e := m.add_evidence(_mk_evidence("chart_forged", 0.5, Evidence.Source.WITNESSED, 100))
	e.neutralized = true
	m.add_evidence(_mk_evidence("chart_forged", 0.5, Evidence.Source.WITNESSED, 130))
	t.ok(not m.evidence[0].neutralized, "catching you twice undoes the excuse")

func test_retelling_degrades() -> void:
	var e := _mk_evidence("machine_overdial", 0.6)
	var r1 := e.retold()
	var r2 := r1.retold()
	t.lt(r1.certainty, e.certainty, "retelling loses certainty")
	t.lt(r2.certainty, r1.certainty, "and again")
	t.eq(r2.source, Evidence.Source.GOSSIP, "retold evidence is gossip")

func test_burned_covers_stop_working() -> void:
	var m := Mind.new("n", "N", "nurse")
	t.near(m.cover_effectiveness("paperwork"), 1.0, 0.001, "fresh excuse works")
	m.burn_cover("paperwork")
	t.lt(m.cover_effectiveness("paperwork"), 0.7, "second use is weaker")
	m.burn_cover("paperwork")
	m.burn_cover("paperwork")
	t.near(m.cover_effectiveness("paperwork"), 0.0, 0.001, "fourth use is worthless")

func test_tiers_are_ordered() -> void:
	var m := Mind.new("n", "N", "nurse")
	m.skepticism = 0.5
	m.trust = 0.5
	t.eq(m.tier(0), 0, "starts calm")
	for i in 8:
		var e := _mk_evidence("act_%d" % i, 0.5, Evidence.Source.WITNESSED, i * 10)
		m.add_evidence(e)
	t.gt(float(m.tier(0)), 2.0, "a pile of witnessed acts convinces them")

func test_strongest_picks_the_worst() -> void:
	var m := Mind.new("n", "N", "nurse")
	m.add_evidence(_mk_evidence("small", 0.1))
	m.add_evidence(_mk_evidence("huge", 0.9))
	m.add_evidence(_mk_evidence("mid", 0.4))
	t.eq(m.strongest(0).kind, "huge", "strongest evidence is the one they bring up")

func test_prune_drops_stale() -> void:
	var m := Mind.new("n", "N", "nurse")
	m.add_evidence(_mk_evidence("old", 0.05, Evidence.Source.HEARD, 0))
	m.prune(GameState.MINUTES_PER_DAY * 30)
	t.eq(m.evidence.size(), 0, "ancient trivia is forgotten")

func test_mind_roundtrip() -> void:
	var m := DB.make_mind("n", "Nurse Sarah", "nurse", "gossip")
	m.add_evidence(_mk_evidence("machine_overdial", 0.5))
	m.burn_cover("paperwork")
	var back := Mind.from_dict(m.to_dict())
	t.eq(back.display_name, "Nurse Sarah", "name roundtrips")
	t.eq(back.evidence.size(), 1, "evidence roundtrips")
	t.eq(int(back.burned_covers.get("paperwork", 0)), 1, "burned covers roundtrip")
	t.near(back.suspicion(0), m.suspicion(0), 0.0001, "suspicion identical after roundtrip")

func test_bedside_manner_is_never_a_gamble() -> void:
	# Ordinary politeness must not be rolled. Showing a failure chance against
	# "how are you feeling?" teaches the player to distrust the confidence band
	# everywhere it actually matters.
	var m := DB.make_mind("p", "Greg", "patient", "confrontational")
	m.trust = 0.1
	var opt = Dialogue.Option.new("How are you feeling?", "small_talk", "", 0.0, "trust")
	t.near(Dialogue.success_chance(m, opt), 1.0, 0.0001, "small talk always lands")
	var before := m.trust
	var res: Dictionary = Dialogue.resolve(m, opt, null)
	t.ok(bool(res.get("success", false)), "and always succeeds")
	t.gt(m.trust, before, "and buys a little trust")
	t.eq(m.evidence.size(), 0, "and never creates evidence")

func test_a_real_excuse_is_still_a_gamble() -> void:
	var m := DB.make_mind("n", "Nurse", "nurse", "suspicious")
	m.trust = 0.1
	var e := Evidence.new()
	e.kind = "machine_extreme_dial"
	e.source = Evidence.Source.WITNESSED
	e.base_weight = 0.7
	e.certainty = 1.0
	m.add_evidence(e)
	var opt = Dialogue.Option.new("That's a known equipment fault.", "deflect",
		"equipment_variance", 0.4)
	t.lt(Dialogue.success_chance(m, opt), 0.5,
		"a suspicious nurse holding strong evidence is hard to talk around")
	t.gt(Dialogue.success_chance(m, opt), 0.0, "but never impossible")

func test_gossip_prefers_people_who_get_on() -> void:
	# Affinity was serialised and never consulted, so who told whom was purely
	# a matter of who happened to be standing nearby.
	var a := DB.make_mind("a", "Nurse A", "nurse", "gossip")
	a.affinity["b"] = 1.0
	a.affinity["c"] = 0.0
	t.near(float(a.affinity.get("b", 0.5)), 1.0, 0.001, "a close colleague is close")
	t.near(float(a.affinity.get("c", 0.5)), 0.0, 0.001, "and a distant one is not")
	t.near(float(a.affinity.get("nobody", 0.5)), 0.5, 0.001,
		"strangers fall back to even odds rather than never talking")

	var back := Mind.from_dict(a.to_dict())
	t.near(float(back.affinity.get("b", 0.0)), 1.0, 0.001, "and it survives a save")

func test_repeated_explanations_leave_growing_residue() -> void:
	# explained_attempts was recorded, serialised, and never affected anything.
	# A story you have had to defend three times is one nobody quite believes.
	var once := Evidence.new()
	once.base_weight = 0.6
	once.certainty = 1.0
	once.neutralized = true
	once.explained_attempts = 1

	var thrice := Evidence.new()
	thrice.base_weight = 0.6
	thrice.certainty = 1.0
	thrice.neutralized = true
	thrice.explained_attempts = 3

	t.gt(thrice.current_weight(0), once.current_weight(0),
		"explaining the same thing repeatedly leaves more behind")
	t.lt(thrice.current_weight(0), 0.6 * 0.6, "but still far less than never explaining it")

func test_a_watching_npc_is_harder_to_distract() -> void:
	# Letting suspicion reach the watching tier costs you the thrown-bedpan
	# distraction, which is the whole point of the tell.
	var calm := NPCBody.new()
	var alert := NPCBody.new()
	t.root.add_child(calm)
	t.root.add_child(alert)
	calm.mind = DB.make_mind("c", "C", "nurse", "gossip")
	alert.mind = DB.make_mind("a", "A", "nurse", "gossip")
	alert.mind.watching = true

	calm.perception.distract(0.8)
	alert.perception.distract(0.8)
	t.lt(alert.perception._distraction, calm.perception._distraction,
		"somebody watching you does not look away as readily")
	calm.queue_free()
	alert.queue_free()

func test_a_patient_who_is_not_counting_does_not_mind_waiting() -> void:
	var counting := Patient.new("c")
	counting.expected_stay_days = 2.0
	counting.days_admitted = 5.0
	counting.satisfaction = 0.8
	counting.knows_expected_date = true
	counting.tick(1.0)

	var oblivious := Patient.new("o")
	oblivious.expected_stay_days = 2.0
	oblivious.days_admitted = 5.0
	oblivious.satisfaction = 0.8
	oblivious.knows_expected_date = false
	oblivious.tick(1.0)

	t.lt(counting.satisfaction, oblivious.satisfaction,
		"somebody counting the days minds the overrun")
	t.near(oblivious.satisfaction, 0.8, 0.0001,
		"somebody who has lost the thread does not")

func test_how_blatant_an_act_is_dominates_whether_it_is_noticed() -> void:
	# This was missing entirely: the chance depended only on observance and
	# distance, so cranking a machine to eleven in somebody's face was exactly
	# as likely to be spotted as nudging a thermostat. The whole risk curve the
	# game is built on did not exist.
	var blatant := NPCPerception.notice_chance(0.9, 0.5, 0.9)
	var subtle := NPCPerception.notice_chance(0.05, 0.5, 0.9)
	t.gt(blatant, subtle * 3.0, "a blatant act is far more likely to be seen than a subtle one")
	t.gt(blatant, 0.6, "and a blatant act at close range is usually caught")
	t.lt(subtle, 0.35, "while a subtle one usually is not")

func test_observance_and_distance_still_matter() -> void:
	var attentive := NPCPerception.notice_chance(0.5, 0.9, 0.9)
	var oblivious := NPCPerception.notice_chance(0.5, 0.1, 0.9)
	t.gt(attentive, oblivious, "an attentive witness notices more")

	var near := NPCPerception.notice_chance(0.5, 0.5, 1.0)
	var far := NPCPerception.notice_chance(0.5, 0.5, 0.1)
	t.gt(near, far, "and proximity matters")

func test_even_a_blatant_act_is_never_certain_and_a_subtle_one_never_free() -> void:
	t.lt(NPCPerception.notice_chance(1.0, 1.0, 1.0), 1.0,
		"nothing is guaranteed to be seen")
	t.gt(NPCPerception.notice_chance(0.01, 0.0, 0.0), 0.0,
		"and nothing is guaranteed to be missed")
