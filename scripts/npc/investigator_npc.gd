class_name InvestigatorNPC
extends NPCBody
## Someone who has come to look at your ward.
##
## Investigations used to resolve in the abstract. Putting a body on the floor
## turns them into something you can watch, follow, interfere with and panic
## about — which is the whole point. They physically walk to a chart to read it,
## physically corner a nurse to interview her, and physically open a machine to
## check its log, so every one of those is a thing you can get to first.

enum State { ARRIVING, TO_TARGET, WORKING, LEAVING }

const WORK_SECONDS := 4.0

var investigation = null            ## Investigation this body belongs to
var state: State = State.ARRIVING
var tasks: Array[Dictionary] = []   ## {kind, target}
var _task_index := 0
var _timer := 0.0
var _work_timer := 0.0
var _announced := false

func _ready() -> void:
	role = "inspector"
	outfit = Color(0.20, 0.22, 0.30)      # a suit, on a ward. unmistakable.
	super._ready()
	add_to_group("investigator")

func begin(inv, kind: String) -> void:
	investigation = inv
	display = _title_for(kind)
	if _nametag:
		_nametag.text = display
	_plan_tasks()
	var h = get_tree().get_first_node_in_group("hospital")
	if h:
		goto(h.point_in("station", "inv_arrive"))

func _title_for(kind: String) -> String:
	match kind:
		"admin_audit": return "Ms Pell, Administration"
		"insurance": return "Meridian Mutual Assessor"
		"inspector": return "Health Inspector"
		"attorney": return "Solicitor (someone's)"
		"police": return "Detective"
	return "Visitor"

## Build the round they are going to walk. Charts first, then people, then kit —
## which gives you a readable order to get in front of.
func _plan_tasks() -> void:
	tasks.clear()
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps:
		var focus: String = String(investigation.focus_patient) if investigation else ""
		for p in ps.active():
			if focus != "" and p.id != focus and not RNG.chance("inv_task", 0.4):
				continue
			tasks.append({"kind": "chart", "patient": p.id, "room": p.room})
	for s in get_tree().get_nodes_in_group("staff"):
		if RNG.chance("inv_interview", 0.7):
			tasks.append({"kind": "interview", "npc": s.npc_id})
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is TreatmentMachine and RNG.chance("inv_machine", 0.5):
			tasks.append({"kind": "machine", "room": f.room_key})

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_timer -= delta
	match state:
		State.ARRIVING:
			if not is_moving():
				if not _announced:
					_announced = true
					say(String(RNG.pick("inv_arrive_bark", [
						"I'll need about an hour of your time.",
						"Don't let me interrupt. Carry on.",
						"I'm just here to look at some paperwork.",
						"Is the doctor on the floor?",
					])), 4.5)
				state = State.TO_TARGET
				_next_task()
		State.TO_TARGET:
			if not is_moving():
				state = State.WORKING
				_work_timer = WORK_SECONDS
		State.WORKING:
			_work_timer -= delta
			if _work_timer <= 0.0:
				_do_task()
				_task_index += 1
				_next_task()
		State.LEAVING:
			if not is_moving():
				queue_free()

func _next_task() -> void:
	if _task_index >= tasks.size():
		_leave()
		return
	var t: Dictionary = tasks[_task_index]
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		_leave()
		return
	match String(t["kind"]):
		"chart", "machine":
			goto(h.point_in(String(t.get("room", "corridor")), "inv_goto"))
		"interview":
			var body := _staff_body(String(t.get("npc", "")))
			if body == null or not is_instance_valid(body):
				_task_index += 1
				_next_task()
				return
			goto(body.global_position)
	state = State.TO_TARGET

func _staff_body(npc_id: String) -> NPCBody:
	for s in get_tree().get_nodes_in_group("staff"):
		if s.npc_id == npc_id:
			return s
	return null

# ------------------------------------------------------------------ tasks
func _do_task() -> void:
	if investigation == null or _task_index >= tasks.size():
		return
	var t: Dictionary = tasks[_task_index]
	match String(t["kind"]):
		"chart": _read_chart(String(t["patient"]))
		"interview": _interview(String(t["npc"]))
		"machine": _inspect_machine(String(t.get("room", "")))

## Reads the chart in front of them. If you have taken it, that is worse than
## anything it could have said.
func _read_chart(patient_id: String) -> void:
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps == null:
		return
	var p = ps.get_patient(patient_id)
	if p == null:
		return
	var chart_prop = ps.charts.get(patient_id, null)
	if chart_prop == null or not is_instance_valid(chart_prop):
		_add("chart_missing", 0.8, "the physical chart for %s is not on the ward" % p.display_name,
			patient_id)
		say("Where is this patient's chart?", 4.0)
		return
	# Charts live on the ward they belong to. One that has wandered is either
	# carelessness or an attempt to keep it away from somebody — and an inspector
	# cannot tell which, which is rather the point.
	var chart_room := ""
	var h = get_tree().get_first_node_in_group("hospital")
	if h and h.has_method("room_at"):
		chart_room = h.room_at(chart_prop.global_position)
	if chart_room != p.room:
		_add("chart_misfiled", 0.4,
			"%s's chart was found in %s rather than on their ward" % [
				p.display_name,
				h.room(chart_room).display if (h and h.room(chart_room)) else "another room"],
			patient_id)
		say("Why is this chart in here?", 3.5)

	var findings: Array = p.chart.audit(p.actual_treatments, p.complications)
	if findings.is_empty():
		say(String(RNG.pick("inv_clean", ["Fine.", "That's in order.", "Mm."])), 2.5)
		return
	for f in findings:
		_add(String(f["kind"]), float(f["weight"]), String(f["text"]), patient_id)
	say(String(RNG.pick("inv_finding", [
		"That's odd.", "Hm. This doesn't follow.", "Who signed this off?",
		"I'll be taking a copy of this.",
	])), 3.5)

