class_name WindowUnit
extends Fixture
## An openable window. The single cheapest way to make a room uncomfortable,
## and the easiest thing in the building to blame on facilities.

var open := false
var _pane: MeshInstance3D = null

func build(width := 1.8, height := 1.2) -> void:
	fixture_name = "Window"
	var frame := Build.mat(Color(0.55, 0.58, 0.60))
	var glass := Build.mat(Color(0.55, 0.72, 0.80, 1.0), 0.15, 0.1)
	setup_body(Vector3(width, height, 0.12), [
		{"mesh": Build.box_mesh(Vector3(width, 0.08, 0.14)), "mat": frame, "pos": Vector3(0, height * 0.5, 0)},
		{"mesh": Build.box_mesh(Vector3(width, 0.08, 0.14)), "mat": frame, "pos": Vector3(0, -height * 0.5, 0)},
		{"mesh": Build.box_mesh(Vector3(0.08, height, 0.14)), "mat": frame, "pos": Vector3(-width * 0.5, 0, 0)},
		{"mesh": Build.box_mesh(Vector3(0.08, height, 0.14)), "mat": frame, "pos": Vector3(width * 0.5, 0, 0)},
	])
	_pane = Build.mi(Build.box_mesh(Vector3(width - 0.14, height - 0.14, 0.04)), glass)
	get_node("Mesh").add_child(_pane)

func prompt(_player) -> Array:
	return ["Close window" if open else "Open window",
		"the ward gets cold quickly" if not open else ""]

func interact(_player, _held) -> void:
	open = not open
	var r := room()
	if r:
		r.set_window(open, true)
	if _pane:
		_pane.rotation.y = deg_to_rad(-55.0) if open else 0.0
		_pane.position.x = 0.35 if open else 0.0
