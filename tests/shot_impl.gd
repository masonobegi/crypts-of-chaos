extends RefCounted
## Photograph the ward. Five real bugs in this project were found only by
## looking at it, and every one of them was invisible to the tests.
var tree: SceneTree = null
var game: Node = null
var frames := 0
var index := 0
var settle := 0
var out_dir := ""

## Fixed vantages. The ward runs along +Z from the corridor.
## Vantages derived from the ACTUAL layout rather than guessed. Corridor is
## Rect2(0,0,20,4), ward Rect2(0,4,20,9) with its door at x=10, station
## Rect2(0,-8,12,8), office Rect2(12,-8,8,8). Beds run along the ward's far wall
## at z=11.65. Getting these wrong put the first render inside a bedside table
## looking at the sky.
const SHOTS := [
	["01_corridor", Vector3(1.5, 1.7, 2.0), Vector3(18.0, 1.5, 2.0)],
	["02_ward_from_door", Vector3(10.0, 1.7, 4.8), Vector3(10.0, 1.3, 12.0)],
	["03_bedside", "bedside"],
	["04_face", "face"],
	["05_ward_along", Vector3(1.6, 1.7, 9.5), Vector3(18.5, 1.2, 11.0)],
	["06_station", Vector3(6.0, 1.7, -1.0), Vector3(6.0, 1.3, -7.0)],
	["07_office", Vector3(16.0, 1.7, -2.0), Vector3(16.0, 1.3, -7.0)],
	["08_ward_wide", Vector3(2.0, 2.6, 6.0), Vector3(14.0, 1.0, 11.5)],
	["10_morning", "ui:morning"],
	["11_patient", "ui:patient"],
	["12_chart", "ui:chart"],
	["13_board", "ui:board"],
	["14_write", "ui:write"],
	["15_ward_two", "ui:ward_two"],
	["16_review", "ui:review"],
]

func start() -> void:
	GameState.start_new_career(20260822)
	GameState.set_flag("tutorial_done", true)
	# NOT headless_sim: Game._spawn_ui() returns early under that flag, so the
	# whole UI is nil and every screen shot photographs an empty room. This is a
	# rendered run — it wants the real UI.
	out_dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	GameState.start_day()

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 20:
		return false
	if index >= SHOTS.size():
		print("captured %d frames to %s" % [SHOTS.size(),
			ProjectSettings.globalize_path(out_dir)])
		return true
	var shot: Array = SHOTS[index]
	var cam: Camera3D = game.player.camera
	var w = tree.get_first_node_in_group("ward_day")

	if typeof(shot[1]) == TYPE_STRING and String(shot[1]).begins_with("ui:"):
		if settle == 0:
			# A CARD OVER A ROOM, NOT A CARD OVER THE SKY. Several stages move
			# the player to make a point — into the bay to be witnessed, into
			# the station to reach the board — and the camera went with them,
			# straight into the plaster. Point it down the ward first; the card
			# is the subject but the room behind it is why any of this is 3D.
			_stage_ui(String(shot[1]).substr(3), w)
			# AFTER staging, not before: several stages move the player to make
			# their point — into the bay to be witnessed, into the station to
			# reach the board — and the camera is a child of the player, so
			# pointing it first just carried it into the plaster with them.
			_look_down_the_ward(cam)
		settle += 1
		if settle < 5:
			return false
		settle = 0
		_save(String(shot[0]))
		if game.ui.has_method("close"):
			game.ui.close()
		index += 1
		return false

	if game.ui and game.ui.has_method("close"):
		game.ui.close()
	if typeof(shot[1]) == TYPE_STRING:
		_frame_a_person(cam, String(shot[1]))
	else:
		cam.global_position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
	settle += 1
	if settle < 4:
		return false
	settle = 0
	_save(String(shot[0]))
	index += 1
	return false

## From the ward door, along the row of beds. The one view that shows the game
## is a place and not a spreadsheet.
func _look_down_the_ward(cam: Camera3D) -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null:
		return
	cam.global_position = h.door_point("ward") + Vector3(-4.5, 0.0, 1.6)
	cam.look_at(h.door_point("ward") + Vector3(4.0, -0.35, 6.5), Vector3.UP)