## Corners a member of staff. Loyalty is a real defence.
func _interview(npc_id: String) -> void:
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus == null:
		return
	var m: Mind = sus.mind_of(npc_id)
	if m == null:
		return
	if investigation.interviewed.has(npc_id):
		return
	investigation.interviewed.append(npc_id)
	var body := _staff_body(npc_id)
	var worst := m.strongest(GameState.career_minutes)
	if worst == null:
		if body:
			body.say(String(RNG.pick("inv_nothing", [
				"Nothing to report.", "It's been quiet.", "Normal week.",
			])), 3.0)
		return
	var will_talk := clampf(0.85 - m.trust * 0.7 + m.escalation * 0.3, 0.05, 0.95)
	will_talk *= 1.0 - GameState.rep("staff_trust") * 0.35
	will_talk *= 1.0 - Upgrades.staff_silence_bonus()
	if not RNG.chance("inv_talk", will_talk):
		if body:
			body.say(String(RNG.pick("inv_cover", [
				"I didn't see anything.", "You'd have to ask the doctor.",
				"I wasn't on that shift.",
			])), 3.2)
		return
	var copy := worst.retold()
	copy.source = Evidence.Source.WITNESSED
	copy.certainty = worst.certainty * 0.9
	copy.summary = "%s: %s" % [m.display_name, worst.label()]
	investigation.gathered.append(copy)
	if body:
		body.say(String(RNG.pick("inv_told", [
			"Well... there was one thing.", "I did wonder about it, actually.",
			"I wrote it down, if that helps.",
		])), 3.5)
	say("Go on.", 2.5)

## Opens the machine. Reads the log. Notices the calibration screw. Then reads
## the thermostat, because a ward that keeps being set to twelve degrees is a
## record too.
func _inspect_machine(room_key: String) -> void:
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is Thermostat and f.room_key == room_key:
			for entry in f.suspicious_log_entries():
				_add("thermostat_log", 0.3, "%s set to %d on day %d" % [
					f.fixture_name, int(entry["setting"]), int(entry["day"])])
			if not f.suspicious_log_entries().is_empty():
				say("Who has been playing with the heating?", 3.5)
	for f in get_tree().get_nodes_in_group("fixture"):
		if not (f is TreatmentMachine) or f.room_key != room_key:
			continue
		var m: TreatmentMachine = f
		for entry in m.suspicious_log_entries():
			_add("machine_log_deviation", clampf(absf(float(entry["deviation"])) * 0.12, 0.1, 0.7),
				"%s run at %d for %s (prescribed %d)" % [m.fixture_name, int(entry["dial"]),
					entry.get("patient_name", "a patient"), int(entry["prescribed"])],
				String(entry.get("patient", "")))
		if m.log_cleared_count > 0:
			_add("machine_log_cleared", 0.5 * float(m.log_cleared_count),
				"%s log has been cleared %d time(s)" % [m.fixture_name, m.log_cleared_count])
			say("This device's log has been wiped.", 4.0)
		if m.is_miscalibrated():
			# The one sabotage that a technician can undo — and report.
			_add("machine_miscalibrated", 0.45,
				"%s is out of calibration" % m.fixture_name)
			say("This is nowhere near calibration.", 4.0)
			m.calibration = 1.0
		return

func _add(kind: String, weight: float, summary: String, patient_id := "") -> void:
	if investigation == null:
		return
	var ev := Evidence.new()
	ev.kind = kind
	ev.about_actor = "player"
	ev.patient_id = patient_id
	ev.source = Evidence.Source.RECORD
	ev.time = GameState.career_minutes
	ev.base_weight = weight
	ev.certainty = 0.95
	ev.summary = summary
	investigation.gathered.append(ev)

func _leave() -> void:
	state = State.LEAVING
	say(String(RNG.pick("inv_leave", [
		"That's everything for now.", "You'll hear from us.",
		"Thank you for your time, doctor.", "I'll be in touch.",
	])), 4.0)
	var h = get_tree().get_first_node_in_group("hospital")
	if h:
		goto(h.point_in("lobby", "inv_leave_pt"))

func prompt(_player) -> Array:
	return ["Talk to %s" % display, "they are here about your ward"]

func interact(player, _held) -> void:
	look_toward(player.global_position if player else global_position)
	EventBus.request_ui.emit("dialogue", {"npc_id": npc_id})
