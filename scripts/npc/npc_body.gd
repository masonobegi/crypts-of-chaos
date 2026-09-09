class_name NPCBody
extends CharacterBody3D
## Base for every character in the building: a procedurally-assembled low-poly
## body, grid navigation, a head that looks at things, and a speech label.
##
## The body exists to BROADCAST STATE. If a nurse suspects you, she stops what
## she is doing and watches you — you should always be able to see trouble
## coming without opening a menu.

## SKIN IS NOT EMULSION. Every part of every person was built at roughness
## 0.85 — the same finish as a painted wall — so the closest and most
## looked-at object in the game had no highlight on it anywhere. Skin is a
## soft dielectric: a broad, low specular that reads as a sheen across a
## cheekbone rather than as a hotspot on a plastic doll.
const SKIN_ROUGH := 0.52

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
## Width independent of height, so two people the same height are not the same
## person scaled. Applied to the trunk and the limbs, never to the head — a
## head that scales with the body reads as a different species rather than a
## different build.
var girth := 1.0
## 0 is a full head of hair, 1 is none of it. Shrinks the crown and lifts the
## hairline rather than deleting the mesh, so it reads as thinning.
var bald := 0.0
var beard := false
## THE HEAD IS WHAT YOU READ AT THREE METRES, and every one in the building was
## the same ellipsoid at the same size with the same cap on it. `girth` and
## `height_scale` vary the body, which is a coat; these vary the person.
##
## Applied to the SILHOUETTE pieces only — skull, ears, jaw, hair — and never to
## the `_head` node itself, because the brows rotate for expressions and a
## rotated child of a non-uniformly scaled parent shears.
var skull := Vector3.ONE
var nose_size := 1.0
var jaw_size := 1.0
## Which of `Appearance.HAIR_STYLES` this head is cut in.
var hair_style := 0
## Whether anybody has actually chosen a look for this body. `PatientNPC._ready`
## used to force a gown colour unconditionally, which runs after the spawner has
## called `set_look` and before `_build_body` reads it — so every patient's gown
## came out the same hardcoded pale blue no matter what `Appearance` decided,
## and the variation was invisible on the largest surface on the model.
var _look_given := false
var _shadow: MeshInstance3D = null

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
## How an arm hangs when it is doing nothing: a little forward and a little out
## from the body. Both halves matter — everybody's arms vertical and parallel is
## a rack of mannequins — and both are tiny, because an arm that is obviously
## posed is worse than one that is obviously not.
const ARM_REST_X := 0.07
const ARM_REST_Z := 0.055
## Where a brow sits when nothing is happening. Written in TWO places — once
## when the head is built and once every time `set_mood` runs — so they have to
## be the same number or a neutral mood is a different face to a fresh one.
## AN EYE HAS TO BE DARKER THAN ANY FACE IT IS ON, AND UNSHADED CANNOT PROMISE
## THAT. The eye was `unshaded(0.10, 0.09, 0.11)` — a fixed emissive value — and
## measured off a real frame, the darkest skin in `Appearance.SKIN` renders at
## (56, 33, 16) while that eye renders at (68, 45, 37). The eye was LIGHTER than
## the face. On the four darkest of twelve skins these people had no eyes and no
## mouth, only brows and a nose, and the "eyes" in the picture were the head
## sphere's own shading.
##
## Lit, not unshaded, and that is the whole fix: a lit material is albedo times
## the same illumination the skin gets, so an eye at 0.03 against skin at 0.29 is
## ten times darker on every face in every room at every hour of the shift, and
## the ratio cannot come apart the way two absolute numbers did. Same for the
## mouth. The catchlight stays unshaded, because a catchlight IS a light.
## Gotcha 40's lesson exactly: take a reading off a render before choosing a
## colour, and take it off the hardest case rather than the average one.
const EYE_INK := Color(0.058, 0.040, 0.034)
const MOUTH_INK := Color(0.080, 0.045, 0.048)

const BROW_REST_Y := 0.052
const BROW_REST_Z := 0.09
var _eyes_open: Array[MeshInstance3D] = []
var _eyes_shut: Array[MeshInstance3D] = []
var _brows: Array[MeshInstance3D] = []
## The head sphere itself, so a test can measure the face against the real mesh.
var _skull_mi: MeshInstance3D = null
var _mouth: MeshInstance3D = null
var _mouth_corners: Array[MeshInstance3D] = []
## -1 is "you have made this worse", +1 is "that is much better". Sticky: it is
## set by something happening to them, not by the frame.
var _mood := 0.0
var _head_y := 1.50
var _arms: Array[Node3D] = []
var _torso: Node3D = null
var _react_cooldown := 0.0
## Speed we are TRYING to walk at, captured before move_and_slide resolves the
## collision. Needed because a blocked body's post-slide velocity is ~0, so
## gating the shove on it meant a body pressed against a door could never push
## it — which is exactly what was happening to every nurse on every ward door.
var _intended_speed := 0.0
## Stuck detection. Anything that wants to walk but has not actually moved for a
## while re-plans and steps aside. Without this a single bad spawn or a doorway
## scrum leaves a character standing in place for the rest of the shift, which is
## invisible in a screenshot and fatal to the simulation.
var _stuck_time := 0.0
var _last_progress_pos: Vector3 = Vector3.ZERO
## Idle motion. `_idle_offset` is per-character so a corridor of people does not
## breathe in unison, which reads as a machine rather than as a crowd.
var _knees: Array[Node3D] = []
var _idle_phase := 0.0
var _idle_offset := 0.0
var _blink_t := 2.0
var _blink_close := 0.0
## Set while physically startled — drives the flail animation.
var _startle := 0.0
## Whether this character is rostered on right now. See set_on_duty().
var on_duty := true
var _duty_layer := 8
var _off_duty_at := Vector3.ZERO
## Held in place by something else — a bed, for now. A pinned body does no
## physics at all.
##
## A patient in bed is re-pinned to the bed's origin every frame, and then the
## solver ran anyway: the bed's collision box is 1.0 x 0.7 x 2.1 about its own
## centre, the patient was pinned INSIDE it, and depenetration ejected them half
## a metre straight up. Every patient in the game has been hovering above their
## bed since beds were added, which reads at a distance as somebody lying down
## and at two metres as a head floating over the linen with no body attached.
## The screenshots were ambiguous enough to argue about; a smoke check that
## measures the head against the mattress is not.
var pinned := false
## Set while getting out of somebody's way. See step_aside().
var _yield_time := 0.0
var _yield_dir := Vector3.ZERO
## Set while standing still writing something down. See make_a_note().
var _note_time := 0.0
var _note_pad: Node3D = null


## WHERE THE FRONT OF THIS PARTICULAR HEAD IS.
##
## THE FACES WERE WELDED TO A FIXED z AND THE HEAD WAS NOT. `skull` is
## independent per axis and its z runs 0.90 to 1.09, so the head's own front
## surface moves by nearly four centimetres across the cast — and the eyes, the
## catchlight, the brows, the mouth and the sockets were all placed at literal
## depths tuned against an average head. Above about skull.z = 1.05 the front of
## the skull is IN FRONT OF THEM, so on those people the eyes, the mouth and one
## or both catchlights are inside their own head and simply do not exist.
##
## Photographed, measured and then found: on the darkest-skinned of the six
## `./faces.sh` subjects there was exactly ONE white pixel cluster where two
## catchlights should be (108 pixels on the left eye, 0 on the right), and the
## "eyes" reading in the frame were the shading of the head sphere. Every note in
## this file about the face being flat — and gotcha 44's whole measured argument
## that lighting is not the lever — was written about a model where some of the
## cast had no features at all. Nothing errors, nothing is missing from the
## scene, and the head still renders: the pieces are simply behind it.
##
## So the ellipsoid gets asked. `proud` is how far in front of its own surface
## the piece sits, in metres, and the numbers below are exactly the offsets the
## old literals had on an average head — so nobody who looked right changes, and
## everybody who did not is fixed.
## A LIP IS A PROPORTION OF A FACE, NOT A COLOUR.
##
## This was `skin.lerp(Color(0.62, 0.34, 0.34), 0.32).lightened(0.10)` — a lerp
## toward one fixed pink — and a lerp toward an absolute does opposite things at
## the two ends of a palette that runs from 0.29 to 0.96. On the pale skins the
## result is DARKER than the face and vanishes, which is why it looked fine; on
## the darkest it is two thirds lighter, so the one bright thing on the whole
## face was a salmon block under the mouth that read as an open mouth with the
## tongue showing. Reported as "some of the black characters\' faces look messed
## up compared to the white ones", and it is the same fault as the unshaded eye
## one line of this file away: an absolute value chosen against the middle of a
## range that the ends of the range cannot carry.
##
## In HSV off the person\'s own skin, so it is the same small step on all twelve.
## A TENTH, NOT A FIFTH: at s * 1.20 the middle of the palette — where the skins
## are most saturated — came out as an orange sliver under the bar, which is the
## same fault one notch along. Its job is only to be the thing the dark line is
## the top edge of; if you can name its colour it is wrong.
static func _lip(skin: Color) -> Color:
	return Color.from_hsv(skin.h, clampf(skin.s * 1.10, 0.0, 1.0),
		clampf(skin.v * 1.05, 0.0, 1.0), 1.0)

