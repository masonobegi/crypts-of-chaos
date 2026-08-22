extends RefCounted
## Boot the real game and walk one day through it.
##
## The old smoke run was 1,000 lines covering shifts, treatments, machines,
## investigations, the street and a save round-trip. This one asks the four
## questions a vertical slice has to answer in the actual scene tree rather than
## in isolation: does it build, are the five people in the five beds, can the
## doctor walk over to one of them, and does the day close on what was written.
##
## Gone with the redesign: the shift loop, the machines, the supply shelves, the
## examinations, the surgeries, the overflow trolleys, the family row, the
## evening, the courtroom and the save round-trip. None of those systems exist
## to smoke any more.

var tree: SceneTree = null
var game: Node = null
var frames := 0
var stage := "boot"
var errors: Array[String] = []
var notes: Array[String] = []
## Where the doctor was standing when we told them to walk, and the physics
## frame we said it on. Walking is measured in PHYSICS frames, not idle ones:
## headless idle frames go past in microseconds and a dozen of them can pass
## without the body being stepped once, which would make this a coin toss
## rather than a test.
var _walk_from := Vector3.ZERO
var _walk_since := 0

func start() -> void:
	GameState.start_new_career(20260821)
	GameState.set_flag("tutorial_done", true)
	# NOT headless_sim. Game._spawn_ui() returns early under that flag, so `ui`
	# is null and every screen check silently passes by never running — which is
	# how a build with five invisible buttons went out with a green smoke run.
	GameState.set_flag("tutorial_done", true)
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
				_start_walking()
				stage = "walk"
		"walk":
			if Engine.get_physics_frames() - _walk_since >= 20:
				_check_the_player_can_walk()
				stage = "screens"
		"screens":
			if frames % 6 == 0 and not _check_screens_actually_draw():
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
	if frames > 6000:
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

## THE DOCTOR HAS TO BE ABLE TO GET TO THE BED.
##
## Everything else in this file is a call into a system, and a building nobody
## can cross would pass all of it. So this presses the key a player presses and
## then looks at where the body ended up — on its feet, somewhere else, and not
## through the floor.
func _start_walking() -> void:
	var p = tree.get_first_node_in_group("player")
	if p == null:
		return
	_walk_from = p.global_position
	_walk_since = Engine.get_physics_frames()
	Input.action_press("move_forward")

func _check_the_player_can_walk() -> void:
	var p = tree.get_first_node_in_group("player")
	Input.action_release("move_forward")
	if p == null:
		return
	var moved: float = p.global_position.distance_to(_walk_from)
	_ok(moved > 0.05, "the doctor walks when you ask them to (%.2fm)" % moved)
	_ok(p.global_position.y > -1.0, "and does not fall through the floor")

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
	rv.begin(f, w.records.entries, w.review_truth())
	var asked := 0
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.STAND_BY, res["held"])
		asked += 1
	_ok(asked > 0, "the handover asks at least one question")
	var o := rv.outcome()
	_ok(String(o["because"]).length() > 10,
		"and the outcome always names what caused it")

## EVERY CONTROL ON EVERY SCREEN HAS TO HAVE A SIZE.
##
## The one class of bug six suites have never been able to see. A screen whose
## body renders at zero height looks completely normal — heading, subheading,
## footer, panel — and simply has nothing in the middle of it. The redesigned
## patient card shipped with five of its six verbs invisible, the chart
## unreachable and the handover asking a question with no answers on screen, and
## everything was green, because no test had ever asked a Button how tall it was.
##
## Cheap, general, and it would have caught it in the first frame.
var _screen_queue: Array = []
var _screen_started := false

func _check_screens_actually_draw() -> bool:
	var ui = game.get("ui")
	if ui == null:
		return false
	if not _screen_started:
		_screen_started = true
		_screen_queue = [
			["morning", {}],
			["patient", {"patient_id": "oduya"}],
			["chart", {"patient_id": "oduya"}],
		]
		EventBus.request_ui.emit(String(_screen_queue[0][0]), _screen_queue[0][1])
		return true
	if _screen_queue.is_empty():
		return false
	var name := String(_screen_queue[0][0])
	var buttons: Array = []
	_collect_buttons(ui, buttons)
	# CHECK THE ANCESTORS, NOT THE BUTTON.
	#
	# The first version of this check asked each Button for its own size and
	# passed with the bug still in — a ScrollContainer CLIPS its child, it does
	# not resize it, so every invisible button reported a perfectly healthy
	# 180x28 while rendering as nothing. What makes a control unreachable is an
	# ancestor with no height, so that is what has to be measured.
	var dead: Array[String] = []
	for b in buttons:
		if b.size.y < 6.0 or b.size.x < 6.0:
			dead.append("%s (itself %.0fx%.0f)" % [b.text, b.size.x, b.size.y])
			continue
		var a: Node = b.get_parent()
		while a != null and a is Control and a != ui:
			if (a as Control).size.y < 6.0:
				dead.append("%s (inside a %s of height %.0f)" % [
					b.text, a.get_class(), (a as Control).size.y])
				break
			a = a.get_parent()
	_ok(not buttons.is_empty(), "the %s screen has controls on it" % name)
	_ok(dead.is_empty(), "and every control on %s has a size%s" % [name,
		"" if dead.is_empty() else ": " + ", ".join(dead)])
	_screen_queue.pop_front()
	if _screen_queue.is_empty():
		if ui.has_method("close"):
			ui.call("close")
		return false
	EventBus.request_ui.emit(String(_screen_queue[0][0]), _screen_queue[0][1])
	return true

func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)

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
