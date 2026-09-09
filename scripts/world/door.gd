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
## Which way it is currently swinging, and whether somebody is leaning on it
## right now. See open_for(): both exist because a door being pushed open is a
## continuous act and this class integrates by hand.
var _open_dir := 0.0
var _held := 0
var _latch := 0.0
## Deliberately being pulled shut. Distinct from the passive closer, which only
## ever eases a door that has run out of momentum.
var _closing := false

# ------------------------------------------------------------------ sound
## A DOOR IS THREE EVENTS AND IT USED TO BE ONE SOUND PLAYED THREE TIMES.
##
## `push()`, the `is_open()` threshold crossing three or four frames later, and
## the crossing back on the way shut all played the same 350 ms saw at 180 Hz
## with a ±10-15% pitch spread — so one shove-and-let-go was that buzz three
## times inside two seconds, on the most common physical interaction in a
## building made of corridors. Distant doors in `AmbienceSystem.SPARSE` were
## the same buzz again.
##
## Now: `door_swing` when somebody moves the leaf on purpose, `door_latch` when
## it comes to rest shut, and `door_bump` for the threshold crossing — quiet,
## and only when the swing was not one the player just started, because that
## crossing is exactly the moment their own push is still ringing.
##
## The bump is NOT deleted, which was the tempting simplification: `push()` and
## `pull_shut()` are the player's verbs and NPCs use neither. `NPCBody`
## (`_open_door_ahead` and `_push_obstacles`) calls `open_for()` directly, so
## the crossing is the only audio a door gets when somebody else walks through
## it, and deleting it makes every staff member in the building a ghost.
const SWING_QUIET := 0.75
var _swing_quiet := 0.0
## True while the leaf is at rest against its frame. The latch used to be
## played only from the `_closing` branch — the deliberate pull — so a door
## left to the passive closer, which is every door an NPC ever touches and most
## of the ones the player does, arrived home in silence. Tracked as a state
## rather than fired from one code path, because there are two ways for a door
## to reach zero and both of them are a latch.
var _latched := true

## How long a swing keeps its direction before the door will listen to where the
## person leaning on it is standing again.
##
## It has to be long enough to cover walking through — the moment you are past
## the leaf, "which side are you on" flips, and without a latch the door
## immediately sweeps back into the doorway you are still in. And it has to be
## short enough that somebody PINNED behind an open leaf can push it off them,
## which is the same geometry a second later and is a soft-lock if it never
## resolves. Nine tenths of a second is comfortably both.
const LATCH_TIME := 0.9

func build(a: Vector3, b: Vector3, _flip: bool) -> void:
	width = a.distance_to(b)
	position = a
	var along := (b - a).normalized()
	# Face the door so its local +Z runs along the wall FROM the hinge, because
	# the leaf is built extending along local +Z. Get this wrong by ninety
	# degrees and the leaf stands perpendicular to its own doorway.
	#
	# It was wrong by ninety degrees. `atan2(-along.x, -along.z) + PI * 0.5`
	# evaluates to exactly 0 for every door in this building (all of them run
	# along +X), so every leaf was a seven-centimetre slab jutting into the room
	# beside its opening, and every opening stood permanently, completely clear.
	#
	# Nothing caught it. The doors swung, made their noise, reported angles,
	# blocked the slab's own footprint, and passed every test — because what was
	# tested was "can staff path through a doorway", and the answer was yes,
	# trivially, since there was nothing in it. What nobody had ever asked was
	# whether a SHUT door shuts anything.
	#
	# It does now, and that is not a small change: closing the door is the
	# stealth game's most basic move. Privacy, line of sight into a ward, being
	# seen from the corridor, and every upgrade that reduces witnesses were all
	# resting on a leaf that was not in the way of anything.
	rotation.y = atan2(along.x, along.z)

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
		Build.mat(Build.METAL, 0.30, 0.25), Vector3(0, 1.05, width * 0.85)))

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
	var held := _held > 0
	_held = maxi(0, _held - 1)
	_latch = maxf(0.0, _latch - delta)
	_swing_quiet = maxf(0.0, _swing_quiet - delta)
	if _closing:
		var was := angle
		angle += angular_velocity * delta
		# Stop AT the frame, not past it and out the other side.
		if signf(angle) != signf(was) or absf(angle) < 0.02:
			angle = 0.0
			angular_velocity = 0.0
			_closing = false
			_open_dir = 0.0
			_latch = 0.0
		leaf.rotation.y = angle
		_was_open = is_open()
		_settle()
		return
	if absf(angular_velocity) > 0.001 or absf(angle) > 0.001:
		angle += angular_velocity * delta
		angular_velocity = lerpf(angular_velocity, 0.0, 1.0 - exp(-DAMPING * delta))
		if absf(angle) >= MAX_ANGLE:
			angle = clampf(angle, -MAX_ANGLE, MAX_ANGLE)
			# A door somebody is leaning on rests against its stop. One that was
			# shoved and let go bounces off it. Without the distinction, a door
			# being held open by a body in the gap slams into the stop, bounces,
			# is re-driven at full speed on the next frame, and spends the whole
			# time sweeping back and forth THROUGH the person holding it — who
			# is then batted around by a kinematic body they cannot push. That
			# is what "stood in the supply room doorway for forty-five seconds"
			# actually was: not a door that would not open, a door that would
			# not stop opening.
			angular_velocity = 0.0 if held else -angular_velocity * 0.25
		# Ease shut once it has lost its momentum, like a real closer — unless
		# somebody is still in it.
		if absf(angular_velocity) < 0.35 and not held:
			angle = lerpf(angle, 0.0, 1.0 - exp(-1.1 * delta))
		if absf(angle) < 0.02 and not held:
			_open_dir = 0.0
			_latch = 0.0
		leaf.rotation.y = angle

	var open := is_open()
	if open != _was_open:
		_was_open = open
		# Somebody ELSE's door. Suppressed for three quarters of a second after
		# a deliberate push or pull, because that crossing happens three or
		# four frames into a swing the player has already heard start — which
		# is where two of the three copies of the old buzz came from.
		if _swing_quiet <= 0.0:
			AudioMgr.play_at_var("door_bump", global_position, -22.0, 0.18)
	_settle()

