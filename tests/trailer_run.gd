extends SceneTree
## Thin runner. `trailer_impl.gd` is loaded at RUNTIME because autoloads are not
## resolvable at compile time from a `--script` main loop (gotcha 4), and every
## line of the implementation reads one.
var _i = null
func _initialize() -> void:
	_i = load("res://tests/trailer_impl.gd").new()
	_i.tree = self
	_i.start()
func _process(_d: float) -> bool:
	return _i.tick()
