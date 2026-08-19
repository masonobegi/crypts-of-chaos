class_name Patient
extends RefCounted
## The *truth layer* for one admitted human. Recovery is never shown to the
## player as a number — only as three noisy fictional vitals — so treatment is a
## question of reading a person, not reading a progress bar.

var id: String = ""
var display_name: String = ""
var age: int = 40
var skin_tone: Color = Color(0.87, 0.72, 0.6)
var shirt_color: Color = Color(0.5, 0.7, 0.9)

var condition_id: String = ""
var archetype: String = "trusting"

## HIDDEN TRUTH. 0 = just admitted, 1 = fit to leave.
var recovery: float = 0.0
## Baseline fraction of recovery per in-game day with correct care.
var recovery_rate: float = 0.5
## What the intake paperwork predicted, in days. Used for the "wasn't I supposed
## to leave yesterday?" pressure.
var expected_stay_days: float = 2.0
var days_admitted: float = 0.0
var admitted_on_day: int = 1

var insurance: String = "standard"
var base_daily_revenue: int = 800

var complications: Array[Complication] = []
var chart: PatientChart = null
## Ground truth of what you actually did to them.
var actual_treatments: Array[Dictionary] = []   ## {id, time, quality}
var last_treatment_time: int = -999

var room: String = ""
var discharged: bool = false
var discharge_reason: String = ""
## 0..1. Low satisfaction produces complaints even with zero suspicion — being
## bad at your job is its own failure state.
var satisfaction: float = 0.7
## Set by the room each tick: comfort, noise, temperature all feed recovery.
var env_modifier: float = 1.0
## Accumulates when the room is unpleasant; drives environmental complications.
var discomfort: float = 0.0

## Their own beliefs about you.
var mind: Mind = null

## Set true once they have been told (or have worked out) a discharge date.
var knows_expected_date: bool = true
## Ticks up while they sit past their promised date. Drives escalating dialogue.
var overdue_days: float = 0.0

func _init(p_id: String = "") -> void:
	id = p_id
	chart = PatientChart.new()
	chart.patient_id = p_id

# ------------------------------------------------------------------ economics
func daily_revenue() -> int:
	var mult: float = DB.insurance_multiplier(insurance)
	var comp_bonus := 1.0
	for c in complications:
		if not c.resolved:
			comp_bonus += 0.18   # complications are billable, that's the point
	return int(round(float(base_daily_revenue) * mult * comp_bonus))

# ------------------------------------------------------------------ stay math
func total_stay_days() -> float:
	var extra := 0.0
	for c in complications:
		if not c.resolved:
			extra += c.days_added
	return expected_stay_days + extra

func projected_discharge_day() -> int:
	return admitted_on_day + int(ceil(total_stay_days()))

func is_overdue() -> bool:
	return days_admitted > expected_stay_days + 0.25

func ready_for_discharge() -> bool:
	return recovery >= 1.0 and not discharged

# ------------------------------------------------------------------ simulation
## Advance the hidden state. `days` is fractional in-game days.
func tick(days: float) -> void:
	if discharged:
		return
	days_admitted += days

	# Complications suppress the recovery rate while active — that is the
	# mechanism by which they extend a stay, rather than a flat timer.
	var suppression := 1.0
	for c in complications:
		if not c.resolved:
			suppression *= clampf(1.0 - 0.34 * c.severity, 0.12, 1.0)

	var rate := recovery_rate * suppression * env_modifier
	recovery = clampf(recovery + rate * days, -0.2, 1.0)

	if is_overdue():
		overdue_days += days
		# Sitting in a bed past your date is annoying, and annoyance is a
		# perfectly ordinary route to a complaint.
		satisfaction = clampf(satisfaction - 0.06 * days * DB.trait_of(archetype, "impatience", 1.0), 0.0, 1.0)

	if env_modifier < 0.95:
		discomfort += (1.0 - env_modifier) * days
	else:
		discomfort = maxf(0.0, discomfort - 0.2 * days)

func add_complication(c: Complication) -> void:
	c.onset_time = GameState.career_minutes
	complications.append(c)
	recovery = clampf(recovery + c.recovery_delta, -0.2, 1.0)
	EventBus.complication_added.emit(self, c)

func resolve_complication(c: Complication) -> void:
	c.resolved = true
	EventBus.complication_resolved.emit(self, c)

func active_complications() -> Array[Complication]:
	var out: Array[Complication] = []
	for c in complications:
		if not c.resolved:
			out.append(c)
	return out

func record_treatment(tid: String, quality: float) -> void:
	actual_treatments.append({"id": tid, "time": GameState.career_minutes, "quality": quality})
	last_treatment_time = GameState.career_minutes

