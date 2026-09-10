extends Node
## Tiny leveled logger.
##
## IT KEPT A RING BUFFER FOR AN IN-GAME DEBUG CONSOLE AND A BUG-REPORT DUMP,
## neither of which exists. `recent()` was the only reader of it and had no
## caller anywhere, so every line the game logged was appended to a four-hundred
## entry array that nothing would ever look at — and the docstring above
## described two features by name. Same shape as a constant nothing reads, one
## level up: the buffer had a reader, the reader had no caller, and the file
## announced a purpose for both.

enum Level { DEBUG, INFO, WARN, ERROR }

@export var min_level: Level = Level.INFO

func _ready() -> void:
	if OS.is_debug_build():
		min_level = Level.DEBUG

func d(msg: String, tag: String = "") -> void: _emit(Level.DEBUG, tag, msg)
func i(msg: String, tag: String = "") -> void: _emit(Level.INFO, tag, msg)
func w(msg: String, tag: String = "") -> void: _emit(Level.WARN, tag, msg)
func e(msg: String, tag: String = "") -> void: _emit(Level.ERROR, tag, msg)

func _emit(lv: Level, tag: String, msg: String) -> void:
	var line := "[%s]%s %s" % [Level.keys()[lv], ("[" + tag + "]") if tag != "" else "", msg]
	if lv < min_level:
		return
	if lv == Level.ERROR:
		push_error(line)
	elif lv == Level.WARN:
		push_warning(line)
	else:
		print(line)