func _face_z(x: float, y: float, proud: float) -> float:
	var a: float = 0.215 * 0.98 * skull.x
	var b: float = 0.215 * 1.14 * skull.y
	var c: float = 0.215 * 0.92 * skull.z
	var t: float = 1.0 - (x / a) * (x / a) - (y / b) * (y / b)
	return c * sqrt(maxf(t, 0.0)) + proud


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
	cap.radius = 0.30
	cap.height = 1.78 * height_scale
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	add_child(cs)

	# Every character gets its own place in the breath cycle, from its own name.
	# Deterministic, so a seeded run looks the same twice, and not from an RNG
	# stream, so adding characters cannot shift anybody else's dice.
	_idle_offset = float(absi(hash(npc_id + display)) % 1000) * 0.00628
	_blink_t = 1.0 + float(absi(hash(display)) % 500) * 0.01

	var root := Node3D.new()
	root.name = "Body"
	root.scale = Vector3.ONE * height_scale
	add_child(root)

	# A PATCH ON THE FLOOR. The project ships on the Compatibility renderer,
	# which has no SSAO, so a character walking down a corridor had nothing at
	# all underneath them and read as pasted onto the floor rather than standing
	# on it. Parented to the BODY so it inherits the height scale, but pinned to
	# the character's own origin height, which is the floor when they are stood
	# on it. Hidden when seated — somebody in a bed is not casting this, the bed
	# is, and a patch hovering half a metre up is worse than none.
	_shadow = Build.blob_shadow(Vector2(0.86, 0.66), 0.02)
	add_child(_shadow)

	# Chunky on purpose, and TAPERED, and as few separate solids as possible.
	#
	# These were built to realistic human proportions — a 0.155m head on a
	# 0.22m torso with 0.062m arms — and at the distance you actually see
	# people in this game, across a sixty-two metre corridor, that reads as a
	# set of grey sticks. Made chunky, they read at distance and looked like a
	# stack of capsules up close.
	#
	# Two things fix that, and the second is not obvious. The first is
	# SILHOUETTE: shoulders wider than the waist, a head a fifth too big, hands
	# and feet that stick out past the limbs, no two parts the same width.
	#
	# The second is PART COUNT, because of the outline pass. The outline is a
	# second copy of each mesh grown along its normals, so a torso built from
	# three stacked slabs draws three outlines and every seam becomes a hard
	# black band across the chest — the first render of this was a person made
	# of pillows. Each limb and the trunk are now single tapered solids, and the
	# only interior details that carry a line of their own are the ones that
	# should read as separate objects: the collar, the cuffs, the hair.
	const LINE := 0.009
	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0, 0.95, 0)
	root.add_child(_torso)
	# One solid, hip to shoulder, broad at the top.
	# WOVEN. A gown is the largest single area of colour on the closest object
	# in the game, and it was the same flat paint finish as the cabinet behind
	# it. `Surfaces.fabric_mat` puts a warp and a weft in it, faded out by
	# `fwidth` before they can moire.
	# GIRTH ON THE TRUNK, and only on the trunk and the limbs. Scaling the whole
	# body would just be a taller or shorter copy of the same person; widening
	# the trunk against a fixed head is the difference between five sizes of one
	# person and five people.
	# ROUNDED HARD ENOUGH TO BE A BODY. At a corner radius of 0.13 on a solid
	# 0.70 wide and 0.36 deep, the flat front face is 0.44 across and the rim
	# only 0.13 — so the chest is a big flat panel, lit head-on and evenly, with
	# a darker curved border round it. Photographed at four metres
	# (`./faces.sh`) every character in the game was wearing a sandwich board:
	# the arms read as being BEHIND a slab rather than attached to a torso.
	# Deeper and much rounder leaves a small flat front and a wide soft turn,
	# which is a chest.
	# SHORTER BY SIX CENTIMETRES, AND THE HEAD IS UP EIGHT, BECAUSE THERE WAS NO
	# NECK. The chin sat at 1.285 and the collar's top edge at 1.38, so the head
	# was ten centimetres INSIDE the shoulders — photographed from three metres
	# the jaw rested on the collar and the whole cast read as a rack of skittles.
	# It is the single loudest "assembled from primitives" tell left in the
	# frame, louder than the hands and louder than the flat gown, because a neck
	# is the one piece of a person the eye checks without being asked.
	# The trunk keeps its hip line (world 0.64) and loses the six centimetres off
	# the top; the head goes up to put the chin at 1.37, which leaves five
	# centimetres of neck under it. The crown ends up at 1.80 rather than 1.72,
	# which is a person rather than a short one.
	_torso.add_child(Build.mi(
		Build.taper_mesh(Vector2(0.44 * girth, 0.34 * girth),
			Vector2(0.68 * girth, 0.40 * girth), 0.68, 0.17),
		Build.cloth_mat(outfit, LINE), Vector3(0, 0.03, 0)))
	# A collar, deliberately proud of the shoulders so it DOES take a line of
	# its own — one band of contrast at the top of the body, which is what the
	# eye lands on first.
	_torso.add_child(Build.mi(
		Build.taper_mesh(Vector2(0.42 * girth, 0.34 * girth),
			Vector2(0.34 * girth, 0.28 * girth), 0.09, 0.035),
		Build.cloth_mat(outfit.lightened(0.30), LINE),
		Vector3(0, 0.325, 0.005)))
	# ...and a neck inside it, so the head is attached to something instead of
	# hovering over a collar. No line: it is never the silhouette.
	# ...and a neck inside it that is now LONG ENOUGH TO SHOW. It was 22cm at
	# local 0.46, which put its top at world 1.52 and every centimetre of it
	# behind the collar or inside the skull. No line on it: a neck is never the
	# silhouette, and inking it would draw a collar where there is a throat.
	_torso.add_child(Build.mi(Build.capsule_mesh(0.076, 0.30),
		Build.mat(skin.darkened(0.10), SKIN_ROUGH, 0.0, Color(0, 0, 0), 0.0),
		Vector3(0, 0.42, 0)))

	_head = Node3D.new()
	_head.position = Vector3(0, 1.585, 0)
	_head_y = 1.585
	root.add_child(_head)
	# An egg, not a ball: taller than wide, flattened at the back, the volume
	# carried high, and the jaw taken out of the same solid by squashing rather
	# than bolted on as a second box.
	# `skull` is per-person and non-uniform, so the cast has long faces, round
	# faces and broad ones rather than five sizes of one head. Everything that
	# makes the OUTLINE takes it; the eyes, brows and mouth do not, because
	# interpupillary distance varies far less than a skull does and a face
	# stretched with its own head reads as a smear.
	# KEPT, so a harness can ask the SKULL where its own surface is rather than
	# asking `_face_z`, which would only ever agree with itself. See
	# `smoke_impl._check_nobody_has_their_eyes_inside_their_head`.
	_skull_mi = Build.mi(Build.sphere_mesh(0.215),
		Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, -0.01, 0), Vector3.ZERO,
		Vector3(0.98 * skull.x, 1.14 * skull.y, 0.92 * skull.z))
	_head.add_child(_skull_mi)
	# Ears and a nose. Four centimetres of geometry each, and between them the
	# difference between a face and a balloon with eyes drawn on it. Lined,
	# because both of them break the head's silhouette.
	for ex in [-1.0, 1.0]:
		_head.add_child(Build.mi(Build.sphere_mesh(0.052),
			Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), LINE),
			# The ear has to move OUT with a wider skull or it sinks into it.
			Vector3(ex * 0.198 * skull.x, -0.015, -0.02), Vector3.ZERO,
			Vector3(0.45, 1.05, 0.75)))
	# The nose is the most identifying thing on a face and the cheapest to vary.
	# It also has to move FORWARD on a deeper skull, for the same reason as the
	# ears — the head is an ellipsoid and its front moves when its depth does.
	var nose_z: float = _face_z(0.0, -0.022, -0.006)
	_head.add_child(Build.mi(Build.sphere_mesh(0.035 * nose_size),
		Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, -0.022, nose_z), Vector3.ZERO,
		Vector3(0.80, 0.72, 1.02)))
	# A BRIDGE, so the nose is part of the face rather than stuck to it.
	#
	# A single ball between two eyes reads as a clown nose, and at the closest
	# camera distance in the game — a doctor standing over a bed — that is the
	# thing you look at. What makes a nose a nose is that it RISES out of the
	# brow: one tapered ridge running up between the eyes, narrow at the top and
	# meeting the ball at the bottom. Unlined, because it is never the
	# silhouette from the front and an ink line up the middle of a face reads as
	# a scar.
	_head.add_child(Build.mi(Build.rbox_mesh(Vector3(0.030, 0.078, 0.030), 0.014),
		Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), 0.0),
		Vector3(0, 0.018, _face_z(0.0, 0.018, -0.0233)), Vector3.ZERO,
		Vector3(0.78, 1.0, 0.82)))
	# AND A SOCKET UNDER EACH EYE. The whites are unshaded ovals sitting proud
	# of an ellipsoid, which is why they read as stickers: a real eye sits IN
	# something. A slightly larger, slightly darker skin disc behind each one
	# seats it, and costs one sphere. Darkened rather than tinted, so it works
	# across the whole skin range without anybody going grey round the eyes.
	for ex2 in [-1.0, 1.0]:
		_head.add_child(Build.mi(Build.sphere_mesh(0.050),
			Build.mat(skin.darkened(0.10), SKIN_ROUGH, 0.0, Color(0, 0, 0), 0.0),
			Vector3(ex2 * 0.072, 0.012, _face_z(0.072, 0.012, -0.0156)), Vector3.ZERO,
			Vector3(1.08, 0.90, 0.26)))
	# The mouth is built further down, in three pieces that move. There WAS a
	# static bar here as well — the original single-piece mouth — and adding the
	# animated one below it did not remove it, so every face in the building
	# carried two: the new one at y=-0.062 pulling a grimace, and a dead one
	# 3.8cm under it sitting flat through the whole reaction. Both stand proud
	# of the head ellipsoid at their own heights, so neither hid the other.
	# A chin, so the jaw has a bottom to it. Lined, because it is the profile.
	# `jaw` is a heavy chin or a small one. It reads from further away than the
	# nose because it is the bottom edge of the silhouette.
	_head.add_child(Build.mi(Build.sphere_mesh(0.085),
		Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, -0.150 * skull.y, 0.075 * skull.z), Vector3.ZERO,
		Vector3(1.05 * skull.x * jaw_size, 0.72 * jaw_size, 0.95 * skull.z)))
	# FACIAL HAIR, where the record says so. Built as two solids that follow the
	# jaw the chin already established — a jawline piece and a moustache — both
	# lined, because the whole reason it is here is that it changes the profile
	# of a head seen from across a ward. Authored per person in `Cases`, never
	# rolled from a hash: it is a fact about somebody, not a size.
	if beard:
		_head.add_child(Build.mi(Build.sphere_mesh(0.175),
			Build.mat(hair.darkened(0.05), 0.92, 0.0, Color(0, 0, 0), LINE),
			Vector3(0, -0.105, 0.055), Vector3.ZERO, Vector3(1.03, 0.86, 1.02)))
		_head.add_child(Build.mi(Build.sphere_mesh(0.072),
			Build.mat(hair.darkened(0.05), 0.92, 0.0, Color(0, 0, 0), 0.0),
			Vector3(0, -0.058, _face_z(0.0, -0.058, -0.0222)), Vector3.ZERO,
			Vector3(1.25, 0.42, 0.70)))

	# A cap on the crown, set BACK from the face and narrower than the skull.
	# The first pass made it 0.37 wide on a 0.40 head and centred it, which is
	# a helmet — and a patient lying in a bed is rotated ninety degrees, so the
	# first rendered close-up was a brown block where a face should be with two
	# eyes peering over the top of it. A squashed SPHERE, not a box: a slab
	# reads as hair from straight on only, and from the side it was a dark plank
	# stuck to somebody's cheek.
	# THINNING, from `Appearance`. The crown shrinks toward the back of the
	# skull and flattens; it is never removed, because a head with no hair mesh
	# on it reads as shaved — a decision somebody made — where thinning is just
	# time passing, which is what the age it comes from means.
	var crown: float = lerpf(1.0, 0.80, bald)
	var hair_mat := Build.mat(hair, 0.9, 0.0, Color(0, 0, 0), LINE)
	var hair_flat := Build.mat(hair, 0.9, 0.0, Color(0, 0, 0), 0.0)
	# SET BACK FAR ENOUGH THAT IT IS NOT THE HAIRLINE. At z=-0.030 with a
	# z-scale of 1.0 the crown's front face reaches 0.194 — in FRONT of the eyes
	# at 0.184 — so the crown itself came down over the forehead and the
	# forelock below was decorating a helmet. Pulled back and narrowed in depth,
	# it is hair on the back and top of a head, which is what a crown is; the
	# forelock owns the front edge.
	_head.add_child(Build.mi(Build.sphere_mesh(0.224 * crown),
		hair_mat,
		Vector3(0, 0.086 + 0.012 * bald, -0.052 - 0.030 * bald), Vector3.ZERO,
		Vector3(0.99 * skull.x, lerpf(0.70, 0.48, bald) * skull.y, 0.92 * skull.z)))
	# ...and a forelock, so there is a hairLINE. Hair with no edge on the
	# forehead reads as a swimming cap — but a straight BAR across the forehead
	# reads as a headband, which is what the first attempt at this was. A second
	# squashed sphere set forward and low follows the skull instead.
	# ...and the hairline goes back with it, which is the half of this that
	# actually reads: a smaller cap alone looks like a smaller haircut.
	if bald < 0.85:
		# AND HIGH ENOUGH TO LEAVE A FOREHEAD. Its bottom edge was at y=-0.014
		# — below the brows at 0.052 and below the eyes at 0.008 — so the hair
		# ran down to the eyebrows on every character in the game and the whole
		# cast read as wearing swimming caps. It sits at 0.087 now, which is
		# about three centimetres of forehead on a head half a metre tall, and
		# it is the single change that stopped these looking like helmets.
		_head.add_child(Build.mi(Build.sphere_mesh(0.170 * lerpf(1.0, 0.72, bald)),
			hair_flat,
			Vector3(0, 0.165 + 0.020 * bald, (0.048 - 0.075 * bald) * skull.z),
			Vector3.ZERO,
			Vector3(1.02 * skull.x, lerpf(0.46, 0.30, bald) * skull.y, 0.88 * skull.z)))
	_hair_style(hair_mat)
	# THE EYE IS A MARK, NOT A BALL.
	#
	# This was a big white sclera with a dark disc floating in it, and photo-
	# graphed close up (`./faces.sh`) it is the single thing that made this cast
	# read as default-stylised rather than as a look somebody chose: two white
	# ovals with an ink line round each, sitting ON the face rather than in it.
	# Every note above it was a real fix — the whites came down a third for
	# "swimming goggles", the pupil was flattened for "walleyed", the pupil was
	# grown for "permanently surprised" — and each one was fixing a symptom of
	# the sclera being there at all.
	#
	# A solid dark almond with one catchlight is what a stylised eye is: it is
	# the shape you draw when you draw an eye, and it is what every flat-shaded
	# game with an ink line does. Nothing is lost by dropping the white, because
	# NOTHING IN THIS GAME EVER MOVED A PUPIL — gaze is carried entirely by
	# `look_toward` turning the head, and an almond on the front of a head that
	# has turned toward you is exactly as legible as an oval was. That legibility
	# is load-bearing (the suspicion system is built on "is this person looking
	# at me"), which is why it is spelled out here rather than left to be
	# rediscovered.
	for sx in [-1.0, 1.0]:
		# SMALLER, WARMER AND MATTE, WHICH IS WHAT STOPS IT BEING A DEMON.
		#
		# Reported from outside as "a lot of the eyes look like they\'re demons",
		# and that is the fourth separate note about this one piece. The first
		# three — goggles, walleyed, permanently surprised — were all symptoms of
		# the white sclera, and dropping the sclera fixed those and not this one,
		# because what makes a dark eye read as a hole is not the missing white.
		# It is three things that are all measurable: the almond was 6.5cm on a
		# 42cm head, which is a SIXTH of the width of the face per eye; it was
		# very nearly pure black, which no part of a person is; and it was shiny
		# — roughness 0.35, so it carried a specular sheen and read as glass.
		#
		# AN UPPER LID WAS TRIED FIRST AND WAS WORSE, which is the useful half.
		# A flattened sphere in the person\'s own skin, cutting the top quarter
		# off the almond, is the textbook answer and it produced a heavy pale
		# hood over a low dark crescent: every character looked drugged. Three
		# overlapping ellipsoids around one eye — socket, lid, almond — is a
		# lumpy mess at any weight, and the second attempt (lid raised, thinner,
		# barely tinted) was still a pale blob catching its own light. The style
		# this game is in does not want lid geometry; it wants a smaller, warmer,
		# matte mark.
		var eye := Build.mi(Build.sphere_mesh(0.030), Build.mat(EYE_INK, 0.85, 0.0, Color(0, 0, 0), 0.0),
			Vector3(sx * 0.068, 0.007, _face_z(0.068, 0.007, -0.0025)), Vector3.ZERO,
			Vector3(0.92, 0.50, 0.30))
		# A CATCHLIGHT, AND IT IS NOT MIRRORED. One small bright dot is what
		# stops a dark eye reading as a hole, and it is the only thing keeping
		# an eye legible on the darkest skin in `Appearance.SKIN` — where a dark
		# almond against a dark face has very little else to work with.
		#
		# Both eyes take it on the SAME side rather than mirrored, because a
		# catchlight is a reflection of a light and there is one sun. Mirroring
		# it reads as decoration; not mirroring it reads as lit, and costs
		# exactly the same.
		var glint := Build.mi(Build.sphere_mesh(0.0058),
			Build.unshaded(Color(0.93, 0.95, 0.97)),
			Vector3(sx * 0.068 - 0.009, 0.0122, _face_z(sx * 0.068 - 0.009, 0.0122, 0.0062)),
			Vector3.ZERO,
			Vector3(1.0, 1.0, 0.30))
		_head.add_child(eye)
		_head.add_child(glint)
		_eyes_open.append(eye)
		_eyes_open.append(glint)
		# A brow above each eye. Two small dark bars are the whole of this
		# model's expression budget and they are worth every triangle: without
		# them the face is permanently, blankly surprised.
		#
		# DARKENED, NOT LIGHTENED, and floored. It was `hair.lightened(0.10)`,
		# which on the white hair of a seventy-three-year-old is a white bar on
		# a pale forehead — invisible, on the one part of the model that carries
		# every expression in the game. A brow has to be darker than the face it
		# is on whatever colour the hair is, so it is mixed toward the ink.
		var brow_col: Color = hair.darkened(0.25).lerp(Color(0.16, 0.13, 0.12), 0.55)
		var brow := Build.mi(Build.rbox_mesh(Vector3(0.066, 0.014, 0.020), 0.007),
			Build.mat(brow_col, 0.9, 0.0, Color(0, 0, 0), 0.0),
			Vector3(sx * 0.072, BROW_REST_Y, _face_z(0.072, BROW_REST_Y, 0.0109)))
		# Angled out and down a little at rest, which is a face at ease rather
		# than a face at attention. `set_mood` rotates FROM here — see
		# BROW_REST_Z, which is why that is a constant and not a literal: the
		# first version set 0.09 at build time and `set_mood` then wrote
		# `sx * _mood * 0.42` over it, so the moment anybody's mood was set to
		# neutral their brows snapped flat and stayed there. Same for the
		# height: build put it at 0.052 and set_mood at 0.068.
		brow.rotation.z = sx * BROW_REST_Z
		brow.position.y = BROW_REST_Y
		_head.add_child(brow)
		_brows.append(brow)
		# A CLOSED EYE IS A LINE. It was a skin-coloured bar, which on a light
		# face is nothing at all and on a dark one is a smudge — so a sleeping
		# patient read as a patient with no eyes. The lash line is the same
		# colour as the eye and a third of its height, which is what a shut eye
		# looks like from any distance.
		# ...AND IT IS THE WIDTH OF THE OPEN EYE, NOT WIDER. The bar was 6.8cm
		# against an almond that is now 5.5, so a sleeping patient had a wider
		# line across the face than an awake one has an eye — which reads as a
		# stitch rather than as a shut eye.
		var lid := Build.mi(Build.rbox_mesh(Vector3(0.056, 0.010, 0.018), 0.0045),
			Build.mat(EYE_INK, 0.85, 0.0, Color(0, 0, 0), 0.0),
			Vector3(sx * 0.068, 0.009, _face_z(0.068, 0.009, 0.0036)))
		lid.visible = false
		_head.add_child(lid)
		_eyes_shut.append(lid)

	# A mouth in three pieces: a bar, and a corner block each side that rides up
	# for a smile and down for a grimace. One rotated bar cannot do both, and a
	# face that cannot do both has no opinion about what you just did to it.
	# A LOWER LIP FIRST, so the dark bar has something to be the edge OF.
	#
	# The mouth was one flat bar and two flat corner blocks, all unshaded, and
	# on a head that now has a nose with a bridge and eyes in sockets it was the
	# last thing on the face reading as a sticker: a dark red letterbox with
	# nothing above or below it. A mouth is a LINE between two lips, and the
	# lower one is the half that catches light — so it is a small warm piece
	# sitting just under the bar, in the person's own skin pushed toward it
	# rather than a fixed pink, which is the only way this works across a range
	# from 0.29 to 0.96.
	#
	# BEHIND the bar in z and BELOW it in y, both by a couple of millimetres, so
	# it never fights the bar for a pixel and never pokes through when the bar
	# scales open for a grimace.
	# ...AND ONLY A SLIVER OF IT. At 0.017 tall and 0.054 wide it was very
	# nearly the same rectangle as the bar, sitting directly under it — so the
	# two together were a three-centimetre two-tone stripe with parallel edges,
	# which is a letterbox with a highlight rather than a mouth. A closed mouth
	# is a LINE, and the lower lip's job is to be the thing the line is the top
	# edge of: narrower than the bar, so the bar's ends overhang it and the
	# corners read as lips meeting, and short enough that most of it is hidden
	# behind the bar.
	_head.add_child(Build.mi(Build.rbox_mesh(Vector3(0.038, 0.0095, 0.020), 0.004),
		Build.mat(_lip(skin), SKIN_ROUGH, 0.0, Color(0, 0, 0), 0.0),
		Vector3(0, -0.0660, _face_z(0.0, -0.0660, 0.0021))))
	# NARROWER THAN THE EYES ARE APART. The bar was 0.086 half-width against an
	# eye span of 0.105, so the mouth was 82% as wide as the whole face — which
	# on a stylised head is a letterbox, and it is what kept these reading as
	# blocky once the eyes had stopped. A mouth is about as wide as the gap
	# between the pupils, and no wider.
	# THINNER AND LESS RED. 0.013 of a head that is 0.43 across is a three
	# millimetre band at life size and it photographed as a slot; and
	# (0.30, 0.15, 0.16) is a saturated maroon, which on a face lit flat and
	# unshaded is the most colourful thing above the collar. A closed mouth is
	# darker and quieter than that — it is a shadow between two lips, not a
	# painted line.
	_mouth = Build.mi(Build.rbox_mesh(Vector3(0.062, 0.0095, 0.022), 0.0045),
		Build.mat(MOUTH_INK, 0.75, 0.0, Color(0, 0, 0), 0.0),
		Vector3(0, -0.061, _face_z(0.0, -0.061, 0.0044)))
	_head.add_child(_mouth)
	for sx in [-1.0, 1.0]:
		# HALF THE HEIGHT OF THE BAR, so the line TAPERS to the corners. With the
		# corners the same height as the middle the mouth is a band of constant
		# width — a letterbox — however thin you make it. A closed mouth is
		# thickest between the lips and vanishes where they meet, and that is
		# the difference between a line and a slot: two blocks, four
		# millimetres, and the shape stops being rectangular.
		var corner := Build.mi(Build.rbox_mesh(Vector3(0.020, 0.005, 0.022), 0.0025),
			Build.mat(MOUTH_INK, 0.75, 0.0, Color(0, 0, 0), 0.0),
			Vector3(sx * 0.038, -0.0605, _face_z(0.038, -0.0605, 0.0057)))
		_head.add_child(corner)
		_mouth_corners.append(corner)

	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		# Shoulders move out with the trunk. Left at a fixed 0.395 the arms of a
		# broad person hang inside their own chest.
		arm.position = Vector3(sx * 0.382 * girth, 1.18, 0)
		# ...AND THEY HANG, they do not stand to attention. Six characters with
		# both arms at exactly vertical is six mannequins; three degrees out and
		# four forward is what an arm resting at somebody's side actually does,
		# and it costs nothing. `set_in_bed` restores to the same rest rather
		# than to zero.
		arm.rotation = Vector3(ARM_REST_X, 0.0, sx * ARM_REST_Z)
		root.add_child(arm)
		# One sleeve, one cuff, one mitten. The hand is WIDER than the wrist:
		# limbs that taper to nothing read as tentacles, and what sells a hand
		# is being the widest thing at the end of the arm.
		# Limbs take HALF the trunk's variation. A broad person is not broad in
		# proportion everywhere, and arms at full girth read as inflated.
		var limb: float = lerpf(1.0, girth, 0.5)
		# A SHOULDER, so the arm is attached to the body rather than standing
		# beside it. The sleeve is a taper with a rounded end, and a rounded end
		# next to a rounded trunk leaves a dark vertical seam between two
		# separate solids — from three metres the arms read as sausages laid
		# against a slab, which is most of what made the cast look assembled.
		# One sphere in the gown's own colour, at the joint, closes it.
		# SMALLER THAN THE SLEEVE IT JOINS, AND SUNK INTO IT. The first attempt
		# at this capped the shoulder and read as an epaulette; the second was
		# 0.105 — a twenty-one centimetre ball on a twenty centimetre sleeve, so
		# it was still the widest thing on the body and photographed as shoulder
		# pads on every character in the ward. A joint is not wider than the
		# limb it joins: 17.6cm, tucked five centimetres in and five down, where
		# the seam actually is.
		arm.add_child(Build.mi(Build.sphere_mesh(0.088 * limb),
			Build.cloth_mat(outfit, LINE), Vector3(sx * -0.052, -0.050, 0)))
		arm.add_child(Build.mi(Build.taper_mesh(Vector2(0.135 * limb, 0.135 * limb),
			Vector2(0.190 * limb, 0.190 * limb), 0.56, 0.070),
			Build.cloth_mat(outfit, LINE), Vector3(0, -0.26, 0)))
		# A WRIST IS THINNER THAN A SLEEVE, and this one was not: a capsule
		# 16.4cm across poking out of a sleeve that ends at 15 made the whole
		# arm one tube from shoulder to knuckles, and the comment two lines down
		# — "the hand is WIDER than the wrist" — was describing a hand 1.4cm
		# narrower than the arm it is on. Eleven centimetres is a wrist, and it
		# is what makes the hand read as a hand rather than as the end of a pipe.
		arm.add_child(Build.mi(Build.capsule_mesh(0.056, 0.15),
			Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), LINE), Vector3(0, -0.50, 0)))
		arm.add_child(Build.mi(Build.rbox_mesh(Vector3(0.15, 0.17, 0.10), 0.048),
			Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), LINE), Vector3(0, -0.60, 0.01)))
		# A THUMB. The hand was one rounded box, which is a mitten, and a mitten
		# is the thing on the end of the arm of every person in the building —
		# including the one holding a chart eighteen inches from the camera. It
		# is four centimetres of geometry and it is the difference between a
		# hand and a paddle: the eye reads the notch between thumb and fingers
		# long before it counts anything.
		var thumb := Build.mi(Build.rbox_mesh(Vector3(0.055, 0.095, 0.06), 0.026),
			Build.mat(skin, SKIN_ROUGH, 0.0, Color(0, 0, 0), LINE),
			Vector3(-sx * 0.072, -0.585, 0.045))
		thumb.rotation = Vector3(0.30, 0.0, sx * 0.42)
		arm.add_child(thumb)
		_arms.append(arm)

		# Thigh, then a KNEE, then shin and shoe.
		#
		# One rigid leg can only ever stick straight out, which is what the first
		# sitting pose looked like: a patient in the waiting row with both legs
		# horizontal and their feet in the air. A knee costs one more node per
		# leg and buys a real sit — thigh forward, shin down, foot on the floor —
		# as well as a bend on the back-swing of the walk.
		# CLOSER TOGETHER, BUT STILL TWO OF THEM. At sx*0.145 with a thigh 0.20
		# across, the inner faces sit 45mm off centre each — a nine-centimetre
		# gap of daylight between the thighs of every standing character, which
		# at four metres reads as two poles rather than as legs. It is invisible
		# on somebody lying in a bed, which is why it survived until there was a
		# harness that photographs people standing up.
		#
		# 0.118 was too far the other way and closed the gap completely: hip to
		# ankle became one column with a seam down it, which is a different
		# wrong answer. This leaves about two centimetres.
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.129 * limb, 0.68, 0)
		root.add_child(leg)
		leg.add_child(Build.mi(Build.taper_mesh(Vector2(0.20 * limb, 0.20 * limb),
			Vector2(0.27 * limb, 0.25 * limb), 0.34, 0.085),
			Build.mat(outfit.darkened(0.34), 0.85, 0.0, Color(0, 0, 0), LINE),
			Vector3(0, -0.17, 0)))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.34, 0)
		leg.add_child(knee)
		knee.add_child(Build.mi(Build.taper_mesh(Vector2(0.17, 0.17), Vector2(0.20, 0.20), 0.32, 0.075),
			Build.mat(outfit.darkened(0.42), 0.85, 0.0, Color(0, 0, 0), LINE),
			Vector3(0, -0.16, 0)))
		knee.add_child(Build.mi(Build.rbox_mesh(Vector3(0.19, 0.115, 0.35), 0.055),
			Build.mat(Color(0.19, 0.21, 0.27), 0.6, 0.0, Color(0, 0, 0), LINE),
			Vector3(0, -0.29, 0.075)))
		_knees.append(knee)
		_legs.append(leg)

	# SMALLER, AND IT FADES OUT WHEN YOU ARE ON TOP OF SOMEBODY.
	#
	# A 0.095 label is a metre and a half of text, and the player stands about
	# a metre and a half from a bed — so walking up to a patient put their name
	# across the entire screen in grey capitals, over the ceiling, over the
	# wall, over their face. The name is for picking a bed out from the door;
	# once you are at the bedside the interaction prompt already says who this
	# is, twice.
	_nametag = Build.label3d(display, 0.062, Color(0.99, 0.99, 0.96))
	_nametag.position = Vector3(0, 1.98 * height_scale, 0)
	# Godot fades a GeometryInstance3D by distance for us. `begin` is the NEAR
	# limit — below it the label is not drawn at all — so this is "appears once
	# you have stepped back from the bed, gone again from the far end of the
	# building". The margins make both ends a fade rather than a pop.
	_nametag.visibility_range_begin = 2.4
	_nametag.visibility_range_begin_margin = 0.9
	_nametag.visibility_range_end = 15.0
	_nametag.visibility_range_end_margin = 3.0
	_nametag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_nametag)

	_speech = Build.label3d("", 0.075, Color(1, 1, 1))
	_speech.position = Vector3(0, 2.20 * height_scale, 0)
	_speech.width = 900
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD
	_speech.visible = false
	add_child(_speech)

