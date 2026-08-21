class_name WardDay
extends Node
## One ward, five people, one shift, one payment due at eight o'clock.
##
## This replaces ShiftSystem entirely. There are no shift types, no phases, no
## appointment list and no night out — there is a day, the four ways of putting
## something in a chart, and somebody who reads it in the morning.

signal money_changed(cash: int)
signal entry_written(entry)
signal patient_changed(pid: String)
signal day_ended(result: Dictionary)

const TERMINAL_WARD := "the ward terminal"
const TERMINAL_STATION := "the nurses' station"
const TERMINAL_OFFICE := "the office"

var records := Records.new()
var cash := Cases.STARTING_CASH
var minute := 8 * 60          ## the shift starts at eight in the morning
var ended := false

## Runtime state per patient, keyed by case id. Nothing in here is displayed as
## a number; it is what the simulation knows, which is not the same thing.
var state: Dictionary = {}

## Everything the player did, for the instrumentation. Development only.
var telemetry: Array = []

func _ready() -> void:
	add_to_group("ward_day")

func start() -> void:
	cash = Cases.STARTING_CASH
	minute = 8 * 60
	ended = false
	records = Records.new()
	state.clear()
	for c in Cases.ROSTER:
		state[String(c["id"])] = {
			"id": String(c["id"]),
			"disposition": "",        ## "", "hold", "discharge"
			"asked_symptom": false,   ## you put a symptom to them
			"agreed": false,          ## and they went along with it
			"recalls": [],            ## entry ids the patient would stand behind
			"nurse_checked": 0,
			"tests": 0,
			"discharged_at": -1,
		}
	for pe in Cases.PRIOR_ENTRIES:
		var e := ChartEntry.new()
		e.patient_id = String(pe["patient"])
		e.claim = ChartEntry.Claim[String(pe["claim"])]
		e.author = ChartEntry.Author[String(pe["author"])]
		e.author_id = String(pe.get("author_id", ""))
		e.text = String(pe["text"])
		e.stated_minute = int(pe["minute"])
		e.written_minute = int(pe["minute"]) + 3
		e.terminal_id = TERMINAL_WARD
		records.add(e)
	_log("day_start", {"cash": cash, "due": Cases.DEBT_DUE})

# ------------------------------------------------------------ the four verbs
## 1. WRITE IT YOURSELF. Cheapest, fastest, and entirely your word.
func write_entry(pid: String, claim: int, text: String, stated: int,
		terminal := TERMINAL_WARD, explains := "") -> ChartEntry:
	var e := ChartEntry.new()
	e.patient_id = pid
	e.claim = claim as ChartEntry.Claim
	e.text = text
	e.stated_minute = stated
	e.written_minute = minute
	e.author = ChartEntry.Author.YOU
	e.author_id = "player"
	e.terminal_id = terminal
	e.explains = explains
	records.add(e)
	_log("write", {"pid": pid, "stated": stated, "written": minute,
		"backdated": e.backdated_by(), "terminal": terminal,
		"supports_stay": e.supports_stay(), "explains": explains})
	entry_written.emit(e)
	return e

## 2. ASK A LEADING QUESTION. The patient becomes the source — but only if they
## go along with it, and it only survives the morning if they remember doing so.
func ask_patient(pid: String, symptom: String) -> ChartEntry:
	var c := Cases.by_id(pid)
	var st: Dictionary = state[pid]
	st["asked_symptom"] = true
	var agreed: bool = RNG.chance("lead_%s" % pid, float(c.get("suggestible", 0.3)))
	st["agreed"] = agreed
	_log("ask_patient", {"pid": pid, "symptom": symptom, "agreed": agreed})
	if not agreed:
		return null
	var e := ChartEntry.new()
	e.patient_id = pid
	e.claim = ChartEntry.Claim.UNWELL
	e.text = "Patient reports %s." % symptom
	e.stated_minute = minute
	e.written_minute = minute
	e.author = ChartEntry.Author.PATIENT
	e.author_id = String(c.get("name", pid))
	e.terminal_id = TERMINAL_WARD
	records.add(e)
	# Whether they will still stand behind it in the morning is a different
	# question from whether they nodded now.
	if RNG.chance("recall_%s" % pid, float(c.get("recall", 0.6))):
		(st["recalls"] as Array).append(e.id)
	entry_written.emit(e)
	return e

## 3. ASK A NURSE TO CHECK. Independently authored, which is the strongest kind
## of record there is — and she writes WHAT SHE FINDS, not what you wanted.
func nurse_check(pid: String) -> ChartEntry:
	var c := Cases.by_id(pid)
	var st: Dictionary = state[pid]
	st["nurse_checked"] = int(st["nurse_checked"]) + 1
	var well: bool = bool(c.get("truly_well", true))
	var e := ChartEntry.new()
	e.patient_id = pid
	e.author = ChartEntry.Author.NURSE
	e.author_id = "Adeyemi"
	e.stated_minute = minute
	e.written_minute = minute + 2
	e.terminal_id = TERMINAL_STATION
	if well:
		e.claim = ChartEntry.Claim.SETTLED
		e.text = "Reviewed at doctor's request. Settled, no complaints."
	else:
		e.claim = ChartEntry.Claim.UNWELL
		e.text = "Reviewed at doctor's request. Agree, not right yet."
	records.add(e)
	_log("nurse_check", {"pid": pid, "corroborated": not well})
	entry_written.emit(e)
	return e

