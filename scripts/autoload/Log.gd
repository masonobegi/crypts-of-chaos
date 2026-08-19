extends Node
## Tiny leveled logger. Keeps a ring buffer so the in-game debug console and the
## bug-report dump can show recent history without spamming stdout.

enum Level { DEBUG, INFO, WARN, ERROR }

const RING_SIZE := 400

@export var min_level: Level = Level.INFO

var _ring: Array[String] = []

func _ready() -> void:
	if OS.is_debug_build():
		min_level = Level.DEBUG

func d(msg: String, tag: String = "") -> void: _emit(Level.DEBUG, tag, msg)
func i(msg: String, tag: String = "") -> void: _emit(Level.INFO, tag, msg)
func w(msg: String, tag: String = "") -> void: _emit(Level.WARN, tag, msg)
func e(msg: String, tag: String = "") -> void: _emit(Level.ERROR, tag, msg)

func _emit(lv: Level, tag: String, msg: String) -> void:
	var line := "[%s]%s %s" % [Level.keys()[lv], ("[" + tag + "]") if tag != "" else "", msg]
	_ring.append(line)
	if _ring.size() > RING_SIZE:
		_ring.remove_at(0)
	if lv < min_level:
		return
	if lv == Level.ERROR:
		push_error(line)
	elif lv == Level.WARN:
		push_warning(line)
	else:
		print(line)

func recent(n: int = 60) -> Array[String]:
	return _ring.slice(maxi(0, _ring.size() - n))
