extends ScreenBase
## The upgrade shop. Every entry states its downside plainly, because the
## interesting decision is not "can I afford it" but "do I want to be that
## visible".

func _build() -> void:
	var v := shell(920, 800, "Capital Spending",
		"Hospital funds: %s" % UIKit.money_str(GameState.hospital_money))
	var content := UIKit.vbox(8)

	var owned: Array = GameState.owned_upgrades
	if not owned.is_empty():
		content.add_child(UIKit.label("INSTALLED", 13, UIKit.INK_DIM))
		for id in owned:
			content.add_child(UIKit.row(String(Upgrades.spec(String(id)).get("name", id)),
				"installed", UIKit.GOOD, 14))
		content.add_child(UIKit.rule())

	content.add_child(UIKit.label("AVAILABLE", 13, UIKit.INK_DIM))
	for id in Upgrades.available():
		var spec := Upgrades.spec(id)
		var box := UIKit.panel(UIKit.NOTE, 6)
		var bv := UIKit.vbox(4)
		bv.add_child(UIKit.row(String(spec["name"]),
			UIKit.money_str(int(spec["cost"])),
			UIKit.MONEY if Upgrades.can_afford(id) else UIKit.BAD, 17, UIKit.INK))
		bv.add_child(UIKit.label(String(spec["desc"]), 14, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
		bv.add_child(UIKit.label(String(spec["note"]), 13, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
		var upgrade_id := id
		var b := UIKit.button("Purchase", func(): _buy(upgrade_id))
		b.disabled = not Upgrades.can_afford(id)
		bv.add_child(b)
		box.add_child(bv)
		content.add_child(box)

	v.add_child(UIKit.scroll(content))
	v.add_child(UIKit.button("Back", func():
		if ui:
			ui.open("statement", _last_statement())))

func _last_statement() -> Dictionary:
	# Return to the report we came from rather than dropping the player into the
	# world mid-evening — and to the SAME report, not a fresh one.
	#
	# This used to rebuild the context by hand with "heat_delta": 0.0 and
	# "clean": true hardcoded, and re-rolled Endings.headline(), which is a
	# random pick. So walking into the upgrade shop and back out again changed
	# the game's verdict on your shift to the flattering one and gave you a
	# different headline. The two numbers the card exists to show were the two
	# it threw away.
	var ss = shift_system()
	if ss == null or ss.last_statement.is_empty():
		return {}
	return ss.last_statement

func _buy(id: String) -> void:
	if Upgrades.purchase(id):
		AudioMgr.play("money", -10.0)
	rebuild()
