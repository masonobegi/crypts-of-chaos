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
		# BUILT FROM THE CONSTANTS. This said "three thousand two hundred"
		# against a DEBT_DUE of 2,200 — a number that was right for a balance
		# pass two reworks ago and has been wrong ever since. It is also the only
		# line in the running game that states the premise out loud, so it was
		# wrong in the one place it mattered.
		"id": "owed", "line": "", "done": "disposition_set",
	},
]

## The third line, in figures that cannot drift from the economy.
static func _owed_line() -> String:
	return "Vinnie wants %s by eight. You have %s." % [
		UIKit.money_str(Cases.DEBT_DUE), UIKit.money_str(Cases.STARTING_CASH)]

var _index := 0
var _active := true

func _ready() -> void:
	add_to_group("tutorial")
	# CONNECT ALWAYS, GATE ON STATE.
	#
	# This returned early when `tutorial_done` was set, so the signals were never
	# connected at all — and once a run has been marked done there is no way back
	# even if the flag is cleared, which is what the screenshot harness and the
	# "start again" path both do. `note()` and `_say()` already check `_active`,
	# so gating at the connection bought nothing and cost recoverability.
	_active = not GameState.flag("tutorial_done", false)
	EventBus.request_ui.connect(_on_ui)
	# THE OTHER TWO STEPS HAD NO WAY TO FIRE. `note()` had exactly one caller —
	# `_on_ui`, gated on the chart — so `_index` could only ever reach 1. Step
	# two ("every note records when it was written") was shown forever and step
	# three, the only line in the running game that states the premise, could
	# never be reached at all. `tutorial_done` was therefore never set either, so
	# a returning player was re-tutorialised every morning of their career.
	#
	# Deferred because the ward is built after this: connecting here would find
	# no WardDay in the group yet.
	call_deferred("_hook_the_ward")
	# ...AND THE FIRST LINE WAITS FOR THE BRIEFING TO CLOSE.
	#
	# There are three lines of teaching in this game. The first one — "Five
	# beds. Read somebody's chart before you decide anything." — was emitted on
	# the same frame the morning card opens, and the morning card is a
	# 700-pixel panel with five patient rows and three money figures on it.
	# Nobody reads that in six seconds.
	#
	# The toast queue no longer ages behind a card, which fixes the general
	# case, but this one deserves better than "still there when you look": the
	# player is being told what to do first, so it should arrive at the moment
	# they can do it. `start_day()` is what "Start the round" presses.
	if not GameState.day_started.is_connected(_on_day_started):
		GameState.day_started.connect(_on_day_started)

func _on_day_started(_d: int) -> void:
	_say()

func _hook_the_ward() -> void:
	var w = get_tree().get_first_node_in_group("ward_day")
	if w == null:
		return
	if w.has_signal("entry_written") and not w.entry_written.is_connected(_on_entry):
		w.entry_written.connect(_on_entry)
	if w.has_signal("disposition_set") and not w.disposition_set.is_connected(_on_disposition):
		w.disposition_set.connect(_on_disposition)

func _on_entry(_e) -> void:
	note("entry_written")

func _on_disposition(_pid, _what) -> void:
	note("disposition_set")

func _say() -> void:
	if not _active or _index >= STEPS.size():
		return
	var line := String(STEPS[_index]["line"])
	if line == "":
		line = _owed_line()
	EventBus.toast.emit(line, "info")

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
