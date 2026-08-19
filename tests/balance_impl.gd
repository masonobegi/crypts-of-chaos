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

## ...and BALANCE_SEEDS=5 to trust the answer more.
##
## One seed per strategy was a coin flip pretending to be a measurement. A
## change that only reshuffled which patients turned up in which order — an
## appointment list that stopped booking the same man four times — moved the
## careless career from $27k to $198k and flipped the premise check, without
## touching a single number in the economy. Anything read off one career is
## noise with a decimal point on it.
var SEEDS := int(OS.get_environment("BALANCE_SEEDS")) if OS.get_environment("BALANCE_SEEDS") != "" else 3

var tree: SceneTree = null
var results: Array[Dictionary] = []
var errors: Array[String] = []

func run_all() -> void:
	for i in SEEDS:
		# Spread out, and deterministic: the same command gives the same answer,
		# but a fix is never validated against one lucky ward.
		var run_seed := 90210 + i * 7919
		for strategy in ["honest", "mild", "careless", "careful"]:
			results.append(_run(strategy, run_seed))

func _run(strategy: String, run_seed: int) -> Dictionary:
	GameState.start_new_career(run_seed)
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
		# Interleaved rather than "run the whole clock, then act". Appointments
		# expire if you are three hours late for them, so a harness that did all
		# of its time first and all of its work afterwards would arrive to find
		# every slot already missed and would be measuring that instead of the
		# design.
		for i in GameState.shift_hours() * 60:
			GameState._advance_minute()
			if GameState.shift_over():
				break
			if i % 30 == 0:
				_work_the_list(game, strategy)
		_work_the_list(game, strategy)
		_act(game, strategy)
		game.shift.end_shift()
		var report: Dictionary = game.shift.clock_out()
		_spend(game, strategy)
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
		"seed": run_seed,
		"days": day_log.size(),
		# What a day of this actually pays. Total earnings reward surviving, so
		# comparing them lets a strategy that gets struck off in a fortnight
		# look modest while being the most profitable thing in the game.
		"per_day": float(GameState.stats.personal_earned) / maxf(float(day_log.size()), 1.0),
		"avg_overstay": _mean_of_log(day_log, "overstay"),
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
		"injury_rate": game.shift.rolling_injury_rate(),
		"injuries": int(GameState.stats.injuries_caused),
		"investigations": game.investigations.closed_investigations.size(),
		"adverse": _count_adverse(game),
		"upgrades": GameState.owned_upgrades.duplicate(),
		"upgrade_count": GameState.owned_upgrades.size(),
		"depts": GameState.unlocked_departments.duplicate(),
		"dept_count": GameState.unlocked_departments.size(),
		"ending": Endings.evaluate(GameState.stats),
		"log": day_log,
	}
	# Remove first, then free: queue_free() leaves the node in the tree for a
	# frame, and this harness never yields a frame between careers.
	tree.root.remove_child(game)
	game.free()
	return out

## Buying priority for the strategies that invest. Deliberately front-loads the
## things that reduce witnesses and raise throughput, which is what a player
## working this line would actually do.
const BUY_ORDER := [
	"union_rep_lunch", "coffee_machine", "better_beds", "shred_bin",
	"private_rooms", "maintenance_contract", "admin_assistant",
	"dept_psych", "legal_retainer", "dept_emergency", "diagnostics",
	"dept_radiology", "second_opinion_policy", "vip_suite", "security_cameras",
	"records_consultant", "board_appointment",
]

func _spend(game, strategy: String) -> void:
	if strategy == "honest":
		return      # the saint reinvests nothing; that is part of being broke
	for id in BUY_ORDER:
		if GameState.has_upgrade(String(id)):
			continue
		if not Upgrades.can_afford(String(id)):
			continue
		Upgrades.purchase(String(id))
		return      # one purchase per shift, like the shop allows

