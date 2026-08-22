class_name PatientNPC
extends NPCBody
## The body of an admitted patient. Holds a reference to the Patient data model
## (the truth layer) and expresses its state physically — sitting in the chair in
## their room, sleeping through a night shift, wandering into the corridor when
## nobody is looking.
##
## Four other expressions used to live here and have gone with the systems that
## drove them: the complication halo over the head, the pink surgical site mark
## on the limb about to be operated on, the shudder while a treatment machine ran,
## and being knocked out cold in a fight. There are no complications, no
## machines, no procedures and no fights any more.

enum State { IN_BED, SITTING, WANDERING, TALKING, LEAVING }

var data: Patient = null
var bed: PatientBed = null
var state: State = State.IN_BED
var _timer := 0.0
var _bark_timer := 0.0
var _reclined := false
## Whatever they were doing before you spoke to them, so that a word with
## somebody in the corridor puts them back in the corridor and not, with a pop,
## into a chair two rooms away.
var _pre_talk: State = State.IN_BED

func _ready() -> void:
	EventBus.shift_started.connect(_on_shift_started)
	role = "patient"
	outfit = Color(0.72, 0.78, 0.82)     # gown
	super._ready()
	add_to_group("patient_npc")
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
		# The chair does not collide with the person in it. Its collider is the
		# seat and legs, and a seated capsule reaches down into that — so
		# without this the ward's own furniture spends every frame trying to
		# push the patient out of their own room.
		add_collision_exception_with(p_bed)

func _physics_process(delta: float) -> void:
	_hold_bed_pose(delta)
	super._physics_process(delta)
	_timer -= delta
	_bark_timer = maxf(0.0, _bark_timer - delta)
	_tick_state(delta)

## An admitted patient sits in the chair in their room.
##
## They used to lie in a bed, and lying down turned every person on the ward
## into scenery you did things to. Upright in a chair, facing the door, they are
## somebody you walked in on — which is what every other system in this game is
## built to make interesting.
func _hold_bed_pose(_delta: float) -> void:
	# SITTING is the waiting-room pose; IN_BED is now the same pose in the
	# chair in their own room. Both want the same thing from the rig.
	# TALKING KEEPS THE CHAIR. It did not, and it had to not: _animate returned
	# before the head-look pass for anybody seated, so a patient in a chair could
	# not turn their head towards you at all, and the only way to make somebody
	# face you was to take them out of the seat entirely. So pressing E on a
	# patient stood them up — in a game whose wards are chairs, and whose note
	# was "I want them sitting in a chair". The head-look runs in every branch
	# now, so they stay put and turn to look at you, which is what a person in a
	# chair does when a doctor walks in.
	var in_chair := (state == State.IN_BED or state == State.TALKING) \
		and bed != null and is_instance_valid(bed)
	var wants_seat := state == State.SITTING or in_chair
	if wants_seat != is_seated():
		set_in_bed(wants_seat)
	if _reclined:
		_reclined = false
		set_reclined(false)
	pinned = in_chair
	if not in_chair:
		return
	global_position = bed.mount_point()
	# Facing the FOOT of the bed, which is the door. A patient lying with their
	# back to the way you come in cannot look at you, and being looked at when
	# you walk in is most of what this game is about.
	rotation.y = bed.rotation.y + PI
	velocity = Vector3.ZERO

## A patient in their chair does not budge for a doctor squeezing past — the
## pose is re-asserted every frame anyway, so a sidestep would only make them
## twitch and snap back.
func can_step_aside() -> bool:
	return state == State.WANDERING

## Asleep.
##
## The three shifts differed by five numbers and were otherwise the same eight
## hours. This is the one that changes what the player DOES: at night most of
## the ward is asleep, and a sleeping patient sees nothing — so the five people
## who would normally be lying there watching you work are, on nights, five
## people who are not.
##
## It is not free. They wake to a bang, so the distraction you used to move the
## nurse also wakes the man in the next bed, and a shift you chose because
## nobody was watching becomes one where everybody is, because you made a noise.
const SLEEP_CHANCE := {"night": 0.85, "evening": 0.30, "day": 0.06}

var asleep := false

func _on_shift_started(_day: int) -> void:
	if data == null or data.discharged:
		return
	if state != State.IN_BED:
		return
	set_asleep(RNG.chance("patient_sleep", float(
		SLEEP_CHANCE.get(GameState.shift_kind, 0.06))))

func set_asleep(v: bool) -> void:
	if asleep == v:
		return
	asleep = v
	# Held, so the blink timer cannot open a sleeping patient's eyes again a
	# few seconds later — which it otherwise would, every few seconds, all night.
	_lids_held = v
	set_eyes_open(not v)
	if perception != null:
		# The FLAG is what makes this real. Attention is derived — perception
		# recomputes it from its own distraction every frame — so writing the
		# number here and nothing else lasted less than one frame, and a ward
		# put to sleep for the night was back to full observance immediately
		# and silently. The number is still written so that a same-frame read
		# of attention agrees with the flag rather than lagging it by a tick.
		perception.suppressed = v
		perception.attention = 0.0 if v else 1.0

