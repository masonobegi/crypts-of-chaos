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
	t.eq(GameState.personal_money, 820, "personal money resets")
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
	t.eq(GameState.personal_money, 1320, "money roundtrips")
	t.near(GameState.rep("doctor"), 0.7, 0.0001, "reputation roundtrips")
	t.near(GameState.heat, 0.3, 0.0001, "heat roundtrips")

func test_day_one_is_survivable() -> void:
	# The first briefing must not be a wall of missed payments for things the
	# player has not yet had a chance to do anything about.
	GameState.start_new_career(11)
	t.gt(float(GameState.personal_money), float(GameState.daily_debt_payment()),
		"starting money covers the first day's debts")
	t.lt(float(GameState.personal_money), float(GameState.daily_debt_payment()) * 2.0,
		"but not the second — the squeeze arrives on day two")

func test_missing_rent_repeatedly_ends_the_career() -> void:
	# This path existed but its counter was never incremented, so eviction was
	# unreachable and the bankrupt ending could not occur.
	GameState.start_new_career(12)
	GameState.personal_money = 0
	t.eq(int(GameState.flag("missed_rent_days", 0)), 0, "starts with no missed rent")
	var eco := EconomySystem.new()
	for i in 4:
		eco.settle_debts()
	t.eq(int(GameState.flag("missed_rent_days", 0)), 4, "four missed rent days are counted")
	eco.free()

func test_paying_rent_resets_the_counter() -> void:
	GameState.start_new_career(13)
	GameState.personal_money = 0
	var eco := EconomySystem.new()
	eco.settle_debts()
	t.eq(int(GameState.flag("missed_rent_days", 0)), 1, "one missed day")
	GameState.personal_money = 20000
	eco.settle_debts()
	t.eq(int(GameState.flag("missed_rent_days", 0)), 0, "paying up clears the streak")
	eco.free()

# ==================================================================== meta
func test_perks_are_locked_until_their_ending_is_reached() -> void:
	Meta.reset()
	t.eq(Meta.unlocked_perks().size(), 0, "nothing unlocked on a fresh install")
	t.ok(not Meta.is_unlocked("retainer"), "the retainer perk is locked")
	Meta.record_ending("tycoon")
	t.ok(Meta.is_unlocked("retainer"), "reaching Tycoon unlocks it")
	t.ok(not Meta.is_unlocked("good_name"), "but not the others")
	t.eq(Meta.runs_completed, 1, "the career is counted")

func test_every_perk_is_reachable_from_a_real_ending() -> void:
	# A perk whose source ending does not exist can never be unlocked.
	for id in Meta.PERKS:
		var source := Meta.perk_source(String(id))
		t.ok(Endings.ENDINGS.has(source),
			"perk '%s' comes from a real ending ('%s')" % [id, source])

func test_selecting_a_locked_perk_does_nothing() -> void:
	Meta.reset()
	Meta.select_perk("retainer")
	t.eq(Meta.selected_perk, "", "a locked perk cannot be selected")

func test_perks_actually_change_the_starting_state() -> void:
	Meta.reset()
	Meta.record_ending("bankrupt")
	Meta.select_perk("consolidated")
	GameState.start_new_career(31)
	var full := GameState.daily_debt_payment()
	Meta.apply_perk()
	t.lt(float(GameState.daily_debt_payment()), float(full) * 0.85,
		"Consolidated Debt genuinely lowers the daily outflow")

	Meta.reset()
	Meta.record_ending("tycoon")
	Meta.select_perk("retainer")
	GameState.start_new_career(32)
	Meta.apply_perk()
	t.ok(GameState.has_upgrade("legal_retainer"), "the retainer perk grants the upgrade")

	Meta.reset()
	Meta.record_ending("prison")
	Meta.select_perk("a_friend")
	GameState.start_new_career(33)
	var before := GameState.personal_money
	Meta.apply_perk()
	t.eq(GameState.personal_money, before + 2000, "A Friend Outside pays out")
	Meta.reset()
	GameState.start_new_career(1)

func test_meta_survives_a_save_and_load() -> void:
	Meta.reset()
	Meta.record_ending("saint")
	Meta.record_ending("saint")
	Meta.select_perk("good_name")
	Meta.load_meta()
	t.eq(int(Meta.endings_seen.get("saint", 0)), 2, "repeat endings are counted")
	t.eq(Meta.selected_perk, "good_name", "the chosen perk persists")
	t.eq(Meta.runs_completed, 2, "career count persists")
	Meta.reset()
