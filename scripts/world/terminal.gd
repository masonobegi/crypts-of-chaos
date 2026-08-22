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
	var w = get_tree().get_first_node_in_group("ward_day")
	if _is_the_office() and w != null and not w.ended:
		var p: Dictionary = w.projected()
		return ["Go home", "%s against %s owed  ·  she still rounds till eight" % [
			UIKit.money_str(int(p["total"])), UIKit.money_str(w.debt_tonight)]]
	var sub := "in full view of the ward" if not is_private \
		else "door's shut. nobody's looking."
	return ["Read the ward's notes", sub]

## THE DAY ENDS IN A SPECIFIC ROOM WITH A DOOR ON IT.
##
## Not a clock running out and not a button on a screen. Walking to your own
## office to sign off is the last decision of the shift, and it is made in the
## room where the records are, which is where it belongs — and it means "go and
## fix one more thing first" is a real errand with a real way back.
func _is_the_office() -> bool:
	return mode == "admin" and is_private

func interact(_player, _held) -> void:
	AudioMgr.play("beep", -12.0)
	var w = get_tree().get_first_node_in_group("ward_day")
	if w == null:
		return
	if _is_the_office() and not w.ended:
		# Anybody you never made a decision about goes home. Nursing is not
		# going to keep a bed occupied because you did not get round to it.
		for c in Cases.roster():
			var pid := String(c["id"])
			if String(w.state[pid]["disposition"]) == "":
				w.set_disposition(pid, "discharge")
		w.end_day()
		EventBus.request_ui.emit("review", {})
		return
	# Any other terminal is somewhere to read from, and somewhere to be seen
	# reading from.
	EventBus.request_ui.emit("records", {})

