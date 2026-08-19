class_name SwingDoor
extends Node3D
## A swinging door that blocks movement and line of sight.
##
## Script-driven rather than joint-driven, deliberately.
##
## This was originally a RigidBody3D leaf on a HingeJoint3D. Two things went
## wrong with that and neither was visible without running the AI with real
## frames: a HingeJoint3D rotates about its own LOCAL Z, which at identity is
## horizontal, so the joint was pinning the leaf against rotating the only way a
## door can — and even with the axis corrected, the solver fought every attempt
## to drive the leaf, so a nurse could stand against a door indefinitely. Every
## ward was unreachable to staff and nothing caught it, because nothing ran the
## simulation frame by frame.
##
## Integrating an angle by hand keeps everything that mattered — doors swing,
## carry momentum, bounce off their stops, block sight when shut, and can be
## shoved by anybody — and makes "can a nurse get into this room" a certainty
## rather than a solver outcome.

const HEIGHT := 2.1
const THICK := 0.07
const MAX_ANGLE := 1.75          ## ~100 degrees
const DAMPING := 2.6
const OPEN_SPEED := 2.8
const PUSH_SPEED := 3.6

@export var room_key := ""
@export var width := 1.4

var leaf: AnimatableBody3D = null
var angle := 0.0
var angular_velocity := 0.0

var _was_open := false
var _mesh_root: Node3D = null

func build(a: Vector3, b: Vector3, _flip: bool) -> void:
	width = a.distance_to(b)
	position = a
	var along := (b - a).normalized()
	# Face the door so its local -Z runs along the wall; the leaf then swings
	# about this node's Y, which is what a door does.
	rotation.y = atan2(-along.x, -along.z) + PI * 0.5

	leaf = AnimatableBody3D.new()
	leaf.name = "Leaf"
	leaf.collision_layer = 1 | 32     # world | vision blocker
	leaf.collision_mask = 0
	leaf.sync_to_physics = false
	add_child(leaf)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(THICK, HEIGHT, width)
	cs.shape = shape
	cs.position = Vector3(0, HEIGHT * 0.5, width * 0.5)
	leaf.add_child(cs)

	_mesh_root = Node3D.new()
	_mesh_root.name = "Mesh"
	leaf.add_child(_mesh_root)
	_mesh_root.add_child(Build.mi(Build.box_mesh(shape.size),
		Build.mat(Color(0.78, 0.74, 0.66)), cs.position))
	# A window, so you can be seen through a shut door — which is the point.
	_mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(THICK * 1.4, 0.55, width * 0.45)),
		Build.mat(Color(0.60, 0.72, 0.75), 0.25), Vector3(0, 1.5, width * 0.5)))
	_mesh_root.add_child(Build.mi(Build.sphere_mesh(0.05),
		Build.mat(Build.METAL, 0.3, 0.7), Vector3(0, 1.05, width * 0.85)))

	var area := Area3D.new()
	area.name = "UseArea"
	area.collision_layer = 16
	area.collision_mask = 0
	var acs := CollisionShape3D.new()
	var ashape := BoxShape3D.new()
	ashape.size = Vector3(1.2, HEIGHT, width)
	acs.shape = ashape
	acs.position = Vector3(0, HEIGHT * 0.5, width * 0.5)
	area.add_child(acs)
	area.set_script(load("res://scripts/world/door_use.gd"))
	area.set("door", self)
	add_child(area)

func _physics_process(delta: float) -> void:
	if leaf == null:
		return
	if absf(angular_velocity) > 0.001 or absf(angle) > 0.001:
		angle += angular_velocity * delta
		angular_velocity = lerpf(angular_velocity, 0.0, 1.0 - exp(-DAMPING * delta))
		if absf(angle) >= MAX_ANGLE:
			# Bounce off the stop rather than sticking to it.
			angle = clampf(angle, -MAX_ANGLE, MAX_ANGLE)
			angular_velocity = -angular_velocity * 0.25
		# Ease shut once it has lost its momentum, like a real closer.
		if absf(angular_velocity) < 0.35:
			angle = lerpf(angle, 0.0, 1.0 - exp(-1.1 * delta))
		leaf.rotation.y = angle

	var open := is_open()
	if open != _was_open:
		_was_open = open
		AudioMgr.play_at_var("door", global_position, -20.0, 0.15)

func angle_deg() -> float:
	return rad_to_deg(angle)

func is_open() -> bool:
	return absf(angle) > 0.35

## Swing away from whoever is standing there. Used by NPCs and by the player.
func open_for(pos: Vector3, speed := OPEN_SPEED) -> void:
	if leaf == null:
		return
	# Which side of the door plane they are on. The door's local X is the plane
	# normal, since the leaf extends along local Z.
	var normal := global_transform.basis.x
	var side := signf((pos - global_position).dot(normal))
	if side == 0.0:
		side = 1.0
	angular_velocity = -side * speed

func push(from: Vector3) -> void:
	open_for(from, PUSH_SPEED)
	AudioMgr.play_at_var("door", global_position, -14.0)

func slam() -> void:
	angle = 0.0
	angular_velocity = 0.0
	if leaf:
		leaf.rotation.y = 0.0
	AudioMgr.play_at("thud", global_position, -6.0)
	WorldEvent.new("door_slammed", "player").at(global_position, room_key) \
		.heard(0.0, 16.0).tag("noise").says("a door slammed").emit()
