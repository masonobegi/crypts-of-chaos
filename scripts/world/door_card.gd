class_name WardDoorCard
extends Node3D
## The card in the plastic holder beside a ward door.
##
## The corridor is sixty-two metres of identical doors. Before this it told you
## nothing whatsoever: the room number was an 8cm plate flat against the wall,
## unreadable from more than about four metres, and who was behind each door —
## which is the only thing the player actually needs to know — was available
## only by walking in, or by opening a tablet the player has to already suspect
## matters.
##
## So the building says it. Name, condition, how many nights, and a status strip
## in a colour you can read from the far end of the ward.
##
## Nothing on it is a judgement. It is exactly what a ward door card carries in
## a real hospital, and the fact that "FIT FOR DISCHARGE" in green is also the
## most tempting sentence in the game is the game's problem, not the card's.

const W := 0.54
const H := 0.34

## Clinical states, in the words a ward uses for them, with the colours a ward
## uses for them. FIT FOR DISCHARGE is not a hint; it is a fact about a person.
const STATES := {
	"empty":     {"text": "VACANT",            "col": Color(0.55, 0.58, 0.60)},
	"treating":  {"text": "UNDER TREATMENT",   "col": Color(0.38, 0.62, 0.86)},
	"improving": {"text": "IMPROVING",         "col": Color(0.42, 0.74, 0.62)},
	"fit":       {"text": "FIT FOR DISCHARGE", "col": Color(0.36, 0.80, 0.45)},
	"overdue":   {"text": "PAST EXPECTED DATE","col": Color(0.92, 0.68, 0.28)},
}

var room_key := ""
var patient_system = null

var _name_label: Label3D = null
var _cond_label: Label3D = null
var _stay_label: Label3D = null
var _state_label: Label3D = null
var _strip: MeshInstance3D = null
## This card's OWN material, not one of Build's.
##
## Build.mat() returns a shared instance out of a colour-keyed cache, which is
## exactly right for a hospital assembled from primitives and exactly wrong for
## anything that changes colour at runtime: all five cards were handed the same
## StandardMaterial3D, so every strip on the floor turned whichever colour the
## last card to refresh happened to want. The first render of this showed a card
## reading FIT FOR DISCHARGE under a blue UNDER TREATMENT strip — and it would
## equally have repainted any other object in the building built from the same
## grey.
##
## Anything that mutates a material at runtime has to own it. See _own_material.
var _strip_mat: StandardMaterial3D = null
var _last := ""
var _accum := 0.0

func build(room_number: String) -> void:
	add_to_group("door_card")
	var board := Build.box_mi(Vector3(W, H, 0.02), Color(0.93, 0.94, 0.92), Vector3.ZERO, 0.6)
	add_child(board)

	# The status strip runs the full width along the top, because a colour is
	# the only part of this a person reads at twelve metres.
	_strip = Build.box_mi(Vector3(W, 0.075, 0.026), Color(0.55, 0.58, 0.60),
		Vector3(0, H * 0.5 - 0.037, 0.004))
	_strip_mat = _own_material(_strip)
	add_child(_strip)

	var number := Build.label3d(room_number, 0.062, Color(0.16, 0.19, 0.21), false)
	number.position = Vector3(-W * 0.5 + 0.05, H * 0.5 - 0.113, 0.016)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	number.outline_size = 0
	add_child(number)

	_state_label = _line(0.030, Color(0.20, 0.23, 0.25), H * 0.5 - 0.037, true)
	_state_label.outline_size = 0
	_name_label = _line(0.040, Color(0.12, 0.14, 0.16), -0.010)
	_cond_label = _line(0.026, Color(0.32, 0.36, 0.38), -0.062)
	_stay_label = _line(0.028, Color(0.44, 0.48, 0.50), -0.108)
	refresh()

## Give a mesh instance a private copy of whatever material Build handed it, so
## writing to it cannot reach across the scene.
static func _own_material(m: MeshInstance3D) -> StandardMaterial3D:
	var shared := m.material_override as StandardMaterial3D
	if shared == null:
		return null
	var mine: StandardMaterial3D = shared.duplicate()
	m.material_override = mine
	return mine

func _line(size: float, col: Color, y: float, on_strip := false) -> Label3D:
	var l := Build.label3d("", size, col, false)
	l.position = Vector3(-W * 0.5 + 0.05, y, 0.016 if not on_strip else 0.03)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.outline_size = 0
	add_child(l)
	return l

## Polled rather than pushed. A card has to react to recovery crossing a
## threshold, to a complication, to somebody being wheeled to another room and
## to a discharge — four different systems, none of which should have to know
## that door cards exist for the corridor to stay honest.
func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0:
		return
	_accum = 0.0
	refresh()

func refresh() -> void:
	if patient_system == null:
		patient_system = get_tree().get_first_node_in_group("patient_system")
	var p = _occupant()
	var key := "%s|%s" % [p.id if p else "", _state_of(p)]
	if key == _last:
		return
	_last = key
	var st: Dictionary = STATES[_state_of(p)]
	_state_label.text = String(st["text"])
	if _strip_mat != null:
		_strip_mat.albedo_color = st["col"]
	if p == null:
		_name_label.text = "—"
		_cond_label.text = "no patient"
		_stay_label.text = ""
		return
	_name_label.text = p.display_name
	# "Acute Bilateral Opinions (Recursive)" does not fit on a door card, and a
	# label that runs off the edge of its own board reads as a rendering bug.
	var cond: String = p.condition_name()
	_cond_label.text = cond if cond.length() <= 30 else cond.substr(0, 28) + "…"
	var nights := int(round(p.days_admitted))
	_stay_label.text = "admitted today" if nights <= 0 else \
		("night 1" if nights == 1 else "night %d" % nights)

func _occupant():
	if patient_system == null:
		return null
	for p in patient_system.active():
		if p.room == room_key:
			return p
	return null

func _state_of(p) -> String:
	if p == null:
		return "empty"
	if p.is_overdue():
		return "overdue"
	if p.ready_for_discharge():
		return "fit"
	if p.recovery >= 0.6:
		return "improving"
	return "treating"
