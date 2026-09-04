class_name PatientSystem
extends Node
## Puts the five written people into the five beds, and keeps track of which
## body belongs to whom.
##
## The old version of this file was nine hundred lines: admissions, walk-ins,
## trolleys, overflow, recovery ticks, environmental complications, visitors,
## discharge queues and a readmission table. A vertical slice has five people
## who are already here. This is what is left.

var patients: Dictionary = {}     ## case id -> Patient
var bodies: Dictionary = {}       ## case id -> PatientNPC

@onready var hospital = get_tree().get_first_node_in_group("hospital")

func _ready() -> void:
	# SOMEBODY YOU SEND HOME GOES HOME.
	#
	# `PatientNPC.discharge_and_leave()` existed, was written carefully — it
	# wakes them, frees the bed, walks them out, gives them a line on the way —
	# and had no callers anywhere in the project. So you discharged somebody at
	# nine in the morning and they lay in the bed until eight at night, and the
	# ward at the end of a shift where you sent four people home looked exactly
	# like the ward at the start of it. The one decision the game is made of had
	# no visible consequence in the world at all.
	call_deferred("_hook_the_day")
	add_to_group("patient_system")

func populate() -> void:
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	for c in Cases.roster():
		var p := Patient.from_case(c)
		p.archetype = _archetype_for(c)
		p.mind = DB.make_mind(p.id, p.display_name, "patient", p.archetype)
		patients[p.id] = p
		_spawn(p, sus)
	# Ruth arrives at seven, reads her mother's chart, and is a retired ward
	# sister. She is the only visitor and she is worth more than five.
	Log.i("ward populated: %d patients" % patients.size(), "Ward")

## Never exposed to the player as a label. It decides how observant somebody is
## and how readily they agree with a doctor, and the player is expected to work
## that out by talking to them.
func _archetype_for(c: Dictionary) -> String:
	var sugg := float(c.get("suggestible", 0.4))
	if sugg >= 0.7:
		return "trusting"
	if sugg <= 0.25:
		return "observant"
	return "stoic"

func _spawn(p: Patient, sus) -> void:
	var bed = _bed(p.bed_index)
	var npc := PatientNPC.new()
	npc.name = "Patient_" + p.id
	npc.display = p.display_name
	npc.archetype = p.archetype
	npc.set_colours(p.skin_tone, p.shirt_color, Color(0.22, 0.16, 0.12))
	_parent().add_child(npc)
	npc.bind(p, bed)
	if bed:
		npc.global_position = bed.global_position + Vector3(0, 0.5, 0)
	elif hospital:
		npc.global_position = hospital.point_in("ward")
	bodies[p.id] = npc
	npc.tree_exiting.connect(func(): bodies.erase(p.id))
	if sus:
		sus.register(p.mind, npc)

func _parent() -> Node:
	return hospital if hospital != null else self

func _bed(index: int):
	var found: Array = []
	for b in get_tree().get_nodes_in_group("bed"):
		found.append(b)
	found.sort_custom(func(a, c): return a.global_position.x < c.global_position.x)
	return found[index - 1] if index >= 1 and index <= found.size() else null

## Every read of `bodies` goes through here. Reading a freed node into a TYPED
## local aborts the calling function rather than yielding null, which is the
## single most expensive bug this project ever had.
## A new day on the same ward: everybody who went home last night is replaced by
## somebody with the same name and the same problem, because a vertical slice
## has one authored roster and the point of a second day is the STATE you carry
## into it, not new content.
## TOMORROW IS FIVE DIFFERENT PEOPLE.
##
## This woke yesterday's patients up and marked them a day older, which was
## right while there was one authored ward and wrong the moment there were two:
## day two opened with Hal Brennan's name floating over a bed belonging to
## Tallulah Ferreira, because the bodies were never rebuilt. Anybody still on
## the ward whose id is not on today's roster has gone home; anybody on today's
## roster who is not in a bed needs one.
func reset_day() -> void:
	var wanted := {}
	for c in Cases.roster():
		wanted[String(c["id"])] = c

	# Yesterday's ward goes home, bodies and all.
	for id in patients.keys():
		if wanted.has(id):
			continue
		var old_body = get_body(id)
		if old_body != null:
			bodies.erase(id)
			old_body.queue_free()
		patients.erase(id)

	var sus = get_tree().get_first_node_in_group("suspicion_system")
	for id in wanted:
		if patients.has(id) and get_body(id) != null:
			var p: Patient = patients[id]
			p.discharged = false
			p.days_admitted += 1.0
			var b = get_body(id)
			if b != null and b.has_method("wake_up"):
				b.wake_up("morning")
			continue
		# New face, new bed.
		var np := Patient.from_case(wanted[id])
		np.archetype = _archetype_for(wanted[id])
		np.mind = DB.make_mind(np.id, np.display_name, "patient", np.archetype)
		patients[np.id] = np
		_spawn(np, sus)
	Log.i("ward re-populated for day %d: %d patients" % [GameState.day, patients.size()], "Ward")

func get_body(id: String):
	var b = bodies.get(id, null)
	if b != null and not is_instance_valid(b):
		bodies.erase(id)
		return null
	return b

func get_patient(id: String) -> Patient:
	return patients.get(id, null)

func active() -> Array:
	var out: Array = []
	for id in patients:
		var p: Patient = patients[id]
		if not p.discharged:
			out.append(p)
	return out

func active_count() -> int:
	return active().size()

func _hook_the_day() -> void:
	var w = get_tree().get_first_node_in_group("ward_day")
	if w == null or not w.has_signal("disposition_set"):
		return
	if not w.disposition_set.is_connected(_on_disposition):
		w.disposition_set.connect(_on_disposition)

func _on_disposition(pid: String, what: String) -> void:
	var body = get_body(pid)
	if body == null or not is_instance_valid(body):
		return
	if what == "discharge" and body.has_method("discharge_and_leave"):
		body.call("discharge_and_leave")
	elif what == "hold" and body.has_method("_return_to_bed"):
		# Changed your mind. They were halfway to the door.
		if int(body.get("state")) == 4:      # State.LEAVING
			body.call("_return_to_bed")
