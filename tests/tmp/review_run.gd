extends SceneTree
func _initialize() -> void:
	var i = load("res://tests/tmp/review_impl.gd").new(); i.tree = self; i.run(); quit()
