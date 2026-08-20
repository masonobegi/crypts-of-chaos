extends CanvasLayer
## Owns the HUD and routes every modal screen. Screens are built procedurally on
## demand and freed on close, so nothing is kept in memory or in a .tscn.

const SCREEN_SCRIPTS := {
	"dialogue": "res://scripts/ui/screen_dialogue.gd",
	"chart": "res://scripts/ui/screen_chart.gd",
	"records": "res://scripts/ui/screen_records.gd",
	"shift_select": "res://scripts/ui/screen_shift_select.gd",
	"exam": "res://scripts/ui/screen_exam.gd",
	"surgery": "res://scripts/ui/screen_surgery.gd",
	"prescribe": "res://scripts/ui/screen_prescribe.gd",
	"setbone": "res://scripts/ui/screen_setbone.gd",
	"medicate": "res://scripts/ui/screen_medicate.gd",
	"suture": "res://scripts/ui/screen_suture.gd",
	"court": "res://scripts/ui/screen_court.gd",
	"night": "res://scripts/ui/screen_night.gd",
	"briefing": "res://scripts/ui/screen_briefing.gd",
	"review": "res://scripts/ui/screen_review.gd",
	"statement": "res://scripts/ui/screen_statement.gd",
	"upgrades": "res://scripts/ui/screen_upgrades.gd",
	"tablet": "res://scripts/ui/screen_tablet.gd",
}

var hud: HUD
var current: Control = null
var current_id := ""

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	EventBus.request_ui.connect(open)
	EventBus.close_ui.connect(func(_id): close())

	var shift = get_tree().get_first_node_in_group("shift_system")
	if shift:
		shift.shift_choice_ready.connect(func(d): open("shift_select", d))
		shift.briefing_ready.connect(func(d): open("briefing", d))
		shift.review_ready.connect(func(d): open("review", d))
		shift.statement_ready.connect(func(d): open("statement", d))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if current != null:
			if current_id in ["shift_select", "briefing", "review", "statement", "game_over"]:
				return          # these are not dismissible
			close()
		else:
			var owed := _owed_screen()
			if owed.is_empty():
				open("pause", {})
			else:
				open(String(owed["id"]), owed["ctx"])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tablet") and current == null:
		open("tablet", {})
		get_viewport().set_input_as_handled()

## The screen the current phase cannot proceed without, if it is not on screen.
##
## Three of the game's five phases can only be left through one button on one
## screen, and every one of those screens could be dismissed:
##
##   PRE_SHIFT     the briefing calls clock_in()  — and the first-run tutorial
##                 sits on top of it, so Escape there ended a brand-new career
##                 before it started
##   CHART_REVIEW  the review calls clock_out()   — and the review's OTHER
##                 button, "Go fix something", closes it on purpose
##   POST_SHIFT    the statement calls next_day() — and Escape on the upgrade
##                 shop it opens closes the lot
##
## In every case the result was the same: a running game with no screen, a
## stopped clock, and no input anywhere in the building that could advance the
## day. The career was over and nothing said so.
##
## Rather than adding two more names to the non-dismissible list — which would
## have made the tutorial unskippable and the shop a trap of its own — Escape
## with nothing on screen puts the owed screen back. Dismissing is always
## allowed; losing the game to it is not.
func _owed_screen() -> Dictionary:
	var ss = get_tree().get_first_node_in_group("shift_system")
	if ss == null:
		return {}
	match GameState.phase:
		GameState.Phase.PRE_SHIFT:
			return {"id": "briefing", "ctx": ss.briefing()}
		GameState.Phase.CHART_REVIEW:
			if not ss.last_review.is_empty():
				return {"id": "review", "ctx": ss.last_review}
		GameState.Phase.POST_SHIFT:
			if not ss.last_statement.is_empty():
				return {"id": "statement", "ctx": ss.last_statement}
	return {}

# ------------------------------------------------------------------ routing
func open(id: String, ctx: Dictionary = {}) -> void:
	if current != null:
		close()
	var screen: Control = null
	if SCREEN_SCRIPTS.has(id):
		var script: GDScript = load(SCREEN_SCRIPTS[id])
		if script == null or not script.can_instantiate():
			Log.e("screen '%s' failed to load" % id, "UI")
			return
		screen = script.new()
		screen.set("ctx", ctx)
		screen.set("ui", self)
	else:
		screen = _build_simple(id, ctx)
	if screen == null:
		return
	current = screen
	current_id = id
	add_child(screen)
	_set_modal(true)
	# After it is genuinely up, and regardless of who asked. See EventBus.
	EventBus.ui_opened.emit(id)

