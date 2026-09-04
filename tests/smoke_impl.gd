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
			stage = "tomorrow"
		"tomorrow":
			_check_tomorrow_is_a_different_ward()
			_check_a_career_survives_a_save()
			stage = "chain"
		"chain":
			if _check_the_screens_chain():
				stage = "buttons"
		"buttons":
			_check_the_handover_button_reaches_tomorrow()
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
	_ok(ps.active().size() == Cases.roster().size(),
		"all %d patients are on the ward" % Cases.roster().size())
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
	# FROM HERE THE HARNESS OWNS THE CLOCK. Everything below drives the day by
	# hand to specific minutes, and the real one has been running the whole time
	# the player was being walked across the corridor — so the shift was quietly
	# hitting eight o'clock between two checks, force-discharging the entire
	# ward and closing the day, and every assertion after that was reading a
	# cached result for a day nobody played. It surfaced only when readmission
	# started reading the dispositions that force-close had written.
	GameState.clock_running = false
	# THE MORNING FIRST. `advance_to` only goes forward, so everything that
	# needs a particular hour has to happen before something walks the day past
	# it — and the registrar keeps hours.
	_check_the_new_verbs(w)
	_check_the_room_is_watching(w)
	_check_no_sign_is_mirrored()
	_check_the_crosshair_keeps_the_secret(w)
	# HEADROOM. Every verb below costs ward minutes — a note is eight, a nurse
	# review fifteen, an examination fifteen, the registrar twenty-five — and
	# from half past seven that is enough to walk the shift past eight o'clock,
	# at which point the ward force-discharges everybody and closes the day
	# under the harness. Start in the afternoon and there is room for all of it.
	var before: int = w.records.for_patient("oduya").size()
	w.advance_to(15 * 60 + 30)
	var e = w.write_entry("oduya", ChartEntry.Claim.UNWELL,
		"Reports transient dizziness on standing.", 15 * 60 + 10)
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
	# INSIDE THE DAY. This said 21:30, which is an hour and a half after the
	# ward force-ends — so `_on_minute` discharged the whole ward and closed the
	# day here, and everything below was asserting against a cached result on a
	# day that had already finished. It only surfaced when readmission started
	# reading the dispositions the force-close had written.
	w.advance_to(17 * 60 + 30)
	var r = w.resolve_test(o)
	_ok(r.claim == ChartEntry.Claim.RESULT_NORMAL,
		"a test on somebody who is well comes back normal, whatever you wanted")
	_ok(o.fulfilled_by == r.id, "and the order is answered by it")

	_check_being_seen_somewhere_else(w)

## THE CROSSHAIR MUST NOT ANSWER THE QUESTION THE SHIFT IS ABOUT.
##
## The bedside prompt appended "fit to go home" from `ready_for_discharge()`,
## which reduces to `truly_well` — so looking at each of five faces, for free,
## in zero minutes, told the player exactly who was ill. Reading a chart is
## twelve minutes and examining somebody is fifteen; the entire design is that a
## twelve-hour day cannot afford all of it. Every measurement this project has
## ever taken was of a game whose central question could be answered by walking
## down the row, and not one of 273 assertions noticed.
##
## So: for every patient on the ward, the world prompt must read the same
## whether they are genuinely unwell or not, apart from their own name and
## condition. Compared as a SET across the ward — if the well and the unwell
## ever have different vocabularies, something has started leaking again.
func _check_the_crosshair_keeps_the_secret(w) -> void:
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		_fail("no patient system")
		return
	var well_words := {}
	var ill_words := {}
	var seen := 0
	for p in ps.active():
		var body = ps.get_body(p.id)
		if body == null or not body.has_method("prompt"):
			continue
		# `prompt(_player)` TAKES THE PLAYER. Called with no argument the whole
		# check aborted mid-function without erroring — CLAUDE.md 11 — so it
		# asserted nothing and the suite reported the same 72 checks as before
		# it existed. The count is the only reason anybody noticed.
		var pr = body.call("prompt", tree.get_first_node_in_group("player"))
		if pr == null or Array(pr).size() < 2:
			continue
		seen += 1
		var ill: bool = not bool(Cases.by_id(p.id).get("truly_well", true))
		# Drop the words that are legitimately theirs: their name and the
		# condition the chart already prints in the morning briefing.
		var text := String(pr[1])
		for own in String(Cases.by_id(p.id).get("condition", "")).split(" "):
			text = text.replace(String(own), "")
		for word in text.split("·"):
			var k := String(word).strip_edges()
			if k == "":
				continue
			if ill:
				ill_words[k] = true
			else:
				well_words[k] = true
	_ok(seen >= 3, "there are bedside prompts to read (%d)" % seen)
	var leaked: Array = []
	for k in ill_words:
		if not well_words.has(k):
			leaked.append(k)
	for k in well_words:
		if not ill_words.has(k):
			leaked.append(k)
	# Money differs by insurance tier, which is public and on the briefing.
	var real: Array = []
	for k in leaked:
		if not String(k).begins_with("$"):
			real.append(k)
	_ok(real.is_empty(),
		"and looking at somebody does not say whether they are ill%s"
			% ("" if real.is_empty() else ": " + ", ".join(real)))

