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
	EventBus.shift_started.connect(_on_shift_started)
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
		# A bed does not collide with its own passenger.
		#
		# The patient is pinned to the bed's origin, which puts their capsule
		# INSIDE its 1.0 x 0.7 x 2.1 collision box, and the bed's mask includes
		# the NPC layer. Frozen, nothing happens. Release the brake and the
		# solver resolves that overlap against a 42 kg rigid body — which in the
		# first playtest sent the bed across the room and out of the building.
		#
		# An exception rather than dropping layer 8 from the bed's mask: a bed
		# shoved down a corridor should still shove people out of the way. It
		# just should not fight the person lying on it.
		p_bed.add_collision_exception_with(self)

func _physics_process(delta: float) -> void:
	_tick_cycle(delta)
	_hold_bed_pose(delta)
	super._physics_process(delta)
	_timer -= delta
	_bark_timer = maxf(0.0, _bark_timer - delta)
	_tick_state(delta)
	_tick_symptoms(delta)

## While in bed the patient is pinned to the bed's mount point — which means
## wheeling the bed wheels the patient, exactly as it should.
func _hold_bed_pose(_delta: float) -> void:
	# SITTING was a state with no pose. Patients waiting to be seen were sent to
	# a chair in the treatment bay and left STANDING in it — invisible in a wide
	# shot, impossible to unsee at three metres, and the waiting row is the
	# first thing a walk-in patient is ever seen doing.
	var wants_seat := state == State.SITTING
	if wants_seat != is_seated():
		set_seated(wants_seat)
	var in_bed := state == State.IN_BED and bed != null and is_instance_valid(bed)
	if in_bed != _reclined:
		_reclined = in_bed
		set_reclined(in_bed)
	pinned = in_bed
	if not in_bed:
		return
	global_position = bed.global_position
	rotation.y = bed.rotation.y
	velocity = Vector3.ZERO

## A patient lying in a bed does not budge for a doctor squeezing past — the bed
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
	if data == null or data.discharged or state != State.IN_BED:
		return
	set_asleep(RNG.chance("patient_sleep", float(
		SLEEP_CHANCE.get(GameState.shift_kind, 0.06))))

## Being in a machine cycle, from the patient's side.
##
## The treatment used to happen entirely on the doctor's side of the room: a
## button, a noise, a toast. The person it was being done TO did nothing at all,
## which made the whole act read as operating equipment rather than as treating
## somebody. They twitch for the length of the cycle now, harder the further the
## dial is from where it should be, and they say something about it — which is
## also the honest tell, because a patient noticing is how this gets reported.
var _cycle_t := 0.0
var _cycle_strength := 0.0

func undergo_cycle(seconds: float, deviation: int) -> void:
	_cycle_t = maxf(seconds, 0.3)
	# Capped low. Startle drives an arm flail, and re-applying it every frame
	# for two and a half seconds took a patient from "shuddering" to "windmilling
	# both arms over their head in bed" — which is funny once and looks broken
	# every time after that.
	_cycle_strength = clampf(0.14 + float(deviation) * 0.06, 0.14, 0.38)
	wake_up()
	startle(minf(0.35 + float(deviation) * 0.18, 1.0))
	if deviation >= 3:
		say(String(RNG.pick("cycle_bark_bad", [
			"That is — that is a LOT.",
			"Ow. Ow, that's — is it meant to do that?",
			"Turn it down. Turn it DOWN.",
			"I can feel that in my back teeth.",
		])), 3.0)
	elif deviation >= 1:
		say(String(RNG.pick("cycle_bark_off", [
			"Hm. That's warmer than last time.",
			"Is that the usual setting?",
			"Oh. That's new.",
		])), 2.6)
	elif RNG.chance("cycle_bark_ok", 0.4):
		say(String(RNG.pick("cycle_bark_ok_line", [
			"Oh, that's the good one.", "Mm. That's better.", "That's the one, yes.",
		])), 2.4)

func _tick_cycle(delta: float) -> void:
	if _cycle_t <= 0.0:
		return
	_cycle_t = maxf(0.0, _cycle_t - delta)
	# Re-applied every frame rather than set once: startle decays, and what this
	# wants is a sustained shudder for as long as the machine is running.
	startle(_cycle_strength * delta * 1.6)

func set_asleep(v: bool) -> void:
	if asleep == v:
		return
	asleep = v
	# Held, so the blink timer cannot open a sleeping patient's eyes again a
	# few seconds later — which it otherwise would, every few seconds, all night.
	_lids_held = v
	set_eyes_open(not v)
	if perception != null:
		# Attention is the multiplier on every notice roll, so zero means a
		# sleeping patient genuinely witnesses nothing rather than merely
		# looking as though they do not.
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

