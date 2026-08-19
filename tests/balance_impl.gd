extends RefCounted
## Headless balance harness. Plays several full careers with different
## strategies through the REAL systems (not a re-implementation of the formulas)
## and reports whether the intended tension actually exists:
##
##   * an honest doctor should be respected and broke
##   * a careless cheater should get rich briefly and then get caught
##   * a careful cheater should be the interesting middle
##
## If honest play services the debt, the whole premise is broken.

## Override with BALANCE_DAYS=30 to probe the mid/late game.
var DAYS := int(OS.get_environment("BALANCE_DAYS")) if OS.get_environment("BALANCE_DAYS") != "" else 16

var tree: SceneTree = null
var results: Array[Dictionary] = []
var errors: Array[String] = []

func run_all() -> void:
	for strategy in ["honest", "careless", "careful"]:
		results.append(_run(strategy))

func _run(strategy: String) -> Dictionary:
	GameState.start_new_career(90210)
	GameState.set_flag("headless_sim", true)
	var packed: PackedScene = load("res://scenes/Game.tscn")
	var game: Node = packed.instantiate()
	tree.root.add_child(game)
	tree.paused = false

	var day_log: Array[Dictionary] = []
	var caught_on := -1

	for day in DAYS:
		game.shift.clock_in()
		# Run the shift's worth of minutes.
		for i in GameState.SHIFT_HOURS * 60:
			GameState._advance_minute()
			if GameState.shift_over():
				break
		_act(game, strategy)
		game.shift.end_shift()
		var report: Dictionary = game.shift.clock_out()
		day_log.append({
			"day": GameState.day,
			"personal": GameState.personal_money,
			"hospital": GameState.hospital_money,
			"take_home": int(report.get("statement", {}).get("take_home", 0)),
			"heat": GameState.heat,
			"sanction": GameState.sanction_level,
			"census": game.patient_system.active_count(),
			"overstay": game.patient_system.average_overstay(),
			"debt": GameState.total_debt(),
		})
		if caught_on < 0 and GameState.sanction_level >= 4:
			caught_on = GameState.day
		game.shift.next_day()
		if GameState.phase == GameState.Phase.GAME_OVER:
			break

	var out := {
		"strategy": strategy,
		"days": day_log.size(),
		"final_personal": GameState.personal_money,
		"final_debt": GameState.total_debt(),
		"start_debt": 435400,
		"heat": GameState.heat,
		"sanction": GameState.sanction_level,
		"sanction_name": GameState.SANCTIONS[GameState.sanction_level],
		"cured": int(GameState.stats.patients_cured),
		"complications": int(GameState.stats.complications_caused),
		"clean": int(GameState.stats.complications_clean),
		"forged": int(GameState.stats.forged_entries),
		"witnessed": int(GameState.stats.witnessed_acts),
		"complaints": int(GameState.stats.complaints),
		"earned": int(GameState.stats.personal_earned),
		"rep_doctor": GameState.rep("doctor"),
		"rep_patient": GameState.rep("patient_sat"),
		"caught_on": caught_on,
		"admin_sus": game.suspicion.suspicion_of("admin"),
		"insurer_sus": game.suspicion.suspicion_of("insurer"),
		"comp_rate": game.shift.rolling_complication_rate(),
		"investigations": game.investigations.closed_investigations.size(),
		"adverse": _count_adverse(game),
		"ending": Endings.evaluate(GameState.stats),
		"log": day_log,
	}
	# Remove first, then free: queue_free() leaves the node in the tree for a
	# frame, and this harness never yields a frame between careers.
	tree.root.remove_child(game)
	game.free()
	return out

func _count_adverse(game) -> int:
	var n := 0
	for inv in game.investigations.closed_investigations:
		if inv.outcome == "adverse":
			n += 1
	return n

# ------------------------------------------------------------------ strategies
func _act(game, strategy: String) -> void:
	match strategy:
		"honest": _act_honest(game)
		"careless": _act_careless(game)
		"careful": _act_careful(game)

