extends RayCast3D
## Look-at prompts, physics grabbing, throwing, and using a held item on a target.
##
## The grab is a velocity spring, NOT a reparent. Held objects still collide with
## the world, so carrying a full bedpan past a doorframe is a genuine skill check
## and knocking a tray off the nurses' station is always available to you.

const REACH := 2.9
const HOLD_DISTANCE := 1.35
const GRAB_STRENGTH := 14.0
const MAX_GRAB_SPEED := 9.0
const BREAK_DISTANCE := 3.2
const THROW_IMPULSE := 7.5
const ROTATE_SPEED := 9.0

var held: RigidBody3D = null
var _held_gravity := 1.0
var _held_damp := 0.0
var _hover: Node = null
## What [E] acts on. Usually the same node as _hover, but a person standing
## behind a loose prop takes priority for USE while the prop keeps priority for
## GRAB — see _prefer_person.
var _use_hover: Node = null
## Whether there WAS something under the crosshair last frame. A freed object
## compares equal to null, so this is the only way to tell a thing that has been
## destroyed from a thing that was never there — and the difference decides
## whether the HUD prompt needs clearing.
var _had_hover := false
var _hold_yaw := 0.0
var _hold_pitch := 0.0
var _use_progress := 0.0
var _use_target: Node = null

@onready var player: Player = get_parent().get_parent().get_parent() as Player
@onready var camera: Camera3D = get_parent() as Camera3D

func _ready() -> void:
	target_position = Vector3(0, 0, -REACH)
	collision_mask = 1 | 4 | 8 | 16   # world | props | npc | interactable
	collide_with_areas = true
	enabled = true

func _physics_process(delta: float) -> void:
	_update_hover()
	if held:
		_drive_held(delta)
	_handle_input(delta)

# ------------------------------------------------------------------ hover
func _update_hover() -> void:
	# Anything we were pointing at can be freed out from under us between
	# frames — the whole street, with the mark and the rig point on it, goes
	# when the evening ends, and the crosshair is very often still on one of
	# them at that moment. Godot validates a freed object to null in a
	# comparison, so a stale `_hover` reads as equal to the null `target` the
	# raycast returns from the office, the "nothing changed" early return below
	# matches forever, and the fields are never reassigned: the street's prompt
	# stays on the HUD, and _handle_use()'s `var target := _use_hover` is then a
	# TYPED read of a previously freed instance, which raises and ABORTS the
	# function rather than yielding null (CLAUDE.md gotcha 11) — swallowing
	# every [E] press for the rest of the run. is_instance_valid() is the only
	# test that tells a freed object from a null one, and it is happy with null.
	#
	# Nulling the fields is only half of it. If the raycast ALSO returns nothing
	# — which is the described case exactly, the street is gone and the
	# crosshair is on empty air — then `null == null` on both sides and the
	# early return below still fires, so `interact_prompt_cleared` is never
	# emitted and the vanished street's prompt sits on the HUD until the player
	# happens to aim at something else. Whether anything CHANGED is the question
	# the early return is asking, and a thing being freed is a change.
	# `_had_hover` and not `_hover != null`, because a freed object COMPARES
	# equal to null — that is the whole trap — so the only way to tell "we were
	# pointing at something and it has been destroyed" from "we were pointing at
	# nothing, as usual" is to have written down that we had one. Without the
	# distinction this fires on every frame the crosshair is on empty air and
	# the prompt signals go out sixty times a second.
	var lost_something := false
	if not is_instance_valid(_hover):
		_hover = null
		lost_something = lost_something or _had_hover
	if not is_instance_valid(_use_hover):
		_use_hover = null
		lost_something = lost_something or _had_hover
	var hit := get_collider() if is_colliding() else null
	var target := _resolve_interactable(hit)
	var use_target := _prefer_person(target)
	if not lost_something and target == _hover and use_target == _use_hover:
		return
	_hover = target
	_use_hover = use_target
	_had_hover = target != null or use_target != null
	target = use_target
	if held != null:
		# While carrying, the prompt describes what you'd do WITH the thing.
		_show_carry_prompt()
		return
	if target == null:
		EventBus.interact_prompt_cleared.emit()
		return
	_show_prompt_for(target)

