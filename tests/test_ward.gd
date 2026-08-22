extends RefCounted
## The redesigned game, tested at the level the design cares about: does a lie
## cost more than the truth, does patching cost more than not patching, and can
## a player who sequences their day well talk their way out of it.
var t

## BEFORE EVERY TEST, THE WARD IS EMPTY.
##
## `queue_free()` never actually frees anything in this runner — it drives the
## suite from `_process` on frame three and quits, so nothing is ever collected
## and every ward any test has ever built is still sitting in the tree, still
## connected to `GameState.minute_passed`. The moment one test advanced its
## clock to eight o'clock, every one of those zombies force-discharged its own
## ward and paid Vinnie out of the same career debt: a test that handed him
## $2,650 watched $11,100 leave the account.
##
## The runner calls this before each test. `free()`, not `queue_free()`.
func setup() -> void:
	for n in t.root.get_children():
		if n is WardDay:
			t.root.remove_child(n)
			n.free()

## THERE IS ONE WARD. A test that wants a second day wants the ward it already
## had, reset — not another one alive beside it holding a second set of five
## patients and a second connection to the world clock.
func _day() -> WardDay:
	setup()
	# A CLEAN CAREER PER TEST. Ending a day now pays down a career-long debt and
	# writes to the doctor's record, both of which live in GameState — so a test
	# that does not put them back is measuring whatever the tests above it did.
	GameState.reset_debt()
	DoctorRecord.wipe()
	GameState.set_flag(Cases.READMIT_FLAG, [])
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
	for c in Cases.roster():
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
	for c in Cases.roster():
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

## "NOTED" HAS TO COST SOMETHING, or one well-timed fabrication a night is
## strictly better than honesty forever: +700 on the night and nothing carried.
##
## The first version of this carried the BED — a note on that patient's file,
## read harder tomorrow. It was measured, it worked, and a probe that played a
## week found it completely dead: the wards alternate, so the patient whose file
## was marked is not on the ward tomorrow and the flag is overwritten before
## they ever come back. What accumulates is the DOCTOR.
func test_she_remembers_the_doctor_not_the_bed() -> void:
	DoctorRecord.wipe()
	var clean := _day()
	clean.advance_to(17 * 60 + 30)
	clean.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 17 * 60 + 25)
	clean.set_disposition("oduya", "hold")
	var first := _sev(clean.review_findings())
	var rv := ReviewSystem.new()
	rv.begin(clean.review_findings(), clean.records.entries, clean.review_truth())
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.STAND_BY, clean.held_ids())
	rv.commit(clean.review_findings())
	clean.queue_free()

	var rec := DoctorRecord.load_from_state()
	t.eq(rec.times("uncorroborated_stay"), 1,
		"a bed nobody else saw a reason for goes on YOUR record")
	t.eq(rec.nights, 1, "and the night is counted")

	# THE SAME PLAY ON A DIFFERENT WARD. This is the case the per-bed version
	# could not handle at all: tomorrow is five other people.
	GameState.day = 2
	var tomorrow := _day()
	tomorrow.advance_to(17 * 60 + 30)
	tomorrow.write_entry("voss", ChartEntry.Claim.UNWELL, "Unsettled.", 17 * 60 + 25)
	tomorrow.set_disposition("voss", "hold")
	var second := 0.0
	for f in tomorrow.review_findings():
		if f.kind == "uncorroborated_stay":
			second = f.severity
	tomorrow.queue_free()
	GameState.day = 1

	t.gt(second, first * 0.99,
		"and doing the same thing to somebody else tomorrow is read harder, not fresh (%.2f then %.2f)"
			% [first, second])
	DoctorRecord.wipe()

## Three referrals and the Board takes your licence. Before this, REFERRED — the
## worst thing the reviewer can do — cost denser rounds and nothing else, and a
## seven-day probe showed a greedy player being referred every night for a week
## and simply carrying on.
func test_three_referrals_ends_it() -> void:
	DoctorRecord.wipe()
	var rec := DoctorRecord.load_from_state()
	t.ok(not GameState.struck_off(), "you start with a licence")
	for i in 3:
		rec.record_night([], ReviewSystem.OUTCOME_ESCALATED)
	t.eq(rec.referrals, 3, "three referrals are counted")
	t.ok(GameState.struck_off(), "and the third one ends the career")
	DoctorRecord.wipe()
	t.ok(not GameState.struck_off(), "a new career starts with a clean record")

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
	for c in Cases.roster():
		if String(w.state[String(c["id"])]["disposition"]) == "":
			w.set_disposition(String(c["id"]), "discharge")

