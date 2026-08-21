class_name Records
extends RefCounted
## Every chart entry on the ward, and the only place they live.
##
## There is no privileged view of this. The screen the player reads and the
## folder the ward sister opens in the morning are built from the same array by
## the same function. If she can see that a note was typed two hours late, so
## can you, before you go home.

var entries: Array = []            ## Array[ChartEntry]
var _next := 1

## Where somebody was seen, bucketed into quarter hours: "actor|bucket" ->
## {room, witness, expected}. Written by the world when an NPC sees the player.
var placements: Dictionary = {}

func add(e: ChartEntry) -> ChartEntry:
	if e.id == "":
		e.id = "e%d" % _next
		_next += 1
	entries.append(e)
	EventBus.emit_signal("chart_entry_written", e) if EventBus.has_signal("chart_entry_written") else null
	return e

func for_patient(pid: String) -> Array:
	var out: Array = []
	for e in entries:
		if e.patient_id == pid:
			out.append(e)
	out.sort_custom(func(a, b): return a.stated_minute < b.stated_minute)
	return out

func by_id(eid: String) -> ChartEntry:
	for e in entries:
		if e.id == eid:
			return e
	return null

## Somebody saw you at a terminal. This is the only way `author_elsewhere` ever
## fires, and it is why walking around matters.
func place(actor: String, minute: int, room: String, witness: String, expected: String) -> void:
	placements["%s|%d" % [actor, int(minute / 15)]] = {
		"room": room, "witness": witness, "expected": expected,
	}

## The chain of entries that argue a patient should still be here. This is what
## the reviewer walks when she asks "why was the bed still occupied".
func justification_chain(pid: String) -> Array:
	var out: Array = []
	for e in for_patient(pid):
		if e.supports_stay():
			out.append(e)
	return out

func to_dict() -> Dictionary:
	var arr: Array = []
	for e in entries:
		arr.append(e.to_dict())
	return {"entries": arr, "next": _next, "placements": placements}

func from_dict(d: Dictionary) -> void:
	entries.clear()
	for x in Array(d.get("entries", [])):
		entries.append(ChartEntry.from_dict(x))
	_next = int(d.get("next", 1))
	placements = Dictionary(d.get("placements", {}))
