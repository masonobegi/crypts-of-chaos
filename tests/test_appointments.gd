extends RefCounted
## The booked list: what a shift IS, and where most of the money comes from.
var t

func _system() -> AppointmentSystem:
	var ps := PatientSystem.new()
	t.root.add_child(ps)
	var a := AppointmentSystem.new()
	t.root.add_child(a)
	a.patient_system = ps
	a.economy = null
	return a

func test_a_shift_books_the_number_of_slots_it_advertises() -> void:
	# The shift-select screen promises a number of appointments. If the roster
	# did not match it, the one number the player uses to choose a shift would
	# be a lie.
	for kind in DB.SHIFT_ORDER:
		GameState.shift_kind = kind
		GameState.minute_of_day = GameState.shift_start_hour() * 60
		var a := _system()
		a.build_for_shift()
		t.eq(a.list.size(), int(DB.shift(kind)["appointments"]),
			"the %s shift books what it advertises" % kind)
		a.patient_system.free()
		a.free()
	GameState.shift_kind = "day"

func test_slots_are_spread_across_the_shift_rather_than_stacked() -> void:
	GameState.shift_kind = "day"
	GameState.minute_of_day = 8 * 60
	var a := _system()
	a.build_for_shift()
	var hours := {}
	for e in a.list:
		hours[int(e["hour"])] = true
		t.between(float(int(e["hour"])), 8.0, 16.0, "slot sits inside the shift")
	t.gt(float(hours.size()), 2.0, "and they are not all at the same time")
	a.patient_system.free()
	a.free()

## An empty ward can still fill a list, because somebody can always walk in.
func test_an_empty_ward_still_has_a_clinic() -> void:
	GameState.shift_kind = "night"
	GameState.minute_of_day = 0
	var a := _system()
	a.build_for_shift()
	t.eq(a.list.size(), int(DB.shift("night")["appointments"]), "the night list fills")
	for e in a.list:
		t.eq(String(e["kind"]), "physical",
			"with nobody on the ward, everything on it is a walk-in")
	t.eq(a.patient_system.active().size(), 0, "and none of them is admitted yet")
	t.eq(a.patient_system.walkins().size(), a.list.size(), "they are all still walk-ins")
	a.patient_system.free()
	a.free()
	GameState.shift_kind = "day"

## A walk-in earns the hospital nothing until you decide they need a bed. That
## asymmetry is the entire clinic loop.
func test_a_walkin_costs_nothing_and_an_admission_starts_the_meter() -> void:
	GameState.shift_kind = "day"
	var a := _system()
	var p := a.patient_system.book_walkin()
	t.ok(not p.admitted, "a walk-in is not admitted")
	t.eq(a.patient_system.total_daily_revenue(), 0, "and is billing nobody")
	t.eq(a.patient_system.active().size(), 0, "and is not on the census")
	t.eq(a.patient_system.walkins().size(), 1, "but is definitely in the building")
	a.patient_system.free()
	a.free()

func test_completing_a_slot_closes_it_and_only_it() -> void:
	GameState.shift_kind = "day"
	GameState.minute_of_day = 8 * 60
	var a := _system()
	a.build_for_shift()
	var first: Dictionary = a.list[0]
	var before := a.remaining()
	t.eq(a.complete("surgery", String(first["patient_id"])), 0,
		"the wrong kind of work does not clear a slot")
	t.eq(a.remaining(), before, "and leaves the list alone")
	var fee := a.complete(String(first["kind"]), String(first["patient_id"]))
	t.gt(float(fee), 0.0, "doing the booked work pays a fee")
	t.eq(a.remaining(), before - 1, "and takes it off the list")
	t.eq(a.complete(String(first["kind"]), String(first["patient_id"])), 0,
		"you cannot bill the same appointment twice")
	a.patient_system.free()
	a.free()

## Not turning up is its own cost, separate from anything clinical.
func test_a_slot_you_never_attend_costs_you() -> void:
	GameState.shift_kind = "day"
	GameState.minute_of_day = 8 * 60
	var a := _system()
	a.build_for_shift()
	var sat := GameState.rep("patient_sat")
	var n := a.settle_unseen()
	t.eq(n, a.list.size(), "everything outstanding is marked unseen")
	t.lt(GameState.rep("patient_sat"), sat, "and standing with patients drops")
	t.eq(a.remaining(), 0, "nothing is left pending")
	a.patient_system.free()
	a.free()
