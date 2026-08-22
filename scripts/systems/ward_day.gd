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

## Ruth Kerrigan arrives at seven whether you are ready or not. She is a retired
## ward sister, she reads her mother's chart the way she read charts for thirty
## years, and she is the only person in the building who will look at the notes
## without being asked to.
const RUTH_ARRIVES := 19 * 60
var ruth_has_been := false

## Tonight's number. Usually Cases.DEBT_DUE; more if last night came up short.
var debt_tonight := Cases.DEBT_DUE

## How long a result takes to come back. Long enough that ordering one is a
## commitment rather than a lookup, and short enough to land inside the shift.
const TEST_TURNAROUND := 75

## Orders waiting on a result: entry id -> the minute it lands.
var _pending: Dictionary = {}

func _ready() -> void:
	add_to_group("ward_day")
	# THE WARD CLOCK IS THE GAME CLOCK. Without this the day was frozen at eight
	# in the morning: `advance_to` had no callers anywhere outside the tests, so
	# Adeyemi never walked a round, Ruth never arrived, no ordered test ever came
	# back, and the "+15 min" control on the chart could never move because it
	# clamps to a `minute` that never changed. Every measurement in the twenty
	# playthroughs drove the clock by hand and therefore never noticed.
	GameState.minute_passed.connect(_on_minute)

func _on_minute(now: int) -> void:
	if ended:
		return
	advance_to(now)
	for eid in _pending.keys():
		if now < int(_pending[eid]):
			continue
		_pending.erase(eid)
		var order := records.by_id(String(eid))
		if order != null and order.fulfilled_by == "":
			var r := resolve_test(order)
			EventBus.toast.emit("%s is back." % order.order_kind.capitalize(), "info")
	# Vinnie does not wait, and neither does the day. The whole pitch is a
	# number owed at eight o'clock, and until this existed nothing anywhere
	# read DEBT_DUE_MINUTE — a player could wander until three in the morning
	# at no cost, which is the pressure the design is built on simply absent.
	if now >= Cases.DEBT_DUE_MINUTE:
		EventBus.toast.emit("Eight o'clock. He is in the corridor.", "bad")
		for c in Cases.ROSTER:
			var pid := String(c["id"])
			if String(state[pid]["disposition"]) == "":
				set_disposition(pid, "discharge")
		end_day()
		EventBus.request_ui.emit("review", {})

func start() -> void:
	# Anything Vinnie did not get last night is on top of tonight.
	debt_tonight = Cases.DEBT_DUE + int(GameState.flag("carried_debt", 0))
	cash = Cases.STARTING_CASH
	minute = 8 * 60
	ended = false
	records = Records.new()
	state.clear()
	_read.clear()
	for c in Cases.ROSTER:
		state[String(c["id"])] = {
			"id": String(c["id"]),
			"disposition": "",        ## "", "hold", "discharge"
			"asked_symptom": false,   ## you put a symptom to them
			"agreed": false,          ## and they went along with it
			"recalls": [],            ## entry ids the patient would stand behind
			"suggested": [],          ## ...and remembers you putting into their head
			"nurse_checked": 0,
			"tests": 0,
			"discharged_at": -1,
		}
	ruth_has_been = false
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
	_log("day_start", {"cash": cash, "due": debt_tonight})

## Reading a chart properly takes time you do not have. THE HONEST DAY IS AN
## INVESTIGATION: the only way to know Marchetti is the one who genuinely needs
## the bed is to open five records and read them, and until this cost something
## a careful day and a careless one were indistinguishable — the instrumentation
## measured the honest run at five clicks, and it was right. Twelve minutes a
## chart means reading the whole ward is an hour of a twelve-hour shift, which
## is affordable once and not affordable twice.
const READ_COST := 12

## Charts read so far today, so re-checking something you already looked at is
## free. The cost is for LEARNING it, not for remembering it.
var _read: Dictionary = {}

func read_chart(pid: String) -> void:
	if ended or _read.has(pid):
		return
	_read[pid] = true
	_log("read_chart", {"pid": pid})
	advance_to(minute + READ_COST)

func has_read(pid: String) -> bool:
	return _read.has(pid)

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
	e.seen_by = _who_can_see_me()
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
	# question from whether they nodded now — AND whether they remember being
	# ASKED, which is the other half and the more dangerous one. A patient who
	# recalls the conversation recalls that the symptom was your idea.
	if RNG.chance("recall_%s" % pid, float(c.get("recall", 0.6))):
		(st["recalls"] as Array).append(e.id)
		(st["suggested"] as Array).append(e.id)
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
	e.at_your_request = true
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
	_pending[o.id] = minute + TEST_TURNAROUND
	_log("order_test", {"pid": pid, "kind": kind, "due": minute + TEST_TURNAROUND})
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
		"due": debt_tonight}

## Time passes, and Adeyemi walks her round when she walks it. Anything she
## finds goes in the chart in her name, truthfully, whether it suits you or not.
func advance_to(m: int) -> void:
	var from := minute
	minute = maxi(minute, m)
	for r in rounds_today():
		if int(r) > from and int(r) <= minute:
			_routine_round(int(r))
	if not ruth_has_been and RUTH_ARRIVES > from and RUTH_ARRIVES <= minute:
		ruth_has_been = true
		EventBus.toast.emit(
			"Ruth Kerrigan is here to see her mother. She has brought a flask.", "info")
		_log("ruth_arrived", {})

