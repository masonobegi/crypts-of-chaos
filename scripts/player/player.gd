class_name Player
extends CharacterBody3D
## First-person doctor. Movement is deliberately slightly floaty and the
## grab is a physics spring rather than a parent-to-hand, because 90% of the
## comedy in this game comes from things going where you did not intend.

const WALK_SPEED := 3.4
const SPRINT_SPEED := 5.6
const CROUCH_SPEED := 1.8
const ACCEL := 12.0
const AIR_ACCEL := 3.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.0022
const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.0

@export var can_move := true
@export var can_look := true

var _yaw := 0.0
var _pitch := 0.0
var _bob := 0.0
var _step_accum := 0.0
var _crouching := false
var _target_head_y := STAND_HEIGHT
## Speed you are asking for this frame, before collision resolution. Needed
## because move_and_slide overwrites velocity — see _push_obstacles.
var _intended_speed := 0.0
## Camera kick, decaying. Deliberately reserved for the handful of moments the
## game wants you to FEEL rather than read in a toast: something breaking, a
## door slammed, somebody's condition turning. Everything else is head bob.
var _shake := 0.0
var _shake_t := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collider: CollisionShape3D = $Collider
@onready var interactor: Node = $Head/Camera3D/Interactor

## Set by systems that need to freeze the player (dialogue, UI, cutscene).
var input_locked := false:
	set(v):
		input_locked = v
		can_move = not v
		can_look = not v

func _ready() -> void:
	# The two moments where the institution moves against you. A letter opening
	# an investigation and a sanction landing are the biggest things that can
	# happen in a career and both of them used to be a line of text.
	EventBus.item_broke.connect(_on_item_broke)
	add_to_group("player")
	collision_layer = 2      # player
	collision_mask = 1 | 4 | 8   # world | props | npc
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and can_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = MOUSE_SENS * float(Settings.get_value("mouse_sensitivity"))
		var pitch_dir := 1.0 if not bool(Settings.get_value("invert_y")) else -1.0
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens * pitch_dir, -1.45, 1.45)
		rotation.y = _yaw
		head.rotation.x = _pitch

## The right stick, if there is one.
##
## Read every frame rather than driven by events, because a held stick generates
## no events — the same reason a mouse and a pad cannot share a code path. The
## curve is squared so small movements are fine control and the outer edge is
## fast, which is what every first-person game on a controller does and what
## makes one playable at all.
const PAD_LOOK_SPEED := 3.1
const PAD_DEADZONE := 0.16

func _handle_pad_look(delta: float) -> void:
	var look := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() < PAD_DEADZONE or not can_look:
		return
	var shaped := look.normalized() * pow((look.length() - PAD_DEADZONE) / (1.0 - PAD_DEADZONE), 2.0)
	var sens: float = PAD_LOOK_SPEED * float(Settings.get_value("pad_look_sensitivity"))
	var pitch_dir := 1.0 if not bool(Settings.get_value("invert_y")) else -1.0
	_yaw -= shaped.x * sens * delta
	_pitch = clampf(_pitch - shaped.y * sens * pitch_dir * delta, -1.45, 1.45)
	rotation.y = _yaw
	head.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	_handle_pad_look(delta)
	_handle_crouch(delta)
	_handle_movement(delta)
	_handle_bob(delta)

func _handle_crouch(delta: float) -> void:
	var want_crouch := Input.is_action_pressed("crouch") and can_move
	if want_crouch != _crouching:
		# Refuse to stand up under a shelf — being stuck crouching in the supply
		# room is a legitimate way to lose a shift.
		if not want_crouch and _blocked_above():
			pass
		else:
			_crouching = want_crouch
			var cap := collider.shape as CapsuleShape3D
			cap.height = CROUCH_HEIGHT if _crouching else STAND_HEIGHT
			collider.position.y = cap.height * 0.5
			_target_head_y = (CROUCH_HEIGHT if _crouching else STAND_HEIGHT) - 0.18
	head.position.y = lerpf(head.position.y, _target_head_y, 1.0 - exp(-14.0 * delta))

func _blocked_above() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.9, global_position + Vector3.UP * (STAND_HEIGHT + 0.1))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()

func _handle_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 14.0) * delta
	elif Input.is_action_just_pressed("jump") and can_move:
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO
	if can_move:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	var speed := WALK_SPEED
	if _crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint") and can_move:
		speed = SPRINT_SPEED
	# Carrying something bulky slows you down, which matters when you are trying
	# to get a cart somewhere before a nurse rounds the corner.
	if interactor and interactor.has_method("carry_speed_penalty"):
		speed *= interactor.carry_speed_penalty()

	var a := ACCEL if is_on_floor() else AIR_ACCEL
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-a * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-a * delta))
	# How hard you are TRYING to move, captured before move_and_slide gets to
	# have an opinion about it. See _push_obstacles.
	_intended_speed = Vector2(target.x, target.z).length()
	_open_door_ahead()
	var before := global_position
	# What move_and_slide is about to be HANDED, as opposed to what we are asking
	# the body to work up to over the next few frames. The two are the same only
	# at full speed, and _step_up needs this one.
	var commanded := Vector2(velocity.x, velocity.z).length()
	move_and_slide()
	_step_up(before, dir, delta, commanded)
	_push_obstacles()

