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

	# A confused patient loses track of the date; an observant one absolutely
	# does not. This is a large part of what makes a given patient worth holding.
	p.knows_expected_date = true
	if p.archetype == "confused":
		p.knows_expected_date = RNG.chance("knows_date", 0.2)
	elif p.archetype == "trusting":
		p.knows_expected_date = RNG.chance("knows_date", 0.7)
	elif p.archetype in ["observant", "paranoid", "litigious"]:
		p.knows_expected_date = true

	p.mind = DB.make_mind(p.id, p.display_name, "patient", p.archetype)
	# Psychiatric admissions are, by the nature of why they are here, paying
	# very close attention to how they are being treated.
	if String(cond.get("dept", "ward")) == "psych":
		p.mind.observance = clampf(p.mind.observance + 0.35, 0.0, 1.0)
		p.mind.skepticism = clampf(p.mind.skepticism + 0.2, 0.0, 1.0)
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
		if taken:
			continue
		# A ward somebody has wheeled the bed out of is not a free bed, it is an
		# empty room. Without this, stripping the floor of beds would read as
		# five vacancies.
		if _bed_in(key) == null:
			continue
		out.append(key)
	return out

func admit(p: Patient, ward_key := "") -> bool:
	if ward_key == "":
		var free := free_wards()
		if free.is_empty():
			# With Emergency open there is somewhere to put them: a trolley in
			# Intake. They are admitted, they are billing, and they are lying in
			# the busiest room in the building where everyone can see them.
			# Nobody has to decide that is acceptable — it just is, until it is
			# not.
			if hospital != null and hospital.is_room_open("intake") and free_trolleys() > 0:
				ward_key = "intake"
			else:
				waiting.append(p)
				EventBus.toast.emit("%s is waiting in the lobby — no free bed." % p.display_name, "info")
				return false
		else:
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
	# Discharged patients walk out and free themselves. See get_body(): a freed
	# node left in this dictionary breaks every later read of it.
	npc.tree_exiting.connect(func(): bodies.erase(p.id))
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

## An unoccupied bed standing in this room, or failing that any bed in it.
##
## Matched on where the bed ACTUALLY IS rather than on the room it was built in.
## Beds are rigid bodies on wheels; anyone can push one anywhere, and a bed that
## has been wheeled out of Room 103 is not a bed in Room 103 however it was
## labelled at build time. Intake also has three of them, so "the first one that
## matches" stopped being good enough.
func _bed_in(ward_key: String) -> PatientBed:
	var fallback: PatientBed = null
	for b in get_tree().get_nodes_in_group("bed"):
		if _bed_room(b) != ward_key:
			continue
		if b.occupant == null or not is_instance_valid(b.occupant):
			return b
		if fallback == null:
			fallback = b
	return fallback

func _bed_room(b) -> String:
	if hospital == null or not b.is_inside_tree():
		return String(b.room_key)
	var where := hospital.room_at(b.global_position)
	return where if where != "" else String(b.room_key)

## How many trolleys are standing empty in Intake right now.
func free_trolleys() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("bed"):
		if _bed_room(b) == "intake" and (b.occupant == null or not is_instance_valid(b.occupant)):
			n += 1
	return n

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
		var body = get_body(id)
		var room_key: String = body.current_room() if body else p.room
		var r: Room = hospital.room(room_key) if hospital else null
		p.env_modifier = r.comfort() if r else 1.0
		_reconcile_room(p, body)
		var before_ready := p.ready_for_discharge()
		p.tick(days)
		# A trolley in the middle of Emergency Intake is not a room. Nobody
		# sleeps, nobody has any privacy, and the whole hospital walks past.
		# Being parked there costs goodwill roughly four times as fast as simply
		# being kept too long, which is what makes "who do I discharge to free a
		# bed" a decision rather than an inconvenience.
		if room_key == "intake":
			p.corridor_minutes += days * float(GameState.MINUTES_PER_DAY)
			p.satisfaction = clampf(p.satisfaction - 0.24 * days
				* DB.trait_of(p.archetype, "impatience", 1.0), 0.0, 1.0)
		elif WARD_KEYS.has(room_key):
			p.corridor_minutes = 0.0
		_maybe_complain(p)
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

	var body = get_body(p.id)
	if body:
		body.say(String(RNG.pick("comp_bark", [
			"Ohh. That's new.", "Something's happening.", "I don't feel right.",
			"Was that meant to—", "Oh, that's not good.",
		])), 3.4)
		body.startle(0.8)
	EventBus.toast.emit("%s: %s" % [p.display_name, c.display_name], "suspicion")
	return c

## Somebody walked in and saw it.
##
## This is the other half of the game's central mechanic and it was missing:
## Complication.noticed_time was read by the records system and set by nothing,
## so "document it BEFORE anyone notices" was free — every plausible cause filed
## at any time counted as clean. Now there is a real window between a
## complication appearing and the next person walking into that room.
func notice_complication(p: Patient, comp: Complication, by_id: String, by_name: String) -> void:
	if comp.resolved or comp.noticed_by.has(by_id):
		return
	comp.noticed_by.append(by_id)
	if comp.noticed_time < 0:
		comp.noticed_time = GameState.career_minutes
		# The first person to see it is the one that costs you. After that it is
		# already common knowledge on the ward.
		EventBus.toast.emit("%s noticed %s's %s." % [by_name, p.display_name, comp.display_name],
			"suspicion" if comp.documented_cause == "" else "info")

## Undocumented complications a given observer would spot on this patient.
func unnoticed_complications(p: Patient) -> Array[Complication]:
	var out: Array[Complication] = []
	for c in p.active_complications():
		if c.noticed_time < 0:
			out.append(c)
	return out

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

	var body = get_body(p.id)
	if body:
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
	elif WARD_KEYS.has(p.room):
		# Nobody in the lobby, but somebody may be lying on a trolley in Intake.
		# A ward that has just come free is where they go.
		call_deferred("_relieve_intake", p.room)

