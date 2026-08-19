extends SceneTree
## Headless test runner.
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits non-zero on failure so this can gate a commit.
##
## NOTE: suites are pulled in with load() rather than preload(). preload resolves
## at compile time, which drags the whole class_name graph into this script's
## compilation and deadlocks the GDScript loader. Runtime load sidesteps it.

const SUITES := [
	"res://tests/test_compile.gd",
	"res://tests/test_core.gd",
	"res://tests/test_suspicion.gd",
	"res://tests/test_sim.gd",
	"res://tests/test_systems.gd",
]

var passed := 0
var failed := 0
var current := ""
var failures: Array[String] = []
var _frames := 0

## Suites run from _process, not _initialize.
##
## During _initialize the SceneTree's root Window is not yet considered "inside
## the tree", so anything added there reports is_inside_tree() == false and every
## global_position read errors. Waiting a couple of frames gives the integration
## tests a genuinely initialised tree to build the hospital in.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_run()
	return true

func _initialize() -> void:
	pass

func _run() -> void:
	_out("\n=== CHRONIC CARE — headless tests ===\n")
	for path in SUITES:
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		# A script with parse errors still load()s to a non-null GDScript, and
		# calling .new() on one HANGS the process rather than erroring. Always
		# gate on can_instantiate() before instantiating anything.
		if script == null or not script.can_instantiate():
			_out("  !! suite failed to compile: %s" % path)
			failures.append("suite failed to compile: %s" % path)
			failed += 1
			continue
		var inst: Object = script.new()
		inst.set("t", self)
		var suite_name: String = path.get_file()
		var ran := 0
		for m in inst.get_method_list():
			var n: String = m["name"]
			if not n.begins_with("test_"):
				continue
			current = "%s::%s" % [suite_name, n]
			if inst.has_method("setup"):
				inst.call("setup")
			inst.call(n)
			ran += 1
		_out("  %-24s %d tests" % [suite_name, ran])
	_out("\n--------------------------------------")
	for f in failures:
		_out("FAIL " + f)
	_out("PASSED: %d   FAILED: %d" % [passed, failed])
	_out("--------------------------------------\n")
	quit(1 if failed > 0 else 0)

func _out(s: String) -> void:
	print(s)

func ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append("[%s] %s" % [current, msg])

func eq(a, b, msg: String) -> void:
	ok(a == b, "%s  (got %s, expected %s)" % [msg, str(a), str(b)])

func near(a: float, b: float, tol: float, msg: String) -> void:
	ok(absf(a - b) <= tol, "%s  (got %f, expected %f +/- %f)" % [msg, a, b, tol])

func gt(a: float, b: float, msg: String) -> void:
	ok(a > b, "%s  (got %f, expected > %f)" % [msg, a, b])

func lt(a: float, b: float, msg: String) -> void:
	ok(a < b, "%s  (got %f, expected < %f)" % [msg, a, b])

func between(a: float, lo: float, hi: float, msg: String) -> void:
	ok(a >= lo and a <= hi, "%s  (got %f, expected %f..%f)" % [msg, a, lo, hi])
