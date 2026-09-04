class_name StaffNPC
extends NPCBody
## Nurses and doctors. Patrols, tasks, noise investigation, and the two
## behaviours that make the stealth loop work: WATCHING you when suspicious, and
## LEAVING to look at a noise when something falls over somewhere else.

enum State { IDLE, PATROL, INVESTIGATE, WATCH, FOLLOW, TALK, TASK, APPROACH }

@export var patrol_rooms: Array[String] = []
@export var home_room := "station"

var state: State = State.IDLE
var _timer := 0.0
var _investigate_target := Vector3.ZERO
var _investigate_room := ""
var _idle_bias := 1.0
var _patrol_speed := 1.0
var _talk_cooldown := 0.0
var _approached := false
var _round_target := ""
## Set for a shadowing student: they follow you all shift and see everything.
var shadow_player := false

func _ready() -> void:
	super._ready()
	add_to_group("staff")
	_idle_bias = DB.trait_of(archetype, "idle_bias", 1.0)
	_patrol_speed = DB.trait_of(archetype, "patrol_speed", 1.0)
	_enter(State.IDLE)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_timer -= delta
	_talk_cooldown = maxf(0.0, _talk_cooldown - delta)
	_tick_state(delta)

func _enter(s: State) -> void:
	state = s
	# A round belongs to the TASK state. Leaving it without clearing the target
	# left the nurse permanently "on a round" she had already abandoned, and the
	# next patrol overwrote her path so she never arrived at all.
	if s != State.TASK:
		_round_target = ""
	match s:
		State.IDLE:
			stop_moving()
			clear_look()
			_timer = RNG.randf_range_s("staff_idle", 2.0, 6.0) * _idle_bias
		State.PATROL:
			_timer = 20.0
			_pick_patrol_target()
		State.INVESTIGATE:
			_timer = 16.0
			goto(_investigate_target, true)
		State.WATCH:
			stop_moving()
			_timer = RNG.randf_range_s("staff_watch", 3.0, 7.0)
		State.FOLLOW:
			_timer = 12.0
		State.TALK:
			stop_moving()
			_timer = 6.0
		State.TASK:
			_timer = RNG.randf_range_s("staff_task", 6.0, 14.0)
			_begin_round()
			# A round takes as long as the walk takes. The default task timer is
			# shorter than a trip across the ward, so it expired mid-corridor and
			# the nurse turned around before seeing anything.
			if _round_target != "":
				_timer = 30.0
		State.APPROACH:
			_timer = 25.0

## Not while they are on their way somewhere that matters. Standing still for
## two and a half seconds is a real cost to a character who is mid-errand, and
## it made the "does a noise pull anybody off station" check intermittent — a
## nurse who froze to write something up on the way to the supply room had, from
## the outside, simply ignored the noise.
func can_stop_to_write() -> bool:
	return state not in [State.INVESTIGATE, State.FOLLOW, State.APPROACH]

