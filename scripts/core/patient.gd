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
## What they walked in with, in the words the intake clerk used. Frozen at
## admission and never touched again, because the entire pattern the game is
## about is the difference between this and what they leave with.
var presenting_complaint: String = ""
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
## Which day you last put your hands on them. One procedure per patient per day:
## the ward is a question about which of five people is worth YOUR time, and
## being able to work the same person over and over turned that into a grind on
## whoever paid best.
var treated_on_day: int = -1

var room: String = ""
## False while they are a walk-in sitting in the treatment bay waiting to be
## seen. A walk-in costs the hospital nothing and earns it nothing; admitting
## one is what starts the meter, which is why "did I find anything?" is the most
## profitable question in the building.
var admitted: bool = false
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

## Whether this patient is actually tracking their own discharge date. Somebody
## who has lost the thread does not notice an overrun, which is exactly why a
## confused patient is worth more than a lucid one.
var knows_expected_date: bool = true
## Ticks up while they sit past their promised date. Drives escalating dialogue.
var overdue_days: float = 0.0
## Career minute of the last imaging run. While recent, vitals stop being noisy —
## the one way to actually see the truth layer.
var imaged_at: int = -99999
## Career minute of the last hands-on examination. Briefly sharpens your read on
## where they actually are — the cheap, free, legitimate version of imaging.
var examined_at: int = -99999
## A fixed, per-person error in your character's read of them. Your assessment
## of somebody you have not had your hands on recently is not neutral — it is
## wrong in a particular direction, consistently, until you actually examine
## them. Stored rather than rolled so the read does not flicker while you stand
## there looking at it.
var read_bias: float = 0.0
## A colleague can ASK for imaging. Ignoring the request is free on the day and
## expensive at the end of it, which is the point: the department you bought to
## make money is also the one thing in the building that can be pointed at you.
## In-game minutes spent parked in Intake rather than in a ward. Resets the
## moment they get a real room, because what staff object to is somebody being
## LEFT there, not somebody passing through.
var corridor_minutes: float = 0.0
## Set once they have formally complained about their care. One patient files
## one complaint; being hated by the same person twice is not twice the problem.
var complained: bool = false
var imaging_requested_by: String = ""
var imaging_requested_day: int = -1

func _init(p_id: String = "") -> void:
	id = p_id
	chart = PatientChart.new()
	chart.patient_id = p_id

# ------------------------------------------------------------------ economics
## Your share of one more night. The single most important number in the game
## and it was not printed anywhere: bonus_rate lived in GameState, was never
## rendered by any screen, and the player's own balance did not move for twelve
## real minutes — so "keeping them pays ME" was a thing the design knew and the
## player could not find out.
func your_cut_per_day() -> int:
	return int(round(float(daily_revenue()) * GameState.bonus_rate))

## What an insurer will pay for the Nth thing to go wrong with the same person
## in the same admission. The first one is worth having. The fourth is worth
## almost nothing and the eighth is worth nothing at all.
##
## This used to be a flat +0.26 each with no ceiling, which meant a patient with
## fifteen complications billed nearly five times base — and a balance run
## measured the consequence exactly: reckless butchery earned $8,379 a day
## against careful practice's $2,778, so the game's answer to "how should I do
## this?" was "badly, and quickly". Nobody pays five times the daily rate for
## one person who keeps falling over. They ask why they keep falling over.
##
## The shape is the design in one line: the first complication is where the
## money is, the fifteenth is where the prison is.
const COMPLICATION_STEPS := [0.26, 0.19, 0.12, 0.07, 0.04]
const COMPLICATION_TAIL := 0.015
const COMPLICATION_CEILING := 0.78

func daily_revenue() -> int:
	var mult: float = DB.insurance_multiplier(insurance)
	var comp_bonus := 1.0
	var billed := 0
	for c in complications:
		if c.resolved:
			continue
		comp_bonus += (COMPLICATION_STEPS[billed] if billed < COMPLICATION_STEPS.size()
			else COMPLICATION_TAIL)
		billed += 1
	comp_bonus = minf(comp_bonus, 1.0 + COMPLICATION_CEILING)
	# Acuity escalation: a case that runs long with complications gets recoded as
	# complex and bills more per day. Entirely above board, and the reason a
	# six-day stay is worth far more than three two-day stays.
	if not complications.is_empty() and days_admitted > expected_stay_days:
		var extra_days: float = days_admitted - expected_stay_days
		comp_bonus *= 1.0 + clampf(extra_days * 0.05, 0.0, 0.45)
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

