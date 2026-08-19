class_name PatientSystem
extends Node
## Owns every admitted patient: procedural generation, admission, the hidden
## recovery simulation, complications, visitors and discharge.

const MAX_BEDS := 5
const WARD_KEYS := ["ward_101", "ward_102", "ward_103", "ward_104", "ward_105"]

var patients: Dictionary = {}          ## id -> Patient
var bodies: Dictionary = {}            ## id -> PatientNPC
var charts: Dictionary = {}            ## id -> chart Prop
var waiting: Array[Patient] = []       ## admitted to the lobby, not yet in a bed
var _next_id := 1
var _visitor_pool: Array = []

@onready var hospital: Hospital = get_tree().get_first_node_in_group("hospital")

func _ready() -> void:
	add_to_group("patient_system")
	EventBus.hour_tick.connect(_on_hour)

## Where spawned bodies, charts and visitors are parented. Deliberately NOT
## get_tree().current_scene: that is null whenever the game is instantiated into
## the tree rather than loaded as the current scene (headless runs, tests, and
## any future in-game level swap), which silently drops every spawn.
func spawn_parent() -> Node:
	var p := get_parent()
	if p != null:
		return p
	return get_tree().current_scene if get_tree().current_scene != null else get_tree().root

# ================================================================ generation
## Build a brand new patient. Everything about them is rolled: condition,
## personality, insurance, how much they are worth, and whether someone is going
## to turn up and ask questions about them.
func generate(force_condition := "") -> Patient:
	var p := Patient.new("p%d" % _next_id)
	_next_id += 1

	p.display_name = "%s %s" % [
		RNG.pick("patient_name", DB.FIRST_NAMES),
		RNG.pick("patient_name", DB.LAST_NAMES)]
	p.age = RNG.randi_range_s("patient_age", 19, 88)
	p.skin_tone = _skin_tone()
	p.shirt_color = Color(RNG.randf_range_s("patient_col", 0.3, 0.9),
		RNG.randf_range_s("patient_col", 0.3, 0.9),
		RNG.randf_range_s("patient_col", 0.3, 0.9))

	p.condition_id = force_condition if force_condition != "" else _roll_condition()
	var cond: Dictionary = DB.condition(p.condition_id)
	p.expected_stay_days = float(cond.get("base_days", 2.0)) * RNG.randf_range_s("patient_stay", 0.85, 1.2)
	p.recovery_rate = 1.0 / maxf(p.expected_stay_days, 0.4)
	p.base_daily_revenue = int(float(cond.get("revenue", 900)) * RNG.randf_range_s("patient_rev", 0.85, 1.2))

	p.archetype = _roll_archetype()
	p.insurance = _roll_insurance()
	p.admitted_on_day = GameState.day
	p.satisfaction = RNG.randf_range_s("patient_sat", 0.55, 0.85)

	p.chart.recorded_condition = p.condition_id
	p.chart.promised_discharge_day = p.admitted_on_day + int(ceil(p.expected_stay_days))

	p.mind = DB.make_mind(p.id, p.display_name, "patient", p.archetype)
	return p

func _skin_tone() -> Color:
	var tones := [
		Color(0.95, 0.83, 0.72), Color(0.87, 0.72, 0.60), Color(0.76, 0.60, 0.46),
		Color(0.60, 0.44, 0.32), Color(0.44, 0.31, 0.22), Color(0.33, 0.23, 0.17),
	]
	return RNG.pick("patient_skin", tones)

## Better hospital reputation attracts better-insured patients. This is the
## strategic pull toward occasionally being a good doctor.
func _roll_insurance() -> String:
	var rep := GameState.rep("hospital")
	var weights := {
		"none": 1.6 - rep, "bad": 1.4 - rep * 0.5, "standard": 1.2,
		"good": 0.35 + rep * 1.1, "excellent": 0.12 + rep * 1.0,
		"platinum": maxf(0.0, rep - 0.55) * 0.9,
	}
	return String(RNG.pick_weighted("patient_ins", weights))

func _roll_condition() -> String:
	var weights := {}
	for id in DB.CONDITIONS:
		var c: Dictionary = DB.CONDITIONS[id]
		if not GameState.unlocked_departments.has(String(c.get("dept", "ward"))):
			continue
		# Long, lucrative conditions get rarer so they feel like a score when
		# they walk in rather than being the everyday case.
		weights[id] = 1.0 / maxf(1.0, float(c.get("base_days", 2.0)) * 0.55)
	return String(RNG.pick_weighted("patient_cond", weights))

