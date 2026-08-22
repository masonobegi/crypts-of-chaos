extends SceneTree
var impl = null
func _initialize() -> void:
	var s: GDScript = load("res://tests/tmpprobe/vimpl.gd")
	if s == null or not s.can_instantiate():
		printerr("vimpl failed to compile"); quit(1); return
	impl = s.new()
	impl.tree = self
	impl.run()
	quit(0)
