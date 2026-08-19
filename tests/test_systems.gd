extends RefCounted
## Integration tests for the runtime systems. These actually construct the
## hospital in a headless tree — compilation passing is not the same as the
## floor being connected, and an unreachable ward would be invisible until an
## NPC silently failed to path there.
var t

var _h = null

func _hospital():
	if _h != null and is_instance_valid(_h):
		return _h
	var HospitalScript := load("res://scripts/world/hospital.gd")
	_h = HospitalScript.new()
	t.root.add_child(_h)
	_h.build()
	return _h

func test_hospital_builds_all_rooms() -> void:
	var h = _hospital()
	t.eq(h.rooms.size(), 12, "every room in LAYOUT is constructed")
	for key in ["corridor", "ward_101", "ward_105", "lobby", "station",
			"treatment", "supply", "bathroom", "office"]:
		t.ok(h.room(key) != null, "room exists: %s" % key)

func test_room_lookup_by_position() -> void:
	var h = _hospital()
	t.eq(h.room_at(Vector3(4.5, 0, 8.0)), "ward_101", "point inside ward 101")
	t.eq(h.room_at(Vector3(23.0, 0, 2.0)), "corridor", "point inside corridor")
	t.eq(h.room_at(Vector3(43.0, 0, -5.0)), "office", "point inside office")
	t.eq(h.room_at(Vector3(-40.0, 0, -40.0)), "", "point outside the floor")

func test_rooms_do_not_overlap() -> void:
	var h = _hospital()
	var list = h.room_list()
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Rect2 = list[i].rect
			var b: Rect2 = list[j].rect
			var overlap := a.intersection(b)
			t.lt(overlap.get_area(), 0.001, "%s and %s do not overlap" % [list[i].key, list[j].key])

func test_navigation_is_connected() -> void:
	var h = _hospital()
	t.gt(float(h.nav.cell_count()), 300.0, "nav grid has meaningful coverage")
	# Every room must be reachable from the lobby, or NPCs silently fail to path.
	var from: Vector3 = h.point_in("lobby")
	for key in h.rooms.keys():
		var to = h.point_in(key)
		var path = h.nav.find_path(from, to)
		t.gt(float(path.size()), 0.0, "path exists from lobby to %s" % key)

func test_ward_to_ward_paths_cross_the_corridor() -> void:
	var h = _hospital()
	var path = h.nav.find_path(h.point_in("ward_101"), h.point_in("ward_105"))
	t.gt(float(path.size()), 3.0, "cross-floor path has waypoints")
	var touched_corridor := false
	for p in path:
		if h.room_at(p) == "corridor":
			touched_corridor = true
	t.ok(touched_corridor, "ward-to-ward route goes through the corridor, not through walls")

func test_beds_exist_in_every_ward() -> void:
	var h = _hospital()
	var beds: Array = t.root.get_tree().get_nodes_in_group("bed")
	t.gt(float(beds.size()), 4.0, "a bed per ward")
	for w in h.wards():
		var found := false
		for b in beds:
			if b.room_key == w.key:
				found = true
		t.ok(found, "ward %s has a bed" % w.key)

func test_room_comfort_responds_to_environment() -> void:
	var h = _hospital()
	var r = h.room("ward_102")
	r.temperature = 21.0
	r.lights_on = true
	r.cleanliness = 1.0
	var base: float = r.comfort()
	t.gt(base, 0.95, "a comfortable room does not slow recovery")
	r.temperature = 9.0
	t.lt(r.comfort(), base * 0.85, "a freezing room slows recovery")
	r.temperature = 21.0
	r.lights_on = false
	t.lt(r.comfort(), base, "darkness slows recovery")
	r.lights_on = true
	r.cleanliness = 0.0
	t.lt(r.comfort(), base, "filth slows recovery")

func test_open_window_cools_the_room() -> void:
	var h = _hospital()
	var r = h.room("ward_103")
	r.temperature = 21.0
	r.window_open = true
	for i in 200:
		r._drift_temperature(1.0)
	t.lt(r.temperature, 15.0, "an open window genuinely chills the ward")
	t.ok(r.complaints().size() > 0, "and people in it have something to say about that")

func test_machine_normal_setting_is_clean() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp")
	p.condition_id = "spleen_torque"      # humour_rebalance is correct for this
	m.set_prescribed_for(p)
	m.dial = m.prescribed
	var res: Dictionary = m.run_cycle(p)
	t.eq(res["band"], "normal", "on-prescription is the normal band")
	t.gt(float(res["recovery"]), 0.2, "and actually treats the patient")
	t.near(float(res["visual"]), 0.0, 0.001, "and looks like nothing at all")
	t.eq(String(res["complication"]), "", "with no complication")
	m.queue_free()

func test_machine_extreme_setting_is_visible_and_harmful() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp2")
	p.condition_id = "spleen_torque"
	m.set_prescribed_for(p)
	m.dial = clampi(m.prescribed + 6, 0, 11)
	if absi(m.dial - m.prescribed) < 5:
		m.dial = clampi(m.prescribed - 6, 0, 11)
	var res: Dictionary = m.run_cycle(p)
	t.eq(res["band"], "extreme", "far off-prescription is the extreme band")
	t.lt(float(res["recovery"]), 0.0, "and actively harms recovery")
	t.gt(float(res["visual"]), 0.4, "and is very visible to anyone watching")
	t.ok(String(res["complication"]) != "", "and guarantees a complication")
	m.queue_free()

func test_machine_keeps_an_auditable_log() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp3")
	p.condition_id = "spleen_torque"
	p.display_name = "Greg"
	m.set_prescribed_for(p)
	m.dial = m.prescribed
	m.run_cycle(p)
	t.eq(m.suspicious_log_entries().size(), 0, "a by-the-book cycle leaves nothing to find")
	m.dial = clampi(m.prescribed + 4, 0, 11)
	if absi(m.dial - m.prescribed) < 3:
		m.dial = clampi(m.prescribed - 4, 0, 11)
	m.run_cycle(p)
	t.eq(m.suspicious_log_entries().size(), 1, "a deviation is recorded against your name")
	t.eq(m.log_entries.size(), 2, "the log keeps everything")
	m.clear_log()
	t.eq(m.log_entries.size(), 0, "wiping works")
	t.eq(m.log_cleared_count, 1, "and is itself recorded, which is the point")
	m.queue_free()

func test_miscalibration_is_persistent_and_invisible() -> void:
	var m = load("res://scripts/world/machine.gd").new()
	m.treatment_id = "humour_rebalance"
	t.root.add_child(m)
	m.build("Test Rebalancer")
	var p := Patient.new("tp4")
	p.condition_id = "spleen_torque"
	m.set_prescribed_for(p)
	m.dial = m.prescribed
	var healthy: float = float(m.run_cycle(p)["recovery"])
	m.open_panel()
	for i in 4:
		m._nudge_calibration()
	m.close_panel()
	var sabotaged: float = float(m.run_cycle(p)["recovery"])
	t.lt(sabotaged, healthy * 0.75, "miscalibration steals effectiveness from every cycle")
	t.ok(m.is_miscalibrated(), "and persists until someone services it")
	t.eq(m.suspicious_log_entries().size(), 0, "while leaving the dial log spotless")
	m.queue_free()
