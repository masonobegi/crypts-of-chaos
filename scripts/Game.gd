extends Node2D

## CRYPTS OF CHAOS - Main Game Controller
## Handles dungeon state, player, enemies, items, combat, rendering, and touch input.

# ─── Constants ───────────────────────────────────────────────────────────────
const TILE_SIZE    := 26
const DUN_W        := 34
const DUN_H        := 44
const FOV_RADIUS   := 7
const MAX_LOG      := 5
const ENEMY_TURN_DELAY := 0.05

# Tile types (mirror DungeonGenerator)
const T_WALL   := 0
const T_FLOOR  := 1
const T_STAIRS := 2

# ─── 8-bit Colour Palette ────────────────────────────────────────────────────
const C_BG          := Color("#0d0d1a")
const C_WALL        := Color("#1e2a4a")
const C_WALL_EDGE   := Color("#2a3a60")
const C_WALL_DARK   := Color("#0f1528")
const C_FLOOR       := Color("#12121f")
const C_FLOOR_LIT   := Color("#1a1a2e")
const C_FLOOR_DOT   := Color("#1e1e35")
const C_STAIRS      := Color("#00ff88")
const C_STAIRS_DIM  := Color("#00aa55")
const C_UNEXPLORED  := Color("#000000")
const C_SHADOW      := Color(0, 0, 0, 0.55)

# Entity colours
const C_PLAYER   := Color("#00ffff")
const C_PLAYER2  := Color("#0088aa")
const C_RAT      := Color("#cc8833")
const C_BAT      := Color("#884488")
const C_SKEL     := Color("#ccccbb")
const C_GOBLIN   := Color("#33bb33")
const C_ORC      := Color("#226622")
const C_WRAITH   := Color("#aa44ff")
const C_TROLL    := Color("#882222")
const C_DMAGE    := Color("#4444dd")
const C_DEMON    := Color("#ff2222")
const C_DRAGON   := Color("#ff8800")
const C_BOSS     := Color("#ff0055")

# Item colours
const C_POTION   := Color("#ff4455")
const C_GPOTION  := Color("#ff88aa")
const C_SWORD    := Color("#ffff88")
const C_SHIELD   := Color("#8888ff")
const C_ARMOR    := Color("#6688aa")
const C_SCROLL   := Color("#ff88ff")
const C_GOLD     := Color("#ffcc00")
const C_AMULET   := Color("#ff44ff")
const C_HWATER   := Color("#ffffaa")

# UI colours
const C_HP_FULL  := Color("#44ff66")
const C_HP_MID   := Color("#ffcc00")
const C_HP_LOW   := Color("#ff3333")
const C_XP_BAR   := Color("#4488ff")
const C_HUD_BG   := Color(0.05, 0.05, 0.12, 0.95)
const C_HUD_BORD := Color("#334466")
const C_LOG_BG   := Color(0, 0, 0, 0.75)
const C_WHITE    := Color("#ffffff")
const C_YELLOW   := Color("#ffff88")
const C_CYAN     := Color("#00ffff")
const C_RED      := Color("#ff4444")
const C_GREEN    := Color("#44ff88")
const C_GRAY     := Color("#888888")

# ─── Enemy Definitions ───────────────────────────────────────────────────────
const ENEMY_DEFS := {
	"rat":    {"glyph": "r", "color": C_RAT,    "hp": 4,  "atk": 2,  "def": 0, "xp": 2,  "gold": 2,  "min_floor": 1,  "ai": "chase",   "speed": 1},
	"bat":    {"glyph": "b", "color": C_BAT,    "hp": 3,  "atk": 2,  "def": 0, "xp": 2,  "gold": 1,  "min_floor": 1,  "ai": "random",  "speed": 1},
	"skel":   {"glyph": "S", "color": C_SKEL,   "hp": 8,  "atk": 4,  "def": 1, "xp": 5,  "gold": 4,  "min_floor": 3,  "ai": "chase",   "speed": 1},
	"goblin": {"glyph": "g", "color": C_GOBLIN, "hp": 7,  "atk": 5,  "def": 0, "xp": 5,  "gold": 6,  "min_floor": 3,  "ai": "chase",   "speed": 2},
	"orc":    {"glyph": "O", "color": C_ORC,    "hp": 14, "atk": 7,  "def": 2, "xp": 10, "gold": 8,  "min_floor": 5,  "ai": "chase",   "speed": 1},
	"wraith": {"glyph": "W", "color": C_WRAITH, "hp": 11, "atk": 6,  "def": 1, "xp": 12, "gold": 5,  "min_floor": 5,  "ai": "phase",   "speed": 1},
	"troll":  {"glyph": "T", "color": C_TROLL,  "hp": 20, "atk": 8,  "def": 3, "xp": 18, "gold": 10, "min_floor": 7,  "ai": "regen",   "speed": 1},
	"dmage":  {"glyph": "M", "color": C_DMAGE,  "hp": 16, "atk": 9,  "def": 1, "xp": 20, "gold": 12, "min_floor": 7,  "ai": "ranged",  "speed": 1},
	"demon":  {"glyph": "D", "color": C_DEMON,  "hp": 28, "atk": 12, "def": 4, "xp": 30, "gold": 20, "min_floor": 9,  "ai": "chase",   "speed": 1},
	"dragon": {"glyph": "&", "color": C_DRAGON, "hp": 60, "atk": 15, "def": 5, "xp": 80, "gold": 50, "min_floor": 10, "ai": "boss",    "speed": 1},
}