func _roll_archetype() -> String:
	var weights := {
		"trusting": 1.5, "paranoid": 0.7, "hypochondriac": 0.8,
		"confrontational": 0.7, "confused": 0.6, "observant": 0.55,
		"stoic": 0.8, "litigious": 0.4,
	}
	# Government scrutiny quietly seeds the ward with people who pay attention.
	weights["observant"] += GameState.rep("gov_scrutiny") * 2.0
	weights["litigious"] += GameState.rep("gov_scrutiny") * 1.5
	return String(RNG.pick_weighted("patient_arch", weights))

# ================================================================ admission
func free_wards() -> Array[String]:
	var out: Array[String] = []
	# A room closed for deep cleaning is genuinely out of service for the day.
	var closed: String = WARD_KEYS[GameState.day % WARD_KEYS.size()] \
		if GameState.flag("bed_closed", false) else ""
	for key in WARD_KEYS:
		if key == closed:
			continue
		var taken := false
		for id in patients:
			var p: Patient = patients[id]
			if not p.discharged and p.room == key:
				taken = true
		if not taken:
			out.append(key)
	return out

func admit(p: Patient, ward_key := "") -> bool:
	if ward_key == "":
		var free := free_wards()
		if free.is_empty():
			waiting.append(p)
			EventBus.toast.emit("%s is waiting in the lobby — no free bed." % p.display_name, "info")
			return false
		ward_key = free[0]
	p.room = ward_key
	patients[p.id] = p

	var sus = get_tree().get_first_node_in_group("suspicion_system")
	_spawn_body(p, ward_key, sus)
	_spawn_chart(p, ward_key)

	GameState.stats.patients_admitted += 1
	EventBus.patient_admitted.emit(p)
	EventBus.toast.emit("%s admitted to %s — %s" % [
		p.display_name, hospital.room(ward_key).display, p.condition_name()], "info")
	_maybe_schedule_visitor(p)
	return true

func _spawn_body(p: Patient, ward_key: String, sus) -> void:
	var bed := _bed_in(ward_key)
	var npc := PatientNPC.new()
	npc.name = "Patient_" + p.id
	npc.set_colours(p.skin_tone, p.shirt_color, Color(0.22, 0.16, 0.12))
	npc.display = p.display_name
	npc.archetype = p.archetype
	spawn_parent().add_child(npc)
	npc.bind(p, bed)
	if bed:
		npc.global_position = bed.global_position + Vector3(0, 0.5, 0)
	else:
		npc.global_position = hospital.point_in(ward_key)
	bodies[p.id] = npc
	if sus:
		sus.register(p.mind, npc)
	# Point the ward's vitals console at whoever is actually in the bed.
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is VitalsConsole and f.room_key == ward_key:
			f.patient_id = p.id
	# And set the bedside machine's prescribed value from their condition.
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is TreatmentMachine and f.room_key == ward_key:
			f.set_prescribed_for(p)

func _spawn_chart(p: Patient, ward_key: String) -> void:
	var chart := Items.spawn("chart")
	spawn_parent().add_child(chart)
	if chart.has_method("bind"):
		chart.call("bind", p)
	var bed := _bed_in(ward_key)
	var pos: Vector3 = bed.global_position if bed else hospital.point_in(ward_key)
	chart.global_position = pos + Vector3(0.0, 1.05, 1.15)
	charts[p.id] = chart

func _bed_in(ward_key: String) -> PatientBed:
	for b in get_tree().get_nodes_in_group("bed"):
		if b.room_key == ward_key:
			return b
	return null

# ================================================================ visitors
func _maybe_schedule_visitor(p: Patient) -> void:
	var arch := String(RNG.pick_weighted("visitor_arch", {
		"absent": 1.0, "constant": 0.7, "questioner": 1.0,
		"litigious_family": 0.45, "knows_medicine": 0.5, "clueless": 0.9,
	}))
	if not RNG.chance("has_visitor", 0.72):
		return
	_visitor_pool.append({
		"patient_id": p.id, "archetype": arch,
		"first_visit_hour": RNG.randi_range_s("visit_hour", 9, 15),
	})

