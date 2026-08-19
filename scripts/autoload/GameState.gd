extends Node
## Global run state: the clock, the money, the debts, the reputations, and the
## slow-moving institutional numbers that decide how your career ends.

const MINUTES_PER_DAY := 1440
const SHIFT_START_HOUR := 8
const SHIFT_HOURS := 8
## In-game minutes per real second while on shift. 8h shift ≈ 12 real minutes.
const TIME_SCALE := 0.666

enum Phase { TITLE, PRE_SHIFT, SHIFT, CHART_REVIEW, POST_SHIFT, GAME_OVER }

# ------------------------------------------------------------------ clock
var day: int = 1
var minute_of_day: int = SHIFT_START_HOUR * 60
var career_minutes: int = 0
var phase: Phase = Phase.TITLE
var _minute_accum: float = 0.0
var clock_running: bool = false

# ------------------------------------------------------------------ money
## Enough to clear exactly one day of debts and nothing more. Day one is paid;
## day two is the problem. Starting below the daily outflow meant the first
## screen the player ever saw was five missed payments for things they had not
## yet had a chance to do anything about.
var personal_money: int = 820
var hospital_money: int = 12000
## Your cut of hospital profit, improved by upgrades and by being liked.
var bonus_rate: float = 0.08

## Personal financial catastrophe. `daily` is deducted every morning; missing a
## payment escalates it. This is the engine that makes cheating tempting.
var debts: Array[Dictionary] = []

# ------------------------------------------------------------------ reputation
## All 0..1 unless noted. These are institutional, slow, and hard to fake.
var reputation := {
	"hospital": 0.45,       ## public standing → patient volume & insurance tiers
	"doctor": 0.5,          ## your clinical standing → benefit of the doubt
	"staff_trust": 0.5,     ## how much the ward covers for you
	"patient_sat": 0.6,     ## satisfaction → complaints
	"insurer_trust": 0.6,   ## audit frequency
	"gov_scrutiny": 0.05,   ## HIGHER IS WORSE — medical board attention
}

## Institutional suspicion, distinct from any individual's. Rumours convert
## personal suspicion into Heat; Heat is what actually opens investigations.
var heat: float = 0.0

## Escalation ladder position. See SANCTIONS.
var sanction_level: int = 0
const SANCTIONS := [
	"Clean", "Complaint On File", "Written Warning", "Internal Review",
	"Probation", "Malpractice Suit", "Medical Board Inquiry",
	"Police Investigation", "License Revoked", "Arrested",
]

# ------------------------------------------------------------------ progression
var owned_upgrades: Array[String] = []
var unlocked_departments: Array[String] = ["ward"]
## Cover stories currently in play, tag -> career_minute it expires.
var active_covers: Dictionary = {}
## Arbitrary run flags for events, tutorial, codex.
var flags: Dictionary = {}
var codex_unlocked: Array[String] = []

# ------------------------------------------------------------------ career stats
var stats := {
	"patients_admitted": 0, "patients_discharged": 0, "patients_cured": 0,
	"days_billed": 0, "complications_caused": 0, "complications_clean": 0,
	"revenue_total": 0, "personal_earned": 0, "forged_entries": 0,
	"witnessed_acts": 0, "investigations_survived": 0, "longest_stay": 0.0,
	"longest_stay_name": "", "shifts_worked": 0, "cover_stories_used": 0,
	"items_broken": 0, "complaints": 0,
}

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if not clock_running or phase != Phase.SHIFT:
		return
	_minute_accum += delta * TIME_SCALE * 60.0 / 60.0
	while _minute_accum >= 1.0:
		_minute_accum -= 1.0
		_advance_minute()

func _advance_minute() -> void:
	var prev_hour := int(minute_of_day / 60)
	minute_of_day += 1
	career_minutes += 1
	if minute_of_day >= MINUTES_PER_DAY:
		minute_of_day -= MINUTES_PER_DAY
	EventBus.clock_tick.emit(minute_of_day)
	var h := int(minute_of_day / 60)
	if h != prev_hour:
		EventBus.hour_tick.emit(h)
	_expire_covers()

# ------------------------------------------------------------------ clock utils
func time_string() -> String:
	var h := int(minute_of_day / 60)
	var m := minute_of_day % 60
	var suffix := "AM" if h < 12 else "PM"
	var hh := h % 12
	if hh == 0:
		hh = 12
	return "%d:%02d %s" % [hh, m, suffix]

func shift_minutes_remaining() -> int:
	var end := (SHIFT_START_HOUR + SHIFT_HOURS) * 60
	return maxi(0, end - minute_of_day)

func shift_over() -> bool:
	return minute_of_day >= (SHIFT_START_HOUR + SHIFT_HOURS) * 60

func set_phase(p: Phase) -> void:
	phase = p
	clock_running = (p == Phase.SHIFT)
	EventBus.phase_changed.emit(int(p))

# ------------------------------------------------------------------ money
func add_personal(amount: int, label: String = "") -> void:
	personal_money += amount
	if amount > 0:
		stats.personal_earned += amount
	EventBus.transaction.emit(label, amount, false)
	EventBus.money_changed.emit(personal_money, hospital_money)

