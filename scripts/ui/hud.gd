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
var _cash_label: Label
var _owed: Label
var _tl_bg: PanelContainer
var _objective: Label
var _prompt: Label
var _prompt_sub: Label
var _prompt_panel: PanelContainer
var _subtitle: Label
var _subtitle_panel: PanelContainer
## The bottom-right controls reminder, kept so a modal can hide it.
var _help: Label = null
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
	add_to_group("hud")
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
	# THE CLOCK TOO, not just the day number. The time label only repaints on
	# `minute_passed`, and the clock is stopped between days — so at the moment a
	# new shift starts the corner of the screen still reads whatever last night
	# ended at, until the first minute ticks. A screenshot of the third ward
	# caught the HUD saying 7:13 PM over a patient card correctly saying 08:00.
	GameState.day_started.connect(func(_d):
		_refresh_static()
		_on_clock(GameState.minute_of_day))
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
	# 96, not 80: the caption above the figure is a third row.
	UIKit.place(tr_bg, Control.PRESET_TOP_RIGHT, -320, 10, 308, 96)
	var tr := UIKit.vbox(0)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# What you have, and what tonight looks like from here. The second line is
	# the only reason the first one is interesting: `cash` does not move until
	# eight o'clock, so on its own it is a number that sits still all day.
	# A NOUN ON THE BIGGEST NUMBER IN THE GAME.
	#
	# It had none. The morning card says "In your account $900", the player
	# presses Start the round, and the corner of the screen says $1,900 in big
	# green type with nothing attached to it — two different money figures
	# thirty seconds apart, in a game whose entire score is one number. And the
	# figure goes DOWN when you hold a patient, which without a caption reads as
	# a penalty rather than as a bed not being sold.
	_cash_label = UIKit.label("IF YOU SIGNED OFF NOW", 11, UIKit.HUD_INK,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(_cash_label)
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
	# A DARK RING ROUND A LIGHT DOT. A 3px white dot at 55% alpha is invisible
	# against this building: the upper walls are cream (0.87,0.83,0.71) and the
	# ceiling is near-white, which is most of what you look at while walking. A
	# first-person game whose crosshair disappears for half the screen is one
	# people describe as "hard to aim at things" without knowing why.
	var halo := ColorRect.new()
	halo.color = Color(0.05, 0.06, 0.08, 0.55)
	halo.size = Vector2(7, 7)
	halo.position = Vector2(-3.5, -3.5)
	_crosshair.add_child(halo)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.92)
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
	# THE KEYS THEY ACTUALLY BOUND. Rebinding is a headline setting with a whole
	# screen behind it, and this line was hardcoded to E/LMB/RMB — so a player who
	# moved "use" to F was told to press E for the rest of the game, by the HUD,
	# permanently.
	var help := UIKit.label(_controls_line(),
		12, Color(1, 1, 1, 0.62), HORIZONTAL_ALIGNMENT_RIGHT)
	_help = help
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	help.add_theme_constant_override("shadow_offset_y", 1)
	UIKit.place(help, Control.PRESET_BOTTOM_RIGHT, -478, -32, 460, 22)
	add_child(help)
	# Follow a rebind while the game is running, rather than until next launch.
	Settings.changed.connect(func(_k):
		if is_instance_valid(help):
			help.text = _controls_line())
	# ...AND A PAD BEING PLUGGED IN MID-GAME. The line is the only place the
	# game tells you which button does what while you are playing, and it said
	# "[E] use" to somebody holding a controller. Godot announces the joypad, so
	# there is no reason to make them go and look at the Controls screen.
	Input.joy_connection_changed.connect(func(_device, _connected):
		if is_instance_valid(help):
			help.text = _controls_line())

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
	# TO THE EDGE OF THE SCREEN, which is what the two comments above this both
	# claim it does. A circle inscribed in the SHORTER axis has a radius of 404px
	# on 1600x900, so a marker off to the left or right put its arrow at x=396 or
	# x=1204 — four hundred pixels inside the frame, floating in mid-air over a
	# wall or a curtain. It is a pale teal triangle on a ward with a teal dado,
	# and it reads as a stray placeholder mesh rather than as a pointer. Scaled
	# to the rectangle instead: whichever axis the ray leaves through decides the
	# distance, so it lands ON the border on any aspect ratio.
	var half: Vector2 = centre - Vector2(margin, margin)
	var tx: float = half.x / maxf(absf(dir.x), 0.0001)
	var ty: float = half.y / maxf(absf(dir.y), 0.0001)
	var edge: Vector2 = centre + dir * minf(tx, ty)
	_arrow.position = edge - Vector2(14, 18)
	_arrow.rotation = dir.angle() + PI * 0.5
	_arrow.text = "▲"
	_arrow.visible = true

