class_name BrawlSystem
extends Node
## A physical disagreement, in the room, with the actual person.
##
## It was a 2D card with a drawing on it, and the note was "the fighting on that
## 2D minigame was pretty lame — as many times as you can make the minigames in
## the 3D world without them being obnoxious, the better". Right, and not just
## for this one: the whole reason the ward is first person is that a person in
## front of you is worth more than a picture of one.
##
## So: they stand up, you stop being able to walk away, and the exchange happens
## between two bodies in a room with a door. The rules are unchanged — cover the
## side they wind up on, the wind-up shortens, the shortest one is still longer
## than the window — because those were fine. What changed is that the wind-up
## is an arm and the tell is where they are actually standing.

var patient_system = null
var treatment_system = null

var active := false
var patient = null

var _body = null
var _player = null
var _side := 0
var _wind := 0.0
var _t := 0.0
var _recover := 0.0
var _exchange := 0
var _their_guard := Brawl.THEIR_GUARD
var _your_guard := Brawl.YOUR_GUARD
var _blocked := false
var _why := ""
var _was_can_move := true
var _objective_before := ""

func _ready() -> void:
	add_to_group("brawl_system")
	set_physics_process(false)
	# Whatever the ward last told the player to do, kept so the fight can put it
	# back. The objective line is emitted ONCE, at clock-in, and the tutorial's
	# is emitted only when a step advances — so blanking it at the end of a
	# fight left a new player staring at an empty instruction until they
	# happened to complete the step some other way. Only recorded while no fight
	# is running, because the guard prompt and the pips are ours and putting
	# either of those back afterwards would be worse than the blank.
	EventBus.objective_changed.connect(func(text):
		if not active:
			_objective_before = String(text))
	# The day ending stops the fight rather than leaving one running underneath
	# the chart review, still landing hits on somebody whose stay has already
	# been totted up.
	EventBus.shift_ended.connect(func(_day): cancel())

## Square up. Returns false if there is nobody to square up to.
## Where the fight actually took place. Sampled when it starts and again as it
## finishes, but always BEFORE anybody is moved: this is the position the
## altercation's WorldEvent carries, and that position is what decides who was
## near enough to see or hear it.
var _where_it_happened := Vector3.ZERO

func start(p) -> bool:
	if active or p == null or not Brawl.can_fight(p):
		return false
	# Not after the day has been signed off. `Brawl.can_fight()` is a statement
	# about the person — admitted, still here, not already on the floor — and
	# deliberately says nothing about the clock. But half of what a fight costs
	# is only wired up during the shift: losing bills you and then asks
	# ShiftSystem to end a day that has already ended, and winning adds three
	# days and a contusion AFTER `pending_findings()` has built the review the
	# player is sitting reading. "Go and fix it" on that review puts you back on
	# the floor with the phase still on CHART_REVIEW, which is exactly where
	# both of those happen.
	if not Brawl.on_the_clock():
		return false
	_body = patient_system.get_body(p.id) if patient_system != null else null
	_player = get_tree().get_first_node_in_group("player")
	if _body == null or _player == null or not _body.is_inside_tree():
		return false
	patient = p
	_their_guard = Brawl.THEIR_GUARD
	_your_guard = Brawl.YOUR_GUARD
	_where_it_happened = _body.global_position if _body.is_inside_tree() \
		else _player.global_position
	_exchange = 0
	_recover = 0.6
	_why = ""
	active = true

	# They get out of the chair. Somebody who stays sitting down is not in a
	# fight, they are being assaulted, and that is a different game.
	if _body.has_method("stand_and_square_up"):
		_body.stand_and_square_up(_player.global_position)
	_was_can_move = _player.can_move
	_player.can_move = false
	EventBus.objective_changed.emit(
		"[A]/[←] cover left · [D]/[→] cover right")
	EventBus.toast.emit('%s: "%s"' % [p.display_name,
		Brawl.opener(p, _mind_of(p), hash(p.id))], "warn")
	AudioMgr.play("gasp", -12.0)
	set_physics_process(true)
	return true

func _mind_of(p):
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	return sus.mind_of(p.id) if sus != null else null

