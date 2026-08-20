class_name LightSwitch
extends Fixture
## Wall switch. Turning the lights off in an occupied ward is not a crime, which
## is exactly why it is useful.

var _plate: MeshInstance3D = null

func build() -> void:
	fixture_name = "Light Switch"
	setup_body(Vector3(0.16, 0.22, 0.05), [
		{"mesh": Build.box_mesh(Vector3(0.14, 0.2, 0.03)), "mat": Build.mat(Color(0.90, 0.90, 0.86))},
	])
	_plate = Build.mi(Build.box_mesh(Vector3(0.06, 0.08, 0.03)), Build.mat(Color(0.75, 0.76, 0.72)),
		Vector3(0, 0.03, 0.03))
	get_node("Mesh").add_child(_plate)

func prompt(_player) -> Array:
	var r := room()
	var on: bool = r.lights_on if r else true
	return ["Lights off" if on else "Lights on", ""]

func interact(_player, _held) -> void:
	var r := room()
	if r == null:
		return
	r.set_lights(not r.lights_on, true)
	# A switch that makes no noise is a switch you are not sure you flicked,
	# and in this game turning a ward's lights off is a deliberate act.
	AudioMgr.play_at_var("tick", global_position, -8.0, 0.7)
	if _plate:
		_plate.position.y = 0.03 if r.lights_on else -0.03
