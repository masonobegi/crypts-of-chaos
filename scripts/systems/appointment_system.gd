class_name AppointmentSystem
extends Node
## The shift as a list of people who are expecting to see you.
##
## Before this, a shift was eight hours of open-ended wandering and the only
## structure was whatever you decided to do. A booked list changes the whole
## texture: there is somewhere you are supposed to be, there is a reason to be
## alone in a room with somebody, and skipping a slot is itself a thing people
## notice.
##
## It is also the money. A physical is a walk-in who costs the hospital nothing
## and earns it a consultation fee — unless you find something, at which point
## they become an admission with a daily rate. "Did I find anything?" is the most
## profitable question in the building, and you are the one who answers it.

signal roster_changed()

## Deliberately thin, except for surgery.
##
## A consultation has to roughly cover its own overhead and no more, or seeing
## seven people a day becomes a business model and the premise inverts a second
## time: the whole game rests on beds being where the money is. Finding a reason
## to admit somebody is worth more than a hundred consultations, which is
## exactly the pressure this is here to create.
const FEES := {
	"physical": 300,
	"followup": 120,
	"surgery": 4600,
	"discharge": 150,
}

## What it costs the hospital to have somebody sit in the treatment bay and be
## seen. Charged whether or not you find anything.
const CLINIC_OVERHEAD := 265

## And what it costs to open a theatre: staff, time, consumables. A by-the-book
## operation clears about seven hundred pounds, which is real money and nothing
## like enough to live on. The reason surgery is worth having on your list is
## not the fee — it is that an operation is the most deniable place in the
## building for something to go wrong, and a complication is a fortnight of bed
## days. Beds remain the business model. They have to.
const THEATRE_COST := 3850

const LABELS := {
	"physical": "Routine physical",
	"followup": "Post-procedure review",
	"surgery": "Scheduled procedure",
	"discharge": "Discharge and take-home",
}

var patient_system: PatientSystem = null
var economy: EconomySystem = null

## {id, kind, patient_id, name, hour, done, missed, arrived}
var list: Array[Dictionary] = []
var _next_id := 1

func _ready() -> void:
	add_to_group("appointment_system")
	patient_system = get_tree().get_first_node_in_group("patient_system")
	economy = get_tree().get_first_node_in_group("economy")
	EventBus.hour_tick.connect(_on_hour)

# ------------------------------------------------------------------ building
func build_for_shift() -> void:
	list.clear()
	var spec := GameState.shift_spec()
	var count := int(spec.get("appointments", 5))
	var start := GameState.shift_start_hour()
	var hours := GameState.shift_hours()
	for i in count:
		var hour := (start + int(float(i) * float(hours) / float(count))) % 24
		var entry := _make(hour)
		if not entry.is_empty():
			list.append(entry)
	roster_changed.emit()
	_announce_next()

## Pick a kind that there is actually somebody for. Everything except a physical
## needs a patient already on the ward, and on a quiet night there may not be
## one — so the clinic is the fallback, which is also the correct fallback:
## somebody can always walk in.
func _make(hour: int) -> Dictionary:
	var admitted := patient_system.active()
	var kind := "physical"
	if not admitted.is_empty():
		var weights := {"physical": 1.6, "followup": 1.2}
		var ready_to_go: Array = []
		var operable: Array = []
		for p in admitted:
			if p.ready_for_discharge():
				ready_to_go.append(p)
			if not p.acquired_injuries().is_empty() or p.recovery < 0.5:
				operable.append(p)
		if not ready_to_go.is_empty():
			weights["discharge"] = 1.4
		if not operable.is_empty():
			weights["surgery"] = 0.9
		kind = String(RNG.pick_weighted("appt_kind", weights))

	var p: Patient = null
	match kind:
		"physical":
			p = patient_system.book_walkin()
		"discharge":
			p = _pick(admitted, func(q): return q.ready_for_discharge())
		"surgery":
			p = _pick(admitted, func(q): return not q.acquired_injuries().is_empty() or q.recovery < 0.5)
		_:
			p = _pick(admitted, func(_q): return true)
	if p == null:
		return {}
	var id := "appt_%d" % _next_id
	_next_id += 1
	return {
		"id": id, "kind": kind, "patient_id": p.id, "name": p.display_name,
		"complaint": p.presenting_complaint, "hour": hour,
		"done": false, "missed": false, "arrived": kind != "physical",
	}

