class_name MenuScene
extends Node3D
## The title screen's window into the building.
##
## The menu used to be a panel on a flat dark rectangle, which is a strange
## first thing to show somebody about a game whose entire look is a bright
## cartoon hospital. This is a corner of a ward, built from the same primitives
## and lit the same way, with the camera drifting slowly across it behind the
## panel — so the first frame of the game looks like the game.
##
## It is deliberately a *vignette* and not the real hospital: the real one is
## sixty-two metres of building with navigation and staff in it, and the title
## screen has no business paying for that before you have pressed anything.

const WALL_H := 3.0
const HALF_X := 5.0
const HALF_Z := 3.6

var cam: Camera3D = null
var _t := 0.0

func _ready() -> void:
	_room()
	_furnish()
	_people()
	_light()
	_camera()

# ------------------------------------------------------------------ the room
func _room() -> void:
	# Build.wall, not box_mi: this needs a COLLIDER. The nurse is a
	# CharacterBody3D and falls at 9.8 m/s² through a floor that is only a mesh,
	# so the first version of this shot had nobody in it and no error to say why.
	add_child(Build.wall(Vector3(HALF_X * 2.0, 0.2, HALF_Z * 2.0), Build.FLOOR_A,
		Vector3(0, -0.1, 0), 0.0, 0.0))
	add_child(Build.box_mi(Vector3(HALF_X * 2.0, 0.14, HALF_Z * 2.0), Build.CEILING,
		Vector3(0, WALL_H + 0.07, 0), 0.9, 0.0))
	_wall(Vector3(HALF_X * 2.0, WALL_H, 0.2), Vector3(0, 0, -HALF_Z), true)
	_wall(Vector3(0.2, WALL_H, HALF_Z * 2.0), Vector3(-HALF_X, 0, 0), false)
	_wall(Vector3(0.2, WALL_H, HALF_Z * 2.0), Vector3(HALF_X, 0, 0), false)

## The same two-tone wall the hospital builds, with the rail and skirting that
## are most of why its rooms read as built rather than generated.
func _wall(size: Vector3, at: Vector3, horizontal: bool) -> void:
	var lower := 1.1
	add_child(Build.box_mi(Vector3(size.x, lower, size.z), Build.WALL_LOWER,
		at + Vector3(0, lower * 0.5, 0), 0.9, 0.0))
	add_child(Build.box_mi(Vector3(size.x, WALL_H - lower, size.z), Build.WALL_UPPER,
		at + Vector3(0, lower + (WALL_H - lower) * 0.5, 0), 0.9, 0.0))
	var out := Vector3(0, 0, 0.1) if horizontal else Vector3(0.1, 0, 0)
	var rail := Vector3(size.x, 0.075, 0.11) if horizontal else Vector3(0.11, 0.075, size.z)
	var skirt := Vector3(size.x, 0.16, 0.14) if horizontal else Vector3(0.14, 0.16, size.z)
	var cornice := Vector3(size.x, 0.13, 0.16) if horizontal else Vector3(0.16, 0.13, size.z)
	for side in [1.0, -1.0]:
		add_child(Build.box_mi(rail, Color(0.95, 0.93, 0.86),
			at + out * side + Vector3(0, lower, 0), 0.55))
		add_child(Build.box_mi(skirt, Color(0.17, 0.22, 0.27),
			at + out * side + Vector3(0, 0.08, 0), 0.6))
		add_child(Build.box_mi(cornice, Color(0.97, 0.96, 0.93),
			at + out * side + Vector3(0, WALL_H - 0.07, 0), 0.5))

# ------------------------------------------------------------------ contents
func _furnish() -> void:
	# The patient's chair, which is what a ward has in it now.
	var bed := PatientBed.new()
	bed.name = "Chair"
	add_child(bed)
	bed.build()
	# Everything worth looking at is pushed OUT to the sides. The menu panel
	# covers the middle two-fifths of the screen, so anything composed into the
	# centre of the shot is a thing nobody will ever see.
	bed.position = Vector3(-3.05, 0, -1.5)
	bed.rotation.y = 0.55

	Dressing.overbed_table(self, Vector3(-1.75, 0, -1.2), 0.2)
	Dressing.curtain(self, Vector3(-4.3, 0, -0.2), 2.4, PI * 0.5)
	Dressing.cabinet(self, Vector3(3.3, 0, -2.9), 0.0)
	Dressing.plant(self, Vector3(4.35, 0, -2.4), 1.15)
	Dressing.stool(self, Vector3(2.75, 0, 0.1))
	Dressing.water_cooler(self, Vector3(4.35, 0, 0.9), -PI * 0.5)
	Dressing.bin(self, Vector3(-4.4, 0, 1.6))
	Dressing.floor_mat(self, Vector3(0.4, 0, 2.4), Vector2(1.8, 1.1))

	Dressing.oxygen_panel(self, Vector3(-3.05, 1.5, -HALF_Z + 0.1), 0.0)
	Dressing.sharps(self, Vector3(-1.6, 1.35, -HALF_Z + 0.1), 0.0)
	Dressing.poster(self, Vector3(2.1, 1.85, -HALF_Z + 0.1), 0.0)
	Dressing.clock(self, Vector3(3.6, 2.3, -HALF_Z + 0.1), 0.0)
	Dressing.wall_art(self, Vector3(-HALF_X + 0.1, 1.95, 0.9), PI * 0.5)
	Dressing.whiteboard(self, Vector3(HALF_X - 0.1, 1.9, 0.6), -PI * 0.5)
	Dressing.dispenser(self, Vector3(HALF_X - 0.1, 1.5, -1.9), -PI * 0.5)
	Dressing.sprinkler(self, Vector3(0.4, WALL_H - 0.1, 0.4))
	Dressing.vent(self, Vector3(0.6, 2.55, -HALF_Z + 0.1), 0.0)