func wake_up(why := "") -> void:
	if not asleep:
		return
	set_asleep(false)
	if why != "" and _bark_timer <= 0.0:
		_bark_timer = 5.0
		say(String(RNG.pick("wake_bark", [
			"...what? What is it?", "Is it morning?", "Hello? Who's there?",
			"I was asleep.", "...that woke me up.",
		])), 2.8)

func _tick_state(_delta: float) -> void:
	if data == null:
		return
	# Walking out is the one thing a discharged patient is still doing, so it is
	# handled ABOVE the discharged guard and not inside the match below it.
	# PatientSystem.discharge() sets p.discharged and only THEN calls
	# discharge_and_leave(), so with the guard first the LEAVING branch was
	# unreachable: every patient ever sent home walked to the lobby, stopped, and
	# stood there for the rest of the career. Nobody sees a leak like that,
	# because it does not look like one — it looks like a busy lobby. But the
	# node never left the tree, so the tree_exiting hook in PatientSystem never
	# fired, their entry in bodies was never erased, and each of them went on
	# running a live NPCPerception that witnessed the player and fed evidence to
	# a Mind. Suspicion kept climbing from people discharged a fortnight ago.
	if state == State.LEAVING:
		if not is_moving():
			queue_free()
		return
	if data.discharged:
		return
	match state:
		State.IN_BED:
			if _timer <= 0.0:
				_timer = RNG.randf_range_s("patient_idle_t", 10.0, 24.0)
				_maybe_bark()
				_maybe_wander()
		State.SITTING:
			# Walk-ins waiting to be seen. They bark and they do NOT wander:
			# somebody who gets up and walks off has left the queue, and the
			# player then cannot find the person they were told to see. Before
			# this, SITTING had no case at all and fell through to `_: pass` — so
			# the entire waiting room sat in total silence, which read as a room
			# full of props rather than a room full of people with somewhere to
			# be.
			if _timer <= 0.0:
				_timer = RNG.randf_range_s("patient_idle_t", 10.0, 24.0)
				_maybe_bark()
		State.WANDERING:
			if not is_moving():
				_timer -= 1.0
				if _timer <= 0.0:
					_return_to_bed()
		State.TALKING:
			# TALKING was a one-way door. Nothing anywhere put a patient back
			# into State.IN_BED except _return_to_bed(), which is only reachable
			# from WANDERING — so pressing E on somebody once took them out of
			# their chair permanently: _hold_bed_pose stopped wanting a seat and
			# unpinned them, _maybe_bark() is only called from the IN_BED branch
			# so they went silent, and _on_shift_started's IN_BED gate meant they
			# could never be put to sleep again. Since talking to patients IS the
			# loop, the whole ward was standing up and mute by the middle of day
			# one.
			#
			# The state exists so that look_toward() survives and so the barks
			# and the wander stop while somebody is talking to them. A few
			# seconds of facing you is all it needs.
			if _timer <= 0.0:
				state = _pre_talk if _pre_talk != State.TALKING else State.IN_BED
				_timer = RNG.randf_range_s("patient_idle_t", 10.0, 24.0)
		_:
			pass

## What a patient says to the room.
##
## There were three more lines under this one and they came out of Dialogue: the
## idle mutter, the "I'm fit to go home" line, and the complaint about the stay
## running long. Dialogue went with the redesign, and nothing here invents
## replacements — what the ward has to say now is on the chart.
func _maybe_bark() -> void:
	if _bark_timer > 0.0 or data == null or asleep:
		return
	_bark_timer = 6.0
	var r = _room_node()
	var gripes: Array = r.complaints() if r else []
	if gripes.is_empty() or not RNG.chance("patient_env_bark", 0.6):
		return
	say("Sorry — %s." % String(RNG.pick("gripe_p", gripes)), 3.2)
	# Complaining is not evidence, but it IS a satisfaction hit, and
	# satisfaction failure is its own way to lose.
	data.satisfaction = clampf(data.satisfaction - 0.03, 0.0, 1.0)

