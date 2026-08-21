extends ScreenBase
## End-of-shift chart review. The Papers-Please beat: everything an auditor would
## currently find, laid out while you can still do something about it.

func _build() -> void:
	var findings: Array = ctx.get("findings", [])
	var exposure := float(ctx.get("exposure", 0.0))
	var v := shell(940, 800, "Chart Review",
		"Before you go home. This is what a reviewer would find right now.")

	var band := "Nothing to find."
	var colour := UIKit.GOOD
	if exposure > 2.2:
		band = "This will not survive an audit."
		colour = UIKit.BAD
	elif exposure > 1.0:
		band = "There is enough here to start something."
		colour = UIKit.WARN
	elif exposure > 0.25:
		band = "Minor gaps. Probably fine."
		colour = Color(0.58, 0.48, 0.05)
	var head := UIKit.panel(UIKit.NOTE, 6, 1, colour)
	var hv := UIKit.vbox(5)
	hv.add_child(UIKit.label(band, 18, colour))
	hv.add_child(UIKit.bar(clampf(exposure / 3.0, 0.0, 1.0), colour, 480.0, 10.0))
	head.add_child(hv)
	v.add_child(head)

	var content := UIKit.vbox(8)

	var undoc: Array = ctx.get("undocumented", [])
	if not undoc.is_empty():
		content.add_child(UIKit.label("UNDOCUMENTED COMPLICATIONS", 13, UIKit.INK_DIM))
		content.add_child(UIKit.label(
			"A complication with no stated cause is the single most findable thing in a record. "
			+ "Terminals are still on.", 13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		for u in undoc:
			content.add_child(UIKit.row(String(u["patient"]), String(u["complication"]), UIKit.BAD))
		content.add_child(UIKit.rule())

	# Injuries get their own block. Filing a mechanism closes the individual gap
	# and does nothing at all about the fact that this is the third thing to
	# happen to the same person on your ward, and the screen should not imply
	# otherwise by folding them in with everything else.
	var acquired: Array = ctx.get("acquired", [])
	if not acquired.is_empty():
		content.add_child(UIKit.label("SUSTAINED ON THE WARD", 13, UIKit.INK_DIM))
		for a in acquired:
			var n := int(a["count"])
			var box := UIKit.panel(UIKit.NOTE_BAD, 6)
			var bv := UIKit.vbox(2)
			bv.add_child(UIKit.row("%s — in with %s" % [String(a["patient"]),
				String(a["presenting"])],
				"%d since" % n, UIKit.BAD if n > 1 else UIKit.WARN))
			for line in a["injuries"]:
				var cause := String(line["cause"])
				bv.add_child(UIKit.row("    " + String(line["name"]),
					cause if cause != "" else "no mechanism recorded",
					UIKit.INK_DIM if cause != "" else UIKit.BAD, 13))
			box.add_child(bv)
			content.add_child(box)
		content.add_child(UIKit.rule())

	content.add_child(UIKit.label("FINDINGS", 13, UIKit.INK_DIM))
	if findings.is_empty():
		content.add_child(UIKit.label("Your records are consistent. Genuinely.", 15, UIKit.GOOD))
	for f in findings:
		var w := float(f["weight"])
		var c := UIKit.WARN if w < 0.5 else UIKit.BAD
		var box := UIKit.panel(UIKit.NOTE, 6)
		var bv := UIKit.vbox(2)
		bv.add_child(UIKit.row(String(f["patient"]), String(f["kind"]).replace("_", " "), c))
		bv.add_child(UIKit.label(String(f["text"]), 13, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(bv)
		content.add_child(box)

	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("WARD", 13, UIKit.INK_DIM))
	for s in ctx.get("patients", []):
		var over := bool(s["overdue"])
		content.add_child(UIKit.row(
			"%s — %s" % [String(s["name"]), String(s["condition"])],
			"day %d/%d · %s · %s/day" % [int(ceil(float(s["days"]))), int(ceil(float(s["expected"]))),
				String(s["state"]), UIKit.money_str(int(s["revenue"]))],
			UIKit.WARN if over else UIKit.INK, 14))

	v.add_child(UIKit.scroll(content))
	var buttons := UIKit.hbox(10)
	buttons.add_child(UIKit.button("Go and fix it", func():
		close()
		EventBus.toast.emit(
			"Sign off at the terminal in your office when you're done.", "info")))
	buttons.add_child(UIKit.button("Clock out", func():
		var ss = shift_system()
		close()
		if ss:
			ss.clock_out(), Color(0.16, 0.30, 0.28)))
	v.add_child(buttons)
