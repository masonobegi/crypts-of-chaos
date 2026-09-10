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
	# THE SAME FRAME WITH EVERY CEILING FITTING IN THE BUILDING SWITCHED OFF.
	#
	# It is here because for the whole life of this project they may as well
	# have been. The floors, walls and ceilings were `rbox_mesh` slabs, which
	# have no vertex anywhere except on their own edges, so a lamp three metres
	# above the middle of a twenty-metre floor had nothing to light — and
	# turning all thirty-four of them off moved the ward floor by exactly zero
	# levels across 225,000 pixels. Every other layer in this repo passed:
	# nothing errors, nothing is missing, the fittings are all there, their
	# emissive panels still glow, and the room is lit by ambient. The ONLY way
	# to see it is to take the light away and measure whether anything changed.
	#
	# Cheap, because it is one extra frame from a camera that is already set up
	# — and it fails loudly, which is the difference between a check and a
	# screenshot.
	["02b_fittings_off", Vector3(10.0, 1.7, 4.8), Vector3(10.0, 1.3, 12.0)],
	# THE SAME CAMERA ON A DIFFERENT WARD, which is the only way to see whether
	# there IS a different ward. The building is built once and a career rolls
	# the day over in place, so for the life of this project every night was
	# played in one room painted one colour with "Ward C" over the beds —
	# invisible to twenty-one frames of one morning, because every one of them
	# was night one.
	# A WARD INDEX, NOT A NIGHT. This was the day number, and the ward order is
	# a per-career permutation — so "day 3" is whichever of the six that career
	# happens to deal third, and a frame named after a ward showed a different
	# one. Two of these were rendered under the wrong names before anybody
	# looked at the sign in the picture.
	["02d_ward_ash", Vector3(10.0, 1.7, 4.8), Vector3(10.0, 1.3, 12.0), -1, 1],
	["02e_ward_beech", Vector3(10.0, 1.7, 4.8), Vector3(10.0, 1.3, 12.0), -1, 4],
	["02f_ward_2a", Vector3(10.0, 1.7, 4.8), Vector3(10.0, 1.3, 12.0), -1, 5],
	["03_bedside", "bedside"],
	["04_face", "face"],
	["04b_lineup", "lineup"],
	["04c_visitor", "visitor"],
	["05_ward_along", Vector3(1.6, 1.7, 9.5), Vector3(18.5, 1.2, 11.0)],
	["06_station", Vector3(6.0, 1.7, -1.0), Vector3(6.0, 1.3, -7.0)],
	["07_office", Vector3(16.0, 1.7, -2.0), Vector3(16.0, 1.3, -7.0)],
	["08_ward_wide", Vector3(2.0, 2.6, 6.0), Vector3(14.0, 1.0, 11.5)],
	# THE SAME WARD, TWELVE HOURS LATER, FROM THE SAME SPOT AS 02.
	#
	# A FOURTH ELEMENT IS A CLOCK. There was no frame anywhere in this set that
	# showed the building in the evening without a UI card over two thirds of
	# it, so "the evening never arrives" — the walls moved three and a half
	# levels of 255 between eight in the morning and half past seven — survived
	# every screenshot run this project has ever done. It is a controlled pair
	# with `02_ward_from_door` on purpose: same camera, same ward, same seed,
	# so the difference between the two frames is the light and nothing else,
	# and `_evening_reading` prints it.
	["09_ward_evening", Vector3(10.0, 1.7, 4.8), Vector3(10.0, 1.3, 12.0), 19 * 60 + 25],
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
		_skip_only = not _shot_wanted(String(MENU_SHOTS[menu_index]))
		if not _skip_only:
			_wanted += 1
		_save(String(MENU_SHOTS[menu_index]))
		menu_index += 1
		return false

	if index >= SHOTS.size():
		print("captured %d frames to %s" % [_wanted, ProjectSettings.globalize_path(out_dir)])
		# LAST, AND LOUD. Two of the frames above are not photographs, they are
		# measurements, and a measurement that prints a number nobody reads is
		# the same as no measurement. `screenshots.sh` exits on this line.
		if _visual_failures.is_empty():
			print("SHOT CHECKS PASSED")
		else:
			for why in _visual_failures:
				print("  not ok: %s" % why)
			print("SHOT CHECK FAILED — %d" % _visual_failures.size())
		return true
	var shot: Array = SHOTS[index]
	# ONE FRAME, WHEN ONE FRAME IS WHAT YOU ARE LOOKING AT.
	#
	# Twenty-one frames is twenty minutes on a software rasteriser, and chasing
	# a fault that appears in exactly two of them means paying for nineteen you
	# already have. `look.sh` exists for the same reason and does not help here:
	# these are UI stages, and it does not build them.
	#
	# `SHOT_ONLY` is a comma-separated list of names or fragments of them —
	# `SHOT_ONLY=struck_off,17` renders two. The staging still runs in order,
	# because several stages depend on the ones before them; only the SAVE is
	# skipped, which costs a few frames and nothing else.
	_skip_only = not _shot_wanted(String(shot[0]))
	if not _skip_only and _counted != index:
		# ONCE PER SHOT, NOT ONCE PER FRAME. A `ui:` stage returns false four
		# or five times while it settles and re-enters this line each time, so
		# counting here without the guard reported ten frames for two.
		_counted = index
		_wanted += 1
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
			#
			# ...AND THE THREE CARDS YOU READ AT THE DESK ARE READ AT THE DESK.
			# The end of a shift and both endings are signed off in your office
			# with the door shut, and they were staged in the middle of the ward
			# instead — so all three were photographed through a crowd, with
			# Adeyemi's head filling a third of the frame and three speech
			# bubbles clipped across the corner. The room behind a card is why
			# any of this is 3D; it should be the room the card belongs to.
			if String(shot[1]).substr(3) in ["day_over", "paid", "struck_off"]:
				_look_at_the_desk(cam)
			else:
				_look_down_the_ward(cam)
		else:
			# EVERY SETTLE FRAME, because they are walking. See `_clear_the_lens`.
			_clear_the_lens(cam)
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
	_set_clock(shot[3] if shot.size() > 3 else _clock_override())
	# A FIFTH FIELD IS A DAY, and it repaints the room for whichever ward that
	# night deals. Put back after the save, like the clock.
	if shot.size() > 4:
		_set_ward(int(shot[4]))
	if String(shot[0]) == "02b_fittings_off":
		_fittings(false)
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
	if String(shot[0]) == "02b_fittings_off":
		_fittings(true)
		_fittings_reading()
	if String(shot[0]) == "09_ward_evening":
		_evening_reading()
	if shot.size() > 4:
		# BACK TO NIGHT ONE, and by the DAY rather than by the ward. `Cases`
		# is a pure function of `GameState.day`, and every later stage in this
		# file builds its card from the `WardDay` in the tree — which is still
		# night one's. Restoring "whichever night deals Ward C" put the two out
		# of step under a career seed whose rotation does not start there, and
		# the board screen went looking for a patient who was not on the ward
		# it was asked about.
		_set_day(1)
	# BACK TO THE MORNING BEFORE THE NEXT FRAME. The clock is set here for the
	# LIGHT and nothing else — no verb has been performed and no minute has
	# really passed — so leaving it forward would hand every later stage a ward
	# that is somehow at half past seven with a full day's work still in it.
	_set_clock(_clock_override())
	index += 1
	return false