## The latch, from whichever of the two ways home the leaf took.
##
## `pull_shut()` drives the `_closing` branch to exactly zero; everything else
## — an NPC's `open_for`, a shove that ran out of momentum — is eased to
## somewhere under 0.02 by the passive closer and never reaches zero at all. A
## sound fired from the first path only meant that the doors the player deals
## with deliberately clicked shut and every other door in the building went
## quiet mid-swing. A hysteresis band rather than a threshold, so a leaf
## resting a hair off its frame and jittering cannot chatter the latch.
func _settle() -> void:
	if _latched:
		if absf(angle) > 0.06:
			_latched = false
		return
	if absf(angle) >= 0.02 or absf(angular_velocity) >= 0.05:
		return
	_latched = true
	AudioMgr.play_at_var("door_latch", global_position, -17.0, 0.12)

func angle_deg() -> float:
	return rad_to_deg(angle)

func is_open() -> bool:
	return absf(angle) > 0.35

## Swing away from whoever is standing there. Used by NPCs and by the player.
## The middle of the opening, in world space. This node sits on the HINGE — the
## leaf extends from it along local +Z — so the hinge is the one point in the
## doorway from which "which side is this person on" cannot be answered.
func opening_centre() -> Vector3:
	return global_position + global_transform.basis.z * (width * 0.5)

func open_for(pos: Vector3, speed := OPEN_SPEED) -> void:
	if leaf == null:
		return
	# Which side of the door plane they are on. The door's local X is the plane
	# normal, since the leaf extends along local Z.
	#
	# Measured from the middle of the OPENING, not from this node. This node is
	# the hinge, at one edge of the doorway: somebody walking in near that edge
	# has an offset almost parallel to the closed leaf, the dot product lands on
	# either side of zero by rounding, and the fallback then swung the door
	# whichever way the code happened to prefer — frequently straight into the
	# person pushing it, who is then pinned by a kinematic body they cannot
	# move. Two scripted playthroughs stood against the supply room door and the
	# office door for forty-five and sixty seconds each, while the prompt in
	# front of them said "or just walk into it".
	_held = 3
	_closing = false
	var normal := global_transform.basis.x
	var d := (pos - opening_centre()).dot(normal)
	# Ignore anybody standing IN the plane of the door: their side is a rounding
	# error, and acting on it makes the leaf chatter.
	if absf(d) > 0.25 and _latch <= 0.0:
		var want := -signf(d)
		if want != _open_dir:
			_latch = LATCH_TIME
		_open_dir = want
	if _open_dir == 0.0:
		_open_dir = -signf(d) if absf(d) > 0.001 else 1.0
		_latch = LATCH_TIME
	# Already as far open as it goes: hold it there rather than driving it into
	# the stop again.
	if absf(angle) >= MAX_ANGLE * 0.85 and signf(angle) == _open_dir:
		angular_velocity = 0.0
		return
	angular_velocity = _open_dir * speed

func push(from: Vector3) -> void:
	_closing = false
	open_for(from, PUSH_SPEED)
	AudioMgr.play_at_var("door_swing", global_position, -14.0)
	_swing_quiet = SWING_QUIET

## Pull it shut behind you.
##
## There was no way to do this. `door_use.gd` prompted "Pull door" whenever the
## door was open and then called push(), which opens it — so the one verb the
## entire stealth layer rests on did not exist. Shutting the door is how you get
## a room to yourself; it is what the vision-blocker layer on the leaf is FOR,
## and what half the upgrade tree is priced against.
func pull_shut() -> void:
	if leaf == null or absf(angle) < 0.02:
		return
	_closing = true
	_held = 0
	angular_velocity = -signf(angle) * PUSH_SPEED
	# Three decibels under the push: pulling a door to is a smaller gesture
	# than shoving one open, and the latch that follows it a moment later is
	# the loud half of the act.
	AudioMgr.play_at_var("door_swing", global_position, -17.0)
	_swing_quiet = SWING_QUIET

func slam() -> void:
	_closing = false
	_open_dir = 0.0
	_latch = 0.0
	_held = 0
	angle = 0.0
	angular_velocity = 0.0
	if leaf:
		leaf.rotation.y = 0.0
	# A slam IS the latch, at volume. Marked as settled so `_settle` does not
	# put a small click on the end of a bang on the next physics frame.
	_latched = true
	_was_open = false
	_swing_quiet = SWING_QUIET
	AudioMgr.play_at("thud", global_position, -6.0)
	var pl = get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("shake") \
			and pl.global_position.distance_to(global_position) < 5.0:
		pl.shake(0.4)
	WorldEvent.new("door_slammed", "player").at(global_position, room_key) \
		.heard(0.0, 16.0).tag("noise").says("a door slammed").emit()
