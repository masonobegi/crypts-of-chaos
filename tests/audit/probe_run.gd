extends SceneTree
func _initialize() -> void:
	var i = load("res://tests/audit/probe_impl.gd").new(); i.tree = self; i.run(); quit()
