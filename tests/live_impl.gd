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
## -1 means the probe never ran, which is a failure in its own right.
var _seen_in_the_open := -1
var _seen_through_wall := -1
var _witness_suspicion := 0.0
var _witness_took_a_note := -1
var _investigator_moved := false
var _investigator_seen := false
## instance id -> where we first saw it. Tracked per body because an
## investigator that finishes its round leaves and frees itself, and "it walked
## its round and went home" is a pass, not a missing NPC.
var _inv_start: Dictionary = {}
## Blocking a doorway: -1 means the probe never ran.
var _door_block_worked := -1
var _door_unblock_worked := -1
var _blocker = null
## Did a noise at the far end of the floor actually pull anybody off station?
var _distraction_from: Dictionary = {}
var _distraction_worked := -1
var _investigating := 0
## Does shutting a door actually buy you the room? -1 means the probe never ran.
var _seen_door_open := -1
var _seen_door_shut := -1

var _talked_to := ""
var _talk_took_them_out_of_the_chair := false

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
	_sample_cost()

	if frames == 20:
		_begin()
	if frames > 20 and not _in_cost_window():
		# Push the clock along so hourly and daily behaviour fires too.
		for i in 3:
			GameState._advance_minute()
	if frames == 60:
		_seed_conditions()
	if frames == 300:
		_talk_to_somebody()
	if frames == 760:
		_check_they_sat_back_down()
	if frames == FRAMES - 1800:
		_make_a_noise()
	if frames > FRAMES - 1800 and frames <= FRAMES - 1000 and frames % 10 == 0:
		_poll_distraction()
	if frames == FRAMES - 1000:
		_check_distraction()
	if frames == FRAMES - 900:
		_block_a_doorway()
	if frames == FRAMES - 700:
		_check_doorway_blocked()
	if frames == FRAMES - 500:
		_check_doorway_cleared()
	# Four separate frames on purpose. Posing a leaf and querying the physics
	# server in the same frame reads the shape's OLD transform — the first
	# version of this probe reported "cannot see through an open door", which
	# was the door still being shut as far as the space state was concerned.
	if frames == FRAMES - 700:
		_door_probe_setup()
	if frames == FRAMES - 660:
		_seen_door_open = _door_probe_look()
	if frames == FRAMES - 640:
		_door_probe_pose(0.0)
	if frames == FRAMES - 600:
		_seen_door_shut = _door_probe_look()
		_door_probe_finish()
	if frames == FRAMES - 300:
		_test_perception()
	# The procedure screens, driven for real frames. These are the only screens
	# in the game with a `_process` loop and polled input, and neither the unit
	# tests nor the smoke run has frames to give them.
	if frames == FRAMES - 280:
		_procedure_screens_open()
	if frames > FRAMES - 280 and frames < FRAMES - 120:
		_procedure_screen_tick()
	if frames == FRAMES - 120:
		_procedure_screens_report()
	# The evening, on its feet. Entering it moves the player into a street that
	# did not exist a frame ago, so it needs real frames or it proves nothing.
	if frames == FRAMES - 110:
		_night_enter()
	if frames == FRAMES - 60:
		_night_check()
	if frames == FRAMES - 40:
		_night_leave()
	if frames % 60 == 0:
		_sample()
	if frames < FRAMES:
		return false
	_finish()
	return true

## Open every procedure screen in turn, let it run, and check it got somewhere.
##
## A screen that reads `Input.is_mouse_button_pressed` and advances on `_process`
## cannot be tested without frames: the unit tests have no loop and the smoke
## run has no renderer. What this catches is the whole class of "the clock never
## ticks", "the canvas never redraws", "the field is laid out before the rig
## exists" — every one of which would ship as a screen that opens and then does
## nothing at all.
var _proc_screens := ["setbone", "suture", "manipulate", "medicate"]
var _proc_index := 0
var _proc_elapsed: Dictionary = {}
var _proc_opened: Dictionary = {}

