extends RefCounted
## Photograph the ward. Five real bugs in this project were found only by
## looking at it, and every one of them was invisible to the tests.
var tree: SceneTree = null
var game: Node = null
var menu: Node = null
var menu_index := 0
var menu_opened := false
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
	["04b_lineup", "lineup"],
	["04c_visitor", "visitor"],
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
	["16_ward_three", "ui:ward_three"],
	["17_review", "ui:review"],
	["18_day_over", "ui:day_over"],
	["19_paid", "ui:paid"],
	["20_struck_off", "ui:struck_off"],
]

## THE FIRST THING ANYBODY SEES, and nothing had ever photographed it.
##
## This harness instantiates Game.tscn directly, so the title screen — the
## screen every single player looks at before anything else — was outside every
## visual check the project has. That is how a patient sitting INSIDE the bed on
## the backdrop and an unstyled stock LineEdit sitting under the game's own
## buttons both survived: the only way to see either is to look, and nothing
## looked.
const MENU_SHOTS := ["00_title", "00b_title_settings"]

func start() -> void:
	GameState.start_new_career(20260822)
	GameState.set_flag("tutorial_done", true)
	# NOT headless_sim: Game._spawn_ui() returns early under that flag, so the
	# whole UI is nil and every screen shot photographs an empty room. This is a
	# rendered run — it wants the real UI.
	out_dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	menu = load("res://scenes/MainMenu.tscn").instantiate()
	tree.root.add_child(menu)

