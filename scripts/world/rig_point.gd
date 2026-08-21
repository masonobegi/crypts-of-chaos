class_name RigPoint
extends StaticBody3D
## Something on somebody's route that you can see to in advance.
##
## The `rig` act's whole point is that the act and the alibi are separated in
## time: you do this now, and the thing that matters is where you are standing
## in ninety seconds when they walk past it. Nothing here hurts anybody — it is
## a bracket loosened and a stack of boards leaned — and the street decides the
## rest.

var display := "the loose bracket"
var done := false

func build(what: String) -> void:
	display = what
	add_to_group("rig_point")
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.0, 0.9)
	cs.shape = shape
	cs.position = Vector3(0, 0.5, 0)
	add_child(cs)

	# A stack of boards with a strap round it. Reads as "somebody's job, left
	# out overnight", which is the only thing it needs to read as.
	var wood := Build.mat(Color(0.62, 0.48, 0.30), 0.9)
	for i in 4:
		add_child(Build.mi(Build.rbox_mesh(Vector3(2.1, 0.09, 0.34), 0.02), wood,
			Vector3(0, 0.07 + float(i) * 0.10, -0.18 + float(i) * 0.05),
			Vector3(0, 0.05 * float(i), 0)))
	add_child(Build.mi(Build.rbox_mesh(Vector3(0.10, 0.50, 0.44), 0.02),
		Build.mat(Color(0.22, 0.24, 0.28), 0.7), Vector3(0.6, 0.24, -0.05)))
	_glow = Build.mi(Build.sphere_mesh(0.055),
		Build.unshaded(Color(0.42, 0.92, 0.86)), Vector3(0, 0.62, 0))
	add_child(_glow)

var _glow: MeshInstance3D = null

func prompt(_player) -> Array:
	if done:
		return ["Seen to", "now be somewhere else"]
	return ["See to %s" % display, "[hold E]"]

## How long the boards take to lay. Named, because the street's layout has to be
## checked against it: the watchers' sweep has to leave a gap longer than this
## or the job cannot be done cleanly however well it is played, and a magic
## number the test has to copy is a number the test stops agreeing with.
const HOLD_SECONDS := 2.2

func use_seconds(_player, _held) -> float:
	return HOLD_SECONDS

func interact(_player, _held) -> void:
	if done:
		return
	done = true
	if _glow != null:
		_glow.visible = false
	AudioMgr.play("clatter", -16.0)
	var night = get_tree().get_first_node_in_group("night_system")
	if night != null:
		night.rigged = true
		EventBus.toast.emit(
			"Done. Now be a long way from here when they reach it.", "warn")

func display_name() -> String:
	return display
