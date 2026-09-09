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

## Every morning is a different ward, and the board is rewritten with it.
const BOARD_GROUP := "handover_board"
var _head: Label3D = null

## Called from `Hospital.reskin`. The board is a Fixture with collision and a
## navigation footprint, so unlike the dressing it cannot be thrown away and
## rebuilt between wards — the one thing on it that names the ward is a label,
## and a label can simply be rewritten.
func rename_for_ward() -> void:
	if _head != null:
		_head.text = "%s — TODAY" % Cases.ward_name().to_upper()

func build() -> void:
	fixture_name = "Handover Board"
	var frame := Build.mat(Color(0.62, 0.64, 0.66))
	var face := Build.mat(Color(0.92, 0.94, 0.93), 0.6)
	setup_body(Vector3(1.9, 1.1, 0.09), [
		{"mesh": Build.box_mesh(Vector3(1.90, 1.10, 0.05)), "mat": frame, "pos": Vector3(0, 0, 0)},
		{"mesh": Build.box_mesh(Vector3(1.80, 1.00, 0.02)), "mat": face, "pos": Vector3(0, 0, 0.032)},
		{"mesh": Build.box_mesh(Vector3(1.70, 0.02, 0.01)), "mat": frame, "pos": Vector3(0, 0.36, 0.043)},
	], Vector3(0, 0, 0))
	# WHICHEVER WARD IT IS. This said WARD C in marker on the station's own
	# whiteboard on every night of every career, and the smoke run's sign check
	# could not see it because the check matched "Ward" and the board shouts.
	_head = Build.label3d("%s — TODAY" % Cases.ward_name().to_upper(), 0.075,
		Color(0.15, 0.19, 0.24), false)
	_head.position = Vector3(0, 0.44, 0.05)
	add_child(_head)
	add_to_group(BOARD_GROUP)
	# The rounds are a rota and they are written up here in marker, which is the
	# only place in the game they are stated rather than inferred from the chart.
	var times := PackedStringArray()
	for r in Cases.ROUNDS:
		if int(r) < Cases.DEBT_DUE_MINUTE:
			times.append(ChartEntry._hhmm(int(r)))
	# IN MARKER, and now it looks like it. The comment above has claimed this
	# since the board was built; the letters were a bold grotesque like every
	# other sign in the building, which made a whiteboard somebody scribbles on
	# every morning read as a printed timetable.
	var rota := Build.label3d("rounds  " + "   ".join(times), 0.062,
		Color(0.24, 0.30, 0.36), false, Typeface.hand())
	rota.position = Vector3(0, 0.26, 0.05)
	add_child(rota)

func prompt(_player) -> Array:
	return ["Read the board", "Adeyemi's plan for the day"]

func interact(_player, _held) -> void:
	AudioMgr.play("page", -13.0)
	EventBus.request_ui.emit("board", {})
