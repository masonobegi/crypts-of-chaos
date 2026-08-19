extends RefCounted
var t

func test_gamestate_clock() -> void:
	GameState.minute_of_day = 8 * 60
	t.eq(GameState.time_string(), "8:00 AM", "morning time string")
	GameState.minute_of_day = 13 * 60 + 5
	t.eq(GameState.time_string(), "1:05 PM", "afternoon time string")
	GameState.minute_of_day = 0
	t.eq(GameState.time_string(), "12:00 AM", "midnight time string")

func test_shift_bounds() -> void:
	GameState.minute_of_day = 8 * 60
	t.eq(GameState.shift_minutes_remaining(), 480, "full shift at clock-in")
	t.ok(not GameState.shift_over(), "shift not over at start")
	GameState.minute_of_day = 16 * 60
	t.ok(GameState.shift_over(), "shift over at 4pm")

func test_new_career_resets() -> void:
	GameState.start_new_career(12345)
	t.eq(GameState.day, 1, "day resets")
	t.eq(GameState.personal_money, 40, "personal money resets")
	t.gt(float(GameState.total_debt()), 400000.0, "career begins in a hole")
	t.gt(float(GameState.daily_debt_payment()), 600.0, "and the hole has a daily rate")

func test_rng_determinism() -> void:
	RNG.reseed(999)
	var a: Array = []
	for i in 20:
		a.append(RNG.randi_range_s("patients", 0, 1000))
	RNG.reseed(999)
	var b: Array = []
	for i in 20:
		b.append(RNG.randi_range_s("patients", 0, 1000))
	t.eq(a, b, "same seed produces same sequence")

func test_rng_streams_are_independent() -> void:
	RNG.reseed(77)
	var first_patient := RNG.randi_range_s("patients", 0, 10000)
	RNG.reseed(77)
	for i in 50:
		RNG.randf_s("chatter")   # burn a different stream
	var again := RNG.randi_range_s("patients", 0, 10000)
	t.eq(first_patient, again, "burning one stream does not desync another")

func test_weighted_pick_respects_zero() -> void:
	RNG.reseed(5)
	for i in 40:
		var k = RNG.pick_weighted("t", {"a": 1.0, "b": 0.0})
		t.ok(k == "a", "zero-weight option is never picked")

func test_gamestate_roundtrip() -> void:
	GameState.start_new_career(4242)
	GameState.add_personal(500, "test")
	GameState.adjust_rep("doctor", 0.2)
	GameState.add_heat(0.3)
	GameState.day = 7
	var d := GameState.to_dict()
	GameState.start_new_career(1)
	GameState.from_dict(d)
	t.eq(GameState.day, 7, "day roundtrips")
	t.eq(GameState.personal_money, 540, "money roundtrips")
	t.near(GameState.rep("doctor"), 0.7, 0.0001, "reputation roundtrips")
	t.near(GameState.heat, 0.3, 0.0001, "heat roundtrips")