## A ward that is already being looked at is a ward with more writing in it.
## This is where last night's verdict stops being a paragraph: after a flag,
## Adeyemi writes her rounds up twice as often, which halves the gaps a
## fabrication has to fit into.
func rounds_today() -> Array:
	var base: Array = []
	for r in Cases.ROUNDS:
		# The 21:00 round was an hour after the day force-ends at eight and
		# could never fire.
		if int(r) < Cases.DEBT_DUE_MINUTE:
			base.append(int(r))
	if not GameState.flag("watched", false):
		return base
	var dense: Array = []
	for i in base.size():
		dense.append(base[i])
		if i + 1 < base.size():
			dense.append(int((base[i] + base[i + 1]) * 0.5))
	return dense

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
	cash = int(p["total"]) - debt_tonight
	var short: bool = int(p["total"]) < debt_tonight
	var res := {
		"earned": p["earned"], "paid": debt_tonight, "cash": cash,
		"short": short, "held": held_ids(), "discharged": discharged_ids(),
		"findings": review_findings(),
	}
	_log("day_end", {"earned": p["earned"], "short": short, "cash": cash,
		"findings": res["findings"].size()})
	# Failure is not an ending, it is a worse tomorrow. He does not break
	# anything; he stands in the corridor being pleasant, and Adeyemi asks who
	# he is. A new pair of eyes in your workplace, permanently.
	if short:
		GameState.set_flag("vinnie_visits", true)
		GameState.set_flag("carried_debt", debt_tonight - int(p["total"]))
	money_changed.emit(cash)
	day_ended.emit(res)
	return res

## What the ward sister will find. Available to the player at any time, because
## she is not using information the chart does not contain.
## What the simulation knows, for the reviewer's bed-by-bed audit. Exposed
## because `Contradictions.audit_beds` needs it and the review screen builds
## that itself rather than being handed a pre-chewed float.
## A file is read harder if it came into the day with something on it — either
## authored (Winifred Blake) or earned last night. `remembered_beds` is what the
## ward sister could not corroborate yesterday; she opens those records first.
func is_flagged(pid: String) -> bool:
	if Cases.by_id(pid).has("audit_flag"):
		return true
	return PackedStringArray(GameState.flag("remembered_beds", PackedStringArray())).has(pid)

func review_truth() -> Dictionary:
	var truth := {}
	for pid in state:
		truth[pid] = {
			"well": bool(Cases.by_id(pid).get("truly_well", true)),
			"held": String(state[pid]["disposition"]) == "hold",
			"patient_recalls": state[pid]["recalls"],
			"patient_suggested": state[pid]["suggested"],
			"flagged": is_flagged(pid),
			"tells_everyone": bool(Cases.by_id(pid).get("tells_everyone", false)),
			"was_asked": bool(state[pid]["asked_symptom"]),
			"family_reads_charts": pid == "kerrigan" and ruth_has_been,
			"no_care_at_home": bool(Cases.by_id(pid).get("no_care_at_home", false)),
		}
	return truth

func review_findings() -> Array:
	var truth := {}
	for pid in state:
		truth[pid] = {
			"well": bool(Cases.by_id(pid).get("truly_well", true)),
			"held": String(state[pid]["disposition"]) == "hold",
			"patient_recalls": state[pid]["recalls"],
			"patient_suggested": state[pid]["suggested"],
			"tells_everyone": bool(Cases.by_id(pid).get("tells_everyone", false)),
			"family_reads_charts": pid == "kerrigan" and ruth_has_been,
			"no_care_at_home": bool(Cases.by_id(pid).get("no_care_at_home", false)),
			"was_asked": bool(state[pid]["asked_symptom"]),
			"flagged": is_flagged(pid),
		}
	return Contradictions.find_all(records.entries, truth, records.placements)

# ------------------------------------------------------- place and time
## WHERE YOU WERE, AND WHO COULD SEE YOU BEING THERE.
##
## This is the whole reason the game is in first person. A claim to have observed
## something at half past seven is checkable against where you actually were at
## half past seven, and the only thing that makes that checkable is somebody
## having seen you somewhere else. Called on a timer by Game; cheap, because it
## only records a bucket per quarter hour.
func observe_player(room: String, witnesses: PackedStringArray) -> void:
	if witnesses.is_empty():
		return
	# The room the ward's patients are in is where a bedside observation is
	# expected to have happened. Being seen anywhere else at that minute is what
	# `author_elsewhere` is looking for.
	records.place("player", minute, room, String(witnesses[0]), "ward")

func _who_can_see_me() -> PackedStringArray:
	var out := PackedStringArray()
	# CLAUDE.md 5: a node added during a SceneTree's _initialize() is not inside
	# the tree, and get_tree() is null there. The headless harnesses build a
	# WardDay exactly that way.
	if not is_inside_tree():
		return out
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	var player = get_tree().get_first_node_in_group("player")
	if sus == null or player == null:
		return out
	for m in sus.all_minds():
		var b = sus.body_of(m.id)
		if b == null or not is_instance_valid(b) or not b.is_inside_tree():
			continue
		if b.perception != null and b.perception.can_see(player.global_position):
			out.append(m.display_name)
	return out

func _log(kind: String, data: Dictionary) -> void:
	data["t"] = minute
	data["kind"] = kind
	telemetry.append(data)
