class_name PatientChart
extends RefCounted
## The *record layer*: what the hospital officially believes happened.
##
## The chart is a separate object from the patient on purpose. It can be wrong.
## It can be wrong because you were busy, or because you made it wrong. An audit
## is simply someone diffing this against the truth — so every lie you file is a
## loan against a future investigation.

var patient_id: String = ""
## What you told the system was wrong with them. May not be the real condition.
var recorded_condition: String = ""
## What the intake clerk wrote down on the way in. Copied here at admission so
## an audit can be done against the chart alone, which is exactly how an audit
## is actually done — the auditor never gets to see the patient.
var presenting_complaint: String = ""
## Treatments you *billed for*. Entries not backed by a real treatment are
## phantom billing: excellent money, career-ending if audited.
var logged_treatments: Array[Dictionary] = []   ## {id, time, real:bool}
var notes: Array[Dictionary] = []               ## {time, text, author, truthful:bool}
## Discharge date you have committed to in writing. Blowing past it is the #1
## thing patients and families actually notice.
var promised_discharge_day: int = -1
var times_edited: int = 0
var times_forged: int = 0
## Set if the physical chart object was destroyed. Missing charts are their own
## kind of suspicious.
var shredded: bool = false
## Imaging writes an authoritative, timestamped observation into the record.
## It is the most useful diagnostic in the game AND the most dangerous thing to
## have on file, because everything you claim afterwards has to agree with it.
var imaging_done: bool = false
var imaging_clear: bool = false      ## imaging found no underlying cause
var imaging_day: int = -1
## What Radiology actually saw, per complication: {id, name, cause, day}.
##
## The only part of the record not written in the player's handwriting, which is
## precisely what makes it dangerous. Everything else here can be edited, forged
## or fed to the shredder; this cannot, and it states the TRUE cause.
var imaging_findings: Array = []
## The theatre record: one entry per operation, listing how each stage was done.
## Written by the theatre, not by you.
var surgery_log: Array = []          ## {day, site, notes, complication, improvised}
## What they were sent home on, and whether it was indicated for what they had.
## The pharmacy keeps its own copy.
var prescription: String = ""
var prescription_indicated: bool = true

func log_surgery(site: String, notes: PackedStringArray, day: int,
		complication: String, improvised: int, indicated := "") -> void:
	surgery_log.append({
		"day": day, "site": site, "notes": Array(notes),
		"complication": complication, "improvised": improvised,
		"indicated": indicated if indicated != "" else site,
	})

func _day_of(career_minute: int) -> int:
	return 1 + int(career_minute / GameState.MINUTES_PER_DAY)

func log_treatment(id: String, time: int, real: bool) -> void:
	logged_treatments.append({"id": id, "time": time, "real": real})
	if not real:
		times_forged += 1

func add_note(text: String, time: int, author: String = "You", truthful: bool = true) -> void:
	notes.append({"time": time, "text": text, "author": author, "truthful": truthful})
	if not truthful:
		times_forged += 1

