extends RefCounted
## Twenty ways of playing one day, measured against the six criteria in
## docs/REDESIGN.md. Development only. The point is evidence rather than vibes.
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer
var failed := false

func _day() -> WardDay:
	# Each strategy is DAY ONE. Without clearing the carry, run 5's uncorroborated
	# bed lands on run 6's file and every later measurement is really measuring
	# the runs above it in the list.
	GameState.set_flag("remembered_beds", PackedStringArray())
	var w := WardDay.new(); tree.root.add_child(w); w.start(); return w

func _sev(f: Array) -> float:
	var s := 0.0
	for x in f: s += x.severity
	return s

func _discharge_rest(w: WardDay, keep: Array) -> void:
	for c in Cases.ROSTER:
		var id := String(c["id"])
		if not keep.has(id):
			w.set_disposition(id, "discharge")

## A run: play the day, then hold the review, and report everything.
func _play(name: String, play: Callable, answer: Callable) -> Dictionary:
	var w := _day()
	# EVERY strategy starts by reading the ward, because every strategy has to:
	# the roster tells you nothing about who is actually unwell. This is the
	# honest day's real content and it costs an hour of the shift.
	for c in Cases.ROSTER:
		w.read_chart(String(c["id"]))
	play.call(w)
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	var findings: Array = res["findings"]
	var rv := ReviewSystem.new()
	rv.begin(findings, w.records.entries, w.review_truth())
	var qs: Array = []
	while not rv.finished():
		var f = rv.current()
		qs.append(f.kind)
		rv.answer(int(answer.call(f, rv.options(f, w.records))), res["held"])
	var out := rv.outcome()
	var beds := "%d bed(s): %d indefensible, %d on your word alone" % [
		int(out["beds"]), int(out["indefensible"]), int(out["solo"])]
	var fabrications := 0
	# A DECISION is something the player elected to do, not something the ward
	# did to them. Rounds, Ruth and the bookends are the day happening; writes,
	# leading questions, nurse checks, orders and dispositions are the day being
	# played. Only the second kind counts towards decision density.
	const CHOSEN := ["write", "ask_patient", "nurse_check", "order_test",
		"test_result", "disposition", "read_chart"]
	var decisions := 0
	for e in w.telemetry:
		var k := String(e.get("kind", ""))
		if k == "write" and bool(e.get("supports_stay", false)):
			fabrications += 1
		if CHOSEN.has(k):
			decisions += 1
	var row := {
		"name": name, "cash": int(res["cash"]), "short": bool(res["short"]),
		"findings": findings.size(), "sev": _sev(findings),
		"verdict": String(out["verdict"]), "beds": beds,
		"indefensible": int(out["indefensible"]), "solo": int(out["solo"]),
		"because": String(out["because"]), "questions": qs,
		"fabrications": fabrications, "actions": w.telemetry.size(),
		"decisions": decisions,
		"entries": w.records.entries.size(),
	}
	w.queue_free()
	return row

