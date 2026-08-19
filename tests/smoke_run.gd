extends SceneTree
## Headless playthrough. Boots the real Game scene, runs a full shift by driving
## the clock, and checks the whole simulation actually functions end to end.
##
##   godot --headless --path . --script res://tests/smoke_run.gd
##
## This is the test that catches "everything compiles and nothing works".
##
## The logic lives in tests/smoke_impl.gd and is pulled in with a runtime load():
## autoload singletons are not resolvable at compile time from a --script main
## loop, so referencing GameState directly here fails to compile.

var impl = null

func _initialize() -> void:
	print("\n=== SMOKE RUN ===\n")
	var script: GDScript = load("res://tests/smoke_impl.gd")
	if script == null or not script.can_instantiate():
		printerr("smoke_impl.gd failed to compile")
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
		quit(1 if not impl.errors.is_empty() else 0)
		return true
	return false