## Diff the record against what actually happened. Returns a list of findings —
## this is literally what an auditor reads out to you.
func audit(actual_treatments: Array, complications: Array) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []

	# Phantom billing: billed, never happened.
	var actual_ids: Array[String] = []
	for t in actual_treatments:
		actual_ids.append(String(t.get("id", "")))
	var counted: Dictionary = {}
	for lt in logged_treatments:
		var lid: String = String(lt.get("id", ""))
		counted[lid] = int(counted.get(lid, 0)) + 1
	var actual_counted: Dictionary = {}
	for aid in actual_ids:
		actual_counted[aid] = int(actual_counted.get(aid, 0)) + 1
	for lid in counted:
		var extra: int = int(counted[lid]) - int(actual_counted.get(lid, 0))
		if extra > 0:
			findings.append({
				"kind": "phantom_billing", "weight": 0.55 * float(extra),
				"text": "%d billed %s with no corresponding record of it being performed."
					% [extra, DB.treatment_name(lid)],
			})
	# Omission: happened, never charted. Sloppy rather than criminal.
	for aid in actual_counted:
		var missing: int = int(actual_counted[aid]) - int(counted.get(aid, 0))
		if missing > 0:
			findings.append({
				"kind": "undocumented_treatment", "weight": 0.16 * float(missing),
				"text": "%s administered but never charted." % DB.treatment_name(aid),
			})
	# Complications with impossible or absent causes.
	for c in complications:
		var comp := c as Complication
		if comp.is_inconsistent():
			findings.append({
				"kind": "impossible_cause", "weight": 0.7,
				"text": "\"%s\" attributed to %s, which cannot cause it."
					% [comp.display_name, DB.cause_name(comp.documented_cause)],
			})
		elif comp.documented_cause == "":
			findings.append({
				"kind": "undocumented_complication", "weight": 0.4,
				"text": "\"%s\" appears in the record with no stated cause." % comp.display_name,
			})
	if shredded:
		findings.append({
			"kind": "missing_chart", "weight": 0.85,
			"text": "The physical chart for this patient is missing entirely.",
		})
	# Anything blamed on an underlying condition AFTER imaging found none is the
	# single most specific contradiction available in the whole record.
	if imaging_done and imaging_clear:
		for c in complications:
			var comp := c as Complication
			if comp.documented_cause == "underlying" and comp.documented_at >= 0:
				findings.append({
					"kind": "contradicts_imaging", "weight": 0.9,
					"text": "\"%s\" attributed to an underlying condition, which imaging on day %d explicitly ruled out."
						% [comp.display_name, imaging_day],
				})
	# Imaging reports the true cause. Anything the chart says happened for a
	# different reason is now contradicted by a document you did not write.
	for f in imaging_findings:
		var stated := ""
		var still_there := false
		for c in complications:
			var comp := c as Complication
			if comp.id == String(f.get("id", "")):
				stated = comp.documented_cause
				still_there = true
		if not still_there:
			continue
		if stated == String(f.get("cause", "")):
			continue
		findings.append({
			"kind": "contradicts_imaging", "weight": 0.8,
			"text": "Imaging on day %d put \"%s\" down to %s. The chart says %s." % [
				int(f.get("day", 0)), String(f.get("name", "")),
				DB.cause_name(String(f.get("cause", ""))),
				"nothing at all" if stated == "" else DB.cause_name(stated)],
		})
	# ---- injuries acquired here. This is the loudest thing in the record, and
	# it is loud because it is legible: somebody came in with one thing and is
	# going home with three, and every one of them happened on the ward.
	var acquired: Array = []
	var unexplained: Array = []
	for c in complications:
		var comp := c as Complication
		if not (comp.is_injury and comp.acquired_here and not comp.resolved):
			continue
		acquired.append(comp)
		if comp.documented_cause == "":
			unexplained.append(comp)
		elif comp.documented_cause == "pre_existing":
			# The one mechanism that the dates themselves contradict.
			findings.append({
				"kind": "injury_predated", "weight": 0.75,
				"text": "\"%s\" is recorded as present on admission. It first appears in the record on day %d." % [
					comp.display_name, _day_of(comp.onset_time)],
			})
	for comp in unexplained:
		findings.append({
			"kind": "unexplained_injury", "weight": 0.35 + comp.severity * 0.45,
			"text": "\"%s\" was sustained on the ward with no mechanism recorded." % comp.display_name,
		})
	# Two is a coincidence and three is a paragraph somebody writes about you.
	if acquired.size() >= 2:
		var parts := PackedStringArray()
		for comp in acquired:
			parts.append(comp.display_name)
		findings.append({
			"kind": "injury_pattern", "weight": 0.55 + 0.3 * float(acquired.size() - 1),
			"text": "Admitted with %s. Has since sustained %d further injuries here: %s." % [
				presenting_complaint if presenting_complaint != "" else recorded_condition,
				acquired.size(), ", ".join(parts)],
		})
	# ---- theatre records. An operation that went wrong is ordinary. An
	# operation where all three stages were improvised is a paragraph.
	var improvised_ops := 0
	for op in surgery_log:
		if int(op.get("improvised", 0)) >= 2:
			improvised_ops += 1
	for op in surgery_log:
		var did := String(op.get("site", ""))
		var meant := String(op.get("indicated", did))
		if did != meant:
			findings.append({
				"kind": "wrong_site", "weight": 0.95,
				"text": "Day %d: procedure recorded on the %s. The indicated site was the %s." % [
					int(op.get("day", 0)), did, meant],
			})
	if improvised_ops > 0:
		findings.append({
			"kind": "improvised_procedure", "weight": 0.4 + 0.25 * float(improvised_ops),
			"text": "%d procedure(s) recorded as modified intra-operatively at most stages." % improvised_ops,
		})
	# ---- pharmacy. Sending somebody home on something that does not treat what
	# they had is not a crime. It is a question somebody eventually asks.
	if prescription != "" and not prescription_indicated:
		findings.append({
			"kind": "prescription_mismatch", "weight": 0.45,
			"text": "Discharged on %s, which is not indicated for %s." % [
				DB.prescription_name(prescription),
				presenting_complaint if presenting_complaint != "" else recorded_condition],
		})
	if times_forged >= 3:
		findings.append({
			"kind": "handwriting", "weight": 0.3 * float(times_forged - 2),
			"text": "Multiple entries appear to have been written after the fact.",
		})
	return findings

func to_dict() -> Dictionary:
	return {
		"pid": patient_id, "cond": recorded_condition, "lt": logged_treatments,
		"notes": notes, "pdd": promised_discharge_day, "te": times_edited,
		"tf": times_forged, "shred": shredded, "imgf": imaging_findings,
		"pres": presenting_complaint, "surg": surgery_log,
		"rx": prescription, "rxi": prescription_indicated,
	}

static func from_dict(d: Dictionary) -> PatientChart:
	var c := PatientChart.new()
	c.patient_id = d.get("pid", "")
	c.recorded_condition = d.get("cond", "")
	for e in d.get("lt", []):
		c.logged_treatments.append(e)
	for n in d.get("notes", []):
		c.notes.append(n)
	c.promised_discharge_day = int(d.get("pdd", -1))
	c.times_edited = int(d.get("te", 0))
	c.times_forged = int(d.get("tf", 0))
	c.shredded = bool(d.get("shred", false))
	c.imaging_done = bool(d.get("img", false))
	c.imaging_clear = bool(d.get("imgc", false))
	c.imaging_day = int(d.get("imgd", -1))
	c.imaging_findings = d.get("imgf", [])
	c.presenting_complaint = String(d.get("pres", ""))
	c.surgery_log = d.get("surg", [])
	c.prescription = String(d.get("rx", ""))
	c.prescription_indicated = bool(d.get("rxi", true))
	return c
