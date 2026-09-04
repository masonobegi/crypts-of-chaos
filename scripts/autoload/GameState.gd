extends Node
## The clock, the money owed, and the handful of flags a single shift needs.
##
## Everything else that used to live here went with the redesign: three shift
## types, seventeen upgrades, three unlocked departments, a sanction ladder, six
## reputation tracks and a career-stats dictionary that nothing read. A vertical
## slice is one ward and one day. If a number is not used by tonight's decision,
## it is not here.

const MINUTES_PER_DAY := 1440
## How fast the clock runs. A shift is eight in the morning to eight at night,
## and the whole point is that Adeyemi's rounds land at fixed, learnable times,
## so the player needs enough real minutes between them to think.
const TIME_SCALE := 0.6

signal minute_passed(minute_of_day: int)
signal day_started(day: int)

var day: int = 1
var minute_of_day: int = Cases.DAY_START_MINUTE
var clock_running: bool = false
var seed_value: int = 0

## What you have. What you owe is a constant in `Cases`, because it is content.
var cash: int = 0

var flags: Dictionary = {}
## Excuses already used on a given person. `Evidence` reads this: leaning on the
## same cover story twice is what stops working.
var active_covers: Dictionary = {}

var _accum := 0.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if not clock_running:
		return
	_accum += delta * TIME_SCALE * 60.0 / 60.0
	while _accum >= 1.0:
		_accum -= 1.0
		_advance_minute()

func _advance_minute() -> void:
	minute_of_day += 1
	minute_passed.emit(minute_of_day)

## Jump the clock forward because something took time.
##
## THERE MUST ONLY BE ONE CLOCK. Every verb on the ward costs minutes, and those
## minutes were being spent on `WardDay.minute` while the HUD, the day's end and
## everything driven by `minute_passed` went on counting real seconds — so the
## chart said half past seven while the corner of the screen said five past
## eleven, and the two drifted further apart the more the player did.
##
## Emits once for the destination rather than once per minute skipped: the
## consumers all take an absolute time, and a hundred emissions to cross an
## hour is a hundred chances to do something a hundred times.
func skip_to(m: int) -> void:
	if m <= minute_of_day:
		return
	minute_of_day = m
	_accum = 0.0
	minute_passed.emit(minute_of_day)

## Minutes since the career began. `Evidence` decays against this, so it has to
## keep counting across days even though the slice is only one.
var career_minutes: int:
	get: return (day - 1) * MINUTES_PER_DAY + minute_of_day

func start_new_career(with_seed: int = 0) -> void:
	seed_value = with_seed if with_seed != 0 else int(Time.get_unix_time_from_system())
	RNG.reseed(seed_value)
	day = 1
	minute_of_day = Cases.DAY_START_MINUTE
	clock_running = false
	# CLEAR FIRST, THEN SET. `flags.clear()` used to run AFTER reset_debt(),
	# DoctorRecord.wipe() and the readmission list — all three of which write
	# flags — so a new career was arriving at the right state entirely by
	# accident, via the defaults of the getters that read them.
	flags.clear()
	active_covers.clear()
	# The float, once. From here it is your own money.
	cash = Cases.STARTING_CASH
	reset_debt()
	DoctorRecord.wipe()
	set_flag(Cases.READMIT_FLAG, [])
	set_flag("auditor_shifts", 0)
	set_flag("auditor_present", false)
	set_flag("watched", false)
	Log.i("new day, seed %d" % seed_value, "GameState")

## THE LOSING ENDING.
##
## Five strikes and the Board takes your licence — see `DoctorRecord.STRIKE_FOR`
## for what a night is worth. Before this existed, the worst thing the ward
## sister could do cost you denser nurse rounds and nothing else: a probe that
## played seven days found a greedy player being referred on six consecutive
## nights and simply carrying on, so the top of the punishment scale was a
## plateau and there was nothing to be afraid of.


## THE TWO ENDINGS, and until this session the game had neither.
const ENDING_PAID := "paid"
const ENDING_STRUCK_OFF := "struck_off"

## What is left of what Vinnie is owed. Counts down; at zero you are out.
func debt_remaining() -> int:
	var d = flag("debt_remaining", null)
	return Cases.DEBT_TOTAL if d == null else int(d)

func pay_vinnie(amount: int) -> int:
	var left: int = maxi(0, debt_remaining() - maxi(0, amount))
	set_flag("debt_remaining", left)
	return left

## A FRESH CAREER'S WORTH OF DEBT. Every harness that ends a day now drains the
## career total, so anything reusing this autoload between runs has to put it
## back — the same class of leak that had three audits measuring a frontier
## against a debt that depended on the order of the list.
func reset_debt() -> void:
	set_flag("debt_remaining", Cases.DEBT_TOTAL)
	set_flag("vinnie_visits", false)
	cash = Cases.STARTING_CASH

func paid_off() -> bool:
	return debt_remaining() <= 0

## Non-empty once the career is over, either way. Read by the day-over screen,
## which stops offering tomorrow.
## STRUCK OFF WINS THE TIE, and the order matters more than it looks. Vinnie is
## paid at eight and the sister reads the folder at ten past; checking `paid_off`
## first made the last night of every career a total amnesty, because you could
## earn the strike that ends you and the game would hand you the good ending
## anyway. Every career ends on such a night by construction.
func ending() -> String:
	if struck_off():
		return ENDING_STRUCK_OFF
	if paid_off():
		return ENDING_PAID
	return ""

func struck_off() -> bool:
	var d: Dictionary = flag(DoctorRecord.FLAG, {})
	return int(d.get("strikes", 0)) >= DoctorRecord.STRIKES_TO_STRIKE_OFF

func start_day() -> void:
	clock_running = true
	day_started.emit(day)

func time_string() -> String:
	var h := (minute_of_day / 60) % 24
	var m := minute_of_day % 60
	var suffix := "AM" if h < 12 else "PM"
	var hh := h % 12
	if hh == 0:
		hh = 12
	return "%d:%02d %s" % [hh, m, suffix]

func flag(key: String, fallback = false):
	return flags.get(key, fallback)

func set_flag(key: String, value) -> void:
	flags[key] = value

## COPIES, NOT REFERENCES. `flags` was handed out live: a caller holding the
## dictionary from to_dict() was holding this one, so a snapshot taken before a
## change and restored after it restored nothing. The JSON path hid it — going
## through a file deep-copies for free — and the in-memory path, which is what
## every test and every carry uses, silently aliased.
func to_dict() -> Dictionary:
	return {"day": day, "minute": minute_of_day, "cash": cash, "seed": seed_value,
		"flags": flags.duplicate(true), "covers": active_covers.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	minute_of_day = int(d.get("minute", Cases.DAY_START_MINUTE))
	cash = int(d.get("cash", 0))
	seed_value = int(d.get("seed", 0))
	flags = Dictionary(d.get("flags", {})).duplicate(true)
	active_covers = Dictionary(d.get("covers", {})).duplicate(true)
