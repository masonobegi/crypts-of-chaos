extends RefCounted
## RENDER A TRAILER, because it is the one asset a Steam page is mostly judged
## on and this project could not produce a single second of moving picture.
##
## Everything here is the screenshot harness's machinery with the still taken
## out of it. `shot_impl.gd` places a camera, settles the tree for four frames
## and saves one PNG; this places a camera on a PATH, saves EVERY frame, and
## hands the sequence to ffmpeg. The two share their hard-won staging lessons
## rather than their code, deliberately — a still wants the ward to stop moving
## and a trailer wants it not to.
##
## THE THREE THINGS THAT MAKE IT WORK, none of them obvious:
##
## 1. `--fixed-fps 24`. A frame costs about two seconds to rasterise on
##    llvmpipe, so a tree stepped by REAL delta animates at half a frame a
##    second and the finished film is a slideshow of people teleporting. With a
##    fixed delta every `_process` is exactly 1/24 of a second of game time
##    whatever the wall clock says, so the sequence plays back at the speed the
##    game actually runs at. `play_run.gd` learned this first.
## 2. THE CUT ORDER IS THE ENGINE ORDER. The title screen is a different scene
##    to the ward and the transition only goes one way, so the film ends on the
##    logo rather than opening on it — which is a fine structure for a trailer
##    and a terrible one to discover you are stuck with afterwards. Said out
##    loud here so nobody spends an afternoon trying to put the title first.
## 3. THE AUDIO IS NOT RECORDED, IT IS REBUILT. The render is forty times
##    slower than real time, so anything captured off the audio server would
##    drift by minutes. `AudioMgr._build_music()` returns the score as three
##    sub-streams of 16-bit PCM, which is the same data the game plays; the
##    stems are summed and written as a WAV and ffmpeg muxes it. Sample
##    accurate, and it costs one pass over the buffer.
##
## Envs: TRAILER_FPS, TRAILER_SECS (a global cap, for a smoke render),
## TRAILER_ONLY (comma-separated name fragments, like SHOT_ONLY).

var tree: SceneTree = null
var game: Node = null
var menu: Node = null
var out_dir := ""
var fps := 24

var _boot := 0
var _shot := 0
var _shot_frame := 0
var _written := 0
var _caption: Label = null
var _caption_layer: CanvasLayer = null
var _fade: ColorRect = null
var _in_menu := false
var _only: Array = []
var _cap_frames := 0
var _t0 := 0
var _broken: Array = []

