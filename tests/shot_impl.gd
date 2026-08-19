extends RefCounted
## Screenshot harness. Boots the real game and photographs it from a set of
## fixed vantage points, so the procedural world can be eyeballed without a
## human having to sit in front of it.

var tree: SceneTree = null
var game: Node = null
var frames := 0
var index := 0
var settle := 0
var out_dir := "user://shots"

## name, position, look-at
func _set_ceilings_visible(v: bool) -> void:
	if game == null or game.hospital == null:
		return
	for r in game.hospital.room_list():
		for c in r.get_children():
			# Ceilings are the only bare MeshInstance3D parented to a Room.
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = v

const SHOTS := [
	["01_lobby", Vector3(5.5, 1.7, -4.0), Vector3(5.5, 1.5, 2.0)],
	["02_corridor_west", Vector3(3.0, 1.7, 2.0), Vector3(40.0, 1.5, 2.0)],
	["03_corridor_east", Vector3(40.0, 1.7, 2.0), Vector3(3.0, 1.5, 2.0)],
	["04_ward_101", Vector3(4.5, 1.7, 5.5), Vector3(4.0, 1.2, 11.0)],
	["05_nurses_station", Vector3(15.0, 1.7, -1.5), Vector3(15.0, 1.2, -7.0)],
	["06_treatment_bay", Vector3(24.0, 1.7, -2.0), Vector3(24.0, 1.3, -9.0)],
	["07_supply", Vector3(32.0, 1.7, -2.0), Vector3(31.0, 1.3, -8.0)],
	["08_office", Vector3(43.0, 1.7, -2.5), Vector3(43.0, 1.2, -8.5)],
	["09_ward_105", Vector3(41.5, 1.7, 5.5), Vector3(41.0, 1.2, 11.0)],
	["10_overview", Vector3(23.0, 22.0, 24.0), Vector3(23.0, 0.0, 1.0)],
]

func start() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.start_new_career(20260819)
	# Skip the first-run tutorial; its dim overlay darkens every shot.
	GameState.set_flag("tutorial_done", true)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)

func tick() -> bool:
	frames += 1
	tree.paused = false
	if game == null or game.player == null:
		return frames > 60
	# The briefing screen opens on day one and pauses the tree; close whatever
	# modal is up so the camera is photographing the world, not an overlay.
	if game.ui != null and game.ui.current != null:
		game.ui.close()
		return false
	if frames < 45:
		return false
	if index >= SHOTS.size():
		print("captured %d frames to %s" % [SHOTS.size(), ProjectSettings.globalize_path(out_dir)])
		return true

	var shot: Array = SHOTS[index]
	var cam: Camera3D = game.player.camera
	cam.global_position = shot[1]
	cam.look_at(shot[2], Vector3.UP)
	# The overview is shot from above, so the ceilings have to come off.
	var overview := index == SHOTS.size() - 1
	cam.fov = 60.0 if overview else 78.0
	_set_ceilings_visible(not overview)

	settle += 1
	if settle < 4:
		return false
	settle = 0
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, String(shot[0])]
	img.save_png(path)
	print("  shot: ", ProjectSettings.globalize_path(path))
	index += 1
	return false