## Treat everyone correctly, chart everything, discharge as soon as they're well.
func _act_honest(game) -> void:
	for p in game.patient_system.active():
		var correct: Array = DB.correct_treatments(p.condition_id)
		if correct.is_empty():
			continue
		var tid := String(correct[0])
		game.treatment.apply(p, tid, null, Vector3.ZERO)
		game.records.log_real_treatment(p, tid)
		for c in p.active_complications():
			if c.documented_cause == "" and c.plausible_causes.size() > 0:
				game.records.document_complication(p, c, String(c.plausible_causes[0]),
					true, Vector3.ZERO, p.room)
		if p.recovery >= 0.98:
			game.treatment.attempt_discharge(p)

## Crank every machine, document nothing, bill for everything.
func _act_careless(game) -> void:
	var machines: Array = []
	for f in tree.get_nodes_in_group("fixture"):
		if f is TreatmentMachine:
			machines.append(f)
	for p in game.patient_system.active():
		for m in machines:
			if m.room_key != p.room:
				continue
			m.set_prescribed_for(p)
			m.dial = clampi(m.prescribed + 6, 0, 11)
			if absi(m.dial - m.prescribed) < 5:
				m.dial = clampi(m.prescribed - 6, 0, 11)
			game.treatment.run_machine(m, p)
		game.records.log_phantom_treatment(p, "rest", false, Vector3.ZERO, p.room)

## Run a genuinely good ward, and work the angles only on patients worth it.
##
## Low-value patients get correct treatment and go home the moment they are well
## — that is what buys the reputation that brings better-insured patients in.
## High-value patients get a one-notch deviation, immediate paperwork, and an
## extra couple of days. This is the line the game is designed around.
func _act_careful(game) -> void:
	var machines: Array = []
	for f in tree.get_nodes_in_group("fixture"):
		if f is TreatmentMachine:
			machines.append(f)
	for p in game.patient_system.active():
		var worth_it: bool = DB.insurance_multiplier(p.insurance) >= 1.5
		var treated := false
		for m in machines:
			# Only use a machine that is actually indicated — using the wrong one
			# is as visible as hitting someone with the wrong tool.
			if m.room_key != p.room or not DB.is_correct_treatment(p.condition_id, m.treatment_id):
				continue
			m.set_prescribed_for(p)
			m.dial = clampi(m.prescribed + (2 if worth_it else 0), 0, 11)
			game.treatment.run_machine(m, p)
			game.records.log_real_treatment(p, m.treatment_id)
			treated = true
		if not treated:
			var correct: Array = DB.correct_treatments(p.condition_id)
			if not correct.is_empty():
				var tid := String(correct[0])
				game.treatment.apply(p, tid, null, Vector3.ZERO)
				game.records.log_real_treatment(p, tid)
		# Paperwork first, every time, before anyone has a chance to notice.
		for c in p.active_complications():
			if c.documented_cause == "" and c.plausible_causes.size() > 0:
				game.records.document_complication(p, c, String(c.plausible_causes[0]),
					true, Vector3.ZERO, p.room)
		if p.recovery < 0.98:
			continue
		# Cheap patients go home immediately; that is what protects the numbers.
		if not worth_it:
			game.treatment.attempt_discharge(p)
		elif p.days_admitted > p.expected_stay_days + 2.0:
			game.treatment.attempt_discharge(p)

