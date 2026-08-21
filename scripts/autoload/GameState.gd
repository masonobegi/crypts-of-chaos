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
var minute_of_day: int = 8 * 60
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

## Minutes since the career began. `Evidence` decays against this, so it has to
## keep counting across days even though the slice is only one.
var career_minutes: int:
	get: return (day - 1) * MINUTES_PER_DAY + minute_of_day

func start_new_career(with_seed: int = 0) -> void:
	seed_value = with_seed if with_seed != 0 else int(Time.get_unix_time_from_system())
	RNG.reseed(seed_value)
	day = 1
	minute_of_day = 8 * 60
	clock_running = false
	cash = 0
	flags.clear()
	active_covers.clear()
	Log.i("new day, seed %d" % seed_value, "GameState")

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

func to_dict() -> Dictionary:
	return {"day": day, "minute": minute_of_day, "cash": cash, "seed": seed_value,
		"flags": flags, "covers": active_covers}

func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	minute_of_day = int(d.get("minute", 8 * 60))
	cash = int(d.get("cash", 0))
	seed_value = int(d.get("seed", 0))
	flags = Dictionary(d.get("flags", {}))
	active_covers = Dictionary(d.get("covers", {}))