## Photograph the building at a stated minute of the day.
##
## `GameState.minute_of_day` is written directly rather than through `skip_to`,
## because `skip_to` emits `minute_passed` and is one-way — the ward's rounds,
## the ambience pulse and the force-end all hang off that signal, and a
## harness that wants a picture of half past seven does not want a ward that
## believes half past seven has HAPPENED. `apply_shift_look` is then called by
## hand, which is the one thing that actually reads the clock for the look.
##
## -1 means "leave it alone", which is what every frame but `09_ward_evening`
## gets unless SHOT_CLOCK says otherwise.
func _set_clock(minute) -> void:
	var m := int(minute)
	if m < 0 or game == null or not game.has_method("apply_shift_look"):
		return
	GameState.minute_of_day = m
	game.apply_shift_look()
	# AND THE CORNER OF THE SCREEN. The clock label only repaints on
	# `minute_passed`, which is deliberately not emitted here — so the first
	# evening frame this harness took was a ward at dusk with "8:03 AM" over
	# it, which is the same self-contradicting marketing shot as the ending
	# card that once read "Day 1" over "4 SHIFTS". Poked directly rather than
	# through the signal, because the signal is what the rounds, the ambience
	# pulse and the force-end all hang off.
	var hud = tree.get_first_node_in_group("hud")
	if hud != null and hud.has_method("_on_clock"):
		hud._on_clock(m)

