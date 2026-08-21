extends RefCounted
var tree: SceneTree = null

func _day() -> WardDay:
	var w := WardDay.new(); tree.root.add_child(w); w.start(); return w

func _cascade(w: WardDay) -> void:
	var C := ChartEntry.Claim
	w.set_disposition("marchetti", "hold")
	w.advance_to(19*60+42)
	var a = w.write_entry("oduya", C.UNWELL, "Reports dizziness on standing.", 19*60+30)
	var o = w.order_test("oduya", "lying and standing BP")
	w.advance_to(21*60+30); w.resolve_test(o)
	w.advance_to(23*60+10)
	w.write_entry("oduya", C.SETTLED, "BP unremarkable; symptoms positional.", 21*60, WardDay.TERMINAL_OFFICE, a.id)
	w.set_disposition("oduya", "hold")
	for id in ["kerrigan","brennan","blake"]: w.set_disposition(id, "discharge")

func _run_review(label: String, picker: Callable) -> void:
	var w := _day()
	_cascade(w)
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	var rv := ReviewSystem.new()
	rv.begin(res["findings"])
	var held: Array = res["held"]
	print("\n--- %s ---" % label)
	var n := 0
	while not rv.finished():
		var f = rv.current()
		var opts: Array = rv.options(f, w.records)
		var choice: int = picker.call(f, opts, n)
		print("  Q: %s" % f.question)
		var r := rv.answer(choice, held)
		print("     -> [%s] %s  %s" % [
			["stand by","wrote it late","defer","point at nurse","blame system","reconcile"][choice],
			r["effect"], "(cleared)" if r["cleared"] else ""])
		n += 1
	var o := rv.outcome()
	print("  VERDICT: %s   unresolved %.2f   she created %d new problems in the room" % [
		o["verdict"], o["unresolved"], o["created"]])
	print("  BECAUSE: %s" % o["because"])
	print("  %s" % ReviewSystem.closing(o["verdict"]))
	w.queue_free()

func run() -> void:
	GameState.start_new_career(4242)
	var A := ReviewSystem.Answer
	_run_review("A: stand behind everything", func(f, opts, n): return A.STAND_BY)
	_run_review("B: defer on everything (abandon the story)", func(f, opts, n): return A.DEFER)
	_run_review("C: blame the clocks every time", func(f, opts, n): return A.BLAME_SYSTEM)
	_run_review("D: play it well (reconcile where the day supports it)",
		func(f, opts, n):
			for o in opts:
				if o["a"] == A.RECONCILE: return A.RECONCILE
			for o in opts:
				if o["a"] == A.POINT_AT_NURSE: return A.POINT_AT_NURSE
				if o["a"] == A.WROTE_IT_LATE: return A.WROTE_IT_LATE
			return A.STAND_BY)
