extends SceneTree
## Thin runner: see gotcha #4 in CLAUDE.md. Exits non-zero when a success
## criterion regresses, so run_tests.sh can fail on a design regression and not
## just on a crash.
func _initialize() -> void:
	var i = load("res://tests/playtest_impl.gd").new()
	i.tree = self
	i.run()
	quit(1 if i.failed else 0)
