extends Control

## Shard selection — one shard at a time, big readable layout

const C_BG   := Color("#0d0d1a")
const C_WHITE:= Color("#ffffff")
const C_GRAY := Color("#555577")
const C_CYAN := Color("#00ffff")

var font: Font
var anim_t: float  = 0.0
var selected: int  = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font     = ThemeDB.fallback_font
	selected = GameData.selected_shard_index
	_build_ui()

func _build_ui() -> void:
	# ← BACK (top-left)
	var back := _btn("← BACK", 10, 8, 90, 34, Color("#888888"), Color("#111111"))
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"))
	add_child(back)

	# ◀ PREV (left side, vertically centred)
	var prev := _btn("◀", 8, 156, 50, 68, Color("#aaaaaa"), Color("#111122"))
	prev.pressed.connect(func():
		selected = max(0, selected - 1)
		GameData.selected_shard_index = selected
		queue_redraw())
	add_child(prev)

	# ▶ NEXT (right of card, before detail panel)
	var nxt := _btn("▶", 470, 156, 50, 68, Color("#aaaaaa"), Color("#111122"))
	nxt.pressed.connect(func():
		selected = min(GameData.SHARDS.size() - 1, selected + 1)
		GameData.selected_shard_index = selected
		queue_redraw())
	add_child(nxt)

	# ✔ SELECT (top-right)
	var sel := _btn("SELECT  ▶", 720, 8, 116, 34, Color("#00ffff"), Color("#003344"))
	sel.pressed.connect(func():
		AudioManager.play_sfx("menu")
		GameData.selected_shard_index = selected
		get_tree().change_scene_to_file("res://scenes/Game.tscn"))
	add_child(sel)

func _btn(txt: String, x: float, y: float, w: float, h: float, fg: Color, bg: Color) -> Button:
	var b := Button.new()
	b.text = txt;  b.position = Vector2(x, y);  b.size = Vector2(w, h)
	var s := StyleBoxFlat.new()
	s.bg_color = bg;  s.border_color = fg;  s.set_border_width_all(2)
	s.corner_radius_top_left = 4;  s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4;  s.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", s)
	var h2 := s.duplicate() as StyleBoxFlat
	h2.bg_color = Color(fg.r*0.3, fg.g*0.3, fg.b*0.3)
	b.add_theme_stylebox_override("hover", h2);  b.add_theme_stylebox_override("pressed", h2)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_font_size_override("font_size", 17)
	return b

func _process(delta: float) -> void:
	anim_t += delta
	queue_redraw()

