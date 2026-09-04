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
	# EVERY TERMINAL OPENS THE RECORDS, INCLUDING THIS ONE.
	#
	# The office terminal used to end the shift on the keypress. A new player
	# exploring the room signed "DR. YOU" sees a computer, presses E, and every
	# patient they had not got round to is silently sent home — a scored
	# decision the ward sister audits — the day ends at whatever time it is, and
	# the handover opens. No confirmation, no warning, no way back.
	#
	# It also meant the one private machine in the building could not be used
	# for the thing the room exists for. Signing off is now a labelled button on
	# the records screen that says how many beds it is about to decide for you.
	EventBus.request_ui.emit("records", {})