func _on_hour(hour: int) -> void:
	for v in _visitor_pool.duplicate():
		if int(v["first_visit_hour"]) != hour:
			continue
		var p: Patient = patients.get(String(v["patient_id"]), null)
		if p == null or p.discharged:
			_visitor_pool.erase(v)
			continue
		if not RNG.chance("visit_roll", DB.trait_of(String(v["archetype"]), "visit_rate", 0.5)):
			continue
		_spawn_visitor(p, String(v["archetype"]))

func _spawn_visitor(p: Patient, arch: String) -> void:
	var vis := VisitorNPC.new()
	vis.npc_id = "%s_family" % p.id
	vis.archetype = arch
	vis.display = "%s's %s" % [p.display_name.split(" ")[0],
		RNG.pick("relation", ["wife", "husband", "son", "daughter", "brother",
			"sister", "mother", "father", "partner", "flatmate"])]
	vis.set_colours(p.skin_tone, Color(RNG.randf_range_s("vis_col", 0.25, 0.6),
		RNG.randf_range_s("vis_col", 0.25, 0.6), RNG.randf_range_s("vis_col", 0.3, 0.6)),
		Color(0.2, 0.15, 0.12))
	spawn_parent().add_child(vis)
	vis.global_position = hospital.point_in("lobby", "visitor_spawn")
	var mind := DB.make_mind(vis.npc_id, vis.display, "family", arch)
	mind.patient_id = p.id
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus:
		sus.register(mind, vis)
	vis.begin_visit(p.id, p.room, RNG.randf_range_s("visit_len", 60.0, 200.0))
	EventBus.toast.emit("%s has arrived." % vis.display, "info")

# ================================================================ simulation
## Advance every patient's hidden state by `days`, applying the comfort of the
## room they are actually in right now.
func tick(days: float) -> void:
	for id in patients:
		var p: Patient = patients[id]
		if p.discharged:
			continue
		var body: PatientNPC = bodies.get(id, null)
		var room_key: String = body.current_room() if body and is_instance_valid(body) else p.room
		var r: Room = hospital.room(room_key) if hospital else null
		p.env_modifier = r.comfort() if r else 1.0
		var before_ready := p.ready_for_discharge()
		p.tick(days)
		_maybe_environmental_complication(p, r, days)
		if p.ready_for_discharge() and not before_ready:
			EventBus.toast.emit("%s is fit for discharge." % p.display_name, "good")
		EventBus.patient_state_changed.emit(p)

## Cold rooms, dark rooms and filthy rooms eventually produce complications with
## an entirely honest cause. Whether that cause ends up on the chart is your
## business.
func _maybe_environmental_complication(p: Patient, r: Room, days: float) -> void:
	if r == null or p.discomfort < 0.35:
		return
	if not RNG.chance("env_comp", p.discomfort * days * 0.7):
		return
	var comp_id := "draft_exposure"
	if not r.lights_on:
		comp_id = "nocturnal_confusion"
	elif r.cleanliness < 0.4:
		comp_id = "secondary_beige"
	add_complication(p, comp_id, "facilities")
	p.discomfort = 0.0

## The core money-making verb. `true_cause` is what the simulation knows;
## documenting it is a separate, deliberate act at a terminal.
func add_complication(p: Patient, comp_id: String, true_cause: String) -> Complication:
	var spec: Dictionary = DB.COMPLICATIONS.get(comp_id, {})
	if spec.is_empty():
		return null
	var c := Complication.new()
	c.id = comp_id
	c.display_name = String(spec.get("name", comp_id))
	c.days_added = float(spec.get("days", 1.0)) * RNG.randf_range_s("comp_days", 0.8, 1.3)
	c.recovery_delta = float(spec.get("rec", -0.05))
	c.severity = float(spec.get("sev", 0.3))
	c.symptom = String(spec.get("symptom", ""))
	c.symptom_color = spec.get("color", Color.WHITE)
	c.true_cause = true_cause
	c.plausible_causes = PackedStringArray(spec.get("causes", []))
	p.add_complication(c)
	GameState.stats.complications_caused += 1

	# The onset is physically observable — this is the "patient suddenly got
	# worse right after you treated them" tell that makes timing matter.
	WorldEvent.new("complication_onset", "").at(_position_of(p), p.room).about(p.id) \
		.seen(0.0).heard(0.0, 6.0).tag("clinical") \
		.says("%s developed %s" % [p.display_name, c.display_name]).emit()

	var body: PatientNPC = bodies.get(p.id, null)
	if body and is_instance_valid(body):
		body.say(String(RNG.pick("comp_bark", [
			"Ohh. That's new.", "Something's happening.", "I don't feel right.",
			"Was that meant to—", "Oh, that's not good.",
		])), 3.4)
		body.startle(0.8)
	EventBus.toast.emit("%s: %s" % [p.display_name, c.display_name], "suspicion")
	return c

