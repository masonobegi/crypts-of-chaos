extends RefCounted
## Boot the real game and walk one day through it.
##
## The old smoke run was 1,000 lines covering shifts, treatments, machines,
## investigations, the street and a save round-trip. This one asks the four
## questions a vertical slice has to answer in the actual scene tree rather than
## in isolation: does it build, are the five people in the five beds, does
## writing in a chart work through the real systems, and does the day close.

var tree: SceneTree = null
var game: Node = null
var frames := 0
var stage := "boot"
var errors: Array[String] = []
var notes: Array[String] = []

func start() -> void:
	print("\n=== SMOKE RUN ===\n")
	GameState.start_new_career(20260821)
	GameState.set_flag("tutorial_done", true)
	GameState.set_flag("headless_sim", true)
	var packed: PackedScene = load("res://scenes/Game.tscn")
	if packed == null:
		_fail("Game.tscn failed to load")
		return
	game = packed.instantiate()
	tree.root.add_child(game)

func tick() -> bool:
	frames += 1
	tree.paused = false
	match stage:
		"boot":
			if frames > 8:
				_check_the_building()
				_check_the_ward()
				stage = "work"
		"work":
			_check_the_chart_works()
			_check_the_verbs_work()
			stage = "close"
		"close":
			_check_the_day_closes()
			stage = "done"
		"done":
			_report()
			return true
	if frames > 600:
		_fail("smoke run stuck in '%s'" % stage)
		_report()
		return true
	return false

func _check_the_building() -> void:
	var h = tree.get_first_node_in_group("hospital")
	_ok(h != null, "the hospital builds")
	if h == null:
		return
	var rooms: Array = h.room_list()
	_ok(rooms.size() >= 3, "and has the rooms the slice needs (%d)" % rooms.size())
	_ok(tree.get_first_node_in_group("player") != null, "the player exists")
	_ok(tree.get_first_node_in_group("ward_day") != null, "the day exists")

## Five written people, in five beds, with names.
func _check_the_ward() -> void:
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		_fail("no patient system")
		return
	_ok(ps.active().size() == Cases.ROSTER.size(),
		"all %d patients are on the ward" % Cases.ROSTER.size())
	var named := 0
	var bodied := 0
	for p in ps.active():
		if p.display_name != "":
			named += 1
		var b = ps.get_body(p.id)
		if b != null and b.is_inside_tree():
			bodied += 1
	_ok(named == ps.active().size(), "every one of them has a name")
	_ok(bodied == ps.active().size(), "and a body somebody could walk up to")

## The four verbs, through the real WardDay in the real tree.
func _check_the_chart_works() -> void:
	var w = tree.get_first_node_in_group("ward_day")
	if w == null:
		return
	var before: int = w.records.for_patient("oduya").size()
	w.advance_to(19 * 60 + 30)
	var e = w.write_entry("oduya", ChartEntry.Claim.UNWELL,
		"Reports transient dizziness on standing.", 19 * 60 + 10)
	_ok(w.records.for_patient("oduya").size() > before, "a note can be written")
	_ok(e.written_minute > e.stated_minute,
		"and it records both when it happened and when it was typed")
	_ok(e.backdated_by() == 20, "and knows the gap between them exactly")

func _check_the_verbs_work() -> void:
	var w = tree.get_first_node_in_group("ward_day")
	if w == null:
		return
	var n = w.nurse_check("marchetti")
	_ok(n != null and n.author == ChartEntry.Author.NURSE,
		"a nurse can be asked to look, and writes in her own name")
	_ok(n.supports_stay(),
		"and about the patient who is genuinely unwell, she agrees with you")
	var o = w.order_test("oduya", "lying and standing BP")
	w.advance_to(21 * 60 + 30)
	var r = w.resolve_test(o)
	_ok(r.claim == ChartEntry.Claim.RESULT_NORMAL,
		"a test on somebody who is well comes back normal, whatever you wanted")
	_ok(o.fulfilled_by == r.id, "and the order is answered by it")

func _check_the_day_closes() -> void:
	var w = tree.get_first_node_in_group("ward_day")
	if w == null:
		return
	w.set_disposition("marchetti", "hold")
	w.set_disposition("oduya", "hold")
	for id in ["kerrigan", "brennan", "blake"]:
		w.set_disposition(id, "discharge")
	var res: Dictionary = w.end_day()
	_ok(not res.is_empty(), "the day ends")
	_ok(int(res["earned"]) > 0, "and pays something (%s)" % str(res["earned"]))
	var f: Array = res["findings"]
	_ok(f.size() > 0, "and the reviewer has something to ask about (%d findings)" % f.size())
	var rv := ReviewSystem.new()
	rv.begin(f)
	var asked := 0
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.STAND_BY, res["held"])
		asked += 1
	_ok(asked > 0, "the handover asks at least one question")
	var o := rv.outcome()
	_ok(String(o["because"]).length() > 10,
		"and the outcome always names what caused it")

func _fail(msg: String) -> void:
	errors.append(msg)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		notes.append("  ok: " + msg)
	else:
		errors.append(msg)

func _report() -> void:
	for n in notes:
		print(n)
	print("\n--------------------------------------")
	if errors.is_empty():
		print("SMOKE RUN PASSED — %d checks" % notes.size())
	else:
		print("SMOKE RUN FAILED — %d problem(s):" % errors.size())
		for e in errors:
			print("  " + e)
	print("--------------------------------------\n")
