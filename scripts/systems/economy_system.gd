class_name EconomySystem
extends Node
## Hospital revenue, hospital costs, your cut, and the debts that make the whole
## thing tempting in the first place.
##
## The debt schedule is tuned so a scrupulously honest doctor cannot service it
## on the base bonus. The game never tells you to cheat; the arithmetic does.

## Per shift, before bonus.
##
## Raised from 240 when admission workups were folded into the profit the share
## is computed on — a correction that was right (the statement printed the line
## as a cost and then left it out of the total underneath) and that cut the
## honest doctor's income by about forty per cent, from scraping by to bankrupt
## on day fifteen. "Honest is hard" is the premise; "honest is not a playstyle"
## is a missing playstyle.
##
## A wage is the right place to put that floor back, because it is the one
## income a doctor has that does not depend on what happens to the patients —
## so it keeps an honest career alive and is a rounding error to a rich one. It
## is also still hopeless: fifteen thousand a month against four hundred and
## thirty-five thousand of debt is the whole reason any of this starts.
const BASE_SALARY := 520
const STAFF_COST_PER_HEAD := 210
const UTILITIES_BASE := 180
const SUPPLY_COST_PER_PATIENT := 55
const REPAIR_COST := 140
## One-off cost of taking someone in: intake, workup, the whole circus.
##
## This number is why the game works. Without it, curing people fast and
## refilling the bed out-earns prolonging a stay — the ward only has five beds,
## so throughput beats duration and the entire premise inverts. Making admission
## expensive and marginal days cheap is what makes "keep Greg here" the
## profitable play, and it is the single most load-bearing constant in the game.
const ADMISSION_COST := 850

var patient_system: PatientSystem = null
var last_statement: Dictionary = {}

var admissions_today := 0

func _ready() -> void:
	add_to_group("economy")
	patient_system = get_tree().get_first_node_in_group("patient_system")
	EventBus.item_broke.connect(_on_item_broke)
	EventBus.patient_admitted.connect(_on_admitted)
	EventBus.clock_tick.connect(_on_clock_tick)

func _on_admitted(_p) -> void:
	admissions_today += 1
	GameState.add_hospital(-ADMISSION_COST, "admission workup")

func _on_item_broke(_item) -> void:
	GameState.add_hospital(-REPAIR_COST, "repairs")
	GameState.adjust_rep("hospital", -0.004)

# ------------------------------------------------------------------ daily
## What each bed has already been billed for today, patient id -> amount.
##
## Bed days used to arrive as one lump at clock-out. Four scripted playthroughs
## — honest, reckless, careful and opportunist — all reported the same thing:
## `money  you $125   hospital $7,750` at the start, and the identical figure at
## the end. Nothing the player did to anybody moved a number they could see
## while they were doing it. The one mechanic the entire game is about paid out
## after the player had stopped playing.
##
## Procedure fees have always been billed the moment the work is done, under a
## comment reading "the whole point of a booked list is that you can watch it
## add up". Beds are the business model; they get the same treatment.
var billed_today := {}

## Every quarter of an in-game hour, which at the current time scale is about
## thirty-four real seconds. Hourly was the obvious choice and it is far too
## coarse to feel: eight movements across a whole shift, two and a bit minutes
## apart. A number that only changes twice in the time it takes to walk the
## corridor is not feedback.
const BILL_EVERY_MINUTES := 15

func _on_clock_tick(minute: int) -> void:
	if minute % BILL_EVERY_MINUTES == 0:
		bill_interval()

## A slice of every occupied bed. Called while the shift runs.
func bill_interval() -> void:
	if GameState.phase != GameState.Phase.SHIFT:
		return
	var total := 0
	var beds := 0
	for p in patient_system.active():
		var so_far: int = int(billed_today.get(p.id, 0))
		var day_rate := p.daily_revenue()
		# A day is 1440 minutes, so a quarter hour is a ninety-sixth of it — and
		# it can never take a patient past their own daily rate, which is what
		# keeps the day's total identical to the lump this replaced.
		var slice := mini(int(round(float(day_rate) * float(BILL_EVERY_MINUTES) / 1440.0)),
			day_rate - so_far)
		if slice <= 0:
			continue
		billed_today[p.id] = so_far + slice
		total += slice
		beds += 1
	if total <= 0:
		return
	# One movement, not five. The ledger is per patient and the statement
	# itemises it; the thing on screen every half minute is the ward, because
	# five separate lines every thirty seconds is not a readout, it is weather.
	GameState.add_hospital(total, "%d bed%s occupied" % [beds, "" if beds == 1 else "s"])
	earned_today += total

