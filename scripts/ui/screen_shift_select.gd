extends ScreenBase
## The first decision of every day, and the one that shapes all the others.
##
## The three cards deliberately state the upside and the catch in the same
## breath, because the trade is not "safe versus risky" — it is witnesses
## against attribution. Nobody sees anything on a night shift, and there is
## exactly one person to ask about it in the morning.

func _build() -> void:
	var v := shell(880, 640, "Day %d" % int(ctx.get("day", 1)), "Which shift are you taking?")

	var money := UIKit.hbox(24)
	money.add_child(UIKit.row("In your account",
		UIKit.money_str(int(ctx.get("personal", 0))),
		UIKit.MONEY if int(ctx.get("personal", 0)) >= 0 else UIKit.BAD, 16))
	money.add_child(UIKit.row("Owed", UIKit.money_str(int(ctx.get("owed", 0))), UIKit.BAD, 16))
	v.add_child(money)
	v.add_child(UIKit.rule())

	var row := UIKit.hbox(12)
	for o in ctx.get("options", []):
		row.add_child(_card(o))
	v.add_child(row)

func _card(o: Dictionary) -> Control:
	var box := UIKit.panel(UIKit.NOTE, 8, 1, Color(0.28, 0.42, 0.44))
	var bv := UIKit.vbox(6)
	bv.custom_minimum_size = Vector2(258, 0)

	bv.add_child(UIKit.label(String(o.get("name", "")), 22, UIKit.ACCENT))
	bv.add_child(UIKit.label(String(o.get("hours", "")), 14, UIKit.INK_DIM))
	bv.add_child(UIKit.rule())
	bv.add_child(UIKit.row("Pay", "×%.2f" % float(o.get("pay", 1.0)), UIKit.MONEY))
	bv.add_child(UIKit.row("On your list", "%d appointments" % int(o.get("appointments", 0)),
		UIKit.MONEY if int(o.get("appointments", 0)) >= 6 else UIKit.INK))
	# Staff on the floor is the number that decides whether anything you do is
	# seen, so it is stated as what it MEANS rather than as a headcount.
	var staff := int(o.get("staff", 0))
	bv.add_child(UIKit.row("Watching you", _eyes(staff),
		UIKit.BAD if staff >= 5 else (UIKit.WARN if staff >= 3 else UIKit.GOOD)))
	# ...and so is what it costs you afterwards, which is the thing nights were
	# missing. A shift with no evening after it is a shift with no way to fill
	# the beds it just emptied.
	var out: bool = float(o.get("night_penalty", 0.0)) < 0.5
	bv.add_child(UIKit.row("Out afterwards", "yes" if out else "no",
		UIKit.GOOD if out else UIKit.BAD))
	bv.add_child(UIKit.spacer(6))
	bv.add_child(UIKit.label(String(o.get("blurb", "")), 14, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	bv.add_child(UIKit.label(String(o.get("catch", "")), 13, UIKit.WARN,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	bv.add_child(UIKit.spacer())

	var kind := String(o.get("kind", "day"))
	bv.add_child(UIKit.button("Take it", func(): _take(kind), Color(0.16, 0.32, 0.30)))
	box.add_child(bv)
	return box

## Five people is an audience. One is a witness. Nobody is nobody.
func _eyes(staff: int) -> String:
	if staff <= 1:
		return "one nurse"
	if staff <= 3:
		return "%d, and visitors" % staff
	return "%d, all shift" % staff

func _take(kind: String) -> void:
	var ss = shift_system()
	close()
	if ss:
		ss.begin_day(kind)