## Walking up a kerb.
##
## There was no step handling at all: a CharacterBody3D stops dead against
## anything taller than its safe margin, and the street's pavement is a fifth of
## a metre proud of the road. The report was "I couldn't get on the sidewalk for
## one of them" and it was literally true — the kerb was a wall.
##
## The standard three-move version, done only when we are actually stuck: lift
## by the step height, try the move again from up there, and drop back down. If
## the drop finds nothing to stand on within the step height, put everything
## back and take the wall, so this cannot be used to walk up the side of a
## building or off a stair edge into the air.
const STEP_HEIGHT := 0.34

func _step_up(before: Vector3, dir: Vector3, delta: float, commanded: float) -> void:
	if not is_on_floor() or dir.length_squared() < 0.01:
		return
	# Did we actually get anywhere? A fraction of what we asked for means blocked.
	#
	# Measured against the velocity move_and_slide was handed this frame, NOT
	# against the target speed. ACCEL lerps velocity toward the target, so a
	# standing start only commands 18% of WALK_SPEED on its first frame and 33%
	# on its second — both under 40% of the target — and "blocked" was therefore
	# true on open, flat floor for the first two frames of every single walk.
	# The three-move below then found free air at +0.34m with floor beneath it,
	# which is what a kerb looks like, and teleported the body forward: a
	# framerate-dependent lurch out of every standing start (two qualifying
	# frames at 60fps, six at 120), with the bottom third of the capsule swept
	# through whatever happened to be in front of it. A body that is genuinely
	# stuck delivers almost none of what it was handed whether it was
	# accelerating or not, so the ratio against `commanded` is the honest test.
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if commanded < 0.05 or moved > commanded * delta * 0.4:
		return
	var want := Vector3(dir.x, 0.0, dir.z).normalized() * maxf(_intended_speed * delta, 0.06)
	var from := global_transform
	var up := from
	up.origin += Vector3.UP * STEP_HEIGHT
	# Somewhere to put a foot up there?
	if test_move(up, want):
		return
	up.origin += want
	if not test_move(up, Vector3.DOWN * (STEP_HEIGHT + 0.02)):
		return      # nothing below: that was a ledge, not a step
	global_transform = up
	move_and_collide(Vector3.DOWN * (STEP_HEIGHT + 0.02))

## Look a metre and a half ahead and open any door in the way, BEFORE walking
## into it. NPCs have done this since doors were script-driven; the player never
## did, and waited for body contact instead.
##
## Body contact is much too late. A door opening toward you is a kinematic body
## sweeping through the space you are standing in, and it shoves you sideways —
## a scripted walk from Room 102 to the office was knocked off its line into the
## wall recess beside the office door and spent sixty seconds there. Probing
## ahead means the leaf is already out of the way by the time you reach it,
## which is both what a person experiences and the only version that does not
## involve being hit by furniture.
##
## Further than the NPCs' 1.15m, because the player walks faster than they do.
const DOOR_REACH := 1.6

func _open_door_ahead() -> void:
	if _intended_speed < 0.15 or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	# Along the way you are TRYING to go, not the way you are facing: strafing
	# through a doorway is an ordinary thing to do and used to walk you into
	# the leaf side-on.
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length_squared() < 0.04:
		dir = -global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * DOOR_REACH)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var door := _door_of(hit.get("collider"))
	if door == null:
		return
	# Note the absence of "and not door.is_open()". Stopping as soon as it is
	# nominally open hands it straight back to its own closer: the leaf reaches
	# about twenty degrees, nobody is driving it any more, it eases shut, the
	# probe fires again, and it oscillates in the gap forever. A play run stood
	# outside the supply room for forty-five seconds watching a door open and
	# shut on him. open_for() already declines to re-slam a door that is
	# against its stop, so driving it every frame is free.
	door.open_for(global_position)

