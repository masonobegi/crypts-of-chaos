class_name SwingDoor
extends Node3D
## A real hinged physics door. It can be shouldered open, blocked with a cart,
## left swinging, or used to knock a tray out of your own hands.
##
## Doors matter mechanically: a closed door is a line-of-sight blocker, so
## whether you shut it behind you is a genuine decision every single time.

const HEIGHT := 2.1
const THICK := 0.07
const OPEN_IMPULSE := 2.2

@export var room_key := ""
@export var width := 1.4

var leaf: RigidBody3D = null
var hinge: HingeJoint3D = null
var anchor: StaticBody3D = null
var _flip := false
var _was_open := false

func build(a: Vector3, b: Vector3, flip: bool) -> void:
	_flip = flip
	width = a.distance_to(b)
	position = a
	var along := (b - a).normalized()

	anchor = StaticBody3D.new()
	anchor.name = "Anchor"   # referenced by the hinge as a relative NodePath
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	add_child(anchor)

	leaf = RigidBody3D.new()
	leaf.name = "Leaf"       # ditto
	leaf.mass = 14.0
	leaf.collision_layer = 1 | 32     # world | vision blocker
	leaf.collision_mask = 1 | 2 | 4 | 8
	leaf.angular_damp = 1.6
	leaf.linear_damp = 4.0
	# The leaf hangs off one edge, so its collision and mesh are offset by half
	# a width from the hinge origin.
	var offset := along * (width * 0.5)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, HEIGHT, THICK) if absf(along.x) > absf(along.z) \
		else Vector3(THICK, HEIGHT, width)
	cs.shape = shape
	cs.position = offset + Vector3(0, HEIGHT * 0.5, 0)
	leaf.add_child(cs)
	var mesh_root := Node3D.new()
	mesh_root.name = "Mesh"
	leaf.add_child(mesh_root)
	mesh_root.add_child(Build.mi(Build.box_mesh(shape.size), Build.mat(Color(0.78, 0.74, 0.66)),
		offset + Vector3(0, HEIGHT * 0.5, 0)))
	# Window pane — you can be seen through it, which is the point.
	var pane_size := Vector3(shape.size.x * 0.45, 0.55, THICK * 1.4) \
		if absf(along.x) > absf(along.z) \
		else Vector3(THICK * 1.4, 0.55, shape.size.z * 0.45)
	mesh_root.add_child(Build.mi(Build.box_mesh(pane_size),
		Build.mat(Color(0.60, 0.72, 0.75, 1.0), 0.25),
		offset + Vector3(0, 1.5, 0)))
	# Handle, so which side it opens from is readable at a glance.
	mesh_root.add_child(Build.mi(Build.sphere_mesh(0.05), Build.mat(Build.METAL, 0.3, 0.7),
		along * (width * 0.85) + Vector3(0, 1.05, 0)))
	add_child(leaf)

	var area := Area3D.new()
	area.name = "UseArea"
	area.collision_layer = 16
	area.collision_mask = 0
	var acs := CollisionShape3D.new()
	var ashape := BoxShape3D.new()
	ashape.size = Vector3(width, HEIGHT, 1.2)
	acs.shape = ashape
	acs.position = offset + Vector3(0, HEIGHT * 0.5, 0)
	area.add_child(acs)
	area.set_script(load("res://scripts/world/door_use.gd"))
	area.set("door", self)
	add_child(area)

## The hinge is attached in _ready(), NOT in build().
##
## Assigning node_a/node_b makes the joint immediately resolve and read both
## bodies' global transforms. The door is assembled before it is added to the
## scene, so doing that in build() configures the joint against a detached node
## and it silently never hinges. Doing it here guarantees we are in the tree.
func _ready() -> void:
	# Deferred so the whole floor has finished assembling first. Assigning
	# node_a/node_b makes the joint resolve immediately and read both bodies'
	# global transforms, which is only valid once everything is settled in the
	# tree — doing it inline configures the joint against detached transforms and
	# the door silently never hinges.
	call_deferred("_attach_hinge")

func _attach_hinge() -> void:
	if leaf == null or anchor == null or hinge != null:
		return
	if not is_inside_tree():
		return
	hinge = HingeJoint3D.new()
	hinge.name = "Hinge"
	add_child(hinge)
	# Paths are relative to the joint: ".." is this door, then the sibling body.
	hinge.node_a = NodePath("../Anchor")
	hinge.node_b = NodePath("../Leaf")
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(100.0))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-100.0))
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.6)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_BIAS, 0.4)

func _physics_process(_delta: float) -> void:
	var open := is_open()
	if open != _was_open:
		_was_open = open
		AudioMgr.play_at_var("door", global_position, -20.0, 0.15)

func angle() -> float:
	return leaf.rotation.y if leaf else 0.0

func is_open() -> bool:
	return absf(angle()) > 0.35

## Nudge it open away from whoever is using it.
func push(from: Vector3) -> void:
	if leaf == null:
		return
	var to_leaf := leaf.global_position - from
	var dir := signf(to_leaf.normalized().dot(leaf.global_transform.basis.z))
	if dir == 0.0:
		dir = 1.0
	leaf.apply_torque_impulse(Vector3(0, -dir * OPEN_IMPULSE * leaf.mass * 0.1, 0))
	AudioMgr.play_at_var("door", global_position, -14.0)

func slam() -> void:
	if leaf == null:
		return
	leaf.angular_velocity = Vector3.ZERO
	leaf.rotation.y = 0.0
	AudioMgr.play_at("thud", global_position, -6.0)
	WorldEvent.new("door_slammed", "player").at(global_position, room_key) \
		.heard(0.0, 16.0).tag("noise").says("a door slammed").emit()
