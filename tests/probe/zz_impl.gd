extends RefCounted
var tree: SceneTree = null
func run() -> void:
	# Exactly game.gd's ordering: register the callables, then start(), which
	# replaces WardDay.records with a brand new object (ward_day.gd:105).
	GameState.start_new_career(31337)
	var w := WardDay.new()
	tree.root.add_child(w)
	var first := w.records
	SaveSystem.register("records", w.records.to_dict, w.records.from_dict)
	w.start()
	print("records object replaced by start(): %s" % str(first != w.records))
	# Write something to today's chart.
	w.write_entry("marchetti", ChartEntry.Claim.UNWELL, "leg still warm", w.minute)
	print("live chart entries          : %d" % w.records.entries.size())
	print("entries the registered save sees: %d" % Array(w.records.to_dict().get("entries", [])).size() if false else "")
	SaveSystem.save_game("zz_probe")
	var f := FileAccess.open(SaveSystem.slot_path("zz_probe"), FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var saved: Array = Array(Dictionary(Dictionary(d["systems"])["records"]).get("entries", []))
	print("entries actually written to the save file: %d" % saved.size())
	print("game_state keys: %s" % str(Dictionary(d["game_state"]).keys()))
	SaveSystem.delete_save("zz_probe")