func _show_prompt_for(target: Node) -> void:
	var title := ""
	var sub := ""
	if target.has_method("prompt"):
		var p: Array = target.call("prompt", player)
		title = String(p[0]) if p.size() > 0 else ""
		sub = String(p[1]) if p.size() > 1 else ""
	elif target is RigidBody3D:
		title = "Pick up %s" % _display_name(target)
	if title == "":
		EventBus.interact_prompt_cleared.emit()
	else:
		EventBus.interact_prompt.emit(title, sub)

func _show_carry_prompt() -> void:
	var carried := _display_name(held)
	if _use_hover and _use_hover != held and _use_hover.has_method("prompt_with_item"):
		var p: Array = _use_hover.call("prompt_with_item", player, held)
		if p.size() > 0 and String(p[0]) != "":
			EventBus.interact_prompt.emit(String(p[0]), String(p[1]) if p.size() > 1 else "")
			return
	# THE KEYS THEY ACTUALLY BOUND, and the buttons if they are on a pad. This
	# read "[RMB] throw   [LMB] drop" in a build with a rebinding screen and a
	# controller layout — the same bug the HUD's corner reminder had, in the one
	# other place in the game that tells you which button to press.
	EventBus.interact_prompt.emit("Holding %s" % carried,
		"[%s] throw   [%s] drop" % [Settings.prompt_label("throw"),
			Settings.prompt_label("grab")])

## Loose objects do not get to stand in front of people.
##
## Every bed in the building has an IV stand beside it, and it stands squarely
## between the doorway-side approach and the patient's head — so walking up to
## a patient and looking straight at them reliably offered "Pick up IV Stand".
## The single most important interaction in the game lost, every time, to a
## pole. A play run confirmed it twice: with this off, the bedside prompt in
## Room 101 is the stand; with it on, it is Ines Bracket and what her bed earns.
##
## Scoped two ways so it cannot take anything away. Only a plain grabbable prop
## is overruled — a machine, a chart, a console or a door is a deliberate thing
## to be aiming at and keeps the prompt, because reaching past a patient for the
## dial is the entire game. And only the USE target changes: _hover still points
## at the prop, so [LMB] picks the stand up exactly as before.
## ...AND NEITHER DOES A DOORWAY.
##
## A patient who gets up and wanders stops in the ward doorway on the way, and
## a door's interaction area is not a RigidBody3D — so the crosshair offered
## "Open door" and the person standing in it could not be spoken to at all. The
## reasoning is the same as the IV stand's, and it is stronger here: a door can
## always be opened by WALKING INTO IT, which its own prompt says out loud, so
## nothing is taken away by letting a person in front of it win. Found by
## playing a whole shift with a controller on a seed nobody had played.
func _is_a_door(n: Node) -> bool:
	return n != null and n is Area3D and n.get("door") != null

func _prefer_person(target: Node) -> Node:
	if target != null and not _is_a_door(target) \
			and (target is NPCBody or not (target is RigidBody3D)):
		return target
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := global_position + global_transform.basis * target_position
	var q := PhysicsRayQueryParameters3D.create(from, to, 8)   # npc layer only
	q.exclude = [player.get_rid()]
	var res := space.intersect_ray(q)
	if res.is_empty():
		return target
	var person := _resolve_interactable(res.get("collider"))
	return person if person != null and person.has_method("interact") else target

## Walk up from the collider to whatever node actually implements interaction.
func _resolve_interactable(hit: Object) -> Node:
	var n := hit as Node
	while n != null:
		if n.has_method("interact") or n.has_method("prompt") or n is RigidBody3D:
			return n
		n = n.get_parent()
	return null

func _display_name(n: Node) -> String:
	if n and n.has_method("display_name"):
		return String(n.call("display_name"))
	return n.name.capitalize() if n else "it"

