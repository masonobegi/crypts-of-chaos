extends RefCounted
## Screenshot harness. Boots the real game and photographs it from a set of
## fixed vantage points, so the procedural world can be eyeballed without a
## human having to sit in front of it.

var tree: SceneTree = null
var game: Node = null
var frames := 0
var index := 0
var settle := 0
var out_dir := "user://shots"
var ui_index := 0
var phase := "world"

## Modal screens, photographed after the world pass. UI layout bugs are invisible
## to every other kind of test — all three found so far were only visible here.
const UI_SHOTS := [
	["19_shift_select", "shift_select"],
	["20_briefing", "briefing"],
	["20b_exam", "exam"],
	["20c_surgery", "surgery"],
	["20d_prescribe", "prescribe"],
	["21_tablet_ward", "tablet"],
	["21c_tablet_list", "tablet_list"],
	["21b_tablet_record", "tablet_record"],
	["22_chart", "chart"],
	["23_records", "records"],
	["24_dialogue", "dialogue"],
	["24b_patient", "patient"],
	["25_review", "review"],
	["26_statement", "statement"],
	["27_upgrades", "upgrades"],
	["20e_setbone", "setbone"],
	["20e2_setbone_field", "setbone#treat"],
	["20e3_setbone_worsen", "setbone#worsen"],
	["20f_medicate", "medicate"],
	["20f2_medicate_shelf", "medicate#shelf"],
	["20f3_medicate_dose", "medicate#dose"],
	["20g_suture", "suture"],
	["20g2_suture_field", "suture#treat"],
	["20h_manipulate", "manipulate"],
	["20h2_manipulate_field", "manipulate#treat"],
	["30_court_letter", "court"],
	["30b_court_lawyers", "court#lawyers"],
	["30c_court_hearing", "court#hearing"],
	["31_night_choose", "night"],
	["27b_settings", "settings"],
	["27c_controls", "controls"],
	["27d_credits", "credits"],
	["27e_achievements", "achievements"],
	["28_pause", "pause"],
	["29_game_over", "game_over"],
]

## The evening, photographed on its feet. The street does not exist until you
## go out, so it cannot be one of the fixed world vantages — it has to be built,
## walked into, and then taken down again.
const STREET_SHOTS := [
	["32_street", Vector3(-26.0, 1.7, 6.0), Vector3(14.0, 1.5, 4.0)],
	["32b_street_lamp", Vector3(6.0, 1.7, -6.0), Vector3(-10.0, 2.4, 6.0)],
	["32c_street_mark", Vector3(20.0, 1.7, 6.6), Vector3(-12.0, 1.5, 5.0)],
]
var street_index := 0
var street_ready := false

func _tick_street() -> bool:
	var night = game.get("night")
	if night == null:
		return true
	if not street_ready:
		if game.ui != null:
			game.ui.close()
		night.enter("the_anchor")
		street_ready = true
		settle = 0
		return false
	settle += 1
	if settle < 6:
		return false
	if street_index >= STREET_SHOTS.size():
		night.finish(false)
		if game.ui != null:
			game.ui.close()
		print("captured %d frames to %s" % [
			SHOTS.size() + UI_SHOTS.size() + STREET_SHOTS.size(),
			ProjectSettings.globalize_path(out_dir)])
		return true
	var shot: Array = STREET_SHOTS[street_index]
	game.player.camera.global_position = shot[1]
	game.player.camera.look_at(shot[2], Vector3.UP)
	if settle < 9:
		return false
	var img := tree.root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, String(shot[0])])
	print("  shot: ", String(shot[0]))
	street_index += 1
	settle = 6
	return false

