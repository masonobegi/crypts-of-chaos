class_name NPCBody
extends CharacterBody3D
## Base for every character in the building: a procedurally-assembled low-poly
## body, grid navigation, a head that looks at things, and a speech label.
##
## The body exists to BROADCAST STATE. If a nurse suspects you, she stops what
## she is doing and watches you — you should always be able to see trouble
## coming without opening a menu.

signal arrived()
signal spoke(text: String)

const WALK_SPEED := 1.85
const RUN_SPEED := 3.3
const TURN_SPEED := 7.0
const ARRIVE_DIST := 0.42

@export var npc_id := ""
@export var display := "Someone"
@export var role := "nurse"
@export var archetype := ""

var mind: Mind = null
var perception: NPCPerception = null

var skin := Color(0.87, 0.72, 0.60)
var outfit := Build.SCRUB_BLUE
var hair := Color(0.25, 0.18, 0.14)
var height_scale := 1.0

var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _speed := WALK_SPEED
var _look_at: Vector3 = Vector3.ZERO
var _has_look := false
var _walk_phase := 0.0
var _speech: Label3D = null
var _speech_timer := 0.0
var _nametag: Label3D = null
var _head: Node3D = null
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _torso: Node3D = null
var _react_cooldown := 0.0
## Set while physically startled — drives the flail animation.
var _startle := 0.0

func _ready() -> void:
	add_to_group("npc")
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	_build_body()
	perception = NPCPerception.new()
	perception.name = "Perception"
	add_child(perception)
	perception.setup(self)

# ------------------------------------------------------------------ body
func _build_body() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.7 * height_scale
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	add_child(cs)

	var root := Node3D.new()
	root.name = "Body"
	root.scale = Vector3.ONE * height_scale
	add_child(root)

	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.95, 0)
	root.add_child(_torso)
	_torso.add_child(Build.mi(Build.capsule_mesh(0.22, 0.62), Build.mat(outfit)))
	# Shoulders read as a person from a distance far better than a bare capsule.
	_torso.add_child(Build.mi(Build.box_mesh(Vector3(0.52, 0.12, 0.24)), Build.mat(outfit),
		Vector3(0, 0.24, 0)))

	_head = Node3D.new()
	_head.position = Vector3(0, 1.42, 0)
	root.add_child(_head)
	_head.add_child(Build.mi(Build.sphere_mesh(0.155), Build.mat(skin)))
	_head.add_child(Build.mi(Build.box_mesh(Vector3(0.28, 0.1, 0.26)), Build.mat(hair),
		Vector3(0, 0.09, -0.01)))
	# Eyes: the cheapest possible way to make "is this person looking at me"
	# legible across a corridor, which the whole suspicion system depends on.
	for sx in [-1.0, 1.0]:
		_head.add_child(Build.mi(Build.sphere_mesh(0.032), Build.unshaded(Color(0.08, 0.08, 0.1)),
			Vector3(sx * 0.062, 0.015, 0.135)))

	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.29, 1.18, 0)
		root.add_child(arm)
		arm.add_child(Build.mi(Build.capsule_mesh(0.062, 0.5), Build.mat(outfit), Vector3(0, -0.22, 0)))
		arm.add_child(Build.mi(Build.sphere_mesh(0.065), Build.mat(skin), Vector3(0, -0.46, 0)))
		_arms.append(arm)

		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.115, 0.66, 0)
		root.add_child(leg)
		leg.add_child(Build.mi(Build.capsule_mesh(0.08, 0.62), Build.mat(outfit.darkened(0.35)),
			Vector3(0, -0.3, 0)))
		leg.add_child(Build.mi(Build.box_mesh(Vector3(0.15, 0.08, 0.26)), Build.mat(Color(0.2, 0.2, 0.22)),
			Vector3(0, -0.62, 0.05)))
		_legs.append(leg)

	_nametag = Build.label3d(display, 0.085, Color(0.95, 0.96, 0.92))
	_nametag.position = Vector3(0, 1.92 * height_scale, 0)
	add_child(_nametag)

	_speech = Build.label3d("", 0.075, Color(1, 1, 1))
	_speech.position = Vector3(0, 2.12 * height_scale, 0)
	_speech.width = 900
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD
	_speech.visible = false
	add_child(_speech)

func set_colours(p_skin: Color, p_outfit: Color, p_hair: Color) -> void:
	skin = p_skin
	outfit = p_outfit
	hair = p_hair

# ------------------------------------------------------------------ movement
func goto(target: Vector3, run := false) -> void:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null or h.nav == null:
		return
	_path = h.nav.find_path(global_position, target)
	_path_i = 0
	_speed = RUN_SPEED if run else WALK_SPEED

func stop_moving() -> void:
	_path = PackedVector3Array()
	velocity.x = 0.0
	velocity.z = 0.0

func is_moving() -> bool:
	return _path_i < _path.size()

func distance_to(p: Vector3) -> float:
	return global_position.distance_to(p)

func look_toward(pos: Vector3) -> void:
	_look_at = pos
	_has_look = true

func clear_look() -> void:
	_has_look = false