func _draw() -> void:
	var W := size.x
	var H := size.y
	var shards := GameData.SHARDS
	var s : Dictionary = shards[selected]
	var col : Color = s.color as Color
	var bg  : Color = s.bg_color as Color

	# Background
	draw_rect(Rect2(0, 0, W, H), C_BG)

	# Header bar
	draw_rect(Rect2(0, 0, W, 52), Color(0.04, 0.04, 0.1))
	draw_line(Vector2(0, 52), Vector2(W, 52), Color(col.r, col.g, col.b, 0.4), 2)
	draw_string(font, Vector2(W/2, 34), "CHOOSE YOUR SHARD", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, C_CYAN)

	# Shard counter  e.g. "3 / 8"
	draw_string(font, Vector2(W/2, 48), "%d / %d" % [selected+1, shards.size()],
				HORIZONTAL_ALIGNMENT_CENTER, -1, 13, C_GRAY)

	# ── LEFT CARD ──────────────────────────────────────────────
	# Card rect: x=64..464, y=60..370  (400×310)
	var cx := 64.0;  var cy := 60.0;  var cw := 400.0;  var ch := H - cy - 10.0

	# Glow behind card
	var glow: float = 0.10 + 0.07 * sin(anim_t * 3.0)
	draw_rect(Rect2(cx-6, cy-6, cw+12, ch+12), Color(col.r, col.g, col.b, glow))
	# Card body
	draw_rect(Rect2(cx, cy, cw, ch), bg)
	draw_rect(Rect2(cx, cy, cw, ch), col, false, 3.0)

	# Shard name — very large
	draw_string(font, Vector2(cx + cw/2, cy + 52), s.name as String,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 36, col)
	# Subtitle / flavour
	draw_string(font, Vector2(cx + cw/2, cy + 76), s.subtitle as String,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(1,1,1,0.6))

	draw_line(Vector2(cx+16, cy+88), Vector2(cx+cw-16, cy+88), Color(col.r,col.g,col.b,0.35), 2)

	# Stats grid — 2 columns × 3 rows
	var stats: Array = [
		["MAX HP",  "%+d" % (s.bonus_hp      as int), Color("#44ff66")],
		["ATTACK",  "%+d" % (s.bonus_attack  as int), Color("#ff6644")],
		["DEFENSE", "%+d" % (s.bonus_defense as int), Color("#4499ff")],
		["START GOLD", "%d" % (s.start_gold  as int), Color("#ffcc00")],
		["SCORE ×", "%.1f" % (s.score_mult   as float), col],
		["SPECIAL", s.special as String,               Color("#ff88ff")],
	]
	var cols := 2;  var rows := 3
	var sw := (cw - 32.0) / cols;  var sh := 56.0
	var sy0 := cy + 100.0
	for i in stats.size():
		var stat: Array = stats[i]
		var c_idx := i % cols;  var r_idx := i / cols
		var sx := cx + 16.0 + c_idx * sw
		var ry := sy0 + r_idx * sh
		draw_rect(Rect2(sx, ry, sw - 6, sh - 6), Color(0.06, 0.06, 0.14))
		draw_string(font, Vector2(sx + sw/2 - 3, ry + 20), stat[0] as String,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 12, C_GRAY)
		draw_string(font, Vector2(sx + sw/2 - 3, ry + 44), stat[1] as String,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 22, stat[2] as Color)

	# Description at bottom of card
	var desc: String = s.description as String
	var desc_y := sy0 + rows * sh + 8.0
	_draw_wrapped(desc, cx + 16, desc_y, cw - 32, 15, C_WHITE)

	# ── RIGHT DETAIL PANEL ─────────────────────────────────────
	var px := 540.0;  var py := 60.0;  var pw := W - px - 10.0;  var ph := H - py - 10.0
	draw_rect(Rect2(px, py, pw, ph), Color(0.05, 0.05, 0.15))
	draw_rect(Rect2(px, py, pw, ph), Color(col.r,col.g,col.b,0.5), false, 2.0)

	draw_string(font, Vector2(px + pw/2, py + 24), "START ITEM", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, C_GRAY)
	draw_string(font, Vector2(px + pw/2, py + 48), s.start_item as String,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 20, col)

	draw_line(Vector2(px+10, py+58), Vector2(px+pw-10, py+58), Color(col.r,col.g,col.b,0.3), 1)

	draw_string(font, Vector2(px + pw/2, py + 78),  "← ▶ to browse", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, C_GRAY)
	draw_string(font, Vector2(px + pw/2, py + 100), "SELECT to play", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, C_CYAN)

	# Mini index dots
	var dot_y := H - 16.0;  var dot_x := px + pw/2 - shards.size() * 9.0
	for i in shards.size():
		var dot_col: Color = col if i == selected else Color(0.3, 0.3, 0.4)
		draw_rect(Rect2(dot_x + i*18, dot_y, 12, 8), dot_col)

func _draw_wrapped(text: String, x: float, y: float, max_w: float, size: int, color: Color) -> void:
	var words := text.split(" ")
	var line  := ""
	var ly    := y
	var chars_per_line := int(max_w / (size * 0.62))
	for word in words:
		if line.length() + word.length() > chars_per_line and line != "":
			draw_string(font, Vector2(x + max_w/2, ly), line.strip_edges(),
						HORIZONTAL_ALIGNMENT_CENTER, -1, size, color)
			ly += size + 4
			line = word + " "
		else:
			line += word + " "
	if line.strip_edges() != "":
		draw_string(font, Vector2(x + max_w/2, ly), line.strip_edges(),
					HORIZONTAL_ALIGNMENT_CENTER, -1, size, color)

var _drag_start_x: float = 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_LEFT:
				selected = max(0, selected - 1)
				GameData.selected_shard_index = selected
			KEY_RIGHT:
				selected = min(GameData.SHARDS.size()-1, selected+1)
				GameData.selected_shard_index = selected
			KEY_ENTER, KEY_SPACE:
				GameData.selected_shard_index = selected
				get_tree().change_scene_to_file("res://scenes/Game.tscn")

	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			_drag_start_x = te.position.x

	if event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		var delta := de.position.x - _drag_start_x
		if abs(delta) > 40:
			if delta < 0:
				selected = min(GameData.SHARDS.size()-1, selected+1)
			else:
				selected = max(0, selected-1)
			GameData.selected_shard_index = selected
			_drag_start_x = de.position.x