## THERE IS ONE CLOCK. Every verb costs ward minutes; if those minutes are spent
## on WardDay.minute alone, the chart and the corner of the screen disagree and
## drift further apart the more the player does.
func test_the_ward_and_the_world_keep_the_same_time() -> void:
	var w := _day()
	GameState.minute_of_day = 8 * 60
	w.read_chart("oduya")
	t.eq(GameState.minute_of_day, w.minute,
		"reading a chart moves the world's clock, not just the ward's")
	w.write_entry("oduya", ChartEntry.Claim.ADMIN, "Seen.", w.minute)
	t.eq(GameState.minute_of_day, w.minute,
		"and so does writing in it")
	w.queue_free()

## end_day() advances the ward to handover, which comes straight back through
## minute_passed and calls end_day() again. Before the guard was moved, the debt
## came off the takings twice and whichever call lost the race handed its caller
## an empty dictionary.
func test_the_day_only_ends_once() -> void:
	var w := _day()
	w.set_disposition("marchetti", "hold")
	_rest_home(w)
	var first := w.end_day()
	var after := w.cash
	var second := w.end_day()
	t.eq(w.cash, after, "ending the day twice does not pay Vinnie twice")
	t.ok(second.has("earned"), "and the second caller gets the same answer, not an empty one")
	t.eq(int(second["cash"]), int(first["cash"]), "which is the same answer")
	w.queue_free()

## Who was in the room when you wrote it has to CHANGE something, or the two
## terminals are two pieces of flavour text describing the same act — which is
## what they were for three iterations, because `seen_by` was written on every
## entry and read by nothing.
func test_where_you_write_it_is_also_the_skill() -> void:
	var private := _day()
	private.advance_to(17 * 60 + 30)
	var a := private.write_entry("oduya", ChartEntry.Claim.UNWELL,
		"Reports dizziness.", 17 * 60 + 25, WardDay.TERMINAL_OFFICE)
	private.set_disposition("oduya", "hold")
	var alone := _sev(private.review_findings())
	private.queue_free()

	var public := _day()
	public.advance_to(17 * 60 + 30)
	var b := public.write_entry("oduya", ChartEntry.Claim.UNWELL,
		"Reports dizziness.", 17 * 60 + 25, WardDay.TERMINAL_WARD)
	# The harnesses have no scene, so nobody is in any room; state the witness
	# list directly, which is what standing at the bay terminal produces.
	b.seen_by = PackedStringArray(["Sam Oduya", "Hal Brennan"])
	public.set_disposition("oduya", "hold")
	var watched := _sev(public.review_findings())
	public.queue_free()

	t.ok(a.seen_by.is_empty(), "the office terminal records no witnesses")
	t.gt(watched, alone * 1.8,
		"and writing the same line where the patient could watch you do it costs far more (%.2f vs %.2f)"
			% [watched, alone])