func _mean_of_log(rows: Array, key: String) -> float:
	if rows.is_empty():
		return 0.0
	var total := 0.0
	for r in rows:
		total += float(r.get(key, 0.0))
	return total / float(rows.size())

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
		"mild": _act_mild(game)
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

## Work the booked list. Every strategy attends its appointments — not turning
## up for people is a way to lose that has nothing to do with the crime, and a
## harness that skipped the list would be measuring that instead of the design.
##
## The strategies differ in what happens once the door is shut: honest examines
## at the indicated pressure and sends walk-ins home, careless leans on
## everybody, and careful leans on the ones whose insurance makes it worth the
## risk and files a mechanism immediately afterwards.
func _work_the_list(game, strategy: String) -> void:
	var appts = game.appointments
	if appts == null:
		return
	for e in appts.list.duplicate():
		if e["done"] or e["missed"]:
			continue
		var p = game.patient_system.get_patient(String(e["patient_id"]))
		if p == null or p.discharged:
			continue
		var kind := String(e["kind"])
		if kind == "physical" or kind == "followup":
			_see_them(game, p, strategy)
		elif kind == "surgery":
			_operate(game, p, strategy)
		elif kind == "discharge":
			_send_them_home(game, p, strategy)

## Three stages, done properly, quickly, or badly. Careless improvises all three
## on everybody; careful improvises only where the insurance justifies the risk
## and files a mechanism straight afterwards.
func _operate(game, p, strategy: String) -> void:
	var worth_it: bool = DB.insurance_multiplier(p.insurance) >= 1.5
	var how := "careful"
	if strategy == "careless":
		how = "improvise"
	elif strategy == "careful" and worth_it and p.acquired_injuries().is_empty():
		how = "quick"
	# Always the indicated site. Operating on the wrong part of somebody is a
	# deliberate act rather than a degree of carelessness, and none of these
	# three strategies is "picks a limb at random" — a harness that did it by
	# accident on every operation would be measuring something nobody plays.
	var site := TreatmentSystem.indicated_site_for(p)
	var res: Dictionary = game.treatment.perform_surgery(p, site, [how, how, how])
	if strategy == "careful" and String(res.get("complication", "")) != "":
		for c in p.active_complications():
			if c.documented_cause == "" and c.plausible_causes.size() > 0:
				game.records.document_complication(p, c, String(c.plausible_causes[0]),
					true, Vector3.ZERO, p.room)

## Send them home on the right thing, or on something that brings them back.
func _send_them_home(game, p, strategy: String) -> void:
	var options := DB.prescriptions_for(p.condition_id)
	var med := String(options[0]) if not options.is_empty() else "placebex_takehome"
	if strategy == "mild":
		# Attends the slot, does the examination, and simply has not finished
		# the discharge summary yet. No lie is told.
		if DB.insurance_multiplier(p.insurance) >= 1.5 and p.overdue_days < 1.1:
			return
	if strategy == "careful":
		# Same deferral, but bounded by the record rather than by a day count:
		# the summary is outstanding for exactly as long as the chart explains
		# why they are still here. Without this, the sophisticated strategy
		# handed back every day its own paperwork had bought — the discharge
		# slot discharged unconditionally — and the harness then reported that
		# doing the interesting thing paid worse than doing nothing.
		if DB.insurance_multiplier(p.insurance) >= 1.5 and p.unexplained_overstay() < 0.5:
			return
	if strategy == "careless":
		med = "dual_course"
	elif strategy == "careful" and DB.insurance_multiplier(p.insurance) >= 1.5 \
			and p.acquired_injuries().is_empty() and p.chart.surgery_log.is_empty():
		# Only on somebody nothing else has already been done to.
		med = "placebex_takehome"
	game.treatment.prescribe(p, med)
	game.patient_system.discharge(p, "discharged")