## name, position, look-at
func _tick_ui() -> bool:
	phase = "ui"
	if ui_index >= UI_SHOTS.size():
		phase = "street"
		return false
	var shot: Array = UI_SHOTS[ui_index]
	if game.ui.current == null:
		_set_ceilings_visible(true)
		game.player.camera.global_position = Vector3(5.5, 1.7, -4.0)
		game.player.camera.look_at(Vector3(5.5, 1.5, 2.0), Vector3.UP)
		var screen_id := String(shot[1])
		var want_tab := ""
		if screen_id.begins_with("tablet_"):
			want_tab = screen_id.trim_prefix("tablet_")
			screen_id = "tablet"
		# `screen#stage` photographs a screen partway through itself. The
		# procedure screens are three screens each — declare, choose, do — and
		# the only one that was ever in a screenshot was the first.
		var stage := ""
		if screen_id.contains("#"):
			var bits := screen_id.split("#")
			screen_id = bits[0]
			stage = bits[1]
		game.ui.open(screen_id, _ui_context(String(shot[1])))
		if want_tab != "" and game.ui.current != null:
			game.ui.current.set("_tab", want_tab)
			game.ui.current.rebuild()
		if stage != "" and game.ui.current != null:
			_stage_ui(game.ui.current, screen_id, stage)
		settle = 0
		return false
	settle += 1
	if settle == 3:
		_pose_ui(game.ui.current, String(shot[1]))
	if settle < 6:
		return false
	settle = 0
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, String(shot[0])]
	img.save_png(path)
	print("  shot: ", ProjectSettings.globalize_path(path))
	game.ui.close()
	ui_index += 1
	return false

## Advance a procedure screen to the stage we want a photograph of. Sets the
## fields the screen would have set itself and rebuilds, exactly as clicking
## through it would.
func _stage_ui(screen, screen_id: String, stage: String) -> void:
	match screen_id:
		"court":
			screen.set("_stage", "lawyers" if stage == "lawyers" else "hearing")
			if stage == "hearing":
				screen.set("_lawyer", "fixer")
		"night":
			screen.set("_stage", "street")
			screen.set("_place", NightSystem.PLACES[2])
			screen.set("_mark_name", "Wendell Tosh")
		"setbone", "suture", "manipulate":
			screen.set("_intent", "treat" if stage == "treat" else "worsen")
		"medicate":
			screen.set("_intent", "worsen" if stage == "dose" else "treat")
			if stage == "dose":
				var cid := String(screen.get("_patient").condition_id)
				var clashes: Array = Procedures.CLASHES.get(cid, [])
				screen.set("_med", String(clashes[0]) if not clashes.is_empty() else "placebex")
	screen.rebuild()

## Put a hand on it. A procedure screen photographed on frame one is a screen
## nobody has touched; these are the same screens a second in.
func _pose_ui(screen, id: String) -> void:
	if screen == null or not id.contains("#"):
		return
	match id:
		"setbone#treat":
			screen.set("_angle", 0.13)
			screen.set("_angle_shown", 0.13)
			screen.set("_gap_shown", 3.4)
			screen.set("_hold", 0.62)
			screen.set("_grip", true)
		"setbone#worsen":
			screen.set("_angle", 0.37)
			screen.set("_angle_shown", 0.37)
			screen.set("_gap_shown", 13.0)
			screen.set("_hold", 0.85)
			screen.set("_grip", true)
		"suture#treat":
			for k in 3:
				var targets: Array = screen.get("_targets")
				if k < targets.size():
					screen.call("_click", targets[k] + screen.call("_offset"))
		"medicate#dose":
			screen.set("_level", 0.62)
			screen.set("_drawing", true)
		"manipulate#treat":
			# A second and a half into the arc, hand on the guide.
			screen.set("_elapsed", 1.6)
			screen.set("_t", 1.6 / Procedures.MANIP_SECONDS)
			screen.set("_angle", Procedures.manip_angle_at("treat",
				1.6 / Procedures.MANIP_SECONDS) + 0.06)
			screen.set("_grip", true)
		"night#street":
			# A moment into the evening: partway down the street, one lamp too
			# close, with somebody's eyeline just clipping you.
			screen.set("_elapsed", 3.4)
			screen.set("_mark_t", 0.22)
			screen.set("_exposure", 0.31)
			screen.set("_me", Vector2(360.0, 250.0))
	var canvas = screen.get("_canvas")
	if canvas != null:
		canvas.queue_redraw()

