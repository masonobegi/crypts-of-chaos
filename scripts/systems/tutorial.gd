class_name TutorialSystem
extends Node
## First-shift guidance.
##
## Deliberately teaches only the LEGITIMATE job: read a chart, look at a
## patient, treat them, file the paperwork, go home. It never mentions the other
## thing. The player is told what a good doctor does, handed a debt schedule that
## a good doctor cannot service, and left to draw their own conclusions.

const STEPS := [
	{"id": "list", "text": "Check your list. It's on the board by the treatment bay, and on your tablet [Q]."},
	{"id": "chart", "text": "Pick up a patient's chart and read it. [LMB] to grab, [E] to read."},
	{"id": "examine", "text": "Go and see them. Talk to them, then examine them — firm enough to find something."},
	{"id": "vitals", "text": "Check their vitals at the bedside monitor."},
	{"id": "treat", "text": "Treat them. The chart lists what's indicated; the supply room has the kit."},
	{"id": "records", "text": "Log it at a terminal. The nurses' station has one; so does your office."},
	{"id": "shift", "text": "See out the shift, then review your charts before you go."},
]

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
		EventBus.toast.emit("That's the job. The rest is up to you.", "info")
		return
	_show()

func _show() -> void:
	EventBus.objective_changed.emit(String(STEPS[_index]["text"]))

func is_active() -> bool:
	return _active
