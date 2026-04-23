extends Control

## Main menu — landscape 844×390, clear centred layout

const C_BG     := Color("#0d0d1a")
const C_TITLE  := Color("#00ffff")
const C_YELLOW := Color("#ffff88")
const C_GRAY   := Color("#666688")
const C_GOLD   := Color("#ffcc00")
const C_WHITE  := Color("#ffffff")

var font: Font
var anim_t: float = 0.0
var stars: Array = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	AudioManager.start_music()
	randomize()
	for _i in 120:
		stars.append({
			"x":     randf() * 844.0,
			"y":     randf() * 390.0,
			"sz":    randf_range(1.0, 3.5),
			"speed": randf_range(0.5, 2.5),
			"phase": randf() * 6.28,
		})
	_build_ui()

func _build_ui() -> void:
	# Right-half center for buttons: x = 633 (right half is 422–844)
	var play := _btn("⚔   ENTER THE CRYPTS", 503, 240, 260, 56, Color("#00ffff"), Color("#001a2e"))
	play.pressed.connect(func():
		AudioManager.play_sfx("menu")
		get_tree().change_scene_to_file("res://scenes/ShardSelect.tscn"))
	add_child(play)

	var hs := _btn("★   HIGH SCORES", 533, 308, 200, 44, Color("#ffcc00"), Color("#1a1000"))
	hs.pressed.connect(func():
		AudioManager.play_sfx("menu")
		get_tree().change_scene_to_file("res://scenes/HighScores.tscn"))
	add_child(hs)

func _btn(txt: String, x: float, y: float, w: float, h: float, fg: Color, bg: Color) -> Button:
	var b := Button.new()
	b.text = txt;  b.position = Vector2(x, y);  b.size = Vector2(w, h)
	var s := StyleBoxFlat.new()
	s.bg_color = bg;  s.border_color = fg;  s.set_border_width_all(2)
	s.corner_radius_top_left = 4;  s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left = 4;  s.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", s)
	var h2 := s.duplicate() as StyleBoxFlat
	h2.bg_color = Color(fg.r * 0.25, fg.g * 0.25, fg.b * 0.25)
	b.add_theme_stylebox_override("hover", h2);  b.add_theme_stylebox_override("pressed", h2)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_font_size_override("font_size", 18)
	return b

func _process(delta: float) -> void:
	anim_t += delta
	queue_redraw()

func _draw() -> void:
	var W := size.x
	var H := size.y

	draw_rect(Rect2(0, 0, W, H), C_BG)

	# Stars
	for star in stars:
		var br: float = 0.4 + 0.6 * sin(anim_t * float(star.speed) + float(star.phase))
		draw_rect(Rect2(float(star.x), float(star.y), float(star.sz), float(star.sz)),
				  Color(1, 1, 1, br * 0.7))

	# Pixel dungeon art — centred in left half (0..422)
	var art_w := 11.0 * 15.0   # 165 px
	var art_h :=  8.0 * 15.0   # 120 px
	_draw_dungeon_art(211.0 - art_w / 2.0, H / 2.0 - art_h / 2.0)

	# Vertical divider
	draw_rect(Rect2(420, 30, 2, H - 60), Color(1, 1, 1, 0.07))

	# Title — centred in right half (422..844), cx = 633
	var cx := 633.0
	var pulse: float = 0.06 + 0.04 * sin(anim_t * 2.2)
	draw_rect(Rect2(cx - 185, 48, 370, 168), Color(0.0, 0.55, 0.75, pulse))

	var ps := 58 + int(sin(anim_t * 2.5) * 2)
	draw_string(font, Vector2(cx + 3, 143), "CRYPTS",   HORIZONTAL_ALIGNMENT_CENTER, -1, ps,  Color(0,0,0,0.5))
	draw_string(font, Vector2(cx + 3, 183), "OF CHAOS", HORIZONTAL_ALIGNMENT_CENTER, -1, 36,  Color(0,0,0,0.5))
	draw_string(font, Vector2(cx, 140),     "CRYPTS",   HORIZONTAL_ALIGNMENT_CENTER, -1, ps,  C_TITLE)
	draw_string(font, Vector2(cx, 180),     "OF CHAOS", HORIZONTAL_ALIGNMENT_CENTER, -1, 36,  C_YELLOW)
	draw_string(font, Vector2(cx, 210),     "ROGUELITE DUNGEON CRAWLER",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 16, C_GRAY)

	# Best score — under subtitle, still in right half
	var best := ScoreManager.get_high_score()
	if best > 0:
		draw_rect(Rect2(cx - 120, 220, 240, 26), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.15))
		draw_string(font, Vector2(cx, 238), "BEST  %d" % best,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 17, C_GOLD)

	draw_string(font, Vector2(W - 10, H - 8), "v1.0", HORIZONTAL_ALIGNMENT_RIGHT, -1, 13, C_GRAY)

func _draw_dungeon_art(bx: float, by: float) -> void:
	var t  := 14.0
	var gp := 1.0
	var layout := [
		"###########",
		"#....@....#",
		"#.####.>..#",
		"#....#....#",
		"###..######",
		"  #......# ",
		"  #......# ",
		"  ########",
	]
	var color_map: Dictionary = {
		"#": Color("#1e3060"),
		".": Color("#12152a"),
		"@": Color("#00ffff"),
		">": Color("#00ff88"),
		" ": C_BG,
	}
	for row in layout.size():
		var row_str: String = layout[row]
		for col in row_str.length():
			var ch: String = row_str[col]
			var c: Color   = color_map.get(ch, C_BG)
			draw_rect(Rect2(bx + col * (t + gp), by + row * (t + gp), t, t), c)