## THE WHOLE LOOK, from `Appearance.of()`. Must be called before the body is
## built — everything here is baked into meshes in `_build_body`.
func set_look(look: Dictionary) -> void:
	_look_given = true
	skin = look.get("skin", skin)
	outfit = look.get("outfit", outfit)
	hair = look.get("hair", hair)
	height_scale = float(look.get("height", height_scale))
	girth = float(look.get("girth", girth))
	bald = float(look.get("bald", bald))
	beard = bool(look.get("beard", beard))
	skull = look.get("skull", skull)
	nose_size = float(look.get("nose", nose_size))
	jaw_size = float(look.get("jaw", jaw_size))
	hair_style = int(look.get("hair_style", hair_style))

# ------------------------------------------------------------------ movement
func goto(target: Vector3, run := false) -> void:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null or h.nav == null:
		return
	_path = h.nav.find_path(global_position, target)
	_path_i = 0
	_speed = RUN_SPEED if run else WALK_SPEED

## Walk a route that nothing has pathfound.
##
## `goto` asks the hospital's navigation grid, which does not exist anywhere
## except the hospital. Anybody walking home down a street is following a line
## somebody drew, and this is how they do it.
func follow(points: PackedVector3Array, run := false, speed := -1.0) -> void:
	_path = points
	_path_i = 0
	# An explicit pace, because follow() is called once PER LEG of a route and
	# was resetting the walk to WALK_SPEED at every corner — so a caller that
	# set a speed after handing over the route lost it at the first turn, and
	# six differently paced evenings all walked at exactly the same speed.
	_speed = speed if speed > 0.0 else (RUN_SPEED if run else WALK_SPEED)

