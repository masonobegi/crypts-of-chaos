class_name HUD
extends Control
## The always-on layer. Deliberately sparse: the game's real information channel
## is the world (who is looking at you, what colour a patient has gone), and the
## HUD only carries what you genuinely cannot see.

var _clock: Label
var _day: Label
var _sanction: Label
var _left: Label
var _next_appt: Label
var _tl_bg: PanelContainer
var _personal: Label
var _hospital: Label
var _census: Label
var _objective: Label
var _prompt: Label
var _prompt_sub: Label
var _prompt_panel: PanelContainer
var _watch: Label
var _watch_panel: PanelContainer
var _subtitle: Label
var _subtitle_panel: PanelContainer
var _toasts: VBoxContainer
var _toast_queue: Array = []
var _toast_gap := 0.0
var _last_toast_text := ""
var _last_toast_count := 1
var _last_toast_label: Label = null
var _ticker: VBoxContainer
var _crosshair: Control
var _subtitle_timer := 0.0

func _ready() -> void:
	# ...and_offsets_, not set_anchors_preset(). The latter sets anchors only and
	# leaves a freshly created Control at zero size, so every child anchored to
	# the right or bottom edge resolves against a zero-width parent and lands
	# off-screen. That is exactly what happened to the money readout.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.interact_prompt.connect(_on_prompt)
	EventBus.interact_prompt_cleared.connect(_on_prompt_cleared)
	EventBus.toast.connect(_on_toast)
	EventBus.subtitle.connect(_on_subtitle)
	EventBus.money_changed.connect(_on_money)
	EventBus.transaction.connect(_on_transaction)
	EventBus.clock_tick.connect(_on_clock)
	EventBus.objective_changed.connect(_on_objective)
	EventBus.sanction_applied.connect(func(_l, _r): _refresh_static())
	EventBus.day_advanced.connect(func(_d): _refresh_static())
	# The deadline block otherwise stays blank until the first minute ticks over
	# — a second and a half of the shift having no visible end, at exactly the
	# moment the player is looking for one.
	EventBus.shift_started.connect(func(_d): _refresh_deadline())
	_refresh_static()
	_on_money(GameState.personal_money, GameState.hospital_money)