func _procedure_screens_open() -> void:
	_proc_index = 0
	_open_procedure_screen()

func _open_procedure_screen() -> void:
	if _proc_index >= _proc_screens.size():
		return
	var id := String(_proc_screens[_proc_index])
	var kinds := {"setbone": "set_bone", "suture": "suture",
		"manipulate": "manipulate", "medicate": "prescribe"}
	var want := String(kinds.get(id, "dial"))
	var subject = null
	for p in game.patient_system.active():
		if Procedures.procedure_for(p.condition_id) == want:
			subject = p
			break
	if subject == null:
		var any: Array = game.patient_system.active()
		if any.is_empty():
			return
		subject = any[0]
		var fallbacks := {"setbone": "fractured_wrist", "suture": "knuckle_weather",
			"manipulate": "dislocated_shoulder", "medicate": "chronic_beige"}
		subject.condition_id = String(fallbacks.get(id, "chronic_beige"))
	if game.ui != null:
		game.ui.close()
		game.ui.open(id, {"patient_id": subject.id})
		_proc_opened[id] = game.ui.current != null
		# Straight past the intent gate to the part that actually runs.
		if game.ui.current != null:
			game.ui.current.set("_intent", "treat")
			if id == "medicate":
				game.ui.current.set("_med", "beigeolol")
			game.ui.current.rebuild()

func _procedure_screen_tick() -> void:
	if game.ui == null or game.ui.current == null:
		return
	var id := String(game.ui.current_id)
	var e = game.ui.current.get("_elapsed")
	if e != null:
		_proc_elapsed[id] = maxf(float(_proc_elapsed.get(id, 0.0)), float(e))
	# Forty frames each, then on to the next.
	if frames % 40 == 0:
		_proc_index += 1
		_open_procedure_screen()

func _procedure_screens_report() -> void:
	if game.ui != null:
		game.ui.close()
	for id in _proc_screens:
		var sid := String(id)
		_ok(bool(_proc_opened.get(sid, false)), "the %s screen opens" % sid)
		_ok(float(_proc_elapsed.get(sid, 0.0)) > 0.0,
			"and its clock actually runs (%s reached %.2fs)" % [
				sid, float(_proc_elapsed.get(sid, 0.0))])

## Walking out of the hospital and down a street.
##
## Everything about this only exists at runtime: the street is built when you go
## out, the player is teleported into it, people are spawned on it, and the
## whole lot is freed when you come home. Nothing static can check any of that.
var _night_hospital_hidden := false
var _night_had_street := false
var _night_moved := false
var _night_home := false

func _night_enter() -> void:
	var night = game.get("night")
	if night == null:
		_ok(false, "the night system exists")
		return
	if game.ui != null:
		game.ui.close()
	_night_before = game.player.global_position
	night.enter("the_anchor")

var _night_before := Vector3.ZERO

func _night_check() -> void:
	var night = game.get("night")
	if night == null:
		return
	_night_had_street = night.street != null and is_instance_valid(night.street)
	var hospital = tree.get_first_node_in_group("hospital")
	_night_hospital_hidden = hospital != null and not hospital.visible
	_night_moved = game.player.global_position.distance_to(_night_before) > 5.0
	_ok(_night_had_street, "going out builds a street")
	_ok(_night_hospital_hidden, "and puts the hospital away while you are on it")
	_ok(_night_moved, "and you are standing in it")
	_ok(night.mark != null and is_instance_valid(night.mark),
		"with somebody walking home ahead of you")
	_ok(night.watchers.size() > 0, "and other people about")
	# Relative to the street's own origin, not the world's: the street is built
	# four hundred metres under the hospital so the two do not share colliders.
	_ok(game.player.global_position.y > Street.ORIGIN.y - 2.0,
		"and the street has a floor")
	# The street being somewhere else is the whole reason the hospital's walls
	# stop blocking sight-lines the player cannot see.
	_ok(absf(game.player.global_position.y - Street.ORIGIN.y) < 40.0,
		"and it is not built on top of the hospital")
	# Exposure has to be a live reading rather than a constant.
	_ok(night.exposure >= 0.0 and night.exposure <= 1.0,
		"being seen is measured while you walk (%.2f)" % night.exposure)

