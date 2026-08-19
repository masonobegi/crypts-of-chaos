extends ScreenBase
## The upgrade shop. Every entry states its downside plainly, because the
## interesting decision is not "can I afford it" but "do I want to be that
## visible".

func _build() -> void:
	var v := shell(880, 720, "Capital Spending",
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
		var box := UIKit.panel(Color(0.14, 0.17, 0.19, 0.93), 6)
		var bv := UIKit.vbox(4)
		bv.add_child(UIKit.row(String(spec["name"]),
			UIKit.money_str(int(spec["cost"])),
			UIKit.MONEY if Upgrades.can_afford(id) else UIKit.BAD, 17))
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
	# world mid-evening.
	var ss = shift_system()
	if ss == null:
		return {}
	var eco = get_tree().get_first_node_in_group("economy")
	return {
		"day": GameState.day,
		"statement": eco.last_statement if eco else {},
		"headline": Endings.headline(GameState.stats),
		"heat": GameState.heat, "heat_delta": 0.0,
		"sanction": GameState.SANCTIONS[GameState.sanction_level],
		"suspicions": suspicion().ranked_suspicions().slice(0, 6) if suspicion() else [],
		"census": patient_system().active_count() if patient_system() else 0,
		"overstay": patient_system().average_overstay() if patient_system() else 0.0,
		"clean": true,
		"reputation": GameState.reputation.duplicate(),
		"debt": GameState.total_debt(),
		"daily_debt": GameState.daily_debt_payment(),
	}

func _buy(id: String) -> void:
	if Upgrades.purchase(id):
		AudioMgr.play("money", -10.0)
	rebuild()