## What a save has to carry, given a day is one sitting: the day number, the
## money, and what the ward sister remembers. If any of those is dropped,
## Continue is a button that quietly restarts the career.
func test_what_survives_the_night() -> void:
	GameState.day = 4
	GameState.set_flag("carried_debt", 640)
	GameState.set_flag("watched", true)
	DoctorRecord.wipe()
	var rec0 := DoctorRecord.load_from_state()
	rec0.record_night([], ReviewSystem.OUTCOME_FLAGGED)
	var d := GameState.to_dict()
	GameState.day = 1
	GameState.set_flag("carried_debt", 0)
	GameState.set_flag("watched", false)
	DoctorRecord.wipe()
	GameState.from_dict(d)
	t.eq(GameState.day, 4, "the day number survives a round trip")
	t.eq(int(GameState.flag("carried_debt", 0)), 640, "and so does what Vinnie did not get")
	t.eq(DoctorRecord.load_from_state().flagged_nights, 1,
		"and what she remembers about the doctor")
	t.ok(bool(GameState.flag("watched", false)), "and that you are being read closely")
	# ...and the ward reads them on the way in.
	GameState.day = 1
	var w := _day()
	t.eq(w.debt_tonight, Cases.DEBT_DUE,
		"he wants his usual number tomorrow")
	w.queue_free()

	# A SHORT NIGHT MAKES THE WHOLE THING LONGER. He does not ask for more
	# tomorrow; he adds his interest to what is left, which is what falling
	# behind to somebody like Vinnie actually does.
	GameState.reset_debt()
	var before: int = GameState.debt_remaining()
	var lean := _day()
	for c in Cases.roster():
		lean.set_disposition(String(c["id"]), "discharge")
	var res := lean.end_day()
	t.ok(bool(res["short"]), "sending the whole ward home does not cover the night")
	t.gt(float(GameState.debt_remaining()),
		float(before - int(res["paid"])),
		"and what is left of the debt grows by his interest (%d owed, %d paid, %d left)"
			% [before, int(res["paid"]), GameState.debt_remaining()])
	lean.queue_free()
	GameState.set_flag("carried_debt", 0)
	GameState.set_flag("watched", false)
	DoctorRecord.wipe()

## Two wards alive at once must not drag each other's clocks FURTHER FORWARD.
##
## Every WardDay both listens to `minute_passed` and (through advance_to) emits
## into it. Before `_advance_locally` existed that was a feedback loop: a ward
## advancing to half past four woke one sitting at half past six, which pushed
## the shared clock to half past six, which woke the first one back. Every test
## that kept a second day alive silently ran three hours late and measured a
## scenario nobody had written. Following the world clock forward is correct and
## deliberate — there is one clock — but nothing may push it past the ward that
## actually moved.
func test_two_wards_do_not_drag_each_other_forward() -> void:
	# DELIBERATELY TWO, which is the only test in here that wants them: `_day()`
	# frees the previous ward precisely so nothing else has to think about this.
	var early := _day()
	var late := WardDay.new()
	t.root.add_child(late)
	late.start()                ## a new day resets the world to eight o'clock
	late.advance_to(19 * 60)
	t.eq(GameState.minute_of_day, 19 * 60, "the ward that moved moved the world")
	t.eq(early.minute, 19 * 60, "and the other ward follows the world, because there is one clock")
	# The thing that must NOT happen: the ward left behind shoving the clock on.
	early.advance_to(11 * 60)
	t.eq(GameState.minute_of_day, 19 * 60,
		"a ward advancing to a time already past does not move the world at all")
	t.eq(late.minute, 19 * 60, "and nobody gets dragged past where they were")
	t.root.remove_child(late)
	late.free()

## And one ward on its own lands exactly where it is put, which is what every
## measurement in the game depends on.
func test_one_ward_lands_where_you_put_it() -> void:
	var w := _day()
	w.advance_to(11 * 60)
	t.eq(w.minute, 11 * 60, "eleven o'clock is eleven o'clock")
	t.eq(GameState.minute_of_day, 11 * 60, "on both clocks")
	w.queue_free()

# ------------------------------------------------------- the second ward
func _day_two() -> WardDay:
	GameState.day = 2
	return _day()

