extends ScreenBase
## THE CHART. The most important screen in the game, and deliberately the least
## decorated one.
##
## It shows every entry, in order, with who wrote it and when they wrote it. The
## ward sister will open exactly this in the morning and she will not be shown
## anything the player was not shown here. If a note was typed two hours after
## the moment it describes, that is visible now, tonight, while you can still do
## something about it.

var _pid := ""
var _writing := false
var _stated := 0
var _claim := ChartEntry.Claim.UNWELL

func _build() -> void:
	_pid = String(ctx.get("patient_id", ""))
	var c := Cases.by_id(_pid)
	if c.is_empty():
		close()
		return
	var w = ward()
	var v := card_shell(760, 720, String(c["name"]).to_upper(),
		"%s  ·  bed %d  ·  %s" % [String(c["condition"]), int(c["bed"]),
			Cases.tier_name(int(c["tier"]))])

	# The flag lives here and nowhere else. Nobody tells the player it exists;
	# they find it by opening the record, which is the only reason it is
	# interesting that Winifred Blake looks like the easiest hold on the ward.
	if c.has("audit_flag"):
		var flag := UIKit.panel(Color(0.32, 0.20, 0.14), 4, 1, UIKit.BAD)
		var fv := UIKit.vbox(2)
		fv.add_child(UIKit.label("ON FILE", 11, UIKit.BAD))
		fv.add_child(UIKit.label(String(c["audit_flag"]), 13, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
		flag.add_child(fv)
		v.add_child(flag)

	v.add_child(UIKit.label(String(c["summary"]), 14, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	var box := UIKit.vbox(6)
	for e in w.records.for_patient(_pid):
		box.add_child(_entry_row(e))
	if w.records.for_patient(_pid).is_empty():
		box.add_child(UIKit.label("Nothing recorded.", 14, UIKit.INK_DIM))
	# NOT wrapped in another scroll: card_shell already scrolls `body`, and a
	# ScrollContainer inside a ScrollContainer has a minimum height of zero.
	v.add_child(box)

	v.add_child(UIKit.rule())
	if _writing:
		_write_form(v, w)
	else:
		var acts := UIKit.hbox(8)
		acts.add_child(UIKit.button("Write a note", func():
			_writing = true
			_stated = w.minute
			rebuild()))
		acts.add_child(UIKit.button("Close", close))
		v.add_child(acts)

## One line of chart, and its metadata underneath in the colour of small print.
func _entry_row(e: ChartEntry) -> Control:
	var tint := UIKit.INK
	if e.supports_stay():
		tint = UIKit.WARN
	elif e.supports_discharge():
		tint = UIKit.GOOD
	var p := UIKit.panel(UIKit.NOTE, 3)
	var col := UIKit.vbox(1)
	col.add_child(UIKit.row("%s  %s" % [ChartEntry._hhmm(e.stated_minute), e.text],
		e.author_label(), tint, 14))
	var meta := e.metadata_line()
	if meta != "":
		col.add_child(UIKit.label("      " + meta, 11,
			UIKit.BAD if e.is_backdated() else UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT))
	p.add_child(col)
	return p

## Writing a note. The two things the player chooses are what it says and WHAT
## TIME IT SAYS IT HAPPENED — and the second one is the game.
func _write_form(v: VBoxContainer, w) -> void:
	v.add_child(UIKit.label("NEW ENTRY", 12, UIKit.INK_DIM))

	var kinds := [
		[ChartEntry.Claim.UNWELL, "Something is wrong", UIKit.WARN],
		[ChartEntry.Claim.SETTLED, "Comfortable, no concerns", UIKit.GOOD],
		[ChartEntry.Claim.SOCIAL, "Nowhere to go tonight", UIKit.ACCENT],
		[ChartEntry.Claim.ADMIN, "Administrative note", UIKit.INK_DIM],
	]
	var kb := UIKit.hbox(6)
	for k in kinds:
		var claim: int = k[0]
		kb.add_child(UIKit.button(String(k[1]),
			func():
				_claim = claim as ChartEntry.Claim
				rebuild(),
			(k[2] as Color).darkened(0.55) if _claim != claim else (k[2] as Color).darkened(0.2)))
	v.add_child(kb)

	# The time control. Stepping it backwards is backdating, and the screen says
	# so out loud rather than hiding it — the player is allowed to know exactly
	# what they are doing. What they cannot know is who will read it.
	var t := UIKit.hbox(6)
	t.add_child(UIKit.button("-15 min", func():
		_stated = maxi(0, _stated - 15); rebuild()))
	t.add_child(UIKit.label("observed at %s" % ChartEntry._hhmm(_stated), 16, UIKit.ACCENT))
	t.add_child(UIKit.button("+15 min", func():
		_stated = mini(w.minute, _stated + 15); rebuild()))
	v.add_child(t)

	var gap: int = w.minute - _stated
	if gap > ChartEntry.BACKDATE_TOLERANCE:
		v.add_child(UIKit.label(
			"It is %s now. This note will record that you wrote it %d minutes after the fact."
				% [ChartEntry._hhmm(w.minute), gap], 12, UIKit.BAD,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		v.add_child(UIKit.label("It is %s now." % ChartEntry._hhmm(w.minute), 12, UIKit.INK_DIM))

	var texts := _phrases(_claim)
	var pb := UIKit.vbox(4)
	for phrase in texts:
		var s := String(phrase)
		pb.add_child(UIKit.button(s, func(): _commit(w, s), UIKit.PANEL_LIGHT))
	v.add_child(pb)
	v.add_child(UIKit.button("Never mind", func(): _writing = false; rebuild()))

func _commit(w, text: String) -> void:
	w.write_entry(_pid, _claim, text, _stated, _terminal())
	_writing = false
	rebuild()

## Which machine you are standing at. It goes on the entry, and it is how a
## witness in that room ends up being a witness to this note.
func _terminal() -> String:
	var p = player()
	if p == null:
		return WardDay.TERMINAL_WARD
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null or not h.has_method("room_at"):
		return WardDay.TERMINAL_WARD
	match String(h.room_at(p.global_position)):
		"station": return WardDay.TERMINAL_STATION
		"office": return WardDay.TERMINAL_OFFICE
	return WardDay.TERMINAL_WARD

func _phrases(claim: int) -> Array:
	match claim:
		ChartEntry.Claim.UNWELL:
			return [
				"Reports transient dizziness on standing.",
				"Complains of pain at the site this evening.",
				"Appears unsettled. Not right yet.",
				"Wound warm to touch. Query early infection.",
			]
		ChartEntry.Claim.SOCIAL:
			return [
				"No care at home. Awaiting social work review.",
				"Unsafe discharge. Nobody available to collect.",
			]
		ChartEntry.Claim.SETTLED:
			return [
				"Comfortable. No concerns.",
				"Symptoms settled. Positional and transient.",
				"Reviewed. Nothing further to add.",
			]
	return [
		"Discussed plan with patient.",
		"Note timed late owing to ward workload.",
	]

func ward():
	return get_tree().get_first_node_in_group("ward_day")