## SHOT_CLOCK=1165 photographs the whole world set at 19:25.
##
## Sweeping a light means rendering the same room at the same minute twice with
## one number changed, and there was no way to ask for a minute at all: the
## only evening frames in the set were UI stages that had walked the clock
## there as a side effect of writing a note. As a fragment of a name in
## SHOT_ONLY costs one stage, the two together are the loop this file exists to
## be — `SHOT_ONLY=01_corridor SHOT_CLOCK=1165 ./screenshots.sh` is one frame
## of the corridor at half past seven, in about ninety seconds.
var _clock := -2

func _clock_override() -> int:
	if _clock == -2:
		var raw := OS.get_environment("SHOT_CLOCK").strip_edges()
		_clock = int(raw) if raw.is_valid_int() else -1
	return _clock

## The one measurement this pair exists for, printed beside the frames so it is
## in the run's own output rather than in somebody's head. Reads the same box
## out of `02_ward_from_door` and `09_ward_evening` — the middle band, which is
## wall, beds and floor and no HUD — and prints the difference. A build where
## the evening does not arrive prints a single-figure number here.
## Every ceiling fitting in the building, off and on again. `set_lamp_look` is
## the one place that knows how a fitting's single energy is split between its
## shadowed spot and its fill (`Build.SPOT_GAIN` / `FILL_GAIN`), so zeroing it
## there switches both halves of all of them; `apply_shift_look` puts back
## whatever the clock says they should be, which is also how the game itself
## sets them every minute.
func _fittings(on: bool) -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null or not h.has_method("set_lamp_look"):
		return
	if on:
		if game != null and game.has_method("apply_shift_look"):
			game.apply_shift_look()
	else:
		h.set_lamp_look(Color(1, 1, 1), 0.0)

## THE CHECK THAT WOULD HAVE CAUGHT IT. Compares the ward floor — the bottom
## band of the frame, which is nothing but floor from this camera — with the
## fittings on and with them off, and fails if the difference is under ten
## levels of 255. A building whose lamps are decorative prints zero here.
func _fittings_reading() -> void:
	if not (_saved.has("02_ward_from_door") and _saved.has("02b_fittings_off")):
		return
	var lit := _band_luma("%s/02_ward_from_door.png" % out_dir, 640, 860)
	var dark := _band_luma("%s/02b_fittings_off.png" % out_dir, 640, 860)
	if lit < 0.0 or dark < 0.0:
		return
	var delta := lit - dark
	print("  fittings: ward floor reads %.1f lit and %.1f with every fitting off (%.1f levels)"
		% [lit, dark, delta])
	if delta < 10.0:
		_visual_fail("the ceiling fittings light nothing: the ward floor moves %.1f levels between all of them on and all of them off" % delta)

