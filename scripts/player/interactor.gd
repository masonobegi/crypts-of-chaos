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
	var hit := get_collider() if is_colliding() else null
	var target := _resolve_interactable(hit)
	if target == _hover:
		return
	_hover = target
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
	if _hover and _hover != held and _hover.has_method("prompt_with_item"):
		var p: Array = _hover.call("prompt_with_item", player, held)
		if p.size() > 0 and String(p[0]) != "":
			EventBus.interact_prompt.emit(String(p[0]), String(p[1]) if p.size() > 1 else "")
			return
	EventBus.interact_prompt.emit("Holding %s" % carried, "[RMB] throw   [LMB] drop")

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

func _handle_use(delta: float) -> void:
	var target := _hover
	if target == null or not target.has_method("interact"):
		_cancel_use()
		return
	var hold_time := 0.0
	if target.has_method("use_seconds"):
		hold_time = float(target.call("use_seconds", player, held))

	if Input.is_action_just_pressed("interact") and hold_time <= 0.0:
		target.call("interact", player, held)
		return

	if hold_time > 0.0 and Input.is_action_pressed("interact"):
		if _use_target != target:
			_use_target = target
			_use_progress = 0.0
		_use_progress += delta / hold_time
		EventBus.interact_prompt.emit(
			"%s  [%d%%]" % [_prompt_title(target), int(_use_progress * 100.0)], "hold [E]")
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

func _cancel_use() -> void:
	_use_progress = 0.0
	_use_target = null

# ------------------------------------------------------------------ grabbing
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