# ------------------------------------------------------------------ input
func _handle_input(delta: float) -> void:
	if player and player.input_locked:
		_cancel_use()
		return

	if Input.is_action_just_pressed("grab"):
		if held:
			drop()
		elif _hover is RigidBody3D and _can_grab(_hover):
			grab(_hover as RigidBody3D)

	if Input.is_action_just_pressed("throw") and held:
		throw()

	# Rotating a held object — needed to read a label, or to line a cart up with
	# a doorway you are about to fail to fit through.
	if held and Input.is_action_pressed("crouch"):
		var mm := Input.get_last_mouse_velocity()
		_hold_yaw += mm.x * 0.0004
		_hold_pitch += mm.y * 0.0004

	_handle_use(delta)

## How long "held" is, for targets that do one thing on a tap and another on a
## hold. Short enough that a hold is not a wait, long enough that a decisive tap
## is never read as one.
const LONG_PRESS := 0.42
var _long_fired := false

## How far a target you have already pressed on is allowed to drift before the
## press is dropped. The ray is 2.9m; this is "they took a step".
const KEEP_DISTANCE := 3.6

func _handle_use(delta: float) -> void:
	var target := _use_hover
	# THE THING YOU PRESSED ON, NOT THE THING UNDER THE CROSSHAIR WHEN YOU LET
	# GO.
	#
	# A tap on somebody with `interact_held` only fires on the way UP, and
	# patients get up and walk about — so pressing use on a patient who takes
	# one step during the 0.42s of the tap lost the crosshair, hit
	# `_cancel_use()` on the next frame, and the release did nothing at all. No
	# sound, no card, no message: exactly the "I pressed it and nothing
	# happened" that makes a game feel broken. Found by playing a whole shift
	# with a controller on a seed nobody had played, where a wandering patient
	# could not be talked to at all.
	#
	# Only while the press is in flight, only for a target that is still there,
	# and only while they are still within arm's reach — walking away from
	# somebody mid-press still cancels, which is what walking away means.
	if (target == null or not target.has_method("interact")) \
			and is_instance_valid(_use_target) \
			and (Input.is_action_pressed("interact")
				or Input.is_action_just_released("interact")) \
			and _still_near(_use_target):
		target = _use_target
	if target == null or not target.has_method("interact"):
		_cancel_use()
		return
	var hold_time := 0.0
	if target.has_method("use_seconds"):
		hold_time = float(target.call("use_seconds", player, held))

	# Tap-or-hold targets. A tap does the one thing you nearly always want; a
	# hold opens the options. Somebody sitting in the waiting row is admitted on
	# a tap and gives you their card on a hold, which is the difference between
	# "one keypress" and "four clicks down a menu".
	if hold_time <= 0.0 and target.has_method("interact_held"):
		if Input.is_action_just_pressed("interact"):
			_use_target = target
			_use_progress = 0.0
			_long_fired = false
		if Input.is_action_pressed("interact") and _use_target == target:
			_use_progress += delta / LONG_PRESS
			if _use_progress >= 1.0 and not _long_fired:
				_long_fired = true
				target.call("interact_held", player, held)
		if Input.is_action_just_released("interact") and _use_target == target:
			if not _long_fired:
				target.call("interact", player, held)
			_cancel_use()
		return

	if Input.is_action_just_pressed("interact") and hold_time <= 0.0:
		target.call("interact", player, held)
		return

	if hold_time > 0.0 and Input.is_action_pressed("interact"):
		if _use_target != target:
			_use_target = target
			_use_progress = 0.0
		_use_progress += delta / hold_time
		EventBus.interact_prompt.emit(
			"%s  [%d%%]" % [_prompt_title(target), int(_use_progress * 100.0)],
			"hold [%s]" % Settings.prompt_label("interact"))
		if _use_progress >= 1.0:
			_cancel_use()
			target.call("interact", player, held)
	elif not Input.is_action_pressed("interact"):
		_cancel_use()

func _prompt_title(target: Node) -> String:
	if target.has_method("prompt"):
		var p: Array = target.call("prompt", player)
		if p.size() > 0:
			return String(p[0])
	return "Use"

## Is a target we already pressed on still close enough to count.
func _still_near(n: Node) -> bool:
	var n3 := n as Node3D
	if n3 == null or not n3.is_inside_tree() or player == null:
		return false
	return player.global_position.distance_to(n3.global_position) <= KEEP_DISTANCE

func _cancel_use() -> void:
	_use_progress = 0.0
	_use_target = null
	_long_fired = false

