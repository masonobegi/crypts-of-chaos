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
var _shake := 0.0
var _why := ""
var _was_can_move := true

func _ready() -> void:
	add_to_group("brawl_system")
	set_physics_process(false)

## Square up. Returns false if there is nobody to square up to.
func start(p) -> bool:
	if active or p == null or not Brawl.can_fight(p):
		return false
	_body = patient_system.get_body(p.id) if patient_system != null else null
	_player = get_tree().get_first_node_in_group("player")
	if _body == null or _player == null or not _body.is_inside_tree():
		return false
	patient = p
	_their_guard = Brawl.THEIR_GUARD
	_your_guard = Brawl.YOUR_GUARD
	_exchange = 0
	_recover = 0.6
	_shake = 0.0
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
	_shake = maxf(0.0, _shake - delta * 3.0)
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
		_shake = 1.0
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
	if _player != null:
		_player.can_move = _was_can_move
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
		var where: Vector3 = _body.global_position if _body != null \
			and is_instance_valid(_body) else Vector3.ZERO
		res = treatment_system.apply_brawl(patient, won, where)
	EventBus.objective_changed.emit("")
	EventBus.request_ui.emit("fight", {
		"patient_id": patient.id if patient != null else "",
		"result": res, "won": won,
	})
	patient = null
	_body = null

## How hard the camera has just been hit, 0..1. The HUD reads this.
func shake() -> float:
	return _shake

## Which side is coming, if any: -1, 0 or 1, plus how far through the wind-up.
func telegraph() -> Array:
	if not active or _recover > 0.0:
		return [0, 0.0]
	return [_side, clampf(_t / maxf(_wind, 0.01), 0.0, 1.0)]

func guards() -> Array:
	return [_their_guard, _your_guard]