## Screens that normally receive data from a shift transition need it supplied.
func _ui_context(id: String) -> Dictionary:
	match id:
		"briefing":
			return game.shift.briefing()
		"shift_select":
			var options: Array = []
			for kind in DB.SHIFT_ORDER:
				var spec: Dictionary = DB.SHIFTS[kind]
				options.append({
					"kind": kind, "name": String(spec["name"]),
					"hours": "%02d:00 – %02d:00" % [int(spec["start_hour"]),
						(int(spec["start_hour"]) + int(spec["hours"])) % 24],
					"pay": float(spec["pay"]), "staff": DB.staff_on(kind),
					"appointments": int(spec["appointments"]),
					"blurb": String(spec["blurb"]), "catch": String(spec["catch"]),
				})
			return {"day": GameState.day, "options": options,
				"personal": GameState.personal_money, "owed": GameState.total_debt()}
		"exam", "surgery", "prescribe":
			var pool: Array = game.patient_system.active()
			if pool.is_empty():
				return {}
			return {"patient_id": pool[0].id}
		"setbone", "medicate", "suture", "manipulate", "setbone#treat", \
		"setbone#worsen", "medicate#shelf", "medicate#dose", "suture#treat", \
		"manipulate#treat":
			# A patient whose ailment actually calls for this procedure, so the
			# screenshot is of the thing rather than of a fallback.
			var base := id.split("#")[0]
			var want := "set_bone" if base == "setbone" else \
				("suture" if base == "suture" else
					("manipulate" if base == "manipulate" else "prescribe"))
			for cand in game.patient_system.active():
				if Procedures.procedure_for(cand.condition_id) == want:
					return {"patient_id": cand.id}
			# Nobody on the ward has one today: give the first patient the
			# condition, so the screen still has something to draw.
			var any: Array = game.patient_system.active()
			if any.is_empty():
				return {}
			any[0].condition_id = "fractured_wrist" if want == "set_bone" else \
				("knuckle_weather" if want == "suture" else
					("dislocated_shoulder" if want == "manipulate" else "chronic_beige"))
			return {"patient_id": any[0].id}
		"court", "court#lawyers", "court#hearing":
			# A real claim against a real patient, filed on the spot, so the
			# screenshot is of the game rather than of a mock-up.
			var lg = game.get("legal")
			var pool2: Array = game.patient_system.active()
			if lg == null or pool2.is_empty():
				return {}
			var victim2 = pool2[0]
			victim2.recovery = 0.35
			game.patient_system.add_complication(victim2, "fractured_wrist", "examination")
			var claim: Dictionary = lg.file_claim(victim2, "premature_discharge")
			claim["witnesses"] = ["Nurse Sarah Pell", "Ms Odile Vane"]
			claim["imaging"] = true
			return {"claim": claim}
		"night", "night#street":
			return {}
		"chart", "dialogue", "patient":
			var list: Array = game.patient_system.active()
			if list.is_empty():
				return {}
			var p = list[0]
			return {"patient_id": p.id, "npc_id": p.id}
		"records":
			return {"mode": "admin", "private": true, "room": "office",
				"position": Vector3(43, 1, -5)}
		"review":
			# Give the shot something to photograph: the review screen is the
			# "am I getting away with it" beat, and a blank one shows nothing.
			var victim = null
			for q in game.patient_system.active():
				victim = q
				break
			if victim != null and victim.acquired_injuries().is_empty():
				game.patient_system.add_complication(victim, "fractured_wrist", "examination")
				game.patient_system.add_complication(victim, "concussion", "examination")
			return {
				"day": GameState.day,
				"findings": game.records.pending_findings(),
				"exposure": game.records.total_exposure(),
				"undocumented": game.shift._undocumented_complications(),
				"acquired": game.shift._acquired_injury_summary(),
				"patients": game.shift._patient_summaries(),
			}
		"statement":
			return {
				"day": GameState.day,
				"statement": game.economy.close_shift(),
				"headline": Endings.headline(GameState.stats),
				"notes": game.shift._shift_notes(),
				"heat": GameState.heat, "heat_delta": 0.02,
				"sanction": GameState.SANCTIONS[GameState.sanction_level],
				"suspicions": game.suspicion.ranked_suspicions().slice(0, 6),
				"census": game.patient_system.active_count(),
				"overstay": game.patient_system.average_overstay(),
				"clean": true,
				"reputation": GameState.reputation.duplicate(),
				"debt": GameState.total_debt(),
				"daily_debt": GameState.daily_debt_payment(),
			}
		"game_over":
			return {"ending": "legendary"}
	return {}