## Two authored wards, and the second is a different shape rather than the first
## one renamed. The property that makes it a second DAY and not a second SKIN:
## on ward one the honest hold is also the one that pays, and on ward two it is
## the one you cannot find by reading.
func test_the_second_ward_is_a_different_problem() -> void:
	var ids := []
	for c in Cases.roster(1):
		ids.append(String(c["id"]))
	var ids2 := []
	for c in Cases.roster(2):
		ids2.append(String(c["id"]))
	t.eq(ids.size(), 5, "the first ward has five beds")
	t.eq(ids2.size(), 5, "and so does the second")
	for id in ids2:
		t.ok(not ids.has(id), "%s is not on the first ward" % id)
	t.ok(Cases.roster(3) == Cases.roster(1), "day three comes round to the first ward again")

	# The money. Honesty must clear the debt on BOTH wards or the second one is
	# a difficulty spike rather than a different problem.
	var w := _day_two()
	w.set_disposition("bux", "hold")
	w.set_disposition("lomax", "hold")
	_rest_home(w)
	var honest: int = int(w.projected()["total"])
	t.gt(float(honest), float(Cases.DEBT_DUE),
		"holding the two who are genuinely unwell still pays the debt (%d)" % honest)
	t.lt(float(honest - Cases.DEBT_DUE), 400.0, "...and only just, as on the first ward")
	w.queue_free()

	# ...but mercy on its own no longer does, which is the escalation.
	var m := _day_two()
	m.set_disposition("bux", "hold")
	_rest_home(m)
	t.lt(float(int(m.projected()["total"])), float(Cases.DEBT_DUE),
		"keeping only the woman who is unwell and state-funded does NOT pay it")
	m.queue_free()
	GameState.day = 1

## THE REASON THE EXAMINATION EXISTS. Peter Lomax's chart says settled, every
## number on it has been coming down all week, and he is not fit to go. There
## has to be a patient the record cannot tell you about, or looking at people
## is decoration.
func test_there_is_a_man_the_chart_cannot_tell_you_about() -> void:
	var w := _day_two()
	var says_well := true
	for e in w.records.for_patient("lomax"):
		if e.supports_stay():
			says_well = false
	t.ok(says_well, "nothing written about Peter Lomax says he should stay")
	t.ok(not bool(Cases.by_id("lomax").get("truly_well", true)),
		"...and he is the one patient on the ward who genuinely should")
	var found: String = w.examine("lomax")
	t.ok(found.length() > 20, "going to look at him tells you so")
	t.ok(w.has_examined("lomax"), "and the ward remembers that you went")
	w.queue_free()
	GameState.day = 1

## A discharge is a decision and it is audited like one. Before this the
## reviewer only ever asked about beds you KEPT, so the fastest route to a clean
## handover was to empty the ward — the one thing a doctor must not do.
func test_sending_somebody_home_is_audited_too() -> void:
	var w := _day_two()
	w.examine("lomax")                     ## you looked, and you know
	w.set_disposition("lomax", "discharge")
	w.set_disposition("bux", "hold")
	_rest_home(w)
	var kinds := _kinds(w.review_findings())
	t.ok(kinds.has("sent_home_unwell"),
		"sending home a man you examined and found unwell is a finding")
	var beds := Contradictions.audit_beds(w.records.entries, w.review_truth(),
		w.review_findings())
	var emptied := 0
	for b in beds:
		if not b.billed:
			emptied += 1
			t.ok(b.indefensible(), "and the bed you emptied is indefensible")
	t.eq(emptied, 1, "exactly one emptied bed is audited — the one you got wrong")
	w.queue_free()
	GameState.day = 1

## ...and it is NOT a finding when the world never told you otherwise.
func test_a_clean_discharge_is_not_a_finding() -> void:
	var w := _day_two()
	w.set_disposition("bux", "hold")
	w.set_disposition("lomax", "hold")
	_rest_home(w)                          ## the three who are genuinely well
	t.ok(not _kinds(w.review_findings()).has("sent_home_unwell"),
		"sending home three people who are well is not a question")
	w.queue_free()
	GameState.day = 1

