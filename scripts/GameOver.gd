extends Control

## Game Over screen

const C_BG    := Color("#0d0d1a")
const C_RED   := Color("#ff3333")
const C_WHITE := Color("#ffffff")
const C_YELLOW:= Color("#ffff88")
const C_CYAN  := Color("#00ffff")
const C_GOLD  := Color("#ffcc00")
const C_GRAY  := Color("#888888")
const C_GREEN := Color("#44ff88")

var font: Font
var anim_t: float = 0.0
var is_new_best: bool = false
var final_score: int = 0
var particles: Array = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font       = ThemeDB.fallback_font
	final_score = GameData.run_score
	is_new_best = ScoreManager.is_new_high_score(final_score) if final_score > 0 else false

	# Spawn celebratory particles for new high score
	if is_new_best:
		for _i in 60:
			particles.append({
				"x": randf() * 844,
				"y": randf() * 390,
				"vx": randf_range(-30, 30),
				"vy": randf_range(-80, -20),
				"color": [C_GOLD, C_CYAN, C_GREEN][randi() % 3],
				"size": randf_range(3.0, 7.0),
				"life": randf_range(1.0, 3.0),
				"max_life": 3.0,
			})

	_build_ui()

func _build_ui() -> void:
	var W := 844.0
	var H := 390.0

	# Play Again
	var again_btn := _make_btn("⚔  PLAY AGAIN", W * 0.55 - 130, H * 0.68, 260, 50, C_CYAN, Color("#003344"))
	again_btn.pressed.connect(func():
		AudioManager.play_sfx("menu")
		AudioManager.start_music()
		get_tree().change_scene_to_file("res://scenes/ShardSelect.tscn")
	)
	add_child(again_btn)

	# Main Menu
	var menu_btn := _make_btn("⌂  MAIN MENU", W * 0.55 - 100, H * 0.82, 200, 42, C_GRAY, Color("#111111"))
	menu_btn.pressed.connect(func():
		AudioManager.play_sfx("menu")
		AudioManager.start_music()
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	)
	add_child(menu_btn)

	# High Scores
	var hs_btn := _make_btn("★  HIGH SCORES", W * 0.55 - 100, H * 0.93, 200, 38, C_GOLD, Color("#221100"))
	hs_btn.pressed.connect(func():
		AudioManager.play_sfx("menu")
		get_tree().change_scene_to_file("res://scenes/HighScores.tscn")
	)
	add_child(hs_btn)

func _make_btn(text: String, x: float, y: float, w: float, h: float, fg: Color, bg: Color) -> Button:
	var btn  := Button.new()
	btn.text  = text
	btn.position = Vector2(x, y)
	btn.size     = Vector2(w, h)
	var style := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = fg
	style.set_border_width_all(2)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style)
	var h2 := style.duplicate() as StyleBoxFlat
	h2.bg_color = Color(fg.r * 0.2, fg.g * 0.2, fg.b * 0.2)
	btn.add_theme_stylebox_override("hover", h2)
	btn.add_theme_stylebox_override("pressed", h2)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_font_size_override("font_size", 18)
	return btn

func _process(delta: float) -> void:
	anim_t += delta
	for p in particles:
		p.x  += p.vx * delta
		p.vy += 60.0 * delta   # gravity
		p.y  += p.vy * delta
		p.life -= delta
	particles = particles.filter(func(p: Dictionary) -> bool: return p.life > 0)
	queue_redraw()

func _draw() -> void:
	var W := size.x
	var H := size.y

	draw_rect(Rect2(0, 0, W, H), C_BG)

	# Particles
	for p in particles:
		var alpha: float = p.life / p.max_life
		var c     := p.color as Color
		draw_rect(Rect2(p.x, p.y, p.size, p.size), Color(c.r, c.g, c.b, alpha))

	var title      := "YOU DIED"
	var title_col  := C_RED
	var sub_text   := "The darkness consumed you."
	if GameData.run_floor >= 10:
		title     = "VICTORY!"
		title_col = C_GOLD
		sub_text  = "You conquered the Crypts!"

	# Left column: title + stats (40 % width)
	var lx := W * 0.20
	var glow: float = 0.08 + 0.06 * sin(anim_t * 3.0)
	draw_rect(Rect2(lx - 110, 18, 220, 60), Color(title_col.r, title_col.g, title_col.b, glow))
	draw_string(font, Vector2(lx, 56), title, HORIZONTAL_ALIGNMENT_CENTER, -1, 36, title_col)
	draw_string(font, Vector2(lx, 74), sub_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, C_GRAY)

	if is_new_best:
		var badge_pulse: float = 0.7 + 0.3 * sin(anim_t * 5.0)
		draw_rect(Rect2(lx - 90, 80, 180, 26), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.2))
		draw_rect(Rect2(lx - 90, 80, 180, 26), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, badge_pulse), false, 2.0)
		draw_string(font, Vector2(lx, 98), "★ NEW HIGH SCORE! ★", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, C_GOLD)

	# Score panel (left half)
	var py := 114.0
	var pw := W * 0.50 - 16.0
	var ph := H - py - 8.0
	draw_rect(Rect2(8, py, pw, ph), Color(0.05, 0.05, 0.15, 0.95))
	draw_rect(Rect2(8, py, pw, ph), Color("#334466"), false, 2.0)

	var shard := GameData.get_shard()
	draw_string(font, Vector2(8 + pw/2.0, py + 20), shard.name as String,
	            HORIZONTAL_ALIGNMENT_CENTER, -1, 13, shard.color as Color)

	var row_w := pw - 16.0
	var rx    := 8.0 + 8.0
	_draw_stat_row_at(rx, row_w, py + 40,  "FINAL SCORE",    str(GameData.run_score), C_CYAN)
	_draw_stat_row_at(rx, row_w, py + 62,  "FLOOR REACHED",  str(GameData.run_floor), C_YELLOW)
	_draw_stat_row_at(rx, row_w, py + 84,  "ENEMIES SLAIN",  str(GameData.run_kills), C_RED)
	_draw_stat_row_at(rx, row_w, py + 106, "GOLD COLLECTED",  str(GameData.run_gold),  C_GOLD)

	var rank := ScoreManager.get_rank(final_score)
	if rank <= 10:
		draw_string(font, Vector2(8 + pw/2.0, py + ph - 10), "RANK  #%d" % rank,
		            HORIZONTAL_ALIGNMENT_CENTER, -1, 13, C_GREEN)

func _draw_stat_row_at(x: float, w: float, y: float, label: String, value: String, col: Color) -> void:
	draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_GRAY)
	draw_string(font, Vector2(x + w, y), value, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14, col)
	draw_line(Vector2(x, y + 3), Vector2(x + w, y + 3), Color(0.2, 0.2, 0.3, 0.5), 1)

func _draw_stat_row(W: float, y: float, label: String, value: String, col: Color) -> void:
	draw_string(font, Vector2(40, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_GRAY)
	draw_string(font, Vector2(W - 40, y), value, HORIZONTAL_ALIGNMENT_RIGHT, -1, 16, col)
	draw_line(Vector2(40, y + 4), Vector2(W - 40, y + 4), Color(0.2, 0.2, 0.3, 0.5), 1)
