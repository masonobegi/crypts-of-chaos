extends RefCounted
## Does one lie compound, or merely accumulate?
var _n := 0

func _e(pid, claim, text, stated, written, author, aid := "", term := "ward_term", explains := "") -> ChartEntry:
	_n += 1
	var e := ChartEntry.new()
	e.id = "e%d" % _n
	e.patient_id = pid
	e.claim = claim
	e.text = text
	e.stated_minute = stated
	e.written_minute = written
	e.author = author
	e.author_id = aid if aid != "" else ("player" if author == ChartEntry.Author.YOU else "adeyemi")
	e.terminal_id = term
	e.explains = explains
	return e

func run() -> void:
	var C := ChartEntry.Claim
	var A := ChartEntry.Author
	var pid := "sam"
	var entries: Array = []
	var truth := {"sam": {"well": true, "held": true, "patient_recalls": []}}
	var placements := {}

	print("\n=== ONE LIE, STEP BY STEP (Sam Oduya) ===")
	print("%-4s %-46s %6s %6s %s" % ["step", "player action", "finds", "worst", "total severity"])

	var steps := [
		["baseline: nurse round, patient well", func():
			entries.append(_e(pid, C.MOBILISING, "Comfortable. Mobilising independently.", 19*60+55, 19*60+58, A.NURSE))],
		["you write dizziness at 19:30", func():
			entries.append(_e(pid, C.UNWELL, "Reports transient dizziness on standing.", 19*60+30, 19*60+42, A.YOU))],
		["you ask the nurse to re-check him", func():
			entries.append(_e(pid, C.SETTLED, "Reviewed at doctor's request. Settled, no dizziness.", 20*60+10, 20*60+12, A.NURSE))],
		["you order a lying/standing BP", func():
			var o := _e(pid, C.ORDER, "Lying and standing BP requested.", 20*60+30, 20*60+30, A.YOU)
			o.order_kind = "lying and standing BP"
			entries.append(o)],
		["...and it comes back normal", func():
			entries[entries.size()-1].fulfilled_by = "m1"
			var r := _e(pid, C.RESULT_NORMAL, "Lying/standing BP within normal limits.", 21*60, 21*60, A.MACHINE)
			r.id = "m1"
			entries.append(r)],
		["you backdate an addendum explaining it", func():
			entries.append(_e(pid, C.SETTLED, "BP unremarkable; symptoms positional and transient.", 21*60, 23*60+10, A.YOU, "", "office_term", "e2"))],
		["you add a note explaining the addendum", func():
			entries.append(_e(pid, C.ADMIN, "Addendum timed late owing to ward workload.", 23*60+10, 23*60+40, A.YOU, "", "office_term", "e6"))],
	]

	var prev_total := 0.0
	var i := 0
	for s in steps:
		i += 1
		(s[1] as Callable).call()
		var finds: Array = Contradictions.find_all(entries, truth, placements)
		var total := 0.0
		var worst := 0.0
		for f in finds:
			total += f.severity
			worst = maxf(worst, f.severity)
		var delta := total - prev_total
		print("%-4d %-46s %6d %6.2f   %.2f  (+%.2f)" % [i, String(s[0]), finds.size(), worst, total, delta])
		prev_total = total

	print("\n=== WHAT SHE ASKS, at the end ===")
	var finds: Array = Contradictions.find_all(entries, truth, placements)
	for f in finds:
		print("  [%.2f x%d] %s" % [f.severity, f.compounded, f.kind])
		print("        Q: %s" % f.question)

	print("\n=== CONTROL A: a WELL-TIMED lie (no nurse round nearby) ===")
	var e3: Array = [
		_e(pid, C.MOBILISING, "Comfortable. Mobilising independently.", 19*60+55, 19*60+58, A.NURSE),
		_e(pid, C.UNWELL, "Reports transient dizziness on standing.", 21*60+40, 21*60+45, A.YOU),
	]
	var f3: Array = Contradictions.find_all(e3, truth, placements)
	var t3 := 0.0
	for f in f3: t3 += f.severity
	print("  lie placed away from the round: %d findings, total %.2f" % [f3.size(), t3])
	for f in f3: print("     - %s %.2f" % [f.kind, f.severity])

	print("\n=== CONTROL B: the same lie, never patched ===")
	var e2: Array = [entries[0], entries[1]]
	var f2: Array = Contradictions.find_all(e2, truth, placements)
	var t2 := 0.0
	for f in f2: t2 += f.severity
	print("  unpatched lie: %d findings, total severity %.2f" % [f2.size(), t2])
	print("  patched lie:   %d findings, total severity %.2f" % [finds.size(), prev_total])
