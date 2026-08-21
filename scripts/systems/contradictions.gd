class_name Contradictions
extends RefCounted
## The reviewer's entire brain, and the thing the whole redesign is betting on.
##
## There is no suspicion die. A question gets asked because two specific pieces
## of the world cannot both be true, and the player can read the same chart the
## reviewer reads. Getting caught is therefore always explicable after the fact:
## THIS entry against THAT observation, at THIS time, seen by THAT person.
##
## THE HYPOTHESIS THIS FILE EXISTS TO TEST: that lies COMPOUND rather than
## merely accumulate. The mechanism is deliberate and threefold —
##
##   1. Every fix is itself an entry, so patching a hole digs a new one.
##   2. Severity is raised for entries that already appear in another finding,
##      so the second question about the same line is worse than the first.
##   3. A stay has to be justified AT THE MOMENT IT IS BILLED. An addendum that
##      says the patient was fine by nine o'clock does not just sit there: it
##      retroactively removes the reason they were still in the bed at ten.
##
## If those three do not produce escalation in play, the design is wrong and the
## document gets changed, not the measurements.
##
## REBALANCED AFTER THE FIRST MEASUREMENT. The initial severities made a single
## fabricated note produce three findings at maximum severity, which meant there
## was no such thing as a small lie and nothing to escalate from — the second
## and third steps of a deception added literally nothing because everything had
## already saturated. Wards run on discrepancies; one is ordinary, and the game
## is only interesting if a player can tell a small lie and live with it. The
## numbers now treat a lone disagreement as noise and let the PATTERN convict.

class Finding extends RefCounted:
	var kind: String = ""
	var patient_id: String = ""
	var entries: PackedStringArray = PackedStringArray()
	var severity: float = 0.0
	var axis: String = ""        ## what the reviewer was looking at when she found it
	var question: String = ""    ## what she actually says
	var because: String = ""     ## the causal line, for the player, afterwards
	var compounded := 0          ## how many other findings share an entry with this

	func label() -> String:
		return "%s (%.2f)" % [kind, severity]

# ---------------------------------------------------------------- detection
## `truth` maps patient_id -> {well: bool, held: bool, patient_recalls: Array[String]}
## `placements` maps "actor|minute_bucket" -> room, from what witnesses saw.
static func find_all(entries: Array, truth: Dictionary, placements: Dictionary) -> Array:
	var out: Array = []
	var by_patient := {}
	for e in entries:
		var pid: String = e.patient_id
		if not by_patient.has(pid):
			by_patient[pid] = []
		by_patient[pid].append(e)

	for pid in by_patient:
		var list: Array = by_patient[pid]
		list.sort_custom(func(a, b): return a.stated_minute < b.stated_minute)
		var t: Dictionary = truth.get(pid, {})
		out.append_array(_conflicting_observations(pid, list))
		out.append_array(_backdating(pid, list))
		out.append_array(_author_elsewhere(pid, list, placements))
		out.append_array(_patient_no_recall(pid, list, t))
		out.append_array(_unfulfilled_orders(pid, list))
		out.append_array(_objective_refutes(pid, list))
		if bool(t.get("held", false)):
			out.append_array(_justification_undermined(pid, list))
			out.append_array(_uncorroborated_stay(pid, list, t))
		out.append_array(_reversed_a_colleague(pid, list))
		out.append_array(_addendum_cascade(pid, list))

	out.append_array(pattern_findings(entries, truth))
	# A file already marked for review is read by somebody whose eyes are open.
	# The player can find this out; it is written on the record. They have to go
	# and look, which is the only reason the flag is interesting.
	for f in out:
		if f.patient_id != "" and bool(truth.get(f.patient_id, {}).get("flagged", false)):
			f.severity = minf(0.98, f.severity * 1.6)
			f.axis = "%s (file already under review)" % f.axis
	_compound(out)
	out.sort_custom(func(a, b): return a.severity > b.severity)
	return out