func _see_them(game, p, strategy: String) -> void:
	var worth_it: bool = DB.insurance_multiplier(p.insurance) >= 1.5
	var pressure: int = TreatmentSystem.EXAM_INDICATED
	match strategy:
		"careless":
			pressure = TreatmentSystem.EXAM_DIAL_MAX
		"careful":
			# One angle per patient, not three. A careful cheater who leans on
			# somebody in clinic AND improvises their operation AND sends them
			# home on the wrong thing is not a careful cheater, and a harness
			# that models it that way is measuring recklessness.
			# And the lowest pressure that has any chance at all, not the
			# highest that might work. The difference is entirely in how
			# obvious it looks to whoever is standing there.
			if worth_it and not p.admitted:
				pressure = TreatmentSystem.EXAM_INDICATED + 3
	var res: Dictionary = game.treatment.examine(p, String(RNG.pick("bal_part",
		["wrist", "ankle", "shoulder", "knee"])), pressure, Vector3.ZERO)

	# Paperwork, immediately, for anyone who does paperwork.
	if strategy == "careful" and String(res.get("injury", "")) != "":
		for c in p.acquired_injuries():
			if c.documented_cause == "" and c.plausible_causes.size() > 0:
				game.records.document_complication(p, c, String(c.plausible_causes[0]),
					true, Vector3.ZERO, p.room)

	if p.admitted:
		return
	# A walk-in with something wrong with them is an admission. A walk-in with
	# nothing wrong with them is a consultation fee and a wave goodbye.
	var found: bool = not p.acquired_injuries().is_empty()
	if found and not game.patient_system.free_wards().is_empty():
		game.patient_system.admit(p)
	else:
		game.patient_system.send_home(p, "cleared")

## The line almost everybody actually walks.
##
## Nobody is hurt. Nothing is forged. Every treatment is the indicated one at
## the indicated setting and every chart is true. The only thing this doctor
## does is fail to be in a hurry about the paperwork on people whose insurance
## is good, and let them have another night.
##
## It exists in the harness because the brief asks for four rungs and the design
## only had three: honest should be hard survival, THIS should be comfortable,
## reckless should be briefly rich, and sophisticated should be rich and
## difficult. Without a mild run measured, "comfortable" was an aspiration
## nobody had checked.
func _act_mild(game) -> void:
	var machines: Array = []
	for f in tree.get_nodes_in_group("fixture"):
		if f is TreatmentMachine:
			machines.append(f)
	for p in game.patient_system.active():
		var treated := false
		for m in machines:
			if m.room_key != p.room or not DB.is_correct_treatment(p.condition_id, m.treatment_id):
				continue
			m.set_prescribed_for(p)
			m.dial = m.prescribed
			game.treatment.run_machine(m, p)
			game.records.log_real_treatment(p, m.treatment_id)
			treated = true
		if not treated:
			var correct: Array = DB.correct_treatments(p.condition_id)
			if not correct.is_empty():
				var tid := String(correct[0])
				game.treatment.apply(p, tid, null, Vector3.ZERO)
				game.records.log_real_treatment(p, tid)
		if p.recovery < 0.98:
			continue
		# The whole strategy, in one condition: a bed worth having keeps them
		# one more night, a bed that is not worth having is freed at once.
		if DB.insurance_multiplier(p.insurance) < 1.5 or p.overdue_days >= 1.1:
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
			continue
		# And an expensive one stays exactly as long as the RECORD justifies.
		#
		# This used to be a flat two days past projection, which is not the
		# sophisticated line, it is the mild line with extra steps: it threw
		# away the days a documented complication legitimately buys and then
		# wondered why causing one paid worse than doing nothing. Hold until the
		# paperwork stops covering it, and not one night longer.
		if p.unexplained_overstay() >= 0.5:
			game.treatment.attempt_discharge(p)

# ------------------------------------------------------------------ report
## Mean of one numeric field across every career a strategy played.
func mean(strategy: String, key: String) -> float:
	var total := 0.0
	var n := 0
	for r in results:
		if String(r["strategy"]) != strategy:
			continue
		total += float(r.get(key, 0))
		n += 1
	return total / maxf(float(n), 1.0)

