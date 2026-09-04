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
## The seed this run is on. Overridable with SMOKE_SEED.
var seed := 20260821
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
	# THE SEED IS OVERRIDABLE, so the same run can be pointed at a ward it has
	# never seen. Everything below builds a real world with a real UI on ONE
	# deal, and a ward is a draw from a pool of ten per day — so "the game
	# works" has only ever been checked against one of the thirty-two boards
	# ward one alone can produce. `SMOKE_SEED=n ./run_tests.sh` picks another.
	var env := OS.get_environment("SMOKE_SEED")
	if env != "" and env.is_valid_int():
		seed = int(env)
		print("  (seed %d)" % seed)
	GameState.start_new_career(seed)
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

## AN ASSERTION MADE IN THE SAME FRAME AS ITS SETUP READS LAST FRAME'S VALUE.
##
## Anything a node writes in `_process`, `_physics_process` or a `call_deferred`
## has not happened yet when the setup line returns — a rebuilt screen has not
## laid out, a freed node has not gone, a grabbed focus has not landed. `_defer`
## puts the assertion `n` frames later; `_report()` refuses to declare a result
## while one is still outstanding, so a check that never runs is a failure
## rather than a silently smaller number.
var _later: Array = []

func _defer(n: int, what: Callable) -> void:
	_later.append({"at": frames + n, "do": what})

func _drain_deferred() -> void:
	var still: Array = []
	for job in _later:
		if frames >= int(job["at"]):
			(job["do"] as Callable).call()
		else:
			still.append(job)
	_later = still

func tick() -> bool:
	frames += 1
	tree.paused = false
	_drain_deferred()
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
			stage = "toasts"
		"toasts":
			if _check_nothing_is_said_into_a_closed_card():
				# THE SYNCHRONOUS ONE FIRST. The card check opens a screen and
				# defers its assertions four frames; anything that opens another
				# screen after it has replaced the card those assertions are
				# about, and all three of them failed on a screen they did not
				# mean. A deferred check owns the UI until it comes due.
				_check_the_rebind_row_can_be_escaped()
				_check_a_rebuilt_card_still_has_a_selection()
				stage = "settle"
		"settle":
			# Nothing to do but let the deferred checks above come due.
			if _later.is_empty():
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
	_check_every_room_named_in_source_exists()

	_check_the_promised_visitors_arrive()

	_check_the_crosshair_keeps_the_secret(w)
	# HEADROOM. Every verb below costs ward minutes — a note is eight, a nurse
	# review fifteen, an examination fifteen, the registrar twenty-five — and
	# from half past seven that is enough to walk the shift past eight o'clock,
	# at which point the ward force-discharges everybody and closes the day
	# under the harness. Start in the afternoon and there is room for all of it.
	var pen := _anyone()
	var before: int = w.records.for_patient(pen).size()
	w.advance_to(15 * 60 + 30)
	var e = w.write_entry(pen, ChartEntry.Claim.UNWELL,
		"Reports transient dizziness on standing.", 15 * 60 + 10)
	_ok(w.records.for_patient(pen).size() > before, "a note can be written")
	_ok(e.written_minute > e.stated_minute,
		"and it records both when it happened and when it was typed")
	_ok(e.backdated_by() == 20, "and knows the gap between them exactly")

## THE CHECKS THAT SPEND TIME GO LAST.
##
## These write notes and decide beds, and `write_entry` charges eight minutes
## for each one — so seventeen of them walked the ward clock past half three and
## the backdating assertion in `_check_the_chart_works`, which writes at 15:30
## stating 15:10 and expects a gap of exactly 20, started measuring a gap of
## whatever the clock had drifted to. Anything that moves the clock belongs
## after everything that reads it.
func _check_the_verbs_work() -> void:
	var w = tree.get_first_node_in_group("ward_day")
	if w == null:
		return
	var n = w.nurse_check(_someone_unwell())
	_ok(n != null and n.author == ChartEntry.Author.NURSE,
		"a nurse can be asked to look, and writes in her own name")
	_ok(n.supports_stay(),
		"and about the patient who is genuinely unwell, she agrees with you")
	# SOMEBODY WHO IS WELL, because the assertion below is that the lab comes
	# back normal for them. `_anyone()` is the first bed on the roster and on
	# some wards that is the genuinely unwell one, whose bloods correctly come
	# back abnormal — a real result failing a check that had assumed a ward.
	var o = w.order_test(_someone_well(), "lying and standing BP")
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
	_check_the_tutorial_finishes()
	_check_writing_is_observed(w)
	_check_discharged_patients_leave(w)
	_check_the_nurse_does_rounds()
	_check_tests_in_flight_come_back(w)
	_check_a_watched_day_can_still_be_written_in()
	_check_a_readmission_waits_for_the_morning()
	_check_nobody_is_misgendered()
	_check_nothing_floats_or_sinks()
	_check_the_doors_have_room_to_swing()
	_check_the_nurse_does_not_copy_and_paste()
	_check_the_daughter_actually_turns_up()
	_check_the_day_gives_you_warning()
	_check_nothing_calls_a_method_that_is_not_there()
	_check_the_money_on_the_hud_is_the_money_you_get()

## A WATCHED DAY IS HARDER, NOT AIRLESS.
##
## The extra rounds a flag buys you used to be placed at the MIDPOINT between
## two existing ones, which put every round ninety minutes from its neighbour.
## `ChartEntry.SAME_MOMENT` is forty-five, and `same_moment_as` uses `<=`, so
## each round owns a ninety-one minute window — and those windows tiled the
## whole shift end to end. There was no minute left in the day at which a note
## could be written without reading as two people disagreeing about the same
## half hour, and the findings that produces are what get you flagged again.
## One bad night was an inescapable spiral, and it looked like difficulty.
##
## So this asserts the property the placement exists to guarantee, computed
## from the real constants rather than from the numbers that happen to be in
## `Cases.ROUNDS` today: on a watched day there is still somewhere to write.
func _check_a_watched_day_can_still_be_written_in() -> void:
	var was_watched: bool = GameState.flag("watched", false)
	var w := WardDay.new()
	tree.root.add_child(w)

	GameState.set_flag("watched", false)
	var calm: Array = w.rounds_today()
	GameState.set_flag("watched", true)
	var watched: Array = w.rounds_today()

	_ok(watched.size() > calm.size(),
		"a flag does buy the ward more rounds (%d, was %d)"
			% [watched.size(), calm.size()])

	# Every minute of the shift that is not inside any round's window. This is
	# the same comparison `ChartEntry.same_moment_as` makes, so a change to
	# either the constant or the operator moves this check with it.
	var free_calm := _writable_minutes(calm)
	var free_watched := _writable_minutes(watched)
	_ok(free_calm > 0, "an ordinary day has room to write in (%d min)" % free_calm)
	_ok(free_watched > 0,
		"and a watched day still does — this is the spiral guard (%d min)"
			% free_watched)
	# Harder is the point: it must cost, or doubling the rounds meant nothing.
	_ok(free_watched < free_calm,
		"but there is less of it than on a quiet day (%d against %d)"
			% [free_watched, free_calm])
	# And the room that is left has to be usable, AFTER THE FIRST ROUND.
	#
	# Measured across the whole shift this passes on a day with no gaps at all,
	# because the stretch from clocking on at eight to the first round at ten is
	# free whatever the rounds do afterwards — and a note written before Adeyemi
	# has been anywhere is not the timing skill this is guarding. So the window
	# has to be found in the part of the day she is walking through, and it has
	# to be long enough to read a chart and write the note that reading suggests.
	var need: int = WardDay.READ_COST + WardDay.WRITE_COST
	var first: int = int(watched[0])
	var longest := _longest_writable_run(watched, first)
	_ok(longest >= need,
		"and one unbroken window after her first round is long enough to read "
			+ "and write in (%d >= %d)" % [longest, need])
	# Twice, in fact — one window is a single note, and the ward has five beds.
	_ok(_writable_minutes(watched, first) >= need * 2,
		"with enough left over for a second (%d min after %d:00)"
			% [_writable_minutes(watched, first), first / 60])

	GameState.set_flag("watched", was_watched)
	tree.root.remove_child(w)
	w.free()

## Minutes of the shift at which a note would collide with no round.
func _writable_minutes(rounds: Array, from := -1) -> int:
	var n := 0
	for m in range(maxi(from, Cases.DAY_START_MINUTE), Cases.DEBT_DUE_MINUTE):
		if _clear_of(m, rounds):
			n += 1
	return n

## The longest unbroken stretch of them.
func _longest_writable_run(rounds: Array, from := -1) -> int:
	var best := 0
	var run := 0
	for m in range(maxi(from, Cases.DAY_START_MINUTE), Cases.DEBT_DUE_MINUTE):
		if _clear_of(m, rounds):
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return best