## Swap the title screen for the ward, once its shots are taken.
func _into_the_game() -> void:
	tree.root.remove_child(menu)
	menu.queue_free()
	menu = null
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	GameState.start_day()

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 20:
		return false

	# The title screen first, then the ward.
	if menu != null:
		if menu_index >= MENU_SHOTS.size():
			_into_the_game()
			settle = 0
			return false
		settle += 1
		if settle < 6:
			return false
		settle = 0
		# The second one with a submenu up, because Settings and Controls are
		# built by a different path and are the two most likely to be wrong.
		# Opened on the pass BEFORE the shot, so the settle counter above gives
		# it frames to lay out in — opening and saving in the same pass
		# photographed the title screen twice and never the submenu.
		if menu_index == 1 and not menu_opened and menu.has_method("_open_menu_screen"):
			menu._open_menu_screen("settings")
			menu_opened = true
			return false
		_save(String(MENU_SHOTS[menu_index]))
		menu_index += 1
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
			EventBus.request_ui.emit("patient", {"patient_id": _someone()})
		"chart":
			if w != null:
				# A note written on top of the seven o'clock round, backdated by
				# half an hour: the photograph has to show a chart with
				# something WRONG in it, or it is a photograph of an empty form.
				w.advance_to(19 * 60 + 5)
				w.write_entry(_someone(), ChartEntry.Claim.UNWELL,
					"Reports transient dizziness on standing.", 18 * 60 + 35)
			EventBus.request_ui.emit("chart", {"patient_id": _someone()})
		"write":
			# The form itself, standing in the bay: the note being composed, the
			# gap it will record, and who is in the room while you compose it.
			var pl = tree.get_first_node_in_group("player")
			var h = tree.get_first_node_in_group("hospital")
			if pl != null and h != null:
				pl.global_position = h.point_in("ward") + Vector3(0, 0.1, 0)
			EventBus.request_ui.emit("chart", {"patient_id": _someone()})
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
				w.examine(_someone())
			EventBus.request_ui.emit("patient", {"patient_id": _someone()})
		"day_over":
			EventBus.request_ui.emit("day_over", {
				"verdict": ReviewSystem.OUTCOME_FLAGGED,
				"remembered": PackedStringArray([_someone()])})
		"paid":
			# THE WAY OUT. Nothing in the game had an ending until this session.
			# Staged with a plausible career behind it, or the card documents a
			# doctor who paid off fifteen thousand pounds in no shifts at all.
			DoctorRecord.wipe()
			var won := DoctorRecord.load_from_state()
			for i in 8:
				won.record_night([], ReviewSystem.OUTCOME_CLEAR)
			won.record_night([], ReviewSystem.OUTCOME_QUESTIONS)
			GameState.set_flag("debt_remaining", 0)
			GameState.day = maxi(DoctorRecord.load_from_state().nights, 1)
			GameState.start_day()
			EventBus.request_ui.emit("day_over",
				{"verdict": ReviewSystem.OUTCOME_CLEAR})
		"struck_off":
			GameState.reset_debt()
			DoctorRecord.wipe()
			var rec := DoctorRecord.load_from_state()
			rec.record_night([_mk("uncorroborated_stay")], ReviewSystem.OUTCOME_QUESTIONS)
			rec.record_night([_mk("uncorroborated_stay"), _mk("backdated")],
				ReviewSystem.OUTCOME_FLAGGED)
			rec.record_night([_mk("uncorroborated_stay"), _mk("sent_home_unwell")],
				ReviewSystem.OUTCOME_ESCALATED)
			rec.record_night([_mk("backdated")], ReviewSystem.OUTCOME_FLAGGED)
			# THE CARD SAYS "DAY %d" AND THE STATS SAY "%d SHIFTS", and this
			# staged four nights onto a day-one career — so the shipped
			# screenshot of the game's own ending read "Day 1" over "4 SHIFTS".
			# In real play the two always agree; a marketing shot that
			# contradicts itself is still a marketing shot that contradicts
			# itself, and this is the frame somebody would put on a store page.
			GameState.day = rec.nights
			GameState.start_day()
			GameState.set_flag("debt_remaining", 9240)
			EventBus.request_ui.emit("day_over",
				{"verdict": ReviewSystem.OUTCOME_ESCALATED})
		"ward_three":
			# THE THIRD WARD. Nobody on it is ill except a man who says he is
			# fine, and the best-paying bed is a woman asking you to keep her.
			GameState.day = 3
			GameState.start_day()
			if w != null:
				w.start()
				var ps4 = tree.get_first_node_in_group("patient_system")
				if ps4 != null and ps4.has_method("reset_day"):
					ps4.reset_day()
			EventBus.request_ui.emit("patient", {"patient_id": "fry"})
		"review":
			# Back to the first ward: this stage names its patients, and the
			# ward_two stage before it left the day on the second one. Staged
			# with a fortnight behind it, because the escalation — her opening
			# line, the running tally, how near the edge you are — is the half
			# of this screen a first-night shot cannot show.
			GameState.day = 1
			GameState.start_day()
			DoctorRecord.wipe()
			var had := DoctorRecord.load_from_state()
			had.record_night([_mk("uncorroborated_stay")], ReviewSystem.OUTCOME_QUESTIONS)
			had.record_night([_mk("uncorroborated_stay"), _mk("backdated")],
				ReviewSystem.OUTCOME_FLAGGED)
			had.record_night([_mk("uncorroborated_stay")], ReviewSystem.OUTCOME_CLEAR)
			had.record_night([_mk("backdated")], ReviewSystem.OUTCOME_FLAGGED)
			if w != null:
				w.start()
				var ps3 = tree.get_first_node_in_group("patient_system")
				if ps3 != null and ps3.has_method("reset_day"):
					ps3.reset_day()
				w.advance_to(19 * 60 + 5)
				w.write_entry(_someone(), ChartEntry.Claim.UNWELL,
					"Reports transient dizziness on standing.", 18 * 60 + 35)
			if w != null:
				# The chart stage already left a contradiction in Sam Oduya's
				# notes; hold him and the reviewer has something to ask about,
				# which is the only version of this screen worth looking at.
				w.set_disposition(_someone(), "hold")
				# EVERYONE ELSE ON THIS WARD. The list was four names from the
				# canonical seed-0 ward and this harness runs on another one, so
				# every call errored — "Invalid access to property or key
				# 'kerrigan'" — four times per run, in among the real output.
				for id in _the_others():
					w.set_disposition(id, "discharge")
				w.advance_to(Cases.DEBT_DUE_MINUTE)
				w.end_day()
			EventBus.request_ui.emit("review", {})

## Stand in front of somebody. Characters have to read at two metres and at ten.
## WHOEVER IS ACTUALLY IN THE BED, not a name from another ward.
##
## These two shots asked for "oduya" and this harness starts a career on seed
## 20260822 — a ward oduya is not on. `get_body` came back null, the function
## returned, and the camera stayed wherever the previous shot had left it. So
## the only two frames in the whole set that were supposed to photograph a
## PERSON have been quietly photographing the same wide ward view as everything
## else, for as long as they have existed.
##
## That is why "every patient in the game is the same body" survived a hundred
## screenshot runs: the shots that would have shown it never framed anybody.
func _someone() -> String:
	var r := Cases.roster()
	return String(r[0]["id"]) if not r.is_empty() else ""