## THE CUT. One entry a shot, played in this order, and the order is the engine's
## (see note 2 above).
##
##   name   — the frame prefix, and what TRAILER_ONLY matches against
##   secs   — how long it is on screen
##   from/to        — where the camera starts and ends
##   at_from/at_to  — what it is looking at, start and end
##   clock  — minute of day for the light, -1 to leave it
##   ward   — ward index to repaint to, -1 to leave it
##   ui     — a screen to open behind the move, "" for none
##   text   — the caption, "" for none
##
## The camera MOVES IN EVERY SHOT, including the ones behind a card. A static
## frame with a menu over it is a screenshot, and eight screenshots in a row is
## what a trailer made by somebody who did not want to make one looks like.
const CUT := [
	{
		"name": "01_corridor", "secs": 4.0,
		"from": Vector3(2.4, 1.70, 2.0), "to": Vector3(8.2, 1.70, 2.0),
		"at_from": Vector3(19.0, 1.55, 2.1), "at_to": Vector3(19.0, 1.45, 2.4),
		"clock": 8 * 60 + 10, "ward": -1, "ui": "",
		"text": "Eight in the morning. Five beds.",
	},
	{
		"name": "02_ward", "secs": 4.0,
		"from": Vector3(10.0, 1.70, 4.6), "to": Vector3(10.0, 1.70, 7.2),
		"at_from": Vector3(10.0, 1.35, 12.0), "at_to": Vector3(11.4, 1.25, 12.0),
		"clock": 8 * 60 + 40, "ward": -1, "ui": "",
		"text": "",
	},
	{
		"name": "03_bedside", "secs": 4.0,
		"from": Vector3(15.6, 1.62, 10.10), "to": Vector3(14.6, 1.58, 10.55),
		"at_from": Vector3(12.10, 1.30, 11.70), "at_to": Vector3(12.10, 1.28, 11.75),
		"clock": 9 * 60 + 30, "ward": -1, "ui": "",
		"text": "Some of them are ready to go home.",
	},
	{
		"name": "04_chart", "secs": 4.5,
		"from": Vector3(13.9, 1.60, 10.6), "to": Vector3(13.4, 1.58, 10.9),
		"at_from": Vector3(12.10, 1.28, 11.70), "at_to": Vector3(12.10, 1.28, 11.70),
		"clock": 10 * 60 + 15, "ward": -1, "ui": "chart",
		"text": "Some of them are not.",
	},
	{
		"name": "05_records", "secs": 4.5,
		"from": Vector3(6.6, 1.62, -2.4), "to": Vector3(6.2, 1.60, -3.0),
		"at_from": Vector3(6.0, 1.50, -7.0), "at_to": Vector3(6.4, 1.48, -7.0),
		"clock": 13 * 60, "ward": -1, "ui": "records",
		"text": "Everything you write, you write in front of somebody.",
	},
	{
		"name": "06_evening", "secs": 4.0,
		"from": Vector3(3.0, 1.70, 9.2), "to": Vector3(7.0, 1.70, 9.6),
		"at_from": Vector3(18.5, 1.25, 11.2), "at_to": Vector3(18.5, 1.20, 11.4),
		"clock": 19 * 60 + 25, "ward": 4, "ui": "",
		"text": "The ward goes quiet. Nobody is watching now.",
	},
	{
		"name": "07_review", "secs": 4.5,
		"from": Vector3(16.6, 1.60, -2.2), "to": Vector3(16.2, 1.58, -2.8),
		"at_from": Vector3(16.0, 1.34, -7.0), "at_to": Vector3(16.3, 1.32, -7.0),
		"clock": 20 * 60, "ward": -1, "ui": "review",
		"text": "At eight o'clock somebody reads it back to you.",
	},
	{
		"name": "08_handover", "secs": 4.0,
		"from": Vector3(16.4, 1.60, -2.6), "to": Vector3(16.0, 1.58, -3.1),
		"at_from": Vector3(16.0, 1.32, -7.0), "at_to": Vector3(16.2, 1.30, -7.0),
		"clock": 20 * 60 + 20, "ward": -1, "ui": "day_over",
		"text": "",
	},
	{
		"name": "09_title", "secs": 5.0,
		"from": Vector3.ZERO, "to": Vector3.ZERO,
		"at_from": Vector3.ZERO, "at_to": Vector3.ZERO,
		"clock": -1, "ward": -1, "ui": "menu",
		"text": "",
	},
]

