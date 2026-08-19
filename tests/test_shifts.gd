extends RefCounted
## The three shifts, and the clock arithmetic that lets one of them cross
## midnight without the whole day falling over.
var t

func _use(kind: String) -> void:
	GameState.shift_kind = kind
	GameState.minute_of_day = GameState.shift_start_hour() * 60

func test_every_shift_is_eight_hours_and_they_tile_the_day() -> void:
	var covered := 0
	var starts: Array[int] = []
	for kind in DB.SHIFT_ORDER:
		var spec: Dictionary = DB.SHIFTS[kind]
		t.eq(int(spec["hours"]), 8, "%s is an eight-hour shift" % kind)
		covered += int(spec["hours"])
		starts.append(int(spec["start_hour"]))
	t.eq(covered, 24, "the three shifts cover the whole day")
	starts.sort()
	t.eq(starts, [0, 8, 16] as Array, "and start where the previous one ends")

## The evening shift ends at midnight and the night shift starts there, so
## anything that compares minute_of_day against an end hour is wrong for one of
## them. Counting forward from the start is the only version that works for all
## three.
func test_the_clock_survives_a_shift_that_crosses_midnight() -> void:
	_use("evening")
	t.eq(GameState.minute_of_day, 16 * 60, "the evening shift starts at 16:00")
	t.ok(not GameState.shift_over(), "and is not over the moment it begins")
	GameState.minute_of_day = 23 * 60 + 59
	t.ok(not GameState.shift_over(), "one minute to midnight is still on shift")
	t.eq(GameState.shift_minutes_remaining(), 1, "with a minute left")
	GameState.minute_of_day = 0                       # midnight rolled over
	t.ok(GameState.shift_over(), "and midnight ends it")

	_use("night")
	t.eq(GameState.minute_of_day, 0, "the night shift starts at midnight")
	t.ok(not GameState.shift_over(), "and is not instantly over")
	GameState.minute_of_day = 7 * 60 + 59
	t.ok(not GameState.shift_over(), "07:59 is still the night shift")
	GameState.minute_of_day = 8 * 60
	t.ok(GameState.shift_over(), "08:00 is not")
	_use("day")

func test_the_night_shift_trades_witnesses_for_attribution() -> void:
	# This is the whole reason there are three of them. If the quiet shift were
	# also the safe one there would be nothing to decide.
	t.lt(float(DB.staff_on("night")), float(DB.staff_on("day")),
		"fewer people are on at night")
	t.gt(float(DB.shift("night")["pay"]), float(DB.shift("day")["pay"]),
		"and it pays more for the inconvenience")
	t.lt(float(DB.shift("night")["appointments"]), float(DB.shift("day")["appointments"]),
		"there is less booked work to hide behind")
	t.eq(DB.staff_on("night"), 1,
		"exactly one other person is on, which is exactly one person to ask")

func test_the_rota_is_fixed_so_who_is_on_is_worth_knowing() -> void:
	# Rostering people at random would make "she's on nights" meaningless, and
	# knowing the staff is most of how you plan anything.
	for kind in DB.SHIFT_ORDER:
		var r := DB.rota(kind)
		t.ok(r.has("nurses") and r.has("doctors"), "%s has a roster" % kind)
	var seen := {}
	for kind in DB.SHIFT_ORDER:
		for n in DB.rota(kind)["nurses"]:
			seen[int(n)] = true
	t.gt(float(seen.size()), 1.0, "more than one nurse exists across the week")
	t.ok(DB.rota("night")["doctors"].is_empty(), "no doctor is on overnight")

## Off duty means out of the building. The MIND stays — being at home does not
## unsee Tuesday — but they cannot witness tonight.
func test_off_duty_staff_cannot_witness_but_do_not_forget() -> void:
	var sus := SuspicionSystem.new()
	t.root.add_child(sus)
	var nurse := NPCBody.new()
	t.root.add_child(nurse)
	nurse.global_position = Vector3.ZERO
	var mind := DB.make_mind("rota_nurse", "Nurse Rota", "nurse", "gossip")
	mind.observance = 1.0
	sus.register(mind, nurse)

	nurse.set_on_duty(false)
	WorldEvent.new("rota_test_act", "player").at(Vector3(0, 1.4, 0), "") \
		.heard(0.9, 12.0).says("something loud").emit()
	t.eq(mind.evidence.size(), 0, "somebody at home does not witness your shift")

	nurse.set_on_duty(true)
	nurse.global_position = Vector3.ZERO
	WorldEvent.new("rota_test_act", "player").at(Vector3(0, 1.4, 0), "") \
		.heard(0.9, 12.0).says("something loud").emit()
	t.eq(mind.evidence.size(), 1, "and does the moment they are back on")

	sus.free()
	nurse.free()