func _physics_process(delta: float) -> void:
	if not active:
		return
	if _body == null or not is_instance_valid(_body) or _player == null:
		_finish(false)
		return
	_face_each_other(delta)
	if _recover > 0.0:
		_recover -= delta
		if _recover <= 0.0:
			_next_exchange()
		return
	_t += delta
	if not _blocked:
		if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left"):
			_try_block(-1)
		elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
			_try_block(1)
	# The arm, driven off the same clock the rules use. There is no separate
	# animation to fall out of step with.
	if _body.has_method("swing_arm"):
		var wind: float = clampf(_t / maxf(_wind, 0.01), 0.0, 1.0)
		var through: float = clampf((_t - _wind) / maxf(Brawl.WINDOW, 0.01), 0.0, 1.0)
		# The switch. Up to the feint point the arm they showed is the arm that
		# is moving; after it, the real one is, and it starts from where a
		# wind-up that far along would be.
		if _feint and wind >= Brawl.FEINT_AT:
			_shown = _side
		_body.swing_arm(_shown, wind, through)
	if _t >= _wind + Brawl.WINDOW:
		_land(false)

## Both of you keep looking at each other. A fight where somebody can turn round
## and wander off is not a fight.
func _face_each_other(delta: float) -> void:
	var to: Vector3 = _player.global_position - _body.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(to.x, to.z),
			1.0 - exp(-8.0 * delta))

func _next_exchange() -> void:
	_side = -1 if RNG.chance("brawl", 0.5) else 1
	_wind = Brawl.telegraph_for(_exchange)
	# Feint: they start one way and come the other. Decided now and revealed
	# partway through the wind-up, so covering early is a guess and covering on
	# the first thing you see is a mistake they get better at punishing.
	_feint = RNG.chance("brawl_feint", Brawl.feint_chance(_exchange))
	_shown = -_side if _feint else _side
	_t = 0.0
	_blocked = false
	_exchange += 1
	if _body.has_method("swing_arm"):
		_body.swing_arm(_shown, 0.0, 0.0)

var _feint := false
var _shown := 0

func _try_block(side: int) -> void:
	_blocked = true
	var early: bool = _t < _wind - Brawl.WINDOW
	if side == _side and not early:
		_land(true)
	else:
		_why = "Too early." if early else "Wrong side."
		_land(false)

func _land(blocked: bool) -> void:
	_recover = Brawl.RECOVER
	if _body.has_method("swing_arm"):
		_body.swing_arm(0, 0.0, 0.0)
	if blocked:
		_their_guard -= 1
		_body.startle(0.9)
		if _body.has_method("set_mood"):
			_body.set_mood(-0.7)
		AudioMgr.play("thud", -11.0, 1.25)
		EventBus.subtitle.emit("Blocked, and returned.", 1.4, "")
	else:
		_your_guard -= 1
		# The camera, via the player's own shake — which respects the
		# camera_shake accessibility setting and stacks on top of the walk bob,
		# and is what a door in the face and an opened investigation already
		# use. This system used to keep a private `_shake` float, decay it every
		# frame and expose it through an accessor "the HUD reads", except that
		# nothing in the HUD had ever heard of the brawl system: getting hit
		# moved nothing on screen at all.
		if _player.has_method("shake"):
			_player.shake(0.85)
		AudioMgr.play("thud", -5.0, 0.8)
		EventBus.subtitle.emit(_why if _why != "" else "That one landed.", 1.4, "")
		_why = ""
	EventBus.objective_changed.emit("%s  ·  you %s" % [
		_pips(_their_guard, Brawl.THEIR_GUARD), _pips(_your_guard, Brawl.YOUR_GUARD)])
	if _their_guard <= 0:
		_finish(true)
	elif _your_guard <= 0:
		_finish(false)

## Guard as pips rather than a number, because during a fight nobody reads a
## number.
func _pips(left: int, total: int) -> String:
	return "●".repeat(maxi(left, 0)) + "○".repeat(maxi(total - left, 0))