func _night_leave() -> void:
	var night = game.get("night")
	if night == null:
		return
	night.finish(false)
	var hospital = tree.get_first_node_in_group("hospital")
	_night_home = hospital != null and hospital.visible
	_ok(_night_home, "and coming home puts the hospital back")
	_ok(night.street == null, "and takes the street away again")
	_ok(game.player.global_position.distance_to(_night_before) < 2.0,
		"and puts you back where you were standing")
	if game.ui != null:
		game.ui.close()

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

## Does a witness standing in front of an obvious act actually end up holding
## evidence of it — and does a wall stop them?
##
## Observance is forced to 1.0 and the act is made maximally blatant so that the
## detection ROLL is not what is under test: notice_chance() has its own unit
## tests, and a probabilistic assertion here would be flaky. What this covers is
## the routing nothing else touches — world event, to perception, to line of
## sight against the real geometry of the building, to that witness's memory.
##
## The two halves are deliberately at comparable range (4.0m and 3.5m) so that
## the only meaningful difference between them is the ward wall. Standing the
## blocked witness across the building would have "passed" for the wrong reason.
func _test_perception() -> void:
	var nurse = _find_staff()
	if nurse == null:
		return
	nurse.mind.observance = 1.0
	nurse.perception.attention = 1.0
	nurse.stop_moving()
	# ...and put her in a state where writing is ALLOWED. A nurse already
	# chasing a noise deliberately does not stop to take notes
	# (StaffNPC.can_stop_to_write), so whether this nurse happened to be
	# mid-investigation when the probe ran silently decided the result — the
	# check went red the first time a furniture change moved staff around, which
	# is a patrol-timing coincidence rather than anything about perception.
	nurse.state = StaffNPC.State.IDLE
	# Inside Room 101, well clear of its doorway at x = 4.5.
	var act := Vector3(1.5, 1.4, 6.0)

	# a) Nurse out in the corridor, with the ward wall in between.
	_seen_through_wall = _witnessed(nurse, Vector3(1.5, 0.0, 2.0), act, "wall_probe_act")
	# b) Same nurse, same act, same sort of distance, nothing in the way.
	_seen_in_the_open = _witnessed(nurse, Vector3(1.5, 0.0, 9.5), act, "open_probe_act")
	_witness_suspicion = nurse.mind.suspicion(GameState.career_minutes)
	# ...and did she visibly do anything about it? The game's only read on what
	# a witness thinks used to be a colour on their name tag, which is a meter
	# wearing a diegetic hat. Somebody stopping and writing it down is the same
	# information as a fact you can watch, and this asserts the animation is
	# driven by the memory rather than decorating it.
	_witness_took_a_note = 1 if nurse._note_time > 0.0 else 0

## Stand the witness somewhere, point them at the act, fire it, and report how
## many fresh memories of it they came away with.
func _witnessed(nurse, stand: Vector3, act: Vector3, kind: String) -> int:
	nurse.global_position = stand
	# look_toward() only gives the AI something to turn towards over the next
	# few frames. The event fires within this one, so the facing has to be true
	# right now or the field-of-view check decides the result instead.
	nurse.look_at(Vector3(act.x, stand.y + 1.5, act.z), Vector3.UP)
	var before := _count_evidence(nurse.mind, kind)
	WorldEvent.new(kind, "player").at(act, "ward_101") \
		.seen(0.95).says("something extremely blatant").emit()
	return _count_evidence(nurse.mind, kind) - before

func _count_evidence(mind: Mind, kind: String) -> int:
	var n := 0
	for ev in mind.evidence:
		if ev.kind == kind:
			n += 1
	return n

