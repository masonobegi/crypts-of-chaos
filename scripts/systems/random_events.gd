class_name RandomEventSystem
extends Node
## Daily disruptions. Events are chosen by weight with live conditions, so the
## ward's actual state decides what can happen — a power cut only lands when
## there are patients to be in the dark, and Vinnie only turns up if you owe him.

const EVENTS := {
	"vip_patient": {
		"title": "VIP Admission", "weight": 1.0,
		"body": "Someone important is coming in. Platinum cover. Administration would like this to go well.",
	},
	"inspection_warning": {
		"title": "Inspection Notice", "weight": 0.7,
		"body": "A health inspection is scheduled. You have today to make the ward look like a hospital.",
	},
	"nurse_sick": {
		"title": "Nurse Called In Sick", "weight": 1.1,
		"body": "You are a nurse down. Fewer eyes on the ward. Also fewer hands, but mostly fewer eyes.",
	},
	"power_flicker": {
		"title": "Power Fault", "weight": 0.9,
		"body": "The lights on the ward are unreliable today. Facilities have been informed. Facilities are aware.",
	},
	"patient_escape": {
		"title": "Patient At Large", "weight": 0.8,
		"body": "Someone has wandered off. They are somewhere on this floor. Probably.",
	},
	"family_dispute": {
		"title": "Families Arguing", "weight": 0.7,
		"body": "Two families are having a disagreement in the corridor. It has been going since six. It will be going at five. Nobody is watching anything else.",
	},
	"news_reporter": {
		"title": "Local Press", "weight": 0.45,
		"body": "A reporter is in the lobby doing a piece on hospital waiting times. Anything anybody complains about today, they will hear about, and so will everyone else.",
	},
	"insurance_audit": {
		"title": "Spot Audit", "weight": 0.6,
		"body": "Meridian Mutual is sampling charts today.",
	},
	"system_crash": {
		"title": "EHR Outage", "weight": 0.6,
		"body": "The records system is down. Nothing you file today will be timestamped properly.",
	},
	"supply_shortage": {
		"title": "Supply Shortage", "weight": 0.8,
		"body": "Pharmacy is short. Substitutions are, regrettably, expected today.",
	},
	"cold_snap": {
		"title": "Cold Snap", "weight": 0.7,
		"body": "It is bitter outside. Wards will run cold. That is the weather's fault.",
	},
	"recognised": {
		"title": "Recognised", "weight": 0.4,
		"body": "Someone recognised you outside work last night. They had questions. You had a sandwich.",
	},
	"vinnie": {
		"title": "Vinnie Called", "weight": 0.0,
		"body": "Vinnie would like his money. Vinnie was very polite about it, which was worse. He mentioned he has been keeping track.",
	},
	"mass_casualty": {
		"title": "Multiple Admissions", "weight": 0.35,
		"body": "A coach did something unwise. Every bed you have will be full by lunch.",
	},
	"student_shadowing": {
		"title": "Student On Placement", "weight": 0.8,
		"body": "A medical student has been assigned to shadow you. All day. At close range.",
	},
	"coffee_broken": {
		"title": "Coffee Machine Down", "weight": 0.6,
		"body": "The nurses' station coffee machine has failed. The nurses will be walking about.",
	},
	"agency_nurse": {
		"title": "Agency Cover", "weight": 0.7,
		"body": "An agency nurse is covering today. Doesn't know anyone, doesn't owe anyone.",
	},
	"bed_closed": {
		"title": "Bed Out Of Service", "weight": 0.5,
		"body": "One room is closed for deep cleaning. Fewer beds, same targets.",
	},
	"good_review": {
		"title": "Glowing Review", "weight": 0.5,
		"body": "A discharged patient left a five-star review. Administration has printed it out.",
	},
}

var fired_today: Array[String] = []
var active_flags: Dictionary = {}     ## event id -> true, cleared at end of day

var patient_system: PatientSystem = null

## Everybody an event put on the floor today. Untyped for the same reason as
## _row: these are nodes with lifetimes of their own.
##
## Nothing used to clear these. A student is assigned to shadow you "all day",
## an agency nurse is "covering today", the row is two people having it out in
## the corridor — and every one of them was still there on day thirty, because
## the only cleanup anywhere was clear_day() resetting six booleans. A career
## accumulated a permanent crowd of the most observant witnesses in the game,
## and the events that read as a one-day inconvenience were quietly permanent.
var _day_npcs: Array = []

