class_name TutorialSystem
extends Node
## First-shift guidance.
##
## Deliberately teaches only the LEGITIMATE job: read a chart, look at a
## patient, treat them, file the paperwork, go home. It never mentions the other
## thing. The player is told what a good doctor does, handed a debt schedule that
## a good doctor cannot service, and left to draw their own conclusions.

## `where` names the thing the step is about, so the marker can point at it.
## Resolved at run time by _target_for(), because none of it exists until the
## hospital has been built.
const STEPS := [
	{"id": "list", "where": "board",
		"text": "Check your list. It's on the board by the treatment bay, and on your tablet [Q]."},
	{"id": "chart", "where": "chart",
		"text": "Pick up a patient's chart and read it. [LMB] to grab, [E] to read."},
	{"id": "examine", "where": "patient",
		"text": "Go and see them. Talk to them, then examine them — firm enough to find something."},
	{"id": "vitals", "where": "vitals",
		"text": "Check their vitals at the bedside monitor."},
	{"id": "treat", "where": "machine",
		"text": "Treat them. The chart lists what's indicated; the supply room has the kit."},
	{"id": "records", "where": "terminal",
		"text": "Log it at a terminal. The nurses' station has one; so does your office."},
	{"id": "shift", "where": "office",
		"text": "See out the shift, then review your charts before you go."},
]

## Short label for the marker floating over the target. The objective line says
## what to do; this says what you are looking at.
const WHERE_LABEL := {
	"board": "Clinic Board",
	"chart": "Patient Chart",
	"patient": "Your Patient",
	"vitals": "Vitals Monitor",
	"machine": "Treatment Machine",
	"terminal": "Records Terminal",
	"office": "Your Office",
}

var _index := 0
var _active := false
## Steps already satisfied, whenever they happened. See complete().
var _done: Dictionary = {}

func _ready() -> void:
	add_to_group("tutorial")
	EventBus.shift_started.connect(_on_shift_started)
	# ui_opened, not request_ui: the tablet is opened straight from the input
	# handler and from the pause menu without ever going through the bus, so
	# step 1 of 6 — "check your list" — could never complete and the tutorial
	# could never advance past it.
	EventBus.ui_opened.connect(func(id): _on_ui(id, {}))
	EventBus.treatment_applied.connect(func(_p, _t, _q): complete("treat"))
	EventBus.shift_ended.connect(func(_d): complete("shift"))
	# The examination step completes on the act, not on opening the screen —
	# looking at the dial is not the same as using it, and the whole point of
	# the step is that the player has now touched the one control the rest of
	# the game is built on.
	EventBus.world_event.connect(func(e):
		if e.kind == "examination":
			complete("examine"))

func _on_shift_started(day: int) -> void:
	if day > 1 or GameState.flag("tutorial_complete", false):
		return
	_active = true
	_index = 0
	_done.clear()
	_show()

func _on_ui(id: String, _ctx: Dictionary) -> void:
	match id:
		"tablet": complete("list")
		"chart": complete("chart")
		"vitals": complete("vitals")
		"records": complete("records")

## Credit is given for the act whenever it happens, not only when the objective
## is currently asking for it.
##
## This used to drop anything out of order outright, which is the wrong shape
## for a game whose whole pitch is a sandbox: a player who walks into a room,
## examines somebody and treats them before they think to pick up the chart had
## done four of the seven steps and been credited with none of them, and the
## objective line sat there asking for something they had already done twice.
func complete(step_id: String) -> void:
	if not _active or _index >= STEPS.size():
		return
	if _done.has(step_id):
		return
	_done[step_id] = true
	var was := _index
	while _index < STEPS.size() and _done.has(String(STEPS[_index]["id"])):
		_index += 1
	if _index == was:
		return             # credited, but the objective has not moved on yet
	AudioMgr.play("ding", -14.0)
	if _index >= STEPS.size():
		_active = false
		GameState.set_flag("tutorial_complete", true)
		EventBus.objective_changed.emit("")
		EventBus.objective_target_changed.emit(Vector3.INF, "")
		EventBus.toast.emit("That's the job. The rest is up to you.", "info")
		return
	_show()

func _show() -> void:
	EventBus.objective_changed.emit(String(STEPS[_index]["text"]))
	_point_at(String(STEPS[_index].get("where", "")))

## Put the marker on whatever this step is about.
##
## Everything is looked up live rather than cached: the chart the step wants is
## whichever chart exists now, the patient is whoever is actually in a bed, and
## a step can be reached on day one or after four discharges.
func _point_at(where: String) -> void:
	var pos := _target_for(where)
	EventBus.objective_target_changed.emit(pos, String(WHERE_LABEL.get(where, "")))

func _target_for(where: String) -> Vector3:
	var tree := get_tree()
	if tree == null or where == "":
		return Vector3.INF
	var h = tree.get_first_node_in_group("hospital")
	match where:
		"board":
			for f in tree.get_nodes_in_group("fixture"):
				if f is ClinicBoard:
					return (f as Node3D).global_position + Vector3(0, 1.1, 0)
		"chart":
			for c in tree.get_nodes_in_group("chart_prop"):
				return (c as Node3D).global_position + Vector3(0, 0.4, 0)
		"patient", "vitals", "machine":
			var ps = tree.get_first_node_in_group("patient_system")
			if ps == null:
				return Vector3.INF
			# The first patient who is actually in a bed — the one every one of
			# these three steps is about.
			for p in ps.active():
				var body = ps.get_body(p.id)
				if body == null:
					continue
				if where == "patient":
					return body.global_position + Vector3(0, 1.7, 0)
				var kind := "vitals" if where == "vitals" else "machine"
				for f in tree.get_nodes_in_group("fixture"):
					if String(f.get("room_key")) != String(p.room):
						continue
					if kind == "vitals" and f is VitalsConsole:
						return (f as Node3D).global_position + Vector3(0, 0.9, 0)
					if kind == "machine" and f is TreatmentMachine:
						return (f as Node3D).global_position + Vector3(0, 1.8, 0)
				return body.global_position + Vector3(0, 1.7, 0)
		"terminal":
			for f in tree.get_nodes_in_group("fixture"):
				if f is RecordsTerminal:
					return (f as Node3D).global_position + Vector3(0, 1.3, 0)
		"office":
			if h != null and h.room("office") != null:
				return h.room("office").center() + Vector3(0, 1.6, 0)
	return Vector3.INF

func is_active() -> bool:
	return _active