## Days in this bed that the RECORD does not account for.
##
## An insurer reading your figures does not know what is true, only what is
## written. A complication that is documented justifies the days it added; one
## that is not documented does not, and those days show up as a patient who
## simply would not leave.
##
## The statistical review used to measure every extra day against the original
## projection, which meant causing a complication and filing it correctly made
## your length-of-stay figures WORSE — the game punished the exact behaviour it
## was built to reward, and a balance run showed the consequence: the most
## profitable strategy in the game was to touch nobody and never file anything,
## because doing the interesting thing cost more than it paid.
func unexplained_overstay() -> float:
	var justified := expected_stay_days
	for c in complications:
		if c.resolved:
			continue
		if c.documented_cause != "":
			justified += c.days_added
	return maxf(0.0, days_admitted - justified)

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

	var rate := (recovery_rate + Upgrades.recovery_bonus() * recovery_rate) * suppression * env_modifier
	# Psychiatric admissions respond to how they are treated as people rather
	# than to equipment: comfort and satisfaction ARE the treatment, which makes
	# a cold dark ward a far more effective way to hold one than any machine.
	if dept() == "psych":
		rate *= clampf(0.35 + satisfaction, 0.2, 1.35)
	recovery = clampf(recovery + rate * days, -0.2, 1.0)

	if is_overdue():
		overdue_days += days
		if not knows_expected_date:
			# They are not counting, so the overrun costs no goodwill. Their
			# family may still be counting, which is the other half of it.
			return
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

## Have you already done something to them today?
func seen_to_today() -> bool:
	return treated_on_day == GameState.day

# ------------------------------------------------------------------ vitals
## The player-facing readout. Deliberately fictional, deliberately noisy, and
## distorted by the patient's own personality — a hypochondriac reports worse
## numbers than they have, a stoic reports better.
func vitals() -> Dictionary:
	var bias: float = DB.trait_of(archetype, "vital_bias", 0.0)
	# The diagnostics bench upgrade is the only thing that makes these readings
	# trustworthy — before that, you are reading a person, not an instrument.
	var noise_scale: float = Upgrades.vitals_noise_scale()
	if GameState.flag("perk_steady_hands", false):
		noise_scale *= 0.6
	# Recent imaging replaces guesswork with fact. It is also on the record.
	if GameState.career_minutes - imaged_at < GameState.MINUTES_PER_DAY:
		noise_scale = 0.0
		bias = 0.0
	var n := func(k: String, spread: float) -> float:
		return RNG.noise("vitals_%s_%s_%d" % [id, k, int(GameState.career_minutes / 30)],
			spread * noise_scale)

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
##
## Deliberately RELATIVE to how far through the projected stay they are, not
## absolute. "Not great" on the morning of admission is true and useless; what a
## doctor actually wants to know is whether this person is on track — which is
## also exactly the question the player is asking about their own interference.
func apparent_state() -> String:
	if recovery < 0.0:
		return "worse than on arrival"
	if recovery >= 0.98:
		return "ready to go home"
	if days_admitted < 0.3:
		return "just admitted"
	var expected: float = clampf(days_admitted / maxf(expected_stay_days, 0.2), 0.0, 1.0)
	var delta: float = recovery - expected
	if delta > 0.2:
		return "ahead of schedule"
	if delta > -0.08:
		return "coming along as expected"
	if delta > -0.25:
		return "slower than I would like"
	return "not coming along at all"

func condition_name() -> String:
	return DB.condition_name(condition_id)

## Whether you have had hands on them recently enough to trust your own read.
func read_is_fresh() -> bool:
	return GameState.career_minutes - examined_at < 240

