class_name RecordsTerminal
extends Fixture
## The EHR. Where charting, billing, complication filing, facilities tickets and
## discharge paperwork happen — i.e. where most of the actual crime happens.
##
## Terminals know WHERE they are, and that matters: editing records from the
## nurses' station in front of three people is not the same act as doing it in
## your office with the door shut.

@export var mode := "ehr"     ## ehr|admin|billing
@export var is_private := false

func build(disp: String, private: bool) -> void:
	fixture_name = disp
	is_private = private
	var case_mat := Build.mat(Color(0.24, 0.26, 0.30))
	var screen := Build.mat(Color(0.08, 0.14, 0.12), 0.15, 0.0, Color(0.08, 0.30, 0.24))
	setup_body(Vector3(0.66, 0.62, 0.36), [
		{"mesh": Build.box_mesh(Vector3(0.62, 0.42, 0.05)), "mat": case_mat, "pos": Vector3(0, 0.75, 0)},
		{"mesh": Build.box_mesh(Vector3(0.56, 0.36, 0.01)), "mat": screen, "pos": Vector3(0, 0.75, 0.031)},
		{"mesh": Build.box_mesh(Vector3(0.14, 0.2, 0.12)), "mat": case_mat, "pos": Vector3(0, 0.5, 0)},
		{"mesh": Build.box_mesh(Vector3(0.4, 0.02, 0.16)), "mat": Build.mat(Color(0.4, 0.42, 0.45)), "pos": Vector3(0, 0.4, 0.25)},
	], Vector3(0, 0.6, 0))

	var glow := Build.label3d("EHR", 0.06, Color(0.4, 1.0, 0.8), false)
	glow.position = Vector3(0, 0.93, 0.04)
	add_child(glow)

func prompt(_player) -> Array:
	if _going_home():
		return ["Finish the shift", "sign off and go home"]
	if _can_call_it_a_day():
		return ["Call it a day", "anyone you have not seen gets seen by nursing"]
	var sub := "in full view of the ward" if not is_private else "door's shut. nobody's looking."
	return ["Use terminal", sub]

## After the chart review, this is how the day ends.
##
## It used to end at a button on a screen that the screen's OTHER button freed
## forever. Ending the shift at a terminal, in the world, means "go and fix
## something first" is a real errand with a real way back — and it puts the last
## act of the day in the room where the records are, which is where it belongs.
func _going_home() -> bool:
	return GameState.phase == GameState.Phase.CHART_REVIEW and mode == "admin"

## Ending the day is a walk to your office rather than a clock running out.
##
## It makes the round a thing you choose the shape of: see five patients
## properly, see one and spend the day on them, or see nobody and let nursing
## have the whole ward. The clock is still there as a backstop, but the decision
## is now yours and it is made in a specific room with a door on it.
func _can_call_it_a_day() -> bool:
	if mode != "admin" or not is_private:
		return false
	var ss = get_tree().get_first_node_in_group("shift_system")
	return ss != null and ss.can_end_day()

func interact(_player, _held) -> void:
	AudioMgr.play("beep", -12.0)
	if _going_home():
		var ss = get_tree().get_first_node_in_group("shift_system")
		if ss != null:
			ss.clock_out()
		return
	if _can_call_it_a_day():
		var ss2 = get_tree().get_first_node_in_group("shift_system")
		if ss2 != null:
			ss2.end_shift(true)
		return
	EventBus.request_ui.emit("records", {
		"mode": mode, "private": is_private, "room": room_key,
		"position": global_position,
	})