## Bill every occupied bed for whatever the hours have not already covered.
## This is where a longer stay becomes money.
func bill_day() -> Dictionary:
	var lines: Array[Dictionary] = []
	var revenue := 0
	for p in patient_system.active():
		var amount := p.daily_revenue()
		var already: int = int(billed_today.get(p.id, 0))
		revenue += amount
		GameState.stats.days_billed += 1
		lines.append({
			"label": "%s — %s (%s)" % [p.display_name, p.condition_name(),
				DB.insurance_name(p.insurance)],
			"amount": amount,
			"overdue": p.is_overdue(),
		})
		var owed := amount - already
		if owed > 0:
			GameState.add_hospital(owed, "%s — rest of the day" % p.display_name)
	billed_today.clear()
	earned_today = 0
	return {"revenue": revenue, "lines": lines}

## A one-off procedure fee: consultations, reviews, operations, discharges.
## Billed the moment the work is done rather than at the end of the day, because
## the whole point of a booked list is that you can watch it add up.
var procedure_fees: int = 0
## Every fee and every theatre cost, in the order they happened.
##
## `procedure_fees` was a single total, so the shift report printed a BILLING
## block of bed lines and then a Revenue row that included the whole appointment
## economy — fees, clinic overheads, theatre time — with nothing itemising it.
## The block visibly did not sum to the number underneath it, and the entire
## day's list of appointments was invisible on the one screen that reports the
## day.
var procedure_lines: Array[Dictionary] = []

func bill_procedure(label: String, amount: int) -> void:
	if amount <= 0:
		return
	procedure_fees += amount
	earned_today += amount
	procedure_lines.append({"label": label, "amount": amount})
	GameState.add_hospital(amount, label)

func bill_procedure_cost(label: String, amount: int) -> void:
	if amount <= 0:
		return
	procedure_fees -= amount
	earned_today -= amount
	procedure_lines.append({"label": label, "amount": -amount})
	GameState.add_hospital(-amount, label)

func staff_count() -> int:
	return get_tree().get_nodes_in_group("staff").size()

func daily_costs() -> Dictionary:
	var staff := staff_count() * STAFF_COST_PER_HEAD
	var utilities := UTILITIES_BASE + int(GameState.owned_upgrades.size()) * 35
	var supplies := patient_system.active_count() * SUPPLY_COST_PER_PATIENT
	var admissions := admissions_today * ADMISSION_COST
	var total := staff + utilities + supplies
	return {
		"staff": staff, "utilities": utilities, "supplies": supplies,
		"admissions": admissions, "total": total,
	}

## Your cut. Improved by upgrades and by the hospital actually being profitable —
## which is why running a genuinely good ward is a viable strategy, not a joke.
## What your cut of the shift is worth SO FAR, for the HUD.
##
## The player's own money did not move once during an entire shift in any of the
## four playstyle runs — the crime pays at clock-out and nowhere else, so the
## thing you are actually trying to survive was a static number in the corner
## while you played. This is not a payment; it is the running total the payment
## will be computed from, which is the feedback that was missing. The money
## still lands at clock-out, and the statement is still the reveal.
var earned_today := 0

func take_so_far() -> int:
	return compute_bonus(earned_today)

func compute_bonus(profit: int) -> int:
	if profit <= 0:
		return 0
	var rate := GameState.bonus_rate
	rate += GameState.rep("hospital") * 0.05
	rate += GameState.rep("doctor") * 0.03
	return int(round(float(profit) * rate))