func _build() -> void:
	# HUD text sits over everything from a white ceiling to a dark corridor, so
	# each block gets a soft dark backing rather than relying on the world
	# behind it happening to have contrast.
	# ---- top left: when you are
	_tl_bg = UIKit.panel(Color(0.06, 0.08, 0.10, 0.42), 8)
	UIKit.place(_tl_bg, Control.PRESET_TOP_LEFT, 12, 10, 300, 152)
	add_child(_tl_bg)
	var tl := UIKit.vbox(2)
	UIKit.place(tl, Control.PRESET_TOP_LEFT, 26, 18, 280, 146)
	_day = UIKit.label("Day 1", 20, UIKit.INK)
	_clock = UIKit.label("8:00 AM", 30, UIKit.ACCENT)
	# A shift that ends at an hour you were never told is not a deadline, it is
	# a surprise. Everything the player is deciding — whether there is time to
	# do this now, whether the paperwork can wait — is a question about this
	# number, and it was not on screen anywhere.
	_left = UIKit.label("", 13, Color(0.78, 0.82, 0.84))
	_sanction = UIKit.label("Clean", 13, Color(0.78, 0.82, 0.84))
	# The next appointment lives here, with the other two answers to "when".
	# It used to sit top-centre, where NPC speech labels float over the heads of
	# whoever is standing in front of you — a rendered play run caught a nurse's
	# "You know I can see you, right?" printed straight through the countdown.
	_next_appt = UIKit.label("", 13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	_next_appt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_child(_day)
	tl.add_child(_clock)
	tl.add_child(_left)
	tl.add_child(_next_appt)
	tl.add_child(_sanction)
	add_child(tl)

	# ---- top right: money
	var tr_bg := UIKit.panel(Color(0.06, 0.08, 0.10, 0.42), 8)
	UIKit.place(tr_bg, Control.PRESET_TOP_RIGHT, -256, 10, 244, 104)
	add_child(tr_bg)
	var tr := UIKit.vbox(2)
	UIKit.place(tr, Control.PRESET_TOP_RIGHT, -248, 18, 228, 100)
	_ticker = UIKit.vbox(1)
	UIKit.place(_ticker, Control.PRESET_TOP_RIGHT, -330, 118, 310, 200)
	_ticker.alignment = BoxContainer.ALIGNMENT_BEGIN
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ticker)

	_personal = UIKit.label("$0", 26, UIKit.MONEY, HORIZONTAL_ALIGNMENT_RIGHT)
	_hospital = UIKit.label("Hospital $0", 14, Color(0.78, 0.82, 0.84), HORIZONTAL_ALIGNMENT_RIGHT)
	_census = UIKit.label("0 admitted", 14, Color(0.78, 0.82, 0.84), HORIZONTAL_ALIGNMENT_RIGHT)
	for n in [_personal, _hospital, _census]:
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.add_child(n)
	add_child(tr)

	# ---- top centre: objective, and the single most important tell in the game
	var tc := UIKit.vbox(6)
	UIKit.place(tc, Control.PRESET_CENTER_TOP, -230, 16, 460, 90)
	_objective = UIKit.label("", 15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER, true)
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.add_child(_objective)


	# Neutral by default and restyled per tier in _refresh_watchers. It used to
	# be hardcoded alarm-red, and it shows for anybody with line of sight
	# including the patient lying in the bed you are treating — so it was on
	# almost permanently, in the colour that means DANGER, and read as wallpaper
	# by the time it actually mattered.
	_watch_panel = UIKit.panel(Color(0.10, 0.13, 0.16, 0.72), 6, 1, Color(0.35, 0.42, 0.48))
	_watch = UIKit.label("", 15, Color(0.86, 0.90, 0.92), HORIZONTAL_ALIGNMENT_CENTER, true)
	_watch_panel.add_child(_watch)
	_watch_panel.visible = false
	tc.add_child(_watch_panel)
	add_child(tc)

	# ---- crosshair
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_crosshair)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.55)
	dot.size = Vector2(3, 3)
	dot.position = Vector2(-1.5, -1.5)
	_crosshair.add_child(dot)

	# ---- interaction prompt
	_prompt_panel = UIKit.panel(Color(0.08, 0.10, 0.12, 0.86), 6)
	UIKit.place(_prompt_panel, Control.PRESET_CENTER, -200, 44, 400, 62)
	var pv := UIKit.vbox(2)
	_prompt = UIKit.label("", 17, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_sub = UIKit.label("", 13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER, true)
	pv.add_child(_prompt)
	pv.add_child(_prompt_sub)
	_prompt_panel.add_child(pv)
	_prompt_panel.visible = false
	add_child(_prompt_panel)

	# ---- subtitles
	_subtitle_panel = UIKit.panel(Color(0.05, 0.06, 0.08, 0.80), 6)
	UIKit.place(_subtitle_panel, Control.PRESET_CENTER_BOTTOM, -330, -132, 660, 66)
	_subtitle = UIKit.label("", 17, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle_panel.add_child(_subtitle)
	_subtitle_panel.visible = false
	add_child(_subtitle_panel)

	# ---- toasts
	_toasts = UIKit.vbox(6)
	UIKit.place(_toasts, Control.PRESET_BOTTOM_LEFT, 18, -286, 410, 268)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	add_child(_toasts)

	# ---- controls reminder
	var help := UIKit.label("[E] use   [LMB] grab   [RMB] throw   [Q] tablet   [Esc] pause",
		12, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	help.add_theme_constant_override("shadow_offset_y", 1)
	UIKit.place(help, Control.PRESET_BOTTOM_RIGHT, -478, -32, 460, 22)
	add_child(help)

func _process(delta: float) -> void:
	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		if _subtitle_timer <= 0.0:
			_subtitle_panel.visible = false
	_drain_toasts(delta)
	_refresh_watchers()

## "Eyes on you" — the readable version of the whole perception system. It never
## tells you what they think, only that they can currently see you.
func _refresh_watchers() -> void:
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus == null:
		return
	var list: Array = sus.watchers()
	if list.is_empty():
		_watch_panel.visible = false
		return
	var names: Array[String] = []
	var worst := 0
	for b in list:
		names.append(b.display)
		if b.mind:
			worst = maxi(worst, b.mind.tier(GameState.career_minutes, GameState.active_covers))
	_watch_panel.visible = true
	var verb := "can see you"
	if worst >= 3:
		verb = "is watching you"
	elif worst >= 2:
		verb = "is paying attention"
	_watch.text = "%s %s" % [", ".join(names), verb]
	# Escalates with the worst tier present. At tier 0 — somebody who simply has
	# eyes and no opinion — it stays a quiet grey note, so the red means
	# something when it arrives.
	var tint := UIKit.tier_color(worst) if worst >= 1 else Color(0.80, 0.86, 0.88)
	_watch.add_theme_color_override("font_color", tint)
	var bg: Color = Color(0.10, 0.13, 0.16, 0.72)
	if worst >= 3:
		bg = Color(0.38, 0.11, 0.11, 0.88)
	elif worst >= 2:
		bg = Color(0.32, 0.20, 0.09, 0.84)
	elif worst >= 1:
		bg = Color(0.24, 0.22, 0.10, 0.80)
	_watch_panel.add_theme_stylebox_override("panel",
		UIKit.stylebox(bg, 6, 1, tint))

func _refresh_static() -> void:
	_day.text = "Day %d" % GameState.day
	_sanction.text = GameState.SANCTIONS[GameState.sanction_level]
	_sanction.add_theme_color_override("font_color",
		UIKit.INK_DIM if GameState.sanction_level == 0 else UIKit.tier_color(
			clampi(GameState.sanction_level / 2, 1, 4)))

func _on_clock(_m: int) -> void:
	_clock.text = GameState.time_string()
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps:
		_census.text = "%d admitted · %s/day" % [ps.active_count(),
			UIKit.money_str(ps.total_daily_revenue())]
	_refresh_deadline()

## The two clocks that actually govern a decision: how long is left of the
## shift, and how long until somebody is expecting you somewhere.
func _refresh_deadline() -> void:
	if GameState.phase != GameState.Phase.SHIFT:
		_left.text = ""
		_next_appt.text = ""
		_fit_clock_panel()
		return
	var mins := GameState.shift_minutes_remaining()
	var end_hour := (GameState.shift_start_hour() + GameState.shift_hours()) % 24
	_left.text = "%s left · ends %s" % [UIKit.span_str(mins),
		GameState.hour_string(end_hour)]
	_left.add_theme_color_override("font_color",
		UIKit.BAD if mins <= 30 else (UIKit.WARN if mins <= 60 else UIKit.INK_DIM))

	var appts = get_tree().get_first_node_in_group("appointment_system")
	if appts == null:
		_next_appt.text = ""
		_fit_clock_panel()
		return
	var e: Dictionary = appts.next_due()
	if e.is_empty():
		_next_appt.text = "Nothing else booked."
		_next_appt.add_theme_color_override("font_color", UIKit.INK_DIM)
		_fit_clock_panel()
		return
	var until: int = appts.minutes_until(int(e["hour"]))
	var label := String(AppointmentSystem.LABELS.get(String(e["kind"]), "Appointment"))
	if until > 0:
		_next_appt.text = "%s — %s in %s" % [label, String(e["name"]), UIKit.span_str(until)]
		_next_appt.add_theme_color_override("font_color",
			UIKit.WARN if until <= 30 else UIKit.INK_DIM)
	else:
		# Three hours late is a no-show. Say how much of that is left rather
		# than only saying "late", which tells you nothing about whether to run.
		var grace := 180 + until
		_next_appt.text = "%s — %s is waiting (%s)" % [label, String(e["name"]),
			UIKit.span_str(grace)]
		_next_appt.add_theme_color_override("font_color",
			UIKit.BAD if grace <= 60 else UIKit.WARN)
	_fit_clock_panel()

## An empty label still takes a line, and the backing panel is a fixed rectangle,
## so before the shift starts the clock block was a tall box with a hole in it.
func _fit_clock_panel() -> void:
	_left.visible = _left.text != ""
	_next_appt.visible = _next_appt.text != ""
	var lines := 3 + (1 if _left.visible else 0) + (1 if _next_appt.visible else 0)
	_tl_bg.size.y = 30.0 + float(lines) * 24.0
	_tl_bg.size.x = 300.0 if _next_appt.visible else 210.0

func _on_money(personal: int, hospital: int) -> void:
	_personal.text = UIKit.money_str(personal)
	_personal.add_theme_color_override("font_color",
		UIKit.MONEY if personal >= 0 else UIKit.BAD)
	_hospital.text = "Hospital %s" % UIKit.money_str(hospital)

func _on_objective(text: String) -> void:
	_objective.text = text

func _on_prompt(text: String, sub: String) -> void:
	_prompt.text = text
	_prompt_sub.text = sub
	_prompt_sub.visible = sub != ""
	_prompt_panel.visible = true

func _on_prompt_cleared() -> void:
	_prompt_panel.visible = false

func _on_subtitle(speaker: String, text: String, seconds: float) -> void:
	_subtitle.text = "%s: \"%s\"" % [speaker, text]
	_subtitle_panel.visible = true
	_subtitle_timer = seconds

## Every movement of money, as it happens, next to the figure it changed.
##
## `EventBus.transaction` was emitted from both halves of GameState and
## connected to nothing at all. Five debts totalling $695 a day drained the
## starting $820 in silence before the player had read either number, and their
## own balance then sat still for twelve real minutes — so the one thing the
## entire game is about, money arriving because somebody stayed another night,
## was never once visible arriving.
func _on_transaction(label: String, amount: int, is_hospital: bool) -> void:
	if amount == 0:
		return
	var l := UIKit.label("%s%s  %s" % ["+" if amount > 0 else "−",
		UIKit.money_str(absi(amount)), label],
		15 if not is_hospital else 13,
		(UIKit.MONEY if amount > 0 else UIKit.BAD) if not is_hospital
			else Color(0.62, 0.72, 0.68), HORIZONTAL_ALIGNMENT_RIGHT)
	_ticker.add_child(l)
	if not is_hospital:
		AudioMgr.play("money" if amount > 0 else "beep_low", -17.0)
	while _ticker.get_child_count() > 7:
		_ticker.get_child(0).free()
	if not is_inside_tree():
		return
	await get_tree().create_timer(4.5).timeout
	if not is_instance_valid(l) or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	await tw.finished
	if is_instance_valid(l):
		l.queue_free()

## Toasts arrive in bursts — five patients handed over at 8:00, a run of
## machine alarms, an argument's worth of complaints — and six of them landing
## in the same frame is a wall of text that reads as decoration. They queue
## instead: at most three on screen, one released every half second, and an
## identical line repeated inside the window becomes a count on the line that is
## already there rather than a second copy of it.
func _on_toast(text: String, kind: String) -> void:
	if _toast_queue.size() >= 14:
		return                    # something is spamming; do not build a backlog
	_toast_queue.append({"text": text, "kind": kind})

func _drain_toasts(delta: float) -> void:
	_toast_gap = maxf(0.0, _toast_gap - delta)
	if _toast_queue.is_empty() or _toast_gap > 0.0:
		return
	var next: Dictionary = _toast_queue.pop_front()
	# A repeat of the line already at the bottom is a tally, not a new toast.
	if _last_toast_text == String(next["text"]) and is_instance_valid(_last_toast_label):
		_last_toast_count += 1
		_last_toast_label.text = "%s  ×%d" % [_last_toast_text, _last_toast_count]
		_toast_gap = 0.2
		return
	_last_toast_text = String(next["text"])
	_last_toast_count = 1
	_toast_gap = 0.5
	_show_toast(String(next["text"]), String(next["kind"]))

func _show_toast(text: String, kind: String) -> void:
	var colour := UIKit.INK
	match kind:
		"good": colour = UIKit.GOOD
		"bad": colour = UIKit.BAD
		"money": colour = UIKit.MONEY
		"suspicion": colour = UIKit.SUS
	var p := UIKit.panel(Color(0.08, 0.10, 0.12, 0.88), 5, 0)
	var l := UIKit.label(text, 14, colour, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.custom_minimum_size.x = 370
	p.add_child(l)
	_toasts.add_child(p)
	_last_toast_label = l
	if kind == "money":
		AudioMgr.play("money", -14.0)
	elif kind == "bad":
		AudioMgr.play("error", -14.0)
	while _toasts.get_child_count() > 3:
		_toasts.get_child(0).free()
	# Guard every await: the HUD can be torn down while a toast is still
	# counting down (scene change, or a headless harness rebuilding the world),
	# and resuming on a freed node throws.
	if not is_inside_tree():
		return
	await get_tree().create_timer(6.0).timeout
	if not is_instance_valid(p) or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	await tw.finished
	if is_instance_valid(p):
		p.queue_free()

func set_crosshair_visible(v: bool) -> void:
	_crosshair.visible = v
