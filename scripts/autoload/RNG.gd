extends Node
## Seeded randomness. Every run has a seed so a hilarious shift can be shared,
## and so headless tests are deterministic.
##
## Separate streams keep unrelated systems from desyncing each other: rolling for
## an extra chatter line must not shift which patient shows up tomorrow.

var seed_value: int = 0
var _streams: Dictionary = {}   # String -> RandomNumberGenerator

func _ready() -> void:
	if seed_value == 0:
		reseed(randi())

func reseed(s: int) -> void:
	seed_value = s
	_streams.clear()
	Log.i("world seed = %d" % s, "RNG")

func stream(name: String) -> RandomNumberGenerator:
	if not _streams.has(name):
		var r := RandomNumberGenerator.new()
		# Hash the stream name into the seed so each stream is independent but
		# still fully determined by the run seed.
		r.seed = hash(name) ^ seed_value
		_streams[name] = r
	return _streams[name]

func randf_s(name: String) -> float: return stream(name).randf()
func randf_range_s(name: String, a: float, b: float) -> float: return stream(name).randf_range(a, b)
func randi_range_s(name: String, a: int, b: int) -> int: return stream(name).randi_range(a, b)

func chance(name: String, p: float) -> bool:
	return stream(name).randf() < p

func pick(name: String, arr: Array):
	if arr.is_empty():
		return null
	return arr[stream(name).randi_range(0, arr.size() - 1)]

## Weighted pick. `weights` maps key -> float weight.
func pick_weighted(name: String, weights: Dictionary):
	var total := 0.0
	for k in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return null
	var roll := stream(name).randf() * total
	for k in weights:
		roll -= maxf(0.0, float(weights[k]))
		if roll <= 0.0:
			return k
	return weights.keys().back()

## Gaussian-ish noise via sum of uniforms — used for vitals jitter.
func noise(name: String, spread: float) -> float:
	var r := stream(name)
	return ((r.randf() + r.randf() + r.randf()) / 3.0 - 0.5) * 2.0 * spread

## A SEED IS NOT A POSITION, and saving only the seed rewinds the whole career.
##
## Every `randf_s`/`chance`/`pick` ADVANCES the generator it names, so a stream
## is (seed, position) and the seed alone is half of it. The first version of
## this pair returned `{"seed": seed_value}` and restored it with `reseed()`,
## which clears `_streams` — so loading a save put every stream back to position
## zero and the next `chance("lead_oduya")` returned whatever the FIRST ask of
## the career had returned. Deterministically, invisibly, and identically on
## every reload, which is a save-scum surface on the suggestibility roll rather
## than merely a lost seed.
##
## Neither half of the pair had a caller. RNG was not registered with SaveSystem
## at all, so a loaded career simply inherited whatever positions the title
## screen's music and idle chatter happened to leave behind — CLAUDE.md 15's
## shape (a thing written, documented, and read by nothing), sitting in the save
## system. `Game._register_saves` registers it now.
##
## The state goes to JSON as a DECIMAL STRING, not a number. `RandomNumberGenerator.state`
## is a full 64-bit value; JSON has one numeric type and it is a double, so a
## state above 2^53 would come back rounded and every stream would resume a few
## draws away from where it stopped — the same bug as the one above, quieter.
func save_state() -> Dictionary:
	var positions := {}
	for name in _streams:
		positions[name] = str((_streams[name] as RandomNumberGenerator).state)
	return {"seed": seed_value, "streams": positions}

func load_state(d: Dictionary) -> void:
	seed_value = int(d.get("seed", seed_value))
	# CLEAR, THEN REBUILD. A stream the save does not mention has to go back to
	# its derived seed rather than keep the position the menu left it at, and
	# `reseed()` is not the way to do that here: it would re-log the seed on
	# every load and it takes an argument this function has already applied.
	_streams.clear()
	var positions: Dictionary = d.get("streams", {})
	for name in positions:
		# Strings only. A save written before this field existed has no
		# "streams" key at all, and anything else in it is a hand-edited file.
		if typeof(positions[name]) != TYPE_STRING:
			continue
		stream(String(name)).state = int(String(positions[name]))