func _pick(pool: Array, filter: Callable) -> Patient:
	var eligible: Array = []
	for p in pool:
		if filter.call(p):
			eligible.append(p)
	if eligible.is_empty():
		return null
	return RNG.pick("appt_patient", eligible)

# ------------------------------------------------------------------ the day
func _on_hour(hour: int) -> void:
	if GameState.phase != GameState.Phase.SHIFT:
		return
	for e in list:
		if e["done"] or e["missed"] or e["arrived"] or int(e["hour"]) != hour:
			continue
		e["arrived"] = true
		var p = patient_system.get_patient(String(e["patient_id"]))
		if p != null:
			patient_system.arrive_walkin(p)
	_expire_past(hour)
	roster_changed.emit()
	_announce_next()

## A slot you are two hours past is a slot you did not turn up for. Being late is
## survivable; not coming at all is a thing the person sitting there tells
## somebody about.
func _expire_past(hour: int) -> void:
	for e in list:
		if e["done"] or e["missed"]:
			continue
		var late := hour - int(e["hour"])
		if late < 0:
			late += 24
		if late >= 3:
			e["missed"] = true
			_on_missed(e)

func _on_missed(e: Dictionary) -> void:
	var p = patient_system.get_patient(String(e["patient_id"]))
	EventBus.toast.emit("%s was not seen." % String(e["name"]), "bad")
	GameState.adjust_rep("patient_sat", -0.03)
	GameState.adjust_rep("insurer_trust", -0.015)
	if p == null:
		return
	p.satisfaction = clampf(p.satisfaction - 0.3, 0.0, 1.0)
	if not p.admitted:
		patient_system.send_home(p, "left_unseen")
		GameState.adjust_rep("hospital", -0.02)

# ------------------------------------------------------------------ completion
## Called by whichever act satisfies the slot. Returns the fee earned, or 0.
func complete(kind: String, patient_id: String) -> int:
	for e in list:
		if e["done"] or e["missed"]:
			continue
		if String(e["kind"]) != kind or String(e["patient_id"]) != patient_id:
			continue
		e["done"] = true
		var fee := int(FEES.get(kind, 0))
		if economy != null:
			economy.bill_procedure("%s — %s" % [String(LABELS.get(kind, kind)),
				String(e["name"])], fee)
			if kind == "physical":
				economy.bill_procedure_cost("clinic overhead — %s" % String(e["name"]),
					CLINIC_OVERHEAD)
			elif kind == "surgery":
				economy.bill_procedure_cost("theatre time — %s" % String(e["name"]),
					THEATRE_COST)
		roster_changed.emit()
		_announce_next()
		return fee
	return 0

func next_due() -> Dictionary:
	for e in list:
		if not e["done"] and not e["missed"]:
			return e
	return {}

func remaining() -> int:
	var n := 0
	for e in list:
		if not e["done"] and not e["missed"]:
			n += 1
	return n

func _announce_next() -> void:
	if GameState.phase != GameState.Phase.SHIFT:
		return
	var e := next_due()
	if e.is_empty():
		EventBus.objective_changed.emit("List cleared. The rest of the shift is yours.")
		return
	EventBus.objective_changed.emit("%02d:00  %s — %s" % [
		int(e["hour"]), String(LABELS.get(String(e["kind"]), "")), String(e["name"])])

## Everything still outstanding when you clock out. Walk-ins go home; admitted
## patients simply remember.
func settle_unseen() -> int:
	var n := 0
	for e in list:
		if e["done"] or e["missed"]:
			continue
		e["missed"] = true
		_on_missed(e)
		n += 1
	return n

# ------------------------------------------------------------------ save/load
func to_dict() -> Dictionary:
	return {"list": list, "next": _next_id}

func from_dict(d: Dictionary) -> void:
	list.clear()
	for e in d.get("list", []):
		list.append(e)
	_next_id = int(d.get("next", 1))
	roster_changed.emit()