func start() -> void:
	fps = int(OS.get_environment("TRAILER_FPS")) if OS.get_environment("TRAILER_FPS") != "" else 24
	var cap := OS.get_environment("TRAILER_SECS")
	_cap_frames = int(float(cap) * float(fps)) if cap != "" else 0
	var only := OS.get_environment("TRAILER_ONLY")
	if only != "":
		for frag in only.split(",", false):
			_only.append(String(frag).strip_edges())
	# THE WINDOW IS NOT THE SCREEN, AND THE PNG IS THE WINDOW.
	#
	# `screenshots.sh` asks Xvfb for 1600x900 and every frame it has ever saved
	# is 1457x820, because the window manager takes a margin and Godot opens
	# inside what is left — nobody noticed, because a still is looked at rather
	# than measured. A video cannot shrug that off: 817x460 is not divisible by
	# two, so x264 refuses the stream outright, and any odd size is a trailer
	# Steam will not take. The screen is asked for bigger than the film and the
	# window is set to the film exactly. `window_set_size` is a measured no-op
	# under the dummy driver (gotcha 28) and works under Xvfb, which is the
	# only place this harness runs.
	var want_w := int(OS.get_environment("TRAILER_W")) if OS.get_environment("TRAILER_W") != "" else 1920
	var want_h := int(OS.get_environment("TRAILER_H")) if OS.get_environment("TRAILER_H") != "" else 1080
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_position(Vector2i(0, 0))
		DisplayServer.window_set_size(Vector2i(want_w, want_h))
	out_dir = "user://trailer"
	# A LEFTOVER FRAME IS A FRAME IN THE FILM. ffmpeg globs the directory, so a
	# shorter run after a longer one silently splices the tail of the old cut
	# onto the new one — and the numbering is contiguous, so nothing looks wrong
	# until somebody watches it.
	_wipe(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_dump_music()
	GameState.start_new_career(20260822)
	GameState.set_flag("tutorial_done", true)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	GameState.start_day()
	_build_overlay()
	_t0 = Time.get_ticks_msec()
	var got: Vector2i = DisplayServer.window_get_size()
	print("trailer: window %d x %d (asked for %d x %d)" % [got.x, got.y, want_w, want_h])

func tick() -> bool:
	tree.paused = false
	_boot += 1
	# The world has to exist before it can be photographed: the hospital is
	# built in `_ready`, the cast is spawned a frame later, and the first
	# rendered frame of a Godot scene is the one nothing has laid out in.
	if _boot < 24:
		return false
	if _shot >= CUT.size():
		_finish()
		return true
	var s: Dictionary = CUT[_shot]
	var want: int = maxi(1, int(float(s["secs"]) * float(fps)))
	if _cap_frames > 0:
		want = mini(want, maxi(1, _cap_frames / CUT.size()))
	if _shot_frame == 0 and not _enter(s):
		_shot += 1
		return false
	var t: float = float(_shot_frame) / float(maxi(1, want - 1))
	_pose(s, clampf(t, 0.0, 1.0))
	_set_fade(s, want)
	_write(String(s["name"]))
	_shot_frame += 1
	if _shot_frame >= want:
		_leave(s)
		_shot += 1
		_shot_frame = 0
	return false

# ------------------------------------------------------------------ staging

## Returns false to skip the shot entirely (TRAILER_ONLY). The staging still
## RUNS for a skipped shot — several of these leave the world somewhere the
## next one expects — only the frames are not written, which is the same rule
## `SHOT_ONLY` follows in the screenshot harness.
func _enter(s: Dictionary) -> bool:
	var ui := String(s["ui"])
	if ui == "menu":
		_into_the_menu()
	else:
		if int(s["ward"]) >= 0:
			_set_ward(int(s["ward"]))
		_set_clock(int(s["clock"]))
		if game != null and game.ui != null and game.ui.has_method("close"):
			game.ui.close()
		if ui != "":
			_open(ui)
			# A SHOT THAT ASKED FOR A CARD AND GOT NONE IS A FAILURE.
			#
			# `request_ui` opens nothing at all when the screen cannot read its
			# own context or the patient is not on the ward, and says nothing
			# about it — which cost this harness one shot on its first render
			# and cost `shot_impl` a frame of the back of a nurse's head
			# (gotcha 107). Checked in the same frame, because `UIRoot.open` is
			# a direct call off the signal and needs no frame to land in.
			if game.ui.current == null:
				_broken.append("%s wanted the '%s' screen and nothing opened"
					% [String(s["name"]), ui])
	_set_caption(String(s["text"]))
	return _wanted(String(s["name"]))

func _leave(s: Dictionary) -> void:
	if String(s["ui"]) == "menu":
		return
	if int(s["ward"]) >= 0:
		_set_day(1)
	if game != null and game.ui != null and game.ui.has_method("close"):
		game.ui.close()

func _pose(s: Dictionary, t: float) -> void:
	if String(s["ui"]) == "menu":
		return
	var cam := _camera()
	if cam == null:
		return
	# Smoothstep rather than a straight lerp: a dolly that starts and stops
	# abruptly reads as a camera being dragged, and the whole reason to move it
	# at all is that the shot should not look like a screenshot.
	var e: float = t * t * (3.0 - 2.0 * t)
	cam.global_position = Vector3(s["from"]).lerp(Vector3(s["to"]), e)
	cam.look_at(Vector3(s["at_from"]).lerp(Vector3(s["at_to"]), e), Vector3.UP)
	# NOBODY STANDS ON THE LENS, and the gaze and the interact prompt read the
	# BODY rather than the camera — gotchas 108 and 119, both of which cost a
	# render in the still harness and would cost forty here.
	_stand_where_the_camera_is(cam)
	_clear_the_lens(cam)

## UP FROM BLACK AT THE HEAD OF THE FILM AND DOWN AT THE END OF IT, and
## nowhere in between — a dip between every shot is a slideshow with a transition
## on it, which is what a trailer made out of screenshots looks like.
const FADE_SECS := 0.9

func _set_fade(s: Dictionary, want: int) -> void:
	if _fade == null:
		return
	var n: int = maxi(1, int(FADE_SECS * float(fps)))
	var a := 0.0
	if _shot == 0:
		a = clampf(1.0 - float(_shot_frame) / float(n), 0.0, 1.0)
	elif _shot == CUT.size() - 1:
		var left: int = want - 1 - _shot_frame
		a = clampf(1.0 - float(left) / float(n), 0.0, 1.0)
	_fade.color = Color(0.02, 0.03, 0.04, a)

func _camera() -> Camera3D:
	var pl = tree.get_first_node_in_group("player")
	if pl == null:
		return null
	for n in _all(pl):
		if n is Camera3D:
			return n as Camera3D
	return null

func _stand_where_the_camera_is(cam: Camera3D) -> void:
	var pl = tree.get_first_node_in_group("player")
	if pl == null or not (pl is Node3D):
		return
	var body := pl as Node3D
	var was: Vector3 = cam.global_position
	body.global_position = Vector3(was.x, body.global_position.y, was.z)
	cam.global_position = was

func _clear_the_lens(cam: Camera3D) -> void:
	for n in tree.get_nodes_in_group("npc"):
		if not (n is Node3D):
			continue
		var b := n as Node3D
		var away: Vector3 = b.global_position - cam.global_position
		away.y = 0.0
		if away.length() > 1.5 or away.length() < 0.001:
			continue
		b.global_position += away.normalized() * (1.5 - away.length())

func _open(which: String) -> void:
	if game == null or game.ui == null:
		return
	var w = tree.get_first_node_in_group("ward_day")
	match which:
		"chart":
			var roster: Array = Cases.roster()
			if not roster.is_empty():
				# `patient_id`, NOT `id`. `request_ui` for a screen whose context
				# it cannot read opens NOTHING, silently — gotcha 107 exactly,
				# and in a film it is four and a half seconds of an empty
				# bedside with a caption about a chart over it.
				EventBus.request_ui.emit("chart",
					{"patient_id": String(roster[1 % roster.size()]["id"])})
		"records":
			EventBus.request_ui.emit("records", {})
		"review":
			EventBus.request_ui.emit("review", {})
		"day_over":
			var verdict := ReviewSystem.OUTCOME_FLAGGED
			if w != null and w.has_method("end_day"):
				w.end_day()
			EventBus.request_ui.emit("day_over", {"verdict": verdict})

func _into_the_menu() -> void:
	# THE TRANSITION ONLY GOES ONE WAY, which is why the logo is the last shot.
	if game != null:
		tree.root.remove_child(game)
		game.queue_free()
		game = null
	menu = load("res://scenes/MainMenu.tscn").instantiate()
	tree.root.add_child(menu)
	_in_menu = true
	if menu.has_method("pose_for_capsule"):
		menu.pose_for_capsule(true)

func _set_clock(minute: int) -> void:
	if minute < 0 or game == null or not game.has_method("apply_shift_look"):
		return
	GameState.minute_of_day = minute
	game.apply_shift_look()
	# AND THE CORNER OF THE SCREEN. The clock label only repaints on
	# `minute_passed`, which is deliberately not emitted here because the
	# rounds, the ambience pulse and the force-end all hang off it — so the
	# evening shot came back as a ward at dusk with "1:00 PM" in the corner,
	# which is gotcha 117 on a surface that moves.
	var hud = tree.get_first_node_in_group("hud")
	if hud != null and hud.has_method("_on_clock"):
		hud._on_clock(minute)

func _set_ward(index: int) -> void:
	var want: int = maxi(0, index) % Cases.DAYS.size()
	for d in range(1, Cases.DAYS.size() + 1):
		if Cases.pool_index(d) == want:
			_set_day(d)
			return
	_set_day(1)

func _set_day(day: int) -> void:
	GameState.day = day
	GameState.day_started.emit(day)

# ------------------------------------------------------------------ overlay

## THE CAPTION AND THE FADE, on their own CanvasLayer above everything.
##
## Built rather than drawn into the PNGs afterwards because a caption has to sit
## over the game's own UI, not over a still of it, and because the game already
## owns the four typefaces the rest of the film is set in — a trailer in a
## different face to the game is a trailer for a different game.
func _build_overlay() -> void:
	_caption_layer = CanvasLayer.new()
	_caption_layer.layer = 200
	tree.root.add_child(_caption_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_layer.add_child(root)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color(0.98, 0.98, 0.95))
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 4)
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06, 0.9))
	# The INTERFACE sans, not the handwriting. `Typeface.for_author` maps a
	# chart author to a face and a caption is not a chart entry — a trailer set
	# in the player's own handwriting reads as the doctor narrating, which is
	# the one voice this game deliberately never uses.
	var face: Font = Typeface.sans()
	if face != null:
		_caption.add_theme_font_override("font", face)
	root.add_child(_caption)
	# THE FADE IS ADDED LAST, so it is over the caption as well as the game.
	# A dip to black with the words still burning through it is the single
	# most obvious "made in a hurry" artefact a cut can have.
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.04, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