# ─── Item Definitions ────────────────────────────────────────────────────────
const ITEM_DEFS := {
	"potion":      {"glyph": "!", "color": C_POTION,  "name": "Health Potion",    "value": 10, "type": "consumable", "min_floor": 1},
	"gpotion":     {"glyph": "!", "color": C_GPOTION, "name": "Greater Potion",   "value": 25, "type": "consumable", "min_floor": 4},
	"sword":       {"glyph": "/", "color": C_SWORD,   "name": "Steel Sword",      "value": 3,  "type": "weapon",     "min_floor": 1},
	"dagger":      {"glyph": "/", "color": C_YELLOW,  "name": "Poison Dagger",    "value": 2,  "type": "weapon",     "min_floor": 1},
	"axe":         {"glyph": "/", "color": C_RED,     "name": "Battle Axe",       "value": 5,  "type": "weapon",     "min_floor": 5},
	"shield":      {"glyph": "[", "color": C_SHIELD,  "name": "Buckler Shield",   "value": 1,  "type": "armor",      "min_floor": 1},
	"armor":       {"glyph": "[", "color": C_ARMOR,   "name": "Chain Mail",       "value": 2,  "type": "armor",      "min_floor": 3},
	"plate":       {"glyph": "[", "color": C_GRAY,    "name": "Plate Armor",      "value": 4,  "type": "armor",      "min_floor": 6},
	"scroll_fire": {"glyph": "?", "color": C_SCROLL,  "name": "Fire Scroll",      "value": 3,  "type": "scroll",     "min_floor": 1},
	"scroll_ice":  {"glyph": "?", "color": C_SHIELD,  "name": "Ice Scroll",       "value": 2,  "type": "scroll",     "min_floor": 3},
	"gold":        {"glyph": "$", "color": C_GOLD,    "name": "Gold Coins",       "value": 15, "type": "gold",       "min_floor": 1},
	"gold_big":    {"glyph": "$", "color": C_YELLOW,  "name": "Treasure Chest",   "value": 40, "type": "gold",       "min_floor": 4},
	"amulet":      {"glyph": "o", "color": C_AMULET,  "name": "Power Amulet",     "value": 2,  "type": "amulet",     "min_floor": 5},
	"holy_water":  {"glyph": "~", "color": C_HWATER,  "name": "Holy Water",       "value": 20, "type": "consumable", "min_floor": 1},
	"map_scroll":  {"glyph": "?", "color": C_GREEN,   "name": "Map Scroll",       "value": 0,  "type": "map",        "min_floor": 1},
}

# ─── Game State Enum ─────────────────────────────────────────────────────────
enum State { PLAYER_TURN, ENEMY_TURN, ANIMATING, FLOOR_DONE, GAME_OVER }

# ─── Member Variables ─────────────────────────────────────────────────────────
var state: State = State.PLAYER_TURN
var current_floor: int = 1
var total_score: int = 0
var kills: int = 0
var rooms_cleared: int = 0
var shard: Dictionary = {}

var dungeon_data: Dictionary = {}
var dungeon: Array = []
var explored: Array = []
var visible_tiles: Array = []
var dun_w: int = DUN_W
var dun_h: int = DUN_H

var player: Dictionary = {}
var enemies: Array = []
var items_on_floor: Array = []
var rooms: Array = []

var log_messages: Array = []
var enemy_queue: Array = []   # enemies left to process this turn
var enemy_timer: float = 0.0
var floor_trans_timer: float = 0.0
var flash_timer: float = 0.0
var flash_color: Color = Color.TRANSPARENT

var camera: Camera2D
var font: Font
var hud_layer: CanvasLayer
var hud_node: Control

# Touch input state
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_start_time: float = 0.0
var touch_active: bool = false
const SWIPE_THRESHOLD := 30.0
const TAP_THRESHOLD   := 10.0

# ─── Scene Setup ─────────────────────────────────────────────────────────────
func _ready() -> void:
	shard = GameData.get_shard()
	GameData.reset_run()
	font = ThemeDB.fallback_font

	_init_player()
	_build_hud()
	_build_camera()
	_new_floor()

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(1.2, 1.2)
	add_child(camera)

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	hud_node = Control.new()
	hud_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_node)
	hud_node.draw.connect(_draw_hud.bind(hud_node))
	hud_node.set_process(true)

func _init_player() -> void:
	var s := shard
	var base_hp  := 30
	var bonus_hp : int = s.bonus_hp as int
	# Void shard randomizes stats
	if s.special == "void":
		bonus_hp    = randi_range(-8, 15)
		s.bonus_attack  = randi_range(-1, 5)
		s.bonus_defense = randi_range(-1, 3)

	player = {
		"pos":       Vector2i(0, 0),
		"hp":        max(5, base_hp + bonus_hp),
		"max_hp":    max(5, base_hp + bonus_hp),
		"attack":    5 + s.bonus_attack,
		"defense":   1 + s.bonus_defense,
		"gold":      s.start_gold,
		"level":     1,
		"exp":       0,
		"exp_next":  10,
		"scrolls":   0,
		"gold_mult": 2.0 if s.special == "rogue" else 1.0,
		"score_mult": s.score_mult,
		"shard_special": s.special,
		"poison_turns": 0,
	}
	_give_start_item(s.start_item)

func _give_start_item(item_key: String) -> void:
	match item_key:
		"sword":       player.attack  += 3
		"dagger":      player.attack  += 2
		"scroll_fire": player.scrolls += 3
		"holy_water":  player.hp = min(player.hp + 10, player.max_hp)
		"map_scroll":  player["has_map"] = true
		"none":        pass
		"random":
			var opts := ["sword", "scroll_fire", "holy_water", "armor"]
			_give_start_item(opts[randi() % opts.size()])

# ─── Floor Generation ────────────────────────────────────────────────────────
func _new_floor() -> void:
	current_floor += 0   # already incremented by caller (except first)
	dungeon_data = DungeonGenerator.generate(DUN_W, DUN_H, current_floor)
	dungeon    = dungeon_data.dungeon
	rooms      = dungeon_data.rooms
	dun_w      = dungeon_data.width
	dun_h      = dungeon_data.height
	explored   = []
	visible_tiles = []
	for y in dun_h:
		explored.append([])
		visible_tiles.append([])
		for _x in dun_w:
			explored[y].append(false)
			visible_tiles[y].append(false)

	player.pos = dungeon_data.player_start
	enemies.clear()
	items_on_floor.clear()

	_spawn_enemies()
	_spawn_items()

	# Ancient shard: reveal entire map
	if shard.special == "scholar" or player.get("has_map", false):
		for y in dun_h:
			for x in dun_w:
				explored[y][x] = true

	_compute_fov()
	_center_camera()
	state = State.PLAYER_TURN
	_add_log("Floor %d. Find the stairs!" % current_floor, C_CYAN)
	if shard.special == "cleric":
		_heal_player(3, false)
	queue_redraw()
	hud_node.queue_redraw()