## THE STRONGEST DEFENCE IN THE GAME, AND THE MOST DANGEROUS REQUEST.
func test_a_colleague_backs_you_or_buries_you() -> void:
	var good := _day_two()
	good.advance_to(11 * 60 + 30)
	good.ask_colleague("bux")              ## genuinely unwell — he agrees
	good.set_disposition("bux", "hold")
	good.set_disposition("lomax", "hold")
	_rest_home(good)
	var beds := Contradictions.audit_beds(good.records.entries, good.review_truth(),
		good.review_findings())
	var backed := false
	for b in beds:
		if b.patient_id == "bux":
			backed = b.state == Contradictions.Defence.BACKED
	t.ok(backed, "a peer's opinion makes a bed something nobody can take apart")
	good.queue_free()

	# The same request about somebody who is well produces a PLAN, and reversing
	# a named doctor's plan is worse than reversing a nurse's observation.
	var bad := _day_two()
	bad.advance_to(11 * 60 + 30)
	var e := bad.ask_colleague("achebe_fry")
	t.ok(e != null and e.claim == ChartEntry.Claim.FIT_FOR_DISCHARGE,
		"about somebody who is well he writes a discharge plan, not an observation")
	bad.advance_to(12 * 60 + 30)
	bad.write_entry("achebe_fry", ChartEntry.Claim.UNWELL, "Unsettled.", 12 * 60 + 25)
	bad.set_disposition("achebe_fry", "hold")
	var peer_sev := 0.0
	for f in bad.review_findings():
		if f.kind == "reversed_a_colleague":
			peer_sev = f.severity
	bad.queue_free()

	var nurse := _day()                    ## ward one: Adeyemi's plan for Hal
	nurse.advance_to(15 * 60)
	nurse.write_entry("brennan", ChartEntry.Claim.UNWELL, "Wound warm.", 14 * 60 + 55)
	nurse.set_disposition("brennan", "hold")
	var nurse_sev := 0.0
	for f in nurse.review_findings():
		if f.kind == "reversed_a_colleague":
			nurse_sev = f.severity
	nurse.queue_free()
	t.gt(peer_sev, nurse_sev,
		"overturning an opinion you asked a doctor for costs more than overturning a nurse's plan (%.2f vs %.2f)"
			% [peer_sev, nurse_sev])
	GameState.day = 1

## She has a shift at four and she has asked three times.
func test_a_bed_with_a_clock_on_it() -> void:
	var w := _day_two()
	w.advance_to(17 * 60)
	t.eq(String(w.state["ferreira"]["disposition"]), "discharge",
		"a patient you never got to signs herself out")
	t.ok(bool(w.state["ferreira"]["self_discharged"]), "and the ward knows she did it herself")
	var last := ""
	for e in w.records.for_patient("ferreira"):
		last = e.text
	t.ok(last.contains("Self-discharged"), "and leaves a note you did not write")
	w.queue_free()

	# ...and getting to her in time is what stops it.
	var quick := _day_two()
	quick.set_disposition("ferreira", "discharge")
	quick.advance_to(17 * 60)
	t.ok(not bool(quick.state["ferreira"].get("self_discharged", false)),
		"deciding before four o'clock means she leaves as your decision, not hers")
	quick.queue_free()
	GameState.day = 1

## Forty-one years on Ward F. Winifred Blake's trap was on her file; this one
## reads the file herself.
func test_the_patient_who_reads_her_own_notes() -> void:
	var w := _day_two()
	w.advance_to(17 * 60 + 30)
	w.write_entry("voss", ChartEntry.Claim.UNWELL, "Unsettled this evening.", 17 * 60 + 25)
	w.set_disposition("voss", "hold")
	t.ok(_kinds(w.review_findings()).has("reads_own_chart"),
		"writing a symptom into the notes of somebody who reads them is a finding")
	w.queue_free()
	GameState.day = 1

## THE SECOND WARD'S PREMISE, pinned. Peter Lomax is not well, and every
## instrument that produces a piece of paper says he is. If the rounds announce
## him — as they did, at ten o'clock, before the player had left the office —
## then going to look at anybody is pointless and the examination is decoration.
func test_the_paperwork_cannot_find_him() -> void:
	var w := _day_two()
	w.advance_to(19 * 60)                  ## every round of the day has happened
	for e in w.records.for_patient("lomax"):
		t.ok(not e.supports_stay(),
			"nothing the ward writes about him says he should stay (%s)" % e.text)
	w.advance_to(11 * 60)
	w.nurse_check("lomax")
	var nurse_said_stay := false
	for e in w.records.for_patient("lomax"):
		if e.author == ChartEntry.Author.NURSE and e.supports_stay():
			nurse_said_stay = true
	t.ok(not nurse_said_stay, "asking Adeyemi to review him does not find it either — she scores him")
	var o := w.order_test("lomax", "bloods")
	var r := w.resolve_test(o)
	t.eq(int(r.claim), int(ChartEntry.Claim.RESULT_NORMAL),
		"and his bloods come back normal, because they would")
	w.queue_free()

	# ...and the two verbs that put somebody in front of him DO find it.
	var seen := _day_two()
	t.ok(seen.examine("lomax").length() > 20, "your own examination finds it")
	seen.advance_to(11 * 60 + 30)
	var peer := seen.ask_colleague("lomax")
	t.ok(peer != null and peer.supports_stay(),
		"and so does the registrar, because he sits down with him")
	seen.queue_free()
	GameState.day = 1