## Shoving things with your body: walking into an IV stand should topple it, and
## walking into a door should open it.
##
## The impulse is scaled by how hard you are TRYING to move, not by how fast you
## ended up going. move_and_slide zeroes your velocity along the axis you are
## blocked on, so gating the shove on post-slide speed means the instant a prop
## actually stops you, you can no longer push it — you are stuck against it
## precisely because it is in your way. A play run spent sixty seconds wedged on
## a wet floor sign in the middle of the corridor, and could only get past by
## sprinting, because sprinting happened to leave enough residual speed to
## generate an impulse. This is the same bug NPCBody was fixed for and the player
## never was.
func _push_obstacles() -> void:
	var speed := maxf(Vector2(velocity.x, velocity.z).length(), _intended_speed)
	if speed < 0.15:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var door := _door_of(c.get_collider())
		if door != null:
			door.open_for(global_position)
			continue
		# Two CharacterBody3Ds cannot move each other at all: neither one is
		# affected by the other's velocity, and move_and_slide zeroes the
		# blocked axis on both. A nurse standing in a two-metre corridor was
		# therefore a wall. There are eight staff on a sixty-two-metre floor and
		# they walk the length of it all shift, so the commonest thing in the
		# game was being unable to get past a colleague — a play run lost eleven
		# seconds to Nurse Nell without either party doing anything wrong.
		var npc := c.get_collider() as NPCBody
		if npc != null:
			npc.step_aside(global_position)
			continue
		var rb := c.get_collider() as RigidBody3D
		if rb == null or rb.mass >= HEAVY_MASS:
			continue
		rb.apply_central_impulse(-c.get_normal() * shove_impulse(rb.mass, speed))

## Nothing above this shifts for a person walking into it. A vending machine
## stays where it is; a bed does not.
const HEAVY_MASS := 150.0

## How much momentum, in kg·m/s, a walking person can put into something per
## contact. Everything else follows from it.
const PUSH_POWER := 45.0

## Light things scatter, heavy things grudgingly give way. A cart left in a
## doorway should genuinely cost you a second, not a shift.
##
## The old rule divided a constant by mass and then multiplied by a tenth of
## walking speed, which produced 1.9 N·s against a twenty-kilo wheelchair — a
## tenth of a metre per second, i.e. nothing. A play run spent twenty-one
## seconds getting into Room 101 past a wheelchair that a person would have
## kicked out of the way without breaking stride.
##
## Now it is momentum-shaped: you can impart PUSH_POWER, but never more than the
## thing would have if it were already moving as fast as you are. Light objects
## are limited by their own mass and shoot off; heavy ones are limited by you
## and grudgingly slide.
##
## Pure, so the rule that matters — that a blocked walker still generates a real
## impulse, and that a heavier thing moves less for the same shove — can be
## asserted without waiting on a physics frame.
static func shove_impulse(mass: float, speed: float) -> float:
	return minf(PUSH_POWER, maxf(mass, 0.2) * speed) * 0.35

func _door_of(body: Object) -> SwingDoor:
	var n := body as Node
	while n != null:
		if n is SwingDoor:
			return n
		n = n.get_parent()
	return null

func _handle_bob(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar > 0.4:
		_bob += delta * planar * 1.9
		_step_accum += delta * planar
		if _step_accum > 2.1:
			_step_accum = 0.0
			AudioMgr.play_at_var("step", global_position, -22.0, 0.18)
	else:
		_bob = lerpf(_bob, 0.0, 1.0 - exp(-8.0 * delta))
	# Two different frequencies so a kick reads as a jolt rather than a wobble,
	# and it lands on TOP of the bob instead of replacing it — a shake that
	# cancels your footsteps feels like the game stopped for a moment.
	_shake = maxf(0.0, _shake - delta * 2.6)
	_shake_t += delta * 34.0
	var k := _shake * _shake
	# Both amounts are scaled by the comfort sliders. Somebody who cannot play
	# with head bob on should be able to turn it off rather than stop playing.
	var bob_amt: float = float(Settings.get_value("head_bob"))
	camera.position.y = sin(_bob) * 0.035 * bob_amt + sin(_shake_t) * k * 0.05
	camera.position.x = cos(_bob * 0.5) * 0.022 * bob_amt + sin(_shake_t * 1.7) * k * 0.04
	camera.rotation.z = lerpf(camera.rotation.z,
		-cos(_bob * 0.5) * 0.012 * bob_amt, 1.0 - exp(-10.0 * delta)) \
		+ sin(_shake_t * 0.9) * k * 0.03

## Kick the camera. `amount` is roughly "how much of a full jolt", 0..1; they do
## not stack past one, so a pile-up of small events cannot black out the screen.
func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount * float(Settings.get_value("camera_shake"))), 0.0, 1.0)

## Where the player is, in room terms — used by perception and events.
func current_room() -> String:
	var hospital := get_tree().get_first_node_in_group("hospital")
	if hospital and hospital.has_method("room_at"):
		return hospital.room_at(global_position)
	return ""

func eye_position() -> Vector3:
	return camera.global_position

func face(target: Vector3) -> void:
	var to := target - global_position
	_yaw = atan2(-to.x, -to.z)
	rotation.y = _yaw

func _on_item_broke(item: Node) -> void:
	if item is Node3D and global_position.distance_to((item as Node3D).global_position) < 5.0:
		shake(0.45)