func _clear_of(minute: int, rounds: Array) -> bool:
	for r in rounds:
		if absi(minute - int(r)) <= ChartEntry.SAME_MOMENT:
			return false
	return true

## THEY COME BACK TOMORROW, NOT TONIGHT.
##
## `Cases.roster()` reads `READMIT_FLAG` live on every call and substitutes
## `readmission_of(c)`, and `GameState.day` is not incremented until the End of
## Shift card. `end_day()` set that flag directly, so from the moment the shift
## ended the man you discharged at six was, on the live ward, a readmission —
## and the handover comes AFTER `end_day()`. Sister Nkemelu asked why he was
## back in that bed before the night staff went home; his file went `flagged`,
## which multiplies every other finding about him by 1.6 as "already under
## review"; and then the very next screen promised he would be back in the
## morning. The two climax screens disagreed by a night about the same bed, and
## the fabricated finding fed the verdict, the strikes and the money.
func _check_a_readmission_waits_for_the_morning() -> void:
	var was := GameState.minute_of_day
	var was_flag = GameState.flag(Cases.READMIT_FLAG, [])
	var was_pending = GameState.flag(Cases.READMIT_PENDING, [])
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.set_flag(Cases.READMIT_PENDING, [])

	# Somebody who genuinely should not go home, sent home.
	var victim := ""
	for c in Cases.roster():
		if not bool(c.get("truly_well", true)) and not bool(c.get("readmitted", false)):
			victim = String(c["id"])
			break
	if victim == "":
		_fail("no unwell patient on the canonical ward to send home")
		GameState.minute_of_day = was
		return

	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	for c in Cases.roster():
		w.set_disposition(String(c["id"]),
			"discharge" if String(c["id"]) == victim else "hold")
	w.end_day()

	# The handover reads the ward FRESH — it does not use the findings cached in
	# end_day()'s return — so this has to be asked the way the screen asks it.
	_ok(not bool(Cases.by_id(victim).get("readmitted", false)),
		"the man you sent home tonight is not already back tonight")
	var came_back := 0
	for f in w.review_findings():
		if String(f.kind) == "readmitted_after_your_discharge":
			came_back += 1
	_ok(came_back == 0,
		"so the handover does not ask about a readmission that has not happened "
			+ "(%d findings)" % came_back)
	_ok(not bool(w.review_truth().get(victim, {}).get("flagged", false)),
		"and his file is not 'already under review' for it, which would have "
			+ "multiplied every other finding about him by 1.6")

	# But it IS queued, and the card that promises it reads the same list.
	var pending := PackedStringArray(GameState.flag(Cases.READMIT_PENDING, []))
	_ok(Array(pending).has(victim),
		"he is on tomorrow's list, which is what the End of Shift card reads")

	# And the morning delivers him. This is what `_carry()` does at the moment
	# it increments the day; doing it by hand keeps the check off the UI.
	GameState.set_flag(Cases.READMIT_FLAG, pending)
	GameState.set_flag(Cases.READMIT_PENDING, [])
	_ok(bool(Cases.by_id(victim).get("readmitted", false)),
		"and once the day turns over, there he is")

	GameState.set_flag(Cases.READMIT_FLAG, was_flag)
	GameState.set_flag(Cases.READMIT_PENDING, was_pending)
	tree.root.remove_child(w)
	w.free()
	GameState.minute_of_day = was

