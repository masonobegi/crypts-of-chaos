class_name HUD
extends Control
## The always-on layer. Deliberately sparse: the game's real information channel
## is the world (who is looking at you, what colour a patient has gone), and the
## HUD only carries what you genuinely cannot see.
##
## What used to be here and is not any more: a standing word for how you are
## regarded ("Clean"), an "eyes on you" panel that escalated by tier, and a bar
## that filled while somebody had you out on the street. The redesign does not
## show the player a suspicion reading of any kind — what the ward thinks of you
## is settled in the morning, out of documents, and telling you in advance turns
## a question about paperwork into a meter to watch. The street is gone with it.

var _clock: Label
var _day: Label
var _cash: Label
var _owed: Label
var _tl_bg: PanelContainer
var _objective: Label
var _prompt: Label
var _prompt_sub: Label
var _prompt_panel: PanelContainer
var _subtitle: Label
var _subtitle_panel: PanelContainer
var _toasts: VBoxContainer
var _arrow: Label
var _toast_queue: Array = []
var _toast_gap := 0.0
var _last_toast_text := ""
var _last_toast_count := 1
var _last_toast_label: Label = null
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
	EventBus.objective_changed.connect(_on_objective)
	# The clock and the day come off GameState directly now. They used to arrive
	# as EventBus.clock_tick and day_advanced, both emitted by ShiftSystem, which
	# no longer exists — a HUD listening to a signal nobody sends is a clock that
	# never moves.
	GameState.minute_passed.connect(_on_clock)
	# The ward pays out at eight; without this the number never changed on the
	# one occasion in the day that it does.
	var wd = get_tree().get_first_node_in_group("ward_day")
	if wd != null:
		wd.money_changed.connect(func(_c): _refresh_money())
	GameState.day_started.connect(func(_d): _refresh_static())
	_refresh_static()
	_refresh_money()

