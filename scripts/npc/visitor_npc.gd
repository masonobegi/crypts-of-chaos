class_name VisitorNPC
extends NPCBody
## Family. Visitors are the most dangerous witness class in the game: they have
## nothing to do but sit in the room and watch, they compare notes with the
## patient, and they escalate faster than staff because they are not worried
## about their job.

enum State { ARRIVING, VISITING, ROAMING, LEAVING }

var patient_id := ""
var relation := "partner"
var state: State = State.ARRIVING
var _timer := 0.0
var _bark_timer := 0.0
var _visit_minutes := 0

func _ready() -> void:
	role = "family"
	outfit = Color(0.45, 0.38, 0.42)
	super._ready()
	add_to_group("visitor")

func begin_visit(p_patient_id: String, ward_key: String, minutes: int) -> void:
	patient_id = p_patient_id
	_visit_minutes = minutes
	state = State.ARRIVING
	var h = get_tree().get_first_node_in_group("hospital")
	if h:
		goto(h.point_in(ward_key, "visitor_pt"))

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_timer -= delta
	_bark_timer = maxf(0.0, _bark_timer - delta)
	match state:
		State.ARRIVING:
			if not is_moving():
				state = State.VISITING
				_timer = float(_visit_minutes)
				say(String(RNG.pick("arrive_bark", [
					"Hello — how are they doing?", "I came as soon as I could.",
					"Right. Where are we with everything?",
				])), 3.5)
		State.VISITING:
			if _bark_timer <= 0.0:
				_bark_timer = RNG.randf_range_s("visitor_bark", 9.0, 20.0)
				_visit_bark()
			if _timer <= 0.0:
				_leave()
		State.LEAVING:
			if not is_moving():
				queue_free()

func _visit_bark() -> void:
	var ps = get_tree().get_first_node_in_group("patient_system")
	var p = ps.get_patient(patient_id) if ps else null
	if p != null and p.is_overdue() and RNG.chance("visitor_overdue", 0.65):
		say(String(RNG.pick("visitor_overdue_bark", [
			"They were supposed to be home by now.",
			"That's not what you told me on Tuesday.",
			"Why is this taking so long?",
			"I'd like to see the notes, actually.",
		])), 4.0)
		# A family member noticing the overrun is INFERRED evidence — nobody saw
		# anything, but the dates don't match what they were told.
		if mind:
			var ev := Evidence.new()
			ev.kind = "overdue_noticed_by_family"
			ev.about_actor = "player"
			ev.patient_id = patient_id
			ev.source = Evidence.Source.INFERRED
			ev.time = GameState.career_minutes
			ev.base_weight = clampf(p.overdue_days * 0.16, 0.05, 0.6)
			ev.certainty = 0.7
			ev.cover_tag = "clinical_caution"
			ev.summary = "noticed the stay running %d days long" % int(p.overdue_days)
			mind.add_evidence(ev)
		return
	say(Dialogue.family_idle(archetype), 3.5)

func _leave() -> void:
	state = State.LEAVING
	var h = get_tree().get_first_node_in_group("hospital")
	if h:
		goto(h.point_in("lobby", "visitor_leave_pt"))

func prompt(_player) -> Array:
	var sub := DB.archetype_name(archetype)
	if mind:
		var tier := mind.tier(GameState.career_minutes, GameState.active_covers)
		if tier >= 2:
			sub += "  ·  wants answers"
	return ["Talk to %s" % display, sub]

func interact(player, _held) -> void:
	look_toward(player.global_position if player else global_position)
	EventBus.request_ui.emit("dialogue", {"npc_id": npc_id})