func _tick_state(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")

	# Suspicion overrides whatever they were doing. This is the tell that makes
	# getting caught feel earned — you can always see them stop and look.
	if state not in [State.TALK] and mind != null and player != null:
		var tier := mind.tier(GameState.career_minutes, GameState.active_covers)
		if tier >= 2 and perception and perception.sees_player():
			if state != State.WATCH and state != State.FOLLOW:
				_enter(State.WATCH)

	# A student on placement is a mobile witness attached to your hip. They do
	# not escalate much on their own, but they see absolutely everything and
	# they talk to the staff room at the end of the day.
	if shadow_player and player != null and state not in [State.TALK]:
		look_toward(player.global_position + Vector3(0, 1.5, 0))
		if distance_to(player.global_position) > 2.8:
			goto(player.global_position)
		elif is_moving():
			stop_moving()
		return

	# Somebody who wants something from you comes and finds you. This is the
	# moment a witness stops being a hazard and becomes a negotiation.
	if state in [State.IDLE, State.PATROL, State.TASK] and not _approached and player != null:
		if _wants_a_word():
			_approached = true
			_enter(State.APPROACH)

	match state:
		State.APPROACH:
			if player == null or _timer <= 0.0:
				_enter(State.IDLE)
			elif distance_to(player.global_position) > 2.2:
				goto(player.global_position)
			else:
				stop_moving()
				look_toward(player.global_position + Vector3(0, 1.5, 0))
				_deliver_proposition()
		State.IDLE:
			if _timer <= 0.0:
				_enter(State.PATROL if RNG.chance("staff_patrol", 0.7 / _idle_bias) else State.TASK)
		State.PATROL:
			if not is_moving() or _timer <= 0.0:
				_enter(State.IDLE)
		State.INVESTIGATE:
			if player:
				look_toward(player.global_position)
			if not is_moving() or _timer <= 0.0:
				_on_reached_investigation()
				_enter(State.IDLE)
		State.WATCH:
			if player:
				look_toward(player.global_position + Vector3(0, 1.5, 0))
			if _timer <= 0.0:
				var tier: int = mind.tier(GameState.career_minutes, GameState.active_covers) if mind else 0
				# The genuinely alarming behaviour: at high suspicion they follow
				# you around the ward and you cannot do anything at all.
				if tier >= 3 and RNG.chance("staff_follow", 0.5):
					_enter(State.FOLLOW)
				else:
					_enter(State.IDLE)
		State.FOLLOW:
			if player == null or _timer <= 0.0:
				_enter(State.IDLE)
			else:
				look_toward(player.global_position)
				if distance_to(player.global_position) > 3.5:
					goto(player.global_position)
				else:
					stop_moving()
		State.TASK:
			if _round_target != "" and not is_moving():
				_do_round()
				_round_target = ""
			if _timer <= 0.0:
				_enter(State.IDLE)
		State.TALK:
			if _timer <= 0.0:
				_enter(State.IDLE)

## Nurses do rounds. This is not flavour: a round is how an undocumented
## complication gets NOTICED, which is the clock the player is racing.
## Nurses do rounds. This is the VISIBLE half of Adeyemi being on the ward: the
## chart entries she writes at ten, one, four and seven are produced by WardDay,
## but somebody has to actually walk to the bed.
##
## None of this worked. `_begin_round` targeted `h.point_in(p.room, ...)` and
## Patient has no `room` — accessing a property that is not there aborts the
## function, silently, so `_round_target` stayed empty and the nurse never once
## left the station. `_do_round` then called `ps.unnoticed_complications()` and
## `ps.notice_complication()`, and `_note_injury_pattern` called
## `p.acquired_injuries()` — none of which exist on PatientSystem or Patient.
## All of it is left over from a complications-and-injuries model that was
## deleted, and the only reason it never crashed is that the first dead property
## access killed the function before it could reach the rest.
func _begin_round() -> void:
	_round_target = ""
	if role != "nurse":
		return
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps == null:
		return
	var list: Array = ps.active()
	if list.is_empty():
		return
	if archetype == "lazy" and RNG.chance("lazy_skip_round", 0.7):
		return
	var p = RNG.pick("round_pick", list)
	var body = ps.get_body(String(p.id))
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	_round_target = String(p.id)
	# Stop a metre short, on the side the bed is open. Walking into the mattress
	# is what the nav margin is for.
	goto(body.global_position + Vector3(0.0, 0.0, 1.1), false)

## At the bedside. She looks at them, and sometimes says something — which is
## most of what makes the ward feel staffed rather than decorated.
func _do_round() -> void:
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps == null:
		return
	var body = ps.get_body(_round_target)
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	look_toward(body.global_position + Vector3(0, 1.2, 0))
	if RNG.chance("round_quiet", 0.45):
		say(String(RNG.pick("round_ok", [
			"All fine here.", "No change.", "Doing nicely, this one.",
			"Obs are stable.", "I'll write that up.",
		])), 2.4)

func _wants_a_word() -> bool:
	if mind == null or mind.deal_state != "none":
		return false
	if archetype not in ["corrupt", "loyal", "gossip"]:
		return false
	var worst := mind.strongest(GameState.career_minutes)
	if worst == null or worst.current_weight(GameState.career_minutes) < 0.25:
		return false
	return RNG.chance("wants_word", 0.5)

func _deliver_proposition() -> void:
	if mind == null or mind.deal_state != "none":
		_enter(State.IDLE)
		return
	match archetype:
		"corrupt":
			# She has a number in mind, and it scales with what she saw.
			var worst := mind.strongest(GameState.career_minutes)
			var weight: float = worst.current_weight(GameState.career_minutes) if worst else 0.3
			mind.deal_price = int(round(180.0 + weight * 900.0))
			mind.deal_state = "offered"
			say(String(RNG.pick("bribe_open", [
				"Doctor. A word. Somewhere that isn't here.",
				"I saw. And I've not written it down. Yet.",
				"We should talk about what I'm not going to say.",
			])), 4.5)
			EventBus.toast.emit("%s wants a word." % display, "suspicion")
		"loyal":
			say(String(RNG.pick("loyal_warn", [
				"Someone's been asking about your ward. Just so you know.",
				"I covered for you. I'd rather not do it twice.",
				"Whatever's going on — be careful. People are noticing.",
			])), 4.5)
			mind.deal_state = "refused"      # warning spent; no repeat
			EventBus.toast.emit("%s is covering for you. For now." % display, "info")
		"gossip":
			say(String(RNG.pick("gossip_warn", [
				"Everyone's talking about 103, by the way. Everyone.",
				"You didn't hear it from me, but people have opinions.",
				"I'd keep your head down this week if I were you.",
			])), 4.5)
			mind.deal_state = "refused"
			EventBus.toast.emit("Word is getting around.", "suspicion")
	_enter(State.IDLE)

func _pick_patrol_target() -> void:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return
	var pool: Array = patrol_rooms
	if pool.is_empty():
		pool = ["corridor", home_room]
	# A lazy nurse simply will not walk to the far end of the ward, which makes
	# the far end of the ward strategically valuable.
	if archetype == "lazy" and RNG.chance("lazy_skip", 0.6):
		pool = [home_room, "corridor"]
	# There are no upgrades to buy any more. What pulls Adeyemi back to the
	# station is the paperwork she has to do there, which is also what makes the
	# ward quiet at predictable moments — and a quiet ward is when a note gets
	# written without anybody watching.
	elif role == "nurse" and RNG.chance("station_paperwork", 0.35):
		pool = ["station"]
	# A department nobody has bought is behind a shutter, and a nurse who picks
	# one stands in the corridor waiting on a path that does not exist. Filtered
	# here rather than at spawn so the annexe fills with staff the moment it
	# opens — buying a department means more of the building is watched.
	var reachable: Array = []
	for k in pool:
		if true:  # every room in a four-room ward is open; the shutters are gone
			reachable.append(k)
	if reachable.is_empty():
		reachable = ["corridor"]
	var key := String(RNG.pick("staff_patrol_pick", reachable))
	goto(h.point_in(key, "staff_patrol_pt"), false)
	_speed = WALK_SPEED * _patrol_speed

## Noise pulls staff off station. This is the whole reason props are throwable.
func on_heard_noise(evt: WorldEvent) -> void:
	if state in [State.WATCH, State.FOLLOW, State.TALK]:
		return
	if archetype == "lazy" and RNG.chance("lazy_ignore", 0.65):
		return
	if not RNG.chance("investigate", 0.55 + mind.observance * 0.4 if mind else 0.6):
		return
	_investigate_target = evt.pos
	_investigate_room = evt.room
	_enter(State.INVESTIGATE)
	# A CODEX ENTRY WAS RECORDED HERE. The Codex — the notebook that wrote a
	# player a line about a mechanism once they had caused the same effect
	# twice — went with the redesign, and nothing has been in the "codex" group
	# since. The lookup returned null, the guard swallowed it, and the two lines
	# read as a working feature every time anybody scrolled past them.
	if _talk_cooldown <= 0.0:
		_talk_cooldown = 8.0
		say(String(RNG.pick("noise_bark", [
			"What was that?", "Hello?", "Oh, for—", "Was that in 103?",
			"Right, I'm coming.",
		])), 2.4)

## On arrival they look at the mess and form an opinion about the state of the
## ward — bad for your reputation, but not evidence of fraud.
func _on_reached_investigation() -> void:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return
	var r = h.room(_investigate_room)
	if r == null:
		return
	var gripes: Array = r.complaints()
	if gripes.is_empty():
		if RNG.chance("noise_shrug", 0.5):
			say(String(RNG.pick("shrug", ["Nothing.", "Must've been the pipes.", "Hm."])), 2.0)
		return
	say(String(RNG.pick("gripe", gripes)).capitalize() + ".", 3.0)
	# `GameState.adjust_rep()` used to be called here and it DOES NOT EXIST —
	# the reputation tracks went with the meta layer. Calling it threw, and a
	# throw ABORTS the function, so everything below this line was unreachable:
	# a nurse who walked in on a tampered room said her line and then never
	# recorded that she had found it.
	# A nurse who walks in on a freezing ward with the window open now KNOWS
	# the environment was tampered with, even if she never saw you do it.
	if r.window_open or not r.lights_on:
		var ev := Evidence.new()
		ev.kind = "found_environment_tampered"
		ev.about_actor = "player"
		ev.source = Evidence.Source.INFERRED
		ev.time = GameState.career_minutes
		ev.base_weight = 0.25 if not r.facilities_ticket_filed else 0.04
		ev.certainty = 0.6
		ev.cover_tag = "facilities"
		ev.summary = "found %s with the environment interfered with" % r.display
		if mind:
			mind.add_evidence(ev)

# A member of staff was somebody you could talk to: prompt() offered it and
# interact() opened the dialogue screen. That screen went with Dialogue and
# there is nothing behind the keypress any more — `request_ui.emit("dialogue")`
# reaches a router that has no "dialogue" in it, logs a warning nobody sees, and
# returns. So the prompt goes too, rather than hanging on a door that no longer
# opens. This is the same cleanup VisitorNPC already had; StaffNPC was missed.
#
# It was the worst-placed one of the pair. Adeyemi is the only other person on
# the ward, she is named in the morning briefing, and she talks in subtitles —
# so everybody presses E on her inside two minutes and gets a woman who turns
# her head and says nothing. Holding E also parked her in State.TALK, which is
# excluded from both suspicion escalation and noise investigation, so the one
# witness in the building could be frozen by leaning on a key.
#
# She watches, and she writes it up in the morning. That was always the
# dangerous half.
