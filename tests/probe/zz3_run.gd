extends SceneTree
var impl = null
func _initialize() -> void:
	impl = load("res://tests/probe/zz3_impl.gd").new(); impl.tree = self; impl.start()
func _process(_d: float) -> bool:
	if impl == null: quit(1); return true
	if impl.tick(): quit(0); return true
	return false