func stop_moving() -> void:
	_path = PackedVector3Array()
	velocity.x = 0.0
	velocity.z = 0.0

func is_moving() -> bool:
	return _path_i < _path.size()

func distance_to(p: Vector3) -> float:
	return global_position.distance_to(p)

## Somebody has walked into you. Get out of their way.
##
## This is a traversal fix wearing a personality. Two CharacterBody3Ds cannot
## displace each other, so before this a member of staff standing anywhere in
## the corridor was a wall the player could only wait out; the play harness lost
## eleven seconds to one nurse and twenty-one to another. Sidestepping — rather
## than backing off — is what actually clears a corridor: a character retreating
## along the axis you are travelling stays in front of you the whole way.
const YIELD_TIME := 1.0
const YIELD_SPEED := 2.1

const YIELD_LINES := [
	"Sorry — sorry.", "Oop.", "Excuse me, doctor.", "Mind your—",
	"After you.", "Yep. Yep. Going.", "Sorry, doctor.",
]

func step_aside(from: Vector3) -> void:
	if _yield_time > 0.0 or not can_step_aside():
		return
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.0025:
		away = -global_transform.basis.z
	away = away.normalized()
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	# Step toward whichever side is actually floor. A ward door is 1.4m wide and
	# picking the wall half the time turns a sidestep into a second wedge.
	var h = get_tree().get_first_node_in_group("hospital")
	if h != null and h.nav != null:
		var right_ok: bool = h.nav.is_walkable(global_position + side * 1.0)
		var left_ok: bool = h.nav.is_walkable(global_position - side * 1.0)
		if left_ok and not right_ok:
			side = -side
		elif not left_ok and not right_ok:
			# Boxed in sideways: give ground along their line instead, which at
			# least stops being a wall even if it is not elegant.
			side = -away
	_yield_dir = side
	_yield_time = YIELD_TIME
	if _react_cooldown <= 0.0:
		_react_cooldown = 5.0
		say(String(RNG.pick("step_aside", YIELD_LINES)), 1.6)

