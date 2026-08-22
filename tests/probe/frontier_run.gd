extends SceneTree
## Thin runner: see gotcha #4 in CLAUDE.md.
func _initialize() -> void:
	var i = load("res://tests/probe/frontier_impl.gd").new(); i.tree = self; i.run(); quit()
