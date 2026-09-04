extends Node
## JSON saves. Deliberately plain-dictionary rather than Resource-based so a
## save from an older build can be migrated by hand instead of failing to load.

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const AUTOSAVE := "autosave"

## Systems register themselves here; each contributes one dictionary. Adding a
## new system to saves is one line at its _ready().
var _providers: Dictionary = {}   ## key -> Callable pair {save, load}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func register(key: String, save_fn: Callable, load_fn: Callable) -> void:
	_providers[key] = {"save": save_fn, "load": load_fn}

func unregister(key: String) -> void:
	_providers.erase(key)

func slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]

func has_save(slot: String = AUTOSAVE) -> bool:
	return FileAccess.file_exists(slot_path(slot))

func save_game(slot: String = AUTOSAVE) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game_state": GameState.to_dict(),
		"systems": {},
	}
	for key in _providers:
		var fn: Callable = _providers[key]["save"]
		if fn.is_valid():
			payload["systems"][key] = fn.call()
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		Log.e("could not open save slot %s" % slot, "Save")
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	Log.i("saved slot '%s' (day %d)" % [slot, GameState.day], "Save")
	return true

func load_game(slot: String = AUTOSAVE) -> bool:
	if not has_save(slot):
		return false
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.e("save slot %s is corrupt" % slot, "Save")
		return false
	var data: Dictionary = parsed
	var ver := int(data.get("version", 0))
	if ver != SAVE_VERSION:
		data = _migrate(data, ver)
	GameState.from_dict(data.get("game_state", {}))
	var systems: Dictionary = data.get("systems", {})
	for key in _providers:
		var fn: Callable = _providers[key]["load"]
		if fn.is_valid() and systems.has(key):
			fn.call(systems[key])
	EventBus.game_loaded.emit()
	Log.i("loaded slot '%s' (day %d)" % [slot, GameState.day], "Save")
	return true

func delete_save(slot: String = AUTOSAVE) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))

func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var slot := fname.trim_suffix(".json")
		var f := FileAccess.open(slot_path(slot), FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var gs: Dictionary = parsed.get("game_state", {})
		out.append({
			"slot": slot,
			"day": int(gs.get("day", 1)),
			# "cash", not "pm". `pm` was the field name in the save schema that
			# was deleted in the redesign, so the one place the game summarises
			# a saved career for the player — "Continue — Day 9, $0" — read zero
			# on every save that has ever existed, which looks exactly like a
			# corrupt save.
			"money": int(gs.get("cash", 0)),
			"saved_at": parsed.get("saved_at", "?"),
		})
	return out

func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	Log.w("migrating save from v%d to v%d" % [from_version, SAVE_VERSION], "Save")
	# No migrations yet; the hook exists so shipping one later is trivial.
	return data
