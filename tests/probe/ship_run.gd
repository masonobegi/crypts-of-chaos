extends SceneTree
## Thin runner: see gotcha #4 in CLAUDE.md — autoloads are not resolvable at
## compile time from a `--script` main loop, so the implementation is load()ed.
##
##   godot --headless --path . --script res://tests/probe/ship_run.gd
##
## `quit()` WITH AN ARGUMENT. A runner that calls quit() bare exits 0 whatever it
## just printed, which is gotcha 21's shape and the reason `check.sh` was green on
## every parse error it had ever reported.

var impl = null

func _initialize() -> void:
	print("\n=== SHIPPABLE? ===")
	var script: GDScript = load("res://tests/probe/ship_impl.gd")
	if script == null or not script.can_instantiate():
		printerr("ship_impl.gd failed to compile")
		quit(1)
		return
	impl = script.new()
	impl.tree = self
	impl.start()

func _process(_delta: float) -> bool:
	if impl == null:
		quit(1)
		return true
	if impl.tick():
		print("\n%s — %d checks, %d failed\n"
			% ["SHIP CHECK PASSED" if impl.bad == 0 else "SHIP CHECK FAILED",
				impl.checks, impl.bad])
		quit(1 if impl.bad > 0 else 0)
		return true
	return false
