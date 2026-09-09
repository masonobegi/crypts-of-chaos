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

## Does a file exist in this slot. DELIBERATELY NOT "is it loadable" — this is
## called from the title screen's build and from its confirm arm, and making it
## parse would open and JSON-decode the file on every menu draw AND leave two
## functions (this and `list_saves`) reading the same file under different rules,
## which is the two-definitions fault CLAUDE.md 48 and 55 are both about.
## Anything that needs to know whether a save is READABLE asks `list_saves()`.
func has_save(slot: String = AUTOSAVE) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## Is there a career here that can actually be resumed. This is the question the
## `Continue` button is asking, and it used to ask `has_save` — a file-exists
## test — so a truncated, half-written or hand-mangled autosave produced a bare
## `Continue` button with no day and no money on it, which reads as a cosmetic
## glitch rather than as the broken save it is.
func readable_save(slot: String = AUTOSAVE) -> Dictionary:
	for row in list_saves():
		if String(row.get("slot", "")) == slot:
			return row
	return {}

func backup_path(slot: String) -> String:
	return slot_path(slot) + ".bak"

## Write, atomically, keeping the previous file.
##
## The first version opened the REAL path with FileAccess.WRITE, which truncates,
## and then wrote into it — so a crash, a full disk or a power cut inside that
## window destroyed a nine-night career and left a zero-length file where it had
## been. There is one slot and no way back from that.
##
## Now: write the temporary, close it, rename the old one aside as `.bak`, rename
## the temporary into place. `load_game` falls back to the `.bak` when the
## primary will not parse, so the worst a torn write costs is one shift.
func save_game(slot: String = AUTOSAVE) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game_state": GameState.to_dict(),
		"systems": {},
	}
	for key in _providers:
		var fn: Callable = _providers[key]["save"]
		# A Callable bound to a freed node reports invalid, which is what makes
		# binding save providers to METHODS rather than to lambdas load-bearing:
		# a lambda that captured a node stays "valid" after the node is gone and
		# throws on the next save instead of being skipped.
		if fn.is_valid():
			payload["systems"][key] = fn.call()
	var real := slot_path(slot)
	var tmp := real + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Log.e("could not open save slot %s (%s)" % [slot, error_string(FileAccess.get_open_error())], "Save")
		EventBus.toast.emit("Could not save the shift. Check disk space.", "bad")
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	if FileAccess.file_exists(real):
		DirAccess.remove_absolute(backup_path(slot))
		DirAccess.rename_absolute(real, backup_path(slot))
	var err := DirAccess.rename_absolute(tmp, real)
	if err != OK:
		Log.e("could not replace save slot %s (%s)" % [slot, error_string(err)], "Save")
		EventBus.toast.emit("Could not save the shift. Check disk space.", "bad")
		return false
	Log.i("saved slot '%s' (day %d)" % [slot, GameState.day], "Save")
	return true

func load_game(slot: String = AUTOSAVE) -> bool:
	var data := _read(slot_path(slot), slot)
	if data.is_empty():
		# ONE SHIFT, NOT A CAREER. The primary is unreadable; the file that was
		# in that slot before tonight's handover still is.
		data = _read(backup_path(slot), slot + " (backup)")
		if data.is_empty():
			return false
		Log.w("save slot %s was unreadable; recovered the previous shift" % slot, "Save")
		EventBus.toast.emit("Today's save was damaged. Recovered the shift before it.", "bad")
	GameState.from_dict(data.get("game_state", {}))
	var systems: Dictionary = data.get("systems", {})
	for key in _providers:
		var fn: Callable = _providers[key]["load"]
		if fn.is_valid() and systems.has(key):
			fn.call(systems[key])
	EventBus.game_loaded.emit()
	Log.i("loaded slot '%s' (day %d)" % [slot, GameState.day], "Save")
	return true

## Read one save file and hand back a payload that is safe to restore from, or
## an empty dictionary. EVERY refusal is a refusal: the old code returned false
## only for a file that would not parse as a dictionary, so `[1,2,3]`, `{}` and a
## save written by a NEWER build all sailed through into `GameState.from_dict`,
## which defaults every field it cannot find — day 1, no cash, seed 0, and a
## `debt_remaining` falling back through `flag()`. That is not a failed load, it
## is a career that looks new and is not one: `start_new_career()` never ran, so
## `DoctorRecord.wipe()` never ran either and last career's strikes were still on
## the record.
func _read(path: String, what: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.e("could not open %s" % what, "Save")
		return {}
	var txt := f.get_as_text()
	f.close()
	# A JSON INSTANCE, NOT `JSON.parse_string`. The static helper pushes the
	# engine's own "Parse JSON failed. Error at line 0: Expected '}'" on top of
	# whatever this function then says, so a player with one damaged file got two
	# errors in the log, one of them about a line number in a file they have
	# never opened. `JSON.new().parse()` returns the code and says nothing, which
	# leaves one line that names the slot and what is wrong with it.
	var reader := JSON.new()
	if reader.parse(txt) != OK or typeof(reader.data) != TYPE_DICTIONARY:
		Log.e("save %s is corrupt (not a save file)" % what, "Save")
		return {}
	var data: Dictionary = reader.data
	if typeof(data.get("game_state")) != TYPE_DICTIONARY:
		Log.e("save %s is corrupt (no career in it)" % what, "Save")
		return {}
	var ver := int(data.get("version", 0))
	if ver > SAVE_VERSION:
		# A DOWNGRADE IS NOT A MIGRATION. Loading a future save's fields into
		# today's schema silently drops whatever it gained and keeps whatever it
		# renamed, and the player finds out several shifts later.
		Log.e("save %s is from a newer version (%d > %d)" % [what, ver, SAVE_VERSION], "Save")
		return {}
	if ver != SAVE_VERSION:
		data = _migrate(data, ver)
		if data.is_empty():
			return {}
	return data

func delete_save(slot: String = AUTOSAVE) -> void:
	# The backup too. `screen_day_over` deletes the autosave when a career ends
	# so "Continue — Day 9" cannot resurrect a struck-off doctor; leaving the
	# `.bak` behind would have `load_game` recover him from it on the next press.
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))
	if FileAccess.file_exists(backup_path(slot)):
		DirAccess.remove_absolute(backup_path(slot))

## Every slot that can actually be resumed, summarised for the title screen.
##
## Reads through `_read`, so "a row appears here" and "load_game will succeed"
## are the SAME test rather than two that agree by coincidence — a listing that
## was more permissive than the loader is what put a `Continue` button on the
## title screen for a save the loader then refused. The `.bak` and `.tmp` files
## are not listed: they are not slots, and the loader reaches them on its own.
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var slot := fname.trim_suffix(".json")
		var parsed := _read(slot_path(slot), slot)
		if parsed.is_empty():
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

## Bring an older save's shape up to the current one, or refuse it.
##
## The first version logged a warning and returned `data` UNCHANGED for any
## version at all, which is not a migration hook, it is a hole: a v0 file (that
## is, anything without a `version` key — a hand-edited file, or a truncated one
## that JSON happened to accept) was handed straight to the loader as though it
## were current. An unhandled version is a refusal now, and refusing is what
## routes the player to "that save could not be read" instead of into a career
## with somebody else's flags in it.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	match from_version:
		# No shipped migrations yet. The first one goes here as
		#   1: data = _v1_to_v2(data); continue
		# and SAVE_VERSION goes up with it.
		_:
			Log.e("save is from an unknown version (%d, this build reads %d)"
				% [from_version, SAVE_VERSION], "Save")
			return {}