## Overridden by anybody who should stay exactly where they are — a patient in
## bed does not politely roll out of it because you brushed past.
func can_step_aside() -> bool:
	return true

## Stop, take out a clipboard, and write something down.
##
## The game's read on what somebody thinks of you was a colour on their name
## tag: a meter, wearing a diegetic hat. This is the fact underneath it, and it
## is a fact you can watch happen — she was standing there, she saw it, she
## stopped, and she has written it down. Nothing is announced and no number
## moves on screen; the player draws the conclusion, which is the only version
## of this that is ever tense.
##
## It is also honest. It fires when a mind genuinely records something it saw
## with its own eyes, so what the animation says is exactly what the simulation
## did.
const NOTE_TIME := 2.4

## Open or shut. Used by sleep, and available to anything else that wants a
## face to stop looking at the player.
## Blinking.
##
## The eyes are two unshaded white ovals that never once closed unless the
## character was asleep, which at conversation distance is the single most
## unsettling thing about them. A blink every few seconds costs one boolean.
##
## Deliberately skipped while asleep: set_asleep already holds the lids shut,
## and a sleeping patient blinking is a bug that looks like a twitch.
func _tick_blink(delta: float) -> void:
	if _eyes_shut.is_empty() or _lids_held:
		return
	if _blink_close > 0.0:
		_blink_close -= delta
		if _blink_close <= 0.0:
			set_eyes_open(true)
		return
	_blink_t -= delta
	if _blink_t > 0.0:
		return
	# Uneven on purpose. A metronome blink is worse than none.
	_blink_t = randf_range(2.4, 6.5)
	_blink_close = 0.11
	set_eyes_open(false)

