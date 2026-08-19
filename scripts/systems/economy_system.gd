class_name EconomySystem
extends Node
## Hospital revenue, hospital costs, your cut, and the debts that make the whole
## thing tempting in the first place.
##
## The debt schedule is tuned so a scrupulously honest doctor cannot service it
## on the base bonus. The game never tells you to cheat; the arithmetic does.

const BASE_SALARY := 240              ## per shift, before bonus
const STAFF_COST_PER_HEAD := 210
const UTILITIES_BASE := 180
const SUPPLY_COST_PER_PATIENT := 55
const REPAIR_COST := 140

var patient_system: PatientSystem = null
var last_statement: Dictionary = {}

func _ready() -> void:
	add_to_group("economy")
	patient_system = get_tree().get_first_node_in_group("patient_system")
	EventBus.item_broke.connect(_on_item_broke)

func _on_item_broke(_item) -> void:
	GameState.add_hospital(-REPAIR_COST, "repairs")
	GameState.adjust_rep("hospital", -0.004)

# ------------------------------------------------------------------ daily
## Bill every occupied bed. This is where a longer stay becomes money.
func bill_day() -> Dictionary:
	var lines: Array[Dictionary] = []
	var revenue := 0
	for p in patient_system.active():
		var amount := p.daily_revenue()
		revenue += amount
		GameState.stats.days_billed += 1
		lines.append({
			"label": "%s — %s (%s)" % [p.display_name, p.condition_name(),
				DB.insurance_name(p.insurance)],
			"amount": amount,
			"overdue": p.is_overdue(),
		})
	GameState.add_hospital(revenue, "patient billing")
	return {"revenue": revenue, "lines": lines}

func staff_count() -> int:
	return get_tree().get_nodes_in_group("staff").size()

func daily_costs() -> Dictionary:
	var staff := staff_count() * STAFF_COST_PER_HEAD
	var utilities := UTILITIES_BASE + int(GameState.owned_upgrades.size()) * 35
	var supplies := patient_system.active_count() * SUPPLY_COST_PER_PATIENT
	var total := staff + utilities + supplies
	return {
		"staff": staff, "utilities": utilities, "supplies": supplies, "total": total,
	}

## Your cut. Improved by upgrades and by the hospital actually being profitable —
## which is why running a genuinely good ward is a viable strategy, not a joke.
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
	var profit: int = int(billing["revenue"]) - int(costs["total"])
	GameState.add_hospital(-int(costs["total"]), "operating costs")

	var bonus := compute_bonus(profit)
	GameState.add_personal(BASE_SALARY, "salary")
	if bonus > 0:
		GameState.add_personal(bonus, "profit share")

	last_statement = {
		"revenue": billing["revenue"],
		"lines": billing["lines"],
		"costs": costs,
		"profit": profit,
		"salary": BASE_SALARY,
		"bonus": bonus,
		"take_home": BASE_SALARY + bonus,
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
			paid.append({"name": d.get("name", ""), "amount": due,
				"remaining": d.get("amount", 0)})
		else:
			d["missed"] = int(d.get("missed", 0)) + 1
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
	return {"last": last_statement}

func from_dict(d: Dictionary) -> void:
	last_statement = d.get("last", {})
