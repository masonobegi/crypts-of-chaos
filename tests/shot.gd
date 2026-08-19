extends SceneTree
## Screenshot entry point (thin — autoloads are not resolvable at compile time
## from a --script main loop).
##   xvfb-run godot --rendering-method gl_compatibility --path . --script res://tests/shot.gd

var impl = null
var started := false

func _initialize() -> void:
	var script: GDScript = load("res://tests/shot_impl.gd")
	if script == null or not script.can_instantiate():
		printerr("shot_impl.gd failed to compile")
		quit(1)
		return
	impl = script.new()
	impl.tree = self

func _process(_delta: float) -> bool:
	if impl == null:
		quit(1)
		return true
	if not started:
		started = true
		impl.start()
		return false
	if impl.tick():
		quit(0)
		return true
	return false
