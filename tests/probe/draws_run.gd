extends SceneTree
## Thin runner: see gotcha #4 in CLAUDE.md. Exits non-zero on failure — a probe
## in run_tests.sh whose runner always calls quit() reports every failure as a
## pass, which this one did for exactly one run.
func _initialize() -> void:
	var i = load("res://tests/probe/draws_impl.gd").new()
	i.tree = self
	i.run()
	quit(1 if int(i.bad) > 0 else 0)
