class_name PatientBed
extends StaticBody3D
## The chair the patient is sitting in.
##
## It used to be a bed on castors you could shove down the corridor with a
## patient still in it. Two playtest notes killed that: "I don't want to be able
## to mess with the patient's bed any more", and "I don't want the patient in
## beds any more, I want them sitting in a chair". Both are right, and the
## second is the bigger change — a person lying down is scenery you do things
## TO, and a person sitting upright in a chair looking at you is somebody you
## are in a room with. Everything in this game is better when the patient is
## somebody you are in a room with.
##
## The class keeps its name because every system, save file and test in the
## project refers to a ward's occupied furniture as its bed, and renaming that
## would be a hundred edits to say the same thing. What it BUILDS is a chair,
## it does not move, and there is nothing on it to interact with.

@export var room_key := ""
@export var patient_id := ""

var occupant: Node3D = null          ## PatientNPC currently in this bed
var brake_on := true
var _mount: Marker3D = null

func _ready() -> void:
	add_to_group("bed")
	collision_layer = 4
	collision_mask = 0

func build() -> void:
	var frame := Build.mat(Color(0.34, 0.46, 0.54), 0.6)
	var pad := Build.mat(Color(0.62, 0.76, 0.80), 0.85)
	var arm_mat := Build.mat(Color(0.28, 0.38, 0.45), 0.6)
	# The collider is the seat and the legs, not the whole chair. A box the full
	# height of the back would have the sitting patient's own capsule inside it,
	# and the player still cannot walk through a chair whose bottom half is
	# solid.
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.86, 0.50, 0.80)
	cs.shape = shape
	cs.position = Vector3(0, 0.25, 0)
	add_child(cs)

	var mesh_root := Node3D.new()
	mesh_root.name = "Mesh"
	add_child(mesh_root)
	# A ward day-chair: seat, raked back, headrest, two arms, four legs. Seat
	# top at 0.48, which is the height every other chair in the building is, so
	# a seated pose written for one works in the other.
	mesh_root.add_child(Build.mi(Build.rbox_mesh(Vector3(0.78, 0.12, 0.72), 0.05),
		pad, Vector3(0, 0.42, 0)))
	mesh_root.add_child(Build.mi(Build.rbox_mesh(Vector3(0.78, 0.62, 0.12), 0.05),
		pad, Vector3(0, 0.79, -0.32), Vector3(-0.12, 0, 0)))
	mesh_root.add_child(Build.mi(Build.rbox_mesh(Vector3(0.58, 0.18, 0.10), 0.045),
		pad, Vector3(0, 1.12, -0.36), Vector3(-0.12, 0, 0)))
	for sx in [-1.0, 1.0]:
		mesh_root.add_child(Build.mi(Build.rbox_mesh(Vector3(0.09, 0.09, 0.62), 0.035),
			arm_mat, Vector3(sx * 0.43, 0.64, 0.0)))
		mesh_root.add_child(Build.mi(Build.rbox_mesh(Vector3(0.07, 0.20, 0.07), 0.03),
			frame, Vector3(sx * 0.43, 0.54, 0.28)))
		for sz in [-1.0, 1.0]:
			mesh_root.add_child(Build.mi(Build.rbox_mesh(Vector3(0.07, 0.42, 0.07), 0.03),
				frame, Vector3(sx * 0.36, 0.21, sz * 0.30)))

	# Where the occupant STANDS. The seated pose does the rest — it drops the
	# body onto the seat and folds the legs — so this is floor level, exactly
	# like every other chair somebody sits in.
	_mount = Marker3D.new()
	_mount.name = "Occupant"
	_mount.position = Vector3(0, 0.0, -0.04)
	add_child(_mount)

func mount_point() -> Vector3:
	return _mount.global_position if _mount else global_position

## Kept because save files from before the chair carry it. A chair has no brake
## and cannot be pushed, so this is a field, not a mechanic.
func toggle_brake() -> void:
	brake_on = not brake_on

func display_name() -> String:
	return "Chair"
