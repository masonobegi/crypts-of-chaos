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
		State.APPROACH:
			_timer = 25.0

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
			if _timer <= 0.0:
				_enter(State.IDLE)
		State.TALK:
			if _timer <= 0.0:
				_enter(State.IDLE)

## Only worth crossing the ward for if they actually have something on you.
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
	# A decent coffee machine is, mechanically, a nurse-retention device. Staff
	# spend more of the shift at the station and less of it in your wards.
	elif role == "nurse" and GameState.has_upgrade("coffee_machine") \
			and not GameState.flag("coffee_broken", false) \
			and RNG.chance("coffee_pull", 0.45):
		pool = ["station"]
	var key := String(RNG.pick("staff_patrol_pick", pool))
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
	if evt.tags.has("noise") or evt.tags.has("chaos"):
		var cdx = get_tree().get_first_node_in_group("codex")
		if cdx:
			cdx.note_distraction()
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
	GameState.adjust_rep("patient_sat", -0.004)
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

func interrupt_for_talk() -> void:
	_enter(State.TALK)

## Send them somewhere on an errand. This is the player's own distraction tool:
## the same effect a thrown bedpan has, except you chose the destination and
## nobody heard anything.
func send_to_room(room_key: String, seconds: float) -> void:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return
	_approached = true          # they are busy; no propositions mid-errand
	_enter(State.TASK)
	_timer = seconds
	goto(h.point_in(room_key, "errand_pt"), false)
	say(String(RNG.pick("errand_bark", [
		"Right, I'll go and look.", "Give me a minute.",
		"On my way.", "If you like.",
	])), 2.6)

## Where to send someone so they are genuinely out of your way.
func farthest_ward_from(pos: Vector3) -> String:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return "corridor"
	var best := "corridor"
	var best_d := -1.0
	for r in h.wards():
		var d: float = r.center().distance_to(pos)
		if d > best_d:
			best_d = d
			best = r.key
	return best

func prompt(_player) -> Array:
	var sub := ""
	if mind:
		var tier := mind.tier(GameState.career_minutes, GameState.active_covers)
		sub = ["", "seems a bit off with you", "is watching you", "does not trust you",
			"has made up their mind about you"][clampi(tier, 0, 4)]
	return ["Talk to %s" % display, sub]

func interact(player, _held) -> void:
	interrupt_for_talk()
	look_toward(player.global_position if player else global_position)
	EventBus.request_ui.emit("dialogue", {"npc_id": npc_id})
