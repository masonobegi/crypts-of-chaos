extends SceneTree
## Thin runner: see gotcha #4 in CLAUDE.md.
##
## AND IT EXITS WITH THE VERDICT. `quit()` with no argument exits 0, which is
## how this probe managed to find the largest design inversion in the game and
## report it to nobody.
func _initialize() -> void:
	var i = load("res://tests/probe/econ_impl.gd").new()
	i.tree = self
	quit(0 if i.run() else 1)