## NO SIGN IN THE BUILDING RENDERS ITS OWN MIRROR IMAGE.
##
## `Build.label3d` used to set `double_sided = true` on everything. A billboard
## turns to face you so it costs nothing there — but a sign bolted to a wall or
## hung from a ceiling shows its BACK to anyone behind it, and the back of text
## is the text backwards. Every hanging corridor sign read correctly walking one
## way and mirrored walking the other.
##
## It had been found and hand-patched twice — `Hospital._build_signage` sets the
## flag false itself and carries a comment about "ǝʞɐʇnI ⅋ ʎqqo˥",
## `Dressing.ceiling_sign` builds a whole second rotated label to cover the back
## — and still shipped, because a fix at two call sites does not fix a default.
## Checked over the real building rather than by eye: at a distance a mirrored
## sign just looks like a blurry sign, which is exactly why it survived every
## screenshot review.
func _check_no_sign_is_mirrored() -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null:
		_fail("no hospital to inspect")
		return
	var bad: Array = []
	var seen := 0
	for n in _all_nodes(tree.root):
		if not (n is Label3D):
			continue
		seen += 1
		if n.billboard == BaseMaterial3D.BILLBOARD_DISABLED and n.double_sided:
			bad.append(String(n.text).substr(0, 18))
	_ok(seen > 5, "there are signs in the building to check (%d)" % seen)
	_ok(bad.is_empty(), "and not one of them renders backwards%s"
		% ("" if bad.is_empty() else ": " + ", ".join(bad)))

func _all_nodes(root: Node) -> Array:
	var out: Array = [root]
	for c in root.get_children():
		out.append_array(_all_nodes(c))
	return out

## THE REASON THIS GAME IS IN FIRST PERSON, CHECKED AGAINST THE ACTUAL BUILDING.
##
## `_written_in_front_of_them` is the finding that makes the ward a place rather
## than a menu: a note claiming somebody is unwell, typed where they can watch
## you type it, is a note the reviewer can check by walking four metres. There is
## a unit test for the RULE, but it states the witness list by hand — every
## headless harness builds its WardDay outside the tree, where `_who_can_see_me`
## returns empty by design, so nothing anywhere exercised the wiring from the
## world to the rule.
##
## That wiring is four things that can each fail silently: the `player` and
## `suspicion_system` groups, `Hospital.room_at` returning a key rather than "",
## and every patient body being in the room the game thinks it is. If any one of
## them broke, `seen_by` would come back empty on every entry, the sharpest
## finding in the audit would switch itself off, and all 271 assertions would
## still be green — which is CLAUDE.md 11's lesson wearing a different hat.
func _check_the_room_is_watching(w) -> void:
	var p = tree.get_first_node_in_group("player")
	var h = tree.get_first_node_in_group("hospital")
	if p == null or h == null:
		_fail("no player or hospital to stand in")
		return
	# Standing at the bay, where the people you are writing about are lying.
	p.global_position = h.point_in("ward")
	var watched: PackedStringArray = w._who_can_see_me()
	_ok(not watched.is_empty(),
		"standing in the bay, somebody can see you type (%s)" % ", ".join(watched))

	# ...and the office, which is the whole reason the walk costs minutes.
	p.global_position = h.point_in("office")
	var alone: PackedStringArray = w._who_can_see_me()
	_ok(alone.size() < watched.size(),
		"and walking to the office is what buys the privacy (%d watching, was %d)"
			% [alone.size(), watched.size()])