## The bottom-right reminder, built from the InputMap rather than typed, so it
## follows a rebind. Rebuilt on `Settings.bindings_changed` for the same reason.
func _controls_line() -> String:
	var bits: Array = []
	for pair in [["interact", "use"], ["grab", "grab"], ["throw", "throw"],
			["pause", "pause"]]:
		bits.append("[%s] %s" % [_key_for(String(pair[0])), String(pair[1])])
	return "   ".join(bits)

## WHAT IS IN THEIR HANDS. `Settings.prompt_label` prefers the pad when one is
## plugged in, because somebody holding a controller is not looking at the
## keyboard — and it is the same answer the carry prompt in `Interactor` gives,
## which is the point of it living in one place.
static func _key_for(action: String) -> String:
	return Settings.prompt_label(action)

func _refresh_static() -> void:
	_day.text = "Day %d" % GameState.day

func _on_clock(_m: int) -> void:
	_clock.text = GameState.time_string()
	# THE DAY COMES WITH THE CLOCK. `GameState.day` is a plain int, and the only
	# thing that ever repainted this label was `start_day()` — so every path that
	# sets the day directly left the corner of the screen a day behind. It has
	# already happened once for real (the second ward opened saying Day 1) and
	# again in the screenshot harness, where the review card said Day 1 under a
	# HUD still reading Day 3. Repainting a two-character label on a signal that
	# fires once a minute costs nothing and makes the whole class impossible.
	_refresh_static()
	_refresh_money()

## What you have. The ward day owns the figure while a day is being played; the
## saved value in GameState is what is left of it between them.
func _refresh_money() -> void:
	var w = get_tree().get_first_node_in_group("ward_day")
	# WHAT TONIGHT IS WORTH, NOT WHAT IS IN YOUR POCKET.
	#
	# Since the debt got a term, Vinnie takes everything at eight — so `cash`
	# reads $900 all day and $0 the moment the day ends, which is a number that
	# never moves and then means nothing. What the player is actually deciding
	# about is what this shift will hand over, against how much of the whole
	# thing is left.
	var tonight: int = int(w.projected()["total"]) if w != null and not w.ended \
		else (int(w.end_day().get("paid", 0)) if w != null else GameState.cash)
	_cash.text = UIKit.money_str(tonight)
	_cash.add_theme_color_override("font_color", UIKit.HUD_MONEY)
	# WHAT TONIGHT LOOKS LIKE FROM HERE. `cash` does not move until eight
	# o'clock, so the money readout sat at nine hundred all day and told the
	# player nothing while they made the only decisions that change it. The
	# second line is the whole tension of the day in six words.
	_owed.visible = true
	if w == null:
		_owed.text = ""
		return
	var left: int = GameState.debt_remaining()
	if w.ended:
		# The caption has to follow the number. Once the shift is over this is
		# not a projection any more, it is what he took.
		_cash_label.text = "VINNIE TOOK"
		_owed.text = "handed over  ·  %s still owed" % UIKit.money_str(left)
		_owed.add_theme_color_override("font_color",
			UIKit.HUD_MONEY if left <= 0 else UIKit.HUD_INK)
		return
	_cash_label.text = "IF YOU SIGNED OFF NOW"
	# Tonight's number and the whole thing, because the whole thing is the game.
	_owed.text = "he wants %s  ·  %s to go" % [
		UIKit.money_str(w.debt_tonight), UIKit.money_str(left)]
	_owed.add_theme_color_override("font_color",
		UIKit.HUD_MONEY if tonight >= w.debt_tonight else UIKit.HUD_BAD)

func _on_objective(text: String) -> void:
	_objective.text = text

func _on_prompt(text: String, sub: String) -> void:
	# NOT BEHIND A CARD. The patient card deliberately does not pause the world,
	# so the interactor keeps raycasting while you read it and keeps emitting the
	# bedside prompt for the person you are already looking at a card about — a
	# crosshair label with no crosshair under it, next to a form that says the
	# same thing at greater length.
	if _modal_open:
		return
	_prompt.text = text
	_prompt_sub.text = sub
	_prompt_sub.visible = sub != ""
	_prompt_panel.visible = true

func _on_prompt_cleared() -> void:
	_prompt_panel.visible = false

## A CARD IS NOT A THING YOU READ PAST. The subtitle panel is centre-bottom and
## 660 wide; every modal screen is drawn on a layer above it and covers the right
## half, so a tannoy line that landed a second before the end-of-shift card
## opened sat there reading `Would whoever keeps setting the` ... `stop."` for
## the rest of its timer. Found by looking at the screenshot — the HUD is paused
## with the world, so its own timer cannot clear it either, and it would have
## stayed clipped until the player closed the card.
var _modal_open := false

# `drop_subtitle()` used to live here. It had no callers anywhere in the
# project and its whole body was `set_modal(true)` — a latch nothing else would
# ever have cleared. Harmless while `_modal_open` only suppressed subtitles;
# now that it also holds the toast queue, one stray call would have silenced
# every toast for the rest of the shift.