## Held shut by something other than a blink — sleep, mostly.
var _lids_held := false

func set_eyes_open(open: bool) -> void:
	for m in _eyes_open:
		m.visible = open
	for m in _eyes_shut:
		m.visible = not open

## Overridden by anybody who has something more urgent on. Nobody stops to
## minute something while they are running toward a bang.
func can_stop_to_write() -> bool:
	return true

func make_a_note() -> void:
	if _note_time > 0.0 or _arms.is_empty() or not can_stop_to_write():
		return
	_note_time = NOTE_TIME
	if _note_pad == null:
		_note_pad = Node3D.new()
		_arms[0].add_child(_note_pad)
		_note_pad.position = Vector3(0, -0.52, 0.10)
		_note_pad.add_child(Build.mi(Build.box_mesh(Vector3(0.22, 0.02, 0.28)),
			Build.mat(Build.PAPER)))
		_note_pad.add_child(Build.mi(Build.box_mesh(Vector3(0.24, 0.015, 0.04)),
			Build.mat(Color(0.30, 0.33, 0.38)), Vector3(0, 0.015, -0.13)))
	_note_pad.visible = true
	AudioMgr.play_at_var("tick", global_position, -21.0, 0.25)

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
	if _note_time > 0.0:
		_note_time -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_intended_speed = 0.0
		if _note_time <= 0.0 and _note_pad != null:
			_note_pad.visible = false
	elif _yield_time > 0.0:
		_yield_time -= delta
		velocity.x = _yield_dir.x * YIELD_SPEED
		velocity.z = _yield_dir.z * YIELD_SPEED
		_intended_speed = YIELD_SPEED
	else:
		_follow_path(delta)
	_face(delta)
	_open_door_ahead()
	if pinned:
		velocity = Vector3.ZERO
		_intended_speed = 0.0
		_animate(delta)
		_tick_speech(delta)
		return

	# Somebody standing still does not need the solver.
	#
	# move_and_slide() was measured at roughly four fifths of all the time this
	# game spends on characters, and most of the building is stationary most of
	# the time: nurses at the station, patients in bed, visitors sitting. Held
	# to a strict test — already resting on the floor, not being pushed, and
	# asking to go nowhere — because a body that skips the solver also skips
	# gravity, and a patient hovering where their bed used to be is a far worse
	# bug than a slow frame. _push_obstacles is skipped with it: it reads the
	# slide collisions move_and_slide produces, and somebody standing still is
	# not shoving anything anyway.
	var resting: bool = is_on_floor() and _path_i >= _path.size() \
		and absf(velocity.y) < 0.01 \
		and Vector2(velocity.x, velocity.z).length_squared() < 0.0004
	if resting:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		move_and_slide()
		_push_obstacles()
	_check_stuck(delta)
	_animate(delta)
	_footsteps(delta)
	_tick_speech(delta)

func _follow_path(delta: float) -> void:
	if _path_i >= _path.size():
		velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-10.0 * delta))
		velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-10.0 * delta))
		_intended_speed = 0.0
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
	_intended_speed = _speed

## Which way a character is pointing.
##
## Two bugs lived here, and together they produced "when people are walking
## backwards I can still see their face".
##
## The sign was wrong. This model's eyes are on its local +Z, so the yaw that
## faces a direction d is atan2(d.x, d.z) — `atan2(-d.x, -d.z)` is a hundred and
## eighty degrees out, and every character in the building walked backwards down
## the corridor looking straight at you. (The doors had the identical bug; it is
## a very easy sign to get wrong when +Z is forward.)
##
## And a look target outranked movement, so anybody who noticed you turned to
## face you and then MOONWALKED wherever they were going. The body follows
## where it is walking; the head, separately, follows what it is looking at.
## That is how people work and it is the whole tell the suspicion system needs:
## a nurse walking past while watching you should be walking past, watching you.
func _face(delta: float) -> void:
	var moving := Vector3(velocity.x, 0.0, velocity.z)
	var face_dir := Vector3.ZERO
	if moving.length_squared() > 0.04:
		face_dir = moving
	elif _has_look:
		# Standing still: turn to whatever has your attention.
		face_dir = _look_at - global_position
	face_dir.y = 0.0
	if face_dir.length_squared() < 0.001:
		return
	var want := atan2(face_dir.x, face_dir.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_SPEED * delta))

## Footsteps.
##
## The player made them; nobody else in the building did. In a game whose entire
## tension is "is somebody about to walk in", every member of staff on the floor
## moved in complete silence — the only way to know a nurse was behind you was
## to already be looking at her. This is the cheapest tension in the whole
## project and it was missing.
##
## Positional, so distance and direction do the work: a step you can barely hear
## is somebody at the far end of the corridor, and a step you can hear clearly is
## somebody in the doorway. Slightly quieter and slower than the player's own,
## because the player's are also feedback for their own movement and these are
## information about somebody else.
const STEP_STRIDE := 2.3

var _step_accum := 0.0