func _build() -> void:
	# HUD text sits over everything from a white ceiling to a dark corridor, so
	# each block gets a dark backing rather than relying on the world behind it
	# happening to have contrast. Three-quarters opaque rather than a little
	# under half: at 0.42 a strip lighting fitting behind the money read
	# straight through it and the second line became guesswork.
	# ---- top left: when you are
	_tl_bg = UIKit.panel(Color(0.06, 0.08, 0.10, 0.74), 8)
	UIKit.place(_tl_bg, Control.PRESET_TOP_LEFT, 12, 10, 210, 92)
	add_child(_tl_bg)
	var tl := UIKit.vbox(2)
	UIKit.place(tl, Control.PRESET_TOP_LEFT, 26, 18, 190, 86)
	_day = UIKit.label("Day 1", 20, UIKit.HUD_INK)
	_clock = UIKit.label("8:00 AM", 30, UIKit.HUD_ACCENT)
	tl.add_child(_day)
	tl.add_child(_clock)
	add_child(tl)

	# ---- top right: money
	# THE LABELS GO INSIDE THE PANEL, not on top of a separately positioned one.
	# Two absolutely-placed siblings drawn in whichever order they were added is
	# how the second line ended up behind its own backing plate, half legible.
	# A PanelContainer sizes itself to its child, so the plate is always exactly
	# as big as what is written on it.
	var tr_bg := UIKit.panel(Color(0.06, 0.08, 0.10, 0.74), 8)
	UIKit.place(tr_bg, Control.PRESET_TOP_RIGHT, -320, 10, 308, 80)
	var tr := UIKit.vbox(0)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# What you have, and what tonight looks like from here. The second line is
	# the only reason the first one is interesting: `cash` does not move until
	# eight o'clock, so on its own it is a number that sits still all day.
	_cash = UIKit.label("$0", 26, UIKit.HUD_MONEY, HORIZONTAL_ALIGNMENT_RIGHT)
	_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(_cash)
	_owed = UIKit.label("", 15, UIKit.HUD_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_owed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(_owed)
	tr_bg.add_child(tr)
	add_child(tr_bg)

	# ---- top centre: objective.
	# Inside its own plate, like the other two. It used to be a bare wrapping
	# label in a 90-tall box anchored 16 from the top, which rendered as a line
	# of grey text half off the top of the screen over whatever the ceiling
	# happened to be.
	var tc_bg := UIKit.panel(Color(0.06, 0.08, 0.10, 0.74), 6)
	UIKit.place(tc_bg, Control.PRESET_CENTER_TOP, -250, 14, 500, 34)
	_objective = UIKit.label("", 15, UIKit.HUD_INK, HORIZONTAL_ALIGNMENT_CENTER)
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc_bg.add_child(_objective)
	add_child(tc_bg)

	# ---- crosshair
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_crosshair)
	# See _make_everything_click_through() at the end of _ready(). The crosshair
	# in particular sits exactly where a captured cursor reports its position.
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.55)
	dot.size = Vector2(3, 3)
	dot.position = Vector2(-1.5, -1.5)
	_crosshair.add_child(dot)

	# ---- interaction prompt
	_prompt_panel = UIKit.panel(Color(0.08, 0.10, 0.12, 0.86), 6)
	UIKit.place(_prompt_panel, Control.PRESET_CENTER, -200, 44, 400, 62)
	var pv := UIKit.vbox(2)
	_prompt = UIKit.label("", 17, UIKit.HUD_INK, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_sub = UIKit.label("", 13, UIKit.HUD_DIM, HORIZONTAL_ALIGNMENT_CENTER, true)
	pv.add_child(_prompt)
	pv.add_child(_prompt_sub)
	_prompt_panel.add_child(pv)
	_prompt_panel.visible = false
	add_child(_prompt_panel)

	# ---- subtitles
	_subtitle_panel = UIKit.panel(Color(0.05, 0.06, 0.08, 0.80), 6)
	UIKit.place(_subtitle_panel, Control.PRESET_CENTER_BOTTOM, -330, -132, 660, 66)
	_subtitle = UIKit.label("", 17, UIKit.HUD_INK, HORIZONTAL_ALIGNMENT_CENTER, true)
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
	var help := UIKit.label("[E] use   [LMB] grab   [RMB] throw   [Esc] pause",
		12, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	help.add_theme_constant_override("shadow_offset_y", 1)
	UIKit.place(help, Control.PRESET_BOTTOM_RIGHT, -478, -32, 460, 22)
	add_child(help)

	# ---- off-screen objective arrow
	_arrow = UIKit.label("", 26, Color(0.42, 0.90, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	_arrow.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_arrow.add_theme_constant_override("shadow_offset_y", 2)
	_arrow.visible = false
	add_child(_arrow)

	_make_everything_click_through()

## THE HUD MUST NOT EAT MOUSE INPUT. This is the fix for the worst bug in the
## first playtest: "I was just walking forward but couldn't look left or right."
##
## Setting mouse_filter = IGNORE on the HUD root does NOT propagate to its
## children, and almost every Control in Godot defaults to STOP — PanelContainer,
## ColorRect, Label, Control itself. While the mouse is CAPTURED, motion events
## still carry a screen position, and any STOP control under that position
## consumes them before `_unhandled_input` ever runs. Player look lives in
## `_unhandled_input`.
##
## The crosshair is the killer: a bare Control anchored to PRESET_CENTER, with a
## ColorRect inside it, sitting exactly where a captured cursor reports itself.
## It swallowed every look event in the game.
##
## Nothing in this HUD is interactive — it is entirely readout — so the whole
## subtree is forced to IGNORE rather than each new panel having to remember.
## Add a clickable HUD element one day and it will need exempting here, which is
## a much better failure mode than silently disabling the mouse.
##
## No harness could have found this: the scripted player presses actions through
## Input.parse_input_event and never generates mouse motion at all. It took a
## person with a mouse about ninety seconds.
func _make_everything_click_through() -> void:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		for c in n.get_children():
			stack.append(c)

func _process(delta: float) -> void:
	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		if _subtitle_timer <= 0.0:
			_subtitle_panel.visible = false
	_drain_toasts(delta)
	_refresh_objective_arrow()

## An arrow at the edge of the screen when the objective is behind you.
##
## A world marker solves "where is it" only while you are facing roughly the
## right way. The rest of the time — which, in a sixty-two metre corridor with
## rooms off both sides, is most of the time — it is invisible and the player is
## exactly as lost as before. This pins it to the edge of the screen instead.
func _refresh_objective_arrow() -> void:
	if _arrow == null:
		return
	var marker = get_tree().get_first_node_in_group("objective_marker")
	var cam: Camera3D = null
	var p = get_tree().get_first_node_in_group("player")
	if p != null:
		cam = p.camera
	if marker == null or cam == null or not marker.target.is_finite():
		_arrow.visible = false
		return

	var target: Vector3 = marker.target
	var behind: bool = cam.is_position_behind(target)
	var screen: Vector2 = cam.unproject_position(target)
	var rect: Vector2 = get_viewport_rect().size
	var margin := 46.0
	var on_screen: bool = not behind \
		and screen.x > margin and screen.x < rect.x - margin \
		and screen.y > margin and screen.y < rect.y - margin
	if on_screen:
		_arrow.visible = false
		return

	# unproject_position mirrors what is behind the camera, so a target directly
	# over your shoulder reads as being in front and on the wrong side. Flip it.
	if behind:
		screen = rect - screen
	var centre: Vector2 = rect * 0.5
	var dir: Vector2 = (screen - centre)
	if dir.length() < 1.0:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	var edge: Vector2 = centre + dir * (minf(rect.x, rect.y) * 0.5 - margin)
	_arrow.position = edge - Vector2(14, 18)
	_arrow.rotation = dir.angle() + PI * 0.5
	_arrow.text = "▲"
	_arrow.visible = true

func _refresh_static() -> void:
	_day.text = "Day %d" % GameState.day

func _on_clock(_m: int) -> void:
	_clock.text = GameState.time_string()
	_refresh_money()

## What you have. The ward day owns the figure while a day is being played; the
## saved value in GameState is what is left of it between them.
func _refresh_money() -> void:
	var w = get_tree().get_first_node_in_group("ward_day")
	var cash: int = int(w.cash) if w != null else GameState.cash
	_cash.text = UIKit.money_str(cash)
	_cash.add_theme_color_override("font_color",
		UIKit.HUD_MONEY if cash >= 0 else UIKit.HUD_BAD)
	# WHAT TONIGHT LOOKS LIKE FROM HERE. `cash` does not move until eight
	# o'clock, so the money readout sat at nine hundred all day and told the
	# player nothing while they made the only decisions that change it. The
	# second line is the whole tension of the day in six words.
	if w == null or w.ended:
		_owed.visible = false
		return
	var p: Dictionary = w.projected()
	var total: int = int(p["total"])
	_owed.visible = true
	_owed.text = "%s against %s owed" % [
		UIKit.money_str(total), UIKit.money_str(w.debt_tonight)]
	_owed.add_theme_color_override("font_color",
		UIKit.HUD_MONEY if total >= w.debt_tonight else UIKit.HUD_BAD)

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
	# Off means off. Somebody who turned subtitles off did not mean "except
	# for the barks", which are most of what this panel ever shows.
	if not bool(Settings.get_value("subtitles")):
		return
	_subtitle.text = "%s: \"%s\"" % [speaker, text]
	_subtitle_panel.visible = true
	_subtitle_timer = seconds

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
	var colour := UIKit.HUD_INK
	# There is no "suspicion" tint any more. A purple toast was a suspicion
	# readout with a shorter life than a panel, and it is the one thing this
	# layer is not allowed to tell you.
	match kind:
		"good": colour = UIKit.HUD_GOOD
		"bad": colour = UIKit.HUD_BAD
		"money": colour = UIKit.HUD_MONEY
	var p := UIKit.panel(Color(0.08, 0.10, 0.12, 0.88), 5, 0)
	var l := UIKit.label(text, 14, colour, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.custom_minimum_size.x = 370
	p.add_child(l)
	_toasts.add_child(p)
	# Created long after _ready, so it misses the sweep that makes the rest of
	# the HUD click-through — and a toast panel is 410px wide at the bottom left.
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
