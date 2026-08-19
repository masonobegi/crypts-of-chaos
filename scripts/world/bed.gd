class_name PatientBed
extends RigidBody3D
## A hospital bed on wheels, with a patient on it.
##
## Beds are rigid bodies specifically so you can shove one down the corridor
## with a patient still in it. Wheeling someone to the treatment bay is a
## legitimate procedure; wheeling them somewhere cold and forgetting about them
## is a different procedure entirely, and the game does not distinguish.

@export var room_key := ""
@export var patient_id := ""

var occupant: Node3D = null          ## PatientNPC currently in this bed
var brake_on := true
var _mount: Marker3D = null

func _ready() -> void:
	add_to_group("bed")
	mass = 42.0
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	# Beds roll; they do not tip over and dump patients on the floor, because
	# that stops being funny the second time it happens by accident.
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	linear_damp = 2.6
	angular_damp = 4.0
	_apply_brake()

func build() -> void:
	var frame := Build.mat(Build.BED_FRAME, 0.4, 0.5)
	var linen := Build.mat(Build.LINEN)
	var rail := Build.mat(Build.METAL, 0.3, 0.7)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.7, 2.1)
	cs.shape = shape
	cs.position = Vector3(0, 0.45, 0)
	add_child(cs)

	var mesh_root := Node3D.new()
	mesh_root.name = "Mesh"
	add_child(mesh_root)
	mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(1.0, 0.14, 2.1)), frame, Vector3(0, 0.6, 0)))
	mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(0.94, 0.12, 1.9)), linen, Vector3(0, 0.72, 0)))
	mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(0.8, 0.1, 0.4)), linen, Vector3(0, 0.82, -0.72)))
	mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(1.06, 0.5, 0.08)), frame, Vector3(0, 0.85, -1.05)))
	mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(1.06, 0.36, 0.08)), frame, Vector3(0, 0.78, 1.05)))
	for sx in [-1.0, 1.0]:
		mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(0.05, 0.32, 1.2)), rail,
			Vector3(sx * 0.5, 0.86, -0.1)))
		for sz in [-1.0, 1.0]:
			mesh_root.add_child(Build.mi(Build.cyl_mesh(0.09, 0.1, 10), Build.mat(Color(0.2, 0.2, 0.22)),
				Vector3(sx * 0.42, 0.1, sz * 0.85), Vector3(0, 0, PI / 2)))
			mesh_root.add_child(Build.mi(Build.box_mesh(Vector3(0.07, 0.4, 0.07)), rail,
				Vector3(sx * 0.42, 0.33, sz * 0.85)))

	_mount = Marker3D.new()
	_mount.name = "Occupant"
	_mount.position = Vector3(0, 0.86, 0.05)
	add_child(_mount)

	var area := Area3D.new()
	area.name = "UseArea"
	area.collision_layer = 16
	area.collision_mask = 0
	var acs := CollisionShape3D.new()
	var ashape := BoxShape3D.new()
	ashape.size = Vector3(1.4, 1.4, 2.4)
	acs.shape = ashape
	acs.position = Vector3(0, 0.8, 0)
	area.add_child(acs)
	area.set_script(load("res://scripts/world/bed_use.gd"))
	area.set("bed", self)
	add_child(area)

func mount_point() -> Vector3:
	return _mount.global_position if _mount else global_position + Vector3(0, 0.86, 0)

func _apply_brake() -> void:
	freeze = brake_on
	if brake_on:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

func toggle_brake() -> void:
	brake_on = not brake_on
	_apply_brake()
	AudioMgr.play_at("squeak", global_position, -12.0)
	if not brake_on:
		WorldEvent.new("bed_unbraked", "player").at(global_position, room_key) \
			.about(patient_id).seen(0.1).tag("logistics") \
			.says("released the brake on a bed").emit()

func display_name() -> String:
	return "Bed"
