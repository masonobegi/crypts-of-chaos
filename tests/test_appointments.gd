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
	# "not all at the same time" is a much weaker claim than it reads as, and it
	# is what let the day shift book EIGHT appointments into the seven hour-slots
	# the spreading formula could produce: two patients landed in the 12:00 slot
	# and one hour got nobody, every single day, and this test was green. One
	# slot per booking, on every shift — the strong form of what it meant to say.
	for kind in DB.SHIFT_ORDER:
		GameState.shift_kind = String(kind)
		GameState.minute_of_day = int(DB.shift(String(kind)).get("start_hour", 8)) * 60
		var b := _system()
		b.build_for_shift()
		var taken := {}
		var clashes := PackedStringArray()
		for e in b.list:
			var h := int(e["hour"])
			if taken.has(h):
				clashes.append("%02d:00" % h)
			taken[h] = true
		t.ok(clashes.is_empty(), "the %s list books one patient per hour, not two%s" % [
			String(kind), "" if clashes.is_empty() else " (double-booked " + ", ".join(clashes) + ")"])
		t.eq(b.list.size(), taken.size(),
			"and every %s booking got a slot of its own" % String(kind))
		b.patient_system.free()
		b.free()
	GameState.shift_kind = "day"
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

## A slot that has not come round yet is not late.
##
## This read hours-of-day directly and wrapped negatives by adding 24, which
## made every appointment more than about an hour ahead look twenty-three hours
## overdue — so the list marked itself entirely unseen at the first hour tick,
## before the player had walked anywhere. Counting inside the shift is the only
## version that is right for a shift that crosses midnight AND for a slot that
## is simply still in the future.
func test_an_appointment_in_the_future_is_not_overdue() -> void:
	GameState.shift_kind = "day"
	var a := _system()
	GameState.minute_of_day = 8 * 60
	t.eq(a.hours_late(8), 0, "the slot happening right now is not late")
	t.eq(a.hours_late(13), -5, "a slot five hours away is five hours away")
	t.eq(a.hours_late(15), -7, "and one at the end of the shift is not overdue at all")
	GameState.minute_of_day = 12 * 60
	t.eq(a.hours_late(9), 3, "a slot you are three hours past is three hours past")
	t.eq(a.hours_late(13), -1, "and the next one still has not come round")
	a.patient_system.free()
	a.free()

## The same arithmetic, on the shift that wraps.
func test_lateness_survives_a_shift_that_crosses_midnight() -> void:
	GameState.shift_kind = "evening"
	var a := _system()
	GameState.minute_of_day = 17 * 60
	t.eq(a.hours_late(16), 1, "an hour into the evening shift")
	t.eq(a.hours_late(22), -5, "and the late slots are still ahead")
	GameState.minute_of_day = 1 * 60          # 01:00, still the evening shift
	t.eq(a.hours_late(22), 3, "past midnight, the 22:00 slot is three hours gone")
	t.eq(a.hours_late(16), 9, "and the first one is long gone")
	a.patient_system.free()
	a.free()
	GameState.shift_kind = "day"

## A list does not expire itself before the shift has started.
func test_the_list_survives_the_first_hour_tick() -> void:
	GameState.shift_kind = "day"
	GameState.minute_of_day = 8 * 60
	var a := _system()
	a.build_for_shift()
	var booked := a.remaining()
	GameState.phase = GameState.Phase.SHIFT
	GameState.minute_of_day = 9 * 60
	a._on_hour(9)
	t.eq(a.remaining(), booked, "an hour in, nothing has been given up on")
	GameState.minute_of_day = 15 * 60
	a._on_hour(15)
	t.lt(float(a.remaining()), float(booked), "by the end of the day, plenty has")
	GameState.phase = GameState.Phase.PRE_SHIFT
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

## People waiting to be seen sit in the waiting row, one to a chair. A clinic
## where you can count the queue by looking at it is a different room from one
## where arrivals materialise wherever the navigation grid felt like.
func test_walkins_sit_down_one_to_a_chair() -> void:
	var h = load("res://scripts/world/hospital.gd").new()
	t.root.add_child(h)
	h.build()
	t.gt(float(Furniture.clinic_seats.size()), 3.0, "the clinic has a waiting row")

	var taken: Array = []
	var used := {}
	for i in Furniture.clinic_seats.size():
		var seat: Vector3 = h.clinic_seat(taken)
		t.ok(not used.has(seat), "each arrival gets a chair of their own")
		used[seat] = true
		taken.append(seat)
	# And when the row is full, the overflow is a real spot in the room rather
	# than the origin.
	var overflow: Vector3 = h.clinic_seat(taken)
	t.eq(h.room_at(overflow), "treatment", "an overflowing clinic still puts them in it")
	h.queue_free()
