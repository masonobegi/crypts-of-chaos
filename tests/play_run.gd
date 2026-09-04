extends SceneTree
## PLAY THE GAME WITH A CONTROLLER, OR WITH THE KEYBOARD AND MOUSE.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/play_run.gd -- pad
##
## Every other harness in this repo reaches past the input layer and calls the
## method a keypress would have called. This one presses the keys. See
## tests/play_impl.gd for what that catches and why it is a separate harness.
##
## Thin runner, loading its implementation at runtime: autoload singletons are
## not resolvable at compile time from a --script main loop (CLAUDE.md 4).

var impl = null

func _initialize() -> void:
	var plan := "pad"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		plan = String(args[0])
	print("\n=== PLAY RUN — %s ===\n" % plan)
	var script: GDScript = load("res://tests/play_impl.gd")
	if script == null or not script.can_instantiate():
		printerr("play_impl.gd failed to compile")
		quit(1)
		return
	impl = script.new()
	impl.tree = self
	impl.plan = plan
	impl.start()

func _process(_delta: float) -> bool:
	if impl == null:
		quit(1)
		return true
	if impl.tick():
		# EXPLICITLY. `quit()` with no argument is 0 whatever happened, which is
		# how a harness that cannot fail gets written (CLAUDE.md 21).
		quit(1 if not impl.errors.is_empty() else 0)
		return true
	return false