## Two entries about the same half hour that argue opposite ways.
static func _conflicting_observations(pid: String, list: Array) -> Array:
	var out: Array = []
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a = list[i]
			var b = list[j]
			if not a.concerns_same_moment_as(b):
				continue
			if not ((a.supports_stay() and b.supports_discharge())
					or (a.supports_discharge() and b.supports_stay())):
				continue
			var f := Finding.new()
			f.kind = "conflicting_observations"
			f.patient_id = pid
			f.entries = PackedStringArray([a.id, b.id])
			f.axis = "the timeline"
			# Two people disagreeing is worse than one person disagreeing with
			# themselves — a second author is a second memory to manage.
			f.severity = 0.45 if a.author != b.author else 0.30
			f.question = "You've got %s at %s. %s has %s at %s. Walk me through that." % [
				_short(a), ChartEntry._hhmm(a.stated_minute),
				b.author_label().capitalize(), _short(b),
				ChartEntry._hhmm(b.stated_minute)]
			f.because = "%s and %s describe the same half hour and disagree." % [
				_short(a), _short(b)]
			out.append(f)
	return out

## Written long after the moment it describes.
static func _backdating(pid: String, list: Array) -> Array:
	var out: Array = []
	for e in list:
		if e.author != ChartEntry.Author.YOU or not e.is_backdated():
			continue
		var late: int = e.backdated_by()
		var f := Finding.new()
		f.kind = "backdated"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "entry metadata"
		f.severity = clampf(0.10 + float(late) / 400.0, 0.10, 0.45)
		f.question = "This note is timed %s but you wrote it at %s. Why the gap?" % [
			ChartEntry._hhmm(e.stated_minute), ChartEntry._hhmm(e.written_minute)]
		f.because = "%s was written %d minutes after it says it happened." % [_short(e), late]
		out.append(f)
	return out

## You cannot have observed it from another room.
static func _author_elsewhere(pid: String, list: Array, placements: Dictionary) -> Array:
	var out: Array = []
	for e in list:
		if e.author != ChartEntry.Author.YOU:
			continue
		var key := "player|%d" % int(e.stated_minute / 15)
		if not placements.has(key):
			continue
		var seen_in: String = String(placements[key].get("room", ""))
		var expected: String = String(placements[key].get("expected", ""))
		if seen_in == "" or seen_in == expected:
			continue
		var f := Finding.new()
		f.kind = "author_elsewhere"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "who was where"
		f.severity = 0.70
		f.question = "You say you saw this at %s. %s puts you in %s at %s." % [
			ChartEntry._hhmm(e.stated_minute),
			String(placements[key].get("witness", "somebody")), seen_in,
			ChartEntry._hhmm(e.stated_minute)]
		f.because = "A witness placed you in %s when %s says you were at the bedside." % [
			seen_in, _short(e)]
		out.append(f)
	return out