func add_hospital(amount: int, label: String = "") -> void:
	hospital_money += amount
	if amount > 0:
		stats.revenue_total += amount
	EventBus.transaction.emit(label, amount, true)
	EventBus.money_changed.emit(personal_money, hospital_money)

func total_debt() -> int:
	var t := 0
	for d in debts:
		t += int(d.get("amount", 0))
	return t

func daily_debt_payment() -> int:
	var t := 0
	for d in debts:
		t += int(d.get("daily", 0))
	return t

# ------------------------------------------------------------------ reputation
func adjust_rep(track: String, delta: float) -> void:
	if not reputation.has(track):
		return
	reputation[track] = clampf(float(reputation[track]) + delta, 0.0, 1.0)
	EventBus.reputation_changed.emit(track, reputation[track])

func rep(track: String) -> float:
	return float(reputation.get(track, 0.5))

func add_heat(delta: float, reason: String = "") -> void:
	heat = clampf(heat + delta, 0.0, 1.0)
	if reason != "":
		Log.d("heat %+0.3f -> %0.2f (%s)" % [delta, heat, reason], "HEAT")
	EventBus.heat_changed.emit(heat)

# ------------------------------------------------------------------ covers
## Register a cover story. While active, evidence tagged with it is heavily
## discounted — that's the reward for getting your excuse in first.
func add_cover(tag: String, minutes: int = 240) -> void:
	active_covers[tag] = career_minutes + minutes
	stats.cover_stories_used += 1

func has_cover(tag: String) -> bool:
	return active_covers.has(tag)

func _expire_covers() -> void:
	var dead: Array = []
	for tag in active_covers:
		if career_minutes > int(active_covers[tag]):
			dead.append(tag)
	for tag in dead:
		active_covers.erase(tag)

# ------------------------------------------------------------------ flags/codex
func flag(k: String, default_value: Variant = false) -> Variant:
	return flags.get(k, default_value)

func set_flag(k: String, v: Variant = true) -> void:
	flags[k] = v

func unlock_codex(id: String) -> void:
	if codex_unlocked.has(id):
		return
	codex_unlocked.append(id)
	EventBus.codex_unlocked.emit(id)

func has_upgrade(id: String) -> bool:
	return owned_upgrades.has(id)

# ------------------------------------------------------------------ new run
func start_new_career(run_seed: int = 0) -> void:
	if run_seed == 0:
		run_seed = randi()
	RNG.reseed(run_seed)
	day = 1
	minute_of_day = SHIFT_START_HOUR * 60
	career_minutes = 0
	personal_money = 820
	hospital_money = 12000
	bonus_rate = 0.08
	heat = 0.0
	sanction_level = 0
	owned_upgrades.clear()
	unlocked_departments = ["ward"]
	active_covers.clear()
	flags.clear()
	codex_unlocked.clear()
	reputation = {
		"hospital": 0.45, "doctor": 0.5, "staff_trust": 0.5,
		"patient_sat": 0.6, "insurer_trust": 0.6, "gov_scrutiny": 0.05,
	}
	for k in stats:
		stats[k] = 0 if typeof(stats[k]) != TYPE_STRING else ""
	debts = [
		{"id": "rent", "name": "Rent (studio, mould feature)", "amount": 3400, "daily": 120, "missed": 0},
		{"id": "loans", "name": "Medical School Loans", "amount": 412000, "daily": 260, "missed": 0},
		{"id": "car", "name": "Car Payment (repossession pending)", "amount": 9800, "daily": 95, "missed": 0},
		{"id": "cards", "name": "Credit Card (declined at brunch)", "amount": 6200, "daily": 70, "missed": 0},
		{"id": "vinnie", "name": "Loan From 'Vinnie'", "amount": 4000, "daily": 150, "missed": 0},
	]
	Log.i("new career, seed %d" % run_seed, "GameState")

# ------------------------------------------------------------------ save/load
func to_dict() -> Dictionary:
	return {
		"day": day, "mod": minute_of_day, "cm": career_minutes,
		"pm": personal_money, "hm": hospital_money, "br": bonus_rate,
		"debts": debts, "rep": reputation, "heat": heat, "sanc": sanction_level,
		"ups": owned_upgrades, "depts": unlocked_departments,
		"covers": active_covers, "flags": flags, "codex": codex_unlocked,
		"stats": stats, "rng": RNG.save_state(),
	}

func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	minute_of_day = int(d.get("mod", SHIFT_START_HOUR * 60))
	career_minutes = int(d.get("cm", 0))
	personal_money = int(d.get("pm", 40))
	hospital_money = int(d.get("hm", 12000))
	bonus_rate = float(d.get("br", 0.08))
	debts.clear()
	for x in d.get("debts", []):
		debts.append(x)
	reputation = d.get("rep", reputation)
	heat = float(d.get("heat", 0.0))
	sanction_level = int(d.get("sanc", 0))
	owned_upgrades.clear()
	for u in d.get("ups", []):
		owned_upgrades.append(String(u))
	unlocked_departments.clear()
	for u in d.get("depts", ["ward"]):
		unlocked_departments.append(String(u))
	active_covers = d.get("covers", {})
	flags = d.get("flags", {})
	codex_unlocked.clear()
	for c in d.get("codex", []):
		codex_unlocked.append(String(c))
	stats = d.get("stats", stats)
	RNG.load_state(d.get("rng", {}))
