extends RefCounted
## The redesigned game, tested at the level the design cares about: does a lie
## cost more than the truth, does patching cost more than not patching, and can
## a player who sequences their day well talk their way out of it.
var t

func _day() -> WardDay:
	var w := WardDay.new()
	t.root.add_child(w)
	w.start()
	return w

func _sev(f: Array) -> float:
	var s := 0.0
	for x in f:
		s += x.severity
	return s

func _kinds(f: Array) -> Array:
	var out: Array = []
	for x in f:
		out.append(x.kind)
	return out

# ---------------------------------------------------------------- economy
## The four properties the whole slice rests on. If any of these inverts, the
## day stops being a decision and becomes a right answer.
func test_the_money_creates_the_decision() -> void:
	var w := _day()
	for c in Cases.ROSTER:
		w.set_disposition(String(c["id"]), "discharge")
	var lazy: int = int(w.projected()["total"])
	t.lt(float(lazy), float(Cases.DEBT_DUE),
		"discharging everybody does not pay the debt — refusing to hold anyone fails")
	w.queue_free()

	var w2 := _day()
	w2.set_disposition("marchetti", "hold")
	for id in ["kerrigan", "brennan", "oduya", "blake"]:
		w2.set_disposition(id, "discharge")
	var honest: int = int(w2.projected()["total"])
	t.gt(float(honest), float(Cases.DEBT_DUE),
		"holding the one genuinely unwell patient DOES pay it — honesty is possible")
	t.lt(float(honest - Cases.DEBT_DUE), 400.0,
		"...and only just, so it stays a decision rather than a formality")
	t.eq(w2.review_findings().size(), 0,
		"and an honest day produces nothing for the reviewer to ask about")
	w2.queue_free()

	# Greed has to be punished by arithmetic before anybody reads a chart.
	var w3 := _day()
	for c in Cases.ROSTER:
		w3.set_disposition(String(c["id"]), "hold")
	var greedy: int = int(w3.projected()["total"])
	w3.queue_free()
	var w4 := _day()
	w4.set_disposition("marchetti", "hold")
	w4.set_disposition("oduya", "hold")
	for id in ["kerrigan", "brennan", "blake"]:
		w4.set_disposition(id, "discharge")
	var selective: int = int(w4.projected()["total"])
	w4.queue_free()
	t.lt(float(greedy), float(selective),
		"holding every bed EARNS LESS than holding two, because the empty beds admit")

	# Mercy has to be affordable or it is not a choice, it is a tax.
	var w5 := _day()
	w5.set_disposition("marchetti", "hold")
	w5.set_disposition("kerrigan", "hold")
	for id in ["brennan", "oduya", "blake"]:
		w5.set_disposition(id, "discharge")
	t.gt(float(int(w5.projected()["total"])), float(Cases.DEBT_DUE),
		"keeping Dot Kerrigan out of kindness still clears the debt")
	w5.queue_free()

# ---------------------------------------------------------------- timing
## The central skill. Adeyemi rounds at fixed times; a fabrication in a gap is
## survivable and a fabrication on top of a round is not.
func test_when_you_write_it_is_the_skill() -> void:
	# Both times must be inside the working day: the ward force-ends at
	# DEBT_DUE_MINUTE, so a test that reached past it was measuring a round
	# that can never happen in play. The gap here is 17:30 — an hour and a
	# half clear of the 16:00 round and ninety minutes before the 19:00 one.
	var good := _day()
	good.advance_to(17 * 60 + 30)
	good.write_entry("oduya", ChartEntry.Claim.UNWELL,
		"Reports transient dizziness on standing.", 17 * 60 + 25)
	good.set_disposition("oduya", "hold")
	var quiet := _sev(good.review_findings())
	good.queue_free()

	var bad := _day()
	bad.advance_to(19 * 60 + 5)
	bad.write_entry("oduya", ChartEntry.Claim.UNWELL,
		"Reports transient dizziness on standing.", 19 * 60)
	bad.set_disposition("oduya", "hold")
	var loud := _sev(bad.review_findings())
	bad.queue_free()

	t.gt(loud, quiet * 2.0,
		"the same lie written over the seven o'clock round is worth more than twice one written in the gap")

func test_the_rounds_happen_whether_you_ask_or_not() -> void:
	var w := _day()
	var before: int = w.records.for_patient("oduya").size()
	w.advance_to(19 * 60 + 30)
	t.gt(float(w.records.for_patient("oduya").size()), float(before),
		"Adeyemi writes in the chart during the day without being asked")
	w.queue_free()

