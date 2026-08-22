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
	var best := _best(rv, w.records, res["held"])
	print("%-52s $%5d  raw %5.2f  BEST %5.2f %-11s | %s"
		% [label, int(res["cash"]), raw, best, _v(best), ", ".join(names)])
	w.queue_free()

## press the leading question until they agree (it re-rolls every press, free)
func _spam(w: WardDay, pid: String, tries := 30) -> int:
	for i in tries:
		if w.ask_patient(pid, "feeling faint") != null:
			return i + 1
	return -1

func run() -> void:
	for s in [31337, 4242, 99, 7]:
		GameState.start_new_career(s)
		GameState.set_flag("headless_sim", true)
		print("\n---- seed %d ----" % s)
		_run("R hold3: write Sam @08:00, LEAD Hal @08:00", ["marchetti","oduya","brennan"], func(w):
			w.write_entry("oduya", C.UNWELL, "Dizzy on standing.", 8*60)
			_spam(w, "brennan"))
		_run("S hold3: LEAD Sam @08:00, write Hal @08:00", ["marchetti","oduya","brennan"], func(w):
			_spam(w, "oduya")
			w.write_entry("brennan", C.UNWELL, "Wound warm.", 8*60))
		_run("T hold3: LEAD both @08:00 (spam)", ["marchetti","oduya","brennan"], func(w):
			_spam(w, "oduya"); _spam(w, "brennan"))
		_run("U hold3: write both @08:00 (baseline)", ["marchetti","oduya","brennan"], func(w):
			w.write_entry("oduya", C.UNWELL, "Dizzy on standing.", 8*60)
			w.write_entry("brennan", C.UNWELL, "Wound warm.", 8*60))
		_run("V hold3: write Sam@08:00 only, Hal nothing", ["marchetti","oduya","brennan"], func(w):
			w.write_entry("oduya", C.UNWELL, "Dizzy on standing.", 8*60))
		_run("W hold3: SOCIAL on Sam+Hal @08:00", ["marchetti","oduya","brennan"], func(w):
			w.write_entry("oduya", C.SOCIAL, "No care at home.", 8*60)
			w.write_entry("brennan", C.SOCIAL, "No care at home.", 8*60))