## Surgical site marking, which is a thing real theatres do for exactly the
## reason it is here: so that the answer to "which side" exists on the patient
## and not only on a screen somebody has to have read carefully.
##
## Opening the wrong part of somebody is catastrophic and stays catastrophic.
## But a player who did it by misreading one line of a menu had been punished
## for a UI problem, and the fix is not a confirmation dialog — it is putting
## the information where the act happens. You can now see, from the doorway,
## which limb has an arrow on it.
const SITE_MARKS := {
	"wrist":    {"limb": "arm", "y": -0.42},
	"shoulder": {"limb": "arm", "y": -0.02},
	"knee":     {"limb": "leg", "y": -0.32},
	"ribs":     {"limb": "torso", "y": 0.06},
}

var _site_mark: MeshInstance3D = null
var _marked_site := ""

func refresh_site_mark() -> void:
	if data == null:
		return
	var site: String = TreatmentSystem.indicated_site_for(data)
	if site == _marked_site:
		return
	_marked_site = site
	if _site_mark != null:
		_site_mark.queue_free()
		_site_mark = null
	if not SITE_MARKS.has(site):
		return
	var spec: Dictionary = SITE_MARKS[site]
	var host: Node3D = null
	match String(spec["limb"]):
		"arm": host = _arms[0] if not _arms.is_empty() else null
		"leg": host = _legs[0] if not _legs.is_empty() else null
		_: host = _torso
	if host == null:
		return
	# A band, in the one colour nothing else in the building uses.
	_site_mark = Build.mi(Build.cyl_mesh(0.13, 0.055, 12),
		Build.unshaded(Color(0.95, 0.25, 0.62)), Vector3(0, float(spec["y"]), 0))
	host.add_child(_site_mark)

func _tick_state(_delta: float) -> void:
	if data == null or data.discharged:
		return
	refresh_site_mark()
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
	if _bark_timer > 0.0 or data == null or asleep:
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
	# Said before the overdue line, and said whether or not they are counting.
	# A patient who is well and has not been discharged is the single most
	# important thing in the building for the player to notice, and a number on
	# a tablet they have not opened yet cannot tell them.
	if data.ready_for_discharge() and not data.is_overdue() \
			and RNG.chance("patient_ready_bark", 0.75):
		say(Dialogue.patient_ready(data), 4.0)
		return
	if data.is_overdue() and data.knows_expected_date \
			and RNG.chance("patient_overdue_bark", 0.7):
		say(Dialogue.patient_overdue(data), 4.0)
		return
	say(Dialogue.patient_idle(data), 3.0)

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
	var day_room: bool = data.dept() == "psych" and h.is_room_open("day_room")
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

## The halo's own material, made once.
##
## This used to hand a fresh colour to Build.unshaded() every physics frame,
## which did two bad things at once. Build.unshaded() caches by colour string,
## so a pulsing alpha wrote a NEW material into a static dictionary sixty times
## a second per patient — an unbounded leak that also meant the halo shared its
## material with anything else that asked for the same colour. And it never
## rendered as a tint at all: Build.unshaded() leaves transparency at
## TRANSPARENCY_DISABLED, so the alpha the pulse animates was discarded and the
## "halo" was an opaque ball sitting on top of the patient.
var _halo: StandardMaterial3D = null

func _halo_mat() -> StandardMaterial3D:
	if _halo == null:
		_halo = (Build.unshaded(Color.WHITE) as StandardMaterial3D).duplicate()
		_halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_symptom_mesh.material_override = _halo
	return _halo

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
		_halo_mat().albedo_color = col

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
	# Doing anything to somebody wakes them. Treating a sleeping patient without
	# waking them would make night a free pass rather than a trade.
	wake_up("touched")
	if held != null:
		var tid := _treatment_for_item(held)
		if tid != "":
			var ts = get_tree().get_first_node_in_group("treatment_system")
			if ts != null:
				# In the world, unpaused. This used to open a modal that paused
				# the tree and then did the treatment inside the screen builder,
				# so the patient could not react to what had just been done to
				# them until after you had closed the box describing it.
				ts.apply(data, tid, held, held.global_position)
				var rs = get_tree().get_first_node_in_group("records_system")
				if rs:
					rs.log_real_treatment(data, tid)
			return
	look_toward(player.global_position if player else global_position)
	state = State.TALKING
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
	look_toward(player.global_position if player else global_position)
	state = State.TALKING
	_open_card()

func _open_card() -> void:
	EventBus.request_ui.emit("patient", {"patient_id": data.id, "npc_id": data.id})
