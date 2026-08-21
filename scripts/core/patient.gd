class_name Patient
extends RefCounted
## A person in a bed. Thin on purpose.
##
## Almost everything that used to be here — recovery curves, complications,
## acquired injuries, insurance multipliers, corridor minutes, treatment history
## — went with the redesign. What a patient IS now is: a name, a bed, a Mind,
## and a written situation in `Cases`. The interesting state belongs to the
## chart, not to the person.

var id: String = ""
var case_id: String = ""
var display_name: String = ""
var archetype: String = "trusting"
var mind: Mind = null
var bed_index: int = 0

var admitted := true
var discharged := false
var days_admitted := 2.0
var expected_stay_days := 2.0
var recovery := 0.9
var satisfaction := 0.7

var skin_tone: Color = Color(0.92, 0.78, 0.66)
var shirt_color: Color = Color(0.86, 0.88, 0.90)

static func from_case(c: Dictionary) -> Patient:
	var p := Patient.new()
	p.id = String(c["id"])
	p.case_id = p.id
	p.display_name = String(c["name"])
	p.bed_index = int(c["bed"])
	# The genuinely unwell one is not "ready", and the game never says so out
	# loud — it shows you a leg that is still warm and lets you decide.
	p.recovery = 0.55 if not bool(c.get("truly_well", true)) else 0.95
	p.expected_stay_days = 2.0
	p.days_admitted = 2.0
	return p

func case() -> Dictionary:
	return Cases.by_id(case_id)

func condition_name() -> String:
	return String(case().get("condition", ""))

func dept() -> String:
	return "ward"

func is_overdue() -> bool:
	return days_admitted > expected_stay_days

func ready_for_discharge() -> bool:
	return recovery >= 0.85

## What the hospital bills for one more night of them.
func daily_revenue() -> int:
	return Cases.night_fee(int(case().get("tier", Cases.Tier.STANDARD))) * 3

func to_dict() -> Dictionary:
	return {"id": id, "case": case_id, "disch": discharged,
		"mind": mind.to_dict() if mind else {}}

static func from_dict(d: Dictionary) -> Patient:
	var p := Patient.from_case(Cases.by_id(String(d.get("case", ""))))
	p.discharged = bool(d.get("disch", false))
	var md: Dictionary = d.get("mind", {})
	if not md.is_empty():
		p.mind = Mind.from_dict(md)
	return p
