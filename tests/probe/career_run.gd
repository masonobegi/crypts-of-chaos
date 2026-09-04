extends SceneTree
## Thin runner: see gotcha #4 in CLAUDE.md.
##
## AND IT EXITS WITH THE VERDICT. `quit()` with no argument exits 0, so a probe
## that printed FAILED in capital letters still told everything reading its exit
## code that it had passed — the same shape of bug as `check.sh` not failing on
## a parse error, and the reason neither of these was in `run_tests.sh`.
func _initialize() -> void:
	var i = load("res://tests/probe/career_impl.gd").new()
	i.tree = self
	quit(0 if i.run() else 1)