# ------------------------------------------------------ they come back
## THE CONSEQUENCE THE GAME DID NOT HAVE. Until this existed a discharge was
## free unless the ward sister happened to catch it in the morning: you sent a
## man home to make the money and he ceased to exist.
func test_the_man_you_sent_home_is_in_a_bed_in_the_morning() -> void:
	GameState.set_flag(Cases.READMIT_FLAG, [])
	var w := _day()
	w.set_disposition("marchetti", "discharge")   ## genuinely unwell, and you knew
	_rest_home(w)
	var res := w.end_day()
	t.ok(PackedStringArray(res["readmitted"]).has("marchetti"),
		"discharging somebody who was not fit to go brings them back")
	w.queue_free()

	GameState.day = 2
	var ids := []
	var readmitted := {}
	for c in Cases.roster():
		ids.append(String(c["id"]))
		if bool(c.get("readmitted", false)):
			readmitted[String(c["id"])] = c
	t.ok(ids.has("marchetti"), "he is on tomorrow's ward, which is not his ward")
	t.eq(ids.size(), Cases.BEDS, "and there are still only five beds")
	t.eq(readmitted.size(), 1, "one of them is a readmission")
	var m: Dictionary = readmitted["marchetti"]
	t.ok(not bool(m.get("truly_well", true)), "he is worse than he was")
	t.ok(m.has("audit_flag"), "and his file opens with the coding review on it")
	t.ok(String(m["opening"]) != String(Cases.anyone("marchetti")["opening"]),
		"and he has something new to say about it")

	# The displaced scheduled patient is simply not admitted — five beds is five.
	var scheduled := []
	for c in Cases.DAY_TWO:
		scheduled.append(String(c["id"]))
	var missing := 0
	for id in scheduled:
		if not ids.has(id):
			missing += 1
	t.eq(missing, 1, "and one scheduled admission does not happen")
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.day = 1

## Somebody who walked out against advice is not on your conscience, and neither
## is somebody who was genuinely well when you sent them home.
func test_not_every_discharge_comes_back() -> void:
	GameState.set_flag(Cases.READMIT_FLAG, [])
	var w := _day()
	w.set_disposition("marchetti", "hold")
	_rest_home(w)                                  ## four well people go home
	var res := w.end_day()
	t.eq(PackedStringArray(res["readmitted"]).size(), 0,
		"sending home four people who are well brings nobody back")
	w.queue_free()

	GameState.day = 2
	var q := _day_two()
	q.advance_to(17 * 60)                          ## Ferreira signs herself out
	q.set_disposition("lomax", "hold")
	q.set_disposition("bux", "hold")
	_rest_home(q)
	var res2 := q.end_day()
	t.ok(not PackedStringArray(res2["readmitted"]).has("ferreira"),
		"and a woman who signed herself out is not your readmission")
	q.queue_free()
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.day = 1

## A readmission does not bounce forever. Once round is the point being made.
func test_a_readmission_does_not_readmit() -> void:
	GameState.day = 2
	var w := _day_two()
	# Set AFTER the clean slate: `_day()` wipes the career, which is what every
	# other test wants and this one has to undo.
	GameState.set_flag(Cases.READMIT_FLAG, ["marchetti"])
	w.start()
	t.ok(bool(Cases.by_id("marchetti").get("readmitted", false)),
		"he is on the ward as a readmission")
	w.set_disposition("marchetti", "discharge")
	w.set_disposition("lomax", "hold")     ## he is on this ward too, and unwell
	_rest_home(w)
	var res := w.end_day()
	t.eq(PackedStringArray(res["readmitted"]).size(), 0,
		"sending him home again does not start it over")
	w.queue_free()
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.day = 1