## The corridor row, if one is running today. Untyped on purpose — see the
## guarded accessor below and CLAUDE.md #11.
var _row: Array = []
var _row_spot: Vector3 = Vector3.ZERO
var _row_next: int = -1

## How long the families take to get their breath back between rounds. Twenty
## in-game minutes is about forty-five real seconds, which is long enough that
## staff make it back to station and short enough that they never settle.
const ROW_PERIOD := 20

func _ready() -> void:
	add_to_group("random_events")
	patient_system = get_tree().get_first_node_in_group("patient_system")
	EventBus.clock_tick.connect(_on_clock_tick)

## Roll for the day. Returns the events that fired so the morning screen can
## show them.
func roll_daily() -> Array[Dictionary]:
	fired_today.clear()
	active_flags.clear()
	_row.clear()
	_row_spot = Vector3.ZERO
	_row_next = -1
	var out: Array[Dictionary] = []
	# Day one is authored. A player who has never seen the building should meet
	# it as it normally is — five beds, a handover, a list — and not spend their
	# only first impression on a mass casualty, a broken boiler and a visit from
	# Vinnie. Everything here is much funnier once you know what normal is.
	if GameState.day <= 1:
		return out
	var count := 1
	if RNG.chance("event_extra", 0.35):
		count = 2
	for i in count:
		var id := _pick()
		if id == "" or fired_today.has(id):
			continue
		fired_today.append(id)
		active_flags[id] = true
		var spec: Dictionary = EVENTS[id]
		apply(id)
		out.append({"id": id, "title": spec["title"], "body": spec["body"]})
		EventBus.random_event_fired.emit(id, String(spec["title"]), String(spec["body"]))
	return out

func _pick() -> String:
	var weights := {}
	for id in EVENTS:
		var w := float(EVENTS[id]["weight"])
		match id:
			"vinnie":
				# Only if you have actually stiffed him.
				for d in GameState.debts:
					if String(d.get("id", "")) == "vinnie" and int(d.get("missed", 0)) > 0:
						w = 2.0 * float(d["missed"])
			"vip_patient":
				w *= 0.4 + GameState.rep("hospital") * 2.0
			"insurance_audit":
				w *= 0.5 + GameState.heat * 2.5
			"news_reporter":
				w *= 0.5 + GameState.rep("hospital")
			"good_review":
				w *= GameState.rep("patient_sat") * 1.6
			"recognised":
				w *= GameState.heat * 2.0
			"mass_casualty":
				w *= 1.0 if patient_system and patient_system.free_wards().size() >= 3 else 0.1
			"patient_escape":
				w *= 1.0 if patient_system and patient_system.active_count() > 1 else 0.0
			"coffee_broken":
				w *= 1.6 if GameState.has_upgrade("coffee_machine") else 0.4
			"student_shadowing":
				w *= 0.5 + GameState.rep("hospital") * 1.5
			"bed_closed":
				w *= 1.0 if patient_system and patient_system.free_wards().size() >= 2 else 0.0
		if w > 0.0:
			weights[id] = w
	if weights.is_empty():
		return ""
	return String(RNG.pick_weighted("random_event", weights))

# ------------------------------------------------------------------ effects
## Group lookup that survives being called on a system that is not in the tree.
## Every spawn helper below already null-checks its hospital, but `apply` read
## the tree on its very first line, so a RandomEventSystem instantiated on its
## own — which is exactly how a unit test wants to poke at one arm of it —
## aborted before reaching any of that.
func _in_group(group: String):
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(group)

