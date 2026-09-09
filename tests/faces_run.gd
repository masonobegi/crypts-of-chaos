extends SceneTree
## Thin runner: autoloads are not resolvable at compile time from a --script
## main loop (CLAUDE.md 4), so the implementation is loaded at runtime.
var impl = null

func _initialize() -> void:
	var script: GDScript = load("res://tests/faces_impl.gd")
	if script == null or not script.can_instantiate():
		printerr("faces_impl.gd failed to compile")
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
		quit(0)
		return true
	return false