func _set_caption(text: String) -> void:
	if _caption == null:
		return
	_caption.text = text
	# Placed every time rather than once: `set_anchors_preset` sets anchors and
	# not offsets, so a Control laid out at boot against a window that has since
	# been resized is a Control with no width and one character a line.
	var vp: Vector2 = tree.root.get_visible_rect().size
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_caption.position = Vector2(vp.x * 0.12, vp.y * 0.80)
	_caption.size = Vector2(vp.x * 0.76, vp.y * 0.16)
	# SIZED OFF THE FRAME, NOT TYPED IN. A 30-pixel caption is a third of the
	# height of a 540-line smoke render and a footnote on a 1080 one, so the
	# framing checked at preview size is not the framing that ships.
	_caption.add_theme_font_size_override("font_size", int(maxf(14.0, vp.y * 0.030)))
	_caption.add_theme_constant_override("outline_size", int(maxf(4.0, vp.y * 0.008)))

# ------------------------------------------------------------------ output

func _wanted(name: String) -> bool:
	if _only.is_empty():
		return true
	for frag in _only:
		if name.findn(String(frag)) >= 0:
			return true
	return false

func _write(name: String) -> void:
	if not _wanted(name):
		return
	var img := tree.root.get_texture().get_image()
	img.save_png("%s/f%05d.png" % [out_dir, _written])
	_written += 1