## Move whoever has been on an Intake trolley longest into a ward that has just
## come free. Trolley time is meant to be a pressure the player feels and can
## shorten — by discharging somebody — not a state patients are abandoned in.
func _relieve_intake(ward_key: String) -> void:
	var oldest: Patient = null
	for id in patients:
		var p: Patient = patients[id]
		if p.discharged or p.room != "intake":
			continue
		if oldest == null or p.days_admitted > oldest.days_admitted:
			oldest = p
	if oldest == null:
		return
	if transfer(oldest, ward_key):
		EventBus.toast.emit("%s finally has a bed." % oldest.display_name, "good")

## Move an admitted patient to another room, bed, chart and all. Deliberately
## moves the EXISTING body rather than freeing it and spawning a new one: the
## body is registered with the suspicion system and carries its own tree_exiting
## hooks, and tearing it down mid-career throws all of that away.
func transfer(p: Patient, ward_key: String) -> bool:
	var bed := _bed_in(ward_key)
	var body = get_body(p.id)
	if bed == null or body == null:
		return false
	var old = body.bed
	if old != null and is_instance_valid(old) and old != bed:
		old.occupant = null
		old.patient_id = ""
	body.bind(p, bed)
	body.global_position = bed.global_position + Vector3(0, 0.5, 0)
	p.room = ward_key

	var chart = charts.get(p.id, null)
	if chart != null and is_instance_valid(chart):
		chart.global_position = bed.global_position + Vector3(0.0, 1.05, 1.15)

	for f in get_tree().get_nodes_in_group("fixture"):
		if f is VitalsConsole and f.room_key == ward_key:
			f.patient_id = p.id
		elif f is TreatmentMachine and f.room_key == ward_key:
			f.set_prescribed_for(p)
	return true

## Being bad at your job is its own failure state, with nothing to do with
## suspicion. A patient who has been kept too long in a cold room, or parked on
## a trolley for a day, eventually complains about their CARE — and a complaint
## is heat, and heat is what brings people to look at you. Nothing about this
## path requires anybody to suspect a thing.
func _maybe_complain(p: Patient) -> void:
	if p.complained or p.mind == null or p.satisfaction > 0.18:
		return
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus == null:
		return
	p.complained = true
	var severity := clampf(0.35 + (0.18 - p.satisfaction) * 2.0, 0.35, 0.8)
	sus.file_complaint(p.mind.id, severity)

## Which room a patient is IN is a question about where their bed has ended up,
## not about where they were admitted. Wheeling somebody out of Room 103 and
## leaving them on the floor of Intake genuinely frees Room 103 for a
## better-insured admission, and genuinely costs the patient who was moved.
##
## Their chart does NOT follow them. A chart in the wrong room is already one of
## the more findable things in the record, and there is no reason wheeling the
## bed should tidy that up for you.
func _reconcile_room(p: Patient, body) -> void:
	if body == null or hospital == null:
		return
	var bed = body.bed
	if bed == null or not is_instance_valid(bed) or not bed.is_inside_tree():
		return
	var where := hospital.room_at(bed.global_position)
	if where == "" or where == p.room:
		return
	# Only somewhere a patient can legitimately be kept counts. A bed parked in
	# the corridor for ten seconds while you get a door open is not a transfer.
	if not (WARD_KEYS.has(where) or where == "intake"):
		return
	var was_ward: bool = WARD_KEYS.has(p.room)
	p.room = where
	EventBus.patient_state_changed.emit(p)
	if was_ward and where == "intake":
		_announce_ramp(p, body, bed)

## Somebody has just wheeled an admitted patient out of a ward and left them in
## the middle of Emergency Intake. This is a legitimate thing a hospital does
## when it has run out of beds, and an indefensible thing to do when it has not
## — so the difference is exactly what decides whether there is a cover story
## for it.
func _announce_ramp(p: Patient, body, bed) -> void:
	var somewhere_else := false
	for key in WARD_KEYS:
		if key == p.room:
			continue
		var taken := false
		for id in patients:
			var q: Patient = patients[id]
			if not q.discharged and q.room == key:
				taken = true
		if not taken and _bed_in(key) != null:
			somewhere_else = true
	if not somewhere_else:
		# The ward genuinely was full. Nobody can argue with that today.
		GameState.add_cover("bed_shortage", 420)

	if body != null and is_instance_valid(body):
		body.say(String(RNG.pick("ramp_bark", [
			"Am I staying out here?", "There's a lot of people out here.",
			"Is this my room now?", "I can hear everything from here.",
		])), 3.6)
	WorldEvent.new("patient_moved_to_corridor", "player") \
		.at(bed.global_position, "intake").about(p.id) \
		.seen(0.45).heard(0.05, 16.0).tag("patient").tag("ramping") \
		.cover("bed_shortage") \
		.says("%s has been moved out to Intake" % p.display_name).emit()

# ================================================================ queries
func get_patient(id: String) -> Patient:
	return patients.get(id, null)

## Every read of `bodies` goes through here. Reading a freed node into a
## `var b: PatientNPC` local raises "Trying to assign invalid previously freed
## instance" and ABORTS THE WHOLE FUNCTION rather than yielding null, so the
## is_instance_valid check on the following line never gets to run — one
## discharged patient could stop tick() from advancing anybody else.
func get_body(id: String):
	var b = bodies.get(id, null)
	if b == null or not is_instance_valid(b):
		bodies.erase(id)
		return null
	return b

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
	var b = get_body(p.id)
	if b:
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