func close() -> void:
	if current == null:
		return
	current.queue_free()
	current = null
	current_id = ""
	_set_modal(false)

func _set_modal(on: bool) -> void:
	get_tree().paused = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.input_locked = on
	if hud:
		hud.set_crosshair_visible(not on)

# ------------------------------------------------------------------ simple screens
func _build_simple(id: String, ctx: Dictionary) -> Control:
	match id:
		"pause": return _pause_screen()
		"settings": return _settings_screen()
		"tutorial": return _tutorial_screen()
		"game_over": return _game_over_screen(String(ctx.get("ending", "saint")))
		"vitals": return _vitals_screen(String(ctx.get("patient_id", "")))
	Log.w("unknown screen '%s'" % id, "UI")
	return null

func _shell(width: float, height: float, heading: String) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(UIKit.dim_background())
	var panel := UIKit.center_panel(width, height)
	root.add_child(panel)
	var v := UIKit.vbox(12)
	panel.add_child(v)
	if heading != "":
		v.add_child(UIKit.title(heading, 26, UIKit.ACCENT))
		v.add_child(UIKit.rule())
	return [root, v]

# ---- settings
##
## Every one of these is a thing a player will look for in the first two
## minutes and, until now, not find. Mouse sensitivity in particular: a
## first-person game whose look speed cannot be changed is one somebody
## refunds rather than adjusts to.
func _settings_screen() -> Control:
	var parts := _shell(680, 720, "Settings")
	var outer: VBoxContainer = parts[1]
	# The options scroll and the buttons do not.
	#
	# Fifteen rows at a fixed height overflowed a fixed-height panel and pushed
	# "Back" off the bottom of the screen — a settings screen you cannot leave
	# is worse than no settings screen. A scroll region means this cannot break
	# again if a row is added, or on a shorter display.
	var v := UIKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroller := UIKit.scroll(v)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroller)
	var pct := func(x: float) -> String: return "%d%%" % int(round(x * 100.0))

	v.add_child(UIKit.label("AUDIO", 13, UIKit.INK_DIM))
	v.add_child(UIKit.slider("Master volume", Settings.get_value("master_volume"),
		0.0, 1.0, 0.05, func(x): Settings.set_value("master_volume", x), pct))
	v.add_child(UIKit.slider("Effects", Settings.get_value("sfx_volume"),
		0.0, 1.0, 0.05, func(x):
			Settings.set_value("sfx_volume", x)
			# Play something at the new level, so the slider answers the
			# question it is actually being asked.
			AudioMgr.play("beep", -8.0), pct))
	v.add_child(UIKit.slider("Ambience", Settings.get_value("music_volume"),
		0.0, 1.0, 0.05, func(x): Settings.set_value("music_volume", x), pct))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("CONTROLS AND CAMERA", 13, UIKit.INK_DIM))
	v.add_child(UIKit.slider("Mouse sensitivity", Settings.get_value("mouse_sensitivity"),
		0.2, 3.0, 0.05, func(x): Settings.set_value("mouse_sensitivity", x),
		func(x: float) -> String: return "%.2fx" % x))
	v.add_child(UIKit.toggle("Invert look", Settings.get_value("invert_y"),
		func(b): Settings.set_value("invert_y", b)))
	v.add_child(UIKit.slider("Field of view", Settings.get_value("fov"),
		60.0, 110.0, 1.0, func(x): Settings.set_value("fov", x),
		func(x: float) -> String: return "%d" % int(x)))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("COMFORT", 13, UIKit.INK_DIM))
	v.add_child(UIKit.slider("Camera shake", Settings.get_value("camera_shake"),
		0.0, 1.0, 0.1, func(x): Settings.set_value("camera_shake", x), pct))
	v.add_child(UIKit.slider("Head bob", Settings.get_value("head_bob"),
		0.0, 1.0, 0.1, func(x): Settings.set_value("head_bob", x), pct))
	v.add_child(UIKit.toggle("Subtitles", Settings.get_value("subtitles"),
		func(b): Settings.set_value("subtitles", b)))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("DISPLAY", 13, UIKit.INK_DIM))
	v.add_child(UIKit.toggle("Fullscreen", Settings.get_value("fullscreen"),
		func(b): Settings.set_value("fullscreen", b)))
	v.add_child(UIKit.toggle("V-Sync", Settings.get_value("vsync"),
		func(b): Settings.set_value("vsync", b)))

	outer.add_child(UIKit.spacer(6))
	var row := UIKit.hbox(10)
	var reset := UIKit.button("Reset to defaults", func():
		Settings.reset_to_defaults()
		# Rebuilt rather than updated: fifteen widgets each holding their own
		# copy of a value is fifteen things to forget to refresh.
		close()
		open("settings", {}), Color(0.28, 0.20, 0.20))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset)
	var back := UIKit.button("Back", close)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	outer.add_child(row)
	return parts[0]

