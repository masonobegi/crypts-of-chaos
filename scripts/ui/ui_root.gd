extends CanvasLayer
## Owns the HUD and routes every modal screen. Screens are built procedurally on
## demand and freed on close, so nothing is kept in memory or in a .tscn.

const SCREEN_SCRIPTS := {
	"dialogue": "res://scripts/ui/screen_dialogue.gd",
	"chart": "res://scripts/ui/screen_chart.gd",
	"records": "res://scripts/ui/screen_records.gd",
	"shift_select": "res://scripts/ui/screen_shift_select.gd",
	"exam": "res://scripts/ui/screen_exam.gd",
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
			open("pause", {})
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tablet") and current == null:
		open("tablet", {})
		get_viewport().set_input_as_handled()

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
		"tutorial": return _tutorial_screen()
		"game_over": return _game_over_screen(String(ctx.get("ending", "saint")))
		"vitals": return _vitals_screen(String(ctx.get("patient_id", "")))
		"apply_treatment": return _apply_treatment(ctx)
		"run_machine": return _run_machine(ctx)
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

# ---- pause
func _pause_screen() -> Control:
	var parts := _shell(400, 380, "Paused")
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.label("Day %d · %s" % [GameState.day, GameState.time_string()], 15, UIKit.INK_DIM))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Resume", close))
	v.add_child(UIKit.button("Save", func():
		SaveSystem.save_game(SaveSystem.AUTOSAVE)
		EventBus.toast.emit("Saved.", "good")))
	v.add_child(UIKit.button("Tablet", func(): open("tablet", {})))
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
	v.add_child(UIKit.button("Clock in", func():
		GameState.set_flag("tutorial_done", true)
		close()))
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
	var stats_box := UIKit.vbox(3)
	stats_box.add_child(UIKit.row("Shifts worked", str(s.shifts_worked)))
	stats_box.add_child(UIKit.row("Patients admitted", str(s.patients_admitted)))
	stats_box.add_child(UIKit.row("Patients actually cured", str(s.patients_cured), UIKit.GOOD))
	stats_box.add_child(UIKit.row("Bed-days billed", str(s.days_billed), UIKit.MONEY))
	stats_box.add_child(UIKit.row("Complications caused", str(s.complications_caused), UIKit.SUS))
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
