extends Node

## Handles saving and loading high scores to a local JSON file

const SAVE_PATH := "user://high_scores.json"
const MAX_SCORES := 10

var high_scores: Array = []

func _ready() -> void:
	load_scores()

func load_scores() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		high_scores = []
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		high_scores = []
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) == OK:
		high_scores = json.get_data()
	else:
		high_scores = []

func save_score(score: int, player_name: String, shard_name: String, floor_reached: int, kills: int) -> void:
	var entry := {
		"score": score,
		"name": player_name,
		"shard": shard_name,
		"floor": floor_reached,
		"kills": kills,
		"date": Time.get_date_string_from_system()
	}
	high_scores.append(entry)
	high_scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"]
	)
	if high_scores.size() > MAX_SCORES:
		high_scores.resize(MAX_SCORES)
	_write_scores()

func _write_scores() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(high_scores, "\t"))
	file.close()

func get_high_score() -> int:
	if high_scores.is_empty():
		return 0
	return int(high_scores[0]["score"])

func is_new_high_score(score: int) -> bool:
	return score > 0 and (high_scores.size() < MAX_SCORES or score > get_high_score())

func get_rank(score: int) -> int:
	for i in high_scores.size():
		if score >= int(high_scores[i]["score"]):
			return i + 1
	return high_scores.size() + 1
