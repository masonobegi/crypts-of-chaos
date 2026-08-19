class_name HUD
extends Control
## The always-on layer. Deliberately sparse: the game's real information channel
## is the world (who is looking at you, what colour a patient has gone), and the
## HUD only carries what you genuinely cannot see.

var _clock: Label
var _day: Label
var _sanction: Label
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
var _crosshair: Control
var _subtitle_timer := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.interact_prompt.connect(_on_prompt)
	EventBus.interact_prompt_cleared.connect(_on_prompt_cleared)
	EventBus.toast.connect(_on_toast)
	EventBus.subtitle.connect(_on_subtitle)
	EventBus.money_changed.connect(_on_money)
	EventBus.clock_tick.connect(_on_clock)
	EventBus.objective_changed.connect(_on_objective)
	EventBus.sanction_applied.connect(func(_l, _r): _refresh_static())
	EventBus.day_advanced.connect(func(_d): _refresh_static())
	_refresh_static()
	_on_money(GameState.personal_money, GameState.hospital_money)

func _build() -> void:
	# ---- top left: when you are
	var tl := UIKit.vbox(2)
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.position = Vector2(18, 14)
	_day = UIKit.label("Day 1", 20, UIKit.INK)
	_clock = UIKit.label("8:00 AM", 30, UIKit.ACCENT)
	_sanction = UIKit.label("Clean", 13, UIKit.INK_DIM)
	tl.add_child(_day)
	tl.add_child(_clock)
	tl.add_child(_sanction)
	add_child(tl)

	# ---- top right: money
	var tr := UIKit.vbox(2)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-230, 14)
	tr.custom_minimum_size.x = 212
	_personal = UIKit.label("$0", 26, UIKit.MONEY, HORIZONTAL_ALIGNMENT_RIGHT)
	_hospital = UIKit.label("Hospital $0", 14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_census = UIKit.label("0 admitted", 14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	for n in [_personal, _hospital, _census]:
		n.custom_minimum_size.x = 212
		tr.add_child(n)
	add_child(tr)

	# ---- top centre: objective, and the single most important tell in the game
	var tc := UIKit.vbox(6)
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-190, 16)
	tc.custom_minimum_size.x = 380
	_objective = UIKit.label("", 15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_objective.custom_minimum_size.x = 380
	tc.add_child(_objective)

	_watch_panel = UIKit.panel(Color(0.35, 0.12, 0.12, 0.85), 6, 1, UIKit.BAD)
	_watch = UIKit.label("", 15, Color(1, 0.85, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
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
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_panel.position = Vector2(-170, 40)
	_prompt_panel.custom_minimum_size = Vector2(340, 0)
	var pv := UIKit.vbox(2)
	_prompt = UIKit.label("", 17, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_sub = UIKit.label("", 13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	pv.add_child(_prompt)
	pv.add_child(_prompt_sub)
	_prompt_panel.add_child(pv)
	_prompt_panel.visible = false
	add_child(_prompt_panel)

	# ---- subtitles
	_subtitle_panel = UIKit.panel(Color(0.05, 0.06, 0.08, 0.80), 6)
	_subtitle_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_panel.position = Vector2(-320, -120)
	_subtitle_panel.custom_minimum_size = Vector2(640, 0)
	_subtitle = UIKit.label("", 17, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.custom_minimum_size.x = 612
	_subtitle_panel.add_child(_subtitle)
	_subtitle_panel.visible = false
	add_child(_subtitle_panel)

	# ---- toasts
	_toasts = UIKit.vbox(6)
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toasts.position = Vector2(18, -260)
	_toasts.custom_minimum_size = Vector2(400, 240)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	add_child(_toasts)

	# ---- controls reminder
	var help := UIKit.label("[E] use   [LMB] grab   [RMB] throw   [Q] tablet   [Esc] pause",
		12, Color(1, 1, 1, 0.28), HORIZONTAL_ALIGNMENT_RIGHT)
	help.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	help.position = Vector2(-460, -28)
	help.custom_minimum_size.x = 440
	add_child(help)

func _process(delta: float) -> void:
	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		if _subtitle_timer <= 0.0:
			_subtitle_panel.visible = false
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
	_watch.add_theme_color_override("font_color", UIKit.tier_color(maxi(worst, 1)))

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

func _on_toast(text: String, kind: String) -> void:
	var colour := UIKit.INK
	match kind:
		"good": colour = UIKit.GOOD
		"bad": colour = UIKit.BAD
		"money": colour = UIKit.MONEY
		"suspicion": colour = UIKit.SUS
	var p := UIKit.panel(Color(0.08, 0.10, 0.12, 0.88), 5, 0)
	var l := UIKit.label(text, 14, colour)
	l.custom_minimum_size.x = 370
	p.add_child(l)
	_toasts.add_child(p)
	if kind == "money":
		AudioMgr.play("money", -14.0)
	elif kind == "bad":
		AudioMgr.play("error", -14.0)
	while _toasts.get_child_count() > 6:
		_toasts.get_child(0).free()
	# Guard every await: the HUD can be torn down while a toast is still
	# counting down (scene change, or a headless harness rebuilding the world),
	# and resuming on a freed node throws.
	if not is_inside_tree():
		return
	await get_tree().create_timer(7.0).timeout
	if not is_instance_valid(p) or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	await tw.finished
	if is_instance_valid(p):
		p.queue_free()

func set_crosshair_visible(v: bool) -> void:
	_crosshair.visible = v
