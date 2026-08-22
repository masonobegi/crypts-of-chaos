extends RefCounted
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer
const IDS := ["marchetti","kerrigan","brennan","oduya","blake"]

func _best(rv: ReviewSystem, records, held: Array) -> float:
	if rv.finished():
		return float(rv.outcome()["unresolved"])
	var f = rv.current()
	var best := 99.0
	for o in rv.options(f, records):
		var a := rv.asked; var r := rv.resolved.duplicate(); var u := rv.used_answers.duplicate()
		var t := rv.transcript.duplicate(); var x := rv.extra.duplicate()
		rv.answer(int(o["a"]), held)
		best = minf(best, _best(rv, records, held))
		rv.asked = a; rv.resolved = r; rv.used_answers = u; rv.transcript = t; rv.extra = x
	return best

func _v(u: float) -> String:
	if u > 2.5: return "referred"
	if u > 1.4: return "flagged"
	if u > 0.6: return "noted"
	return "SIGNED OFF"

func _run(label: String, hold: Array, body: Callable) -> void:
	var w := WardDay.new(); tree.root.add_child(w); w.start()
	body.call(w)
	for pid in IDS:
		w.set_disposition(pid, "hold" if hold.has(pid) else "discharge")
	if w.minute < Cases.DEBT_DUE_MINUTE:
		w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	var fs: Array = res["findings"]
	var raw := 0.0; var names := PackedStringArray()
	for f in fs: raw += f.severity; names.append("%s=%.2f" % [f.kind, f.severity])
	var rv := ReviewSystem.new(); rv.begin(fs)
	# worst case (always STAND_BY) and best case (exhaustive)
	var best := _best(rv, w.records, res["held"])
	rv.begin(fs)
	while not rv.finished(): rv.answer(A.STAND_BY, res["held"])
	var naive := float(rv.outcome()["unresolved"])
	print("%-46s $%5d  raw %5.2f  naive %5.2f %-10s  BEST %5.2f %-10s | %s"
		% [label, int(res["cash"]), raw, naive, _v(naive), best, _v(best), ", ".join(names)])
	w.queue_free()

func run() -> void:
	GameState.start_new_career(31337)
	GameState.set_flag("headless_sim", true)
	print("\n%-46s %6s  %9s  %16s  %16s | findings" % ["PLAY","cash","raw sev","naive answers","best answers"])
	_run("A honest: hold Ivo only", ["marchetti"], func(w): pass)
	_run("B discharge everybody", [], func(w): pass)
	_run("C HOLD 3, WRITE NOTHING (max cash)", ["marchetti","oduya","brennan"], func(w): pass)
	_run("D hold 3, leave at 08:05 (no rounds)", ["marchetti","oduya","brennan"], func(w):
		w.minute = 8*60+5)
	_run("E hold 4, write nothing", ["marchetti","oduya","brennan","blake"], func(w): pass)
	_run("F hold all 5, write nothing", IDS, func(w): pass)
	_run("G ONE LIE: Ivo + Sam note @19:30", ["marchetti","oduya"], func(w):
		w.advance_to(19*60+30)
		w.write_entry("oduya", C.UNWELL, "Reports transient dizziness on standing.", 19*60+30))
	_run("H ONE LIE at 08:05 (before any round)", ["marchetti","oduya"], func(w):
		w.minute = 8*60+5
		w.write_entry("oduya", C.UNWELL, "Reports transient dizziness on standing.", 8*60+5))
	_run("I ONE LIE at 11:00 (mid-gap)", ["marchetti","oduya"], func(w):
		w.advance_to(11*60)
		w.write_entry("oduya", C.UNWELL, "Reports transient dizziness on standing.", 11*60))
	_run("J ONE LIE ON a round (14:00)", ["marchetti","oduya"], func(w):
		w.advance_to(14*60+10)
		w.write_entry("oduya", C.UNWELL, "Reports transient dizziness on standing.", 14*60+5))
	_run("K TWO LIES: Ivo+Sam+Hal notes @19:30", ["marchetti","oduya","brennan"], func(w):
		w.advance_to(19*60+30)
		w.write_entry("oduya", C.UNWELL, "Dizzy on standing.", 19*60+30)
		w.write_entry("brennan", C.UNWELL, "Wound warm this evening.", 19*60+30))
	_run("L TWO LIES early: notes at 08:05", ["marchetti","oduya","brennan"], func(w):
		w.minute = 8*60+5
		w.write_entry("oduya", C.UNWELL, "Dizzy on standing.", 8*60+5)
		w.write_entry("brennan", C.UNWELL, "Wound warm.", 8*60+5))
	_run("M lead Sam + lead Hal (patient-authored)", ["marchetti","oduya","brennan"], func(w):
		w.advance_to(11*60)
		w.ask_patient("oduya","feeling faint"); w.ask_patient("brennan","feeling faint"))
	_run("N mercy Dot documented (SOCIAL @11)", ["marchetti","kerrigan"], func(w):
		w.advance_to(11*60)
		w.write_entry("kerrigan", C.SOCIAL, "No care at home.", 11*60))
	_run("O mercy Dot UNDOCUMENTED", ["marchetti","kerrigan"], func(w): pass)
	_run("P hold Blake (flagged file) + note", ["marchetti","blake"], func(w):
		w.advance_to(11*60)
		w.write_entry("blake", C.UNWELL, "Headache recurred.", 11*60))
	_run("Q max cash + Dot social too (hold 4)", ["marchetti","oduya","brennan","kerrigan"], func(w):
		w.advance_to(11*60)
		w.write_entry("oduya", C.UNWELL, "Dizzy on standing.", 11*60)
		w.write_entry("kerrigan", C.SOCIAL, "No care at home.", 11*60))