func apply(id: String) -> void:
	var hospital = _in_group("hospital")
	match id:
		"vip_patient":
			if patient_system:
				var p := patient_system.generate("ossified_vibes")
				p.insurance = "platinum"
				p.archetype = "confrontational"
				p.display_name = "%s %s" % [
					RNG.pick("vip_name", ["Sir", "Dame", "Councillor", "Bishop", "Alderman"]),
					RNG.pick("vip_name", DB.LAST_NAMES)]
				p.base_daily_revenue = int(float(p.base_daily_revenue) * 1.6)
				p.mind = DB.make_mind(p.id, p.display_name, "patient", p.archetype)
				patient_system.admit(p)
		"inspection_warning":
			GameState.set_flag("inspection_tomorrow", true)
		"nurse_sick":
			var staff: Array = get_tree().get_nodes_in_group("staff") if is_inside_tree() else []
			for s in staff:
				if s is NurseNPC:
					var sus = _in_group("suspicion_system")
					if sus:
						sus.unregister(s.npc_id)
					s.queue_free()
					break
		"power_flicker":
			if hospital:
				for r in hospital.wards():
					if RNG.chance("flicker", 0.5):
						r.set_lights(false, false)
				# Every door on the floor swings. Purely atmospheric, and the
				# reason the hospital keeps a list of them.
				for d in hospital.doors:
					if is_instance_valid(d) and d.leaf:
						d.leaf.apply_torque_impulse(Vector3(0,
							RNG.randf_range_s("flicker_swing", -1.4, 1.4), 0))
			# The crucial part: a genuine facilities fault is a free alibi for
			# anything cold or dark that happens today.
			GameState.add_cover("facilities", GameState.MINUTES_PER_DAY)
		"patient_escape":
			if patient_system and hospital:
				var list := patient_system.active()
				if not list.is_empty():
					var p: Patient = RNG.pick("escape_pick", list)
					var body = patient_system.get_body(p.id)
					if body:
						body.state = PatientNPC.State.WANDERING
						body.goto(hospital.point_in("lobby", "escape_pt"))
		"family_dispute":
			GameState.set_flag("families_arguing", true)
			_spawn_argument()
		"news_reporter":
			GameState.set_flag("press_present", true)
			_spawn_reporter()
		"insurance_audit":
			var inv = _in_group("investigation_system")
			if inv:
				inv.open("insurance", 0)
		"system_crash":
			# Nothing filed today is timestamped, which cuts both ways: your
			# late paperwork stops looking late, and so does everyone else's.
			GameState.set_flag("ehr_down", true)
			GameState.add_cover("administrative", GameState.MINUTES_PER_DAY)
		"supply_shortage":
			GameState.set_flag("supply_shortage", true)
			GameState.add_cover("equipment_variance", GameState.MINUTES_PER_DAY)
		"cold_snap":
			if hospital:
				for r in hospital.room_list():
					r.temperature -= 4.0
			GameState.add_cover("weather", GameState.MINUTES_PER_DAY)
		"recognised":
			GameState.add_heat(0.03, "recognised outside work")
		"vinnie":
			# Vinnie's arithmetic is simple and it compounds. The first visit is
			# a nuisance; the fourth is most of a day's honest work, which is
			# the point at which paying the man on time becomes a strategy
			# rather than an option.
			var visits := int(GameState.flag("vinnie_visits", 0)) + 1
			GameState.set_flag("vinnie_visits", visits)
			GameState.set_flag("vinnie_visited", true)
			GameState.add_personal(-300 * visits, "Vinnie (visit %d)" % visits)
			if visits >= 3:
				# He has started turning up at work, and being seen with Vinnie
				# is its own kind of paperwork.
				GameState.add_heat(0.04, "Vinnie came to the hospital")
				EventBus.toast.emit(
					"Vinnie waited by the staff entrance. People saw.", "bad")
		"mass_casualty":
			if patient_system:
				var free := patient_system.free_wards().size()
				for i in mini(free, 3):
					patient_system.admit(patient_system.generate())
		"good_review":
			GameState.adjust_rep("hospital", 0.05)
			GameState.adjust_rep("patient_sat", 0.04)
		"student_shadowing":
			_spawn_student()
		"coffee_broken":
			GameState.set_flag("coffee_broken", true)
		"agency_nurse":
			_spawn_agency_nurse()
		"bed_closed":
			GameState.set_flag("bed_closed", true)

## A student is a witness with legs. High observance, low escalation, glued to
## you — the single most disruptive thing that can happen to a plan.
func _spawn_student() -> void:
	var hospital = _in_group("hospital")
	var sus = _in_group("suspicion_system")
	if hospital == null or sus == null:
		return
	var s := NurseNPC.new()
	s.npc_id = "student_%d" % GameState.day
	s.archetype = "rule_follower"
	s.display = "%s (student)" % RNG.pick("student_name", DB.STAFF_FIRST)
	s.set_colours(Color(0.87, 0.72, 0.60), Color(0.62, 0.66, 0.72), Color(0.2, 0.16, 0.12))
	s.shadow_player = true
	var parent: Node = hospital.get_parent()
	if parent == null:
		parent = get_tree().root
	parent.add_child(s)
	s.position = hospital.point_in("lobby", "student_spawn")
	var mind := DB.make_mind(s.npc_id, s.display, "nurse", "rule_follower")
	mind.observance = 0.95
	mind.escalation = 0.25
	mind.talkativeness = 0.85     # tells the staff room everything
	mind.trust = 0.7
	sus.register(mind, s)
	_day_npcs.append(s)

