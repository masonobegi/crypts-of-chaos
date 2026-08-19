class_name PatientNPC
extends NPCBody
## The body of an admitted patient. Holds a reference to the Patient data model
## (the truth layer) and expresses its state physically — symptom tints, shivering
## in a cold room, wandering into the corridor when nobody is looking.

enum State { IN_BED, SITTING, WANDERING, TALKING, LEAVING }

var data: Patient = null
var bed: PatientBed = null
var state: State = State.IN_BED
var _timer := 0.0
var _bark_timer := 0.0
var _symptom_mesh: MeshInstance3D = null
var _shiver := 0.0
var _reclined := false

func _ready() -> void:
	role = "patient"
	outfit = Color(0.72, 0.78, 0.82)     # gown
	super._ready()
	add_to_group("patient_npc")
	# Sits above the head whichever way up the patient is.
	_symptom_mesh = Build.mi(Build.sphere_mesh(0.22), Build.unshaded(Color(1, 1, 1, 0.0)),
		Vector3(0, 1.15, 0))
	_symptom_mesh.visible = false
	add_child(_symptom_mesh)
	_timer = RNG.randf_range_s("patient_idle_t", 8.0, 20.0)

func bind(p: Patient, p_bed: PatientBed) -> void:
	data = p
	bed = p_bed
	npc_id = p.id
	display = p.display_name
	archetype = p.archetype
	skin = p.skin_tone
	outfit = p.shirt_color
	if p_bed:
		p_bed.patient_id = p.id
		p_bed.occupant = self

func _physics_process(delta: float) -> void:
	_hold_bed_pose(delta)
	super._physics_process(delta)
	_timer -= delta
	_bark_timer = maxf(0.0, _bark_timer - delta)
	_tick_state(delta)
	_tick_symptoms(delta)

## While in bed the patient is pinned to the bed's mount point — which means
## wheeling the bed wheels the patient, exactly as it should.
func _hold_bed_pose(_delta: float) -> void:
	var in_bed := state == State.IN_BED and bed != null and is_instance_valid(bed)
	if in_bed != _reclined:
		_reclined = in_bed
		set_reclined(in_bed)
	if not in_bed:
		return
	global_position = bed.global_position
	rotation.y = bed.rotation.y
	velocity = Vector3.ZERO

func _tick_state(_delta: float) -> void:
	if data == null or data.discharged:
		return
	match state:
		State.IN_BED:
			if _timer <= 0.0:
				_timer = RNG.randf_range_s("patient_idle_t", 10.0, 24.0)
				_maybe_bark()
				_maybe_wander()
		State.WANDERING:
			if not is_moving():
				_timer -= 1.0
				if _timer <= 0.0:
					_return_to_bed()
		State.LEAVING:
			if not is_moving():
				queue_free()
		_:
			pass

func _maybe_bark() -> void:
	if _bark_timer > 0.0 or data == null:
		return
	_bark_timer = 6.0
	var r = _room_node()
	var gripes: Array = r.complaints() if r else []
	if not gripes.is_empty() and RNG.chance("patient_env_bark", 0.6):
		say("Sorry — %s." % String(RNG.pick("gripe_p", gripes)), 3.2)
		# Complaining is not evidence, but it IS a satisfaction hit, and
		# satisfaction failure is its own way to lose.
		data.satisfaction = clampf(data.satisfaction - 0.03, 0.0, 1.0)
		return
	if data.is_overdue() and RNG.chance("patient_overdue_bark", 0.7):
		say(Dialogue.patient_overdue(data), 4.0)
		return
	say(Dialogue.patient_idle(data), 3.0)

## Patients wander. A confused one wanders more; an escaped patient in the
## corridor is a first-class distraction that you did not have to cause.
func _maybe_wander() -> void:
	if data == null:
		return
	var urge := 0.06
	if data.archetype == "confused":
		urge = 0.4
	elif data.archetype == "confrontational" and data.is_overdue():
		urge = 0.35
	elif data.archetype == "paranoid":
		urge = 0.18
	if data.recovery < 0.25:
		urge *= 0.3      # too unwell to get up
	if not RNG.chance("patient_wander", urge):
		return
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return
	state = State.WANDERING
	_timer = 12.0
	goto(h.point_in("corridor", "patient_wander_pt"))
	say(String(RNG.pick("wander_bark", [
		"I'm just going to stretch my legs.", "Where's the tea?",
		"I need to speak to someone.", "Is this the way out?",
	])), 3.0)
	WorldEvent.new("patient_wandering", "").at(global_position, current_room()) \
		.about(data.id).heard(0.0, 10.0).tag("chaos") \
		.says("%s is out of bed" % data.display_name).emit()

func _return_to_bed() -> void:
	if bed == null or not is_instance_valid(bed):
		state = State.IN_BED
		return
	goto(bed.global_position)
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(self):
		state = State.IN_BED