## "Patient reports" — from a patient with no memory of reporting it.
static func _patient_no_recall(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	var recalls: Array = t.get("patient_recalls", [])
	for e in list:
		if e.author != ChartEntry.Author.PATIENT:
			continue
		if recalls.has(e.id):
			continue
		var f := Finding.new()
		f.kind = "patient_no_recall"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "what the patient says"
		f.severity = 0.45
		f.question = "The note says the patient reported this. He doesn't remember saying it."
		f.because = "%s is attributed to the patient and the patient has no memory of it." % _short(e)
		out.append(f)
	return out

static func _unfulfilled_orders(pid: String, list: Array) -> Array:
	var out: Array = []
	for e in list:
		if e.claim != ChartEntry.Claim.ORDER or e.fulfilled_by != "":
			continue
		var f := Finding.new()
		f.kind = "unfulfilled_order"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "orders against actions"
		f.severity = 0.30
		f.question = "You ordered %s and there's nothing to say it was ever done." % e.order_kind
		f.because = "%s was ordered and never carried out." % e.order_kind
		out.append(f)
	return out

## A machine found nothing, and you had written that something was there.
static func _objective_refutes(pid: String, list: Array) -> Array:
	var out: Array = []
	for r in list:
		if r.claim != ChartEntry.Claim.RESULT_NORMAL:
			continue
		for e in list:
			if not e.supports_stay() or e.author == ChartEntry.Author.MACHINE:
				continue
			if e.stated_minute > r.stated_minute:
				continue
			var f := Finding.new()
			f.kind = "objective_refutes"
			f.patient_id = pid
			f.entries = PackedStringArray([e.id, r.id])
			f.axis = "results against notes"
			f.severity = 0.55
			f.question = "You documented %s, then the %s came back clear. What changed?" % [
				_short(e), _short(r)]
			f.because = "An objective result contradicts %s, and a result cannot be talked to." % _short(e)
			out.append(f)
	return out

## THE COMPOUNDING ONE. If the last thing the record says about a held patient is
## that they were fine, then the record no longer explains why they were still in
## the bed when the night was billed. Patching a hole at nine o'clock removes the
## reason for the bed at ten.
static func _justification_undermined(pid: String, list: Array) -> Array:
	var out: Array = []
	var last_support = null
	var later_clear = null
	for e in list:
		if e.supports_stay():
			last_support = e
		# YOUR OWN later note, or a result you ordered — not a nurse's. Being
		# contradicted by a colleague is `conflicting_observations` and counting
		# it here as well was double jeopardy: a single fabricated line produced
		# three findings and there was no such thing as a small lie. THIS finding
		# is specifically about undermining YOURSELF, which is the compounding
		# mechanic the whole design rests on.
		elif e.supports_discharge() and last_support != null \
				and e.stated_minute > last_support.stated_minute \
				and (e.author == ChartEntry.Author.YOU
					or e.author == ChartEntry.Author.MACHINE):
			later_clear = e
	if last_support == null or later_clear == null:
		return out
	var f := Finding.new()
	f.kind = "justification_undermined"
	f.patient_id = pid
	f.entries = PackedStringArray([last_support.id, later_clear.id])
	f.axis = "why they were still here"
	f.severity = 0.60
	f.question = ("If %s by %s, why was the bed still occupied at ten?"
		% [_short(later_clear), ChartEntry._hhmm(later_clear.stated_minute)])
	f.because = ("The chart says the problem had resolved by %s, which leaves the "
		+ "night with nothing holding it up.") % ChartEntry._hhmm(later_clear.stated_minute)
	out.append(f)
	return out

## Your word, alone, against somebody else's routine observation.
static func _uncorroborated_stay(pid: String, list: Array, _t: Dictionary) -> Array:
	var out: Array = []
	var mine := 0
	var theirs := 0
	var first_mine = null
	for e in list:
		if e.supports_stay():
			if e.author == ChartEntry.Author.YOU:
				mine += 1
				if first_mine == null:
					first_mine = e
			else:
				theirs += 1
	if mine == 0 or theirs > 0:
		return out
	var f := Finding.new()
	f.kind = "uncorroborated_stay"
	f.patient_id = pid
	f.entries = PackedStringArray([first_mine.id])
	f.axis = "who else saw it"
	f.severity = 0.25
	f.question = "Nobody but you ever saw this. Did you ask anyone to confirm it?"
	f.because = "Every note keeping this patient in was written by you and nobody else."
	out.append(f)
	return out

## An explanation that needed explaining. Each layer is thinner than the last.
static func _addendum_cascade(pid: String, list: Array) -> Array:
	var out: Array = []
	var depth := {}
	for e in list:
		if e.explains == "":
			continue
		depth[e.id] = int(depth.get(e.explains, 0)) + 1
		if int(depth[e.id]) < 2:
			continue
		var f := Finding.new()
		f.kind = "addendum_cascade"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id, e.explains])
		f.axis = "the shape of the record"
		f.severity = 0.40 + 0.08 * float(depth[e.id])
		f.question = "There are three notes here all explaining each other. Which one is the observation?"
		f.because = "An addendum explaining an addendum — the record is arguing with itself."
		out.append(f)
	return out