func _set_ceilings_visible(v: bool) -> void:
	if game == null or game.hospital == null:
		return
	for r in game.hospital.room_list():
		for c in r.get_children():
			# By meta, not by type. "The only bare MeshInstance3D parented to a
			# Room" was true until floor borders were added, at which point
			# taking the roof off also took the floor markings with it.
			if c is MeshInstance3D and c.has_meta("is_ceiling"):
				(c as MeshInstance3D).visible = v

const SHOTS := [
	# The literal first frame of a run: the player's own camera, where the game
	# puts them, before they have touched anything.
	["00_first_frame", "player_spawn"],
	# Looking SOUTH, into the room. This shot used to face the corridor doorway
	# with reception, every chair and the vending machine behind the camera, so
	# the lobby photographed as a blank wall and was assumed to be one.
	["01_lobby", Vector3(6.2, 1.7, -1.6), Vector3(4.6, 1.3, -8.5)],
	["02_corridor_west", Vector3(3.0, 1.7, 2.0), Vector3(40.0, 1.5, 2.0)],
	["03_corridor_east", Vector3(40.0, 1.7, 2.0), Vector3(3.0, 1.5, 2.0)],
	# Standing in the corridor outside 101, at head height, looking at the door
	# card — the shot that answers "does the building tell you anything".
	["03b_door_card", Vector3(3.4, 1.6, 2.6), Vector3(3.55, 1.52, 3.9)],
	["04_ward_101", Vector3(4.5, 1.7, 5.5), Vector3(4.0, 1.2, 11.0)],
	# Close enough to see a face. Characters are the one thing in this game that
	# has to read at four metres AND at forty, and every other shot is framed
	# for the room.
	# Beside the pillow, looking across at the face — where a doctor stands.
	# Down the bed from the foot the headboard is between the camera and the
	# patient (it is 1.06 x 0.5 and sits at z -1.05), and off to one side you
	# get the back of a head behind an IV stand.
	# The objective marker: the fix for "I got lost". Down the corridor from the
	# west end, with the marker over the clinic board at the far end of it.
	["00b_objective", Vector3(2.0, 1.7, 2.0), Vector3(40.0, 1.6, 2.0), "objective"],
	# ...and the edge arrow, which is what you get the rest of the time — facing
	# the wrong way, which in a sixty-two metre corridor is most of the time.
	["00c_objective_arrow", Vector3(30.0, 1.7, 2.0), Vector3(46.0, 1.6, 2.0), "objective"],
	# The machine mid-cycle, dialled well past the prescribed setting: the one
	# act the whole game is about, which nothing had ever photographed.
	["04c_cycle", Vector3(5.6, 1.5, 8.2), Vector3(3.4, 1.15, 9.9), "cycle"],
	["04b_bedside", Vector3(5.1, 1.68, 8.8), Vector3(3.05, 1.14, 9.9)],
	["05_nurses_station", Vector3(15.0, 1.7, -1.5), Vector3(15.0, 1.2, -7.0)],
	# The waiting row, with somebody in it. A walk-in patient sitting down is the
	# first thing that class of character is ever seen doing.
	["06b_waiting", Vector3(23.6, 1.30, -6.0), Vector3(20.2, 0.92, -6.0), "walkin"],
	["06_treatment_bay", Vector3(24.0, 1.7, -2.0), Vector3(24.0, 1.3, -9.0)],
	["07_supply", Vector3(32.0, 1.7, -2.0), Vector3(31.0, 1.3, -8.0)],
	["08_office", Vector3(43.0, 1.7, -2.5), Vector3(43.0, 1.2, -8.5)],
	["09_ward_105", Vector3(41.5, 1.7, 5.5), Vector3(41.0, 1.2, 11.0)],
	# The west annexe, shuttered — what a career starts out looking at.
	["09b_clinic_board", Vector3(25.2, 1.62, 1.1), Vector3(27.0, 1.5, 3.95)],
	["10_annexe_shuttered", Vector3(2.0, 1.7, 2.0), Vector3(-16.0, 1.5, 2.0)],
	# ...and the same three rooms with the departments bought. The "unlock" tag
	# rolls the shutters up before the shot is framed.
	["11_intake", Vector3(-8.0, 1.7, 5.2), Vector3(-8.0, 1.3, 12.0), "unlock"],
	["12_radiology", Vector3(-12.0, 1.7, -0.8), Vector3(-11.2, 1.3, -9.0)],
	["13_day_room", Vector3(-4.0, 1.7, -1.4), Vector3(-4.0, 1.3, -8.5)],
	# ---- the same building with the whole catalogue bought.
	# The model itself: a face at a metre, and a whole person at four.
	["13x_face", "portrait", 0.95],
	["13y_person", "portrait", 3.2],
	["13b_kitted_corridor", Vector3(3.0, 1.7, 2.0), Vector3(40.0, 1.6, 2.0), "kitted"],
	["13c_kitted_ward", Vector3(4.5, 1.7, 5.5), Vector3(4.0, 1.2, 11.0)],
	["13d_kitted_office", Vector3(43.0, 1.7, -2.5), Vector3(43.0, 1.5, -9.5)],
	["13e_kitted_vip", Vector3(41.5, 1.7, 5.5), Vector3(41.0, 1.1, 11.0)],
	# ...and hand it all back, so everything after this photographs the hospital
	# a new player actually starts in. The shutters stay up — RollerShutter.open
	# is one-way and re-sealing them mid-run is not something the game does.
	["14_overview", Vector3(15.0, 33.0, 33.0), Vector3(15.0, 0.0, 1.0), "unkit"],
	# The same corridor on all three shifts. The shifts differ in five numbers
	# on a selection screen and, until now, in nothing a player could see — so
	# this is the shot that says whether "Skeleton crew. Nobody is watching."
	# is a claim or a fact.
	["15_shift_day", Vector3(3.0, 1.7, 2.0), Vector3(40.0, 1.5, 2.0), "shift:day"],
	["16_shift_evening", Vector3(3.0, 1.7, 2.0), Vector3(40.0, 1.5, 2.0), "shift:evening"],
	["17_shift_night", Vector3(3.0, 1.7, 2.0), Vector3(40.0, 1.5, 2.0), "shift:night"],
]