func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".png"):
			d.remove(f)
		f = d.get_next()
	d.list_dir_end()

## THE SCORE, SUMMED BACK INTO ONE BUFFER AND WRITTEN AS A WAV.
##
## `_build_music` renders the three stems already normalised against their own
## SUM (gotcha 92), so adding them back gives sample-for-sample the mix the game
## plays at 0 dB on every stem — which is what the trailer wants, because the
## only thing that ever moves those volumes is the last forty minutes of a
## shift and a trailer is not a shift.
func _dump_music() -> void:
	var stream = AudioMgr._build_music()
	if stream == null or not (stream is AudioStreamSynchronized):
		return
	var sync := stream as AudioStreamSynchronized
	var mixed := PackedByteArray()
	var n := 0
	for i in sync.get_stream_count():
		var st = sync.get_sync_stream(i)
		if st == null or not (st is AudioStreamWAV):
			continue
		var d: PackedByteArray = (st as AudioStreamWAV).data
		if mixed.is_empty():
			mixed = d.duplicate()
			n = d.size() / 2
			continue
		for k in mini(n, d.size() / 2):
			var a := _s16(mixed, k) + _s16(d, k)
			_put16(mixed, k, clampi(a, -32768, 32767))
	if n == 0:
		return
	var path := "user://trailer_music.wav"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var sr: int = AudioMgr.SR
	var bytes: int = n * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + bytes)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)          # PCM
	f.store_16(1)          # mono
	f.store_32(sr)
	f.store_32(sr * 2)     # byte rate
	f.store_16(2)          # block align
	f.store_16(16)         # bits
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(bytes)
	f.store_buffer(mixed.slice(0, bytes))
	f.close()
	print("trailer: music %.1fs -> %s" % [float(n) / float(sr),
		ProjectSettings.globalize_path(path)])

static func _s16(b: PackedByteArray, i: int) -> int:
	var v: int = b[i * 2] | (b[i * 2 + 1] << 8)
	return v - 65536 if v >= 32768 else v

static func _put16(b: PackedByteArray, i: int, v: int) -> void:
	var uv: int = v & 0xFFFF
	b[i * 2] = uv & 0xFF
	b[i * 2 + 1] = (uv >> 8) & 0xFF

func _finish() -> void:
	var secs: float = float(_written) / float(maxi(1, fps))
	print("trailer: %d frames at %d fps = %.1fs -> %s"
		% [_written, fps, secs, ProjectSettings.globalize_path(out_dir)])
	print("trailer: rendered in %.1f min" % [float(Time.get_ticks_msec() - _t0) / 60000.0])
	# GOTCHA 21: A HARNESS THAT CANNOT FAIL. This one can — a cut that renders
	# no frames at all, or a shot list whose total does not match what was
	# written, is a film nobody would notice was wrong until they watched it.
	if _written <= 0:
		_broken.append("no frames were written at all")
	if not _broken.is_empty():
		for b in _broken:
			print("  %s" % String(b))
		print("TRAILER FAILED — %d problem(s)" % _broken.size())
		return
	print("TRAILER OK")

func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