func _spawn_enemies() -> void:
	var possible: Array = []
	for key in ENEMY_DEFS:
		if ENEMY_DEFS[key].min_floor <= current_floor:
			possible.append(key)

	# Skip first room, place enemies in others
	for i in range(1, rooms.size()):
		var room: Dictionary = rooms[i]
		var count := 1 + randi() % (1 + current_floor / 2)
		count = min(count, 4)
		# Boss room (last room, floor 10)
		if current_floor >= 10 and i == rooms.size() - 1:
			_place_enemy("dragon", room)
			continue
		for _j in count:
			if possible.is_empty():
				break
			var key: String = possible[randi() % possible.size()]
			_place_enemy(key, room)

func _place_enemy(key: String, room: Dictionary) -> void:
	var def: Dictionary = ENEMY_DEFS[key]
	for _attempt in 10:
		var x: int = room.x as int + 1 + randi() % (room.w as int - 2)
		var y: int = room.y as int + 1 + randi() % (room.h as int - 2)
		if dungeon[y][x] == T_FLOOR and not _enemy_at(Vector2i(x, y)):
			var hp: int = def.hp as int + current_floor
			enemies.append({
				"type": key, "pos": Vector2i(x, y),
				"hp": hp, "max_hp": hp,
				"atk": def.atk, "def": def.def,
				"xp": def.xp, "gold": def.gold,
				"glyph": def.glyph, "color": def.color,
				"ai": def.ai, "speed": def.speed,
				"regen_timer": 0,
				"confused": 0,
			})
			break

func _spawn_items() -> void:
	# Void shard: bonus item each floor
	var extra := 1 if shard.special == "void" else 0
	for i in range(1, rooms.size()):
		if randi() % 3 == 0 or extra > 0:
			extra = max(0, extra - 1)
			_place_item_in_room(rooms[i])

func _place_item_in_room(room: Dictionary) -> void:
	var possible: Array = []
	for key in ITEM_DEFS:
		if ITEM_DEFS[key].min_floor <= current_floor:
			possible.append(key)
	if possible.is_empty():
		return
	var key: String = possible[randi() % possible.size()]
	for _attempt in 10:
		var x: int = room.x as int + 1 + randi() % (room.w as int - 2)
		var y: int = room.y as int + 1 + randi() % (room.h as int - 2)
		if dungeon[y][x] == T_FLOOR and not _item_at(Vector2i(x, y)):
			items_on_floor.append({
				"key": key, "pos": Vector2i(x, y),
				"def": ITEM_DEFS[key]
			})
			return

# ─── FOV (Field of View) ─────────────────────────────────────────────────────
func _compute_fov() -> void:
	# Reset visible
	for y in dun_h:
		for x in dun_w:
			visible_tiles[y][x] = false

	var origin: Vector2i = player.pos as Vector2i
	visible_tiles[origin.y][origin.x] = true
	explored[origin.y][origin.x]      = true

	# Cast rays in 360 degrees
	for angle_deg in range(0, 360, 3):
		var angle := deg_to_rad(float(angle_deg))
		var dx := cos(angle)
		var dy := sin(angle)
		var rx  := float(origin.x) + 0.5
		var ry  := float(origin.y) + 0.5
		for _step in FOV_RADIUS:
			rx += dx
			ry += dy
			var gx := int(rx)
			var gy := int(ry)
			if gx < 0 or gx >= dun_w or gy < 0 or gy >= dun_h:
				break
			visible_tiles[gy][gx] = true
			explored[gy][gx]      = true
			if dungeon[gy][gx] == T_WALL:
				break

# ─── Combat ──────────────────────────────────────────────────────────────────
func _player_attack(enemy: Dictionary) -> void:
	var dmg := _calc_damage(player.attack as int, enemy.def as int)
	# Berserker rage: more damage at low HP
	if player.shard_special as String == "berserker":
		var rage := 1.0 + (1.0 - float(player.hp as int) / float(player.max_hp as int)) * 1.5
		dmg = int(float(dmg) * rage)
	# Rogue: dagger poisons
	if player.shard_special as String == "rogue" and randi() % 3 == 0:
		enemy.confused = 3
		_add_log("Enemy poisoned!", C_GREEN)
	enemy.hp = enemy.hp as int - dmg
	_add_log("You hit %s for %d dmg!" % [enemy.type.capitalize(), dmg], C_WHITE)
	AudioManager.play_sfx("attack")
	flash_timer = 0.15
	flash_color = Color("#ff4444")
	if enemy.hp <= 0:
		_kill_enemy(enemy)

func _enemy_attack(enemy: Dictionary) -> void:
	if enemy.confused as int > 0:
		enemy.confused = enemy.confused as int - 1
		_add_log("%s is poisoned, staggers!" % enemy.type.capitalize(), C_GREEN)
		return
	var dmg := _calc_damage(enemy.atk as int, player.defense as int)
	player.hp -= dmg
	_add_log("%s hits you for %d!" % [enemy.type.capitalize(), dmg], C_RED)
	AudioManager.play_sfx("hit")
	flash_timer = 0.12
	flash_color = Color("#4444ff")
	if player.hp <= 0:
		player.hp = 0
		_trigger_game_over()

func _calc_damage(attack: int, defense: int) -> int:
	var base := max(1, attack - defense)
	return base + randi_range(-1, 1)

