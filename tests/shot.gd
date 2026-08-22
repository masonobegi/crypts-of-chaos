extends SceneTree
var _i = null
func _initialize() -> void:
	_i = load("res://tests/shot_impl.gd").new()
	_i.tree = self
	_i.start()
func _process(_d: float) -> bool:
	return _i.tick()