## Your character's assessment of what this person is like to be alone with.
##
## Deliberately in words rather than numbers, and deliberately never advice: the
## game does not tell you who is safe to hurt, it tells you what you noticed
## about somebody. Every line is a thing a doctor could plausibly say about a
## patient out loud.
##
## Blurred until you have examined them. That is the quiet argument for doing
## the honest version of the examination — it is the only way to find out whose
## account of the afternoon anybody would believe.
func read_notes() -> Array[String]:
	var fresh := read_is_fresh()
	var bias := 0.0 if fresh else read_bias
	var out: Array[String] = []

	var watching: float = clampf((mind.observance if mind else 0.5) + bias, 0.0, 1.0)
	if watching > 0.75:
		out.append("Watches everything. Asked what the dial was for.")
	elif watching > 0.5:
		out.append("Pays attention. Follows you round the room with their eyes.")
	elif watching > 0.28:
		out.append("Half here. Mostly looking at the ceiling.")
	else:
		out.append("Has not looked up once.")

	var escalation: float = clampf(DB.trait_of(archetype, "escalation", 0.4) + bias, 0.0, 1.0)
	if escalation > 0.7:
		out.append("The sort who asks for it in writing.")
	elif escalation > 0.4:
		out.append("Would mention it to somebody. Probably a nurse.")
	else:
		out.append("Not one for making a fuss.")

	if not knows_expected_date:
		out.append("Has lost track of what day they came in.")
	if not fresh:
		out.append("You have not properly examined them. This is a guess.")
	return out

## Injuries that happened under this hospital's care. Not what they arrived
## with — what you gave them.
func acquired_injuries() -> Array[Complication]:
	var out: Array[Complication] = []
	for c in complications:
		if c.is_injury and c.acquired_here and not c.resolved:
			out.append(c)
	return out

## The ones nobody has written a mechanism for. A broken wrist with no
## explanation is a different document from a broken wrist that fell over.
func undocumented_injuries() -> Array[Complication]:
	var out: Array[Complication] = []
	for c in acquired_injuries():
		if c.documented_cause == "":
			out.append(c)
	return out

func imaging_requested() -> bool:
	return imaging_requested_by != ""

func clear_imaging_request() -> void:
	imaging_requested_by = ""
	imaging_requested_day = -1

## Which department this admission belongs to. Drives what unlocks it, how it
## recovers, and where the patient would rather be.
func dept() -> String:
	return String(DB.condition(condition_id).get("dept", "ward"))

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
		"ltt": last_treatment_time, "tod": treated_on_day,
		"room": room, "disc": discharged,
		"dr": discharge_reason, "sat": satisfaction, "env": env_modifier,
		"dis": discomfort, "mind": mind.to_dict() if mind else {},
		"ovd": overdue_days, "ked": knows_expected_date, "img": imaged_at,
		"imgrb": imaging_requested_by, "imgrd": imaging_requested_day,
		"corm": corridor_minutes, "cmpl": complained, "pres": presenting_complaint,
		"adm": admitted,
		"exam": examined_at, "bias": read_bias,
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
	p.treated_on_day = int(d.get("tod", -1))
	p.room = d.get("room", "")
	p.discharged = bool(d.get("disc", false))
	p.discharge_reason = d.get("dr", "")
	p.satisfaction = float(d.get("sat", 0.7))
	p.env_modifier = float(d.get("env", 1.0))
	p.discomfort = float(d.get("dis", 0.0))
	p.overdue_days = float(d.get("ovd", 0.0))
	p.knows_expected_date = bool(d.get("ked", true))
	p.imaged_at = int(d.get("img", -99999))
	p.corridor_minutes = float(d.get("corm", 0.0))
	p.presenting_complaint = String(d.get("pres", ""))
	p.admitted = bool(d.get("adm", true))
	p.examined_at = int(d.get("exam", -99999))
	p.read_bias = float(d.get("bias", 0.0))
	p.complained = bool(d.get("cmpl", false))
	p.imaging_requested_by = String(d.get("imgrb", ""))
	p.imaging_requested_day = int(d.get("imgrd", -1))
	var md: Dictionary = d.get("mind", {})
	if not md.is_empty():
		p.mind = Mind.from_dict(md)
	return p
