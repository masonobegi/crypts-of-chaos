extends Node
## Global run state: the clock, the money, the debts, the reputations, and the
## slow-moving institutional numbers that decide how your career ends.

const MINUTES_PER_DAY := 1440
## The day shift, kept as the default so anything that does not care which shift
## it is still gets a sensible answer. The live values are shift_start_hour()
## and shift_hours(), which follow whichever shift was picked this morning.
const SHIFT_START_HOUR := 8
const SHIFT_HOURS := 8
## In-game minutes per real second while on shift. 8h shift ≈ 18 real minutes.
##
## It used to be 0.666, which made a shift twelve real minutes. Twelve minutes
## is not long enough to have a shape: by the time you had walked the floor,
## read the ward and decided what today was, you were being asked to clock out,
## and there was never a middle in which a plan could go wrong. Eighteen leaves
## room for a first hour of reading the place, a long middle where the thing you
## decided plays out, and a last hour of getting the paperwork straight before
## anybody reads it.
const TIME_SCALE := 0.444

enum Phase { TITLE, PRE_SHIFT, SHIFT, CHART_REVIEW, POST_SHIFT, GAME_OVER }

# ------------------------------------------------------------------ clock
var day: int = 1
## Which of DB.SHIFTS is being worked today. Picked before the briefing.
var shift_kind: String = "day"
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

## The day whose morning has already been run, and on which shift. See
## ShiftSystem.begin_day() — everything in it is a once-a-day effect.
var last_begun_day: int = 0
var last_begun_kind: String = ""

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
	"injuries_caused": 0, "injuries_documented": 0, "surgeries": 0,
	"surgeries_botched": 0, "wrong_prescriptions": 0, "readmissions": 0,
	"wrong_site_procedures": 0,
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

## An hour of the day on its own, in the same twelve-hour form as the clock.
func hour_string(hour: int) -> String:
	var h := ((hour % 24) + 24) % 24
	var suffix := "AM" if h < 12 else "PM"
	var hh := h % 12
	if hh == 0:
		hh = 12
	return "%d:00 %s" % [hh, suffix]

func shift_spec() -> Dictionary:
	return DB.shift(shift_kind)

func shift_start_hour() -> int:
	return int(shift_spec().get("start_hour", SHIFT_START_HOUR))

func shift_hours() -> int:
	return int(shift_spec().get("hours", SHIFT_HOURS))

## Minutes elapsed since the shift started, counted the long way round so the
## evening shift can end at midnight and the night shift can start there.
## Comparing minute_of_day against an end hour breaks the moment a shift crosses
## the day boundary, and one of the three does.
func minutes_into_shift() -> int:
	var m := minute_of_day - shift_start_hour() * 60
	if m < 0:
		m += MINUTES_PER_DAY
	return m

func shift_minutes_remaining() -> int:
	return maxi(0, shift_hours() * 60 - minutes_into_shift())

func shift_over() -> bool:
	return minutes_into_shift() >= shift_hours() * 60

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
	shift_kind = "day"
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
		"shift_kind": shift_kind, "ups": owned_upgrades, "depts": unlocked_departments,
		"covers": active_covers, "flags": flags, "codex": codex_unlocked,
		"stats": stats, "rng": RNG.save_state(),
		# The phase, and which day's morning has already been run.
		#
		# Neither was persisted, so a loaded save had no idea where in the day
		# it was. Continue therefore ran begin_day() unconditionally — settling
		# debts, rolling events, checking investigations, taking readmissions
		# and building a new appointment list — for a day whose morning had
		# already happened. Loading an autosave charged the player a second
		# day's rent.
		"phase": int(phase), "begun": last_begun_day, "begun_kind": last_begun_kind,
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
	shift_kind = String(d.get("shift_kind", "day"))
	phase = d.get("phase", Phase.PRE_SHIFT) as Phase
	clock_running = (phase == Phase.SHIFT)
	last_begun_day = int(d.get("begun", 0))
	last_begun_kind = String(d.get("begun_kind", ""))
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
