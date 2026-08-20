class_name Typewriter
extends Node
## Reveals a Label's text a character at a time, with a voice blip as it goes.
##
## Talking to somebody was a subtitle that appeared complete and vanished on a
## timer, which is why it "goes so quick": there is nothing to read AT, no
## control over the pace, and no sense that a person is saying it. Text that
## arrives at the speed of speech, with a voice under it, and a click to hurry
## it along, is the difference between a line of text and a conversation.
##
## Deliberately a plain Node driving somebody else's Label rather than a widget:
## every screen in this project builds its own layout, and this has to work
## inside all of them.

signal finished()

## Characters per second. Roughly conversational; hurried by clicking.
const SPEED := 42.0
## One blip every N characters. Every character is a machine gun.
const BLIP_EVERY := 3

var voice := ""

var _label: Label = null
var _full := ""
var _shown := 0.0
var _running := false
var _blip_at := 0

func _ready() -> void:
	set_process(true)

## Begin revealing `text` into `label`.
func speak(label: Label, text: String, voice_id := "") -> void:
	_label = label
	_full = text
	voice = voice_id
	_shown = 0.0
	_blip_at = 0
	_running = true
	if _label != null:
		_label.text = ""
		_label.visible_characters = -1

func is_running() -> bool:
	return _running

## Click once to finish the line instantly. Returns true if it did something,
## so the caller can tell "hurry up" apart from "next line, please".
func hurry() -> bool:
	if not _running:
		return false
	_shown = float(_full.length())
	_apply()
	_finish()
	return true

func _process(delta: float) -> void:
	if not _running:
		return
	_shown += delta * SPEED
	_apply()
	if int(_shown) >= _full.length():
		_finish()

func _apply() -> void:
	if _label == null:
		return
	var n: int = clampi(int(_shown), 0, _full.length())
	_label.text = _full.substr(0, n)
	while _blip_at + BLIP_EVERY <= n:
		_blip_at += BLIP_EVERY
		# Spaces and punctuation are silent, which is most of what makes this
		# read as speech rather than as a printer.
		var c := _full.substr(maxi(_blip_at - 1, 0), 1)
		if c.strip_edges() != "" and not ".,!?;:-—".contains(c):
			AudioMgr.mumble(voice)

func _finish() -> void:
	_running = false
	if _label != null:
		_label.text = _full
	finished.emit()