# ---------------------------------------------------------------- compounding
## THE HYPOTHESIS THE WHOLE REDESIGN RESTS ON. Patching a lie has to cost more
## than leaving it alone, or a dishonest day is just a worse honest one.
func test_patching_a_lie_costs_more_than_leaving_it() -> void:
	var bare := _day()
	bare.advance_to(16 * 60 + 42)
	bare.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness on standing.", 16 * 60 + 30)
	bare.set_disposition("oduya", "hold")
	var alone := _sev(bare.review_findings())
	bare.queue_free()

	var patched := _day()
	patched.advance_to(16 * 60 + 42)
	var a := patched.write_entry("oduya", ChartEntry.Claim.UNWELL,
		"Reports dizziness on standing.", 16 * 60 + 30)
	var o := patched.order_test("oduya", "lying and standing BP")
	patched.advance_to(18 * 60)
	patched.resolve_test(o)
	patched.advance_to(18 * 60 + 40)
	var b := patched.write_entry("oduya", ChartEntry.Claim.SETTLED,
		"BP unremarkable; symptoms positional.", 18 * 60, WardDay.TERMINAL_OFFICE, a.id)
	patched.advance_to(19 * 60 + 10)
	patched.write_entry("oduya", ChartEntry.Claim.ADMIN,
		"Addendum timed late owing to workload.", 18 * 60 + 40, WardDay.TERMINAL_OFFICE, b.id)
	patched.set_disposition("oduya", "hold")
	var mended := _sev(patched.review_findings())
	patched.queue_free()

	t.gt(mended, alone * 2.0,
		"covering your tracks is worth more than twice as much as not covering them (%.2f vs %.2f)"
			% [mended, alone])

func test_a_result_cannot_be_talked_to() -> void:
	var w := _day()
	w.advance_to(16 * 60 + 30)
	w.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 16 * 60 + 25)
	var before := _sev(w.review_findings())
	var o := w.order_test("oduya", "lying and standing BP")
	w.advance_to(17 * 60 + 45)
	w.resolve_test(o)
	w.set_disposition("oduya", "hold")
	var after := _sev(w.review_findings())
	t.gt(after - before, 0.9,
		"ordering a test on somebody who is well is the single most expensive thing you can do")
	t.ok(_kinds(w.review_findings()).has("objective_refutes"),
		"and it is the result that does it, by name")
	w.queue_free()

## Asking a nurse is a gamble on the truth, not a button that helps.
func test_asking_the_nurse_depends_entirely_on_who_you_ask_about() -> void:
	var honest := _day()
	honest.advance_to(14 * 60 + 30)
	honest.nurse_check("marchetti")      ## genuinely unwell — she agrees
	honest.set_disposition("marchetti", "hold")
	t.eq(_sev(honest.review_findings()), 0.0,
		"asking her to review the patient who is actually unwell costs nothing and corroborates you")
	honest.queue_free()

	var reckless := _day()
	reckless.advance_to(17 * 60 + 20)
	reckless.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 17 * 60 + 15)
	var solo := _sev(reckless.review_findings())
	reckless.advance_to(17 * 60 + 40)
	reckless.nurse_check("oduya")        ## well — she writes that he is fine
	reckless.set_disposition("oduya", "hold")
	t.gt(_sev(reckless.review_findings()), solo,
		"and asking her about somebody you know is well hands her the contradiction herself")
	reckless.queue_free()

## One lie is a discrepancy. Three is a shape.
func test_the_institution_notices_the_pattern_not_the_note() -> void:
	var w := _day()
	w.advance_to(17 * 60 + 30)
	for id in ["oduya", "brennan", "blake"]:
		w.write_entry(id, ChartEntry.Claim.UNWELL, "Unsettled this evening.", 17 * 60 + 25)
		w.set_disposition(id, "hold")
	t.ok(_kinds(w.review_findings()).has("pattern_of_holds"),
		"three people held on notes only you ever wrote is its own finding")
	w.queue_free()

## The flag is on her file and nowhere else.
func test_the_flagged_file_is_read_harder() -> void:
	var plain := _day()
	plain.advance_to(17 * 60 + 30)
	plain.write_entry("oduya", ChartEntry.Claim.UNWELL, "Headache recurred.", 17 * 60 + 25)
	plain.set_disposition("oduya", "hold")
	var unflagged := _sev(plain.review_findings())
	plain.queue_free()

	var flagged := _day()
	flagged.advance_to(17 * 60 + 30)
	flagged.write_entry("blake", ChartEntry.Claim.UNWELL, "Headache recurred.", 17 * 60 + 25)
	flagged.set_disposition("blake", "hold")
	t.gt(_sev(flagged.review_findings()), unflagged * 1.4,
		"the identical act on the patient whose file is already under review costs meaningfully more")
	flagged.queue_free()