## The full end-of-shift statement.
func close_shift() -> Dictionary:
	var billing := bill_day()
	var costs := daily_costs()
	var fees := procedure_fees
	# Taken before the reset, or the report itemises an empty list.
	var fee_lines := procedure_lines.duplicate(true)
	procedure_fees = 0
	procedure_lines.clear()
	# Admissions are in the printed cost stack and were left out of the profit
	# printed directly underneath it, so the statement did not add up — and,
	# worse, the player's profit share was computed on the inflated figure. The
	# hospital's CASH was always right (ADMISSION_COST is debited when somebody
	# is admitted); it was the number on the page, and the one the bonus runs
	# on, that never saw it.
	var profit: int = int(billing["revenue"]) + fees \
		- int(costs["total"]) - int(costs["admissions"])
	GameState.add_hospital(-int(costs["total"]), "operating costs")

	var bonus := compute_bonus(profit)
	# Unsocial hours pay a premium. It is the only part of the night shift that
	# is straightforwardly good for you.
	var salary := int(round(float(BASE_SALARY) * float(GameState.shift_spec().get("pay", 1.0))))
	GameState.add_personal(salary, "salary (%s)" % DB.shift_name(GameState.shift_kind))
	if bonus > 0:
		GameState.add_personal(bonus, "profit share")

	admissions_today = 0
	last_statement = {
		"revenue": int(billing["revenue"]) + fees,
		"bed_revenue": billing["revenue"],
		"procedure_fees": fees,
		"lines": billing["lines"],
		"procedure_lines": fee_lines,
		"costs": costs,
		"profit": profit,
		"salary": salary,
		"shift": DB.shift_name(GameState.shift_kind),
		"bonus": bonus,
		"take_home": salary + bonus,
	}
	return last_statement

# ------------------------------------------------------------------ debts
## Deducted every morning whether you have it or not. Missing a payment
## escalates — and one of your creditors is not a bank.
func settle_debts() -> Dictionary:
	var paid: Array[Dictionary] = []
	var missed: Array[Dictionary] = []
	for d in GameState.debts:
		var due := int(d.get("daily", 0))
		if due <= 0:
			continue
		if GameState.personal_money >= due:
			GameState.add_personal(-due, String(d.get("name", "debt")))
			d["amount"] = maxi(0, int(d.get("amount", 0)) - due)
			d["missed"] = 0
			if String(d.get("id", "")) == "rent":
				GameState.set_flag("missed_rent_days", 0)
			paid.append({"name": d.get("name", ""), "amount": due,
				"remaining": d.get("amount", 0)})
		else:
			d["missed"] = int(d.get("missed", 0)) + 1
			# Consecutive missed rent is the one that ends a career rather than
			# just costing money.
			if String(d.get("id", "")) == "rent":
				GameState.set_flag("missed_rent_days",
					int(GameState.flag("missed_rent_days", 0)) + 1)
			# Interest, penalties, and in one case a phone call.
			d["amount"] = int(float(d.get("amount", 0)) * 1.04) + 60
			d["daily"] = int(float(d.get("daily", 0)) * 1.06)
			missed.append({"name": d.get("name", ""), "amount": due,
				"missed": d["missed"], "id": d.get("id", "")})
	EventBus.money_changed.emit(GameState.personal_money, GameState.hospital_money)
	return {"paid": paid, "missed": missed}

## Narrative consequence of missing payments. Vinnie is not a bank.
func debt_pressure_lines(missed: Array) -> Array[String]:
	var out: Array[String] = []
	for m in missed:
		var id := String(m.get("id", ""))
		var n := int(m.get("missed", 1))
		match id:
			"rent":
				out.append("Landlord slid another notice under the door." if n < 3
					else "Landlord has started using the word 'eviction' unprompted.")
			"loans":
				out.append("Your loan servicer sent a letter with a cartoon on it.")
			"car":
				out.append("The car was where you left it. That's the good news." if n < 2
					else "The car is not where you left it.")
			"cards":
				out.append("Card declined. In front of people.")
			"vinnie":
				out.append("Vinnie left a voicemail. It was mostly breathing." if n < 2
					else "Vinnie knows where you work. Vinnie mentioned that he knows where you work.")
			_:
				out.append("Another bill went unpaid.")
	return out

func total_owed() -> int:
	return GameState.total_debt()

func to_dict() -> Dictionary:
	return {"last": last_statement, "adm": admissions_today, "earned": earned_today}

func from_dict(d: Dictionary) -> void:
	last_statement = d.get("last", {})
	admissions_today = int(d.get("adm", 0))
	earned_today = int(d.get("earned", 0))