## Biggest across the seeds. Used where the question is "can this strategy ever
## do X" rather than "does it usually" — reinvestment, departments, adverse
## findings.
func best(strategy: String, key: String) -> float:
	var out := -INF
	for r in results:
		if String(r["strategy"]) == strategy:
			out = maxf(out, float(r.get(key, 0)))
	return 0.0 if out == -INF else out

func runs_of(strategy: String) -> Array:
	var out: Array = []
	for r in results:
		if String(r["strategy"]) == strategy:
			out.append(r)
	return out

func report() -> void:
	print("\n=== BALANCE REPORT (%d days each, %d seeds) ===\n" % [DAYS, SEEDS])
	for strategy in ["honest", "mild", "careless", "careful"]:
		var runs := runs_of(strategy)
		if runs.is_empty():
			continue
		print("--- %s  (mean of %d careers) ---" % [strategy.to_upper(), runs.size()])
		print("  survived        : %.1f days" % mean(strategy, "days"))
		print("  personal money  : %s   (earned %s, %s per day)" % [
			_money(int(mean(strategy, "final_personal"))),
			_money(int(mean(strategy, "earned"))),
			_money(int(mean(strategy, "per_day")))])
		print("  standing        : sanction %.1f   heat %.0f%%" % [
			mean(strategy, "sanction"), mean(strategy, "heat") * 100.0])
		print("  complication/dc : %.2f   injuries/shift %.3f   (baselines 0.34 / %.2f)" % [
			mean(strategy, "comp_rate"), mean(strategy, "injury_rate"),
			SuspicionSystem.BASELINE_INJURY_RATE])
		print("  institutions    : admin %.0f%%   insurer %.0f%%   unexplained stay %.2f d" % [
			mean(strategy, "admin_sus") * 100.0, mean(strategy, "insurer_sus") * 100.0,
			mean(strategy, "avg_overstay")])
		print("  adverse findings: %.1f     witnessed %.0f    complaints %.0f" % [
			mean(strategy, "adverse"), mean(strategy, "witnessed"),
			mean(strategy, "complaints")])
		var per_seed: Array[String] = []
		for r in runs:
			per_seed.append("%d:%s/%dd%s" % [int(r["seed"]), _money(int(r["final_personal"])),
				int(r["days"]), "" if String(r["ending"]) == "tycoon" else " " + String(r["ending"])])
		print("  by seed         : %s" % "   ".join(per_seed))
		print("")

	print("=== worked example (first seed) ===\n")
	for r in results.slice(0, 4):
		print("--- %s ---" % String(r["strategy"]).to_upper())
		print("  survived        : %d days   (ending: %s)" % [int(r["days"]), String(r["ending"])])
		print("  personal money  : %s   (earned %s)" % [
			_money(int(r["final_personal"])), _money(int(r["earned"]))])
		print("  debt remaining  : %s" % _money(int(r["final_debt"])))
		print("  standing        : %s   heat %.0f%%" % [String(r["sanction_name"]), float(r["heat"]) * 100.0])
		print("  institutions    : admin %.0f%%   insurer %.0f%%" % [
			float(r["admin_sus"]) * 100.0, float(r["insurer_sus"]) * 100.0])
		print("  complication/dc : %.2f   (ward baseline 0.34)" % float(r["comp_rate"]))
		print("  ward injuries   : %d caused, rate %.3f per patient-shift (baseline %.2f)" % [
			int(r.get("injuries", 0)), float(r.get("injury_rate", -1.0)),
			SuspicionSystem.BASELINE_INJURY_RATE])
		print("  investigations  : %d closed, %d adverse" % [
			int(r["investigations"]), int(r["adverse"])])
		print("  bought          : %s" % ", ".join(PackedStringArray(r["upgrades"])))
		print("  departments     : %s" % ", ".join(PackedStringArray(r["depts"])))
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
	print("--- design intent ---")
	# Everything below is a MEAN across seeds. A single career is noise: the
	# same code answered "$27k" and "$198k" for the same strategy depending only
	# on which patients happened to turn up.
	# The design claim is not "honest earns under N dollars" — that has to be
	# retuned every time the career length changes and says nothing. It is that
	# you cannot make a living here being good: the debt is $435,400 and an
	# honest doctor never gets near it, at any length of career.
	_check(mean("honest", "per_day") < mean("careful", "per_day") * 0.35,
		"an honest doctor cannot make a living here")
	_check(mean("honest", "final_personal") < 435400.0 * 0.1,
		"and never gets within sight of the debt")
	_check(mean("honest", "rep_doctor") >= mean("careless", "rep_doctor"),
		"honest play earns better standing than careless cheating")
	_check(mean("careless", "sanction") > mean("honest", "sanction"),
		"careless cheating gets punished harder than honesty")
	_check(mean("careless", "witnessed") > mean("careful", "witnessed"),
		"careless cheating is seen more often than careful cheating")
	_check(mean("careful", "earned") > mean("honest", "earned"),
		"careful cheating out-earns honest practice (the premise of the game)")
	# Per DAY, not per career. Total earnings quietly reward surviving, so a
	# strategy that makes a fortune and is struck off in a fortnight reads as
	# modest — which is exactly backwards, because the player experiences the
	# rate, not the total. Reckless play out-earning sophisticated play per day
	# means the game's answer to "how should I do this?" is "badly, quickly".
	_check(mean("careful", "per_day") > mean("careless", "per_day"),
		"sophisticated cheating pays better by the day than reckless cheating")
	# The four rungs the brief asks for, in order, by the day.
	_check(mean("mild", "per_day") > mean("honest", "per_day") * 1.4,
		"a mild cheat is meaningfully better off than an honest one")
	_check(mean("careful", "per_day") > mean("mild", "per_day"),
		"and going further pays further")
	_check(mean("mild", "sanction") <= 0.5 and mean("mild", "adverse") < 1.0,
		"mild cheating is genuinely comfortable — nobody comes for you")
	_check(mean("careless", "days") < mean("careful", "days") * 0.85,
		"reckless practice ends, and visibly sooner")
	_check(mean("careful", "sanction") < mean("careless", "sanction"),
		"careful cheating stays further from the ladder than careless")
	_check(mean("careful", "clean") > mean("careless", "clean"),
		"careful play actually produces clean paperwork")
	_check(mean("careful", "heat") < mean("careless", "heat"),
		"careful cheating runs cooler than careless cheating")
	_check(mean("honest", "comp_rate") <= 0.34,
		"an honest ward sits at or under the baseline complication rate")
	_check(mean("careless", "comp_rate") > 0.34 * 3.0
			or mean("careless", "injury_rate") > 0.06,
		"a careless ward is a glaring statistical outlier")
	# The injury statistic exists precisely so that filling every bed with
	# people you hurt and discharging nobody cannot switch the numbers off.
	_check(mean("careless", "injury_rate") > mean("honest", "injury_rate"),
		"and hurting people shows up in the ward-acquired injury rate")
	_check(mean("careful", "insurer_sus") > mean("honest", "insurer_sus"),
		"careful cheating still accumulates insurer attention — safe, not invisible")
	_check(mean("careful", "adverse") < mean("careless", "adverse"),
		"careful play survives its investigations better than careless play")
	_check(best("careful", "upgrade_count") >= 4.0,
		"a profitable career can actually afford to reinvest")
	_check(best("careful", "dept_count") > 1.0,
		"and reaches at least one new department")
	print("")

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   %s" % msg)
	else:
		errors.append(msg)
		print("  FAIL %s" % msg)