## Buy the whole annexe, so the departments can be photographed. Deliberately
## done between shots rather than at start-up: the shuttered corridor is the
## thing a new player actually sees, and it needs a picture too.
func _unlock_departments() -> void:
	for id in ["dept_emergency", "dept_radiology", "dept_psych"]:
		if not GameState.owned_upgrades.has(id):
			GameState.owned_upgrades.append(id)
	for d in ["emergency", "radiology", "psych"]:
		if not GameState.unlocked_departments.has(d):
			GameState.unlocked_departments.append(d)
	if game != null and game.hospital != null:
		game.hospital.refresh_departments()

## Every fitting in the building at once. Half the catalogue changes how you
## have to play and none of it used to change what the ward looks like, so these
## are the shots that answer "can you see what a career's reinvestment bought".
## What was owned before the kitted-out block, so it can be handed back.
##
## Captured ONCE. Every beat in this harness re-runs until its settle counter
## is up, so the naive version snapshotted the list again on the second frame —
## by which point the first frame had already bought everything, and "what was
## owned before" was the full catalogue. The hand-back then handed back
## everything, and the Capital Spending screenshot had an empty AVAILABLE list.
var _owned_before: Array = []
var _took_snapshot := false

func _buy_everything() -> void:
	if not _took_snapshot:
		_owned_before = GameState.owned_upgrades.duplicate()
		_took_snapshot = true
	for id in Upgrades.CATALOGUE:
		if not GameState.owned_upgrades.has(id):
			GameState.owned_upgrades.append(id)
	_unlock_departments()
	if game != null and game.hospital != null:
		game.hospital.refresh_fittings()

