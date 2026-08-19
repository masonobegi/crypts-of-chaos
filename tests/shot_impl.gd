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
	["25_review", "review"],
	["26_statement", "statement"],
	["27_upgrades", "upgrades"],
	["28_pause", "pause"],
	["29_game_over", "game_over"],
]

## name, position, look-at
func _tick_ui() -> bool:
	phase = "ui"
	if ui_index >= UI_SHOTS.size():
		print("captured %d frames to %s" % [
			SHOTS.size() + UI_SHOTS.size(), ProjectSettings.globalize_path(out_dir)])
		return true
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
		game.ui.open(screen_id, _ui_context(String(shot[1])))
		if want_tab != "" and game.ui.current != null:
			game.ui.current.set("_tab", want_tab)
			game.ui.current.rebuild()
		settle = 0
		return false
	settle += 1
	if settle < 4:
		return false
	settle = 0
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, String(shot[0])]
	img.save_png(path)
	print("  shot: ", ProjectSettings.globalize_path(path))
	game.ui.close()
	ui_index += 1
	return false

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
		"chart", "dialogue":
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
			# Ceilings are the only bare MeshInstance3D parented to a Room.
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = v

const SHOTS := [
	["01_lobby", Vector3(5.5, 1.7, -4.0), Vector3(5.5, 1.5, 2.0)],
	["02_corridor_west", Vector3(3.0, 1.7, 2.0), Vector3(40.0, 1.5, 2.0)],
	["03_corridor_east", Vector3(40.0, 1.7, 2.0), Vector3(3.0, 1.5, 2.0)],
	# Standing in the corridor outside 101, at head height, looking at the door
	# card — the shot that answers "does the building tell you anything".
	["03b_door_card", Vector3(3.4, 1.6, 2.6), Vector3(3.55, 1.52, 3.9)],
	["04_ward_101", Vector3(4.5, 1.7, 5.5), Vector3(4.0, 1.2, 11.0)],
	["05_nurses_station", Vector3(15.0, 1.7, -1.5), Vector3(15.0, 1.2, -7.0)],
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
	["14_overview", Vector3(15.0, 33.0, 33.0), Vector3(15.0, 0.0, 1.0)],
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

func start() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
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
	if index >= SHOTS.size():
		return _tick_ui()

	var shot: Array = SHOTS[index]
	if shot.size() > 3 and String(shot[3]) == "unlock":
		_unlock_departments()
	var cam: Camera3D = game.player.camera
	cam.global_position = shot[1]
	cam.look_at(shot[2], Vector3.UP)
	# The overview is shot from above, so the ceilings have to come off.
	var overview := index == SHOTS.size() - 1
	cam.fov = 60.0 if overview else 78.0
	_set_ceilings_visible(not overview)

	settle += 1
	if settle < 4:
		return false
	settle = 0
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, String(shot[0])]
	img.save_png(path)
	print("  shot: ", ProjectSettings.globalize_path(path))
	index += 1
	return false
