extends RefCounted
var tree: SceneTree = null
var game: Node = null
var frames := 0
var done := false

func start() -> void:
	GameState.start_new_career(20260821)
	GameState.set_flag("tutorial_done", true)
	var packed: PackedScene = load("res://scenes/Game.tscn")
	game = packed.instantiate()
	tree.root.add_child(game)

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 12:
		return false
	if done:
		return true
	done = true
	var ps = tree.get_first_node_in_group("patient_system")
	print("\n--- day 1 ---")
	for p in ps.active():
		var b = ps.get_body(p.id)
		print("  %-14s bed %d  pos %s" % [p.id, p.bed_index,
			str(b.global_position) if b != null else "none"])
	# marchetti was sent home wrongly last night
	GameState.set_flag(Cases.READMIT_FLAG, ["marchetti"])
	GameState.day = 2
	var w = tree.get_first_node_in_group("ward_day")
	w.start()
	ps.reset_day()
	print("\n--- day 2, marchetti readmitted ---")
	print("  roster beds: ")
	for c in Cases.roster():
		print("     %-14s case bed %d  readmitted=%s" % [String(c["id"]), int(c["bed"]),
			str(bool(c.get("readmitted", false)))])
	var beds := {}
	for p in ps.active():
		var b = ps.get_body(p.id)
		beds[p.bed_index] = int(beds.get(p.bed_index, 0)) + 1
		print("  %-14s Patient.bed_index %d  condition '%s'  pos %s" % [p.id, p.bed_index,
			p.condition_name(), str(b.global_position) if b != null else "none"])
	print("  distinct beds occupied: %d of %d" % [beds.size(), Cases.BEDS])
	for k in beds:
		if int(beds[k]) > 1:
			print("  *** BED %d HAS %d PEOPLE IN IT ***" % [k, int(beds[k])])
	# what is on the chart
	print("\n  chart patient ids present in records:")
	var seen := {}
	for e in w.records.entries:
		seen[e.patient_id] = int(seen.get(e.patient_id, 0)) + 1
	print("   ", seen)
	print("  roster ids: ", Cases.roster().map(func(c): return String(c["id"])))
	return true