## Two visitors having it out in the corridor. A standing distraction you did
## not have to cause and cannot switch off — staff keep drifting over to it.
func _spawn_argument() -> void:
	var hospital = _in_group("hospital")
	var sus = _in_group("suspicion_system")
	if hospital == null or sus == null:
		return
	var spot: Vector3 = hospital.point_in("corridor", "argument_spot")
	_row_spot = spot
	_row_next = GameState.career_minutes + ROW_PERIOD
	_row.clear()
	for i in 2:
		var v := VisitorNPC.new()
		v.npc_id = "argument_%d_%d" % [GameState.day, i]
		v.archetype = "litigious_family" if i == 0 else "questioner"
		v.display = "Somebody's %s" % RNG.pick("arg_rel", ["brother", "sister", "cousin", "mother"])
		v.set_colours(Color(0.76, 0.60, 0.46), Color(0.4, 0.3, 0.35), Color(0.2, 0.15, 0.12))
		var parent: Node = hospital.get_parent()
		if parent == null:
			parent = get_tree().root
		parent.add_child(v)
		v.stand_and_argue(spot + Vector3(float(i) * 1.4 - 0.7, 0, 0),
			float(GameState.MINUTES_PER_DAY))
		var mind := DB.make_mind(v.npc_id, v.display, "family", v.archetype)
		mind.observance = 0.2      # far too busy with each other to notice you
		sus.register(mind, v)
		_row.append(v)
		_day_npcs.append(v)
	# Loud, continuous, and entirely innocent — the best kind of cover.
	WorldEvent.new("argument", "").at(spot, "corridor") \
		.heard(0.0, 26.0).tag("noise").tag("chaos") \
		.says("a row in the corridor").emit()

## Guarded accessor for the two arguing visitors. Reading a freed node into a
## TYPED local aborts the enclosing function outright (CLAUDE.md #11), which is
## exactly how the witnessing pass once switched itself off mid-shift, so `b`
## here is deliberately untyped and every dead entry is dropped on the way past.
func _row_bodies() -> Array:
	var out: Array = []
	var live: Array = []
	for entry in _row:
		var b = entry
		if not is_instance_valid(b):
			continue
		live.append(b)
		out.append(b)
	_row = live
	return out

## A family row is not an event, it is a condition of the day. Left as a single
## WorldEvent it moved staff exactly once, thirty seconds into the morning, and
## was then indistinguishable from no event at all. Recurring, it is a tool: a
## repeating pull off the station that you did not cause, cannot be blamed for,
## and can plan a whole shift around.
func _on_clock_tick(_minute: int) -> void:
	if _row_next < 0 or not GameState.flag("families_arguing", false):
		return
	if GameState.career_minutes < _row_next:
		return
	_row_next = GameState.career_minutes + ROW_PERIOD
	var bodies := _row_bodies()
	if bodies.is_empty():
		# Both parties have gone home. The day stops handing out free cover.
		_row_next = -1
		GameState.set_flag("families_arguing", false)
		return

	# They drift. A row that stays put becomes furniture — staff learn where it
	# is and route around it — so it wanders, and takes the ward's attention to
	# a different corner each time it flares up.
	var hospital = _in_group("hospital")
	if hospital and RNG.chance("row_move", 0.45):
		_row_spot = hospital.point_in("corridor", "row_move")
		var i := 0
		for b in bodies:
			if b.has_method("goto"):
				b.goto(_row_spot + Vector3(float(i) * 1.4 - 0.7, 0, 0))
			i += 1

	var speaker = bodies[0]
	if speaker.has_method("say"):
		speaker.say(String(RNG.pick("row_bark", [
			"That is NOT what the doctor said.",
			"You weren't even here on Tuesday.",
			"Mum would be appalled. Appalled.",
			"I have it in writing. Somewhere.",
			"Don't you walk away from me.",
		])), 3.0)
	WorldEvent.new("argument", "").at(_row_spot, "corridor") \
		.heard(0.0, 26.0).tag("noise").tag("chaos") \
		.says("the row in the corridor, again").emit()

