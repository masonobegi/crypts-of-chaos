extends SceneTree
## Live simulation entry point.
##   godot --headless --path . --script res://tests/live_run.gd
##
## Thin, like the other harnesses: autoloads are not resolvable at compile time
## from a --script main loop.

var impl = null

func _initialize() -> void:
	print("\n=== LIVE RUN ===\n")
	var script: GDScript = load("res://tests/live_impl.gd")
	if script == null or not script.can_instantiate():
		printerr("live_impl.gd failed to compile")
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