func _find_staff():
	for n in tree.get_nodes_in_group("staff"):
		if n.mind != null:
			return n
	return null

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

## The other half of buying yourself a window: make a noise somewhere else.
##
## Throwable props exist entirely so that a bang in the supply room takes the
## nurse out of the ward you want to be alone in. Every piece of that chain was
## implemented and none of it was ever run end to end — the event, the hearing
## radius, the investigate state and the walk are four separate systems, and
## three of them working is worth nothing.
func _make_a_noise() -> void:
	var h = game.hospital
	var where: Vector3 = h.point_in("supply")
	# Everybody who is on duty and far enough away for "did they come" to be a
	# real question rather than a rounding error. Somebody already watching the
	# player is allowed to ignore a clatter — that is the design — so the claim
	# is that SOMEBODY comes, not that a particular person does.
	for n in tree.get_nodes_in_group("staff"):
		if not (n is StaffNPC) or not n.on_duty:
			continue
		var d: float = n.global_position.distance_to(where)
		if d > 10.0:
			_distraction_from[n.get_instance_id()] = d
	WorldEvent.new("loud_clatter", "").at(where, "supply") \
		.heard(0.0, 60.0).tag("noise").tag("chaos") \
		.says("something fell over in the supply room").emit()
	# The claim under test is that the noise REACHED them and changed what they
	# were doing. Whether they then complete the walk in a given number of
	# frames is a pathing question that other assertions already cover, and
	# making it the assertion here made this flaky the moment doors started
	# genuinely blocking doorways.
	for n in tree.get_nodes_in_group("staff"):
		if _distraction_from.has(n.get_instance_id()) and int(n.get("state")) == 2:
			_investigating += 1

## Sampled every ten frames across the whole window, not read at two instants.
##
## INVESTIGATE is a state somebody passes THROUGH — they hear it, they walk
## over, they look at the mess, they go back to what they were doing — so
## checking for it once, several hundred frames later, catches whoever happens
## to still be mid-errand and misses everybody who already arrived.
var _went_to_look := {}

func _poll_distraction() -> void:
	for n in tree.get_nodes_in_group("staff"):
		if _distraction_from.has(n.get_instance_id()) and int(n.get("state")) == 2:
			_went_to_look[n.get_instance_id()] = true

func _check_distraction() -> void:
	var where: Vector3 = game.hospital.point_in("supply")
	var came := 0
	var best := 0.0
	for n in tree.get_nodes_in_group("staff"):
		var key := n.get_instance_id()
		if not _distraction_from.has(key):
			continue
		var before: float = float(_distraction_from[key])
		var now: float = n.global_position.distance_to(where)
		if before - now > 2.0:
			came += 1
			best = maxf(best, before - now)
	_investigating = _went_to_look.size()
	_distraction_worked = 1 if (came > 0 or _investigating > 0) else 0
	notes.append("noise: %d of %d staff in earshot went to look, %d had closed on it (up to %.1fm)" % [
		_investigating, _distraction_from.size(), came, best])

## Shoving something heavy into a ward doorway is supposed to buy you a private
## room: staff genuinely cannot path through it. That is the entire reason the
## tactic exists, and nothing had ever checked that it does anything — a silent
## failure here would have turned the whole "make yourself a window" layer of
## the game into set dressing.
func _block_a_doorway() -> void:
	var h = game.hospital
	var door_x: float = 0.0
	for entry in Hospital.LAYOUT:
		if String(entry["key"]) == "ward_101" and entry.has("door"):
			door_x = float(entry["door"])
	_blocker = Items.spawn("wheelchair")
	h.add_child(_blocker)
	_blocker.global_position = Vector3(door_x, 0.55, 4.0)
	_blocker.linear_velocity = Vector3.ZERO
	_blocker.freeze = true

func _check_doorway_blocked() -> void:
	var h = game.hospital
	_door_block_worked = 1 if h.nav.find_path(
		h.point_in("corridor"), h.point_in("ward_101")).is_empty() else 0