## The press, in the flesh. A flag alone made a press day indistinguishable from
## any other day; a person standing in your lobby with a notebook makes the
## lobby somewhere you would rather not be seen, which is the entire point.
func _spawn_reporter() -> void:
	var hospital = _in_group("hospital")
	var sus = _in_group("suspicion_system")
	if hospital == null or sus == null:
		return
	var r := VisitorNPC.new()
	r.npc_id = "press_%d" % GameState.day
	r.archetype = "questioner"
	r.display = "%s, Ashcroft Gazette" % RNG.pick("press_name", DB.LAST_NAMES)
	r.set_colours(Color(0.82, 0.66, 0.52), Color(0.72, 0.24, 0.28), Color(0.16, 0.13, 0.11))
	var parent: Node = hospital.get_parent()
	if parent == null:
		parent = get_tree().root
	parent.add_child(r)
	r.stand_and_argue(hospital.point_in("lobby", "press_spot"),
		float(GameState.MINUTES_PER_DAY))
	var mind := DB.make_mind(r.npc_id, r.display, "family", "questioner")
	mind.observance = 0.9        # it is literally their job to notice
	mind.escalation = 0.9        # and to tell everyone
	mind.talkativeness = 1.0
	mind.trust = 0.15            # owes the hospital nothing
	sus.register(mind, r)
	_day_npcs.append(r)

## Agency cover: barely notices anything, but owes you nothing at all.
func _spawn_agency_nurse() -> void:
	var hospital = _in_group("hospital")
	var sus = _in_group("suspicion_system")
	if hospital == null or sus == null:
		return
	var n := NurseNPC.new()
	n.npc_id = "agency_%d" % GameState.day
	n.archetype = "incompetent"
	n.display = "Agency Nurse"
	n.set_colours(Color(0.76, 0.60, 0.46), Color(0.35, 0.52, 0.48), Color(0.18, 0.14, 0.1))
	var parent: Node = hospital.get_parent()
	if parent == null:
		parent = get_tree().root
	parent.add_child(n)
	n.position = hospital.point_in("station", "agency_spawn")
	var mind := DB.make_mind(n.npc_id, n.display, "nurse", "incompetent")
	mind.trust = 0.2              # no history with you, and no reason to cover
	mind.escalation = 0.7
	sus.register(mind, n)
	_day_npcs.append(n)

## The student's placement ends, the agency shift ends, the families are asked
## to leave. Their minds go with them: what a one-day witness saw stays only in
## whatever they told the staff room before they went, which is what gossip is
## for and is a far more interesting shape than an eternal observer.
func _send_the_day_staff_home() -> void:
	var sus = _in_group("suspicion_system")
	for entry in _day_npcs:
		var b = entry            # untyped: a typed local aborts here, CLAUDE.md #11
		if not is_instance_valid(b):
			continue
		if sus:
			sus.unregister(String(b.npc_id))
		b.queue_free()
	_day_npcs.clear()

func is_active(id: String) -> bool:
	return active_flags.has(id)

func clear_day() -> void:
	active_flags.clear()
	GameState.set_flag("ehr_down", false)
	GameState.set_flag("press_present", false)
	GameState.set_flag("families_arguing", false)
	GameState.set_flag("supply_shortage", false)
	GameState.set_flag("coffee_broken", false)
	GameState.set_flag("bed_closed", false)
	_send_the_day_staff_home()
	_row.clear()
	_row_spot = Vector3.ZERO
	_row_next = -1
	# press_story is deliberately NOT cleared here. The reporter goes home; the
	# piece runs. It is read once by the shift report and cleared there.

func to_dict() -> Dictionary:
	return {"fired": fired_today, "flags": active_flags, "row_next": _row_next,
		"row_spot": [_row_spot.x, _row_spot.y, _row_spot.z]}

func from_dict(d: Dictionary) -> void:
	fired_today.clear()
	for x in d.get("fired", []):
		fired_today.append(String(x))
	active_flags = d.get("flags", {})
	_row_next = int(d.get("row_next", -1))
	var sp: Array = d.get("row_spot", [])
	if sp.size() == 3:
		_row_spot = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