# ---- pause
func _pause_screen() -> Control:
	var parts := _shell(400, 430, "Paused")
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.label("Day %d · %s" % [GameState.day, GameState.time_string()], 15, UIKit.INK_DIM))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Resume", close))
	v.add_child(UIKit.button("Save", func():
		SaveSystem.save_game(SaveSystem.AUTOSAVE)
		EventBus.toast.emit("Saved.", "good")))
	v.add_child(UIKit.button("Tablet", func(): open("tablet", {})))
	v.add_child(UIKit.button("Settings", func(): open("settings", {})))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Quit to Menu", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"), Color(0.3, 0.16, 0.16)))
	return parts[0]

# ---- tutorial
func _tutorial_screen() -> Control:
	var parts := _shell(700, 560, "Ward C — First Shift")
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.rich("""[b]You are $%d in debt, your bills are $%d a day, and you make $240 a shift.[/b]

The hospital bills for every day a patient stays. Your bonus is a share of that.
Nobody will ever ask you to do anything unethical. They don't have to.

[b]The basics[/b]
· [color=#5cc]WASD[/color] move, [color=#5cc]E[/color] use, [color=#5cc]LMB[/color] grab, [color=#5cc]RMB[/color] throw, [color=#5cc]Q[/color] tablet.
· Every patient has a [b]chart[/b] — pick it up and read it.
· Treatment machines have a [b]dial[/b] and a [b]prescribed setting[/b]. The chart says which.
· A patient leaves when they're better. Not when the paperwork says so.

[b]The part nobody will tell you[/b]
· People remember what they [i]see[/i]. Two witnesses is much worse than one.
· A complication with a plausible cause written down [i]before anyone notices[/i]
  is just medicine. The same complication with no paperwork is an incident.
· Machines keep their own logs. So does everyone's memory.
· Noise moves people. That's all a thrown bedpan is: a way to move someone.

Nothing in this game will ever be labelled 'suspicious'. Work it out.""" % [GameState.total_debt(), GameState.daily_debt_payment()], 15))
	v.add_child(UIKit.spacer())
	# Hands off to the morning brief rather than closing onto an empty hospital.
	#
	# This screen used to end with a button labelled "Clock in" that set a flag
	# and closed. It did not clock anybody in — the ONLY caller of
	# ShiftSystem.clock_in() in the whole game is the briefing's button, and
	# open() closes whatever is already up, so the briefing this screen appeared
	# on top of had already been destroyed. A new player pressing New Career
	# landed in a hospital stuck in PRE_SHIFT: clock frozen at 8:00, no hour
	# ticks, no appointments, no tutorial steps (they are gated on
	# shift_started), and no input anywhere that could start the day. Every
	# harness sets tutorial_done before booting, so nothing ever walked it.
	v.add_child(UIKit.button("Read the morning brief", func():
		GameState.set_flag("tutorial_done", true)
		close()
		var ss = get_tree().get_first_node_in_group("shift_system")
		if ss:
			open("briefing", ss.briefing()), Color(0.16, 0.32, 0.30)))
	return parts[0]

