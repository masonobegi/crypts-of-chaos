class_name TutorialSystem
extends Node
## What a stranger is told, and what they are deliberately not told.
##
## The old tutorial had eight steps and taught somebody to be a competent honest
## doctor. It never mentioned the arithmetic that the game is actually about, so
## a player finished it having never encountered the premise on the store page.
##
## This one has three lines. It teaches where the chart is, that entries carry
## the time they were written, and that there is a number owed at eight o'clock.
## It does not suggest what to do about any of that. The first two minutes of
## this game should raise a question, not answer one.

const STEPS := [
	{
		"id": "read", "line": "Five beds. Read somebody's chart before you decide anything.",
		"done": "chart_opened",
	},
	{
		"id": "clock", "line": "Every note records when it was written, as well as when it happened.",
		"done": "entry_written",
	},
	{
		"id": "owed", "line": "Vinnie wants three thousand two hundred by eight. You have nine hundred.",
		"done": "disposition_set",
	},
]

var _index := 0
var _active := true

func _ready() -> void:
	add_to_group("tutorial")
	if GameState.flag("tutorial_done", false):
		_active = false
		return
	EventBus.request_ui.connect(_on_ui)
	call_deferred("_say")

func _say() -> void:
	if not _active or _index >= STEPS.size():
		return
	EventBus.toast.emit(String(STEPS[_index]["line"]), "info")

func note(what: String) -> void:
	if not _active or _index >= STEPS.size():
		return
	if String(STEPS[_index]["done"]) != what:
		return
	_index += 1
	if _index >= STEPS.size():
		_active = false
		GameState.set_flag("tutorial_done", true)
		return
	_say()

func _on_ui(id: String, _ctx: Dictionary) -> void:
	if id == "chart":
		note("chart_opened")