func _footsteps(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or planar < 0.35:
		_step_accum = 0.0
		return
	_step_accum += delta * planar
	if _step_accum < STEP_STRIDE:
		return
	_step_accum = 0.0
	# Only if there is anybody to hear it. Eight members of staff walking a
	# sixty-two-metre floor would otherwise churn the whole twenty-four-voice
	# 3D pool with steps nobody is in earshot of, and steal the voices from the
	# things that matter — a door, a gasp, a machine.
	var listener = get_tree().get_first_node_in_group("player")
	if listener == null or global_position.distance_squared_to(listener.global_position) > 400.0:
		return
	AudioMgr.play_at_var("step", global_position, -24.0, 0.22)

func _animate(delta: float) -> void:
	# Writing overrides the walk cycle: one arm holds the pad flat, the other
	# scribbles. Cheap, and unmistakable from across a ward.
	if _note_time > 0.0 and _arms.size() >= 2:
		_walk_phase += delta * 14.0
		_arms[0].rotation.x = -1.15
		_arms[1].rotation.x = -1.0 + sin(_walk_phase) * 0.16
		for leg in _legs:
			leg.rotation.x = 0.0
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * (2.0 + planar * 3.4)
	_idle_phase += delta

	# Standing still used to mean standing PERFECTLY still. Every character in
	# the building was a statue between waypoints, which is the cheapest tell
	# there is that nothing behind them is alive — and most of the time, in a
	# game about watching people, most of them are standing still.
	#
	# Three signals, all tiny, none of which needs a rig: a breath, a slow shift
	# of weight from one foot to the other, and a blink. The first two fade out
	# as the character starts moving, because a walk already carries them.

	# A fight used to claim the arms here, driven from its own rules clock and
	# fighting this pass for them every frame. The brawl went with the redesign;
	# the walk cycle owns every limb again.
	if _seated:
		# Seated: breathe and blink, but do not walk. Without this the legs
		# swing back to vertical on the first frame of the idle cycle and the
		# character stands up through the chair.
		#
		# The breath is offset from the SAME 0.95 base as the standing branch.
		# It used to sit on -0.26, a hip drop copied from set_seated() back when
		# that offset lived on the torso; it lives on the Body node now (and is
		# -0.30), so writing it here as well moved the trunk 1.21m down while
		# the head, arms and legs — siblings of _torso, not children — stayed
		# where they were. That is a floating head with detached limbs, and now
		# that the ward beds are chairs it was every patient in the game rather
		# than only the visitors in the waiting row.
		if _torso:
			_torso.position.y = 0.95 + sin(_idle_phase * 1.35 + _idle_offset) * 0.008
		_tick_blink(delta)
		_tick_look(delta)
		return
	var still: float = clampf(1.0 - planar * 1.6, 0.0, 1.0)
	var breath: float = sin(_idle_phase * 1.35 + _idle_offset) * 0.010 * still
	var sway: float = sin(_idle_phase * 0.55 + _idle_offset * 1.7) * 0.045 * still

	var swing := sin(_walk_phase) * clampf(planar * 0.35, 0.02, 0.6)
	if _legs.size() >= 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
		# The trailing leg bends. A pair of straight legs scissoring is a
		# mannequin on a turntable; one knee folding is a walk.
		if _knees.size() >= 2:
			_knees[0].rotation.x = maxf(0.0, -swing) * 1.5
			_knees[1].rotation.x = maxf(0.0, swing) * 1.5
	if _arms.size() >= 2:
		# Flailing when startled is the entire visual payoff of throwing a tray.
		var flail := _startle * sin(_walk_phase * 9.0) * 1.4
		# Arms hang slightly away from the body and drift with the breath, so
		# the silhouette is never two perfectly vertical lines.
		_arms[0].rotation.x = -swing * 0.8 + flail + breath * 1.4
		_arms[1].rotation.x = swing * 0.8 - flail + breath * 1.4
		_arms[0].rotation.z = 0.06 + sway * 0.5
		_arms[1].rotation.z = -0.06 + sway * 0.5
	if _torso:
		_torso.position.y = 0.95 + absf(sin(_walk_phase)) * clampf(planar * 0.02, 0.0, 0.03) \
			+ breath
		_torso.rotation.z = sway * 0.35
		# The chest actually expands. Two hundredths of a metre, and it is the
		# difference between a person waiting and a prop of a person.
		_torso.scale = Vector3(1.0 + breath * 0.8, 1.0, 1.0 + breath * 1.2)

	_tick_blink(delta)
	_tick_look(delta)

## Where they are looking. ITS OWN PASS, because every early return in _animate
## used to skip it.
##
## A seated character never ran it, so a patient in a chair could not turn their
## head towards you at all — which is why talking to somebody had to stand them
## up out of the chair to work, in a game whose wards are chairs. Every branch
## runs it now, whatever else the body is doing.
func _tick_look(delta: float) -> void:
	if _head and _has_look:
		var to := _look_at - _head.global_position
		var local := to.normalized() * global_transform.basis
		_head.rotation.x = clampf(asin(clampf(local.y, -1.0, 1.0)) * 0.6, -0.5, 0.5)
		# ...and turn the head on its own axis, clamped to something a neck can
		# do. This is what lets somebody walk one way while watching another —
		# which is the single most important thing a witness can be seen doing.
		var yaw := atan2(local.x, local.z)
		_head.rotation.y = lerp_angle(_head.rotation.y,
			clampf(yaw, -1.15, 1.15), 1.0 - exp(-7.0 * delta))
	elif _head:
		_head.rotation.y = lerp_angle(_head.rotation.y, 0.0, 1.0 - exp(-4.0 * delta))

func _check_stuck(delta: float) -> void:
	if _intended_speed < 0.15:
		_stuck_time = 0.0
		_last_progress_pos = global_position
		return
	if global_position.distance_to(_last_progress_pos) > 0.25:
		_stuck_time = 0.0
		_last_progress_pos = global_position
		return
	_stuck_time += delta
	if _stuck_time < 1.5:
		return
	_stuck_time = 0.0
	_unstick()

## Step aside and re-plan. Sidestepping first matters: re-pathing from inside
## whatever we are wedged against just produces the same route.
func _unstick() -> void:
	var side := global_transform.basis.x * (1.0 if randf() < 0.5 else -1.0)
	global_position += side * 0.35 + Vector3(0, 0.05, 0)
	_last_progress_pos = global_position
	if _path_i < _path.size():
		var target: Vector3 = _path[_path.size() - 1]
		goto(target, _speed > WALK_SPEED)

## Look a metre ahead and open any door in the way, BEFORE trying to walk into it.
##
## Reacting to slide collisions is not enough: a body pressed against a door has
## its velocity zeroed by move_and_slide, so it reports no motion, no collision,
## and no reason to push — it just stands there indefinitely. Probing ahead
## breaks that deadlock, and it is also simply what a person does with a door.
func _open_door_ahead() -> void:
	if _intended_speed < 0.15 or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var forward := -global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + forward * 1.15)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var door := _door_of(hit.get("collider"))
	if door == null:
		return
	# Driven every frame while you are still walking at it — see the same call
	# in Player._open_door_ahead for why stopping at "is_open" leaves the leaf
	# oscillating in the gap.
	door.open_for(global_position)

## Shove rigid bodies out of the way — doors especially.
##
## A CharacterBody3D does not move RigidBody3Ds it collides with, so before this
## existed a nurse who walked into a closed door simply stopped there, forever.
## Every ward was unreachable to staff and nobody ever noticed, because nothing
## ran the AI with real frames.
func _push_obstacles() -> void:
	var speed := maxf(Vector2(velocity.x, velocity.z).length(), _intended_speed)
	if speed < 0.15:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		# A door is opened, not shoved: see SwingDoor.open_for. Checked before
		# the RigidBody cast because the leaf is an AnimatableBody3D.
		var door := _door_of(c.get_collider())
		if door != null:
			door.open_for(global_position)
			continue
		var rb := c.get_collider() as RigidBody3D
		if rb == null:
			continue
		# Heavier things need more of a shove and give way more slowly, which is
		# why a cart left in a doorway genuinely slows people down.
		var push: float = clampf(28.0 / maxf(rb.mass, 1.0), 0.25, 3.0)
		rb.apply_central_impulse(-c.get_normal() * push * speed * 0.35)

func _door_of(body: Object) -> SwingDoor:
	var n := body as Node
	while n != null:
		if n is SwingDoor:
			return n
		n = n.get_parent()
	return null

# ------------------------------------------------------------------ speech
const SUBTITLE_RANGE := 14.0

## Barks hold longer than they did.
##
## 3.2 seconds for a full sentence is under the time it takes to notice somebody
## has spoken, look at them, and read it — the first playtester's words were
## "the subtitles go so quick". Scaled by length, with a floor, so "Mm." does
## not sit on screen for six seconds and a paragraph is readable.
func say(text: String, seconds := 3.2) -> void:
	seconds = maxf(seconds, 2.2 + float(text.length()) * 0.055)
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
		# The voice id is what `_voice_pitch()` is keyed on, not the display
		# name, so the subtitle's blips and the grunt below it are the same
		# person even for somebody whose name on screen changes.
		EventBus.subtitle.emit(display, text, seconds, voice_id())
	# EIGHT PEOPLE ON A WARD SHOULD NOT BE ONE MAN CLEARING HIS THROAT.
	#
	# Every line anybody spoke — Adeyemi, the patients, Ruth Kerrigan, Ms
	# Ferrand, the man in the corridor — played the same 220ms saw at 130 Hz with
	# a random 30% wobble. The wobble made it inconsistent WITHIN a character
	# without making any two characters different from each other, which is the
	# worst of both: nobody had a voice and nobody sounded steady.
	#
	# Pitch is derived from who they are instead, so a character sounds the same
	# every time they speak and different from the person in the next bed. The
	# small remaining jitter is per-utterance, so a voice is recognisable without
	# being robotic.
	AudioMgr.play_at("grunt", global_position, -24.0,
		_voice_pitch() * randf_range(0.97, 1.03))

## A steady pitch per character, spread across roughly an octave. Cached, so it
## cannot drift between two lines from the same person.
var _voice := 0.0

## The string everything about this character's voice is keyed on. One
## definition, because two of them is two different people: the grunt under a
## line and the blips of the line itself both derive from this, and until the
## subtitle carried it the HUD had no way to ask.
##
## PUBLIC, and that is not tidiness. `WardDay` puts words in Adeyemi's mouth
## from a system with no reference to her body — she answers when you send her
## to check on somebody — and her `npc_id` is assigned by index in `game.gd`,
## so the only honest way for that line to be the same woman as the one walking
## the ward is to ask her what she is called.
func voice_id() -> String:
	return npc_id if npc_id != "" else display

func _voice_pitch() -> float:
	if _voice > 0.0:
		return _voice
	# The formula moved to `AudioMgr.voice_pitch` — unchanged, and now read by
	# `mumble()` as well, so the grunt under a line and the blips that reveal
	# it are the same person. Two copies of it was gotcha 48 waiting to be
	# audible, and it became audible the moment the typewriter was wired in.
	_voice = AudioMgr.voice_pitch(voice_id())
	return _voice

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
## Off-duty staff are not in the building. Their mind stays registered with the
## suspicion system — somebody who saw you on Tuesday still saw you on Tuesday —
## but they cannot witness, be talked to, or be walked into while they are at
## home, and perception skips them.
func set_on_duty(v: bool) -> void:
	if on_duty == v:
		return
	on_duty = v
	visible = v
	set_physics_process(v)
	set_process(v)
	collision_layer = _duty_layer if v else 0
	if not v:
		stop_moving()
		_off_duty_at = global_position if is_inside_tree() else Vector3.ZERO
		if is_inside_tree():
			global_position = Vector3(_off_duty_at.x, -40.0, _off_duty_at.z)
	elif is_inside_tree():
		var h = get_tree().get_first_node_in_group("hospital")
		if h == null:
			global_position = _off_duty_at
		else:
			var back := String(get("home_room") if get("home_room") != null else "corridor")
			if back == "":
				back = "corridor"
			global_position = h.point_in(back, "duty_return")

