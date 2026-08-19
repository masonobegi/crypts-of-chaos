extends SceneTree
## Scripted playthrough. Drives the REAL player controller through the REAL
## input actions over real frames, and photographs what a player would see.
##
##   xvfb-run -a godot --rendering-method gl_compatibility --fixed-fps 60 \
##       --path . --script res://tests/play_run.gd -- <script_name>
##
## Thin runner: autoloads are not resolvable at compile time from a --script
## main loop, so the implementation is loaded at runtime. Same reason as
## smoke_run.gd and live_run.gd.

var impl = null

func _initialize() -> void:
	var script: GDScript = load("res://tests/play_impl.gd")
	impl = script.new()
	impl.tree = self
	var args := OS.get_cmdline_user_args()
	impl.plan_name = String(args[0]) if args.size() > 0 else "first_shift"
	impl.start()

func _process(_delta: float) -> bool:
	return impl.tick()