func _evening_reading() -> void:
	# ONLY IF BOTH HALVES WERE TAKEN THIS RUN. `SHOT_ONLY=09` leaves a
	# `02_ward_from_door.png` on disk from whatever the last full run rendered,
	# and comparing a fresh evening against a stale morning is how a sweep
	# reports a gain it did not make.
	if not (_saved.has("02_ward_from_door") and _saved.has("09_ward_evening")):
		return
	var morning := _mean_luma("%s/02_ward_from_door.png" % out_dir)
	var evening := _mean_luma("%s/09_ward_evening.png" % out_dir)
	if morning < 0.0 or evening < 0.0:
		return
	print("  evening: ward reads %.1f at 08:00 and %.1f at 19:25 (%.1f levels)"
		% [morning, evening, evening - morning])
	if morning - evening < 20.0:
		_visual_fail("the evening does not arrive: the ward moves %.1f levels between 08:00 and 19:25" % (morning - evening))

## What this run measured and failed. Printed as one block at the end and read
## by `screenshots.sh`, which exits on it — a harness that prints a fault and
## returns 0 cannot fail (gotcha 21), and these two measurements are the only
## things in this repo that can see a lighting rig that is not connected.
var _visual_failures: Array = []

func _visual_fail(why: String) -> void:
	_visual_failures.append(why)

## Mean luminance of a horizontal band of a saved frame, or -1 if it is not
## there. Used for the floor, where the band is the whole width.
func _band_luma(path: String, y0: int, y1: int) -> float:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return -1.0
	var total := 0.0
	var n := 0
	var y := maxi(0, y0)
	var y_end := mini(img.get_height(), y1)
	while y < y_end:
		var x := 0
		while x < img.get_width():
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
			x += 4
		y += 4
	return (total / float(n)) * 255.0 if n > 0 else -1.0

## Mean luminance of the middle band of a saved frame, or -1 if it is not there.
## The band skips the top 130 and bottom 120 pixels because that is where the
## HUD lives, and a clock reading "8:00 AM" in white type is a bright rectangle
## that has nothing to do with how lit the room is.
func _mean_luma(path: String) -> float:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return -1.0
	var h := img.get_height()
	var w := img.get_width()
	var total := 0.0
	var n := 0
	var y := 130
	while y < h - 120:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
			x += 4
		y += 4
	return (total / float(n)) * 255.0 if n > 0 else -1.0

## From the ward door, along the row of beds. The one view that shows the game
## is a place and not a spreadsheet.
## Your own office, from the door, with the desk and the terminal in shot.
func _look_at_the_desk(cam: Camera3D) -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null:
		return
	# The vantage `07_office` already uses, which is known to frame the desk and
	# the terminal. A guessed one a metre nearer put the camera inside the desk.
	cam.global_position = Vector3(16.0, 1.7, -2.0)
	cam.look_at(Vector3(16.0, 1.3, -7.0), Vector3.UP)
	_clear_the_lens(cam)

func _look_down_the_ward(cam: Camera3D) -> void:
	var h = tree.get_first_node_in_group("hospital")
	if h == null:
		return
	cam.global_position = h.door_point("ward") + Vector3(-4.5, 0.0, 1.6)
	var at: Vector3 = h.door_point("ward") + Vector3(4.0, -0.35, 6.5)
	cam.look_at(at, Vector3.UP)
	_clear_the_lens(cam)