func _stage_ui(which: String, w) -> void:
	match which:
		"morning":
			EventBus.request_ui.emit("morning", {})
		"patient":
			EventBus.request_ui.emit("patient", {"patient_id": "oduya"})
		"chart":
			if w != null:
				# A note written on top of the seven o'clock round, backdated by
				# half an hour: the photograph has to show a chart with
				# something WRONG in it, or it is a photograph of an empty form.
				w.advance_to(19 * 60 + 5)
				w.write_entry("oduya", ChartEntry.Claim.UNWELL,
					"Reports transient dizziness on standing.", 18 * 60 + 35)
			EventBus.request_ui.emit("chart", {"patient_id": "oduya"})
		"write":
			# The form itself, standing in the bay: the note being composed, the
			# gap it will record, and who is in the room while you compose it.
			var pl = tree.get_first_node_in_group("player")
			var h = tree.get_first_node_in_group("hospital")
			if pl != null and h != null:
				pl.global_position = h.point_in("ward") + Vector3(0, 0.1, 0)
			EventBus.request_ui.emit("chart", {"patient_id": "oduya"})
			var ui = game.ui
			if ui != null and ui.current != null:
				ui.current.set("_writing", true)
				ui.current.set("_stated", 18 * 60 + 35)
				if ui.current.has_method("rebuild"):
					ui.current.rebuild()
		"board":
			# The one screen that is a place. Stand in the station to read it.
			var pl2 = tree.get_first_node_in_group("player")
			var h2 = tree.get_first_node_in_group("hospital")
			if pl2 != null and h2 != null:
				pl2.global_position = h2.point_in("station") + Vector3(0, 0.1, 0)
			EventBus.request_ui.emit("board", {})
		"ward_two":
			# TOMORROW. A different five people and a different problem, which is
			# the whole point of there being a second one.
			GameState.day = 2
			GameState.start_day()
			if w != null:
				w.start()
				var ps2 = tree.get_first_node_in_group("patient_system")
				if ps2 != null and ps2.has_method("reset_day"):
					ps2.reset_day()
				w.examine("lomax")
			EventBus.request_ui.emit("patient", {"patient_id": "lomax"})
		"review":
			# Back to the first ward: this stage names its patients, and the
			# ward_two stage before it left the day on the second one.
			GameState.day = 1
			if w != null:
				w.start()
				var ps3 = tree.get_first_node_in_group("patient_system")
				if ps3 != null and ps3.has_method("reset_day"):
					ps3.reset_day()
				w.advance_to(19 * 60 + 5)
				w.write_entry("oduya", ChartEntry.Claim.UNWELL,
					"Reports transient dizziness on standing.", 18 * 60 + 35)
			if w != null:
				# The chart stage already left a contradiction in Sam Oduya's
				# notes; hold him and the reviewer has something to ask about,
				# which is the only version of this screen worth looking at.
				w.set_disposition("oduya", "hold")
				for id in ["marchetti", "kerrigan", "brennan", "blake"]:
					w.set_disposition(id, "discharge")
				w.advance_to(Cases.DEBT_DUE_MINUTE)
				w.end_day()
			EventBus.request_ui.emit("review", {})

## Stand in front of somebody. Characters have to read at two metres and at ten.
func _frame_a_person(cam: Camera3D, how: String) -> void:
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		return
	var b = ps.get_body("oduya")
	if b == null or not b.is_inside_tree():
		return
	var head: Vector3 = b.head_position()
	var dist := 1.5 if how == "face" else 2.8
	var eye := head + Vector3(0.35, 0.10, -1.0).normalized() * dist
	# TOWARD THE DOOR, not through the far wall. The bed head is at +Z; adding
	# to z put the camera inside the plaster and photographed a beige gradient.
	if how == "bedside":
		eye = head + Vector3(0.85, 0.45, -1.7)
	cam.global_position = eye
	cam.look_at(head, Vector3.UP)

func _save(name: String) -> void:
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	var note := ""
	if name.begins_with("1") and game != null and game.ui != null:
		# HOW MUCH OF THE CARD IS BELOW THE FOLD.
		#
		# Only measurable HERE. Under --headless the root Window is 64 pixels
		# tall, every Control lays out against it, and a card capped at
		# `viewport height - 116` therefore reports as three-quarters hidden —
		# which is how a UI bug that did not exist got onto the list twice. This
		# harness runs in a real 1600x900 window, so these are real numbers.
		var hidden := _below_the_fold(game.ui)
		note = "   [%.0f%% below the fold%s]" % [hidden * 100.0,
			"  <-- TOO MUCH" if hidden >= 0.5 else ""]
	print("  shot: ", ProjectSettings.globalize_path(path), note)

## The worst overflow on any scrolling area in the screen, as a fraction of its
## own content height. 0.0 means everything fits without scrolling.
func _below_the_fold(n: Node) -> float:
	var worst := 0.0
	if n is ScrollContainer:
		var sc := n as ScrollContainer
		var content := 0.0
		for c in sc.get_children():
			if c is Control:
				content = maxf(content, (c as Control).size.y)
		if content > 1.0 and sc.size.y > 1.0:
			worst = maxf(worst, clampf((content - sc.size.y) / content, 0.0, 1.0))
	for c in n.get_children():
		worst = maxf(worst, _below_the_fold(c))
	return worst