# ------------------------------------------------------------------ vitals
## The player-facing readout. Deliberately fictional, deliberately noisy, and
## distorted by the patient's own personality — a hypochondriac reports worse
## numbers than they have, a stoic reports better.
func vitals() -> Dictionary:
	var bias: float = DB.trait_of(archetype, "vital_bias", 0.0)
	var n := func(k: String, spread: float) -> float:
		return RNG.noise("vitals_%s_%s_%d" % [id, k, int(GameState.career_minutes / 30)], spread)

	var r: float = clampf(recovery, 0.0, 1.0)
	var comp_load := 0.0
	for c in active_complications():
		comp_load += c.severity

	return {
		# 0-100, roughly tracks recovery, but noisy and personality-skewed.
		"humour_balance": clampf(28.0 + r * 62.0 - comp_load * 14.0 + bias * 9.0 + n.call("hb", 6.0), 0.0, 100.0),
		# 0-11. High is bad. Named after nothing.
		"spleen_torque": clampf(7.4 - r * 5.2 + comp_load * 2.1 - bias * 0.8 + n.call("st", 0.7), 0.0, 11.0),
		# Fictional units, lower is better.
		"ambient_dread": clampf(64.0 - r * 40.0 + comp_load * 19.0 + n.call("ad", 5.0) - bias * 6.0, 0.0, 140.0),
	}

## Coarse, honest-ish read a competent doctor gets from looking at them.
func apparent_state() -> String:
	if recovery >= 0.98: return "ready to go home"
	if recovery >= 0.75: return "nearly there"
	if recovery >= 0.45: return "improving"
	if recovery >= 0.2: return "stable"
	if recovery >= 0.0: return "not great"
	return "actively worse than on arrival"

func condition_name() -> String:
	return DB.condition_name(condition_id)

# ------------------------------------------------------------------ save/load
func to_dict() -> Dictionary:
	var comps: Array = []
	for c in complications:
		comps.append(c.to_dict())
	return {
		"id": id, "name": display_name, "age": age,
		"skin": [skin_tone.r, skin_tone.g, skin_tone.b],
		"shirt": [shirt_color.r, shirt_color.g, shirt_color.b],
		"cond": condition_id, "arch": archetype, "rec": recovery,
		"rate": recovery_rate, "esd": expected_stay_days, "da": days_admitted,
		"aod": admitted_on_day, "ins": insurance, "bdr": base_daily_revenue,
		"comps": comps, "chart": chart.to_dict(), "at": actual_treatments,
		"ltt": last_treatment_time, "room": room, "disc": discharged,
		"dr": discharge_reason, "sat": satisfaction, "env": env_modifier,
		"dis": discomfort, "mind": mind.to_dict() if mind else {},
		"ovd": overdue_days,
	}

static func from_dict(d: Dictionary) -> Patient:
	var p := Patient.new(d.get("id", ""))
	p.display_name = d.get("name", "")
	p.age = int(d.get("age", 40))
	var sk: Array = d.get("skin", [0.87, 0.72, 0.6])
	p.skin_tone = Color(sk[0], sk[1], sk[2])
	var sh: Array = d.get("shirt", [0.5, 0.7, 0.9])
	p.shirt_color = Color(sh[0], sh[1], sh[2])
	p.condition_id = d.get("cond", "")
	p.archetype = d.get("arch", "trusting")
	p.recovery = float(d.get("rec", 0.0))
	p.recovery_rate = float(d.get("rate", 0.5))
	p.expected_stay_days = float(d.get("esd", 2.0))
	p.days_admitted = float(d.get("da", 0.0))
	p.admitted_on_day = int(d.get("aod", 1))
	p.insurance = d.get("ins", "standard")
	p.base_daily_revenue = int(d.get("bdr", 800))
	for c in d.get("comps", []):
		p.complications.append(Complication.from_dict(c))
	p.chart = PatientChart.from_dict(d.get("chart", {}))
	for t in d.get("at", []):
		p.actual_treatments.append(t)
	p.last_treatment_time = int(d.get("ltt", -999))
	p.room = d.get("room", "")
	p.discharged = bool(d.get("disc", false))
	p.discharge_reason = d.get("dr", "")
	p.satisfaction = float(d.get("sat", 0.7))
	p.env_modifier = float(d.get("env", 1.0))
	p.discomfort = float(d.get("dis", 0.0))
	p.overdue_days = float(d.get("ovd", 0.0))
	var md: Dictionary = d.get("mind", {})
	if not md.is_empty():
		p.mind = Mind.from_dict(md)
	return p