func test_reversing_a_colleague_is_its_own_problem() -> void:
	var w := _day()
	w.advance_to(15 * 60)
	w.write_entry("brennan", ChartEntry.Claim.UNWELL,
		"Wound appears warm. Not for discharge today.", 14 * 60 + 55)
	w.set_disposition("brennan", "hold")
	t.ok(_kinds(w.review_findings()).has("reversed_a_colleague"),
		"overturning Adeyemi's written discharge plan is a finding no matter what time it is")
	w.queue_free()

# ---------------------------------------------------------------- the review
## The review has to reward sequencing, or there is no skill in the room.
func test_the_defence_is_decided_hours_before_the_conversation() -> void:
	# Test ordered LATE: "it was transient, it had settled by then" is coherent.
	var late := _day()
	late.advance_to(16 * 60 + 30)
	late.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 16 * 60 + 25)
	var o1 := late.order_test("oduya", "lying and standing BP")
	late.advance_to(18 * 60 + 30)
	late.resolve_test(o1)
	late.set_disposition("oduya", "hold")
	var rv1 := ReviewSystem.new()
	rv1.begin(late.review_findings(), late.records.entries, late.review_truth())
	var had_reconcile := false
	while not rv1.finished():
		var q1 = rv1.current()
		# Specifically the question the RESULT asks. Checking "was RECONCILE
		# offered anywhere in the room" passed for the wrong reason — a note
		# written near a round has its own transience answer, which has nothing
		# to do with when you ordered the test.
		if q1.kind == "objective_refutes":
			for opt in rv1.options(q1, late.records):
				if int(opt["a"]) == ReviewSystem.Answer.RECONCILE:
					had_reconcile = true
		rv1.answer(ReviewSystem.Answer.STAND_BY, late.held_ids())
	t.ok(had_reconcile,
		"a test ordered two hours after the symptom leaves you an honest-sounding explanation")
	late.queue_free()

	# Test ordered IMMEDIATELY to cover yourself: that explanation is gone.
	var eager := _day()
	eager.advance_to(16 * 60 + 30)
	eager.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 16 * 60 + 25)
	var o2 := eager.order_test("oduya", "lying and standing BP")
	eager.advance_to(16 * 60 + 45)
	eager.resolve_test(o2)
	eager.set_disposition("oduya", "hold")
	var rv2 := ReviewSystem.new()
	rv2.begin(eager.review_findings(), eager.records.entries, eager.review_truth())
	var eager_reconcile := false
	while not rv2.finished():
		var q2 = rv2.current()
		if q2.kind == "objective_refutes":
			for opt in rv2.options(q2, eager.records):
				if int(opt["a"]) == ReviewSystem.Answer.RECONCILE:
					eager_reconcile = true
		rv2.answer(ReviewSystem.Answer.STAND_BY, eager.held_ids())
	t.ok(not eager_reconcile,
		"covering yourself immediately destroys the only good answer you had — the safe play is the wrong one")
	eager.queue_free()

func test_abandoning_your_story_is_worse_than_defending_it() -> void:
	# Written in the gap, so the bed starts on your word alone rather than
	# already contradicted — a bed that is beyond saving cannot be made worse by
	# anything you say, and testing on one measured nothing.
	var w := _day()
	w.advance_to(17 * 60 + 30)
	w.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 17 * 60 + 25)
	w.set_disposition("oduya", "hold")
	var findings := w.review_findings()

	# Measured in BEDS, which is what the review is about. This used to read
	# outcome()["unresolved"], a key the per-bed audit stopped returning — the
	# lookup aborted the function and the test reported a pass while checking
	# nothing. The runner now fails a test that asserts nothing.
	var stubborn := ReviewSystem.new()
	stubborn.begin(findings, w.records.entries, w.review_truth())
	while not stubborn.finished():
		stubborn.answer(ReviewSystem.Answer.STAND_BY, w.held_ids())
	var a := int(stubborn.outcome()["indefensible"])

	var folding := ReviewSystem.new()
	folding.begin(findings, w.records.entries, w.review_truth())
	while not folding.finished():
		folding.answer(ReviewSystem.Answer.DEFER, w.held_ids())
	var fo := folding.outcome()
	var b := int(fo["indefensible"])

	t.gt(float(b), float(a),
		"telling her the note was wrong, about a bed you billed, is worse than defending it (%d beds vs %d)"
			% [b, a])
	t.gt(float(fo["created"]), 0.0,
		"and it creates problems that did not exist before you opened your mouth")
	w.queue_free()

