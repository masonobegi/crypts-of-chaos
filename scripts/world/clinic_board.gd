class_name ClinicBoard
extends Fixture
## The day's list, on a whiteboard, on the corridor wall.
##
## The tablet already has the list. This exists because a hospital corridor with
## a board on it is a different room from one without, and because looking up
## from what you are doing and reading somebody's name off a wall is a better
## way to be reminded that a person is waiting than a line of HUD text is.
##
## It is also a record. It says who was booked, at what time, and it does not
## quietly update itself to match what actually happened — a slot nobody
## attended still has their name on it at the end of the shift, in front of
## everybody who walked past it all day.

const ROWS := 5

var _lines: Label3D = null
var _heading: Label3D = null

func build() -> void:
	fixture_name = "Clinic Board"
	var frame := Build.mat(Color(0.62, 0.64, 0.68), 0.5, 0.3)
	var face := Build.mat(Color(0.93, 0.94, 0.92), 0.85)
	setup_body(Vector3(2.6, 1.5, 0.08), [
		{"mesh": Build.box_mesh(Vector3(2.6, 1.5, 0.06)), "mat": frame},
		{"mesh": Build.box_mesh(Vector3(2.46, 1.36, 0.08)), "mat": face},
	])
	_heading = Build.label3d("TODAY", 0.075, Color(0.16, 0.18, 0.22), false)
	_heading.position = Vector3(-1.02, 0.56, 0.06)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_heading)

	_lines = Build.label3d("", 0.055, Color(0.18, 0.20, 0.26), false)
	_lines.position = Vector3(-1.14, 0.34, 0.06)
	_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lines.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_lines)

	EventBus.hour_tick.connect(func(_h): refresh())
	EventBus.shift_started.connect(func(_d): refresh())
	EventBus.phase_changed.connect(func(_p): refresh())
	# The board is built with the building, which happens before the systems
	# that fill it in exist. Connecting on the same frame silently found
	# nothing and left the board reading "nothing booked" for the whole game.
	call_deferred("_connect_roster")
	refresh()

func _connect_roster() -> void:
	var appts = get_tree().get_first_node_in_group("appointment_system")
	if appts != null and not appts.roster_changed.is_connected(refresh):
		appts.roster_changed.connect(refresh)
	refresh()

func refresh() -> void:
	if _lines == null or not is_instance_valid(_lines):
		return
	var appts = get_tree().get_first_node_in_group("appointment_system")
	if appts == null or appts.list.is_empty():
		_heading.text = "TODAY"
		_lines.text = "  nothing booked"
		return
	_heading.text = "TODAY  —  %s" % DB.shift_name(GameState.shift_kind).to_upper()
	var out := PackedStringArray()
	var shown := 0
	for a in appts.list:
		if shown >= ROWS:
			break
		shown += 1
		var mark := " "
		if bool(a["done"]):
			mark = "x"
		elif bool(a["missed"]):
			mark = "-"
		out.append("%s %02d:00  %-22s %s" % [mark, int(a["hour"]),
			String(a["name"]).substr(0, 22),
			String(AppointmentSystem.LABELS.get(String(a["kind"]), ""))])
	if appts.list.size() > ROWS:
		out.append("  ...and %d more" % (appts.list.size() - ROWS))
	_lines.text = "\n".join(out)

func prompt(_player) -> Array:
	var appts = get_tree().get_first_node_in_group("appointment_system")
	if appts == null:
		return [fixture_name, ""]
	var next: Dictionary = appts.next_due()
	if next.is_empty():
		return [fixture_name, "list cleared"]
	return [fixture_name, "next: %02d:00  %s" % [int(next["hour"]), String(next["name"])]]