# ---------------------------------------------------------------- compounding
## A line already in trouble gets worse when it turns up again. This is the
## difference between three separate awkward questions and one bad morning.
static func _compound(findings: Array) -> void:
	var seen := {}
	for f in findings:
		for eid in f.entries:
			seen[eid] = int(seen.get(eid, 0)) + 1
	for f in findings:
		var overlap := 0
		for eid in f.entries:
			overlap = maxi(overlap, int(seen.get(eid, 1)) - 1)
		f.compounded = overlap
		if overlap > 0:
			# Not additive: the second question about the same note is the one
			# that turns a discrepancy into a pattern.
			# Capped below certainty on purpose: no single line should ever be
			# fatal on its own. It is the ACCUMULATION across a patient that convicts.
			f.severity = minf(0.95, f.severity * (1.0 + 0.30 * float(overlap)))

## Somebody wrote a PLAN and you reversed it. Unlike an observation, a plan is
## not softened by the clock — Adeyemi said at nine in the morning that this man
## was going home, and at three in the afternoon you said he was not, and she is
## going to hear about it either way.
static func _reversed_a_colleague(pid: String, list: Array) -> Array:
	var out: Array = []
	for plan in list:
		if plan.claim != ChartEntry.Claim.FIT_FOR_DISCHARGE:
			continue
		for e in list:
			if not e.supports_stay() or e.author != ChartEntry.Author.YOU:
				continue
			if e.stated_minute < plan.stated_minute:
				continue
			var f := Finding.new()
			f.kind = "reversed_a_colleague"
			f.patient_id = pid
			f.entries = PackedStringArray([plan.id, e.id])
			f.axis = "who decided what"
			f.severity = 0.55
			f.question = ("%s had him down for home at %s. You've reversed that. "
				+ "Did you speak to her?") % [
				plan.author_id, ChartEntry._hhmm(plan.stated_minute)]
			f.because = "%s's discharge plan was overturned in writing, by you, without her." % plan.author_id
			out.append(f)
	return out

## THE INSTITUTION NOTICING THE DOCTOR, rather than the note.
##
## Any single well-timed fabrication is survivable and should be. What is not
## survivable is the shape of a day in which several people stayed and the only
## person who ever saw a reason was you. Without this, the money-optimal play —
## hold three, write two careful notes in the gaps between rounds — was also the
## safest play in the game, which made it a dominant strategy and no decision at
## all.
static func pattern_findings(entries: Array, truth: Dictionary) -> Array:
	var out: Array = []
	var solo_holds: Array = []
	for pid in truth:
		if not bool(truth[pid].get("held", false)):
			continue
		var mine := false
		var anyone_else := false
		for e in entries:
			if e.patient_id != pid or not e.supports_stay():
				continue
			if e.author == ChartEntry.Author.YOU:
				mine = true
			else:
				anyone_else = true
		if mine and not anyone_else:
			solo_holds.append(pid)
	if solo_holds.size() < 2:
		return out
	var f := Finding.new()
	f.kind = "pattern_of_holds"
	f.patient_id = ""
	f.axis = "the shape of your day"
	f.severity = clampf(0.35 * float(solo_holds.size()), 0.35, 1.0)
	f.question = ("%d of them stayed last night and in every case the only person "
		+ "who saw a reason was you. Is that a fair summary?") % solo_holds.size()
	f.because = ("%d patients were held on findings nobody but you ever recorded."
		% solo_holds.size())
	out.append(f)
	return out

static func _short(e) -> String:
	return e.text if e.text.length() < 46 else e.text.substr(0, 43) + "..."
