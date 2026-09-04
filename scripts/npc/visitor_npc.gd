class_name VisitorNPC
extends NPCBody
## Family. Visitors are the most dangerous witness class in the game: they have
## nothing to do but sit in the room and watch, and they escalate faster than
## staff because they are not worried about their job.

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

## Park a visitor somewhere and let them stay there for a while with nobody to
## visit. Used by the corridor row.
##
## Setting `state = VISITING` from outside is NOT enough and never was: `_timer`
## is only loaded on the ARRIVING -> VISITING transition, so a visitor dropped
## straight into VISITING hit `if _timer <= 0.0: _leave()` on its very first
## physics frame and walked out of the building. Both halves of every family
## dispute did exactly that, which is why the event that promises "nobody is
## watching anything else" had never once distracted anybody.
func stand_and_argue(spot: Vector3, minutes: float) -> void:
	patient_id = ""
	state = State.VISITING
	_timer = minutes
	_visit_minutes = int(minutes)
	position = spot
	look_toward(spot + Vector3(0, 0, 1))

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

## What a visitor says while they sit there.
##
## Spotting an unnoticed complication on the patient used to be the first thing
## this did, and was the whole reason the constantly-visiting archetype was the
## most dangerous witness class in the game. Complications have gone, and so has
## Dialogue, which supplied the idle chat underneath. What a family member is
## left to notice is the one thing they can count on their own fingers: the stay
## running long.
func _visit_bark() -> void:
	var ps = get_tree().get_first_node_in_group("patient_system")
	var p = ps.get_patient(patient_id) if ps else null
	if p == null or not p.is_overdue() or not RNG.chance("visitor_overdue", 0.65):
		return
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

func _leave() -> void:
	state = State.LEAVING
	var h = get_tree().get_first_node_in_group("hospital")
	if h:
		# "lobby" is not a room in this building any more.
		goto(h.point_in("corridor", "visitor_leave_pt"))

# A visitor was somebody you could talk to: prompt() offered it and interact()
# opened the dialogue screen. That screen went with Dialogue, and there is
# nothing behind the keypress any more — so the prompt goes too, rather than
# hanging on a door that no longer opens. They sit there and they watch, which
# was always the dangerous half.
