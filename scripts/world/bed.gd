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

var occupant: Node3D = null:
	set(v):
		occupant = v
		if _duvet != null:
			_duvet.visible = v != null
var _mount: Marker3D = null
var _duvet: MeshInstance3D = null

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
	#
	# ON CASTORS, because a hospital bed is on castors and this one stood on
	# four bare sticks pushed into the floor. It is eight centimetres of
	# geometry per corner and it is the difference between a bed and a table
	# with bedding on it: a wheel reads as "this is wheeled in and out", which
	# is the entire premise of the ward.
	var rubber := Color(0.20, 0.21, 0.24)
	for z in [-LENGTH * 0.5 + 0.08, LENGTH * 0.5 - 0.08]:
		for x in [-WIDTH * 0.5 + 0.07, WIDTH * 0.5 - 0.07]:
			add_child(Build.mi(Build.cyl_mesh(0.028, 0.40, 8), Build.mat(steel),
				Vector3(x, 0.28, z)))
			# The fork the wheel swivels in...
			add_child(Build.box_mi(Vector3(0.055, 0.05, 0.05), steel,
				Vector3(x, 0.075, z), 0.5, 0.006))
			# ...and the wheel, lying on its side across the bed's width.
			add_child(Build.mi(Build.cyl_mesh(0.048, 0.030, 12), Build.mat(rubber, 0.95),
				Vector3(x, 0.048, z), Vector3(0, 0, PI * 0.5)))
	# The deck.
	add_child(Build.box_mi(Vector3(WIDTH, 0.09, LENGTH), frame,
		Vector3(0, 0.50, 0), 0.6))
	# The mattress, raised at the head end so it reads as a backrest.
	add_child(Build.cloth_mi(Vector3(WIDTH - 0.06, 0.13, LENGTH * 0.55), linen,
		Vector3(0, MATTRESS_TOP - 0.02, LENGTH * 0.20)))
	var back := Build.cloth_mi(Vector3(WIDTH - 0.06, 0.13, LENGTH * 0.46), linen,
		Vector3(0, MATTRESS_TOP + 0.12, -LENGTH * 0.26))
	back.rotation.x = -0.42
	add_child(back)
	# A blanket over the legs. Two thirds of the way up, like every hospital.
	# WOVEN, NOT PAINTED. `Surfaces.fabric_mat` had been written and called by
	# nothing at all — the curtains, the bedding, the gowns and the upholstery
	# were every one of them a flat colour on a ward that had just been given a
	# speckled floor.
	add_child(Build.cloth_mi(Vector3(WIDTH - 0.02, 0.05, LENGTH * 0.44), blanket,
		Vector3(0, MATTRESS_TOP + 0.06, LENGTH * 0.25)))
	# Pillow.
	add_child(Build.cloth_mi(Vector3(WIDTH - 0.26, 0.10, 0.34), Color(0.97, 0.98, 0.99),
		Vector3(0, MATTRESS_TOP + 0.26, -LENGTH * 0.38)))
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

	# ...AND A DUVET OVER THE PERSON, WHEN THERE IS ONE.
	#
	# The bedside camera is the one the player spends the whole shift looking
	# through, and what it showed was a man lying on top of the covers in his
	# shoes. The blanket above is BEDDING — it is under the patient and hidden
	# by them the moment anybody is in the bed, which is why turning it bright
	# red and re-rendering the frame found no red on the occupied bed at all and
	# a corner of it on the empty one behind. Four blue-grey tubes with peach
	# ankles and navy shoes on the ends is not a patient, it is a mannequin laid
	# on a slab, and you cannot tell the arms from the legs.
	#
	# So: a second piece, from the hip line down past the feet, shown only when
	# somebody is in the bed. It hides the legs and the shoes, it separates the
	# arms from everything below them, and it is what a ward actually looks
	# like. Darker than the gowns on purpose — every gown in `Appearance` is a
	# pale wash, and a cover the same value as the person under it does nothing.
	# Raised where the person is, because that is what a cover over somebody
	# does — flat on the mattress it is under them and invisible, which is the
	# fault the bedding above already had.
	# WHERE THE LEGS ACTUALLY ARE, which is not where a blanket goes on an empty
	# bed. Measured in the real tree with the bed's transform inverted: the
	# patient occupies z -1.30 to -0.30 of a bed that runs -1.02 to +1.02, sat
	# up against the backrest, so a cover two thirds of the way down the mattress
	# is a cover over nobody. This one is over the LAP, which is what a propped
	# patient has, and it is what stops the frame being four blue-grey tubes with
	# navy shoes on two of them.
	# ...AND FAR ENOUGH DOWN THE BED TO REACH THE FEET. At 1.05 long it stopped
	# at the knees, and photographed from the bedside — which is the camera the
	# whole game is played through — the frame was a man propped up in bed with
	# two navy SHOES sticking out past the near edge of his own bedding. That is
	# the fault this piece exists to fix, half fixed: the lap was covered and the
	# legs were not. Found by turning it bright red and re-rendering the one
	# frame, which is ninety seconds and the only way anybody was ever going to
	# see it.
	# MEASURED, not guessed, and it took two goes. Printing the occupant's mesh
	# boxes through the bed's own inverted transform — after ninety PHYSICS
	# frames with the tree unpaused, because the pose is applied in
	# `_physics_process` and the morning briefing pauses the world, so a probe
	# that waits on `process_frame` measures a patient standing to attention —
	# puts the body at z -1.32..0.20 and the SHINS AND SHOES at y 0.78..1.15.
	# A cover 20cm thick over the lap therefore has fourteen centimetres of foot
	# coming up through it, which is what "navy shoes on a man in bed" actually
	# was: not a cover in the wrong place, a cover the legs were taller than.
	# Feet tent the bedding, so the duvet is as deep as they are.
	_duvet = Build.cloth_mi(Vector3(WIDTH - 0.04, 0.42, 1.42),
		Color(0.33, 0.49, 0.57), Vector3(0, MATTRESS_TOP + 0.37, -0.34))
	_duvet.visible = false
	add_child(_duvet)

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
