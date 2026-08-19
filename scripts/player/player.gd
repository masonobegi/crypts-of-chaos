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
	add_to_group("player")
	collision_layer = 2      # player
	collision_mask = 1 | 4 | 8   # world | props | npc
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and can_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		rotation.y = _yaw
		head.rotation.x = _pitch

func _physics_process(delta: float) -> void:
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
	move_and_slide()

	# Shoving props with your body — walking into an IV stand should topple it.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb and rb.mass < 60.0:
			rb.apply_central_impulse(-c.get_normal() * clampf(velocity.length() * 0.25, 0.0, 3.0))

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
	camera.position.y = sin(_bob) * 0.035
	camera.position.x = cos(_bob * 0.5) * 0.022
	camera.rotation.z = lerpf(camera.rotation.z, -cos(_bob * 0.5) * 0.012, 1.0 - exp(-10.0 * delta))

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
