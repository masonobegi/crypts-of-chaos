extends ScreenBase
## The evening: where you are going, and what happened when you got there.
##
## Two small screens with a whole 3D street between them. This used to BE the
## street — a top-down field with dots on it — and the note after playing it was
## "the crime minigames should be in 3D as well, the one I just played sucked".
## Right. The ward is a first-person game about lines of sight; drawing the one
## place where that is the entire point as a diagram threw the point away.
##
## So this screen picks a place and then gets out of the way. What happens next
## happens on your feet, in the dark, with the same controls as everything else.

var _result: Dictionary = {}

func night():
	return get_tree().get_first_node_in_group("night_system")

func _build() -> void:
	_result = Dictionary(ctx.get("result", {}))
	if _result.is_empty():
		_build_choose()
	else:
		_build_after()

# ------------------------------------------------------------------ choosing
func _build_choose() -> void:
	var ns = night()
	var free: int = ns.beds_free() if ns != null else 0
	var v := shell(820, 760, "The evening",
		"Day %d  ·  %d bed%s free" % [GameState.day, free, "" if free == 1 else "s"])
	first_time_note(v, "night")
	v.add_child(UIKit.label(
		"You could go home. The ward fills up on its own eventually, and "
		+ "eventually is the problem.", 15, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	if free <= 0:
		v.add_child(UIKit.label(
			"Every bed is full. Anybody you meet tonight goes across town, and "
			+ "you will have taken the risk for nothing.",
			14, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())
	var list := UIKit.vbox(6)
	# Easiest first. PLACES is already in that order and the test says so.
	for spec in NightSystem.PLACES:
		list.add_child(_place_option(spec))
	v.add_child(UIKit.scroll(list))
	v.add_child(UIKit.button("Go home. It's been a day.", _go_home))

func _place_option(spec: Dictionary) -> Control:
	var w := int(spec["watchers"])
	var l := int(spec["lamps"])
	var diff := int(spec.get("diff", 1))
	var act := String(spec.get("act", "reach"))
	var tint: Color = [UIKit.INK, UIKit.GOOD, UIKit.WARN, UIKit.BAD][clampi(diff, 0, 3)]
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 3, 2, tint)
	var bv := UIKit.vbox(3)
	var b := UIKit.button(String(spec["name"]), func(): _go_there(spec))
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", UIKit.ACCENT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bv.add_child(b)
	# Difficulty first, because "I want a hard one tonight" is the question this
	# screen is actually being asked.
	bv.add_child(UIKit.row(String(NightSystem.DIFF_NAMES[clampi(diff, 0, 3)]),
		String(NightSystem.ACTS[act]["name"]), tint, 14, tint))
	bv.add_child(UIKit.label(String(spec["blurb"]), 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	bv.add_child(UIKit.label(String(NightSystem.ACTS[act]["how"]), 13, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	# And what they turn up with, because which limb walks through your door
	# tomorrow is half the reason to pick one street over another.
	var cond := String(spec["condition"])
	bv.add_child(UIKit.field("They arrive with",
		String(DB.condition(cond).get("name", cond)), UIKit.ACCENT, 13))
	bv.add_child(UIKit.field("Other people about", "%d" % w,
		UIKit.BAD if w >= 4 else UIKit.INK, 13))
	bv.add_child(UIKit.field("Street lighting",
		"none" if l == 0 else ("one lamp" if l == 1 else "%d lamps" % l),
		UIKit.BAD if l >= 3 else UIKit.INK, 13))
	var hz := String(NightSystem.HAZARDS.get(String(spec.get("hazard", "")), ""))
	if hz != "":
		bv.add_child(UIKit.label(hz, 13, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	p.add_child(bv)
	return p

## Pick a street, close the screen, and walk down it.
func _go_there(spec: Dictionary) -> void:
	var ns = night()
	close()
	if ns != null:
		ns.call_deferred("enter", String(spec["id"]))

# ------------------------------------------------------------------ afterwards
func _build_after() -> void:
	var outcome := String(_result.get("outcome", "missed"))
	var headings := {
		"clean": "Nobody saw a thing",
		"seen": "Somebody saw somebody",
		"caught": "Somebody saw YOU",
		"missed": "You went home",
	}
	var tints := {"clean": UIKit.GOOD, "seen": UIKit.WARN, "caught": UIKit.BAD}
	var tint: Color = tints.get(outcome, UIKit.INK_DIM)
	var v := shell(760, 560, String(headings.get(outcome, "You went home")),
		String(_result.get("place", "")))
	v.add_child(UIKit.stamp(outcome if outcome != "missed" else "no further action", tint))
	var box := UIKit.panel(UIKit.NOTE, 3, 2, tint)
	var bv := UIKit.vbox(4)
	bv.add_child(UIKit.label(String(_result.get("line", "")), 16, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	# What you actually did to them. Asked for by name — "let me know how I
	# injured the patient after I've done it" — and it belongs here rather than
	# on the way in, because the whole phase is about not knowing quite how bad
	# it was until afterwards.
	var injury := String(_result.get("injury", ""))
	if injury != "":
		bv.add_child(UIKit.field("%s has" % String(_result.get("mark", "They")),
			injury, UIKit.ACCENT))
	if bool(_result.get("admitted", false)):
		bv.add_child(UIKit.field("On your list", "tomorrow morning", UIKit.MONEY))
	box.add_child(bv)
	v.add_child(box)

	if outcome == "seen":
		v.add_child(_note(UIKit.WARN,
			"A description, and nothing more. It goes on a pile with a hundred "
			+ "other descriptions of a man in a coat — but the pile is yours now."))
	elif outcome == "caught":
		if bool(_result.get("sued", false)):
			v.add_child(_note(UIKit.BAD,
				"A witness. Not a colleague, not a patient, and they owe you "
				+ "nothing. There will be a letter, and it will not be about "
				+ "your paperwork."))
		else:
			v.add_child(_note(UIKit.BAD,
				"A witness, and a very long walk home."))
	if bool(_result.get("admitted", false)) and outcome != "clean":
		v.add_child(_note(UIKit.BAD,
			"And they will be in one of your beds for a week, trying to place "
			+ "your face."))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Home", _go_home))

func _note(tint: Color, text: String) -> Control:
	var p := UIKit.panel(UIKit.NOTE, 3, 1, tint)
	p.add_child(UIKit.label(text, 14, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	return p

func _go_home() -> void:
	close()
	var ss = shift_system()
	if ss != null:
		ss.call_deferred("next_day")