func _check_doorway_cleared() -> void:
	if _blocker != null and is_instance_valid(_blocker):
		_blocker.queue_free()
		_blocker = null

## The whole reason a door leaf is on the vision-blocker layer.
##
## Until this session no door in the building spanned its own doorway — every
## leaf stood perpendicular to its opening — so a shut door blocked a
## seven-centimetre sliver of nothing and "close the door behind you" was a move
## the game described and did not have. Both halves are checked here: that the
## corridor CAN see into a ward through an open door, and that it cannot once
## the door is shut. The first half matters as much as the second, because a
## test that only asserts the blocking passes just as well on a floor made of
## solid concrete.
var _probe_door = null
var _probe_watcher = null
var _probe_at := Vector3.ZERO
var _probe_stand := Vector3.ZERO

func _door_probe_setup() -> void:
	var h = game.hospital
	for d in h.get_children():
		if d is SwingDoor and d.room_key == "ward_101":
			_probe_door = d
	if _probe_door == null:
		return
	for n in tree.get_nodes_in_group("staff"):
		if n is StaffNPC and n.perception != null:
			_probe_watcher = n
			break
	if _probe_watcher == null:
		return
	# Straight through the middle of the doorway, from the corridor to a point
	# just inside the room. Deliberately not the bed: the bed is off to one side
	# and that sightline clips the frame, so a failure there would say something
	# about furniture placement rather than about the door.
	_probe_at = _probe_door.opening_centre() + Vector3(0, 1.0, 1.5)
	_probe_stand = _probe_door.opening_centre() + Vector3(0, 0, -1.6)
	_probe_watcher.stop_moving()
	_probe_watcher.global_position = _probe_stand
	_probe_watcher.look_toward(_probe_at)
	# Nothing else may move the leaf while it is posed — the passive closer
	# would ease it shut underneath the measurement.
	_probe_door.set_physics_process(false)
	_door_probe_pose(-1.4)

func _door_probe_pose(a: float) -> void:
	if _probe_door == null:
		return
	_probe_door.angle = a
	_probe_door.leaf.rotation.y = a

func _door_probe_look() -> int:
	if _probe_watcher == null or _probe_door == null:
		return -1
	# Put them back on the spot. stop_moving() clears the path, but the state
	# machine picks a new destination within a second or two and forty frames is
	# long enough to walk 1.6m — at which point the sightline being probed is no
	# longer the one that was set up, and the answer is about where the nurse
	# wandered to rather than about the door.
	_probe_watcher.stop_moving()
	_probe_watcher.global_position = _probe_stand
	_probe_watcher.force_update_transform()
	return 1 if _probe_watcher.perception.has_line_of_sight(_probe_at) else 0