func _tick_symptoms(delta: float) -> void:
	if data == null or _symptom_mesh == null:
		return
	var comps := data.active_complications()
	if comps.is_empty():
		_symptom_mesh.visible = false
	else:
		# The most severe complication tints a halo over the patient, so you can
		# read "something is wrong in here" from the doorway.
		var worst: Complication = comps[0]
		for c in comps:
			if c.severity > worst.severity:
				worst = c
		_symptom_mesh.visible = true
		var col := worst.symptom_color
		col.a = 0.35 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.003)
		_symptom_mesh.material_override = Build.unshaded(col)

	var r = _room_node()
	if r and r.temperature < 16.0:
		_shiver = minf(_shiver + delta, 1.0)
	else:
		_shiver = maxf(_shiver - delta * 0.5, 0.0)
	if _shiver > 0.05 and _symptom_mesh:
		_symptom_mesh.position.x = sin(float(Time.get_ticks_msec()) * 0.04) * 0.02 * _shiver

## Patients react to chaos, which is most of the reason chaos is worth causing.
## Perception calls this on anything within hearing range.
func on_heard_noise(evt: WorldEvent) -> void:
	if data == null or data.discharged:
		return
	var dist := global_position.distance_to(evt.pos)
	var strength := clampf(1.0 - dist / maxf(evt.hear_radius, 1.0), 0.15, 1.0)
	startle(strength)
	# Applied BEFORE the bark gate: being startled costs a little satisfaction
	# whether or not they happen to say something about it. A ward full of
	# startled patients is unsettled, so noise is never entirely free.
	data.satisfaction = clampf(data.satisfaction - 0.012 * strength, 0.0, 1.0)
	var r = _room_node()
	if r:
		r.add_noise(0.35 * strength)
	if _bark_timer > 0.0 or not RNG.chance("patient_startle_bark", 0.45 * strength):
		return
	_bark_timer = 5.0
	# Personality decides whether a crash is frightening, annoying, or a
	# development they intend to write down.
	match data.archetype:
		"paranoid": say(String(RNG.pick("startle_par", [
			"What was that? What WAS that?", "Somebody's doing something.",
			"That wasn't nothing."])), 3.0)
		"confrontational": say(String(RNG.pick("startle_conf", [
			"Oh, for God's sake.", "Is anyone running this place?",
			"That's the third time."])), 3.0)
		"observant": say(String(RNG.pick("startle_obs", [
			"That came from the corridor.", "Something went over.",
			"That was near 103."])), 3.0)
		"hypochondriac": say(String(RNG.pick("startle_hypo", [
			"My heart. My actual heart.", "I felt that in my chest.",
			"I'll need to be monitored after that."])), 3.0)
		"confused": say(String(RNG.pick("startle_conf2", [
			"Is that the postman?", "Are we moving?", "Was that me?"])), 3.0)
		"stoic": say("Hm.", 2.0)
		_: say(String(RNG.pick("startle_any", [
			"Ooh.", "Everything alright out there?", "Goodness.",
			"That sounded expensive."])), 3.0)

func _room_node():
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return null
	return h.room(current_room())

func discharge_and_leave() -> void:
	state = State.LEAVING
	if bed:
		bed.occupant = null
	var h = get_tree().get_first_node_in_group("hospital")
	if h:
		goto(h.point_in("lobby", "discharge_pt"), false)
	say(String(RNG.pick("leave_bark", [
		"Thanks, doctor.", "Finally.", "I'll not be coming back here.",
		"Cheers. I think.",
	])), 4.0)

func prompt(_player) -> Array:
	if data == null:
		return ["", ""]
	var sub := data.condition_name()
	if data.is_overdue():
		sub += "  ·  %d days over" % int(data.days_admitted - data.expected_stay_days)
	return ["Talk to %s" % data.display_name, sub]

## Holding a treatment tool turns the prompt into the treatment itself.
func prompt_with_item(_player, held) -> Array:
	if data == null or held == null:
		return ["", ""]
	var tid := _treatment_for_item(held)
	if tid == "":
		return ["Talk to %s" % data.display_name, "that isn't a treatment"]
	return ["%s on %s" % [DB.treatment_name(tid), data.display_name], "[hold E]"]

func use_seconds(_player, held) -> float:
	if held == null or data == null:
		return 0.0
	var tid := _treatment_for_item(held)
	if tid == "":
		return 0.0
	return float(DB.treatment(tid).get("time", 2.0))

func _treatment_for_item(held) -> String:
	if held == null or not held.has_method("get_item_id"):
		return ""
	var item_id := String(held.call("get_item_id"))
	# A syringe does whatever is actually IN it, not what the label says.
	if held.contents != "":
		var as_treatment := Items.substance_effect(held.contents)
		if as_treatment != "":
			return as_treatment
	# One tool can serve several treatments (the wrench detorques a spleen AND
	# realigns wrist opinions). Prefer whichever is actually indicated for this
	# patient — otherwise picking up a wrench would silently perform the wrong
	# procedure depending on dictionary order.
	var fallback := ""
	for tid in DB.TREATMENTS:
		if String(DB.TREATMENTS[tid].get("tool", "")) != item_id:
			continue
		if DB.is_correct_treatment(data.condition_id, String(tid)):
			return String(tid)
		if fallback == "":
			fallback = String(tid)
	return fallback

func interact(player, held) -> void:
	if data == null:
		return
	if held != null:
		var tid := _treatment_for_item(held)
		if tid != "":
			EventBus.request_ui.emit("apply_treatment", {
				"patient_id": data.id, "treatment_id": tid, "item": held,
			})
			return
	look_toward(player.global_position if player else global_position)
	state = State.TALKING
	EventBus.request_ui.emit("dialogue", {"npc_id": data.id})