# ------------------------------------------------------------------ report
func report() -> void:
	print("\n=== BALANCE REPORT (%d days each, seed 90210) ===\n" % DAYS)
	for r in results:
		print("--- %s ---" % String(r["strategy"]).to_upper())
		print("  survived        : %d days   (ending: %s)" % [int(r["days"]), String(r["ending"])])
		print("  personal money  : %s   (earned %s)" % [
			_money(int(r["final_personal"])), _money(int(r["earned"]))])
		print("  debt remaining  : %s" % _money(int(r["final_debt"])))
		print("  standing        : %s   heat %.0f%%" % [String(r["sanction_name"]), float(r["heat"]) * 100.0])
		print("  institutions    : admin %.0f%%   insurer %.0f%%" % [
			float(r["admin_sus"]) * 100.0, float(r["insurer_sus"]) * 100.0])
		print("  complication/dc : %.2f   (ward baseline 0.34)" % float(r["comp_rate"]))
		print("  investigations  : %d closed, %d adverse" % [
			int(r["investigations"]), int(r["adverse"])])
		print("  patients cured  : %d" % int(r["cured"]))
		print("  complications   : %d caused, %d filed cleanly" % [
			int(r["complications"]), int(r["clean"])])
		print("  forged entries  : %d   witnessed %d times   %d complaints" % [
			int(r["forged"]), int(r["witnessed"]), int(r["complaints"])])
		print("  reputation      : doctor %.2f   patients %.2f" % [
			float(r["rep_doctor"]), float(r["rep_patient"])])
		if int(r["caught_on"]) > 0:
			print("  first serious sanction on day %d" % int(r["caught_on"]))
		print("  money by day    : %s" % _sparkline(r["log"]))
		print("")
	_assert_design_intent()

func _money(v: int) -> String:
	return ("-$" if v < 0 else "$") + str(absi(v))

func _sparkline(log_rows: Array) -> String:
	var parts: Array[String] = []
	for row in log_rows:
		parts.append(str(int(float(row["personal"]) / 100.0)))
	return " ".join(parts) + "   (hundreds of $)"

## The balance targets. These are assertions about the DESIGN, not the code:
## if they fail, the game's premise is not working and the numbers need moving.
func _assert_design_intent() -> void:
	var by: Dictionary = {}
	for r in results:
		by[String(r["strategy"])] = r
	var honest: Dictionary = by.get("honest", {})
	var careless: Dictionary = by.get("careless", {})
	var careful: Dictionary = by.get("careful", {})

	print("--- design intent ---")
	_check(int(honest.get("final_personal", 0)) < 4000,
		"an honest doctor cannot get comfortable (personal money stays low)")
	_check(float(honest.get("rep_doctor", 0.0)) >= float(careless.get("rep_doctor", 1.0)),
		"honest play earns better standing than careless cheating")
	_check(int(careless.get("sanction", 0)) > int(honest.get("sanction", 0)),
		"careless cheating gets punished harder than honesty")
	_check(int(careless.get("witnessed", 0)) > int(careful.get("witnessed", 0)),
		"careless cheating is seen more often than careful cheating")
	_check(int(careful.get("earned", 0)) > int(honest.get("earned", 0)),
		"careful cheating out-earns honest practice (the premise of the game)")
	_check(int(careful.get("sanction", 0)) < int(careless.get("sanction", 0)),
		"careful cheating stays further from the ladder than careless")
	_check(int(careful.get("clean", 0)) > int(careless.get("clean", 0)),
		"careful play actually produces clean paperwork")
	_check(float(careful.get("heat", 1.0)) < float(careless.get("heat", 0.0)),
		"careful cheating runs cooler than careless cheating")
	_check(float(honest.get("comp_rate", 1.0)) <= 0.34,
		"an honest ward sits at or under the baseline complication rate")
	_check(float(careless.get("comp_rate", 0.0)) > 0.34 * 3.0,
		"a careless ward is a glaring statistical outlier")
	_check(float(careful.get("insurer_sus", 0.0)) > float(honest.get("insurer_sus", 1.0)),
		"careful cheating still accumulates insurer attention — safe, not invisible")
	_check(int(careful.get("adverse", 99)) == 0 and int(careless.get("adverse", 0)) > 0,
		"careful play survives its investigations and careless play does not")
	print("")

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   %s" % msg)
	else:
		errors.append(msg)
		print("  FAIL %s" % msg)