## A CARD IS UP FOR AS LONG AS IT IS UP, not just for the instant it opens.
##
## The first version of this cleared the subtitle when a screen opened, which
## fixed the line that was ALREADY on screen and nothing else. Most screens do
## not pause the world — the ward clock keeps running behind the chart, which is
## the whole point of the chart costing you twelve minutes — so the tannoy went
## on firing into a panel that covers the right half of the subtitle box, and
## the next line landed clipped exactly as before. A screenshot of the chart
## screen caught it: `Would the doctor who left ... please co`.
func set_modal(on: bool) -> void:
	_modal_open = on
	# AND THE CONTROLS REMINDER GOES WITH THEM. The patient card is a sheet
	# pinned to the right of the screen, and this line sits in the bottom-right
	# corner UNDER it — so with a card open the only part of it a player could
	# see was the last three letters of "pause" poking out past the card's left
	# edge, which reads as a rendering fault rather than a hint. It is also the
	# least useful moment for it: what [E] does in the world is not the question
	# while a form is up.
	if _help != null and is_instance_valid(_help):
		_help.visible = not on
	if on and _prompt_panel != null:
		_prompt_panel.visible = false
	if on:
		_subtitle_timer = 0.0
		if _subtitle_panel != null:
			_subtitle_panel.visible = false

func _on_subtitle(speaker: String, text: String, seconds: float) -> void:
	# Nothing goes behind a card. The world is still talking — it just is not
	# worth showing half a sentence for.
	if _modal_open:
		return
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
	# NOTHING IS SHOWN BEHIND A CARD, and nothing ages behind one either.
	#
	# A toast lives six seconds from the moment it is shown, and that clock ran
	# whether or not there was a 700-pixel briefing card sitting on top of it.
	# The very first line of teaching in the game — "Five beds. Read somebody's
	# chart before you decide anything." — is emitted on the same frame the
	# morning card opens, and the morning card has five patient rows and three
	# money figures on it. Nobody reads that in six seconds, so the instruction
	# that tells a new player what the first verb is had reliably expired
	# before they pressed "Start the round", and it never came back.
	#
	# The same applied to a lab result landing while a chart was open: five
	# minutes to order, seventy-five to wait, and it could arrive and die
	# entirely unseen. They queue instead, and the queue is not drained until
	# there is a screen to see them on. Subtitles already worked this way.
	if _modal_open:
		return
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
	# A BACKLOG DRAINS FASTER THAN A TRICKLE.
	#
	# Half a second between toasts is right when they arrive one at a time. It
	# is wrong the moment there is a queue — and there is now, because the queue
	# holds while a card is up, and the day has real things to say: three
	# warnings in the last hour, a round every ninety minutes (twice that when
	# you are watched), the registrar coming and going, a lab result, somebody's
	# family. Close a card on ten of those and the last of them arrives five
	# seconds later, by which point the first three have already been pushed off
	# the bottom of a column that holds three.
	_toast_gap = 0.5 if _toast_queue.size() < 3 else 0.18
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
	# EVERY TOAST MAKES A SOUND EXCEPT THE ONES THAT SHOULD NOT.
	#
	# Only "money" and "bad" played anything, and nothing in the project ever
	# emits "money" — so in practice one toast kind in the game had audio. The
	# returning test result is the single delayed payoff in the whole loop: you
	# spend five minutes ordering it and seventy-five waiting, and it arrived as
	# a small grey rectangle in the corner with no sound, frequently while a card
	# was open on top of it. It could land and expire completely unseen.
	match kind:
		"money": AudioMgr.play("money", -14.0)
		"bad": AudioMgr.play("error", -14.0)
		"result": AudioMgr.play("beep", -10.0, 1.35)
		# Deliberately silent: suspicion toasts are the game telling you
		# something you are supposed to notice out of the corner of your eye.
		"suspicion": pass
		_: AudioMgr.play("paper", -20.0, 1.1)
	while _toasts.get_child_count() > 3:
		_toasts.get_child(0).free()
	# Guard every await: the HUD can be torn down while a toast is still
	# counting down (scene change, or a headless harness rebuilding the world),
	# and resuming on a freed node throws.
	if not is_inside_tree():
		return
	# Six seconds OF BEING VISIBLE. `create_timer` runs while the tree is
	# paused, so a toast shown a frame before a card opened spent its whole
	# life behind it.
	var left := 6.0
	while left > 0.0:
		await get_tree().process_frame
		if not is_instance_valid(p) or not is_inside_tree():
			return
		if not _modal_open:
			left -= get_process_delta_time()
	if not is_instance_valid(p) or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	await tw.finished
	if is_instance_valid(p):
		p.queue_free()

func set_crosshair_visible(v: bool) -> void:
	_crosshair.visible = v
