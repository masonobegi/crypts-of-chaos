class_name PatientBed
extends StaticBody3D
## A hospital bed, with somebody in it.
##
## This was a chair for a while, and the note that asked for chairs was right
## about the game it was asking about: a person lying down is scenery you do
## things TO, and a person sitting upright looking at you is somebody you are in
## a room with.
##
## The redesign changed what the argument is about. The economy bills BED-NIGHTS,
## the ward sister asks why a bed was still occupied at ten o'clock, and the
## commercial audit found the statement screen printing "BED DAYS" over a room
## that visibly contained no beds — which made the whole premise read as a
## waiting area rather than a ward somebody is being kept in. So: a bed, with the
## patient propped at forty degrees against the pillows, which is upright enough
## to be talked to and unmistakably a bed you are being kept in.
##
## It does not move. There is nothing on it to interact with. The person is the
## interaction.

const LENGTH := 2.05
const WIDTH := 0.92
const MATTRESS_TOP := 0.62

@export var room_key := ""
@export var patient_id := ""

var occupant: Node3D = null
var _mount: Marker3D = null

func _ready() -> void:
	add_to_group("bed")
	collision_layer = 4
	collision_mask = 0

func build() -> void:
	# The bed's own patch on the floor. See `Build.blob_shadow` — the shipping
	# renderer has no ambient occlusion, so without this a ward is five beds
	# floating a centimetre over a flat plane.
	add_child(Build.blob_shadow(Vector2(WIDTH + 0.34, LENGTH + 0.26), 0.02))
	var frame := Color(0.86, 0.88, 0.90)
	var steel := Color(0.62, 0.65, 0.69)
	var linen := Color(0.93, 0.95, 0.96)
	var blanket := Color(0.42, 0.60, 0.66)

	# Head is local -Z, foot is local +Z.
	for z in [-LENGTH * 0.5 + 0.08, LENGTH * 0.5 - 0.08]:
		for x in [-WIDTH * 0.5 + 0.07, WIDTH * 0.5 - 0.07]:
			add_child(Build.mi(Build.cyl_mesh(0.028, 0.48, 8), Build.mat(steel),
				Vector3(x, 0.24, z)))
	# The deck.
	add_child(Build.box_mi(Vector3(WIDTH, 0.09, LENGTH), frame,
		Vector3(0, 0.50, 0), 0.6))
	# The mattress, raised at the head end so it reads as a backrest.
	add_child(Build.box_mi(Vector3(WIDTH - 0.06, 0.13, LENGTH * 0.55), linen,
		Vector3(0, MATTRESS_TOP - 0.02, LENGTH * 0.20), 0.9))
	var back := Build.box_mi(Vector3(WIDTH - 0.06, 0.13, LENGTH * 0.46), linen,
		Vector3(0, MATTRESS_TOP + 0.12, -LENGTH * 0.26), 0.9)
	back.rotation.x = -0.42
	add_child(back)
	# A blanket over the legs. Two thirds of the way up, like every hospital.
	add_child(Build.box_mi(Vector3(WIDTH - 0.02, 0.05, LENGTH * 0.44), blanket,
		Vector3(0, MATTRESS_TOP + 0.06, LENGTH * 0.25), 0.85))
	# Pillow.
	add_child(Build.box_mi(Vector3(WIDTH - 0.26, 0.10, 0.34), Color(0.97, 0.98, 0.99),
		Vector3(0, MATTRESS_TOP + 0.26, -LENGTH * 0.38), 0.95))
	# Head and foot boards, and the rails that make it a hospital bed rather
	# than a divan.
	for z in [-LENGTH * 0.5 + 0.03, LENGTH * 0.5 - 0.03]:
		add_child(Build.box_mi(Vector3(WIDTH + 0.04, 0.30, 0.05), frame,
			Vector3(0, 0.70, z), 0.6))
	for x in [-WIDTH * 0.5 - 0.01, WIDTH * 0.5 + 0.01]:
		add_child(Build.mi(Build.cyl_mesh(0.018, LENGTH * 0.42, 8), Build.mat(steel),
			Vector3(x, 0.80, -LENGTH * 0.12), Vector3(PI * 0.5, 0, 0)))
		add_child(Build.box_mi(Vector3(0.03, 0.20, 0.03), steel,
			Vector3(x, 0.70, -LENGTH * 0.33), 0.5))
		add_child(Build.box_mi(Vector3(0.03, 0.20, 0.03), steel,
			Vector3(x, 0.70, LENGTH * 0.09), 0.5))

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 0.06, 0.62, LENGTH)
	shape.shape = box
	shape.position = Vector3(0, 0.31, 0)
	add_child(shape)

	# Where the patient goes. Hips a little below the mattress top, because
	# set_in_bed() drops the body from the marker rather than standing on it.
	_mount = Marker3D.new()
	_mount.name = "Occupant"
	# Toward the HEAD end, so the hips land near the pillow and the legs run down
	# the mattress instead of the body sitting on the foot of the bed.
	_mount.position = Vector3(0, MATTRESS_TOP + 0.30, -LENGTH * 0.22)
	add_child(_mount)

func mount_point() -> Vector3:
	return _mount.global_position if _mount else global_position

func display_name() -> String:
	return "Bed"