## One person, standing where a nurse stands. A room with nobody in it reads as
## a screenshot of a level; a room with somebody breathing in it reads as a
## place with a job going on in it, which is what the game is about.
var nurse: NPCBody = null
var sitter: NPCBody = null

func _people() -> void:
	nurse = NPCBody.new()
	nurse.display = ""
	nurse.set_colours(Color(0.88, 0.73, 0.60), Build.SCRUB_GREEN, Color(0.22, 0.16, 0.13))
	add_child(nurse)
	nurse.position = Vector3(-3.55, 0, -0.35)
	# Facing the chair, which is the whole reason to have her in the shot.
	nurse.rotation.y = 2.59

	# And somebody in the chair. A ward room with an empty chair in it is a
	# picture of some furniture; the game is about the person in it.
	sitter = NPCBody.new()
	sitter.display = ""
	sitter.set_colours(Color(0.80, 0.62, 0.47), Color(0.62, 0.72, 0.86),
		Color(0.30, 0.22, 0.16))
	add_child(sitter)
	sitter.position = Vector3(-3.05, 0, -1.5)
	sitter.rotation.y = 0.55
	sitter.set_seated(true)

func _light() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# The menu has no sky, so ambient has to come off the colour — see the note
	# in NightSystem._set_night_look for the half-day this cost the first time.
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_color = Color(0.74, 0.84, 0.92)
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.80
	env.tonemap_white = 2.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.06
	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.3
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -34, 0)
	key.light_energy = 0.9
	key.light_color = Color(1.0, 0.98, 0.94)
	add_child(key)

	var panel := Node3D.new()
	add_child(panel)
	panel.position = Vector3(-1.2, WALL_H - 0.12, -1.0)
	panel.add_child(Build.mi(Build.box_mesh(Vector3(1.5, 0.10, 0.42)),
		Build.unshaded(Color(1.0, 0.98, 0.90)), Vector3.ZERO))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.96, 0.88)
	lamp.light_energy = 3.2
	lamp.omni_range = 9.0
	lamp.position = Vector3(0, -0.3, 0)
	panel.add_child(lamp)

func _camera() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.current = true
	add_child(cam)
	_aim(0.0)

## A slow drift rather than a fixed shot. Two different periods so it never
## quite repeats, and small enough that it reads as a room being looked at
## rather than as a camera being moved.
func _process(delta: float) -> void:
	_t += delta
	_aim(_t)

## Hold still, and look at the people.
##
## The drifting shot is composed around a panel in the middle of the screen. A
## capsule has no panel and wants the room's occupants filling the right two
## thirds, so this stops the drift and re-frames.
var _capsule := false

func pose_for_capsule(on: bool) -> void:
	_capsule = on
	set_process(not on)
	if not on:
		_aim(_t)
		return
	if cam == null:
		return
	# The people move, not just the camera. A capsule wants its subjects filling
	# the right two thirds with the title over the quiet left, and the room was
	# laid out the other way round for a panel in the middle.
	var chair := get_node_or_null("Chair")
	if chair == null:
		for c in get_children():
			if c is PatientBed:
				chair = c
	if chair != null:
		chair.position = Vector3(2.05, 0, -1.15)
		chair.rotation.y = -0.67
	if sitter != null and is_instance_valid(sitter):
		sitter.position = Vector3(2.05, 0, -1.15)
		sitter.rotation.y = -0.67
		sitter.set_seated(true)
		sitter.set_mood(-0.35)
	if nurse != null and is_instance_valid(nurse):
		nurse.position = Vector3(0.62, 0, 0.20)
		nurse.rotation.y = 2.32
		nurse.set_mood(0.15)
	cam.fov = 52.0
	cam.position = Vector3(-1.15, 1.52, 2.75)
	cam.look_at(Vector3(1.70, 1.16, -0.85), Vector3.UP)

func _aim(t: float) -> void:
	if _capsule:
		return
	if cam == null:
		return
	cam.position = Vector3(
		0.55 + sin(t * 0.11) * 0.70,
		1.38 + sin(t * 0.077) * 0.08,
		2.95 + cos(t * 0.13) * 0.30)
	# Aimed slightly UP. A camera at eye height looking level at a room fills
	# the bottom half of the frame with empty floor, and the bottom half of the
	# frame is the half the panel does not cover.
	cam.look_at(Vector3(-0.35 + sin(t * 0.09) * 0.30, 1.52, -2.2), Vector3.UP)
