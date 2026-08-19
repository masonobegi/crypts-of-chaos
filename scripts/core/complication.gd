class_name Complication
extends RefCounted
## The unit of profit. A secondary fictional condition that extends a stay.
##
## Every complication carries BOTH what actually caused it and what you wrote
## down. The gap between those two is the whole game.

var id: String = ""
var display_name: String = ""
var flavor: String = ""

## Extra days this keeps the patient admitted.
var days_added: float = 1.0
## Immediate hit to hidden recovery (negative = patient got worse).
var recovery_delta: float = 0.0
## 0..1 — how obviously *wrong* this looks to an onlooker.
var severity: float = 0.3

## TRUTH: the cause tag the simulation knows about, e.g. "machine_overdial".
var true_cause: String = ""
## RECORD: the cause you filed. "" means undocumented, which is the risky state.
var documented_cause: String = ""
var documented_at: int = -1

## Career minute of onset, and the minute anyone other than the player noticed.
var onset_time: int = 0
var noticed_time: int = -1
var noticed_by: PackedStringArray = PackedStringArray()

## Cause tags a chart will accept for this complication. Filing one that is on
## this list is plausible; filing one that isn't is a record inconsistency
## waiting for an investigator to find.
var plausible_causes: PackedStringArray = PackedStringArray()

## A physical tell that appears in the room — the thing that makes a visiting
## wife go "why is he BEIGE".
var symptom: String = ""
## Symptom tint applied to the patient mesh, for readability at a glance.
var symptom_color: Color = Color(1, 1, 1)

var resolved: bool = false

## Documented, with a cause the chart finds plausible, before anyone noticed.
## This is the clean kill: revenue, no suspicion.
func is_clean() -> bool:
	if documented_cause == "":
		return false
	if not plausible_causes.has(documented_cause):
		return false
	return noticed_time < 0 or documented_at <= noticed_time

## Filed a cause the chart does not accept — an inconsistency that a records
## audit will happily find months later.
func is_inconsistent() -> bool:
	return documented_cause != "" and not plausible_causes.has(documented_cause)

## How suspicious this complication is right now, before witnesses.
func paper_suspicion() -> float:
	if is_clean():
		return 0.0
	if is_inconsistent():
		return severity * 1.4
	return severity   # undocumented

func to_dict() -> Dictionary:
	return {
		"id": id, "name": display_name, "flavor": flavor, "days": days_added,
		"rd": recovery_delta, "sev": severity, "tc": true_cause,
		"dc": documented_cause, "da": documented_at, "ot": onset_time,
		"nt": noticed_time, "nb": Array(noticed_by),
		"pc": Array(plausible_causes), "sym": symptom,
		"col": [symptom_color.r, symptom_color.g, symptom_color.b],
		"res": resolved,
	}

static func from_dict(d: Dictionary) -> Complication:
	var c := Complication.new()
	c.id = d.get("id", "")
	c.display_name = d.get("name", "")
	c.flavor = d.get("flavor", "")
	c.days_added = float(d.get("days", 1.0))
	c.recovery_delta = float(d.get("rd", 0.0))
	c.severity = float(d.get("sev", 0.3))
	c.true_cause = d.get("tc", "")
	c.documented_cause = d.get("dc", "")
	c.documented_at = int(d.get("da", -1))
	c.onset_time = int(d.get("ot", 0))
	c.noticed_time = int(d.get("nt", -1))
	c.noticed_by = PackedStringArray(d.get("nb", []))
	c.plausible_causes = PackedStringArray(d.get("pc", []))
	c.symptom = d.get("sym", "")
	var col: Array = d.get("col", [1, 1, 1])
	c.symptom_color = Color(col[0], col[1], col[2])
	c.resolved = bool(d.get("res", false))
	return c
