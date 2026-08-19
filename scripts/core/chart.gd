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
		"tf": times_forged, "shred": shredded,
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
	return c