# ================================================================ discharge
func discharge(p: Patient, reason := "recovered") -> void:
	if p.discharged:
		return
	p.discharged = true
	p.discharge_reason = reason
	GameState.stats.patients_discharged += 1
	if p.recovery >= 0.98:
		GameState.stats.patients_cured += 1
	var overstay := p.days_admitted - p.expected_stay_days
	if p.days_admitted > float(GameState.stats.longest_stay):
		GameState.stats.longest_stay = p.days_admitted
		GameState.stats.longest_stay_name = p.display_name

	# Satisfaction at discharge moves reputation more than anything else.
	GameState.adjust_rep("patient_sat", (p.satisfaction - 0.5) * 0.08)
	GameState.adjust_rep("hospital", (p.satisfaction - 0.5) * 0.03)
	if reason == "recovered" and overstay < 0.3:
		GameState.adjust_rep("doctor", 0.02)
		if p.mind:
			p.mind.adjust_trust(0.15)

	var body: PatientNPC = bodies.get(p.id, null)
	if body and is_instance_valid(body):
		body.discharge_and_leave()
	var chart = charts.get(p.id, null)
	if chart and is_instance_valid(chart):
		chart.queue_free()
	charts.erase(p.id)

	EventBus.patient_discharged.emit(p, reason)
	EventBus.toast.emit("%s discharged after %.1f days (projected %.1f)." % [
		p.display_name, p.days_admitted, p.expected_stay_days],
		"good" if overstay < 0.5 else "money")

	# Fill the bed if anyone is waiting.
	if not waiting.is_empty():
		var next: Patient = waiting.pop_front()
		call_deferred("admit", next, p.room)

# ================================================================ queries
func get_patient(id: String) -> Patient:
	return patients.get(id, null)

func get_body(id: String) -> PatientNPC:
	return bodies.get(id, null)

func active() -> Array[Patient]:
	var out: Array[Patient] = []
	for id in patients:
		var p: Patient = patients[id]
		if not p.discharged:
			out.append(p)
	return out

func active_count() -> int:
	return active().size()

func total_daily_revenue() -> int:
	var total := 0
	for p in active():
		total += p.daily_revenue()
	return total

## Average days over projection across everyone currently admitted. This is the
## number an insurer's analytics team notices, and the number that ends careers.
func average_overstay() -> float:
	var list := active()
	if list.is_empty():
		return 0.0
	var total := 0.0
	for p in list:
		total += maxf(0.0, p.days_admitted - p.expected_stay_days)
	return total / float(list.size())

func _position_of(p: Patient) -> Vector3:
	var b: PatientNPC = bodies.get(p.id, null)
	if b and is_instance_valid(b):
		return b.global_position
	return hospital.point_in(p.room) if hospital else Vector3.ZERO

# ================================================================ save/load
func to_dict() -> Dictionary:
	var out := {}
	for id in patients:
		out[id] = (patients[id] as Patient).to_dict()
	var wait: Array = []
	for w in waiting:
		wait.append(w.to_dict())
	return {"patients": out, "next_id": _next_id, "waiting": wait, "visitors": _visitor_pool}

func from_dict(d: Dictionary) -> void:
	for id in bodies:
		var b = bodies[id]
		if is_instance_valid(b):
			b.queue_free()
	for id in charts:
		var c = charts[id]
		if is_instance_valid(c):
			c.queue_free()
	patients.clear()
	bodies.clear()
	charts.clear()
	waiting.clear()

	_next_id = int(d.get("next_id", 1))
	_visitor_pool = d.get("visitors", [])
	var stored: Dictionary = d.get("patients", {})
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	for id in stored:
		var p := Patient.from_dict(stored[id])
		patients[p.id] = p
		if not p.discharged:
			_spawn_body(p, p.room, sus)
			_spawn_chart(p, p.room)
	for w in d.get("waiting", []):
		waiting.append(Patient.from_dict(w))