func run() -> void:
	GameState.start_new_career(31337)
	var stand := func(_f, _o): return A.STAND_BY
	var smart := func(_f, opts):
		for o in opts:
			if int(o["a"]) == A.RECONCILE: return A.RECONCILE
		for o in opts:
			if int(o["a"]) == A.POINT_AT_NURSE: return A.POINT_AT_NURSE
			if int(o["a"]) == A.WROTE_IT_LATE: return A.WROTE_IT_LATE
		return A.STAND_BY
	var fold := func(_f, _o): return A.DEFER

	var runs: Array = []
	var S := [
		["01 honest — hold only the unwell man", func(w):
			w.set_disposition("marchetti","hold"); _discharge_rest(w,["marchetti"]), stand],
		["02 honest + mercy for Dot", func(w):
			w.set_disposition("marchetti","hold"); w.set_disposition("kerrigan","hold")
			_discharge_rest(w,["marchetti","kerrigan"]), stand],
		["02b mercy for Dot, documented honestly", func(w):
			w.set_disposition("marchetti","hold")
			w.advance_to(17*60)
			w.write_entry("kerrigan", C.SOCIAL, "No care at home. Awaiting social work review.", 17*60)
			w.set_disposition("kerrigan","hold")
			_discharge_rest(w,["marchetti","kerrigan"]), stand],
		["03 honest + nurse corroboration", func(w):
			w.advance_to(14*60+20); w.nurse_check("marchetti")
			w.set_disposition("marchetti","hold"); _discharge_rest(w,["marchetti"]), stand],
		["04 discharge everybody", func(w): _discharge_rest(w,[]), stand],
		["05 one lie, in the gap", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(17*60+30)
			w.write_entry("oduya",C.UNWELL,"Reports transient dizziness on standing.",17*60+25)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), stand],
		["06 one lie, on top of the round", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(19*60+5)
			w.write_entry("oduya",C.UNWELL,"Reports transient dizziness on standing.",19*60)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), stand],
		["07 one lie, badly timed, played well", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(19*60+5)
			w.write_entry("oduya",C.UNWELL,"Reports transient dizziness on standing.",19*60)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), smart],
		["08 lie then order a test LATE", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(15*60+30)
			w.write_entry("oduya",C.UNWELL,"Reports dizziness.",15*60+25)
			var o=w.order_test("oduya","lying and standing BP")
			w.advance_to(17*60+45); w.resolve_test(o)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), smart],
		["09 lie then order a test IMMEDIATELY", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(15*60+30)
			w.write_entry("oduya",C.UNWELL,"Reports dizziness.",15*60+25)
			var o=w.order_test("oduya","lying and standing BP")
			w.advance_to(15*60+45); w.resolve_test(o)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), smart],
		["10 full cleanup cascade", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(16*60+42)
			var a=w.write_entry("oduya",C.UNWELL,"Reports dizziness.",16*60+30)
			var o=w.order_test("oduya","lying and standing BP")
			w.advance_to(18*60); w.resolve_test(o)
			w.advance_to(18*60+40)
			var b=w.write_entry("oduya",C.SETTLED,"BP unremarkable; symptoms positional.",18*60,WardDay.TERMINAL_OFFICE,a.id)
			w.advance_to(19*60+10)
			w.write_entry("oduya",C.ADMIN,"Addendum timed late.",18*60+40,WardDay.TERMINAL_OFFICE,b.id)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), stand],
		["11 cascade, then talk well", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(16*60+42)
			var a=w.write_entry("oduya",C.UNWELL,"Reports dizziness.",16*60+30)
			var o=w.order_test("oduya","lying and standing BP")
			w.advance_to(18*60); w.resolve_test(o)
			w.advance_to(18*60+40)
			w.write_entry("oduya",C.SETTLED,"BP unremarkable; symptoms positional.",18*60,WardDay.TERMINAL_OFFICE,a.id)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), smart],
		["12 lean on the confused woman", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(17*60)
			w.ask_patient("kerrigan","feeling faint this evening")
			w.set_disposition("kerrigan","hold"); _discharge_rest(w,["marchetti","kerrigan"]), stand],
		["13 lean on the frightened man", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(17*60+20)
			w.ask_patient("oduya","feeling faint this evening")
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), stand],
		["14 reverse Adeyemi on Hal", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(15*60)
			w.write_entry("brennan",C.UNWELL,"Wound warm. Not for discharge today.",14*60+50)
			w.set_disposition("brennan","hold"); _discharge_rest(w,["marchetti","brennan"]), stand],
		["15 hold the flagged woman", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(17*60+30)
			w.write_entry("blake",C.UNWELL,"Headache recurred this evening.",17*60+25)
			w.set_disposition("blake","hold"); _discharge_rest(w,["marchetti","blake"]), stand],
		["16 money-optimal: hold three", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(17*60+30)
			w.write_entry("oduya",C.UNWELL,"Reports dizziness.",17*60+25)
			w.write_entry("brennan",C.UNWELL,"Wound warm this evening.",17*60+28)
			w.set_disposition("oduya","hold"); w.set_disposition("brennan","hold")
			_discharge_rest(w,["marchetti","oduya","brennan"]), stand],
		["17 greed: hold all five", func(w):
			w.advance_to(17*60+30)
			for id in ["kerrigan","brennan","oduya","blake"]:
				w.write_entry(id,C.UNWELL,"Unsettled this evening.",17*60+25)
			for c in Cases.ROSTER: w.set_disposition(String(c["id"]),"hold"), stand],
		["18 backdating-heavy", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(19*60+45)
			w.write_entry("oduya",C.UNWELL,"Reports dizziness.",16*60)
			w.write_entry("brennan",C.UNWELL,"Wound warm.",15*60+30)
			w.set_disposition("oduya","hold"); w.set_disposition("brennan","hold")
			_discharge_rest(w,["marchetti","oduya","brennan"]), stand],
		["19 nurse-reliant on a well patient", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(17*60+30)
			w.write_entry("oduya",C.UNWELL,"Reports dizziness.",17*60+25)
			w.advance_to(17*60+50); w.nurse_check("oduya")
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), stand],
		["21 sign off at 08:05 and go home", func(w):
			for id in ["marchetti","oduya","brennan"]: w.set_disposition(id,"hold")
			_discharge_rest(w,["marchetti","oduya","brennan"]), stand],
		["22 the same, with a note on each first", func(w):
			w.write_entry("oduya",C.UNWELL,"Unsettled overnight.",8*60)
			w.write_entry("brennan",C.UNWELL,"Wound warm.",8*60+5)
			for id in ["marchetti","oduya","brennan"]: w.set_disposition(id,"hold")
			_discharge_rest(w,["marchetti","oduya","brennan"]), smart],
		["20 fold under questioning", func(w):
			w.set_disposition("marchetti","hold"); w.advance_to(19*60+5)
			w.write_entry("oduya",C.UNWELL,"Reports dizziness.",19*60)
			w.set_disposition("oduya","hold"); _discharge_rest(w,["marchetti","oduya"]), fold],
	]
	for s in S:
		runs.append(_play(String(s[0]), s[1], s[2]))

	print("\n%-42s %6s %5s %5s %-18s %s" % ["run","cash","fab","find","verdict","beds"])
	for r in runs:
		print("%-42s %6d %5d %5d %-18s %s" % [r["name"], r["cash"], r["fabrications"],
			r["findings"], r["verdict"], r["beds"]])

	var passed := _criteria(runs)

	# The risk/reward frontier: more money must cost more exposure.
	print("\n=== is there a real frontier? (cash against unresolved severity) ===")
	var sorted_runs := runs.duplicate()
	sorted_runs.sort_custom(func(a, b): return int(a["cash"]) < int(b["cash"]))
	for r in sorted_runs:
		print("  %6d   %-18s %s" % [r["cash"], r["verdict"], r["name"]])

	print("")
	if passed:
		print("PLAYTEST PASSED — all six criteria met")
	else:
		print("PLAYTEST FAILED — a success criterion regressed")
	failed = not passed