func test_the_same_excuse_twice_stops_working() -> void:
	var w := _day()
	w.advance_to(19 * 60 + 5)
	w.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 18 * 60 + 30)
	w.write_entry("brennan", ChartEntry.Claim.UNWELL, "Wound warm.", 18 * 60 + 35)
	w.set_disposition("oduya", "hold")
	w.set_disposition("brennan", "hold")
	var rv := ReviewSystem.new()
	rv.begin(w.review_findings(), w.records.entries, w.review_truth())
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.BLAME_SYSTEM, w.held_ids())
	var o := rv.outcome()
	t.gt(float(o["created"]), 0.0, "blaming the terminal clocks twice is itself a finding")
	w.queue_free()

## Nobody should ever leave the review not knowing what happened to them.
func test_failure_is_always_explicable() -> void:
	var w := _day()
	w.advance_to(19 * 60 + 5)
	w.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 19 * 60)
	w.set_disposition("oduya", "hold")
	var rv := ReviewSystem.new()
	rv.begin(w.review_findings(), w.records.entries, w.review_truth())
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.STAND_BY, w.held_ids())
	var o := rv.outcome()
	t.ok(String(o["because"]).length() > 20,
		"the outcome always names the thing that caused it")
	for line in Array(o["transcript"]):
		t.ok(String(line["question"]).length() > 10,
			"and every question she asked is on the record afterwards")
	w.queue_free()

## "Noted" used to be free. It has to cost something or one well-timed
## fabrication a day is strictly better than honesty forever: +150 on the night
## and nothing carried into the morning. What carries is the BED, by name.
func test_a_bed_she_could_not_stand_up_goes_on_the_file() -> void:
	GameState.set_flag("remembered_beds", PackedStringArray())
	var clean := _day()
	clean.advance_to(17 * 60 + 30)
	clean.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 17 * 60 + 25)
	clean.set_disposition("oduya", "hold")
	var first := _sev(clean.review_findings())
	var rv := ReviewSystem.new()
	rv.begin(clean.review_findings(), clean.records.entries, clean.review_truth())
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.STAND_BY, clean.held_ids())
	var remembered := PackedStringArray(rv.outcome()["remembered"])
	clean.queue_free()

	t.ok(remembered.has("oduya"),
		"the bed you held on nobody's word but your own is remembered by name")

	# Tomorrow, the identical play on the identical patient is read harder.
	GameState.set_flag("remembered_beds", remembered)
	var after := _day()
	t.ok(after.is_flagged("oduya"), "and he opens tomorrow with a note on his file")
	after.advance_to(17 * 60 + 30)
	after.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 17 * 60 + 25)
	after.set_disposition("oduya", "hold")
	t.gt(_sev(after.review_findings()), first * 1.4,
		"doing it to him twice costs meaningfully more the second time (%.2f then %.2f)"
			% [first, _sev(after.review_findings())])
	after.queue_free()
	GameState.set_flag("remembered_beds", PackedStringArray())

## The office desk used to end the day at whatever minute you walked into it,
## so the safest shift on the ward was to hold three beds at five past eight and
## sign off before anybody had rounded. Leaving early buys you absence, not
## silence: the evening happens and you are not there to answer it.
func test_going_home_early_does_not_stop_the_evening() -> void:
	var early := _day()
	early.advance_to(8 * 60 + 5)
	early.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 8 * 60)
	early.set_disposition("oduya", "hold")
	early.set_disposition("marchetti", "hold")
	_rest_home(early)
	var res := early.end_day()
	t.gt(float(early.records.for_patient("oduya").size()), 2.0,
		"the rounds between leaving and handover are on the chart when she reads it")
	t.gt(float(Array(res["findings"]).size()), 0.0,
		"and the note you left behind has something to argue with")
	early.queue_free()

func _rest_home(w: WardDay) -> void:
	for c in Cases.ROSTER:
		if String(w.state[String(c["id"])]["disposition"]) == "":
			w.set_disposition(String(c["id"]), "discharge")
