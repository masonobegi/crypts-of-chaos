extends RefCounted
## THREE VANTAGES, RENDERED FAST.
##
## `shot_impl.gd` photographs twenty-one frames and measures two layouts, which
## is the right thing to run before a commit and the wrong thing to run in a
## loop: on a software rasteriser it is twenty minutes, and a shader, a light or
## a line weight wants a picture back in ninety seconds. This is the ward wide,
## a bedside and the corridor, and nothing else.
##
## `LOOK_TAG` names the set so two runs can be compared side by side.
var tree: SceneTree = null
var game: Node = null
var frames := 0
var si := 0
var settle := 0
var out_dir := "user://look"
var tag := "x"

## AT EYE HEIGHT, ALL THREE. The wide vantage used to sit at 2.6m — 0.65m below
## a 3.25m ceiling — which is a good establishing frame for a store page and a
## terrible one to tune a shader from, because it is a view no player can ever
## stand in. Judged from up there the ceiling fills the top half of the frame at
## a near-grazing angle, its 0.6m grid fans out from the vanishing point into
## broad diagonals, and those diagonals have now been blamed on the sun's shadow
## map, on the tile runner being too strong, and on noise aliasing. They are
## none of those: they are the grid, drawn correctly, seen from an impossible
## place. `screenshots.sh` keeps the high wide shot; the tuning loop does not.
const SHOTS := [
	["wide", Vector3(2.0, 1.7, 6.0), Vector3(14.0, 1.3, 11.5)],
	["bedside", Vector3(9.0, 1.7, 9.2), Vector3(11.0, 1.15, 11.8)],
	["corridor", Vector3(1.5, 1.7, 2.0), Vector3(18.0, 1.5, 2.0)],
	# THE LINEUP. Five people side on, which is the only frame that answers "do
	# these read as five people". Character work was being judged from a
	# twenty-minute `screenshots.sh` run, which is the wrong loop for it: the
	# first pass at head variation shipped with three of the five patients
	# drawing a hairstyle that is invisible from the front, and one render at
	# the right vantage would have said so.
	#
	# Placed like `shot_impl`'s: the mean of the heads, back five and a half
	# metres, at their own height. Resolved at shoot time, so it follows
	# whichever ward the seed dealt.
	["lineup", Vector3.ZERO, Vector3.ZERO],
]

func start() -> void:
	tag = OS.get_environment("LOOK_TAG")
	if tag == "":
		tag = "x"
	GameState.start_new_career(20260822)
	GameState.set_flag("tutorial_done", true)
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	GameState.start_day()

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 30:
		return false
	if si >= SHOTS.size():
		print("look done")
		return true
	if game.ui and game.ui.has_method("close"):
		game.ui.close()
	var cam: Camera3D = game.player.camera
	var shot: Array = SHOTS[si]
	if String(shot[0]) == "lineup":
		if not _aim_lineup(cam):
			print("  look: lineup — nobody on the ward")
			si += 1
			return false
	else:
		cam.global_position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
	settle += 1
	if settle < 4:
		return false
	settle = 0
	var img := tree.root.get_texture().get_image()
	img.save_png("%s/%s__%s.png" % [out_dir, tag, String(shot[0])])
	print("  look: ", String(shot[0]))
	si += 1
	return false

## Point the camera at the ward's five, from the foot of the beds. Returns false
## if the ward has not populated yet, which is a caller's problem and not a
## reason to abort the whole set.
func _aim_lineup(cam: Camera3D) -> bool:
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		return false
	var heads: Array = []
	for c in Cases.roster():
		var body = ps.get_body(String(c["id"]))
		if body != null and body.is_inside_tree():
			heads.append(body.head_position())
	if heads.is_empty():
		return false
	var mid := Vector3.ZERO
	for hp in heads:
		mid += hp
	mid /= float(heads.size())
	cam.global_position = Vector3(mid.x, mid.y + 0.25, mid.z - 5.4)
	cam.look_at(Vector3(mid.x, mid.y - 0.10, mid.z), Vector3.UP)
	return true
