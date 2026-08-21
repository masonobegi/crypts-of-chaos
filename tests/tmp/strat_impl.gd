extends RefCounted
var tree: SceneTree = null

func _day() -> WardDay:
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	return w

func _sev(f: Array) -> float:
	var t := 0.0
	for x in f: t += x.severity
	return t

func run() -> void:
	GameState.start_new_career(4242)
	var C := ChartEntry.Claim
	var rows: Array = []

	var strategies := {
		"1 lazy honest — discharge everyone": func(w):
			for c in Cases.ROSTER: w.set_disposition(String(c["id"]), "discharge"),

		"2 honest — hold only the unwell one": func(w):
			w.set_disposition("marchetti", "hold")
			for id in ["kerrigan","brennan","oduya","blake"]: w.set_disposition(id, "discharge"),

		"3 honest + mercy (keep Dot too)": func(w):
			w.set_disposition("marchetti", "hold"); w.set_disposition("kerrigan", "hold")
			for id in ["brennan","oduya","blake"]: w.set_disposition(id, "discharge"),

		"4 one fabrication, WELL timed": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(21*60+40)
			w.write_entry("oduya", C.UNWELL, "Reports transient dizziness on standing.", 21*60+35)
			w.set_disposition("oduya", "hold")
			for id in ["kerrigan","brennan","blake"]: w.set_disposition(id, "discharge"),

		"5 one fabrication, BADLY timed": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(9*60)
			w.write_entry("oduya", C.UNWELL, "Reports transient dizziness on standing.", 8*60+55)
			w.set_disposition("oduya", "hold")
			for id in ["kerrigan","brennan","blake"]: w.set_disposition(id, "discharge"),

		"6 fabricate then get the nurse to check": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(21*60)
			w.write_entry("oduya", C.UNWELL, "Reports dizziness on standing.", 20*60+55)
			w.advance_to(21*60+20); w.nurse_check("oduya")
			w.set_disposition("oduya", "hold")
			for id in ["kerrigan","brennan","blake"]: w.set_disposition(id, "discharge"),

		"7 nurse-check the GENUINELY unwell one (honest corroboration)": func(w):
			w.advance_to(14*60); w.nurse_check("marchetti")
			w.set_disposition("marchetti", "hold")
			for id in ["kerrigan","brennan","oduya","blake"]: w.set_disposition(id, "discharge"),

		"8 test-reliant cover-up": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(20*60)
			w.write_entry("oduya", C.UNWELL, "Reports dizziness on standing.", 19*60+55)
			var o = w.order_test("oduya", "lying and standing BP")
			w.advance_to(21*60); w.resolve_test(o)
			w.set_disposition("oduya", "hold")
			for id in ["kerrigan","brennan","blake"]: w.set_disposition(id, "discharge"),

		"9 full cleanup cascade": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(19*60+42)
			var a = w.write_entry("oduya", C.UNWELL, "Reports dizziness on standing.", 19*60+30)
			var o = w.order_test("oduya", "lying and standing BP")
			w.advance_to(21*60); w.resolve_test(o)
			w.advance_to(23*60+10)
			var b = w.write_entry("oduya", C.SETTLED, "BP unremarkable; symptoms positional.", 21*60, WardDay.TERMINAL_OFFICE, a.id)
			w.advance_to(23*60+40)
			w.write_entry("oduya", C.ADMIN, "Addendum timed late owing to workload.", 23*60+10, WardDay.TERMINAL_OFFICE, b.id)
			w.set_disposition("oduya", "hold")
			for id in ["kerrigan","brennan","blake"]: w.set_disposition(id, "discharge"),

		"10 lean on the confused patient (leading question)": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(19*60); w.ask_patient("kerrigan", "feeling faint this evening")
			w.set_disposition("kerrigan", "hold")
			for id in ["brennan","oduya","blake"]: w.set_disposition(id, "discharge"),

		"11 contradict a colleague (hold Hal)": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(15*60)
			w.write_entry("brennan", C.UNWELL, "Wound appears warm. Not for discharge today.", 14*60+55)
			w.set_disposition("brennan", "hold")
			for id in ["kerrigan","oduya","blake"]: w.set_disposition(id, "discharge"),

		"12 the money-optimal play (hold three)": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(21*60+30)
			w.write_entry("oduya", C.UNWELL, "Reports dizziness on standing.", 21*60+25)
			w.write_entry("brennan", C.UNWELL, "Wound warm to touch this evening.", 21*60+28)
			w.set_disposition("oduya", "hold"); w.set_disposition("brennan", "hold")
			for id in ["kerrigan","blake"]: w.set_disposition(id, "discharge"),

		"13 reckless greed — hold all five, fabricate all": func(w):
			w.advance_to(21*60)
			for id in ["kerrigan","brennan","oduya","blake"]:
				w.write_entry(id, C.UNWELL, "Unsettled this evening. For observation.", 20*60+55)
			for c in Cases.ROSTER: w.set_disposition(String(c["id"]), "hold"),

		"14 hold the flagged one (Winifred)": func(w):
			w.set_disposition("marchetti", "hold")
			w.advance_to(21*60)
			w.write_entry("blake", C.UNWELL, "Headache recurred this evening.", 20*60+55)
			w.set_disposition("blake", "hold")
			for id in ["kerrigan","brennan","oduya"]: w.set_disposition(id, "discharge"),
	}

	print("\n%-58s %6s %7s %5s %6s %s" % ["strategy","earned","cash","find","sev","outcome"])
	for name in strategies:
		var w := _day()
		(strategies[name] as Callable).call(w)
		w.advance_to(Cases.DEBT_DUE_MINUTE)
		var res: Dictionary = w.end_day()
		var f: Array = res["findings"]
		var sev := _sev(f)
		var verdict := "signed off"
		if sev > 2.5: verdict = "ESCALATED"
		elif sev > 1.4: verdict = "flagged"
		elif sev > 0.6: verdict = "questions"
		var short := "  SHORT" if bool(res["short"]) else ""
		print("%-58s %6d %7d %5d %6.2f  %s%s" % [name, res["earned"], res["cash"], f.size(), sev, verdict, short])
		rows.append({"n": name, "sev": sev, "cash": res["cash"], "f": f.size(),
			"tel": w.telemetry.size(), "short": res["short"]})
		w.queue_free()

	print("\n=== decision density (telemetry events per day) ===")
	for r in rows:
		print("  %-58s %d" % [r["n"], r["tel"]])