func _finish(won: bool) -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	# is_instance_valid, not just != null: `_player` is untyped, so a freed
	# instance sails past a null check and the property write errors. cancel()
	# already had this right and these two paths have to agree.
	if _player != null and is_instance_valid(_player):
		_player.can_move = _was_can_move
	# Sampled BEFORE knock_out() moves anybody. See the note at the event below.
	if _body != null and is_instance_valid(_body) and _body.is_inside_tree():
		_where_it_happened = _body.global_position
	if _body != null and is_instance_valid(_body):
		if _body.has_method("swing_arm"):
			_body.swing_arm(0, 0.0, 0.0)
		# Out cold BEFORE the event goes out, so they are not a witness to it.
		# "If I win the fight the patient should be knocked out so they can't
		# remember I just fought them" — which is exactly what an attention of
		# zero means to the perception pass.
		if won and _body.has_method("knock_out"):
			_body.knock_out()
		elif not won and _body.has_method("stand_down"):
			_body.stand_down()
	var res: Dictionary = {}
	if treatment_system != null and patient != null:
		# WHERE THE FIGHT WAS, not where the loser ended up. knock_out() puts
		# somebody who has a chair back into it before slumping them, so reading
		# the body afterwards reported a corridor brawl from the patient's own
		# room — and this position is what decides who could see and hear it. An
		# NPC standing over the actual fight failed the radius test while the
		# empty ward next door passed it.
		var where: Vector3 = _where_it_happened
		res = treatment_system.apply_brawl(patient, won, where)
	EventBus.objective_changed.emit(_objective_before)
	EventBus.request_ui.emit("fight", {
		"patient_id": patient.id if patient != null else "",
		"result": res, "won": won,
	})
	# Only when the loss actually PRODUCED something. apply_brawl() returns {}
	# for a patient who has been discharged, and _physics_process calls
	# _finish(false) the moment the body goes invalid — which, now that
	# discharged patients are genuinely freed, is a real path. With no result
	# there is no bill, no card and nothing said, so an unconditional call here
	# put the day's end back exactly where it was found: stopping for no stated
	# reason, which is the thing this was written to remove.
	if not won and not res.is_empty():
		_end_the_day_once_the_card_is_read()
	patient = null
	_body = null

## Losing ends the day — but not until the card that says so has been read.
##
## `apply_brawl` used to end it itself, with `call_deferred("end_shift", true)`,
## and a deferred call flushes at the end of the same physics step whether or
## not the tree is paused. So: `_finish` asked for the day to end, emitted
## `request_ui`, UIRoot built the result card — "you wake up on the floor", the
## bill, the rest of today gone — and before that frame was ever presented the
## flush ran `end_shift`, which fires `review_ready`, and `open("review")`
## closes whatever is up first. The player lost the afternoon, the evening and
## the best part of two thousand pounds and was shown their paperwork with
## nothing anywhere saying why.
##
## The card's own exit is the join instead, which is how every other
## end-of-phase screen hands back to ShiftSystem. Connected to the node rather
## than to a signal on the bus because there is no "screen closed" signal, and
## one-shot because the next fight will want its own.
func _end_the_day_once_the_card_is_read() -> void:
	var shift = get_tree().get_first_node_in_group("shift_system")
	if shift == null or not shift.can_end_day():
		return
	var game = get_tree().get_first_node_in_group("game")
	var card = game.get("ui").current if game != null and game.get("ui") != null else null
	if card == null or not is_instance_valid(card):
		# No card went up, so there is nothing to read and nothing to wait for.
		shift.call_deferred("end_shift", true)
		return
	card.tree_exited.connect(_end_the_day_now, CONNECT_ONE_SHOT)

func _end_the_day_now() -> void:
	# `tree_exited` also fires while a scene is being torn down, and a node on
	# its way out of the tree has nothing to look ShiftSystem up in — so this
	# checks that it is still standing in a tree before it goes asking.
	if not is_inside_tree():
		return
	var shift = get_tree().get_first_node_in_group("shift_system")
	if shift != null:
		shift.end_shift(true)

## Put the fight down without settling it.
##
## The day ending mid-exchange is the case: the review has already been built
## from the ward as it stood, so applying an outcome after it would be writing
## into a document the player is reading. Everything `_finish` restores is
## restored, and nothing it decides is decided.
func cancel() -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	if _player != null and is_instance_valid(_player):
		_player.can_move = _was_can_move
	if _body != null and is_instance_valid(_body):
		if _body.has_method("swing_arm"):
			_body.swing_arm(0, 0.0, 0.0)
		if _body.has_method("stand_down"):
			_body.stand_down()
	EventBus.objective_changed.emit(_objective_before)
	patient = null
	_body = null