## NOBODY IS DESCRIBED BY SOMEBODY ELSE'S PRONOUN.
##
## Six strings had one welded in. The self-discharge toast said "%s has signed
## herself out" about whoever walked out, and five of Sister Nkemelu's questions
## asked about "him" or "her" regardless of who was in the bed — so on a ward of
## five drawn from forty, the game got it wrong about half the time it spoke, in
## the two places the writing is trying hardest: the moment somebody walks out
## on you, and the moment you are asked to account for them.
##
## Both halves are checked. The data half, that all forty people have a pronoun
## and that it is one the table knows. And the source half, by grepping the
## strings themselves — because the fix is a template and a template is only as
## good as the next person remembering to use it.
func _check_nobody_is_misgendered() -> void:
	var missing := 0
	var unknown := 0
	for c in Cases.everyone():
		var they := String(c.get("they", ""))
		if they == "":
			missing += 1
		elif not Cases.PRONOUNS.has(they):
			unknown += 1
	_ok(missing == 0 and unknown == 0,
		"all %d authored patients carry their own pronoun (%d missing, %d unknown)"
			% [Cases.everyone().size(), missing, unknown])

	# The template does the agreement, which is the half a lookup table alone
	# gets wrong: "they are" against "she is".
	var she := Cases.about(_someone_who("she"), "{They} {are} asking for {their} coat.")
	var they2 := Cases.about(_someone_who("they"), "{They} {are} asking for {their} coat.")
	_ok(she == "She is asking for her coat.", "she reads as she (%s)" % she)
	_ok(they2 == "They are asking for their coat.", "they reads as they (%s)" % they2)
	_ok(Cases.about(_someone_who("he"), "{They} {v:read} {their} chart.")
		== "He reads his chart.", "and a regular verb agrees with either")
	# An id nobody has heard of gets they/them, not a guess.
	_ok(Cases.about("nobody_at_all", "{They} {are} here.") == "They are here.",
		"an unknown patient is they, never an assumption")

	# AND NOTHING NEW SNEAKS ONE BACK IN. A gendered pronoun in the same string
	# as a `%s` is the shape of the bug: a name substituted into a sentence that
	# has already decided who the person is.
	var offenders: Array = []
	for path in ["res://scripts/systems/contradictions.gd",
			"res://scripts/systems/ward_day.gd", "res://scripts/systems/review_system.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var n := 0
		for line in src.split("\n"):
			n += 1
			var bare := line.strip_edges()
			if bare.begins_with("#") or not bare.contains("%s"):
				continue
			# Only inside the quoted parts — a trailing comment on a line of
			# real code is prose and is allowed to say "she" about Adeyemi.
			for chunk in _quoted(bare):
				for word in ["he ", "him ", "his ", "she ", "her ", "hers ",
						"himself", "herself"]:
					if (" " + chunk.to_lower()).contains(" " + word):
						offenders.append("%s:%d %s" % [path.get_file(), n, chunk.substr(0, 48)])
						break
	_ok(offenders.is_empty(),
		"no templated line decides the patient's gender for them%s"
			% ("" if offenders.is_empty() else " — " + String(offenders[0])))

func _someone_who(kind: String) -> String:
	for c in Cases.everyone():
		if String(c.get("they", "")) == kind:
			return String(c["id"])
	return ""

## The double-quoted runs of a line, so a trailing comment is not searched.
func _quoted(line: String) -> Array:
	var out: Array = []
	var parts := line.split("\"")
	for i in parts.size():
		if i % 2 == 1:
			out.append(String(parts[i]))
	return out

## THINGS THAT STAND ON THINGS ACTUALLY STAND ON THEM.
##
## All three EHR terminals were built around an origin somewhere inside the
## case, so the lowest part of the model sat 0.39 above it — and all three
## callers placed the origin by eye. The ward and office machines floated
## nineteen centimetres over their desks; the station one was five centimetres
## inside the worktop. Nobody had put a number on it because the only way to
## see it is to go and look, and the screenshots point at the room rather than
## at one desk.
##
## So: measure. For each fixture that is meant to rest on something, take the
## lowest point of its geometry, find the highest surface underneath its
## footprint, and insist they meet. Wall-mounted pieces are excluded by being
## absent from the list — `Dressing` has its own rule and its own bug history.
const STANDS_ON_SOMETHING := ["RecordsTerminal"]
const RESTS_TOLERANCE := 0.02

func _check_nothing_floats_or_sinks() -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null:
		_fail("no hospital to measure")
		return
	# Everything with a shape, in world space, once.
	var boxes: Array = []
	var standers: Array = []
	for n in _all_nodes(h):
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		var owner_name := _fixture_kind(mi)
		# The fixture this part belongs to, so a terminal's own base is not
		# mistaken for the desk it is supposed to be standing on.
		var owner_node := _fixture_ancestor(mi)
		boxes.append({"aabb": aabb, "owner": owner_name, "of": owner_node})
		if owner_name in STANDS_ON_SOMETHING:
			standers.append({"aabb": aabb, "owner": owner_name, "node": mi})

	_ok(not standers.is_empty(),
		"there are %d pieces of geometry that have to rest on something"
			% standers.size())

	# Group each fixture's parts back together — a terminal is four boxes and
	# only the lowest of them is standing on the desk.
	var by_fixture: Dictionary = {}
	for st in standers:
		var f = _fixture_ancestor(st["node"])
		var key := str(f.get_instance_id())
		if not by_fixture.has(key):
			by_fixture[key] = {"node": f, "aabb": st["aabb"]}
		else:
			by_fixture[key]["aabb"] = by_fixture[key]["aabb"].merge(st["aabb"])

	var floating: Array = []
	for key in by_fixture:
		var f = by_fixture[key]["node"]
		var box: AABB = by_fixture[key]["aabb"]
		var foot := box.position.y
		var best := 0.0                     ## the floor, if nothing else
		for b in boxes:
			var other: AABB = b["aabb"]
			if b["of"] == f:
				continue
			# Directly underneath, in plan, and topping out below this thing.
			if not _overlaps_in_plan(box, other):
				continue
			var top: float = other.position.y + other.size.y
			if top <= foot + RESTS_TOLERANCE and top > best:
				best = top
		var gap: float = foot - best
		if absf(gap) > RESTS_TOLERANCE:
			floating.append("%s %s by %.0fcm" % [_fixture_kind(f),
				"floats" if gap > 0.0 else "is sunk", absf(gap) * 100.0])
	_ok(floating.is_empty(),
		"and every one of them does%s" % ("" if floating.is_empty()
			else " — " + ", ".join(PackedStringArray(floating))))

## Two boxes seen from above.
func _overlaps_in_plan(a: AABB, b: AABB) -> bool:
	return a.position.x < b.position.x + b.size.x \
		and b.position.x < a.position.x + a.size.x \
		and a.position.z < b.position.z + b.size.z \
		and b.position.z < a.position.z + a.size.z

func _fixture_ancestor(n: Node) -> Node:
	var cur := n
	while cur != null:
		if cur is Fixture:
			return cur
		cur = cur.get_parent()
	return n

func _fixture_kind(n: Node) -> String:
	var cur := n
	while cur != null:
		var scr = cur.get_script()
		if scr != null:
			var g := String(scr.get_global_name())
			if g != "":
				return g
		cur = cur.get_parent()
	return ""

## AND THE DOORS CAN ACTUALLY OPEN.
##
## The ward's hand-gel dispenser was mounted ten centimetres from the door jamb,
## and a SwingDoor opens either way — `_open_dir` is decided by which side the
## person came from — so the leaf swept a two-hundred-degree arc straight
## through it. Scenery has no collision by design, which is exactly what lets
## there be a lot of it and exactly why nothing in the engine was ever going to
## complain: the leaf passed through the dispenser silently, every time anybody
## walked into the ward.
##
## Nothing decorative may stand inside the disc a leaf sweeps. Checked against
## the door's real width and hinge, so a wider door moves the rule with it.
func _check_the_doors_have_room_to_swing() -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null:
		_fail("no hospital to measure")
		return
	var doors: Array = []
	for n in _all_nodes(h):
		if n is SwingDoor:
			doors.append(n)
	_ok(doors.size() >= 2, "the building has %d swinging doors" % doors.size())

	var blocked: Array = []
	var checked := 0
	for d in doors:
		# The hinge is the door's own origin and the leaf extends along local
		# +Z, so the swept disc has the leaf's width for a radius.
		var hinge: Vector3 = d.global_position
		var reach: float = float(d.width)
		for piece in tree.get_nodes_in_group("dressing"):
			if not (piece is Node3D):
				continue
			var box := _world_box(piece)
			if box.size == Vector3.ZERO:
				continue
			# Only things at door height matter: a floor tile under the swing
			# and a light fitting above it are both fine.
			if box.position.y > SwingDoor.HEIGHT or box.position.y + box.size.y < 0.05:
				continue
			checked += 1
			if _nearest_in_plan(box, hinge) < reach:
				var c := box.get_center()
				blocked.append("%s (%s) centred %.1f,%.1f comes within %.2fm of the %s hinge at %.1f,%.1f (sweeps %.2f)"
					% [piece.name, _dressing_kind(piece), c.x, c.z,
						_nearest_in_plan(box, hinge), String(d.room_key),
						hinge.x, hinge.z, reach])
	_ok(checked > 0, "with %d pieces of scenery near enough to matter" % checked)
	for b in blocked:
		notes.append("  .. " + String(b))
	_ok(blocked.is_empty(), "and no leaf sweeps through any of it (%d in the way)"
		% blocked.size())

func _dressing_kind(n: Node) -> String:
	var p := n.get_parent()
	return "%s under %s" % [n.get_class(), p.name if p != null else "?"]

## The closest point of a box to a point, seen from above.
func _nearest_in_plan(box: AABB, p: Vector3) -> float:
	var nx: float = clampf(p.x, box.position.x, box.position.x + box.size.x)
	var nz: float = clampf(p.z, box.position.z, box.position.z + box.size.z)
	return Vector2(p.x - nx, p.z - nz).length()

## Every mesh under a node, merged, in world space — EXCEPT its shadow.
##
## A contact shadow is a flat quad a hand's width larger than the piece it sits
## under, and it is a child of the piece. Merging it in grows every measurement
## by eleven centimetres on each side, so this check would start reporting
## objects as standing in a door's arc when only their shadows do.
func _world_box(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _all_nodes(n):
		if not (m is MeshInstance3D):
			continue
		var mi: MeshInstance3D = m
		if mi.mesh == null or mi.name == "ContactShadow":
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out

## THE BIG GREEN NUMBER IS A PROMISE.
##
## `projected()` claims to be "what tonight pays if the day ended right now",
## and "right now" has to mean the same thing on both sides of the sum. It did
## not: `free_beds()` is `BEDS - held`, so an undecided bed counted as free and
## paid its $500 admission — while `discharged_ids()` counts only beds
## explicitly marked, so the same undecided bed paid no discharge fee.
##
## At 08:00 with nothing decided the HUD therefore read $1,900: nine hundred in
## hand plus two admissions for five beds nobody had touched, and none of the
## five discharge fees those admissions imply. Sign off on that exact state and
## the shift pays $2,650, because both the eight o'clock close and the office
## terminal discharge every undecided bed first. The corner of the screen was
## quoting a ward that cannot exist — thirty seconds after a briefing card
## reading "In your account $900", in a game whose entire score is one number.
func _check_the_money_on_the_hud_is_the_money_you_get() -> void:
	var was := GameState.minute_of_day
	# Nothing decided at all: the state the player is looking at on the first
	# frame of the game, and the one the two figures disagreed most about.
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	# THROUGH `sign_off()`, not `end_day()`. `end_day` computes its takings FROM
	# `projected()`, so comparing the two is comparing a number with itself and
	# passes just as happily on the broken arithmetic. What signing off actually
	# does first is send every undecided bed home — and whether the projection
	# already counted those beds that way is the entire question.
	var promised: int = int(w.projected()["total"])
	var paid: int = int(w.sign_off().get("paid", 0))
	_ok(promised == paid,
		"the untouched ward is worth what signing off on it pays (%d, %d)"
			% [promised, paid])
	tree.root.remove_child(w)
	w.free()

	# And with real decisions on it, so this is not passing on a special case.
	var q := WardDay.new()
	tree.root.add_child(q)
	q.start()
	var i := 0
	for c in Cases.roster():
		# Hold two, discharge one, leave the rest undecided — the mixture that
		# has an admission fee, a discharge fee and a night value all in it.
		if i < 2:
			q.set_disposition(String(c["id"]), "hold")
		elif i == 2:
			q.set_disposition(String(c["id"]), "discharge")
		i += 1
	var promised2: int = int(q.projected()["total"])
	var paid2: int = int(q.sign_off().get("paid", 0))
	_ok(promised2 == paid2,
		"and so is a half-decided one (%d, %d)" % [promised2, paid2])
	# The two wards must not be the same number, or this proves nothing.
	_ok(promised != promised2,
		"and the two are different wards (%d against %d)" % [promised, promised2])
	tree.root.remove_child(q)
	q.free()
	GameState.minute_of_day = was

## A TOAST RAISED BEHIND A CARD IS STILL THERE WHEN THE CARD GOES.
##
## A toast lived six real seconds from the moment it was shown, and that clock
## ran whether or not there was a 700-pixel briefing panel on top of it. The
## first line of teaching in the game is emitted on the same frame the morning
## card opens — five patient rows and three money figures to read — so the one
## instruction that tells a new player what the first verb is had reliably
## expired before they pressed "Start the round", and never came back. A lab
## result landing while a chart was open died the same way: five minutes to
## order, seventy-five to wait, and nobody ever saw it.
##
## Its own stage, because it is the one check in this file that needs frames to
## pass in the middle of it. Returns true when it is finished.
var _toast_step := 0
var _rounds_announced := 0
var _toasts_before := 0

func _check_nothing_is_said_into_a_closed_card() -> bool:
	var hud = tree.get_first_node_in_group("hud")
	if hud == null or not hud.has_method("set_modal"):
		_fail("no HUD to talk to")
		return true
	_toast_step += 1
	if _toast_step == 1:
		_toasts_before = _toast_count(hud)
		hud.set_modal(true)
		# A LINE NOTHING ELSE SAYS. `_drain_toasts` merges a repeat of the line
		# already at the bottom into a tally on the existing label rather than
		# adding a panel — so a check that counts panels and reuses a line the
		# run has already spoken watches the count not move and calls it a bug.
		EventBus.toast.emit("Blue folder, third shelf, behind the kettle.", "info")
		return false
	# The queue also holds a half-second gap between toasts, so "after the card
	# closes" is a window rather than a frame. Poll it.
	if _toast_step < 120:
		if _toast_count(hud) != _toasts_before:
			_fail("a toast was drawn behind a card (%d, was %d)"
				% [_toast_count(hud), _toasts_before])
			return true
		return false
	if _toast_step == 120:
		_ok(_toast_count(hud) == _toasts_before,
			"nothing is drawn behind a card (%d, was %d)"
				% [_toast_count(hud), _toasts_before])
		hud.set_modal(false)
		return false
	if _toast_count(hud) > _toasts_before:
		_ok(true, "and it arrives when there is a screen to see it on (%d, was %d)"
			% [_toast_count(hud), _toasts_before])
		return true
	if _toast_step > 260:
		_ok(false, "and it arrives when there is a screen to see it on — it did not")
		return true
	return false

## The HUD's toast column.
func _toast_count(hud) -> int:
	var col = hud.get("_toasts")
	return col.get_child_count() if col != null else -1

## FOUR ROUNDS, FOUR NOTES.
##
## The round line was picked from the patient's id alone, on purpose — so that
## a chart read as one nurse describing one person all day rather than as a
## shuffle. What it actually produced was four notes that were identical word
## for word, stacked on the chart screen, which is the screen the whole game
## happens on. A nurse who looks at somebody four times writes four notes: she
## says the same THING, not the same words, and a column of copy-paste reads as
## a bug however well it was reasoned.
func _check_the_nurse_does_not_copy_and_paste() -> void:
	# ON A WATCHED DAY, which is the hard case and the one that matters: a flag
	# doubles her rounds to eight, so anything shorter than eight lines comes
	# round twice on the same patient — on the night the chart is being read
	# hardest. It is also the only version of this check that can fail.
	var was: bool = GameState.flag("watched", false)
	GameState.set_flag("watched", true)
	_rounds_announced = 0
	var heard := func(text: String, _kind: String):
		if text.contains("%s has been round" % DB.WARD_NURSE):
			_rounds_announced += 1
	EventBus.toast.connect(heard)
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	w.advance_to(Cases.DEBT_DUE_MINUTE - 1)
	EventBus.toast.disconnect(heard)

	var worst := 0
	var who := ""
	var repeated := 0
	for c in Cases.roster():
		var pid := String(c["id"])
		var seen := {}
		var n := 0
		for e in w.records.entries:
			if e.patient_id != pid or e.author != ChartEntry.Author.NURSE:
				continue
			n += 1
			seen[e.text] = int(seen.get(e.text, 0)) + 1
		if n > worst:
			worst = n
			who = pid
		for t in seen:
			if int(seen[t]) > 1:
				repeated += 1
	_ok(worst >= 8, "a watched ward has Adeyemi writing %s up %d times" % [who, worst])
	# AND SHE SAYS SO. Writing in the gap between her rounds is the central
	# timing skill of the game and the rounds were silent — a rhythm nobody can
	# hear is a rhythm nobody learns, and the doubling a flag buys reads as
	# nothing at all without it.
	_ok(_rounds_announced >= 8,
		"and every round she does is announced (%d)" % _rounds_announced)
	_ok(repeated == 0,
		"and no two of anybody's round notes are the same words (%d repeats)"
			% repeated)
	GameState.set_flag("watched", was)
	tree.root.remove_child(w)
	w.free()

## "RUTH KERRIGAN IS HERE TO SEE HER MOTHER."
##
## That line has been printed at seven o'clock since the day it was written and
## nothing ever spawned anybody — the same unkept promise as "Ms Ferrand from
## Coding is on the ward today", which was fixed earlier by making her turn up.
## `VisitorNPC` existed the whole time, 115 lines of it, never instantiated
## anywhere in the project, and broken with it: `_visit_bark` read
## `p.overdue_days`, which is not a property of Patient, so the half of it that
## produces evidence could not have run even if something had built one.
##
## Two halves, because the first version of this check asserted against Dot
## Kerrigan by name and the smoke run's ward does not have her on it — so it
## passed by doing nothing, which is how a check that cannot fail gets written.
func _check_the_daughter_actually_turns_up() -> void:
	# THE TRIGGER, on whichever ward actually has somebody expecting family.
	var fired := {}
	for day in range(1, Cases.DAYS.size() + 1):
		var was_day := GameState.day
		GameState.day = day
		var expected := ""
		var at := 0
		for c in Cases.roster():
			if int(c.get("family_at", 0)) > 0:
				expected = String(c["id"])
				at = int(c["family_at"])
		if expected == "":
			GameState.day = was_day
			continue
		var q := WardDay.new()
		tree.root.add_child(q)
		q.start()
		q.visitor_arrived.connect(func(pid, _who): fired[String(pid)] = day)
		q.advance_to(at + 1)
		tree.root.remove_child(q)
		q.free()
		GameState.day = was_day
	_ok(not fired.is_empty(),
		"the families the game promises are announced on the day they are due (%s)"
			% ", ".join(PackedStringArray(fired.keys())))

	# THE BODY, on the ward that is actually running, for somebody who is on it.
	var w = tree.get_first_node_in_group("ward_day")
	var game_node = tree.get_first_node_in_group("hospital")
	if w == null or game_node == null:
		_fail("no ward to put anybody on")
		return
	var who := String(Cases.roster()[0]["id"])
	var before := tree.get_nodes_in_group("visitor").size()
	w.visitor_arrived.emit(who, "Somebody's family")
	var visitors: Array = tree.get_nodes_in_group("visitor")
	_ok(visitors.size() > before,
		"and somebody is standing in the room when they are (%d)" % visitors.size())
	if visitors.size() <= before:
		return
	var them = visitors[visitors.size() - 1]
	var ps = tree.get_first_node_in_group("patient_system")
	var bed_body = ps.get_body(who) if ps != null else null
	if bed_body != null and is_instance_valid(bed_body):
		var d: float = them.global_position.distance_to(bed_body.global_position)
		_ok(d < 3.0, "at that patient's bed rather than somewhere in the ward (%.1fm)" % d)
	# And the suspicion layer knows about them, which is the whole reason a
	# visitor is interesting: `_who_can_see_me` walks every registered mind, so
	# a note typed in front of them is a note they saw.
	var sus = tree.get_first_node_in_group("suspicion_system")
	var known := false
	if sus != null:
		for m in sus.all_minds():
			if String(m.id).begins_with("visitor_"):
				known = true
	_ok(known, "and they are somebody the ward can be seen by")

## WHO IS ACTUALLY ON THIS WARD.
##
## Every check below used to name a patient — "oduya", "marchetti", "blake" —
## and a ward is five people drawn from a pool of ten per day. So this whole
## file could only ever run against ONE of the thirty-two boards the first ward
## alone can deal, and pointing it at any other seed produced eight failures
## that were all the harness naming somebody who was not there. The game was
## fine; the check could not see it.
##
## Picked off the roster instead, by the property each check actually needs.
func _anyone() -> String:
	var r := Cases.roster()
	return String(r[0]["id"]) if not r.is_empty() else ""

## Somebody the simulation says is genuinely unwell AND whom a second pair of
## eyes can see it in, for the checks that assert the nurse or the registrar
## agrees with you.
##
## `only_visible_in_person` is the whole point of Gwen Ashworth: the nurse goes,
## finds nothing, and writes that down. Picking her would fail a check that is
## asserting the nurse tells the truth — and she does.
func _someone_unwell() -> String:
	for c in Cases.roster():
		if not bool(c.get("truly_well", true)) \
				and not bool(c.get("only_visible_in_person", false)) \
				and not bool(c.get("colleague_wrong", false)):
			return String(c["id"])
	for c in Cases.roster():
		if not bool(c.get("truly_well", true)):
			return String(c["id"])
	return _anyone()

func _someone_well() -> String:
	for c in Cases.roster():
		if bool(c.get("truly_well", true)):
			return String(c["id"])
	return _anyone()

## Everybody, in roster order, for the checks that decide a whole ward.
func _all_ids() -> Array:
	var out: Array = []
	for c in Cases.roster():
		out.append(String(c["id"]))
	return out

## THE DAY DOES NOT END WITHOUT SAYING SO.
##
## At eight o'clock every undecided bed is sent home, the shift closes and the
## handover opens — and the first thing the game ever said about it was "Eight
## o'clock. He is in the corridor.", by which point it had already happened.
## The clock is in the corner so it was never hidden, but a game whose entire
## pressure is a deadline should count down to it, and the useful half of the
## warning is not the time. It is how many beds you have not decided about,
## which is the one thing the player cannot see without opening something.
func _check_the_day_gives_you_warning() -> void:
	var said: Array = []
	var grab := func(text: String, _kind: String): said.append(text)
	EventBus.toast.connect(grab)
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	# Straight through the last hour with nothing decided.
	w.advance_to(Cases.DEBT_DUE_MINUTE - 1)
	EventBus.toast.disconnect(grab)
	tree.root.remove_child(w)
	w.free()

	var warnings := 0
	var counted := false
	for t in said:
		for phrase in WardDay.LAST_CALL.values():
			if String(t).begins_with(String(phrase)):
				warnings += 1
				if String(t).contains("undecided"):
					counted = true
	_ok(warnings == WardDay.LAST_CALL.size(),
		"the last hour is called %d times, once each (%d)"
			% [WardDay.LAST_CALL.size(), warnings])
	_ok(counted, "and it says how many beds are still undecided")

	# AND THE REGISTRAR'S FOUR HOURS ARE ANNOUNCED. He is the strongest
	# corroboration a bed can have and he is here for four hours of twelve. The
	# patient screen says when he is next about, which only helps if you happen
	# to be looking at a patient — and the window you want him in is usually the
	# one you are busy in. Missing it was silent.
	#
	# Driven a minute at a time rather than by advancing a ward, because the
	# announcements hang off the WORLD clock — one ward, one voice — and this
	# file already has a live ward on the same clock that has been walked to
	# gone five by the checks above it.
	var heard: Array = []
	var listen := func(text: String, _kind: String): heard.append(text)
	EventBus.toast.connect(listen)
	var q := WardDay.new()
	tree.root.add_child(q)
	q.start()
	for m in range(Cases.DAY_START_MINUTE, Cases.DEBT_DUE_MINUTE):
		q._registrar_moves(m)
	EventBus.toast.disconnect(listen)
	tree.root.remove_child(q)
	q.free()

	var comings := 0
	var goings := 0
	for t in heard:
		if String(t) == "%s is on the ward." % WardDay.COLLEAGUE:
			comings += 1
		elif String(t).begins_with("%s has gone back" % WardDay.COLLEAGUE):
			goings += 1
	_ok(comings == WardDay.COLLEAGUE_HOURS.size(),
		"%s arriving is announced once per window (%d of %d)"
			% [WardDay.COLLEAGUE, comings, WardDay.COLLEAGUE_HOURS.size()])
	_ok(goings == WardDay.COLLEAGUE_HOURS.size(),
		"and so is him leaving (%d)" % goings)

## NOTHING CALLS AN AUTOLOAD METHOD THAT DOES NOT EXIST.
##
## `GameState.adjust_rep()` was called from two live code paths and had been
## deleted with the meta layer. Calling a method an autoload does not have
## throws, and a throw ABORTS the function it is in (CLAUDE.md 11) — so both
## paths died on that line and everything below them was unreachable:
##
##   * on a press day, a formal complaint produced no toast and never reached
##     the institutional mind, on the day the design comment promises
##     "everything costs roughly three times as much"
##   * a nurse who walked in on a tampered room said her line and then never
##     recorded that she had found it
##
## Neither errored anywhere anybody was looking, because the throw is the abort.
## This greps the source for `Autoload.method(` and asks the autoload whether it
## has one — the cheapest possible check for the most silent failure in the
## project.
const AUTOLOADS := ["GameState", "EventBus", "AudioMgr", "RNG", "DB", "Settings",
	"SaveSystem", "Log"]

func _check_nothing_calls_a_method_that_is_not_there() -> void:
	var missing: Array = []
	var checked := 0
	for path in _all_scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		for name in AUTOLOADS:
			var node := tree.root.get_node_or_null(NodePath(name))
			if node == null:
				continue
			for m in _calls_on(src, name):
				checked += 1
				# A property read looks the same to a regex; only flag things
				# that are definitely calls and definitely absent.
				if not node.has_method(m) and not (m in node):
					missing.append("%s.%s() in %s" % [name, m, path.get_file()])
	_ok(checked > 20, "%d autoload calls to check" % checked)
	_ok(missing.is_empty(), "and every one of them exists%s"
		% ("" if missing.is_empty() else " — " + ", ".join(PackedStringArray(missing))))

	# AND EVERY SOUND THE SOURCE ASKS FOR IS A SOUND THAT EXISTS.
	#
	# `AudioMgr._build` used to fall back to "beep" in silence for an unknown
	# name, so a typo played the wrong sound forever and the only way to notice
	# was to know what that action was meant to sound like. It says so now — but
	# only when the line actually runs, and half the sounds in this game belong
	# to verbs a smoke run never reaches. This reads the source instead.
	var bad_sounds: Array = []
	var sounds := 0
	for path in _all_scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		for line in src.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			var at := line.find("AudioMgr.play")
			while at >= 0:
				var q := line.find("\"", at)
				if q < 0:
					break
				var q2 := line.find("\"", q + 1)
				if q2 < 0:
					break
				var nm := line.substr(q + 1, q2 - q - 1)
				if nm.is_valid_identifier():
					sounds += 1
					if not AudioMgr.RECIPES.has(nm) and not bad_sounds.has(nm):
						bad_sounds.append("%s in %s" % [nm, path.get_file()])
				at = line.find("AudioMgr.play", q2)
	# The one table that names sounds as data rather than at the call site.
	for spec in AmbienceSystem.SPARSE:
		sounds += 1
		if not AudioMgr.RECIPES.has(String(spec[0])):
			bad_sounds.append("%s in AmbienceSystem.SPARSE" % String(spec[0]))
	_ok(sounds > 15, "%d sound names in the source" % sounds)
	_ok(bad_sounds.is_empty(), "and every one is a recipe that exists%s"
		% ("" if bad_sounds.is_empty() else " — " + ", ".join(PackedStringArray(bad_sounds))))

	# AND EVERY SETTING IS READ BY SOMETHING.
	#
	# CLAUDE.md 15, made automatic. `show_damage_flash` and `pad_vibration` were
	# both saved to disk, both restored on load, both defaulted, and both read
	# by NOTHING — one of them a setting for a health bar in a game that has
	# never had a health bar. A dead key is a promise the options menu is one
	# line away from making, and the only way to find one is to look for it.
	var dead: Array = []
	var src_all := ""
	for path in _all_scripts("res://scripts"):
		if path.ends_with("Settings.gd"):
			continue
		src_all += FileAccess.get_file_as_string(path)
	for key in Settings.DEFAULTS:
		if not src_all.contains("get_value(\"%s\")" % String(key)):
			dead.append(String(key))
	_ok(dead.is_empty(), "every one of the %d settings is read by something%s"
		% [Settings.DEFAULTS.size(), "" if dead.is_empty()
			else " — nothing reads " + ", ".join(PackedStringArray(dead))])

	# AND NOTHING TELLS THE PLAYER TO PRESS A KEY BY NAME.
	#
	# This game has a rebinding screen AND a controller layout, and three places
	# printed a key at the player from a string literal: the HUD's corner
	# reminder ("[E] use  [LMB] grab"), the carry prompt you see while holding
	# something ("[RMB] throw  [LMB] drop"), and the title screen ("WASD move ·
	# E use"). A player who moved "use" to F was told to press E for the rest of
	# their career, by three different parts of the game, and somebody on a pad
	# was told to press E by all of them. `Settings.prompt_label(action)` is the
	# only honest answer, and it knows about the pad.
	var hardcoded: Array = []
	for path in _all_scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		var n := 0
		for line in src.split("\n"):
			n += 1
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#") or trimmed.begins_with("##"):
				continue
			if not line.contains("\""):
				continue
			for bad in ["[E]", "[LMB]", "[RMB]", "[MMB]", "[Escape]", "WASD"]:
				if line.contains(bad):
					hardcoded.append("%s:%d %s" % [path.get_file(), n, bad])
	_ok(hardcoded.is_empty(), "no player-facing string names a key by hand%s"
		% ("" if hardcoded.is_empty()
			else " — " + ", ".join(PackedStringArray(hardcoded))))

	# AND EVERY GROUP THE SOURCE LOOKS SOMETHING UP IN HAS SOMETHING IN IT.
	#
	# `get_first_node_in_group("codex")` sat in `StaffNPC` for as long as the
	# Codex has been deleted — returning null, guarded by `if cdx:`, and reading
	# as a working feature to anybody scrolling past. A group lookup for a group
	# nothing joins is the same silent nothing as a call to a method that is not
	# there, and it is found the same way.
	var empty_groups: Array = []
	var group_names: Dictionary = {}
	for path in _all_scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		for line in src.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for call in ["get_first_node_in_group(\"", "get_nodes_in_group(\""]:
				var at := line.find(call)
				while at >= 0:
					var from: int = at + call.length()
					var end := line.find("\"", from)
					if end < 0:
						break
					group_names[line.substr(from, end - from)] = path.get_file()
					at = line.find(call, end)
	for g in group_names:
		if tree.get_first_node_in_group(String(g)) == null:
			empty_groups.append("%s (%s)" % [g, group_names[g]])
	_ok(group_names.size() >= 5, "%d groups looked up by name" % group_names.size())
	_ok(empty_groups.is_empty(), "and something is in every one of them%s"
		% ("" if empty_groups.is_empty()
			else " — nothing is in " + ", ".join(PackedStringArray(empty_groups))))

	# AND EVERY RECIPE ACTUALLY MAKES A NOISE.
	#
	# The check above proves every name the source asks for is in the table. It
	# says nothing about whether the table's entry SOUNDS like anything: every
	# sound in this game is synthesised from six numbers, and a decay of 90 on a
	# quarter-second sample, or a duration of zero, produces a perfectly valid
	# silent stream that no harness and no player can tell from a sound that
	# never played. Build all of them and look at the peak.
	var silent: Array = []
	for name in AudioMgr.RECIPES:
		var st: AudioStreamWAV = AudioMgr._build(String(name))
		if st == null or st.data.size() < 200:
			silent.append("%s (no samples)" % name)
			continue
		var peak := 0
		var d: PackedByteArray = st.data
		# Every 16th sample: a stream that is audible anywhere is audible on a
		# sixteenth of itself, and this runs over forty of them.
		for i in range(0, d.size() - 1, 32):
			var v: int = d[i] | (d[i + 1] << 8)
			if v >= 32768:
				v -= 65536
			peak = maxi(peak, absi(v))
		if peak < 2000:
			silent.append("%s (peak %d)" % [name, peak])
	_ok(silent.is_empty(), "all %d sound recipes make a noise%s"
		% [AudioMgr.RECIPES.size(), "" if silent.is_empty()
			else " — silent: " + ", ".join(PackedStringArray(silent))])

## `Name.method(` occurrences in a source file, outside comments.
func _calls_on(src: String, autoload: String) -> Array:
	var out: Array = []
	for line in src.split("\n"):
		var bare := line.strip_edges()
		if bare.begins_with("#"):
			continue
		var from := 0
		while true:
			var at := line.find(autoload + ".", from)
			if at < 0:
				break
			from = at + 1
			# Must be a whole word before the dot.
			if at > 0 and (line[at - 1].is_valid_identifier() or line[at - 1] == "_"):
				continue
			var rest := line.substr(at + autoload.length() + 1)
			var open := rest.find("(")
			if open <= 0:
				continue
			var name := rest.substr(0, open)
			if not name.is_valid_identifier():
				continue
			if not out.has(name):
				out.append(name)
	return out

func _all_scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := dir + "/" + f
		if d.current_is_dir():
			out.append_array(_all_scripts(full))
		elif f.ends_with(".gd"):
			out.append(full)
		f = d.get_next()
	d.list_dir_end()
	return out

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

## A TEST YOU PAID FOR COMES BACK.
##
## `end_day` sets `ended` and disconnects from the clock, and `_on_minute`
## returns early once `ended` is set — so every test still in flight when the
## shift closed was silently thrown away. `_unfulfilled_orders` then charged
## 0.30 a piece for "you ordered this and there is nothing to say it was ever
## done". Ordering bloods was punished twice: you paid five minutes for a result
## you never got, and the ward sister held the missing result against you.
func _check_tests_in_flight_come_back(_w) -> void:
	# ITS OWN WARD. This check has to END a day to prove the point, and the
	# shared one is mid-shift with a clock the checks above have already walked
	# to gone five — order a test on it and seventy-five minutes puts the result
	# past the handover, which is the one case that SHOULD stay unfulfilled.
	# The shared clock is put back afterwards, because `advance_to` writes it.
	var was := GameState.minute_of_day
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	var pid := String(Cases.roster()[0]["id"])
	w.advance_to(17 * 60)
	var o = w.order_test(pid, "Repeat bloods")
	_ok(o != null and o.fulfilled_by == "", "a test ordered at five is still out")
	if o == null:
		tree.root.remove_child(w); w.free()
		GameState.minute_of_day = was
		return
	# Sign off. Seventy-five minutes from five o'clock is 18:20, well before the
	# eight o'clock handover, so this one has to be back.
	var res: Dictionary = w.end_day()
	_ok(o.fulfilled_by != "",
		"and signing off does not throw it away — it is back by eight")
	var unfulfilled := 0
	for f in res["findings"]:
		if String(f.kind) == "unfulfilled_order":
			unfulfilled += 1
	_ok(unfulfilled == 0,
		"so nobody is charged for an order the lab did answer (%d findings)"
			% unfulfilled)
	tree.root.remove_child(w)
	w.free()
	GameState.minute_of_day = was

## THE NURSE ACTUALLY WALKS TO A BED.
##
## `_begin_round` targeted `h.point_in(p.room, ...)` and Patient has no `room`.
## Accessing a property that is not there aborts the function silently, so
## `_round_target` stayed empty and Adeyemi never once left the nurses' station
## in the entire life of the game. `_do_round` was worse: it called
## `unnoticed_complications()` and `notice_complication()` on PatientSystem and
## `acquired_injuries()` on Patient, none of which exist — all left over from a
## complications model that was deleted. The only reason none of it ever crashed
## is that the first dead property access killed the function before it reached
## the rest.
func _check_the_nurse_does_rounds() -> void:
	var nurse = null
	for n in _all_nodes(tree.root):
		# GUARDED. `get()` on a node without the property returns null, and
		# String(null) throws — which aborts this whole check mid-function
		# without erroring, so it asserted nothing and the smoke count did not
		# move. Same trap as CLAUDE.md 11, and the count is the only tell.
		if n.get("npc_id") == null:
			continue
		if String(n.get("npc_id")) == "nurse_0":
			nurse = n
			break
	if nurse == null:
		_fail("no nurse on the ward")
		return
	# Drive her into the state that starts a round, the way her own timer does.
	nurse.call("_enter", 6)          # State.TASK — enum index, checked
	var target := String(nurse.get("_round_target"))
	_ok(target != "",
		"the nurse picks somebody to go and look at%s"
			% ("" if target != "" else " — she never leaves the station"))
	if target == "":
		return
	# ...and it is a real patient, not a name from a table that no longer exists.
	var ps = tree.get_first_node_in_group("patient_system")
	_ok(ps != null and ps.get_patient(target) != null,
		"and the person she picked is on this ward (%s)" % target)

## SOMEBODY YOU SEND HOME GOES HOME.
##
## `PatientNPC.discharge_and_leave()` was written carefully — it wakes them,
## frees the bed, walks them to the corridor and gives them a line on the way —
## and had no callers anywhere in the project. So a patient discharged at nine in
## the morning lay in the bed until eight at night, and a ward where you had sent
## four people home looked identical to one where you had sent nobody. The single
## decision this entire game is made of had no visible consequence in the world.
func _check_discharged_patients_leave(w) -> void:
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		_fail("no patient system")
		return
	var pid := ""
	for c in Cases.roster():
		if bool(c.get("truly_well", true)):
			pid = String(c["id"])
			break
	if pid == "":
		_fail("no well patient to send home")
		return
	var body = ps.get_body(pid)
	_ok(body != null, "%s has a body before you send them home" % pid)
	if body == null:
		return
	var bed_before = body.get("bed")
	w.set_disposition(pid, "discharge")
	_ok(int(body.get("state")) == 4,
		"and deciding to send them home puts them on their feet (state %d)"
			% int(body.get("state")))
	_ok(bed_before != null and bed_before.occupant == null,
		"and frees the bed they were in")

## WRITING IN FRONT OF SOMEBODY IS SOMETHING THEY NOTICE.
##
## The two halves of this game were not connected. The paperwork crime is
## audited at eight o'clock through `seen_by`; the suspicion layer — nametag
## colour, staff stopping to watch you, following you round the ward — is fed
## only by WorldEvents, and the only emitters were a slammed door, a thrown prop
## and a patient getting out of bed. A doctor who spent the shift writing
## fabrications at the bedside was watched exactly as closely as one who wrote
## nothing, so the observable crime produced no observation and the stealth
## layer had nothing to do with the game.
func _check_writing_is_observed(w) -> void:
	var sus = tree.get_first_node_in_group("suspicion_system")
	var p = tree.get_first_node_in_group("player")
	var h = tree.get_first_node_in_group("hospital")
	if sus == null or p == null or h == null:
		_fail("no ward to be observed in")
		return
	var pid := String(Cases.roster()[0]["id"])
	# In the bay, where the patients are.
	p.global_position = h.point_in("ward")
	var before := _total_evidence(sus)
	# A PATTERN, not one note. The event is weighted low on purpose — a doctor
	# writing at a bedside is also just a doctor writing at a bedside — and
	# perception is a roll against observance and distance rather than a
	# threshold, so any single note may well go unnoticed. What must not happen
	# is a whole shift of them going unnoticed.
	for i in 8:
		w.write_entry(pid, ChartEntry.Claim.UNWELL, "Unsettled.", w.minute,
			WardDay.TERMINAL_WARD)
	var after := _total_evidence(sus)
	_ok(after > before,
		"writing notes where people can see you gets noticed (%d -> %d)"
			% [before, after])
	# ...and in the office, with the door shut, it is not.
	p.global_position = h.point_in("office")
	var mid := _total_evidence(sus)
	for i in 8:
		w.write_entry(pid, ChartEntry.Claim.UNWELL, "Unsettled.", w.minute,
			WardDay.TERMINAL_OFFICE)
	_ok(_total_evidence(sus) == mid,
		"and writing it in your own office is not, which is the whole point")

func _total_evidence(sus) -> int:
	var n := 0
	for id in sus.minds:
		var m = sus.minds[id]
		if m != null:
			n += Array(m.evidence).size()
	return n

## THE PEOPLE THE CARD PROMISES ACTUALLY TURN UP.
##
## The End of Shift card says, in as many words, "Ms Ferrand from Coding is on
## the ward for the next two shifts. She is not there to help" and "there is a
## man in the corridor". Both are gated on flags — `auditor_present`,
## `vinnie_visits` — that are written by that card, at the END of a night. Both
## spawns live in `Game._spawn_staff`, which runs in `_ready`. And a career never
## reloads Game.tscn: the day rolls over in place through `_carry` and
## `PatientSystem.reset_day`. So `_ready` never ran again, and neither of them
## could ever appear, for the entire life of the feature — the game made a
## specific promise on its most dramatic screen and never once kept it.
func _check_the_promised_visitors_arrive() -> void:
	var before := _count_visitors()
	_ok(before == 0, "nobody from Coding is here on a clean day (%d)" % before)
	GameState.set_flag("auditor_present", true)
	GameState.set_flag("vinnie_visits", true)
	GameState.start_day()
	var after := _count_visitors()
	_ok(after == 2, "and after a bad night both of them are on the ward (%d)" % after)
	# ...and they go away again when the ward is clean.
	GameState.set_flag("auditor_present", false)
	GameState.set_flag("vinnie_visits", false)
	GameState.start_day()
	_ok(_count_visitors() == 0, "and they leave when the ward is clean again")

func _count_visitors() -> int:
	var n := 0
	for c in _all_nodes(tree.root):
		if not c.has_method("get"):
			continue
		var who := String(c.get("npc_id")) if c.get("npc_id") != null else ""
		if (who == "auditor" or who == "vinnie") and c.is_inside_tree():
			n += 1
	return n

## THE TUTORIAL CAN REACH ITS LAST LINE.
##
## `note()` had exactly one caller — the chart-opened hook — so `_index` could
## only ever reach 1. Step two was shown forever, step three (the only line in
## the running game that states the premise) could never fire, and because the
## run never completed, `tutorial_done` was never set: a returning player was
## re-tutorialised every morning of their career. Three toasts is the entire
## onboarding and two thirds of it was unreachable.
func _check_the_tutorial_finishes() -> void:
	var t = tree.get_first_node_in_group("tutorial")
	if t == null:
		_fail("no tutorial system in the tree")
		return
	var w = tree.get_first_node_in_group("ward_day")
	if w == null:
		_fail("no ward to drive the tutorial with")
		return
	GameState.set_flag("tutorial_done", false)
	t.set("_active", true)
	t.set("_index", 0)
	if t.has_method("_hook_the_ward"):
		t.call("_hook_the_ward")
	# Step one: open a chart.
	EventBus.request_ui.emit("chart", {"patient_id": String(Cases.roster()[0]["id"])})
	_ok(int(t.get("_index")) >= 1, "opening a chart advances the tutorial")
	# Step two: write something.
	w.write_entry(String(Cases.roster()[0]["id"]), ChartEntry.Claim.UNWELL,
		"Reviewed.", w.minute)
	_ok(int(t.get("_index")) >= 2, "and writing a note advances it again")
	# Step three: decide a bed. This is the one that states the premise.
	w.set_disposition(String(Cases.roster()[0]["id"]), "hold")
	_ok(bool(GameState.flag("tutorial_done", false)),
		"and deciding a bed finishes it, so it does not run again tomorrow")
	# ...and the line it says is built from the economy rather than typed.
	var owed := String(t.call("_owed_line")) if t.has_method("_owed_line") else ""
	_ok(owed.find(UIKit.money_str(Cases.DEBT_DUE)) >= 0,
		"and the premise line quotes what Vinnie actually wants (%s)" % owed)

## EVERY ROOM NAME IN THE SOURCE IS A ROOM THAT EXISTS.
##
## `Hospital.point_in` push_errors and returns Vector3.ZERO for a room it does
## not have, and push_error goes to a log nobody reads during play. Four rooms
## were demolished in the redesign — `lobby`, `day_room`, `ward_101`,
## `ward_105`, `supply` — and five call sites went on asking for them: the
## ambience system picked four of its six rooms from that list, so two thirds of
## the hospital's ambient sound came from the one corner where the corridor
## meets the station, on a 30m falloff in a 29m building, and the five-bed bay
## where the whole game happens was never named at all. A discharged patient
## walked to the origin instead of out; so did a leaving visitor.
##
## Greps the source rather than exercising the paths, because the wandering and
## discharge branches are rare and the ambience one is a random pick — none of
## them is reliably reachable in a smoke run, which is exactly why they survived.
func _check_every_room_named_in_source_exists() -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null:
		_fail("no hospital")
		return
	var known := {}
	for r in h.room_list():
		known[String(r.key)] = true
	var bad: Array = []
	var checked := 0
	for path in ["res://scripts/systems/ambience.gd", "res://scripts/npc/patient_npc.gd",
			"res://scripts/npc/visitor_npc.gd", "res://scripts/npc/staff_npc.gd",
			"res://scripts/core/game.gd", "res://scripts/systems/patient_system.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		# COMMENTS ARE NOT CALL SITES. The first run of this failed on
		# `day_room` and the only remaining mention of it in the project was the
		# comment explaining that it had been removed.
		var lines: PackedStringArray = f.get_as_text().split("\n")
		f.close()
		var kept: PackedStringArray = PackedStringArray()
		for ln in lines:
			if String(ln).strip_edges().begins_with("#"):
				continue
			kept.append(String(ln))
		var src := "\n".join(kept)
		var re := RegEx.new()
		re.compile('point_in\\(\\s*"([a-z_0-9]+)"')
		for m in re.search_all(src):
			checked += 1
			var key := m.get_string(1)
			if not known.has(key) and not bad.has(key):
				bad.append(key)
		# ...and the room lists the ambience system picks from by name.
		var re2 := RegEx.new()
		re2.compile('ambience_room",\\s*\\[([^\\]]*)\\]')
		for m2 in re2.search_all(src):
			for raw in m2.get_string(1).split(","):
				var k := raw.strip_edges().replace('"', "")
				if k == "":
					continue
				checked += 1
				if not known.has(k) and not bad.has(k):
					bad.append(k)
	_ok(checked > 5, "there are room names in the source to check (%d)" % checked)
	_ok(bad.is_empty(), "and every one of them is a room that exists%s"
		% ("" if bad.is_empty() else ": " + ", ".join(bad)))

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
	# The one the simulation says is genuinely unwell, because two of these
	# assert that a second pair of eyes AGREES — which is only true of somebody
	# who actually has something wrong with them.
	var ill := _someone_unwell()
	var was_entries: int = _entries_for(w, ill)
	var before: int = w.minute
	var found: String = w.examine(ill)
	_ok(found.length() > 20, "you can go and look at somebody, and it tells you something")
	_ok(w.minute > before, "and it costs a quarter of an hour of the shift")
	_ok(_entries_for(w, ill) == was_entries,
		"and it writes nothing down, which is the point of it")
	var again: int = w.minute
	w.examine(ill)
	_ok(w.minute == again, "looking twice is free — the cost is for learning, not remembering")

	# The registrar keeps his own hours, so the harness has to be at one of them.
	w.advance_to(11 * 60 + 30)
	_ok(WardDay.colleague_available(w.minute), "%s is on the ward at half eleven" % WardDay.COLLEAGUE)
	var peer = w.ask_colleague(ill)
	_ok(peer != null and peer.author == ChartEntry.Author.DOCTOR,
		"a colleague can be asked, and writes in his own name")
	_ok(peer.supports_stay(),
		"and about the one who is genuinely unwell, he backs you in writing")
	w.advance_to(14 * 60)
	_ok(not WardDay.colleague_available(w.minute),
		"at two o'clock he is on the other ward and cannot be asked at all")
	_ok(w.ask_colleague(_someone_well()) == null, "and asking anyway does nothing")

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
	var corridor_pid := _anyone()
	w.write_entry(corridor_pid, ChartEntry.Claim.UNWELL, "Headache recurred.", at)
	w.set_disposition(corridor_pid, "hold")
	var kinds: Array = []
	for f in w.review_findings():
		kinds.append(f.kind)
	_ok(kinds.has("author_elsewhere"),
		"and a bedside note timed for a minute you were seen in the corridor is a finding")
	w.set_disposition(corridor_pid, "")

func _check_the_day_closes() -> void:
	var w = tree.get_first_node_in_group("ward_day")
	if w == null:
		return
	# Hold the first two, send the rest home. The point of the check is that a
	# day ENDS and produces something for the reviewer, not which two — and
	# naming five people meant this could only run on the one ward that has
	# them.
	var i := 0
	for id in _all_ids():
		w.set_disposition(String(id), "hold" if i < 2 else "discharge")
		i += 1
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
			["patient", {"patient_id": _anyone()}],
			["chart", {"patient_id": _anyone()}],
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
	# AND EVERY ONE OF THEM DOES SOMETHING WHEN IT IS PRESSED.
	#
	# `UIKit.button` guards its callback with `cb.is_valid()`, so a button built
	# with an empty Callable is a button that clicks, lights up under the mouse
	# and does nothing — and looks correct in a screenshot. Two connections is
	# the floor: the click noise UIKit wires itself, and what the button is FOR.
	var inert: Array[String] = []
	for b in buttons:
		if b.pressed.get_connections().size() < 2:
			inert.append(b.text)
	_ok(inert.is_empty(), "and pressing any of them does something%s"
		% ("" if inert.is_empty() else " — inert: " + ", ".join(inert)))
	# AND SOMETHING ON IT IS SELECTED.
	#
	# Not decoration: navigation with a pad or the arrow keys starts from
	# whatever holds focus, and for the life of this project nothing ever took
	# it — so the D-pad moved a selection that did not exist and every screen in
	# the game was mouse-only. `UIKit.focus_first` is called on the way in; this
	# is the check that it stays called.
	var vp := tree.root.get_viewport()
	var holder: Control = vp.gui_get_focus_owner() if vp else null
	_ok(holder != null, "and the %s screen has a selection on it for a pad%s"
		% [name, "" if holder != null else " — nothing has focus"])
	# AND THE VIEW FOLLOWS IT DOWN THE PAGE.
	#
	# `ScrollContainer.follow_focus` defaults to FALSE, and every long card in
	# this game is a scroll region — the settings screen, the key bindings, the
	# list of verbs on a patient. Without it the selection walks off the bottom
	# of the visible area and keeps going with nothing moving on screen, which
	# is indistinguishable from navigation not working at all. Asserted as a
	# PROPERTY rather than by measuring the scroll offset, because under
	# --headless the root window is 64 pixels tall and no layout is real
	# (CLAUDE.md 19); the offset was watched move from 0 to 143 under Xvfb.
	var unfollowing: Array[String] = []
	_scrollers(ui, unfollowing)
	_ok(unfollowing.is_empty(), "and the view follows it down the %s screen%s"
		% [name, "" if unfollowing.is_empty()
			else " — " + ", ".join(unfollowing) + " does not follow focus"])
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

func _scrollers(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is ScrollContainer and not (c as ScrollContainer).follow_focus:
			out.append(String(c.name))
		_scrollers(c, out)

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
			"remembered": PackedStringArray([_anyone()])}
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

## A CARD REBUILDS ITSELF AFTER EVERY ACTION TAKEN ON IT.
##
## Which is the moment the selection is easiest to lose: `rebuild()` frees every
## control on the screen and builds new ones, and the first version of the focus
## code grabbed focus on a button that was already queued for deletion — so a
## pad player could open a card, press one thing, and find the selection gone
## with no way to get it back except a mouse. Worse, `gui_get_focus_owner()`
## then returns a FREED control, and reading that into a typed local aborts the
## function that was about to fix it (CLAUDE.md 11).
func _check_a_rebuilt_card_still_has_a_selection() -> void:
	var ui = game.get("ui")
	if ui == null:
		return
	EventBus.request_ui.emit("patient", {"patient_id": _anyone()})
	_defer(4, func():
		var vp := tree.root.get_viewport()
		var before = vp.gui_get_focus_owner() if vp else null
		_ok(is_instance_valid(before), "a card opens with a selection on it")
		# AND THE CROSSHAIR LABEL STAYS DOWN WHILE IT IS UP. The patient card
		# deliberately does not pause the world, so the interactor keeps
		# raycasting and keeps emitting the bedside prompt for the very person
		# the card is about — a crosshair label with no crosshair under it.
		# Emitted by hand, because a smoke run's doctor is not necessarily
		# looking at anybody and "it was already hidden" is not the assertion.
		var hud = tree.get_first_node_in_group("hud")
		EventBus.interact_prompt.emit("Talk to somebody", "and it should not show")
		_ok(hud != null and not hud._prompt_panel.visible,
			"and nothing the crosshair would have said gets in behind it")
		if ui.current != null and ui.current.has_method("rebuild"):
			ui.current.rebuild()
		_defer(6, func():
			var vp2 := tree.root.get_viewport()
			var after = vp2.gui_get_focus_owner() if vp2 else null
			_ok(is_instance_valid(after),
				"and still has one after it rebuilds itself")
			if ui.has_method("close"):
				ui.call("close")))

## "PRESS A KEY…" HAS TO HAVE A WAY OUT OF IT.
##
## Pad bindings are deliberately fixed, so `Settings.rebind` refuses a joypad
## event — which meant somebody who pressed A on a binding row got "press a
## key…" and, with no keyboard in reach, nothing that would end it: B is not a
## key either, so the row listened for ever. And every way out of the screen
## except the two buttons that cleared it by hand left `_listening_for` set, so
## the next visit opened already waiting for a key nobody had asked it to want.
func _check_the_rebind_row_can_be_escaped() -> void:
	var ui = game.get("ui")
	if ui == null:
		return
	ui.open("controls", {})
	ui._start_listening("interact")
	_ok(String(ui._listening_for) == "interact", "a binding row can be armed")
	var pad := InputEventJoypadButton.new()
	pad.device = 0
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	ui._input(pad)
	_ok(String(ui._listening_for) == "",
		"and a pad button gets back out of it")
	# ...AND CLOSING THE SCREEN DISARMS IT.
	ui._start_listening("interact")
	ui.close()
	_ok(String(ui._listening_for) == "",
		"and leaving the screen stops it listening")
	# ...AND REBINDING STILL WORKS, which is the thing all of that is guarding.
	ui.open("controls", {})
	ui._start_listening("interact")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.physical_keycode = KEY_F
	key.pressed = true
	ui._input(key)
	_ok(Settings.binding_label("interact") == "F",
		"and a key still rebinds (%s)" % Settings.binding_label("interact"))
	Settings.reset_bindings()
	if ui.has_method("close"):
		ui.call("close")

func _fail(msg: String) -> void:
	errors.append(msg)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		notes.append("  ok: " + msg)
	else:
		errors.append(msg)

func _report() -> void:
	if not _later.is_empty():
		_fail("%d deferred check(s) never ran" % _later.size())
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
	# THE SEED THIS RUN IS ON, not the default. Restoring 20260821 by name here
	# put every check after this one back on a different ward from the one the
	# run was pointed at, which is invisible until the run is pointed anywhere.
	GameState.start_new_career(seed)
	GameState.set_flag("tutorial_done", true)
