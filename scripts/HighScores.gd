extends Control

## High scores screen — reads from local JSON database

const C_BG    := Color("#0d0d1a")
const C_WHITE := Color("#ffffff")
const C_GRAY  := Color("#888888")
const C_CYAN  := Color("#00ffff")
const C_GOLD  := Color("#ffcc00")
const C_YELLOW:= Color("#ffff88")
const C_GREEN := Color("#44ff88")
const C_RED   := Color("#ff4444")

var font: Font
var anim_t: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	_build_ui()

func _build_ui() -> void:
	var W := 844.0
	var H := 390.0

	var back := Button.new()
	back.text     = "← BACK"
	back.position = Vector2(10, 10)
	back.size     = Vector2(90, 32)
	var style := StyleBoxFlat.new()
	style.bg_color     = Color("#111111")
	style.border_color = Color("#888888")
	style.set_border_width_all(2)
	style.corner_radius_top_left     = 3
	style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	back.add_theme_stylebox_override("normal", style)
	back.add_theme_stylebox_override("hover", style)
	back.add_theme_color_override("font_color", Color("#888888"))
	back.add_theme_font_size_override("font_size", 14)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"))
	add_child(back)

	# Clear scores button (bottom)
	var clear := Button.new()
	clear.text     = "CLEAR SCORES"
	clear.position = Vector2(W - 170, H - 48)
	clear.size     = Vector2(158, 34)
	var cs := StyleBoxFlat.new()
	cs.bg_color     = Color("#220000")
	cs.border_color = Color("#ff4444")
	cs.set_border_width_all(1)
	cs.corner_radius_top_left     = 3
	cs.corner_radius_top_right    = 3
	cs.corner_radius_bottom_left  = 3
	cs.corner_radius_bottom_right = 3
	clear.add_theme_stylebox_override("normal", cs)
	clear.add_theme_stylebox_override("hover", cs)
	clear.add_theme_color_override("font_color", Color("#ff4444"))
	clear.add_theme_font_size_override("font_size", 13)
	clear.pressed.connect(func():
		ScoreManager.high_scores.clear()
		ScoreManager._write_scores()
		queue_redraw()
	)
	add_child(clear)

func _process(delta: float) -> void:
	anim_t += delta
	queue_redraw()

func _draw() -> void:
	var W := size.x
	var H := size.y

	draw_rect(Rect2(0, 0, W, H), C_BG)

	# Title bar
	draw_string(font, Vector2(W/2, 30), "HIGH SCORES", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, C_GOLD)
	draw_string(font, Vector2(W/2, 46), "★  HALL OF LEGENDS  ★", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, C_GRAY)

	# Column headers
	var hy   := 58.0
	var row_h := 28.0
	draw_rect(Rect2(8, hy, W - 16, 22), Color(0.1, 0.1, 0.2))
	draw_string(font, Vector2(16,  hy + 16), "#",     HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GRAY)
	draw_string(font, Vector2(38,  hy + 16), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GRAY)
	draw_string(font, Vector2(130, hy + 16), "SHARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GRAY)
	draw_string(font, Vector2(260, hy + 16), "FLR",   HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GRAY)
	draw_string(font, Vector2(300, hy + 16), "KILLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GRAY)
	draw_string(font, Vector2(W - 16, hy + 16), "DATE", HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, C_GRAY)

	var scores := ScoreManager.high_scores
	if scores.is_empty():
		draw_rect(Rect2(20, 100, W - 40, 80), Color(0.05, 0.05, 0.12))
		draw_string(font, Vector2(W/2, 145), "No scores yet!", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, C_GRAY)
		draw_string(font, Vector2(W/2, 165), "Start a run to get on the board.", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(C_GRAY.r, C_GRAY.g, C_GRAY.b, 0.6))
		return

	var start_y := hy + 26.0
	var max_rows := int((H - start_y - 44.0) / row_h)

	for i in min(scores.size(), max_rows):
		var entry  := scores[i] as Dictionary
		var row_y  := start_y + i * row_h
		var row_c  := Color(0.06, 0.06, 0.14) if i % 2 == 0 else Color(0.04, 0.04, 0.10)

		if i == 0:
			row_c = Color(0.20, 0.16, 0.00)
		elif i == 1:
			row_c = Color(0.12, 0.12, 0.15)
		elif i == 2:
			row_c = Color(0.12, 0.07, 0.03)

		draw_rect(Rect2(8, row_y, W - 16, row_h - 1), row_c)

		var rank_col := C_GRAY
		var rank_str := "#%d" % (i + 1)
		if i == 0:
			rank_col = C_GOLD;  rank_str = "①"
		elif i == 1:
			rank_col = Color("#cccccc");  rank_str = "②"
		elif i == 2:
			rank_col = Color("#cc8844");  rank_str = "③"

		var ty := row_y + row_h - 8.0
		draw_string(font, Vector2(16,  ty), rank_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, rank_col)

		var score_col: Color = C_GOLD if i == 0 else C_YELLOW
		draw_string(font, Vector2(38,  ty), str(entry.get("score", 0)),  HORIZONTAL_ALIGNMENT_LEFT, -1, 13, score_col)

		var shard_name := str(entry.get("shard", "?"))
		var short_shard := shard_name.split(" ")[0]
		draw_string(font, Vector2(130, ty), short_shard, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_CYAN)

		draw_string(font, Vector2(260, ty), "F%d" % int(entry.get("floor", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_WHITE)
		draw_string(font, Vector2(300, ty), str(entry.get("kills", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_RED)

		var date := str(entry.get("date", ""))
		if date.length() >= 10:
			date = date.substr(5, 5)
		draw_string(font, Vector2(W - 16, ty), date, HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, C_GRAY)

		draw_line(Vector2(8, row_y + row_h - 1), Vector2(W - 8, row_y + row_h - 1), Color(0.15, 0.15, 0.25), 1)