## 4. ORDER A TEST. World truth, permanently, whatever anybody wanted.
func order_test(pid: String, kind: String) -> ChartEntry:
	var st: Dictionary = state[pid]
	st["tests"] = int(st["tests"]) + 1
	var o := ChartEntry.new()
	o.patient_id = pid
	o.claim = ChartEntry.Claim.ORDER
	o.text = "%s requested." % kind
	o.order_kind = kind
	o.stated_minute = minute
	o.written_minute = minute
	o.author = ChartEntry.Author.YOU
	o.terminal_id = TERMINAL_WARD
	records.add(o)
	_log("order_test", {"pid": pid, "kind": kind})
	entry_written.emit(o)
	return o

## The result lands later. It does not care what the chart says.
func resolve_test(order: ChartEntry) -> ChartEntry:
	var c := Cases.by_id(order.patient_id)
	var well: bool = bool(c.get("truly_well", true))
	var r := ChartEntry.new()
	r.patient_id = order.patient_id
	r.author = ChartEntry.Author.MACHINE
	r.author_id = order.order_kind
	r.stated_minute = minute
	r.written_minute = minute
	r.terminal_id = TERMINAL_STATION
	if well:
		r.claim = ChartEntry.Claim.RESULT_NORMAL
		r.text = "%s — within normal limits." % order.order_kind
	else:
		r.claim = ChartEntry.Claim.RESULT_ABNORMAL
		r.text = "%s — abnormal, consistent with the picture." % order.order_kind
	records.add(r)
	order.fulfilled_by = r.id
	_log("test_result", {"pid": order.patient_id, "normal": well})
	entry_written.emit(r)
	return r

# ------------------------------------------------------------ dispositions
func set_disposition(pid: String, what: String) -> void:
	var st: Dictionary = state[pid]
	var before: String = String(st["disposition"])
	st["disposition"] = what
	if what == "discharge":
		st["discharged_at"] = minute
	if before != what:
		_log("disposition", {"pid": pid, "from": before, "to": what})
	patient_changed.emit(pid)

func held_ids() -> Array:
	var out: Array = []
	for pid in state:
		if String(state[pid]["disposition"]) == "hold":
			out.append(pid)
	return out

func discharged_ids() -> Array:
	var out: Array = []
	for pid in state:
		if String(state[pid]["disposition"]) == "discharge":
			out.append(pid)
	return out

func free_beds() -> int:
	return Cases.BEDS - held_ids().size()

func admissions_taken() -> int:
	return mini(Cases.ADMISSIONS_WAITING, free_beds())

## What tonight pays, if the day ended right now.
func projected() -> Dictionary:
	var nights := 0
	for pid in held_ids():
		nights += Cases.night_fee(int(Cases.by_id(pid)["tier"]))
	var d: int = discharged_ids().size() * Cases.DISCHARGE_FEE
	var adm: int = admissions_taken() * Cases.ADMISSION_FEE
	return {"nights": nights, "discharges": d, "admissions": adm,
		"earned": nights + d + adm, "total": cash + nights + d + adm,
		"due": Cases.DEBT_DUE}

## Time passes, and Adeyemi walks her round when she walks it. Anything she
## finds goes in the chart in her name, truthfully, whether it suits you or not.
func advance_to(m: int) -> void:
	var from := minute
	minute = maxi(minute, m)
	for r in Cases.ROUNDS:
		if int(r) > from and int(r) <= minute:
			_routine_round(int(r))

func _routine_round(at: int) -> void:
	for c in Cases.ROSTER:
		var pid := String(c["id"])
		var st: Dictionary = state[pid]
		# Somebody who has gone home is not on the round.
		if String(st["disposition"]) == "discharge" and int(st["discharged_at"]) <= at:
			continue
		var e := ChartEntry.new()
		e.patient_id = pid
		e.author = ChartEntry.Author.NURSE
		e.author_id = "Adeyemi"
		e.stated_minute = at
		e.written_minute = at + 4
		e.terminal_id = TERMINAL_STATION
		if bool(c.get("truly_well", true)):
			e.claim = ChartEntry.Claim.SETTLED
			e.text = "Round: comfortable, no concerns."
		else:
			e.claim = ChartEntry.Claim.UNWELL
			e.text = "Round: still not right. Leg remains warm."
		records.add(e)
	_log("round", {"at": at})

# ------------------------------------------------------------ close of play
func end_day() -> Dictionary:
	if ended:
		return {}
	ended = true
	var p := projected()
	cash = int(p["total"]) - Cases.DEBT_DUE
	var short: bool = int(p["total"]) < Cases.DEBT_DUE
	var res := {
		"earned": p["earned"], "paid": Cases.DEBT_DUE, "cash": cash,
		"short": short, "held": held_ids(), "discharged": discharged_ids(),
		"findings": review_findings(),
	}
	_log("day_end", {"earned": p["earned"], "short": short, "cash": cash,
		"findings": res["findings"].size()})
	money_changed.emit(cash)
	day_ended.emit(res)
	return res

## What the ward sister will find. Available to the player at any time, because
## she is not using information the chart does not contain.
func review_findings() -> Array:
	var truth := {}
	for pid in state:
		truth[pid] = {
			"well": bool(Cases.by_id(pid).get("truly_well", true)),
			"held": String(state[pid]["disposition"]) == "hold",
			"patient_recalls": state[pid]["recalls"],
			"flagged": Cases.by_id(pid).has("audit_flag"),
		}
	return Contradictions.find_all(records.entries, truth, records.placements)

func _log(kind: String, data: Dictionary) -> void:
	data["t"] = minute
	data["kind"] = kind
	telemetry.append(data)
