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
var _eyes_open: Array[MeshInstance3D] = []
var _eyes_shut: Array[MeshInstance3D] = []
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
	cap.height = 1.7 * height_scale
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
	_torso.position = Vector3(0, 0.95, 0)
	root.add_child(_torso)
	# One solid, hip to shoulder, broad at the top.
	_torso.add_child(Build.mi(
		Build.taper_mesh(Vector2(0.44, 0.30), Vector2(0.70, 0.36), 0.74, 0.13),
		Build.mat(outfit, 0.85, 0.0, Color(0, 0, 0), LINE), Vector3(0, 0.06, 0)))
	# A collar, deliberately proud of the shoulders so it DOES take a line of
	# its own — one band of contrast at the top of the body, which is what the
	# eye lands on first.
	_torso.add_child(Build.mi(
		Build.taper_mesh(Vector2(0.42, 0.34), Vector2(0.34, 0.28), 0.09, 0.035),
		Build.mat(outfit.lightened(0.30), 0.85, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, 0.385, 0.005)))
	# ...and a neck inside it, so the head is attached to something instead of
	# hovering over a collar. No line: it is never the silhouette.
	_torso.add_child(Build.mi(Build.capsule_mesh(0.082, 0.22),
		Build.mat(skin.darkened(0.10), 0.85, 0.0, Color(0, 0, 0), 0.0),
		Vector3(0, 0.46, 0)))

	_head = Node3D.new()
	_head.position = Vector3(0, 1.50, 0)
	root.add_child(_head)
	# An egg, not a ball: taller than wide, flattened at the back, the volume
	# carried high, and the jaw taken out of the same solid by squashing rather
	# than bolted on as a second box.
	_head.add_child(Build.mi(Build.sphere_mesh(0.215),
		Build.mat(skin, 0.85, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, -0.01, 0), Vector3.ZERO, Vector3(0.98, 1.14, 0.92)))
	# Ears and a nose. Four centimetres of geometry each, and between them the
	# difference between a face and a balloon with eyes drawn on it. Lined,
	# because both of them break the head's silhouette.
	for ex in [-1.0, 1.0]:
		_head.add_child(Build.mi(Build.sphere_mesh(0.052),
			Build.mat(skin, 0.85, 0.0, Color(0, 0, 0), LINE),
			Vector3(ex * 0.198, -0.015, -0.02), Vector3.ZERO, Vector3(0.45, 1.05, 0.75)))
	_head.add_child(Build.mi(Build.sphere_mesh(0.040),
		Build.mat(skin, 0.85, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, -0.022, 0.188), Vector3.ZERO, Vector3(0.78, 0.70, 1.15)))
	# A mouth. One dark bar, and the face stops being a nose between two eyes.
	# It is also where every future expression goes, if there is ever one.
	_head.add_child(Build.mi(Build.rbox_mesh(Vector3(0.085, 0.022, 0.03), 0.010),
		Build.mat(Color(0.42, 0.24, 0.24), 0.9, 0.0, Color(0, 0, 0), 0.0),
		Vector3(0, -0.100, 0.180)))
	# A chin, so the jaw has a bottom to it. Lined, because it is the profile.
	_head.add_child(Build.mi(Build.sphere_mesh(0.085),
		Build.mat(skin, 0.85, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, -0.150, 0.075), Vector3.ZERO, Vector3(1.05, 0.72, 0.95)))
	# A cap on the crown, set BACK from the face and narrower than the skull.
	# The first pass made it 0.37 wide on a 0.40 head and centred it, which is
	# a helmet — and a patient lying in a bed is rotated ninety degrees, so the
	# first rendered close-up was a brown block where a face should be with two
	# eyes peering over the top of it. A squashed SPHERE, not a box: a slab
	# reads as hair from straight on only, and from the side it was a dark plank
	# stuck to somebody's cheek.
	_head.add_child(Build.mi(Build.sphere_mesh(0.224),
		Build.mat(hair, 0.9, 0.0, Color(0, 0, 0), LINE),
		Vector3(0, 0.078, -0.030), Vector3.ZERO, Vector3(0.99, 0.70, 1.0)))
	# ...and a forelock, so there is a hairLINE. Hair with no edge on the
	# forehead reads as a swimming cap — but a straight BAR across the forehead
	# reads as a headband, which is what the first attempt at this was. A second
	# squashed sphere set forward and low follows the skull instead.
	_head.add_child(Build.mi(Build.sphere_mesh(0.185),
		Build.mat(hair, 0.9, 0.0, Color(0, 0, 0), 0.0),
		Vector3(0, 0.082, 0.055), Vector3.ZERO, Vector3(1.02, 0.52, 0.86)))
	# Eyes: the cheapest possible way to make "is this person looking at me"
	# legible across a corridor, which the whole suspicion system depends on.
	# Bigger than life, with a white behind them — a dot on a sphere is a mole;
	# a dot on a white oval is an eye. Unshaded and unlined: a black ring round
	# an eyeball at this scale is just a bigger pupil.
	for sx in [-1.0, 1.0]:
		var white := Build.mi(Build.sphere_mesh(0.056), Build.unshaded(Color(0.99, 0.99, 1.0)),
			Vector3(sx * 0.080, 0.012, 0.166), Vector3.ZERO, Vector3(0.92, 1.18, 0.78))
		var pupil := Build.mi(Build.sphere_mesh(0.030), Build.unshaded(Color(0.10, 0.11, 0.16)),
			Vector3(sx * 0.080, 0.008, 0.196))
		_head.add_child(white)
		_head.add_child(pupil)
		_eyes_open.append(white)
		_eyes_open.append(pupil)
		# A brow above each eye, in the hair colour. Two small dark bars are the
		# whole of this model's expression budget and they are worth every
		# triangle: without them the face is permanently, blankly surprised.
		_head.add_child(Build.mi(Build.rbox_mesh(Vector3(0.098, 0.020, 0.026), 0.009),
			Build.mat(hair.lightened(0.10), 0.9, 0.0, Color(0, 0, 0), 0.0),
			Vector3(sx * 0.082, 0.068, 0.192)))
		# A closed lid, hidden until it is needed. Hiding the eyes alone leaves
		# a blank face, which reads as a missing texture rather than as sleep.
		var lid := Build.mi(Build.rbox_mesh(Vector3(0.095, 0.017, 0.024), 0.008),
			Build.unshaded(Color(0.36, 0.27, 0.24)), Vector3(sx * 0.080, 0.012, 0.192))
		lid.visible = false
		_head.add_child(lid)
		_eyes_shut.append(lid)

	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.395, 1.24, 0)
		root.add_child(arm)
		# One sleeve, one cuff, one mitten. The hand is WIDER than the wrist:
		# limbs that taper to nothing read as tentacles, and what sells a hand
		# is being the widest thing at the end of the arm.
		arm.add_child(Build.mi(Build.taper_mesh(Vector2(0.15, 0.15), Vector2(0.20, 0.20), 0.56, 0.075),
			Build.mat(outfit, 0.85, 0.0, Color(0, 0, 0), LINE), Vector3(0, -0.26, 0)))
		arm.add_child(Build.mi(Build.capsule_mesh(0.082, 0.13),
			Build.mat(skin, 0.85, 0.0, Color(0, 0, 0), LINE), Vector3(0, -0.50, 0)))
		arm.add_child(Build.mi(Build.rbox_mesh(Vector3(0.15, 0.17, 0.10), 0.048),
			Build.mat(skin, 0.85, 0.0, Color(0, 0, 0), LINE), Vector3(0, -0.60, 0.01)))
		_arms.append(arm)

		# Thigh, then a KNEE, then shin and shoe.
		#
		# One rigid leg can only ever stick straight out, which is what the first
		# sitting pose looked like: a patient in the waiting row with both legs
		# horizontal and their feet in the air. A knee costs one more node per
		# leg and buys a real sit — thigh forward, shin down, foot on the floor —
		# as well as a bend on the back-swing of the walk.
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.145, 0.68, 0)
		root.add_child(leg)
		leg.add_child(Build.mi(Build.taper_mesh(Vector2(0.20, 0.20), Vector2(0.27, 0.25), 0.34, 0.085),
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

	_nametag = Build.label3d(display, 0.095, Color(0.99, 0.99, 0.96))
	_nametag.position = Vector3(0, 1.98 * height_scale, 0)
	add_child(_nametag)

	_speech = Build.label3d("", 0.075, Color(1, 1, 1))
	_speech.position = Vector3(0, 2.20 * height_scale, 0)
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
	if _seated:
		# Seated: breathe and blink, but do not walk. Without this the legs
		# swing back to vertical on the first frame of the idle cycle and the
		# character stands up through the chair.
		_idle_phase += 0.0
		if _torso:
			_torso.position.y = -0.26 + sin(_idle_phase * 1.35 + _idle_offset) * 0.008
		_tick_blink(delta)
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
			if back == "" or not h.is_room_open(back):
				back = "corridor"
			global_position = h.point_in(back, "duty_return")

## Sit down.
##
## Waiting patients and visitors are sent to chairs and then STOOD in them,
## which is the sort of thing that is invisible in a wide shot and impossible to
## unsee at three metres. There is no knee in this rig, so the whole leg rotates
## forward at the hip and the torso drops to seat height: at this level of
## stylisation that reads as sitting, and it costs two rotations.
func set_seated(on: bool) -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	_seated = on
	var b: Node3D = body
	b.position = Vector3(0, -0.26, 0) if on else Vector3.ZERO
	for leg in _legs:
		leg.rotation.x = -1.45 if on else 0.0
	# Thigh forward, shin back down, foot on the floor.
	for knee in _knees:
		knee.rotation.x = 1.45 if on else 0.0
	if _arms.size() >= 2 and on:
		# Hands on knees, roughly. Anything is better than two arms hanging
		# through the seat of a chair.
		_arms[0].rotation.x = -0.55
		_arms[1].rotation.x = -0.55
	if _nametag:
		_nametag.position.y = (1.62 if on else 1.92) * height_scale
	if _speech:
		_speech.position.y = (1.86 if on else 2.12) * height_scale

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