func _kill_enemy(enemy: Dictionary) -> void:
	kills += 1
	var gold: int = int(enemy.gold as float * player.gold_mult as float)
	player.gold += gold
	var xp: int = enemy.xp as int
	player.exp += xp
	_add_log("%s slain! +%d XP, +%d Gold" % [enemy.type.capitalize(), xp, gold], C_YELLOW)
	enemies.erase(enemy)
	_check_levelup()
	_check_room_cleared(enemy.pos as Vector2i)

func _check_levelup() -> void:
	while player.exp >= player.exp_next:
		player.exp     -= player.exp_next
		player.level   += 1
		player.exp_next = int(player.exp_next * 1.4)
		var sp: String = player.shard_special as String
		var hp_gain: int = 5 + (4 if sp == "cleric" else 0)
		player.max_hp += hp_gain
		player.hp     += hp_gain
		player.attack += 1
		_add_log("LEVEL UP! Now level %d!" % player.level, C_CYAN)
		AudioManager.play_sfx("levelup")

func _check_room_cleared(pos: Vector2i) -> void:
	for room in rooms:
		var rx: int = room.x as int
		var ry: int = room.y as int
		var rw: int = room.w as int
		var rh: int = room.h as int
		if pos.x >= rx and pos.x < rx + rw and \
		   pos.y >= ry and pos.y < ry + rh and not room.cleared:
			var has_enemy := false
			for e in enemies:
				var ep: Vector2i = e.pos as Vector2i
				if ep.x >= rx and ep.x < rx + rw and \
				   ep.y >= ry and ep.y < ry + rh:
					has_enemy = true
					break
			if not has_enemy:
				room.cleared = true
				rooms_cleared += 1
				if player.shard_special as String == "scholar":
					total_score += int(50 * 1.08)
				_add_log("Room cleared!", C_GREEN)

func _use_scroll() -> void:
	if player.scrolls <= 0:
		_add_log("No scrolls!", C_RED)
		AudioManager.play_sfx("denied")
		return
	player.scrolls -= 1
	AudioManager.play_sfx("scroll")
	var hit := 0
	for e in enemies.duplicate():
		var dist: float = ((e.pos as Vector2i) - (player.pos as Vector2i)).length()
		if dist <= 3.5:
			var dmg: int = player.attack as int + randi_range(3, 8)
			e.hp -= dmg
			hit  += 1
			_add_log("Fire hits %s for %d!" % [e.type.capitalize(), dmg], C_SCROLL)
			if e.hp <= 0:
				_kill_enemy(e)
	if hit == 0:
		_add_log("No enemies in range!", C_GRAY)
	flash_timer = 0.2
	flash_color = Color("#ff8800")
	state = State.ENEMY_TURN
	_start_enemy_turn()

func _pick_up_item(item: Dictionary) -> void:
	var d   : Dictionary = item.def as Dictionary
	var key : String     = item.key as String
	match d.type:
		"consumable":
			if key == "potion":
				_heal_player(d.value as int, true)
			elif key == "gpotion":
				_heal_player(d.value as int, true)
			elif key == "holy_water":
				_heal_player(d.value as int, true)
				if player.poison_turns > 0:
					player.poison_turns = 0
					_add_log("Poison cured!", C_GREEN)
		"weapon":
			player.attack = player.attack as int + d.value as int
			_add_log("Equipped %s! +%d ATK" % [d.name, d.value], C_SWORD)
		"armor":
			player.defense = player.defense as int + d.value as int
			_add_log("Equipped %s! +%d DEF" % [d.name, d.value], C_SHIELD)
		"scroll":
			player.scrolls = player.scrolls as int + 3
			_add_log("Found %s! +3 Scrolls" % d.name, C_SCROLL)
		"gold":
			var g := int(d.value as float * player.gold_mult as float)
			player.gold = player.gold as int + g
			_add_log("Picked up %d gold!" % g, C_GOLD)
			AudioManager.play_sfx("gold")
		"amulet":
			player.attack  = player.attack  as int + d.value as int
			player.defense = player.defense as int + d.value as int
			_add_log("Power Amulet! +%d ATK/DEF" % d.value, C_AMULET)
		"map":
			player["has_map"] = true
			for y in dun_h:
				for x in dun_w:
					explored[y][x] = true
			_add_log("Map revealed!", C_GREEN)
	if d.type != "gold":
		AudioManager.play_sfx("pickup")
	items_on_floor.erase(item)

func _heal_player(amount: int, show_log: bool) -> void:
	var old_hp: int = player.hp as int
	player.hp  = min(player.hp + amount, player.max_hp)
	if show_log:
		_add_log("Healed %d HP!" % (player.hp - old_hp), C_HP_FULL)

# ─── Turn Management ─────────────────────────────────────────────────────────
func _player_move(dir: Vector2i) -> void:
	if state != State.PLAYER_TURN:
		return
	var nx: Vector2i = (player.pos as Vector2i) + dir
	if nx.x < 0 or nx.x >= dun_w or nx.y < 0 or nx.y >= dun_h:
		return
	# Check enemy
	var enemy: Variant = _enemy_at(nx)
	if enemy:
		_player_attack(enemy as Dictionary)
		state = State.ENEMY_TURN
		_start_enemy_turn()
		return
	# Check wall
	if dungeon[nx.y][nx.x] == T_WALL:
		return
	player.pos = nx
	# Check item
	var item: Variant = _item_at(nx)
	if item:
		_pick_up_item(item as Dictionary)
	# Check stairs
	if dungeon[nx.y][nx.x] == T_STAIRS:
		_descend_stairs()
		return
	_compute_fov()
	state = State.ENEMY_TURN
	_start_enemy_turn()
	queue_redraw()
	hud_node.queue_redraw()

func _descend_stairs() -> void:
	_add_log("Descending to floor %d..." % (current_floor + 1), C_CYAN)
	AudioManager.play_sfx("stairs")
	state = State.FLOOR_DONE
	floor_trans_timer = 1.0
	# Score for clearing a floor
	var floor_score := current_floor * 100
	total_score += floor_score
	queue_redraw()
	hud_node.queue_redraw()

