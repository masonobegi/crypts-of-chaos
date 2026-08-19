class_name TutorialSystem
extends Node
## First-shift guidance.
##
## Deliberately teaches only the LEGITIMATE job: read a chart, look at a
## patient, treat them, file the paperwork, go home. It never mentions the other
## thing. The player is told what a good doctor does, handed a debt schedule that
## a good doctor cannot service, and left to draw their own conclusions.

const STEPS := [
	{"id": "chart", "text": "Pick up a patient's chart and read it. [LMB] to grab, [E] to read."},
	{"id": "vitals", "text": "Check their vitals at the bedside monitor."},
	{"id": "treat", "text": "Treat them. The chart lists what's indicated; the supply room has the kit."},
	{"id": "records", "text": "Log it at a terminal. The nurses' station has one; so does your office."},
	{"id": "shift", "text": "See out the shift, then review your charts before you go."},
]

var _index := 0
var _active := false

func _ready() -> void:
	add_to_group("tutorial")
	EventBus.shift_started.connect(_on_shift_started)
	EventBus.request_ui.connect(_on_ui)
	EventBus.treatment_applied.connect(func(_p, _t, _q): complete("treat"))
	EventBus.shift_ended.connect(func(_d): complete("shift"))

func _on_shift_started(day: int) -> void:
	if day > 1 or GameState.flag("tutorial_complete", false):
		return
	_active = true
	_index = 0
	_show()

func _on_ui(id: String, _ctx: Dictionary) -> void:
	match id:
		"chart": complete("chart")
		"vitals": complete("vitals")
		"records": complete("records")

func complete(step_id: String) -> void:
	if not _active or _index >= STEPS.size():
		return
	if String(STEPS[_index]["id"]) != step_id:
		return
	_index += 1
	AudioMgr.play("ding", -14.0)
	if _index >= STEPS.size():
		_active = false
		GameState.set_flag("tutorial_complete", true)
		EventBus.objective_changed.emit("")
		EventBus.toast.emit("That's the job. The rest is up to you.", "info")
		return
	_show()

func _show() -> void:
	EventBus.objective_changed.emit(String(STEPS[_index]["text"]))

func is_active() -> bool:
	return _active
