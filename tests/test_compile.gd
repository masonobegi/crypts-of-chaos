extends RefCounted
## Compiles every script in the project from source. Catches syntax and type
## errors across the whole codebase in one pass — which matters a lot when most
## of the game is built procedurally and rarely opened in an editor.
##
## A script with parse errors still load()s to a non-null (broken) GDScript, so
## null-checking is not enough. Recompiling from source is also wrong — it trips
## "hides a global script class" on everything that declares a class_name.
## can_instantiate() is the check that actually distinguishes the two.
var t

func test_all_scripts_compile() -> void:
	var files := _walk("res://scripts")
	files.append_array(_walk("res://tests"))
	t.gt(float(files.size()), 10.0, "found scripts to check")
	for f in files:
		var s: GDScript = load(f) as GDScript
		t.ok(s != null and s.can_instantiate(), "compiles: %s" % f)

func _walk(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := dir_path.path_join(n)
		# SCRATCH IS NOT THE PROJECT. `check.sh` writes `tests/_check.gd`, probes
		# get thrown into `tests/tmpcheck/`, and anything else running in the
		# repo drops its own working files — all of which this used to walk. The
		# assertion count then moved between runs (271, 273, 275, 277, all
		# green), which is a count nobody can read a regression out of. The set
		# of scripts this test checks is now a naming rule rather than whatever
		# happened to be on disk at the time.
		if n.begins_with("_") or n.begins_with("tmp") or n.begins_with("scratch"):
			n = d.get_next()
			continue
		if d.current_is_dir():
			out.append_array(_walk(full))
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out
