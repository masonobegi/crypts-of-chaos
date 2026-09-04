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

const SHOTS := [
	["wide", Vector3(2.0, 2.6, 6.0), Vector3(14.0, 1.0, 11.5)],
	["bedside", Vector3(9.0, 1.7, 9.2), Vector3(11.0, 1.15, 11.8)],
	["corridor", Vector3(1.5, 1.7, 2.0), Vector3(18.0, 1.5, 2.0)],
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
