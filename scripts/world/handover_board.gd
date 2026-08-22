class_name HandoverBoard
extends Fixture
## The whiteboard behind the nurses' station, and THE SECOND REASON TO BE
## SOMEWHERE.
##
## The ward already had one place worth standing — the bay terminal, in front of
## five people, as against the office with a door on it. That is a choice about
## where to be SEEN. This is a choice about where to LEARN: Adeyemi's plan for
## the day is on this board and nowhere else, so the one piece of information
## that lets you time a note against the rounds instead of guessing at them is
## twenty metres from the beds and forty from your office.
##
## What it shows is deliberately not the truth. It is what the nursing staff
## INTEND — who they expect to send home, who they are watching — which is a
## forecast written by somebody who has been on since six. It is right about the
## rounds, because those are a rota. It is only as right about the patients as
## she is.

func build() -> void:
	fixture_name = "Handover Board"
	var frame := Build.mat(Color(0.62, 0.64, 0.66))
	var face := Build.mat(Color(0.92, 0.94, 0.93), 0.6)
	setup_body(Vector3(1.9, 1.1, 0.09), [
		{"mesh": Build.box_mesh(Vector3(1.90, 1.10, 0.05)), "mat": frame, "pos": Vector3(0, 0, 0)},
		{"mesh": Build.box_mesh(Vector3(1.80, 1.00, 0.02)), "mat": face, "pos": Vector3(0, 0, 0.032)},
		{"mesh": Build.box_mesh(Vector3(1.70, 0.02, 0.01)), "mat": frame, "pos": Vector3(0, 0.36, 0.043)},
	], Vector3(0, 0, 0))
	var head := Build.label3d("WARD C — TODAY", 0.075, Color(0.15, 0.19, 0.24), false)
	head.position = Vector3(0, 0.44, 0.05)
	add_child(head)
	# The rounds are a rota and they are written up here in marker, which is the
	# only place in the game they are stated rather than inferred from the chart.
	var times := PackedStringArray()
	for r in Cases.ROUNDS:
		if int(r) < Cases.DEBT_DUE_MINUTE:
			times.append(ChartEntry._hhmm(int(r)))
	var rota := Build.label3d("rounds  " + "   ".join(times), 0.055,
		Color(0.24, 0.30, 0.36), false)
	rota.position = Vector3(0, 0.26, 0.05)
	add_child(rota)

func prompt(_player) -> Array:
	return ["Read the board", "Adeyemi's plan for the day"]

func interact(_player, _held) -> void:
	AudioMgr.play("page", -13.0)
	EventBus.request_ui.emit("board", {})