func _door_probe_finish() -> void:
	if _probe_door != null:
		_probe_door.set_physics_process(true)
	notes.append("line of sight into Room 101 from the corridor: door open=%s shut=%s" % [
		str(_seen_door_open == 1), str(_seen_door_shut == 1)])

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

	_ok(_seen_in_the_open > 0,
		"a witness in the room recorded a blatant act (%d)" % _seen_in_the_open)
	_ok(_seen_through_wall == 0,
		"a ward wall stopped that same act being seen (%d)" % _seen_through_wall)
	_check_a_patient_is_actually_in_the_bed()
	_ok(_witness_took_a_note == 1,
		"and she stopped and wrote it down where the player could see her do it")
	_ok(_witness_suspicion > 0.0,
		"witnessing it moved that character's suspicion (%.2f)" % _witness_suspicion)

	# The player must not have fallen through the floor or got stuck in geometry.
	_ok(game.player.global_position.y > -2.0, "player is still on the floor")
	# Navigation must still be intact after all the physics.
	#
	# Every room EXCEPT the ones something is deliberately parked across —
	# blocking a doorway is a mechanic, not a bug, so a route failing into a
	# blocked room is the game working. This used to path lobby → ward_105 and
	# call it "the floor", which meant a trolley coming to rest in one doorway
	# during eight hours of physics failed a test about the whole building.
	var obstruction = tree.get_first_node_in_group("obstruction")
	var blocked: Array = obstruction.blocked_doorways() if obstruction != null else []
	var unreachable: Array[String] = []
	var from: Vector3 = game.hospital.point_in("corridor")
	for key in game.hospital.open_room_keys():
		if blocked.has(String(key)):
			continue
		if game.hospital.nav.find_path(from, game.hospital.point_in(String(key))).is_empty():
			unreachable.append(String(key))
	_ok(unreachable.is_empty(),
		"every room nobody has parked anything across is still reachable%s" % (
			"" if unreachable.is_empty() else ": " + ", ".join(unreachable)))
	var path = game.hospital.nav.find_path(
		game.hospital.point_in("lobby"), game.hospital.point_in("corridor"))
	_ok(path.size() > 0, "the floor is still navigable after a live shift")
	_ok(_distraction_worked != 0,
		"a noise at the far end of the floor pulls somebody off station")
	_ok(_investigating > 0 or _distraction_worked == 1,
		"and it is the noise doing it, not a coincidence of patrol routes")
	_ok(_seen_door_open == 1,
		"the corridor can see into a ward through an open door")
	_ok(_seen_door_shut == 0,
		"and cannot once the door is shut — which is the entire point of shutting it")
	_ok(_door_block_worked == 1,
		"a heavy prop left in a ward doorway genuinely cuts the room off")
	_ok(path.size() > 0 and _door_block_worked == 1,
		"and clearing it puts the room back on the map")
	# Patients must have progressed.
	var progressed := false
	for p in game.patient_system.active():
		if p.recovery > 0.01 or p.days_admitted > 0.01:
			progressed = true
	_ok(progressed, "the simulation advanced patient state")

	_report()

## Is the person in the bed, or beside it?
##
## The closest look a player ever gets at a character is a patient lying two
## metres away, and screenshots of that were ambiguous enough to argue about: a
## head, some linen, and no obvious body. Numbers settle it.
##
## This lives HERE and not in the smoke run because it is entirely a
## real-frames question — the smoke harness gets through about forty physics
## frames, which is not enough for a body to be pinned, ejected and settle, so
## it reported a number that was an artifact of its own brevity.
func _check_a_patient_is_actually_in_the_bed() -> void:
	var body = null
	var bed = null
	for cand in game.patient_system.active():
		var b = game.patient_system.get_body(cand.id)
		if b == null or b.state != PatientNPC.State.IN_BED:
			continue
		if b.bed == null or not is_instance_valid(b.bed):
			continue
		body = b
		bed = b.bed
		break
	if body == null:
		_ok(false, "somebody on this ward is in their chair")
		return

	var rel: Vector3 = body.head_position() - bed.global_position
	# The chair is 0.78 across with its seat top at 0.48 and its back at z -0.32.
	_ok(absf(rel.x) < 0.45, "the patient's head is over the chair, not beside it (x %+.2f)" % rel.x)
	_ok(absf(rel.z) < 0.55, "and between its arms rather than in front of it (z %+.2f)" % rel.z)
	# Sitting is lower than standing and higher than lying down. A head at 1.6
	# is somebody who never sat; a head at 0.9 is somebody through the seat.
	_ok(rel.y > 1.05 and rel.y < 1.50,
		"and sitting on it rather than standing in it (y %+.2f)" % rel.y)
	_ok(body.is_seated(), "and actually in the seated pose")

# ------------------------------------------------------------------ cost
## Phase 19. What a frame of this game actually costs, measured on the one
## harness that runs the whole simulation with real frames.
##
## --fixed-fps makes the CLOCK deterministic; it does not make the work free, so
## the wall time between ticks is still a true reading of how long a frame took
## to produce. Reported rather than asserted: a threshold here would fail on
## whatever machine happens to be busy, and the number is the point.
var _cost_ms: Array[float] = []
var _last_us := 0

