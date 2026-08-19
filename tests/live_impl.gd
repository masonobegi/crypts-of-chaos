extends RefCounted
## Live simulation test: runs the real game with real FRAMES, so NPCs actually
## move, patrol, do rounds, gossip, investigate and react.
##
## The smoke run drives the clock in a tight loop with no frames between steps,
## which means it never executes a single line of NPC behaviour. Everything in
## scripts/npc/ was effectively untested at runtime — a crash in a state machine
## would have shipped.

## Headless iterates as fast as it can, so a frame is a small slice of real
## time rather than 1/60s of simulated time. This needs to be generous enough
## for NPC state machines to cycle several times.
const FRAMES := 7000

var tree: SceneTree = null
var game: Node = null
var frames := 0
var errors: Array[String] = []
var notes: Array[String] = []

var _start_positions: Dictionary = {}
var _seen_gossip := false
var _seen_noticed := false
var _seen_bark := false
var _rooms_visited: Dictionary = {}
var _investigator_moved := false
var _investigator_seen := false
## instance id -> where we first saw it. Tracked per body because an
## investigator that finishes its round leaves and frees itself, and "it walked
## its round and went home" is a pass, not a missing NPC.
var _inv_start: Dictionary = {}

func start() -> void:
	GameState.start_new_career(555111)
	GameState.set_flag("tutorial_done", true)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	EventBus.rumor_spread.connect(func(_a, _b, _c): _seen_gossip = true)
	EventBus.subtitle.connect(func(_s, _t, _x): _seen_bark = true)

func tick() -> bool:
	frames += 1
	tree.paused = false

	if frames == 20:
		_begin()
	if frames > 20:
		# Push the clock along so hourly and daily behaviour fires too.
		for i in 3:
			GameState._advance_minute()
	if frames == 60:
		_seed_conditions()
	if frames % 60 == 0:
		_sample()
	if frames < FRAMES:
		return false
	_finish()
	return true

func _begin() -> void:
	if game.ui != null and game.ui.current != null:
		game.ui.close()
	game.shift.clock_in()
	# Only staff are expected to walk about; patients are in beds and are in the
	# npc group too, so counting them would make the movement check meaningless.
	for n in tree.get_nodes_in_group("staff"):
		_start_positions[n.get_instance_id()] = n.global_position

## Give the ward something to react to: an undocumented complication for the
## rounds to find, and a visible investigation to walk the floor.
func _seed_conditions() -> void:
	# Every patient, not just the first: a nurse picks whom to check at random,
	# and the test should be exercising the rounds mechanic rather than the
	# odds of her choosing the one bed that was seeded.
	for p in game.patient_system.active():
		game.patient_system.add_complication(p, "ferrous_aura", "machine_deviation")
	game.investigations.open("inspector", 0)

func _sample() -> void:
	# Staff reaching wards at all is the thing that was silently broken: closed
	# doors made every ward unreachable and nothing noticed for weeks.
	for n in tree.get_nodes_in_group("staff"):
		var r: String = n.current_room()
		if r != "":
			_rooms_visited[r] = true
	for p in game.patient_system.active():
		for c in p.active_complications():
			if c.noticed_time >= 0:
				_seen_noticed = true
	for n in tree.get_nodes_in_group("investigator"):
		_investigator_seen = true
		var key := n.get_instance_id()
		if not _inv_start.has(key):
			_inv_start[key] = n.global_position
		elif n.global_position.distance_to(_inv_start[key]) > 2.0:
			_investigator_moved = true

func _finish() -> void:
	var moved := 0
	var total := 0
	for n in tree.get_nodes_in_group("staff"):
		if not _start_positions.has(n.get_instance_id()):
			continue
		total += 1
		if n.global_position.distance_to(_start_positions[n.get_instance_id()]) > 1.0:
			moved += 1

	_ok(total > 0, "staff exist to simulate (%d)" % total)
	# A lazy nurse legitimately stays put, so not everyone has to move — but if
	# NOBODY moved, the AI is not running.
	_ok(moved > 0, "staff moved under their own AI (%d of %d)" % [moved, total])
	_ok(_rooms_visited.size() >= 3,
		"staff reached several different rooms (%s)" % ", ".join(
			PackedStringArray(_rooms_visited.keys())))
	_ok(_seen_bark, "somebody said something")
	_ok(_seen_noticed, "a nurse or visitor noticed an undocumented complication")
	_ok(_investigator_seen, "a visible investigation put somebody on the floor")
	_ok(_investigator_moved, "the investigator walked its round")

	# The player must not have fallen through the floor or got stuck in geometry.
	_ok(game.player.global_position.y > -2.0, "player is still on the floor")
	# Navigation must still be intact after all the physics.
	var path = game.hospital.nav.find_path(
		game.hospital.point_in("lobby"), game.hospital.point_in("ward_105"))
	_ok(path.size() > 0, "the floor is still navigable after a live shift")
	# Patients must have progressed.
	var progressed := false
	for p in game.patient_system.active():
		if p.recovery > 0.01 or p.days_admitted > 0.01:
			progressed = true
	_ok(progressed, "the simulation advanced patient state")
	_report()

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
		print("LIVE RUN PASSED — %d checks over %d frames" % [notes.size(), FRAMES])
	else:
		print("LIVE RUN FAILED — %d problem(s):" % errors.size())
		for e in errors:
			printerr("  " + e)
	print("--------------------------------------\n")