## Point the objective marker at the clinic board.
##
## This harness never starts a shift, so the tutorial never activates and there
## is no objective to photograph — which is why the first attempt at this shot
## was a picture of an empty room.
func _aim_the_objective() -> void:
	for f in tree.get_nodes_in_group("fixture"):
		if f is ClinicBoard:
			EventBus.objective_target_changed.emit(
				(f as Node3D).global_position + Vector3(0, 1.1, 0), "Clinic Board")
			return

## Put somebody in the waiting row so it can be photographed with a person in
## it. Idempotent — every beat re-runs until its settle counter is up.
var _seated_walkin := false

func _seat_a_walkin() -> void:
	if _seated_walkin or game.patient_system == null:
		return
	_seated_walkin = true
	var p = game.patient_system.book_walkin()
	if p != null:
		game.patient_system.arrive_walkin(p)

## Fire a machine cycle in Room 101 and hold it open.
##
## The central act of the game is a two-and-a-half second event, and every other
## shot in this harness is of a room standing still — so the one thing the
## player spends the game doing had never been photographed at all.
##
## Re-triggered every settle frame so the cycle is still running when the
## shutter opens; without that the shot lands after it has finished and is a
## picture of a machine doing nothing, which is the state it was already in.
func _start_a_cycle() -> void:
	var m = null
	for f in tree.get_nodes_in_group("fixture"):
		if f is TreatmentMachine and String(f.room_key) == "ward_101":
			m = f
			break
	if m == null:
		return
	m.dial = m.prescribed + 5
	m._refresh()
	var body = null
	if game.patient_system != null:
		for pt in game.patient_system.active():
			if String(pt.room) == "ward_101":
				body = game.patient_system.get_body(pt.id)
				break
	m.begin_cycle(3.0, 5, body)
	if body != null:
		body.undergo_cycle(3.0, 5)

## Hand it all back.
##
## _buy_everything used to be permanent, so every shot after the kitted-out
## block photographed a fully upgraded hospital — including the three
## shift-look shots and the Capital Spending screen, which had an empty
## AVAILABLE list and nothing to advertise.
func _sell_everything() -> void:
	GameState.owned_upgrades.assign(_owned_before)
	GameState.unlocked_departments.clear()
	if game != null and game.hospital != null:
		game.hospital.refresh_fittings()

func start() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Clear the last run's frames first.
	#
	# These accumulate, and a renamed or removed shot leaves its old PNG sitting
	# in the directory looking exactly like a current one. A stale `10_overview`
	# survived several rounds of this and was read as evidence about a build it
	# predated by hours, which is the worst failure mode a screenshot harness
	# has: it does not go wrong, it goes convincingly out of date.
	var d := DirAccess.open(out_dir)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".png"):
				d.remove(f)
	GameState.start_new_career(20260819)
	# Skip the first-run tutorial; its dim overlay darkens every shot.
	GameState.set_flag("tutorial_done", true)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)