# ------------------------------------------------------------------ grabbing
#
# THREE OF THE HOOKS BELOW ARE SEAMS, NOT FEATURES, and it is worth saying so
# in one place rather than leaving a reader to work it out three times.
# `can_grab`, `on_dropped` and `prompt_with_item` are all guarded with
# `has_method` and NOTHING IN THE GAME IMPLEMENTS ANY OF THEM — they were the
# interface the item system used, and the item system was cut. So every
# grabbable is decided purely on mass, nothing is told when it is put down, and
# carrying something always shows "Holding X" rather than what you could do
# with it. They stay because they are the cheapest possible way to add an item
# that behaves, and because a guarded call to a method nobody has costs
# nothing. They are not a description of anything the player can see.
func _can_grab(n: Node) -> bool:
	if n is not RigidBody3D:
		return false
	if n.has_method("can_grab") and not n.call("can_grab", player):
		return false
	return (n as RigidBody3D).mass <= 45.0

func grab(body: RigidBody3D) -> void:
	held = body
	_held_gravity = body.gravity_scale
	_held_damp = body.angular_damp
	body.gravity_scale = 0.0
	body.angular_damp = 6.0
	_hold_yaw = 0.0
	_hold_pitch = 0.0
	# Held items must not shove the player around; they still hit everything else.
	body.add_collision_exception_with(player)
	AudioMgr.play_var("pickup", -14.0)
	EventBus.item_picked_up.emit(body)
	if body.has_method("on_grabbed"):
		body.call("on_grabbed", player)
	_show_carry_prompt()

func drop() -> void:
	if held == null:
		return
	var b := held
	held = null
	b.gravity_scale = _held_gravity
	b.angular_damp = _held_damp
	b.remove_collision_exception_with(player)
	AudioMgr.play_var("drop", -16.0)
	EventBus.item_dropped.emit(b)
	if b.has_method("on_dropped"):
		b.call("on_dropped", player)
	_hover = null
	_use_hover = null

func throw() -> void:
	if held == null:
		return
	var b := held
	var dir := -camera.global_transform.basis.z
	drop()
	b.apply_central_impulse(dir * THROW_IMPULSE * clampf(2.0 / maxf(b.mass, 0.4), 0.4, 2.5))
	b.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.6)
	AudioMgr.play_var("whoosh", -14.0)
	if b.has_method("on_thrown"):
		b.call("on_thrown", player)

func _drive_held(delta: float) -> void:
	if not is_instance_valid(held):
		held = null
		return
	var hold_point := camera.global_position - camera.global_transform.basis.z * HOLD_DISTANCE
	var to := hold_point - held.global_position
	if to.length() > BREAK_DISTANCE:
		# Yanked out of your hands — usually by a door, occasionally by a patient.
		drop()
		return
	var desired := to / maxf(delta, 0.0001) * 0.35
	held.linear_velocity = held.linear_velocity.lerp(
		desired.limit_length(MAX_GRAB_SPEED), 1.0 - exp(-GRAB_STRENGTH * delta))

	var want := Basis.from_euler(Vector3(_hold_pitch, player.rotation.y + _hold_yaw, 0.0))
	var diff := (want * held.global_transform.basis.inverse()).get_rotation_quaternion()
	var axis := diff.get_axis()
	var ang := diff.get_angle()
	if ang > PI:
		ang -= TAU
	if axis.is_finite() and axis.length_squared() > 0.001:
		held.angular_velocity = held.angular_velocity.lerp(
			axis.normalized() * ang * ROTATE_SPEED, 1.0 - exp(-8.0 * delta))

## Carrying a wheelchair should feel like carrying a wheelchair.
func carry_speed_penalty() -> float:
	if held == null:
		return 1.0
	return clampf(1.0 - (held.mass / 70.0), 0.45, 1.0)

func is_holding(id: String) -> bool:
	return held != null and held.has_method("get_item_id") and String(held.call("get_item_id")) == id

func held_item_id() -> String:
	if held and held.has_method("get_item_id"):
		return String(held.call("get_item_id"))
	return ""

## Force-release, used when a nurse takes something off you or a cutscene starts.
func force_release() -> void:
	if held:
		drop()