func _start_enemy_turn() -> void:
	enemy_queue = enemies.duplicate()
	enemy_timer = 0.0

func _process_enemy_queue() -> void:
	if enemy_queue.is_empty():
		state = State.PLAYER_TURN
		queue_redraw()
		hud_node.queue_redraw()
		return
	var e: Dictionary = enemy_queue.pop_front()
	if not enemies.has(e):
		return
	_do_enemy_ai(e)

func _do_enemy_ai(e: Dictionary) -> void:
	var epos: Vector2i = e.pos as Vector2i
	if not visible_tiles[epos.y][epos.x]:
		# Not visible: wander
		_enemy_wander(e)
		return
	match e.ai as String:
		"chase":   _enemy_chase(e)
		"random":  _enemy_wander(e)
		"phase":   _enemy_phase(e)
		"regen":   _enemy_regen(e)
		"ranged":  _enemy_ranged(e)
		"boss":    _enemy_boss(e)
		_:         _enemy_chase(e)

func _enemy_chase(e: Dictionary) -> void:
	var dir: Vector2i = _dir_to_player(e)
	_enemy_step(e, dir)

func _enemy_wander(e: Dictionary) -> void:
	var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	dirs.shuffle()
	for d in dirs:
		var nx: Vector2i = (e.pos as Vector2i) + (d as Vector2i)
		if _tile_walkable(nx) and not _enemy_at(nx):
			e.pos = nx
			return

func _enemy_phase(e: Dictionary) -> void:
	# Wraith can walk through walls
	var dir: Vector2i = _dir_to_player(e)
	var nx: Vector2i  = (e.pos as Vector2i) + dir
	if nx == player.pos as Vector2i:
		_enemy_attack(e)
	elif nx.x >= 0 and nx.x < dun_w and nx.y >= 0 and nx.y < dun_h and not _enemy_at(nx):
		e.pos = nx

func _enemy_regen(e: Dictionary) -> void:
	e.regen_timer += 1
	if e.regen_timer >= 3:
		e.regen_timer = 0
		e.hp = min(e.hp as int + 2, e.max_hp as int)
	_enemy_chase(e)

func _enemy_ranged(e: Dictionary) -> void:
	var dist: float = ((e.pos as Vector2i) - (player.pos as Vector2i)).length()
	if dist <= 4.0:
		var dmg: int = _calc_damage(e.atk as int, player.defense as int)
		player.hp = player.hp as int - dmg
		_add_log("Dark Mage fires for %d!" % dmg, C_RED)
		if player.hp as int <= 0:
			_trigger_game_over()
	else:
		_enemy_chase(e)

func _enemy_boss(e: Dictionary) -> void:
	# Dragon: attacks and occasionally breathes fire
	var dist: float = ((e.pos as Vector2i) - (player.pos as Vector2i)).length()
	if dist <= 1.5:
		if randi() % 3 == 0:
			var dmg: int = e.atk as int + randi_range(3, 8)
			player.hp = player.hp as int - dmg
			_add_log("Dragon breathes fire! %d damage!" % dmg, C_RED)
			flash_timer = 0.3
			flash_color = Color("#ff8800")
		else:
			_enemy_attack(e)
		if player.hp as int <= 0:
			_trigger_game_over()
	else:
		_enemy_chase(e)