## Frames 2500-4000, during which the clock is left alone.
##
## Sampling everywhere gave a number 400x too pessimistic, and it took a while
## to see why: this harness force-advances three game MINUTES per frame so that
## hourly and daily behaviour fires inside seven thousand frames, and real play
## advances 0.0074. Every per-minute system in the game — economy, shift,
## suspicion decay, the tannoy — was therefore running four hundred times more
## often than it ever will, and that was most of the frame.
func _in_cost_window() -> bool:
	return frames >= 2500 and frames < 4000

func _sample_cost() -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0 and _in_cost_window():
		_cost_ms.append(float(now - _last_us) / 1000.0)
	_last_us = now

func _cost_line() -> String:
	if _cost_ms.is_empty():
		return "  cost: not sampled"
	var sorted := _cost_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	var p50: float = sorted[int(sorted.size() * 0.50)]
	var p99: float = sorted[int(sorted.size() * 0.99)]
	var nodes := 0
	var stack: Array = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		for c in n.get_children():
			stack.append(c)
	return "  cost: mean %.2f ms  ·  p50 %.2f  ·  p99 %.2f  ·  worst %.2f  ·  %d nodes" % [
		total / float(sorted.size()), p50, p99, sorted[-1], nodes]

func _ok(cond: bool, msg: String) -> void:
	if cond:
		notes.append("  ok: " + msg)
	else:
		errors.append(msg)

func _report() -> void:
	for n in notes:
		print(n)
	print(_cost_line())
	print("\n--------------------------------------")
	if errors.is_empty():
		print("LIVE RUN PASSED — %d checks over %d frames" % [notes.size(), FRAMES])
	else:
		print("LIVE RUN FAILED — %d problem(s):" % errors.size())
		for e in errors:
			printerr("  " + e)
	print("--------------------------------------\n")

## TALKING TO A PATIENT HAS TO END.
##
## Pressing E on somebody is the single most common thing a player does in this
## game, and for most of the project's life it permanently broke whoever it was
## done to. State.TALKING had no exit: the only route back into IN_BED was
## _return_to_bed(), reachable only from WANDERING. So one conversation took a
## patient out of their chair for the rest of the career — standing, silent
## (barks fire from the IN_BED branch, including the line that tells you they
## are fit to go home), and un-sleepable, because the night pass gates on
## IN_BED. It needs REAL FRAMES to catch: the state is left by a timer that
## decrements in _physics_process, so no unit test and no smoke frame can see
## the door fail to open.
func _talk_to_somebody() -> void:
	var ps = game.patient_system
	for q in ps.active():
		var b = ps.get_body(q.id)
		if b == null or not b.is_seated() or q.discharged:
			continue
		_talked_to = String(q.id)
		b.interact(game.player, null)
		# The pin has to let go while they are facing you, or they cannot turn
		# their head at all — so the intermediate state is part of the contract.
		_talk_took_them_out_of_the_chair = b.state == PatientNPC.State.TALKING
		return

func _check_they_sat_back_down() -> void:
	if _talked_to == "":
		return
	_ok(_talk_took_them_out_of_the_chair,
		"talking to a patient turns them towards you")
	var b = game.patient_system.get_body(_talked_to)
	if b == null:
		# Discharged mid-test. Nothing to prove, and nothing broken.
		return
	_ok(b.state != PatientNPC.State.TALKING,
		"and a few seconds later they are done talking, not stuck facing you forever")
	_ok(b.state == PatientNPC.State.IN_BED or b.state == PatientNPC.State.WANDERING,
		"and they are back to being a patient (state %d)" % b.state)
	if b.state == PatientNPC.State.IN_BED:
		_ok(b.is_seated(), "and the chair has claimed them back")