# ---- game over
func _game_over_screen(ending_id: String) -> Control:
	var spec := Endings.spec(ending_id)
	var parts := _shell(760, 620, String(spec["title"]))
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.label(String(spec["line"]), 17, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.label(String(spec["epitaph"]), 14, UIKit.INK_DIM))
	v.add_child(UIKit.rule())
	var s := GameState.stats

	# The score. Everything below it is detail; this is the number the run was
	# for, and it is stated as what it is rather than as "final earnings".
	var haul := UIKit.panel(Color(0.13, 0.17, 0.14, 0.95), 8, 1, UIKit.MONEY)
	var hv := UIKit.vbox(2)
	hv.add_child(UIKit.label("YOU TOOK OUT OF THAT HOSPITAL", 13, UIKit.INK_DIM))
	hv.add_child(UIKit.title(UIKit.money_str(int(s.personal_earned)), 40, UIKit.MONEY))
	hv.add_child(UIKit.label("over %d %s, before %s" % [GameState.day,
		"day" if GameState.day == 1 else "days",
		_what_stopped_you(ending_id)], 14, UIKit.INK_DIM))
	var prev: Dictionary = Meta.best_haul
	if not prev.is_empty() and int(prev.get("earned", 0)) > 0:
		var diff := int(s.personal_earned) - int(prev["earned"])
		hv.add_child(UIKit.row("Your best so far",
			"%s over %d days" % [UIKit.money_str(int(prev["earned"])), int(prev.get("days", 0))],
			UIKit.MONEY if diff <= 0 else UIKit.INK_DIM))
		if diff > 0:
			hv.add_child(UIKit.label("Beaten by %s." % UIKit.money_str(diff), 15, UIKit.GOOD))
	haul.add_child(hv)
	v.add_child(haul)
	var stats_box := UIKit.vbox(3)
	stats_box.add_child(UIKit.row("Shifts worked", str(s.shifts_worked)))
	stats_box.add_child(UIKit.row("Patients admitted", str(s.patients_admitted)))
	stats_box.add_child(UIKit.row("Patients actually cured", str(s.patients_cured), UIKit.GOOD))
	stats_box.add_child(UIKit.row("Bed-days billed", str(s.days_billed), UIKit.MONEY))
	stats_box.add_child(UIKit.row("Complications caused", str(s.complications_caused), UIKit.SUS))
	stats_box.add_child(UIKit.row("Injuries sustained on your ward",
		str(s.get("injuries_caused", 0)), UIKit.BAD))
	stats_box.add_child(UIKit.row("Operations", "%d, of which %d improvised" % [
		int(s.get("surgeries", 0)), int(s.get("surgeries_botched", 0))], UIKit.SUS))
	stats_box.add_child(UIKit.row("Sent home on the wrong thing",
		str(s.get("wrong_prescriptions", 0)), UIKit.SUS))
	stats_box.add_child(UIKit.row("...and came back", str(s.get("readmissions", 0)), UIKit.MONEY))
	stats_box.add_child(UIKit.row("...documented cleanly", str(s.complications_clean), UIKit.GOOD))
	stats_box.add_child(UIKit.row("Falsified entries", str(s.forged_entries), UIKit.BAD))
	stats_box.add_child(UIKit.row("Times witnessed", str(s.witnessed_acts), UIKit.WARN))
	stats_box.add_child(UIKit.row("Complaints filed about you", str(s.complaints), UIKit.BAD))
	stats_box.add_child(UIKit.row("Investigations survived", str(s.investigations_survived), UIKit.GOOD))
	stats_box.add_child(UIKit.row("Personal earnings", UIKit.money_str(s.personal_earned), UIKit.MONEY))
	stats_box.add_child(UIKit.row("Remaining debt", UIKit.money_str(GameState.total_debt()), UIKit.BAD))
	if String(s.longest_stay_name) != "":
		stats_box.add_child(UIKit.row("Longest stay",
			"%s — %.1f days" % [s.longest_stay_name, s.longest_stay], UIKit.SUS))
	v.add_child(UIKit.scroll(stats_box))
	v.add_child(UIKit.label(Endings.headline(s), 15, UIKit.WARN, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.button("New career", func():
		get_tree().paused = false
		GameState.start_new_career()
		Meta.apply_perk()
		get_tree().change_scene_to_file("res://scenes/Game.tscn")))
	v.add_child(UIKit.button("Main menu", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
	return parts[0]

## What actually ended it, in the words somebody would use.
func _what_stopped_you(ending_id: String) -> String:
	match ending_id:
		"prison", "custodial": return "they arrested you"
		"license_revoked", "struck_off": return "they took your licence"
		"bankrupt", "repossessed": return "the money ran out"
		"whistleblower": return "you told them yourself"
	return "you stopped"

# ---- vitals
func _vitals_screen(patient_id: String) -> Control:
	var ps = get_tree().get_first_node_in_group("patient_system")
	var p = ps.get_patient(patient_id) if ps else null
	if p == null:
		return null
	var parts := _shell(480, 400, p.display_name)
	var v: VBoxContainer = parts[1]
	var vit: Dictionary = p.vitals()
	v.add_child(UIKit.label(p.condition_name(), 16, UIKit.ACCENT))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.row("Humour balance", "%0.0f" % vit["humour_balance"]))
	v.add_child(UIKit.row("Spleen torque", "%0.1f" % vit["spleen_torque"]))
	v.add_child(UIKit.row("Ambient dread", "%0.0f" % vit["ambient_dread"]))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.row("Clinical impression", p.apparent_state(), UIKit.INK))
	v.add_child(UIKit.row("Day of stay", "%d of %d projected" % [
		int(ceil(p.days_admitted)), int(ceil(p.expected_stay_days))],
		UIKit.WARN if p.is_overdue() else UIKit.INK))
	for c in p.active_complications():
		v.add_child(UIKit.row(c.display_name,
			"documented" if c.documented_cause != "" else "UNDOCUMENTED",
			UIKit.GOOD if c.documented_cause != "" else UIKit.BAD))
	v.add_child(UIKit.spacer())
	v.add_child(UIKit.button("Close", close))
	return parts[0]

# ---- apply treatment confirmation
func _apply_treatment(ctx: Dictionary) -> Control:
	var ps = get_tree().get_first_node_in_group("patient_system")
	var ts = get_tree().get_first_node_in_group("treatment_system")
	var p = ps.get_patient(String(ctx.get("patient_id", ""))) if ps else null
	if p == null or ts == null:
		return null
	var tid := String(ctx.get("treatment_id", ""))
	var item = ctx.get("item", null)
	var pos: Vector3 = item.global_position if item != null and is_instance_valid(item) else Vector3.ZERO
	var res: Dictionary = ts.apply(p, tid, item, pos)

	var rs = get_tree().get_first_node_in_group("records_system")
	if rs:
		rs.log_real_treatment(p, tid)

	var parts := _shell(460, 300, DB.treatment_name(tid))
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.label("Administered to %s." % p.display_name, 16))
	# Never state the outcome numerically — you observe the patient, not a number.
	v.add_child(UIKit.label(String(RNG.pick("treat_flavour", [
		"They say they feel something. Possibly.",
		"No immediate reaction.",
		"They wince, then apologise for wincing.",
		"Hard to say. That's medicine.",
		"They thank you, which is nice.",
	])), 15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	if String(res.get("complication", "")) != "":
		v.add_child(UIKit.label("Something else has started happening.", 15, UIKit.SUS))
	v.add_child(UIKit.spacer())
	v.add_child(UIKit.button("Close", close))
	return parts[0]

# ---- run machine
func _run_machine(ctx: Dictionary) -> Control:
	var m = ctx.get("machine", null)
	var ts = get_tree().get_first_node_in_group("treatment_system")
	if m == null or ts == null:
		return null
	var p = m._nearby_patient(null)
	if p == null:
		var parts0 := _shell(420, 220, m.fixture_name)
		var v0: VBoxContainer = parts0[1]
		v0.add_child(UIKit.label("The cycle runs. There is nobody in it.", 16, UIKit.INK_DIM))
		v0.add_child(UIKit.spacer())
		v0.add_child(UIKit.button("Close", close))
		return parts0[0]

	var res: Dictionary = ts.run_machine(m, p)
	var rs = get_tree().get_first_node_in_group("records_system")
	if rs:
		rs.log_real_treatment(p, m.treatment_id)

	var parts := _shell(480, 340, m.fixture_name)
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.row("Patient", p.display_name))
	v.add_child(UIKit.row("Setting", "%d (prescribed %d)" % [m.dial, m.prescribed],
		UIKit.INK if absi(m.dial - m.prescribed) < 2 else UIKit.WARN))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label(String(RNG.pick("machine_flavour", [
		"The machine hums. Then stops humming.",
		"Cycle complete. The readout blinks twice.",
		"A smell of warm dust.",
		"It makes the noise it makes.",
	])), 15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	if String(res.get("complication", "")) != "":
		v.add_child(UIKit.label("%s looks different." % p.display_name, 15, UIKit.SUS))
	v.add_child(UIKit.label("Logged to device history.", 12, UIKit.INK_DIM))
	v.add_child(UIKit.spacer())
	v.add_child(UIKit.button("Close", close))
	return parts[0]
