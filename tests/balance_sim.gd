extends SceneTree
## Balance harness entry point.
##   godot --headless --path . --script res://tests/balance_sim.gd
##
## Thin, like smoke_run.gd, because autoloads are not resolvable at compile time
## from a --script main loop.

var impl = null
var started := false

func _initialize() -> void:
	var script: GDScript = load("res://tests/balance_impl.gd")
	if script == null or not script.can_instantiate():
		printerr("balance_impl.gd failed to compile")
		quit(1)
		return
	impl = script.new()
	impl.tree = self

func _process(_delta: float) -> bool:
	if impl == null:
		quit(1)
		return true
	if started:
		return false
	started = true
	impl.run_all()
	impl.report()
	quit(1 if not impl.errors.is_empty() else 0)
	return true
