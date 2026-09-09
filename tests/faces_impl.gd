extends RefCounted
## SIX FACES, CLOSE UP, IN THE GAME'S OWN LIGHT.
##
## Character work was being judged from `screenshots.sh` — twenty-one frames and
## twenty minutes — or from `look.sh`'s lineup, where a head is sixty pixels
## tall. Neither is a loop you can do an art pass in, and the first attempt at
## head variation shipped with a hairstyle that is invisible from the front
## because nothing ever looked at a face from the distance a player looks at one.
##
## This spawns six people through `Appearance` — the same machinery the ward
## uses, so these are real draws and not hand-picked — stands them in the
## corridor, and photographs each from eighty centimetres, which is where you
## are when you are standing over a bed. Then all six together, because a cast
## is judged against itself.
##
## Deliberately in the CORRIDOR and not a void: plain walls, the building's own
## ceiling fittings, the real grade. A face on a grey card is a different
## problem to a face in this game.
var tree: SceneTree = null
var game: Node = null
var frames := 0
var index := 0
var settle := 0
var bodies: Array = []
var tag := "x"
## Where each subject's portrait camera goes — which is also what that subject
## is looking at, so nobody is caught mid-turn.
var _aims: Array = []
var _cast_posed := false

## Ages spread so the greying and the balding are both in the frame.
const WHO := [
	["face_a", 27], ["face_b", 41], ["face_c", 58],
	["face_d", 66], ["face_e", 34], ["face_f", 73],
]

## Where they stand, and THE CORRIDOR IS TWENTY METRES LONG (Rect2(0,0,20,4)).
## The first version spaced six subjects five metres apart from x=2.5, which put
## the last two at 22.5 and 27.5 — outside the building, with nothing under
## them. They fell: by the time the camera reached them their heads were at
## y=0.43 and still dropping, so the portrait framed the top of a skull and the
## head pitched up at a lens above it. It reads exactly like a model with a
## broken neck, and a render went into blaming `_tick_look` for it.
##
## Three metres still leaves a portrait at eighty centimetres with nobody else
## in the frame, and six of them fit between the walls.
const SPACING := 3.0
const FIRST_X := 2.5
const Z := 2.6
## For the cast shot only, everybody shuffles into a tight line IN THE WARD.
##
## Two constraints collide here. Six people three metres apart span fifteen
## metres, so they have to close up — and closed up at 0.78m they still span
## nearly four, which needs four and a half metres of standback to frame. The
## corridor is four metres DEEP (Rect2(0,0,20,4)), so the first version put the
## cast camera at z=-2.0: outside the building, pointed at the back of a wall,
## and the shot came back as a photograph of some plaster with a Ward C sign on
## it. The ward is nine metres deep and its middle is open floor.
const CAST_SPACING := 0.78
const CAST_AT := Vector3(10.0, 0.0, 9.6)
const CAST_BACK := 4.6
## Frames to hold before the shutter. A portrait needs almost none, because the
## subject was aimed at that exact lens on the frame it spawned and has had the
## whole warm-up to turn. The cast shot moves everybody, so it pays for the turn.
const SETTLE_PORTRAIT := 5
const SETTLE_CAST := 34

func start() -> void:
	tag = OS.get_environment("FACES_TAG")
	if tag == "":
		tag = "x"
	GameState.start_new_career(20260822)
	GameState.set_flag("tutorial_done", true)
	DirAccess.make_dir_recursive_absolute("user://faces")
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	GameState.start_day()

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 30:
		return false
	if game.ui and game.ui.has_method("close"):
		game.ui.close()
	if bodies.is_empty():
		_spawn()
		return false
	if index > WHO.size():
		print("faces done")
		return true
	# AIMED ONCE, EACH AT ITS OWN LENS. Re-aiming every subject for every shot
	# and then waiting for the neck to lerp round cost twenty-six frames a shot,
	# which on a software rasteriser is ten minutes and a harness that times out.
	if _aims.is_empty():
		for b in bodies:
			# ...AND SAY SO IF ANYBODY IS FALLING. See SPACING. A subject placed
			# off the end of the floor is photographed mid-fall and reads as a
			# modelling fault; this is the assertion I did not have.
			if b.global_position.y < -0.05:
				printerr("faces: subject at x=%.1f is not standing on anything (y=%.2f)"
					% [b.global_position.x, b.global_position.y])
			var e: Vector3 = b.head_position() + Vector3(0.26, 0.05, -0.80)
			_aims.append(e)
			b.look_toward(e)
		return false

	var cam: Camera3D = game.player.camera
	var eye: Vector3 = Vector3.ZERO
	if index < WHO.size():
		eye = _aims[index]
	else:
		eye = Vector3(CAST_AT.x, 1.60, CAST_AT.z - CAST_BACK)
		if not _cast_posed:
			_cast_posed = true
			for i in bodies.size():
				bodies[i].global_position = CAST_AT + Vector3(
					(float(i) - float(WHO.size() - 1) * 0.5) * CAST_SPACING, 0.0, 0.0)
				bodies[i].look_toward(eye)
	cam.global_position = eye
	cam.look_at(eye + Vector3(-0.26, -0.05, 0.80), Vector3.UP)
	settle += 1
	if settle < (SETTLE_CAST if index == WHO.size() else SETTLE_PORTRAIT):
		return false
	settle = 0
	var shot := "%s__%02d" % [tag, index] if index < WHO.size() else "%s__cast" % tag
	tree.root.get_texture().get_image().save_png("user://faces/%s.png" % shot)
	print("  face: ", shot)
	index += 1
	return false

func _spawn() -> void:
	for i in WHO.size():
		var b := NPCBody.new()
		b.display = ""
		b.set_look(Appearance.anyone(String(WHO[i][0]), int(WHO[i][1])))
		game.add_child(b)
		b.global_position = Vector3(FIRST_X + float(i) * SPACING, 0.0, Z)
		# AWAKE, ON THEIR FEET. Every other frame in this repo photographs people
		# asleep in beds, which hides the eyes — the one part of this model the
		# suspicion system depends on being readable, and the part that most
		# needs looking at.
		b.set_in_bed(false)
		b.set_eyes_open(true)
		bodies.append(b)
