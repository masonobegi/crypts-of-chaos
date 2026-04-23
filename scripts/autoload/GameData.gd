extends Node

## Global game state shared between scenes

var selected_shard_index: int = 0
var run_score: int = 0
var run_floor: int = 1
var run_kills: int = 0
var run_gold: int = 0
var player_name: String = "HERO"

const SHARDS: Array = [
	{
		"name": "Iron Shard",
		"subtitle": "The Warrior's Crest",
		"description": "+20 Max HP  |  +2 Attack\nStart with a Steel Sword\nSolid and reliable.",
		"color": Color("#8899dd"),
		"bg_color": Color("#111133"),
		"border_color": Color("#aabbff"),
		"bonus_hp": 20,
		"bonus_attack": 2,
		"bonus_defense": 0,
		"start_gold": 10,
		"score_mult": 1.0,
		"special": "warrior",
		"start_item": "sword"
	},
	{
		"name": "Shadow Shard",
		"subtitle": "The Rogue's Favor",
		"description": "+1 Speed  |  Double gold drops\nStart with a Poison Dagger\nStrike from the dark.",
		"color": Color("#cc44cc"),
		"bg_color": Color("#1a0022"),
		"border_color": Color("#ff66ff"),
		"bonus_hp": -5,
		"bonus_attack": 1,
		"bonus_defense": 0,
		"start_gold": 30,
		"score_mult": 1.25,
		"special": "rogue",
		"start_item": "dagger"
	},
	{
		"name": "Arcane Shard",
		"subtitle": "The Mage's Grimoire",
		"description": "Start with 3 Fire Scrolls\n+4 Spell Power  |  -10 Max HP\nHarness forbidden fire.",
		"color": Color("#4488ff"),
		"bg_color": Color("#000a22"),
		"border_color": Color("#66aaff"),
		"bonus_hp": -10,
		"bonus_attack": 4,
		"bonus_defense": -1,
		"start_gold": 5,
		"score_mult": 1.35,
		"special": "mage",
		"start_item": "scroll_fire"
	},
	{
		"name": "Golden Shard",
		"subtitle": "The Merchant's Mark",
		"description": "Start with 80 Gold\nShop prices -30%  |  +1 Defense\nWealth is power.",
		"color": Color("#ffcc00"),
		"bg_color": Color("#221a00"),
		"border_color": Color("#ffee66"),
		"bonus_hp": 0,
		"bonus_attack": 0,
		"bonus_defense": 1,
		"start_gold": 80,
		"score_mult": 1.1,
		"special": "merchant",
		"start_item": "none"
	},
	{
		"name": "Cursed Shard",
		"subtitle": "The Berserker's Oath",
		"description": "2.5x Score Multiplier\n-15 Max HP  |  Rage as HP drops\nChaos fuels your might.",
		"color": Color("#ff3333"),
		"bg_color": Color("#220000"),
		"border_color": Color("#ff6666"),
		"bonus_hp": -15,
		"bonus_attack": 5,
		"bonus_defense": -2,
		"start_gold": 0,
		"score_mult": 2.5,
		"special": "berserker",
		"start_item": "none"
	},
	{
		"name": "Holy Shard",
		"subtitle": "The Cleric's Blessing",
		"description": "Regen 3 HP per floor\n+4 Max HP on level up\nStart with Holy Water",
		"color": Color("#ffffaa"),
		"bg_color": Color("#1a1a00"),
		"border_color": Color("#ffffdd"),
		"bonus_hp": 15,
		"bonus_attack": 0,
		"bonus_defense": 2,
		"start_gold": 15,
		"score_mult": 1.0,
		"special": "cleric",
		"start_item": "holy_water"
	},
	{
		"name": "Void Shard",
		"subtitle": "The Chaos Conduit",
		"description": "Random bonus stats each run\nBonus item each floor\n1.5x Score Multiplier",
		"color": Color("#aa00ff"),
		"bg_color": Color("#0d0019"),
		"border_color": Color("#cc44ff"),
		"bonus_hp": 0,
		"bonus_attack": 0,
		"bonus_defense": 0,
		"start_gold": 20,
		"score_mult": 1.5,
		"special": "void",
		"start_item": "random"
	},
	{
		"name": "Ancient Shard",
		"subtitle": "The Scholar's Eye",
		"description": "Full map revealed from start\nAll items auto-identified\n+8% score per room cleared",
		"color": Color("#44ffaa"),
		"bg_color": Color("#001a0d"),
		"border_color": Color("#88ffcc"),
		"bonus_hp": 5,
		"bonus_attack": 0,
		"bonus_defense": 1,
		"start_gold": 10,
		"score_mult": 1.2,
		"special": "scholar",
		"start_item": "map_scroll"
	}
]

func get_shard() -> Dictionary:
	return SHARDS[selected_shard_index]

func reset_run():
	run_score = 0
	run_floor = 1
	run_kills = 0
	run_gold = 0
