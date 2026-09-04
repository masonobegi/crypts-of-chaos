extends SceneTree
## Thin runner. Autoloads are not resolvable at compile time from a `--script`
## main loop (CLAUDE.md 4), so the implementation is loaded at runtime.
var _i = null
func _initialize() -> void:
	_i = load("res://tests/look_impl.gd").new()
	_i.tree = self
	_i.start()
func _process(_d: float) -> bool:
	if _i.tick():
		quit(0)
	return false