# --------------------------------------------------------- the two endings
## Until this session the game had neither. `game_over` was a signal connected
## to a handler and emitted by nobody, and Vinnie asked for the same number on
## night seven as on night one.
func test_paying_it_off_is_the_way_out() -> void:
	GameState.reset_debt()
	DoctorRecord.wipe()
	t.eq(GameState.debt_remaining(), Cases.DEBT_TOTAL, "you start owing the whole thing")
	t.eq(GameState.ending(), "", "and the career is not over")
	GameState.pay_vinnie(Cases.DEBT_TOTAL - 100)
	t.eq(GameState.debt_remaining(), 100, "he takes what you hand him")
	t.eq(GameState.ending(), "", "and a hundred short is still short")
	GameState.pay_vinnie(100)
	t.eq(GameState.debt_remaining(), 0, "and then it is nothing")
	t.eq(GameState.ending(), GameState.ENDING_PAID, "which is the way out")
	GameState.reset_debt()

## A night that comes up short does not make tomorrow more expensive — it makes
## the whole thing longer, which is what falling behind to somebody like Vinnie
## actually does.
func test_a_short_night_lengthens_the_whole_thing() -> void:
	GameState.reset_debt()
	var w := _day()
	for c in Cases.roster():
		w.set_disposition(String(c["id"]), "discharge")
	var res := w.end_day()
	t.ok(bool(res["short"]), "sending the whole ward home does not cover the night")
	t.eq(GameState.debt_remaining(),
		Cases.DEBT_TOTAL - int(res["paid"]) + Cases.SHORTFALL_VIG,
		"and his interest goes on the total")
	t.eq(w.debt_tonight, Cases.DEBT_DUE, "he still wants his usual number, not more")
	w.queue_free()
	GameState.reset_debt()

## A bed you emptied by mistake earns you nothing all day. Without this the
## people who bounce back keep their insurance tier, so sending a premium
## patient home wrongly handed you a premium bed you could then hold entirely
## honestly — a mistake that PAID.
func test_a_readmitted_bed_is_not_reimbursed() -> void:
	GameState.set_flag(Cases.READMIT_FLAG, [])
	var normal := _day()
	normal.set_disposition("marchetti", "hold")
	_rest_home(normal)
	var full: int = int(normal.projected()["nights"])
	normal.queue_free()
	t.gt(float(full), 0.0, "an ordinary premium night is worth something (%d)" % full)

	GameState.day = 2
	var back := _day()
	GameState.set_flag(Cases.READMIT_FLAG, ["marchetti"])
	back.start()
	back.set_disposition("marchetti", "hold")
	_rest_home(back)
	t.eq(int(back.projected()["nights"]), 0,
		"the bed you emptied by mistake earns nothing at all")
	t.eq(back.night_value("marchetti"), 0, "and the ward says so by name")
	back.queue_free()
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.day = 1

## A ward is people you keep walking past. "Ask how they have been" returned the
## same sentence every time it was pressed, all day, forever — so every person
## in the game was four lines long and the third conversation was identical to
## the first.
func test_they_have_something_else_to_say_the_third_time() -> void:
	var w := _day()
	var said := {}
	for i in 3:
		said[w.what_they_say("oduya")] = true
	t.gt(float(said.size()), 1.0,
		"asking somebody three times gets more than one answer (%d distinct)" % said.size())

	# And what you have WRITTEN about them beats everything else they might say.
	# `_day()` frees the previous ward, so this reuses the one already open.
	w.advance_to(17 * 60)
	w.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 17 * 60)
	t.eq(w.what_they_say("oduya"), String(Cases.by_id("oduya")["on_your_note"]),
		"and once it is in the notes, that is what they want to talk about")
	w.queue_free()

	# Every authored patient has the middle, on both wards.
	for day in [1, 2]:
		for c in Cases.roster(day):
			for k in ["later", "evening", "pressed", "on_your_note"]:
				t.ok(c.has(k), "%s has something to say when %s" % [c["id"], k])