## NOBODY STANDS ON THE LENS.
##
## `_look_down_the_ward` puts the camera a metre and a half inside the ward
## door, which is exactly where every nurse in the building walks — and the
## `ui:` stages then settle for five frames, so somebody who was clear when the
## camera was placed has walked into it by the time the picture is taken. Two
## card frames came back as a photograph of the back of a head filling a third
## of the picture, with the card beside it. `faces.sh` learned the same lesson
## twice (gotcha 62): when a frame looks wrong, check where the camera is
## standing before you change anything in it.
##
## The offender is pushed OUT along the line from the camera rather than the
## camera being pushed back, because backing up from that vantage walks into
## the plaster. It is a photograph; moving a bystander is allowed.
func _clear_the_lens(cam: Camera3D) -> void:
	for n in tree.get_nodes_in_group("npc"):
		if not (n is Node3D):
			continue
		var b := n as Node3D
		var away: Vector3 = b.global_position - cam.global_position
		away.y = 0.0
		if away.length() > 1.9 or away.length() < 0.001:
			continue
		b.global_position += away.normalized() * (2.6 - away.length())

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
			GameState.day = _day_dealing(1)
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
			#
			# BY WARD, AND WITHOUT NAMING ANYBODY. This set `day = 3` and asked
			# for "fry" by id — and the ward order is a per-career permutation,
			# so night three is not the third ward and Rosalind Fry was not on
			# it. `request_ui` for a patient who is not on the ward opens
			# nothing, so this frame was a photograph of the back of a nurse's
			# head with no card on it at all, in a set whose whole job is the
			# screens. Gotcha 78, in the harness rather than in a check.
			GameState.day = _day_dealing(2)
			GameState.start_day()
			if w != null:
				w.start()
				var ps4 = tree.get_first_node_in_group("patient_system")
				if ps4 != null and ps4.has_method("reset_day"):
					ps4.reset_day()
			EventBus.request_ui.emit("patient", {"patient_id": _someone()})
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
## The night in the first cycle that deals the ward at `index` in `Cases.WARDS`.
## The rotation is drawn per career, so "day N" is not "ward N" on any seed but
## zero — and this harness runs at 20260822.
func _day_dealing(index: int) -> int:
	for d in range(1, Cases.DAYS.size() + 1):
		if Cases.pool_index(d) == index:
			return d
	return 1

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

## Which frames this run wants. Empty means all of them, which is the default
## and what `screenshots.sh` does.
var _only: PackedStringArray = PackedStringArray()
var _only_read := false
var _skip_only := false
var _wanted := 0
var _counted := -1
var _saved := {}

func _shot_wanted(name: String) -> bool:
	if not _only_read:
		_only_read = true
		var raw := OS.get_environment("SHOT_ONLY").strip_edges()
		if raw != "":
			for part in raw.split(",", false):
				_only.append(String(part).strip_edges())
	if _only.is_empty():
		return true
	for want in _only:
		if name.contains(want):
			return true
	return false

## Paint the ward for a given night without playing to it. `Hospital.reskin`
## reads `GameState.day` through `Cases.pool_index`, so the day IS the ward.
## Stand in the ward at `index` in `Cases.WARDS`, whichever night deals it.
##
## The rotation is a per-career permutation, so this walks the first cycle for
## the night that lands on the ward asked for rather than assuming night N is
## ward N — which it has not been since the order was drawn.
func _set_ward(index: int) -> void:
	var want: int = maxi(0, index) % Cases.DAYS.size()
	for d in range(1, Cases.DAYS.size() + 1):
		if Cases.pool_index(d) == want:
			_set_day(d)
			return
	_set_day(1)

func _set_day(day: int) -> void:
	GameState.day = maxi(1, day)
	if game != null and game.hospital != null:
		game.hospital.reskin()
	# ...AND THE CORNER OF THE SCREEN AGREES WITH THE SIGN. The HUD writes the
	# day on `day_started`, which this deliberately does not emit — so without
	# this every ward frame carried whatever number the frame before it left
	# behind, in a store screenshot.
	if game != null and game.ui != null:
		var hud = game.ui.get_node_or_null("HUD")
		if hud != null and hud.has_method("_refresh_static"):
			hud.call("_refresh_static")

func _save(name: String) -> void:
	if _skip_only:
		return
	_saved[name] = true
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	var note := ""
	# WHENEVER THERE IS A CARD UP, not "whenever the shot's name starts with a
	# 1". That happened to cover 10 through 19 and left `20_struck_off` — one of
	# the two endings, and the last thing a career shows anybody — unmeasured.
	if game != null and game.ui != null and game.ui.current != null:
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