func _physics_process(delta: float) -> void:
	_react_cooldown = maxf(0.0, _react_cooldown - delta)
	_startle = maxf(0.0, _startle - delta * 1.6)
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	else:
		velocity.y = 0.0
	_follow_path(delta)
	_face(delta)
	move_and_slide()
	_animate(delta)
	_tick_speech(delta)

func _follow_path(delta: float) -> void:
	if _path_i >= _path.size():
		velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-10.0 * delta))
		velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-10.0 * delta))
		return
	var target: Vector3 = _path[_path_i]
	var to := target - global_position
	to.y = 0.0
	if to.length() < ARRIVE_DIST:
		_path_i += 1
		if _path_i >= _path.size():
			arrived.emit()
		return
	var dir := to.normalized()
	velocity.x = lerpf(velocity.x, dir.x * _speed, 1.0 - exp(-9.0 * delta))
	velocity.z = lerpf(velocity.z, dir.z * _speed, 1.0 - exp(-9.0 * delta))

func _face(delta: float) -> void:
	var face_dir := Vector3.ZERO
	if _has_look:
		face_dir = _look_at - global_position
	elif is_moving():
		face_dir = Vector3(velocity.x, 0, velocity.z)
	face_dir.y = 0.0
	if face_dir.length_squared() < 0.001:
		return
	var want := atan2(-face_dir.x, -face_dir.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_SPEED * delta))

func _animate(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * (2.0 + planar * 3.4)
	var swing := sin(_walk_phase) * clampf(planar * 0.35, 0.02, 0.6)
	if _legs.size() >= 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
	if _arms.size() >= 2:
		# Flailing when startled is the entire visual payoff of throwing a tray.
		var flail := _startle * sin(_walk_phase * 9.0) * 1.4
		_arms[0].rotation.x = -swing * 0.8 + flail
		_arms[1].rotation.x = swing * 0.8 - flail
	if _torso:
		_torso.position.y = 0.95 + absf(sin(_walk_phase)) * clampf(planar * 0.02, 0.0, 0.03)
	if _head and _has_look:
		var to := _look_at - _head.global_position
		var local := to.normalized() * global_transform.basis
		_head.rotation.x = clampf(asin(clampf(local.y, -1.0, 1.0)) * 0.6, -0.5, 0.5)

# ------------------------------------------------------------------ speech
const SUBTITLE_RANGE := 14.0

func say(text: String, seconds := 3.2) -> void:
	if _speech == null:
		return
	_speech.text = text
	_speech.visible = true
	_speech_timer = seconds
	spoke.emit(text)
	# Only caption speech the player could plausibly hear. A global subtitle feed
	# meant a patient muttering in Room 101 was captioned from the treatment bay,
	# which made the whole channel read as UI noise rather than as the ward.
	if _player_can_hear():
		EventBus.subtitle.emit(display, text, seconds)
	AudioMgr.play_at_var("grunt", global_position, -26.0, 0.3)

func _player_can_hear() -> bool:
	var p = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if p == null:
		return true      # no player (headless tooling) — do not swallow the line
	if global_position.distance_to(p.global_position) <= SUBTITLE_RANGE:
		return true
	# Same room still counts even if the room is a long one.
	return current_room() != "" and current_room() == p.current_room()

func _tick_speech(delta: float) -> void:
	if _speech_timer <= 0.0:
		return
	_speech_timer -= delta
	if _speech_timer <= 0.0 and _speech:
		_speech.visible = false

func startle(strength := 1.0) -> void:
	_startle = clampf(_startle + strength, 0.0, 1.5)

# ------------------------------------------------------------------ suspicion tells
## Refresh the visible signals of what this character currently believes.
func refresh_tell(player_pos: Vector3) -> void:
	if mind == null or _nametag == null:
		return
	var tier := mind.tier(GameState.career_minutes, GameState.active_covers)
	var colour := Color(0.95, 0.96, 0.92)
	match tier:
		1: colour = Color(0.95, 0.90, 0.65)
		2: colour = Build.WARN
		3: colour = Color(0.95, 0.45, 0.30)
		4: colour = Build.BAD
	_nametag.modulate = colour
	# The physical tell: from "suspicious" upward they stop and watch you.
	mind.watching = tier >= 2 and global_position.distance_to(player_pos) < 14.0
	if mind.watching:
		look_toward(player_pos + Vector3(0, 1.5, 0))

## Lay the character down (or stand them back up). Rotating the visual Body node
## rather than the whole node keeps the collision capsule upright, which is what
## every other system expects.
##
## A -90 degree rotation about X maps local +Y to local -Z, so the head ends up
## at the -Z end of the body — which is the pillow end of the bed.
func set_reclined(on: bool) -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	var b: Node3D = body
	b.rotation.x = -PI * 0.5 if on else 0.0
	b.position = Vector3(0, 0.86, 0.52) if on else Vector3.ZERO
	if _nametag:
		_nametag.position.y = 1.35 if on else 1.92 * height_scale
	if _speech:
		_speech.position.y = 1.6 if on else 2.12 * height_scale

func head_position() -> Vector3:
	if _head and _head.is_inside_tree():
		return _head.global_position
	return global_position + Vector3(0, 1.5, 0)

func display_name() -> String:
	return display

func current_room() -> String:
	var h = get_tree().get_first_node_in_group("hospital")
	if h and h.has_method("room_at"):
		return h.room_at(global_position)
	return ""