## Patients wander. A confused one wanders more; an escaped patient in the
## corridor is a first-class distraction that you did not have to cause.
func _maybe_wander() -> void:
	if data == null or asleep:
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
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return
	# A psychiatric admission with a day room to sit in will use it, and will
	# stay a good while. That matters more than it looks: recovery is scored
	# against the comfort of the room they are ACTUALLY in, so a cold, dark day
	# room slows down every psych patient on the floor at once, from a
	# thermostat nobody associates with any of them.
	var day_room := false  # there is no day room; the ward is the ward
	if day_room:
		urge = maxf(urge, 0.45)
	if not RNG.chance("patient_wander", urge):
		return
	state = State.WANDERING
	_timer = 40.0 if day_room else 12.0
	goto(h.point_in("day_room", "day_room_pt") if day_room
		else h.point_in("corridor", "patient_wander_pt"))
	say(String(RNG.pick("wander_bark", [
		"I'm just going to stretch my legs.", "Where's the tea?",
		"I need to speak to someone.", "Is this the way out?",
	]) if not day_room else RNG.pick("day_room_bark", [
		"I'll be in the day room.", "There's a jigsaw. I'm told it's missing a piece.",
		"The telly's on. It's always on.", "I prefer it in there. It's warmer.",
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

## Patients react to chaos, which is most of the reason chaos is worth causing.
## Perception calls this on anything within hearing range.
func on_heard_noise(evt: WorldEvent) -> void:
	if asleep:
		wake_up("noise")
		return
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
	# Somebody asleep when the discharge comes through opens their eyes and walks
	# out rather than being carried. Cheap to call on everyone: it is idempotent.
	set_asleep(false)
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
	# Somebody sitting in the waiting row is one keypress from a bed. The
	# playtest note was "there should be no friction getting a customer into a
	# bed unless all my beds are full", and it was right: admitting is the
	# commonest thing you do all day and it was four clicks down a menu.
	if not data.admitted and not data.discharged:
		var ps = get_tree().get_first_node_in_group("patient_system")
		var free: int = ps.free_wards().size() if ps != null else 0
		if free > 0:
			return ["Admit %s" % data.display_name,
				"%s  ·  %d of five rooms free  ·  [hold E] to look first" % [
					data.condition_name(), free]]
		return ["%s is waiting" % data.display_name,
			"%s  ·  every room is full  ·  [hold E] for options" % data.condition_name()]
	var sub := data.condition_name()
	# The three facts that decide what you do next, on the thing you are already
	# looking at. What a bed earns per night was previously only readable by
	# opening the tablet and scrolling to the right row, which is a menu the
	# player has to already suspect matters before they will ever open it.
	if data.ready_for_discharge():
		sub += "  ·  fit to go home"
	elif data.recovery >= 0.6:
		sub += "  ·  nearly there"
	if data.is_overdue():
		sub += "  ·  %d days over" % int(data.days_admitted - data.expected_stay_days)
	sub += "  ·  %s a night" % UIKit.money_str(data.daily_revenue())
	return ["Talk to %s" % data.display_name, sub]

## Holding a tool used to turn this prompt into the treatment itself —
## prompt_with_item(), use_seconds() and _treatment_for_item() picked a
## procedure out of DB.TREATMENTS from whatever was in your hand, and what was
## actually in the syringe. Treatments, substances and the machines that ran them
## have all gone; a patient is somebody you look at and talk to.

## How long somebody stays turned towards you after you speak to them. Refreshed
## on every interaction, so it is "a few seconds after you last did anything"
## rather than a countdown that starts when the card opens — the patient card
## deliberately does not pause the world, so this ticks while you read it.
const TALK_SECONDS := 6.0

## Face whoever is talking to them, without getting out of the chair to do it.
##
## _hold_bed_pose rewrites rotation.y to the chair's yaw every frame, so the
## turn is entirely in the neck — which is a clamped 66 degrees, and is why a
## patient you address from behind their chair looks over their shoulder at you
## rather than spinning to face you.
##
## Guarded on `discharged`, because somebody on their way out of the building is
## in State.LEAVING and that state is the one that frees them — dropping them
## into TALKING as you pass would strand them in the lobby permanently.
func _turn_to_talk(player) -> void:
	look_toward(player.global_position if player else global_position)
	if data.discharged:
		return
	if state != State.TALKING:
		_pre_talk = state
	state = State.TALKING
	_timer = TALK_SECONDS

func interact(player, _held) -> void:
	if data == null:
		return
	# Walking up and speaking to somebody wakes them.
	wake_up("touched")
	_turn_to_talk(player)
	# A tap admits a waiting patient outright. Everybody already in a bed gets
	# the card, because there is nothing you would do to them in one keypress.
	if not data.admitted and not data.discharged:
		var ps = get_tree().get_first_node_in_group("patient_system")
		if ps != null and not ps.free_wards().is_empty():
			if ps.admit(data):
				AudioMgr.play_at_var("trolley", global_position, -11.0)
				return
	_open_card()

## The hold. Always the card, whoever they are — it is the way to see the
## options for somebody a tap would otherwise admit on the spot.
func interact_held(player, _held) -> void:
	if data == null:
		return
	wake_up("touched")
	_turn_to_talk(player)
	_open_card()

func _open_card() -> void:
	EventBus.request_ui.emit("patient", {"patient_id": data.id, "npc_id": data.id})
