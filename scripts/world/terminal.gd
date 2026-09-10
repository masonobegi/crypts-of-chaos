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
	# ITS ORIGIN IS ITS FOOT. Every part used to be measured from a floating
	# point somewhere inside the case, so the lowest thing on the model — the
	# keyboard tray — sat 0.39 above the origin, and all three callers placed
	# the origin by eye. The ward and office machines hovered nineteen
	# centimetres over their desks and the station one was buried in the
	# counter. Now a caller passes the height of the surface it stands on and
	# nobody has to know how a computer is put together.
	#
	# Same rule as `Dressing._add()` and its own depth. The piece knows its
	# shape; the room knows where the shape goes.
	setup_body(Vector3(0.66, 0.62, 0.36), [
		{"mesh": Build.box_mesh(Vector3(0.62, 0.42, 0.05)), "mat": case_mat, "pos": Vector3(0, 0.36, 0)},
		{"mesh": Build.box_mesh(Vector3(0.56, 0.36, 0.01)), "mat": screen, "pos": Vector3(0, 0.36, 0.031)},
		{"mesh": Build.box_mesh(Vector3(0.14, 0.2, 0.12)), "mat": case_mat, "pos": Vector3(0, 0.11, 0)},
		{"mesh": Build.box_mesh(Vector3(0.4, 0.02, 0.16)), "mat": Build.mat(Color(0.4, 0.42, 0.45)), "pos": Vector3(0, 0.01, 0.25)},
	], Vector3(0, 0.21, 0))

	# SOMETHING ON THE SCREEN.
	#
	# The terminal is the object this whole game is about — every note in it is
	# typed at one — and it rendered as a flat dark-green rectangle with the
	# word EHR floating at its top edge. A blank screen on the one machine the
	# player spends the day at reads as a prop that was never finished.
	#
	# BARS, NOT TEXT, for the reason `Dressing.poster` gives: real words on a
	# screen are a promise the game has to keep, because a player will walk up
	# and read them, and a ward list that has to stay in step with the ward is a
	# second copy of the roster. Bars read as a list of names at the distance
	# anybody sees this from, and they cannot go stale.
	#
	# No ink on any of it (line 0.0): at 2cm a bar is mostly outline, which is
	# gotcha 46, and a cel line around a glowing pixel is not what a screen does.
	var glow := Build.label3d("EHR", 0.045, Color(0.45, 1.0, 0.85), false,
		Typeface.mono_bold())
	glow.position = Vector3(0, 0.505, 0.038)
	add_child(glow)
	var rule := Build.mat(Color(0.10, 0.42, 0.34), 0.2, 0.0, Color(0.10, 0.42, 0.34), 0.0)
	var row := Build.mat(Color(0.09, 0.34, 0.28), 0.2, 0.0, Color(0.09, 0.34, 0.28), 0.0)
	var lit := Build.mat(Color(0.30, 0.88, 0.70), 0.2, 0.0, Color(0.30, 0.88, 0.70), 0.0)
	add_child(Build.mi(Build.box_mesh(Vector3(0.48, 0.004, 0.004)), rule,
		Vector3(0, 0.478, 0.038)))
	# Seven rows, one of them selected, and a caret on the row under it. The
	# widths come off a sine so the list has the ragged right edge a list of
	# names has rather than the block a loop with one width produces.
	for i in 7:
		var t: float = float(i)
		var w: float = 0.20 + 0.24 * (0.5 + 0.5 * sin(t * 2.3))
		var y: float = 0.446 - t * 0.036
		var sel: bool = i == 3
		if sel:
			add_child(Build.mi(Build.box_mesh(Vector3(0.50, 0.026, 0.003)), row,
				Vector3(0, y, 0.037)))
		add_child(Build.mi(Build.box_mesh(Vector3(w, 0.011, 0.004)),
			lit if sel else row, Vector3(-0.24 + w * 0.5, y, 0.039)))
		# A short second column, which is what makes it read as a TABLE — a
		# left-aligned stack of bars alone reads as a paragraph.
		add_child(Build.mi(Build.box_mesh(Vector3(0.055, 0.011, 0.004)),
			lit if sel else row, Vector3(0.205, y, 0.039)))
	add_child(Build.mi(Build.box_mesh(Vector3(0.012, 0.018, 0.004)), lit,
		Vector3(-0.232, 0.194, 0.039)))

func prompt(_player) -> Array:
	var w = get_tree().get_first_node_in_group("ward_day")
	if _is_the_office() and w != null and not w.ended:
		var p: Dictionary = w.projected()
		# THE SAME FOUR WORDS EVERYWHERE. The crosshair said "Go home", the
		# objective banner says "Sign off in your office before eight", and the
		# screen it opens is headed WARD RECORDS with a "Sign off" button
		# somewhere down it — three names for one act, on the one act a player
		# has to find without being told where it is.
		return ["Sign off for the night", "%s against %s owed  ·  she still rounds till eight" % [
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