## Sit down.
##
## Waiting patients and visitors are sent to chairs and then STOOD in them,
## which is the sort of thing that is invisible in a wide shot and impossible to
## unsee at three metres. There is no knee in this rig, so the whole leg rotates
## forward at the hip and the torso drops to seat height: at this level of
## stylisation that reads as sitting, and it costs two rotations.
## Sitting.
##
## Hips down, thighs forward, shins down, hands on the thighs and a little
## forward lean. The first version left the arms straight out in front like
## somebody sleepwalking, and never put them back when they stood up.
func set_seated(on: bool) -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	_seated = on
	if _shadow != null:
		_shadow.visible = not on
	var b: Node3D = body
	b.position = Vector3(0, -0.30, 0) if on else Vector3.ZERO
	# Sitting up straight is a thing nobody does. A few degrees of forward lean
	# is most of the difference between a person and a shop dummy.
	b.rotation.x = 0.07 if on else 0.0
	for leg in _legs:
		leg.rotation.x = -1.42 if on else 0.0
	for knee in _knees:
		knee.rotation.x = 1.36 if on else 0.0
	for i in _arms.size():
		var arm: Node3D = _arms[i]
		# Down and forward, elbows in — hands land on the thighs rather than
		# hovering over them.
		var sx: float = -1.0 if i == 0 else 1.0
		arm.rotation.x = -0.95 if on else ARM_REST_X
		arm.rotation.z = (0.16 if i == 0 else -0.16) if on else sx * ARM_REST_Z
	if _nametag:
		_nametag.position.y = (1.58 if on else 1.92) * height_scale
	if _speech:
		_speech.position.y = (1.82 if on else 2.12) * height_scale

## PROPPED UP IN A BED, which is not the same as lying flat and not the same as
## sitting in a chair.
##
## The chair was right for the game this used to be — a person lying down is
## scenery you do things TO, and the note that asked for chairs was correct
## about that. The redesign changed what the argument is about: the economy
## bills BED-NIGHTS, the reviewer asks why a bed was occupied at ten o'clock,
## and a ward that visibly contains no beds made the whole premise read as a
## waiting room. So they are in beds again, propped against the pillows at
## forty degrees, which is upright enough to look at you and to be looked at.
func set_in_bed(on: bool) -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	_seated = on
	if _shadow != null:
		_shadow.visible = not on
	var b: Node3D = body
	# Hips down at the mattress and back toward the pillow; trunk tipped BACKWARD
	# against the raised head of the bed.
	#
	# The sign matters and the first version had it wrong: a character model
	# faces its own -Z, so a POSITIVE rotation.x tips the top of the body toward
	# where it is looking — face down. The render showed five people hunched
	# forward over their own knees like a ward full of men being sick. Backward
	# is negative.
	b.position = Vector3(0, -0.55, 0.26) if on else Vector3.ZERO
	b.rotation.x = -0.52 if on else 0.0
	# Legs out along the mattress rather than folded off a seat, and nearly
	# straight at the knee — this is lying in a bed, not perching on one.
	for leg in _legs:
		leg.rotation.x = -1.02 if on else 0.0
	for knee in _knees:
		knee.rotation.x = 0.18 if on else 0.0
	for i in _arms.size():
		var arm: Node3D = _arms[i]
		arm.rotation.x = -0.30 if on else 0.0
		arm.rotation.z = (0.26 if i == 0 else -0.26) if on else 0.0
	if _nametag:
		_nametag.position.y = (1.30 if on else 1.92) * height_scale
	if _speech:
		_speech.position.y = (1.54 if on else 2.12) * height_scale

## How they feel about it, on the face and in the shoulders.
##
## Asked for by name: "there should be an immediate facial and body expression
## change if it's worse or better". Immediate is the point — the reaction has to
## land in the same second as the thing that caused it, or the player never
## connects the two.
func set_mood(m: float) -> void:
	_mood = clampf(m, -1.0, 1.0)
	for i in _brows.size():
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var brow: MeshInstance3D = _brows[i]
		# Inner ends down for a scowl, up and out for pleased.
		brow.rotation.z = sx * (BROW_REST_Z + _mood * 0.42)
		brow.position.y = BROW_REST_Y + _mood * 0.012
	for i in _mouth_corners.size():
		var corner: MeshInstance3D = _mouth_corners[i]
		corner.position.y = -0.062 + _mood * 0.030
	if _mouth != null:
		# A mouth that opens slightly when things are bad. Nobody grimaces with
		# their lips closed.
		_mouth.scale.y = 1.0 + maxf(0.0, -_mood) * 1.6
	if _torso != null:
		# And the shoulders. Slumped when it went badly, squared when it did not.
		_torso.rotation.x = -_mood * 0.10
	if _head != null:
		_head.position.y = _head_y + _mood * 0.014 - maxf(0.0, -_mood) * 0.03

# Squaring up, throwing a punch, and folding unconscious over your own knees all
# lived here — stand_and_square_up(), stand_down(), swing_arm() and
# set_slumped(), driven straight off the fight's rules clock. They went with the
# fistfight. Nobody in the building swings at anybody any more.

func mood() -> float:
	return _mood

func is_seated() -> bool:
	return _seated

var _seated := false

func set_reclined(on: bool) -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	var b: Node3D = body
	b.rotation.x = -PI * 0.5 if on else 0.0
	# 1.02 puts the head on the pillow rather than a hand's width above it: the
	# mattress top is 0.78 over the bed's origin and a head is 0.20 across.
	b.position = Vector3(0, 1.02, 0.52) if on else Vector3.ZERO
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


## ------------------------------------------------------------------ hair
func _hair_style(hair_mat: Material) -> void:
	# WHAT THE HAIRCUT IS, on top of what colour it is.
	#
	# Colour alone is close to invisible across a lit ward: three dark-haired
	# patients in a row are three identical dark caps whatever the swatches say,
	# and that is what the first ward lineup came back as. A SILHOUETTE is
	# visible at any distance the head is, and it costs two spheres.
	#
	# Everything here is squashed spheres in the hair material, because that is
	# what the crown and the forelock already are and a slab reads as hair from
	# straight on only (see the note above them).
	# Heavy thinning takes the cropped cap whatever the draw said: a receding
	# bob is not a haircut anybody has.
	if bald >= 0.5:
		return
	match hair_style:
		1:
			# SWEPT. One mass, off centre and higher on one side, so the head
			# has a parting. The one style with a left/right asymmetry, which
			# is what makes a crowd stop looking mirror-symmetrical.
			_head.add_child(Build.mi(Build.sphere_mesh(0.150), hair_mat,
				Vector3(-0.052 * skull.x, 0.128 * skull.y, 0.010), Vector3(0, 0, 0.24),
				Vector3(0.92 * skull.x, 0.46, 0.88 * skull.z)))
		2:
			# BOBBED. Two masses down each side to the jaw. The biggest change
			# to an outline in this list and the one that reads furthest.
			for hx in [-1.0, 1.0]:
				_head.add_child(Build.mi(Build.sphere_mesh(0.115), hair_mat,
					Vector3(hx * 0.170 * skull.x, -0.055 * skull.y, -0.020),
					Vector3.ZERO,
					Vector3(0.52, 1.28, 0.94 * skull.z)))
		3:
			# TIED UP, and it is a TOPKNOT rather than the low bun this started
			# as. Measured on the authored cast: 6 of 40 draw this style and 6
			# draw the cropped cap, and a bun sitting behind the skull is
			# invisible from the front — which is where you see a patient, in a
			# bed, from the foot of it. Twelve of forty were reading as the
			# same haircut for want of four centimetres of height.
			#
			# Two pieces: the knot clearing the crown, and the sweep that
			# gathers into it, so it does not read as a ball balanced on a head.
			_head.add_child(Build.mi(Build.sphere_mesh(0.082), hair_mat,
				Vector3(0, 0.225 * skull.y, -0.045 * skull.z), Vector3.ZERO,
				Vector3(0.92, 0.92, 0.88)))
			_head.add_child(Build.mi(Build.sphere_mesh(0.140), hair_mat,
				Vector3(0, 0.120 * skull.y, -0.070 * skull.z), Vector3.ZERO,
				Vector3(0.86 * skull.x, 0.62, 0.90 * skull.z)))
		4:
			# FULL. More volume everywhere rather than a shape, which is a
			# haircut in its own right and also the one that survives being
			# seen from directly above — the angle you get standing over a bed.
			# Volume at the BACK and top. Left where it was it reached z=0.227,
			# well in front of the eyes, and buried the forehead the forelock
			# above had just uncovered.
			_head.add_child(Build.mi(Build.sphere_mesh(0.238), hair_mat,
				Vector3(0, 0.126 * skull.y, -0.075), Vector3.ZERO,
				Vector3(1.06 * skull.x, 0.72, 0.95 * skull.z)))