## Returns false if any criterion failed, so the harness can exit non-zero and
## a regression in the design shows up in run_tests.sh rather than in a report
## nobody reads.
func _criteria(runs: Array) -> bool:
	print("\n================ SUCCESS CRITERIA ================")
	var all_pass := true

	# 1. DECISION DENSITY — is a day eight real choices, or a formality?
	#
	# Counted over the verbs the player drives, and judged on the runs that
	# WORKED: cleared the debt and came out of the review no worse than noted.
	# Measuring every run punishes the harness for containing deliberately
	# degenerate strategies — "discharge all five" is five clicks by design,
	# and the game answering it with an unpayable debt is the system working,
	# not a shallow day. What must be true is the sharper claim: there is no
	# five-click way to WIN. If a thin run ever succeeds, the day is a
	# formality and this fails.
	var total_dec := 0
	var thin: Array = []
	var won: Array = []
	for r in runs:
		total_dec += int(r["decisions"])
		var ok: bool = not bool(r["short"]) and (
			String(r["verdict"]) == ReviewSystem.OUTCOME_CLEAR
			or String(r["verdict"]) == ReviewSystem.OUTCOME_QUESTIONS)
		if not ok:
			continue
		won.append(r)
		if int(r["decisions"]) < 8:
			thin.append("%s (%d)" % [String(r["name"]), int(r["decisions"])])
	var least := 999
	for r in won:
		least = mini(least, int(r["decisions"]))
	var mean_dec := float(total_dec) / float(maxi(1, runs.size()))
	var dense: bool = not won.is_empty() and thin.is_empty()
	all_pass = all_pass and dense
	print("1 DECISIONS       %.1f per run; %d runs came out solvent and unflagged, thinnest %d   %s"
		% [mean_dec, won.size(), least if not won.is_empty() else 0,
			"PASS" if dense else "FAIL"])
	if not thin.is_empty():
		print("                  won on under 8 decisions: %s" % ", ".join(PackedStringArray(thin)))

	# 2. DIVERGENCE — do different plays produce different reviews?
	#
	# Measured twice on purpose. The raw figure counts every honest run's empty
	# review as a collision, which penalises the game for correctly declining to
	# interrogate somebody who did nothing — three clean days SHOULD produce
	# three identical silences. The meaningful number is whether days that gave
	# the reviewer something to work with gave her DIFFERENT things.
	var sigs := {}
	var dirty_sigs := {}
	var dirty := 0
	for r in runs:
		var sig := "%s|%s" % [",".join(PackedStringArray(r["questions"])), r["verdict"]]
		sigs[sig] = true
		if int(r["findings"]) > 0:
			dirty += 1
			dirty_sigs[sig] = true
	var div := float(sigs.size()) / float(runs.size())
	var ddiv := float(dirty_sigs.size()) / float(maxi(1, dirty))
	print("2 DIVERGENCE      all runs:      %d shapes / %d runs = %.0f%%"
		% [sigs.size(), runs.size(), div * 100.0])
	print("                  runs with findings: %d shapes / %d = %.0f%%   %s"
		% [dirty_sigs.size(), dirty, ddiv * 100.0, "PASS" if ddiv >= 0.8 else "FAIL"])
	all_pass = all_pass and ddiv >= 0.8

	# 3. LIES CREATE DEBT — does a fabrication bring friends?
	var dishonest: Array = []
	for r in runs:
		if int(r["fabrications"]) > 0:
			dishonest.append(r)
	var compounded := 0
	for r in dishonest:
		if int(r["findings"]) >= int(r["fabrications"]) * 2:
			compounded += 1
	var rate := float(compounded) / float(maxi(1, dishonest.size()))
	print("3 LIES COMPOUND   %d of %d dishonest runs produced >=2 findings per lie = %.0f%%   %s"
		% [compounded, dishonest.size(), rate * 100.0, "PASS" if rate >= 0.7 else "FAIL"])
	all_pass = all_pass and rate >= 0.7

	# 4. LEGIBILITY — does every bad outcome name its cause?
	var legible := 0
	var bad := 0
	for r in runs:
		if String(r["verdict"]) == ReviewSystem.OUTCOME_CLEAR:
			continue
		bad += 1
		if String(r["because"]).length() > 25:
			legible += 1
	print("4 LEGIBLE FAILURE %d of %d non-clear runs named the line that did it   %s"
		% [legible, bad, "PASS" if legible == bad else "FAIL"])
	all_pass = all_pass and legible == bad

	# 5. HONEST VIABLE — and does it demand something?
	var honest_ok := true
	for r in runs:
		if int(r["fabrications"]) == 0 and String(r["name"]).begins_with("01"):
			honest_ok = not bool(r["short"]) and String(r["verdict"]) == ReviewSystem.OUTCOME_CLEAR
	print("5 HONEST VIABLE   an honest day pays the debt and is signed off   %s"
		% ["PASS" if honest_ok else "FAIL"])
	all_pass = all_pass and honest_ok

	# 6. A SECOND DAY IS A DIFFERENT DAY.
	#
	# Whether a human comes back is not something a harness can answer. What it
	# CAN answer is whether there would be anything new if they did — and the
	# criterion is worthless without that. Tomorrow after a flag has Adeyemi
	# rounding twice as often, which is the same ward with half the gaps in it,
	# so the identical dishonest play must land harder than it did today.
	all_pass = _second_day() and all_pass
	return all_pass