## THE TWO VERBS THAT ARE NOT DOCUMENTS. Both are new and both are the answer to
## a specific hole: the examination is the only way to learn something the chart
## does not contain, and the registrar is the only corroboration a bed can have
## that nobody can take apart.
func _check_the_new_verbs(w) -> void:
	var before: int = w.minute
	var found: String = w.examine("marchetti")
	_ok(found.length() > 20, "you can go and look at somebody, and it tells you something")
	_ok(w.minute > before, "and it costs a quarter of an hour of the shift")
	_ok(w.records.for_patient("marchetti").size() == _entries_for(w, "marchetti"),
		"and it writes nothing down, which is the point of it")
	var again: int = w.minute
	w.examine("marchetti")
	_ok(w.minute == again, "looking twice is free — the cost is for learning, not remembering")

	# The registrar keeps his own hours, so the harness has to be at one of them.
	w.advance_to(11 * 60 + 30)
	_ok(WardDay.colleague_available(w.minute), "%s is on the ward at half eleven" % WardDay.COLLEAGUE)
	var peer = w.ask_colleague("marchetti")
	_ok(peer != null and peer.author == ChartEntry.Author.DOCTOR,
		"a colleague can be asked, and writes in his own name")
	_ok(peer.supports_stay(),
		"and about the man who is genuinely unwell, he backs you in writing")
	w.advance_to(14 * 60)
	_ok(not WardDay.colleague_available(w.minute),
		"at two o'clock he is on the other ward and cannot be asked at all")
	_ok(w.ask_colleague("oduya") == null, "and asking anyway does nothing")

func _entries_for(w, pid: String) -> int:
	return w.records.for_patient(pid).size()

## THE CLAIM THE FIRST PERSON EXISTS FOR, tested against the real scene.
##
## "I observed this at the bedside at half past five" is checkable against where
## the player was standing at half past five, and the only thing that makes it
## checkable is somebody having seen them somewhere else. Every part of that is
## live wiring — Game's placement tick, the nurse's perception cone, the rooms
## the hospital thinks it has — and none of it was tested anywhere. A silent
## break here does not fail: it just quietly makes the game top-down.
func _check_being_seen_somewhere_else(w) -> void:
	var h = tree.get_first_node_in_group("hospital")
	var player = tree.get_first_node_in_group("player")
	if h == null or player == null:
		_fail("no player or hospital to test being seen")
		return
	# THE TWO TERMINALS HAVE TO MEAN WHAT THE GAME SAYS THEY MEAN: the one in
	# the bay is in full view of the ward, the one in your office has a door on
	# it. Both are read off where the player is standing, so both are testable.
	player.global_position = h.point_in("ward") + Vector3(0, 0.1, 0)
	var in_ward: PackedStringArray = w._who_can_see_me()
	_ok(not in_ward.is_empty(),
		"writing at the ward terminal happens in front of people (%s)" % ", ".join(in_ward))
	player.global_position = h.point_in("office") + Vector3(0, 0.1, 0)
	_ok(w._who_can_see_me().is_empty(),
		"and writing in your office with the door shut happens in front of nobody")
	# ...UNLESS SHE IS IN IT. The end-of-day screen promises an auditor after a
	# referral and promises you will be writing in front of somebody; this is
	# that promise, tested. She is spawned at boot from the flag, so the check
	# stands one up by hand rather than replaying a whole night.
	var auditor := NurseNPC.new()
	auditor.npc_id = "auditor_probe"
	auditor.display = "Ms Ferrand, Coding"
	game.add_child(auditor)
	auditor.global_position = h.point_in("office")
	var sus = tree.get_first_node_in_group("suspicion_system")
	if sus != null:
		sus.register(DB.make_mind(auditor.npc_id, auditor.display,
			"institution", "observant"), auditor)
	_ok(Array(w._who_can_see_me()).has(auditor.display),
		"with Coding standing in your office, the office is not private")
	if sus != null:
		sus.unregister(auditor.npc_id)
	auditor.queue_free()

	# Stood in the corridor, writing up a bedside observation for right now.
	player.global_position = h.point_in("corridor") + Vector3(0, 0.1, 0)
	var at: int = w.minute
	w.observe_player("corridor", PackedStringArray(["Adeyemi"]))
	w.write_entry("blake", ChartEntry.Claim.UNWELL, "Headache recurred.", at)
	w.set_disposition("blake", "hold")
	var kinds: Array = []
	for f in w.review_findings():
		kinds.append(f.kind)
	_ok(kinds.has("author_elsewhere"),
		"and a bedside note timed for a minute you were seen in the corridor is a finding")
	w.set_disposition("blake", "")

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
	# HOW MUCH OF THE CARD IS BELOW THE FOLD.
	#
	# A control can have a perfectly good size and still be somewhere nobody
	# looks. Everything a screen offers being reachable by scrolling is not the
	# same as it being READABLE, and a card whose second half is hidden reads as
	# a card with half the options on it.
	_screen_queue.pop_front()
	if _screen_queue.is_empty():
		if ui.has_method("close"):
			ui.call("close")
		return false
	EventBus.request_ui.emit(String(_screen_queue[0][0]), _screen_queue[0][1])
	return true

