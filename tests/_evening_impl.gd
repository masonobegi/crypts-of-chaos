extends RefCounted
## Measure whether the ward actually gets darker as the shift runs, and by how
## much, on the renderer this project ships.
var tree: SceneTree = null
var game: Node = null
var frames := 0
var index := 0
var settle := 0
var out_dir := ""

const TIMES := [480, 720, 990, 1110, 1140, 1200]   # 08:00 12:00 16:30 18:30 19:00 20:00
const VANTAGES := [
	["wide", Vector3(2.0, 2.6, 6.0), Vector3(14.0, 1.0, 11.5)],
	["along", Vector3(1.6, 1.7, 9.5), Vector3(18.5, 1.2, 11.0)],
]

func start() -> void:
	GameState.start_new_career(20260822)
	GameState.set_flag("tutorial_done", true)
	out_dir = "user://evening"
	DirAccess.make_dir_recursive_absolute(out_dir)

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 20:
		return false
	if game == null:
		game = load("res://scenes/Game.tscn").instantiate()
		tree.root.add_child(game)
		GameState.start_day()
		return false
	if index >= TIMES.size() * VANTAGES.size():
		return true
	var ti: int = index / VANTAGES.size()
	var vi: int = index % VANTAGES.size()
	var m: int = TIMES[ti]
	var v: Array = VANTAGES[vi]
	if settle == 0:
		if game.ui and game.ui.has_method("close"):
			game.ui.close()
		GameState.clock_running = false
		GameState.minute_of_day = m
		# Exactly the shipped path.
		game.apply_shift_look()
		var cam: Camera3D = game.player.camera
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
	settle += 1
	if settle < 8:
		return false
	settle = 0
	var img: Image = tree.root.get_texture().get_image()
	img.save_png("%s/%02d_%s_%s.png" % [out_dir, index, _hhmm(m), v[0]])
	print("%s %-6s  mean=%.1f  floor=%.1f  wall=%.1f  p5=%d p95=%d" % [
		_hhmm(m), v[0], _mean(img, Rect2i(0, 0, img.get_width(), img.get_height())),
		_mean(img, Rect2i(500, 640, 600, 200)),
		_mean(img, Rect2i(60, 260, 220, 200)),
		_pct(img, 5), _pct(img, 95)])
	index += 1
	return false

func _hhmm(m: int) -> String:
	return "%02d%02d" % [m / 60, m % 60]

func _mean(img: Image, r: Rect2i) -> float:
	var total := 0.0
	var n := 0
	for y in range(r.position.y, mini(r.end.y, img.get_height()), 3):
		for x in range(r.position.x, mini(r.end.x, img.get_width()), 3):
			var c := img.get_pixel(x, y)
			total += (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			n += 1
	return total / maxf(1.0, float(n))

func _pct(img: Image, p: int) -> int:
	var hist := PackedInt32Array()
	hist.resize(256)
	var n := 0
	for y in range(0, img.get_height(), 6):
		for x in range(0, img.get_width(), 6):
			var c := img.get_pixel(x, y)
			var l := int((0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0)
			hist[clampi(l, 0, 255)] += 1
			n += 1
	var want := n * p / 100
	var acc := 0
	for i in 256:
		acc += hist[i]
		if acc >= want:
			return i
	return 255