func tick() -> bool:
	frames += 1
	tree.paused = false
	if game == null or game.player == null:
		return frames > 60
	# The briefing screen opens on day one and pauses the tree; close whatever
	# modal is up so the camera is photographing the world, not an overlay.
	if phase == "world" and game.ui != null and game.ui.current != null:
		game.ui.close()
		return false
	if frames < 45:
		return false
	if phase == "street":
		return _tick_street()
	if index >= SHOTS.size():
		return _tick_ui()

	var shot: Array = SHOTS[index]
	if shot.size() > 3 and String(shot[3]) == "unlock":
		_unlock_departments()
	if shot.size() > 3 and String(shot[3]) == "objective":
		_aim_the_objective()
	if shot.size() > 3 and String(shot[3]) == "walkin":
		_seat_a_walkin()
	if shot.size() > 3 and String(shot[3]) == "cycle":
		_start_a_cycle()
	if shot.size() > 3 and String(shot[3]) == "kitted":
		_buy_everything()
	if shot.size() > 3 and String(shot[3]) == "unkit":
		_sell_everything()
	if shot.size() > 3 and String(shot[3]).begins_with("shift:"):
		GameState.shift_kind = String(shot[3]).trim_prefix("shift:")
		game.apply_shift_look()
	var cam: Camera3D = game.player.camera
	# typeof, not String(): shot[1] is a Vector3 for an ordinary shot, and
	# String(Vector3) is not a constructor Godot 4 has. It errors every frame
	# without advancing, so the harness spins forever on the first shot.
	if shot.size() >= 2 and typeof(shot[1]) == TYPE_STRING and shot[1] == "portrait":
		_frame_a_person(cam, float(shot[2]) if shot.size() > 2 else 2.4)
		settle += 1
		if settle < 4:
			return false
		settle = 0
		_save(String(shot[0]))
		index += 1
		return false
	if shot.size() == 2 and typeof(shot[1]) == TYPE_STRING and shot[1] == "player_spawn":
		# Leave the camera exactly where the game put it.
		pass
	else:
		cam.global_position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
	# The overview is shot from above, so the ceilings have to come off.
	#
	# By NAME, not by position. This was `index == SHOTS.size() - 1`, which was
	# true of whatever happened to be last in the list — so the moment any shot
	# was added after the overviews, both of them started photographing the
	# roof of the building, and did for some time.
	var overview := String(shot[0]).ends_with("overview")
	cam.fov = 60.0 if overview else 78.0
	_set_ceilings_visible(not overview)

	settle += 1
	if settle < 4:
		return false
	settle = 0
	_save(String(shot[0]))
	index += 1
	return false

func _save(name: String) -> void:
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	print("  shot: ", ProjectSettings.globalize_path(path))

## Stand in front of somebody and look them in the face.
##
## Characters are the only thing in this game that has to read at four metres
## AND at forty, and every other shot is framed for a room — so the model was
## being judged from whatever happened to wander through the back of a corridor
## photograph. The staff are picked by npc_id so the same person is photographed
## every run.
func _frame_a_person(cam: Camera3D, dist: float) -> void:
	var who = null
	var best := ""
	for n in tree.get_nodes_in_group("staff"):
		var id := String(n.npc_id)
		if best == "" or id < best:
			best = id
			who = n
	if who == null:
		return
	who.stop_moving()
	who.set("state", 0)
	who.velocity = Vector3.ZERO
	# Somewhere with room to stand back in: the corridor, mid-run, clear of the
	# doors. Framing them where they happened to be walking put the camera
	# inside a supply room wall.
	# The corridor is only four metres deep, so the standoff has to run mostly
	# along it. Backing off across it put the camera inside Room 103.
	who.global_position = Vector3(19.0, 0.0, 3.0)
	var head: Vector3 = who.global_position + Vector3(0, 1.50, 0)
	# Three-quarter view. A portrait aims at the FACE; a full-length aims at
	# the middle of the body, or the feet fall out of the bottom of the frame.
	var aim: Vector3 = head if dist < 1.5 else who.global_position + Vector3(0, 0.95, 0)
	var dir := Vector3(0.88, 0.0, -0.48).normalized()
	cam.global_position = aim + dir * dist + Vector3(0, dist * 0.08, 0)
	# Turn them to face the camera outright. look_toward only leans the head,
	# and the body faces wherever the AI last walked — every portrait so far has
	# been the back of somebody's head.
	#
	# atan2(dx, dz) and not the usual atan2(-dx, -dz): this model's eyes are on
	# its local +Z, so +Z is its front.
	var to_cam: Vector3 = cam.global_position - who.global_position
	who.rotation.y = atan2(to_cam.x, to_cam.z)
	who.look_toward(cam.global_position)
	# Eyes open. Characters blink now, and a portrait is a one-in-eight chance
	# of photographing somebody mid-blink — which looks like a broken model
	# rather than like a working one.
	who.set_eyes_open(true)
	who._blink_t = 9.0
	cam.look_at(aim, Vector3.UP)