func _frame_a_person(cam: Camera3D, how: String) -> void:
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		push_error("shot: no patient system to photograph")
		return
	# SOMEBODY'S FAMILY, AT THE BEDSIDE. A spawn nobody has ever looked at is a
	# spawn with a pose bug in it, and this one puts a body next to a bed by
	# hand rather than by walking it there.
	if how == "visitor":
		var w = tree.get_first_node_in_group("ward_day")
		var who := _someone()
		if w != null and tree.get_nodes_in_group("visitor").is_empty():
			w.visitor_arrived.emit(who, "Ruth Kerrigan")
		var body = ps.get_body(who)
		if body == null or not body.is_inside_tree():
			push_error("shot: nobody to visit")
			return
		var at: Vector3 = body.head_position()
		cam.global_position = at + Vector3(2.6, 0.55, -3.4)
		cam.look_at(at + Vector3(0.6, -0.45, 0.2), Vector3.UP)
		return

	# ALL FIVE HEADS IN ONE FRAME. The variety between patients is the thing
	# that is easiest to lose and hardest to see one bed at a time — five
	# people who differ only slightly from their neighbour still read as one
	# person repeated. Photographed square on, from the foot of the bay.
	if how == "lineup":
		var heads: Array = []
		for c in Cases.roster():
			var body = ps.get_body(String(c["id"]))
			if body != null and body.is_inside_tree():
				heads.append(body.head_position())
		if heads.is_empty():
			push_error("shot: nobody on the ward to line up")
			return
		var mid := Vector3.ZERO
		for hp in heads:
			mid += hp
		mid /= float(heads.size())
		cam.global_position = Vector3(mid.x, mid.y + 0.25, mid.z - 5.4)
		cam.look_at(Vector3(mid.x, mid.y - 0.10, mid.z), Vector3.UP)
		return

	var who := _someone()
	var b = ps.get_body(who)
	if b == null or not b.is_inside_tree():
		# LOUDLY. A silent return here is what hid this for so long.
		push_error("shot: nobody to photograph — wanted %s on ward %d" % [who, GameState.day])
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

## Everyone on today's ward except the one the shots are framed on.
func _the_others() -> Array:
	var out: Array = []
	var first := _someone()
	for c in Cases.roster():
		if String(c["id"]) != first:
			out.append(String(c["id"]))
	return out

## A finding of a given kind, for staging a record that took a few weeks.
func _mk(kind: String):
	var f = Contradictions.Finding.new()
	f.kind = kind
	return f

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
		var buried := _hud_under_the_card()
		if buried != "":
			note += "   [UNDER THE CARD: %s]" % buried
	print("  shot: ", ProjectSettings.globalize_path(path), note)

## The worst overflow on any scrolling area in the screen, as a fraction of its
## own content height. 0.0 means everything fits without scrolling.
## WHAT THE CARD IS SITTING ON TOP OF.
##
## Only measurable here, for the same reason as the fold: under `--headless` the
## root window is 64 pixels tall and every global rect is nonsense. The patient
## card is a sheet pinned to the right of the screen and the HUD's controls
## reminder is anchored to the bottom-right CORNER — so with a card open the
## only part of that line anybody could see was the last three letters of
## "pause" sticking out past the card's left edge, on every monitor, for as long
## as both have existed. It reads as a rendering fault, not a hint.
func _hud_under_the_card() -> String:
	if game == null or game.ui == null or game.ui.current == null:
		return ""
	var hud = tree.get_first_node_in_group("hud")
	if hud == null:
		return ""
	var sheet := Rect2()
	for c in _controls_in(game.ui.current):
		if c is PanelContainer and c.size.x > 40.0 and c.size.y > 40.0:
			sheet = c.get_global_rect()
			break
	if sheet.size.x <= 0.0:
		return ""
	var hit: Array = []
	for c in _controls_in(hud):
		if not (c is Label or c is PanelContainer):
			continue
		if not c.is_visible_in_tree() or c.size.x < 8.0 or c.size.y < 8.0:
			continue
		if c is Label and String((c as Label).text).strip_edges() == "":
			continue
		if sheet.intersects(c.get_global_rect()):
			hit.append(c.name if c is PanelContainer else String((c as Label).text).left(24))
	return "" if hit.is_empty() else ", ".join(PackedStringArray(hit))

func _controls_in(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Control:
			out.append(c)
		out.append_array(_controls_in(c))
	return out

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