## THE WHOLE EVENING, THROUGH THE ACTUAL SCREENS.
##
## Everything above drives WardDay directly, which is how a build shipped where
## every system worked and the screens that reach them did not join up. The end
## of a day is a chain — handover, then the verdict, then tomorrow — and each
## link is a different script asking the UI router for the next one by name. A
## typo in any one of those names is a game that stops at eight o'clock.
## `records` is in here because it was NOT, and a screen the router had never
## heard of failed silently: `open()` logged a warning and returned, so both
## public terminals beeped and did nothing for as long as they have existed.
var _chain: Array = ["review", "day_over", "morning", "board", "records"]
var _chain_at := -1

func _check_the_screens_chain() -> bool:
	var ui = game.get("ui")
	if ui == null:
		_fail("no UI to walk the end of the day through")
		return true
	if _chain_at >= 0:
		var want := String(_chain[_chain_at])
		_ok(String(ui.get("current_id")) == want,
			"the %s screen opens when it is asked for" % want)
	_chain_at += 1
	if _chain_at >= _chain.size():
		if ui.has_method("close"):
			ui.call("close")
		return true
	# The verdict the day actually produced, so day_over is built from a real
	# outcome rather than a default that no play can reach.
	var ctx := {}
	if String(_chain[_chain_at]) == "day_over":
		ctx = {"verdict": ReviewSystem.OUTCOME_QUESTIONS,
			"remembered": PackedStringArray(["oduya"])}
	EventBus.request_ui.emit(String(_chain[_chain_at]), ctx)
	return false

## THE ONE BUTTON THAT ENDS A SHIFT, PRESSED.
##
## Everything above reaches a screen by emitting `request_ui` for it, which is
## how the End of Shift card kept passing every check while being unreachable in
## the actual game. The review screen's "Go home" did:
##
##     EventBus.request_ui.emit("day_over", ...)   # opens the card
##     close()                                     # ...and frees it
##
## `UIRoot.open()` closes whatever is up before building the next screen, and a
## signal runs inline, so by the time that lambda continued `current` WAS the
## End of Shift card. The only button that ends the first shift threw the whole
## shift away: the card flashed, the player was dumped into a ward with a dead
## clock, and "Work tomorrow" — the sole caller of `_carry()`, which increments
## the day, carries the debt forward and saves — could never be pressed. No
## career could reach day two, and 273 assertions, 74 smoke checks, 31
## playtests and four probes all passed.
##
## So this presses the real button and then looks at what is on screen.
func _check_the_handover_button_reaches_tomorrow() -> void:
	var ui = game.get("ui")
	if ui == null:
		_fail("no UI to press")
		return
	EventBus.request_ui.emit("review", {})
	if String(ui.get("current_id")) != "review":
		_fail("the handover would not open to be pressed")
		return
	var go = _find_button(ui.get("current"), "Go home")
	_ok(go != null, "the handover has a button that ends the shift")
	if go == null:
		return
	go.emit_signal("pressed")
	_ok(String(ui.get("current_id")) == "day_over",
		"and pressing it leaves the End of Shift card UP (got '%s')"
			% String(ui.get("current_id")))
	var tomorrow = _find_button(ui.get("current"), "Work tomorrow")
	_ok(tomorrow != null, "with the button that starts tomorrow on it")
	# ...and Escape must not be able to take it away again.
	if ui.has_method("_unhandled_input"):
		var ev := InputEventAction.new()
		ev.action = "pause"
		ev.pressed = true
		ui.call("_unhandled_input", ev)
		_ok(String(ui.get("current_id")) == "day_over",
			"and Escape does not strand you in a finished ward")
	if ui.has_method("close"):
		ui.call("close")