## The same fabrication, played twice: once on a quiet ward, once on one that is
## already being looked at.
func _second_day() -> bool:
	var play := func(w: WardDay):
		w.advance_to(17 * 60 + 30)
		w.write_entry("oduya", C.UNWELL, "Reports dizziness on standing.", 17 * 60 + 25)
		w.set_disposition("oduya", "hold")
		w.set_disposition("marchetti", "hold")
		_discharge_rest(w, ["oduya", "marchetti"])

	GameState.set_flag("watched", false)
	var quiet := _day(); play.call(quiet)
	var quiet_rounds: int = quiet.rounds_today().size()
	var quiet_sev := _sev(quiet.review_findings())
	quiet.queue_free()

	GameState.set_flag("watched", true)
	GameState.set_flag("carried_debt", 400)
	var watched := _day(); play.call(watched)
	var watched_rounds: int = watched.rounds_today().size()
	var watched_sev := _sev(watched.review_findings())
	var owed: int = watched.debt_tonight
	watched.queue_free()
	GameState.set_flag("watched", false)
	GameState.set_flag("carried_debt", 0)

	var harder: bool = watched_rounds > quiet_rounds and watched_sev > quiet_sev \
		and owed > Cases.DEBT_DUE
	print("6 A SECOND DAY    rounds %d -> %d, same lie costs %.2f -> %.2f, owed %d -> %d   %s"
		% [quiet_rounds, watched_rounds, quiet_sev, watched_sev, Cases.DEBT_DUE, owed,
			"PASS" if harder else "FAIL"])
	return harder


