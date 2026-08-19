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

func save_state() -> Dictionary:
	return {"seed": seed_value}

func load_state(d: Dictionary) -> void:
	reseed(int(d.get("seed", 0)))