func _find_button(root, label: String):
	if root == null:
		return null
	for n in _all_nodes(root):
		if n is Button and String(n.text).findn(label) >= 0:
			return n
	return null

## TOMORROW IS FIVE DIFFERENT PEOPLE, IN THE BEDS.
##
## Day two opened with Hal Brennan's name floating over a bed belonging to
## Tallulah Ferreira: the roster changed, the WardDay changed, and the bodies in
## the room did not. Nothing above would have caught it — every other harness
## reads `Cases` and `WardDay` and never looks at the ward.
func _check_tomorrow_is_a_different_ward() -> void:
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		_fail("no patient system")
		return
	var before := {}
	for p in ps.active():
		before[p.id] = p.display_name

	GameState.day = 2
	var w = tree.get_first_node_in_group("ward_day")
	if w != null:
		w.start()
	ps.reset_day()
	var names := {}
	var beds := {}
	for p in ps.active():
		names[p.id] = p.display_name
		beds[p.bed_index] = true
		_ok(not before.has(p.id), "%s was not on yesterday's ward" % p.display_name)
		var b = ps.get_body(p.id)
		_ok(b != null and is_instance_valid(b) and b.is_inside_tree(),
			"%s has a body in the room" % p.display_name)
	_ok(names.size() == Cases.roster().size(),
		"tomorrow has %d people on it" % Cases.roster().size())
	_ok(beds.size() == Cases.BEDS, "in %d different beds" % Cases.BEDS)
	for id in before:
		_ok(ps.get_body(id) == null,
			"and yesterday's %s has gone home, body and all" % before[id])
	GameState.day = 1
	if w != null:
		w.start()
	ps.reset_day()

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

## A WHOLE CAREER SURVIVES A SAVE, which is what "Continue" is.
##
## Since the debt got a term, what has to come back is not just the day number
## and the money: it is what is left of what Vinnie is owed, what the ward
## sister has written down about you, how near the Board you are, and who is
## bouncing back in the morning. Any one of those dropped and Continue quietly
## restarts a career the player is nine nights into.
func _check_a_career_survives_a_save() -> void:
	var before_debt := 4321
	GameState.set_flag("debt_remaining", before_debt)
	GameState.set_flag(Cases.READMIT_FLAG, ["oduya"])
	GameState.day = 6
	GameState.cash = 777
	DoctorRecord.wipe()
	var rec := DoctorRecord.load_from_state()
	rec.record_night([], ReviewSystem.OUTCOME_FLAGGED)
	rec.record_night([], ReviewSystem.OUTCOME_ESCALATED)

	var snapshot := GameState.to_dict()
	GameState.start_new_career(99)
	_ok(GameState.debt_remaining() != before_debt, "a new career forgets the old one")

	GameState.from_dict(snapshot)
	_ok(GameState.debt_remaining() == before_debt,
		"and a save brings back what is left of the debt")
	_ok(GameState.day == 6, "the day you were on")
	_ok(GameState.cash == 777, "the money in your pocket")
	var back := DoctorRecord.load_from_state()
	_ok(back.strikes == 4, "how near the Board you are (%d)" % back.strikes)
	_ok(back.nights == 2, "how many shifts you have worked")
	_ok(PackedStringArray(GameState.flag(Cases.READMIT_FLAG, [])).has("oduya"),
		"and who is back in a bed in the morning")
	GameState.start_new_career(20260821)
	GameState.set_flag("tutorial_done", true)