func _enemy_step(e: Dictionary, dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	var nx: Vector2i = (e.pos as Vector2i) + dir
	if nx == player.pos as Vector2i:
		_enemy_attack(e)
		return
	if _tile_walkable(nx) and not _enemy_at(nx):
		e.pos = nx
	else:
		var perp := [Vector2i(dir.y, dir.x), Vector2i(-dir.y, -dir.x)]
		for d in perp:
			var sx: Vector2i = (e.pos as Vector2i) + (d as Vector2i)
			if _tile_walkable(sx) and not _enemy_at(sx):
				e.pos = sx
				break

func _dir_to_player(e: Dictionary) -> Vector2i:
	var d: Vector2i = (player.pos as Vector2i) - (e.pos as Vector2i)
	if abs(d.x) >= abs(d.y):
		return Vector2i(sign(d.x), 0)
	return Vector2i(0, sign(d.y))

func _trigger_game_over() -> void:
	state = State.GAME_OVER
	AudioManager.play_sfx("death")
	AudioManager.stop_music()
	_finalize_score()
	ScoreManager.save_score(total_score, GameData.player_name, shard.name, current_floor, kills)
	GameData.run_score = total_score
	GameData.run_floor = current_floor
	GameData.run_kills = kills
	GameData.run_gold  = player.gold
	queue_redraw()
	hud_node.queue_redraw()
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")

func _finalize_score() -> void:
	total_score += kills * 10
	total_score += player.gold as int
	total_score = int(float(total_score) * player.score_mult as float)

# ─── Helpers ─────────────────────────────────────────────────────────────────
func _enemy_at(pos: Vector2i) -> Variant:
	for e in enemies:
		if e.pos == pos:
			return e
	return null

func _item_at(pos: Vector2i) -> Variant:
	for item in items_on_floor:
		if item.pos == pos:
			return item
	return null

func _tile_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= dun_w or pos.y < 0 or pos.y >= dun_h:
		return false
	return dungeon[pos.y][pos.x] != T_WALL

func _add_log(msg: String, color: Color = C_WHITE) -> void:
	log_messages.append({"text": msg, "color": color})
	if log_messages.size() > MAX_LOG:
		log_messages.pop_front()

func _center_camera() -> void:
	var ppos: Vector2i = player.pos as Vector2i
	camera.position = Vector2(ppos.x * TILE_SIZE + TILE_SIZE / 2,
							  ppos.y * TILE_SIZE + TILE_SIZE / 2)

# ─── Process ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		queue_redraw()

	match state:
		State.ENEMY_TURN:
			enemy_timer -= delta
			if enemy_timer <= 0.0:
				enemy_timer = ENEMY_TURN_DELAY
				_process_enemy_queue()

		State.FLOOR_DONE:
			floor_trans_timer -= delta
			queue_redraw()
			hud_node.queue_redraw()
			if floor_trans_timer <= 0.0:
				current_floor += 1
				_new_floor()

	# Smooth camera follow
	var ppos2: Vector2i = player.pos as Vector2i
	var target := Vector2(ppos2.x * TILE_SIZE + TILE_SIZE / 2,
						  ppos2.y * TILE_SIZE + TILE_SIZE / 2)
	camera.position = camera.position.lerp(target, 0.2)

# ─── Input ───────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYER_TURN:
		return

	# Keyboard
	if event.is_action_pressed("move_up"):
		_player_move(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"):
		_player_move(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"):
		_player_move(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_player_move(Vector2i(1, 0))
	elif event.is_action_pressed("use_item"):
		_use_scroll()
	elif event.is_action_pressed("wait"):
		state = State.ENEMY_TURN
		_start_enemy_turn()

	# Touch input
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			touch_start_pos  = te.position
			touch_start_time = Time.get_ticks_msec() / 1000.0
			touch_active     = true
		else:
			if touch_active:
				_handle_touch_release(te.position)
			touch_active = false

func _handle_touch_release(end_pos: Vector2) -> void:
	var delta_v := end_pos - touch_start_pos
	var dist    := delta_v.length()

	# Check if we tapped a HUD button (y > 680 on 844-tall screen)
	if touch_start_pos.y > 680:
		return  # handled by HUD buttons

	if dist < TAP_THRESHOLD:
		# Tap: move toward tapped world position
		var world_pos := get_canvas_transform().affine_inverse() * touch_start_pos
		var tile_x := int(world_pos.x / TILE_SIZE)
		var tile_y := int(world_pos.y / TILE_SIZE)
		var tapped  := Vector2i(tile_x, tile_y)
		var diff := tapped - (player.pos as Vector2i)
		if abs(diff.x) + abs(diff.y) == 1:
			_player_move(diff)
		elif abs(diff.x) == 1 and abs(diff.y) == 1:
			_player_move(Vector2i(sign(diff.x), 0))
	elif dist >= SWIPE_THRESHOLD:
		# Swipe
		if abs(delta_v.x) > abs(delta_v.y):
			_player_move(Vector2i(sign(delta_v.x) as int, 0))
		else:
			_player_move(Vector2i(0, sign(delta_v.y) as int))

# ─── Drawing ─────────────────────────────────────────────────────────────────
func _draw() -> void:
	# Background
	draw_rect(Rect2(-50, -50, dun_w * TILE_SIZE + 100, dun_h * TILE_SIZE + 100), C_BG)

	_draw_dungeon()
	_draw_items()
	_draw_entities()

	# Flash overlay
	if flash_timer > 0.0:
		var alpha := flash_timer / 0.3
		var fc    := flash_color
		fc.a      = alpha * 0.3
		draw_rect(Rect2(-50, -50, dun_w * TILE_SIZE + 100, dun_h * TILE_SIZE + 100), fc)

func _draw_dungeon() -> void:
	for y in dun_h:
		for x in dun_w:
			var vis  := visible_tiles[y][x]
			var expl := explored[y][x]
			if not expl:
				continue
			var tile  := dungeon[y][x]
			var rect  := Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			match tile:
				T_WALL:
					var col := C_WALL if vis else C_WALL_DARK
					draw_rect(rect, col)
					if vis:
						# Edge highlight (top + left brighter)
						draw_rect(Rect2(rect.position, Vector2(TILE_SIZE, 2)), C_WALL_EDGE)
						draw_rect(Rect2(rect.position, Vector2(2, TILE_SIZE)), C_WALL_EDGE)
				T_FLOOR, T_STAIRS:
					var col := C_FLOOR_LIT if vis else C_FLOOR
					draw_rect(rect, col)
					# Subtle dot pattern
					if vis and (x + y) % 3 == 0:
						draw_rect(Rect2(x * TILE_SIZE + TILE_SIZE/2 - 1, y * TILE_SIZE + TILE_SIZE/2 - 1, 2, 2), C_FLOOR_DOT)
					if tile == T_STAIRS and vis:
						# Draw stairs symbol
						_draw_stairs(x, y)

			# Dim unexplored explored tiles
			if not vis:
				draw_rect(rect, C_SHADOW)

func _draw_stairs(x: int, y: int) -> void:
	var bx := x * TILE_SIZE + 4
	var by := y * TILE_SIZE + 4
	var sz := TILE_SIZE - 8
	# Chevron > shape
	draw_rect(Rect2(bx, by + sz/2 - 2, sz, 4), C_STAIRS)
	draw_rect(Rect2(bx + sz/2, by, 4, sz/2), C_STAIRS)
	draw_rect(Rect2(bx + sz/2, by + sz/2, 4, sz/2 + 4), C_STAIRS)
	draw_string(font, Vector2(x * TILE_SIZE + 6, y * TILE_SIZE + TILE_SIZE - 4), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, TILE_SIZE - 6, C_STAIRS)

func _draw_items() -> void:
	for item in items_on_floor:
		var pos: Vector2i = item.pos as Vector2i
		if not visible_tiles[pos.y][pos.x]:
			continue
		var d: Dictionary = item.def as Dictionary
		var bx   := pos.x * TILE_SIZE + 4
		var by   := pos.y * TILE_SIZE + 4
		var sz   := TILE_SIZE - 8
		var dc: Color = d.color as Color
		# Glow background
		draw_rect(Rect2(pos.x * TILE_SIZE + 2, pos.y * TILE_SIZE + 2, TILE_SIZE - 4, TILE_SIZE - 4), Color(dc.r, dc.g, dc.b, 0.2))
		draw_rect(Rect2(bx, by, sz, sz), dc)
		# Inner
		draw_rect(Rect2(bx + 2, by + 2, sz - 4, sz - 4), Color(dc.r * 0.5, dc.g * 0.5, dc.b * 0.5))
		draw_string(font, Vector2(pos.x * TILE_SIZE + 5, pos.y * TILE_SIZE + TILE_SIZE - 5), d.glyph as String, HORIZONTAL_ALIGNMENT_LEFT, -1, TILE_SIZE - 8, dc)

func _draw_entities() -> void:
	for e in enemies:
		var pos: Vector2i = e.pos as Vector2i
		if not visible_tiles[pos.y][pos.x]:
			continue
		_draw_entity_box(pos, e.color as Color, e.glyph as String)
		_draw_mini_hp(pos, e.hp as int, e.max_hp as int)

	# Player
	_draw_player()

func _draw_entity_box(pos: Vector2i, color: Color, glyph: String) -> void:
	var bx := pos.x * TILE_SIZE + 2
	var by := pos.y * TILE_SIZE + 2
	var sz := TILE_SIZE - 4
	draw_rect(Rect2(bx, by, sz, sz), Color(color.r * 0.3, color.g * 0.3, color.b * 0.3))
	draw_rect(Rect2(bx, by, sz, 2), color)
	draw_rect(Rect2(bx, by + sz - 2, sz, 2), Color(color.r * 0.5, color.g * 0.5, color.b * 0.5))
	draw_rect(Rect2(bx, by, 2, sz), color)
	draw_rect(Rect2(bx + sz - 2, by, 2, sz), Color(color.r * 0.5, color.g * 0.5, color.b * 0.5))
	draw_string(font, Vector2(pos.x * TILE_SIZE + 6, pos.y * TILE_SIZE + TILE_SIZE - 5), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, TILE_SIZE - 6, color)

func _draw_player() -> void:
	var pos: Vector2i = player.pos as Vector2i
	var bx  := pos.x * TILE_SIZE + 2
	var by  := pos.y * TILE_SIZE + 2
	var sz  := TILE_SIZE - 4
	# Glowing border
	draw_rect(Rect2(bx - 1, by - 1, sz + 2, sz + 2), Color(C_PLAYER.r, C_PLAYER.g, C_PLAYER.b, 0.4))
	draw_rect(Rect2(bx, by, sz, sz), C_PLAYER2)
	draw_rect(Rect2(bx, by, sz, 2), C_PLAYER)
	draw_rect(Rect2(bx, by, 2, sz), C_PLAYER)
	draw_rect(Rect2(bx + sz - 2, by, 2, sz), C_PLAYER)
	draw_rect(Rect2(bx, by + sz - 2, sz, 2), C_PLAYER)
	draw_string(font, Vector2(pos.x * TILE_SIZE + 6, pos.y * TILE_SIZE + TILE_SIZE - 5), "@", HORIZONTAL_ALIGNMENT_LEFT, -1, TILE_SIZE - 6, C_PLAYER)

func _draw_mini_hp(pos: Vector2i, hp: int, max_hp: int) -> void:
	var ratio := float(hp) / float(max_hp)
	var bx    := pos.x * TILE_SIZE + 2
	var by    := pos.y * TILE_SIZE
	draw_rect(Rect2(bx, by, TILE_SIZE - 4, 3), Color("#440000"))
	var col := C_HP_FULL
	if ratio < 0.5:
		col = C_HP_MID
	if ratio < 0.25:
		col = C_HP_LOW
	draw_rect(Rect2(bx, by, int((TILE_SIZE - 4) * ratio), 3), col)

# ─── HUD Drawing ─────────────────────────────────────────────────────────────
func _draw_hud(node: Control) -> void:
	var W := node.size.x
	var H := node.size.y

	# Right HUD panel (fixed 200px on the right)
	var hud_x := W - 200.0
	draw_hud_rect(node, Rect2(hud_x, 0, 200, H), C_HUD_BG)
	draw_hud_line(node, Vector2(hud_x, 0), Vector2(hud_x, H), C_HUD_BORD, 2)

	# Shard name / title
	var shard_col: Color = shard.get("color", C_CYAN)
	_hud_text(node, "CRYPTS", hud_x + 100, 16, 13, shard_col, true)
	_hud_text(node, shard.name as String, hud_x + 100, 28, 10, shard_col, true)

	draw_hud_line(node, Vector2(hud_x + 4, 32), Vector2(W - 4, 32), C_HUD_BORD, 1)

	# HP bar
	var hp_ratio := float(player.hp) / float(player.max_hp)
	var hp_col   := C_HP_FULL
	if hp_ratio < 0.5: hp_col = C_HP_MID
	if hp_ratio < 0.25: hp_col = C_HP_LOW
	_hud_text(node, "HP %d/%d" % [player.hp, player.max_hp], hud_x + 6, 47, 11, C_WHITE)
	draw_hud_rect(node, Rect2(hud_x + 4, 50, 192, 10), Color("#220000"))
	draw_hud_rect(node, Rect2(hud_x + 4, 50, int(192 * hp_ratio), 10), hp_col)
	draw_hud_rect_border(node, Rect2(hud_x + 4, 50, 192, 10), C_HUD_BORD)

	# XP bar
	var xp_ratio := float(player.exp) / float(player.exp_next)
	_hud_text(node, "LV%d  XP" % player.level, hud_x + 6, 73, 11, C_XP_BAR)
	draw_hud_rect(node, Rect2(hud_x + 4, 76, 192, 8), Color("#000011"))
	draw_hud_rect(node, Rect2(hud_x + 4, 76, int(192 * xp_ratio), 8), C_XP_BAR)
	draw_hud_rect_border(node, Rect2(hud_x + 4, 76, 192, 8), C_HUD_BORD)

	# Stats row
	_hud_text(node, "ATK %d  DEF %d" % [player.attack, player.defense], hud_x + 6, 96, 11, C_WHITE)
	_hud_text(node, "GOLD %d G" % player.gold, hud_x + 6, 110, 11, C_GOLD)
	_hud_text(node, "FLOOR %d" % current_floor, hud_x + 6, 124, 11, C_YELLOW)
	_hud_text(node, "SCORE %d" % total_score, hud_x + 6, 138, 11, C_CYAN)

	draw_hud_line(node, Vector2(hud_x + 4, 143), Vector2(W - 4, 143), C_HUD_BORD, 1)

	# Log panel (middle of right panel)
	var log_y := 148.0
	for i in min(log_messages.size(), 4):
		var msg: Dictionary = log_messages[log_messages.size() - 1 - i]
		var alpha: float = 1.0 - i * 0.22
		var mc: Color = msg.color as Color
		var col   := Color(mc.r, mc.g, mc.b, alpha)
		_hud_text(node, msg.text as String, hud_x + 6, log_y + i * 16, 10, col)

	draw_hud_line(node, Vector2(hud_x + 4, log_y + 68), Vector2(W - 4, log_y + 68), C_HUD_BORD, 1)

	# D-pad at bottom of right panel
	_draw_dpad(node, hud_x, H)

	# Scrolls
	if player.scrolls > 0:
		_hud_text(node, "[F] Fire x%d" % player.scrolls, hud_x + 100, H - 4, 10, C_SCROLL, true)

	# Top-left tiny overlay: floor number on dungeon view
	draw_hud_rect(node, Rect2(0, 0, hud_x, 18), Color(0, 0, 0, 0.5))
	_hud_text(node, "F%d  Score:%d  Gold:%dG" % [current_floor, total_score, player.gold], 4, 14, 11, C_YELLOW)

	# Game over overlay
	if state == State.GAME_OVER:
		draw_hud_rect(node, Rect2(0, 0, W, H), Color(0, 0, 0, 0.7))
		_hud_text(node, "YOU DIED", W / 2, H / 2 - 20, 36, C_RED, true)
		_hud_text(node, "Score: %d" % total_score, W / 2, H / 2 + 20, 20, C_WHITE, true)

	# Floor transition overlay
	if state == State.FLOOR_DONE:
		var a: float = min(1.0, 1.0 - floor_trans_timer)
		draw_hud_rect(node, Rect2(0, 0, W, H), Color(0, 0, 0, a * 0.8))
		_hud_text(node, "FLOOR %d" % (current_floor + 1), W / 2, H / 2, 32, C_CYAN, true)

func _draw_dpad(node: Control, hud_x: float, H: float) -> void:
	var cx  := hud_x + 100.0
	var bs  := 42.0
	var gap := 4.0
	var py  := H - bs * 2.0 - gap - 6.0
	# Up
	_draw_btn(node, cx - bs/2, py - bs - gap, bs, bs, "▲", C_HUD_BG, C_HUD_BORD)
	# Down
	_draw_btn(node, cx - bs/2, py, bs, bs, "▼", C_HUD_BG, C_HUD_BORD)
	# Left
	_draw_btn(node, cx - bs*1.5 - gap, py - bs/2 - gap/2, bs, bs, "◀", C_HUD_BG, C_HUD_BORD)
	# Right
	_draw_btn(node, cx + bs/2 + gap, py - bs/2 - gap/2, bs, bs, "▶", C_HUD_BG, C_HUD_BORD)
	# Wait
	_draw_btn(node, cx - bs/2, py - bs/2 - gap/2, bs, bs, "•", C_HUD_BG, C_HUD_BORD)

func _draw_btn(node: Control, x: float, y: float, w: float, h: float, label: String, bg: Color, border: Color) -> void:
	draw_hud_rect(node, Rect2(x, y, w, h), bg)
	draw_hud_rect_border(node, Rect2(x, y, w, h), border)
	_hud_text(node, label, x + w / 2, y + h / 2 + 7, 18, C_WHITE, true)

func _hud_text(node: Control, text: String, x: float, y: float, size: int, color: Color, center: bool = false) -> void:
	var align := HORIZONTAL_ALIGNMENT_LEFT
	if center:
		align = HORIZONTAL_ALIGNMENT_CENTER
	node.draw_string(font, Vector2(x, y), text, align, -1, size, color)

func draw_hud_rect(node: Control, rect: Rect2, color: Color) -> void:
	node.draw_rect(rect, color)

func draw_hud_rect_border(node: Control, rect: Rect2, color: Color) -> void:
	node.draw_rect(rect, color, false, 1.5)

func draw_hud_line(node: Control, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	node.draw_line(from, to, color, width)

# ─── HUD Touch ───────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if state != State.PLAYER_TURN:
		return
	if not (event is InputEventScreenTouch):
		return
	var te := event as InputEventScreenTouch
	if not te.pressed:
		return

	var vp_size := get_viewport().get_visible_rect().size
	var W       := vp_size.x
	var H       := vp_size.y
	var pos     := te.position
	var hud_x   := W - 200.0
	var bs      := 42.0
	var cx      := hud_x + 100.0
	var gap     := 4.0
	var py      := H - bs * 2.0 - gap - 6.0

	# Up button
	if Rect2(cx - bs/2, py - bs - gap, bs, bs).has_point(pos):
		_player_move(Vector2i(0, -1))
		get_viewport().set_input_as_handled()
	# Down button
	elif Rect2(cx - bs/2, py, bs, bs).has_point(pos):
		_player_move(Vector2i(0, 1))
		get_viewport().set_input_as_handled()
	# Left button
	elif Rect2(cx - bs*1.5 - gap, py - bs/2 - gap/2, bs, bs).has_point(pos):
		_player_move(Vector2i(-1, 0))
		get_viewport().set_input_as_handled()
	# Right button
	elif Rect2(cx + bs/2 + gap, py - bs/2 - gap/2, bs, bs).has_point(pos):
		_player_move(Vector2i(1, 0))
		get_viewport().set_input_as_handled()
	# Wait button
	elif Rect2(cx - bs/2, py - bs/2 - gap/2, bs, bs).has_point(pos):
		state = State.ENEMY_TURN
		_start_enemy_turn()
		get_viewport().set_input_as_handled()
