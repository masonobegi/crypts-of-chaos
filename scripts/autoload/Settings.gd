extends Node
## Player-facing options, and the one place they are stored.
##
## There were none. No volume, no mouse sensitivity, no fullscreen, no way to
## turn the camera shake off — in a first-person game that is the difference
## between "a demo" and "software somebody can use", and it is the single
## cheapest thing on the list of what this needs before anyone plays it.
##
## Deliberately NOT part of the save file. Settings belong to the machine, not
## to the career: loading somebody else's save should not change your mouse
## sensitivity, and starting a new run should not reset your volume.

const PATH := "user://settings.cfg"

## Defaults are the values the game shipped with before there was a screen for
## any of it, so an existing player who never opens this sees no change.
const DEFAULTS := {
	"master_volume": 0.7,
	"sfx_volume": 1.0,
	"music_volume": 0.55,
	"mouse_sensitivity": 1.0,     ## multiplier on Player.MOUSE_SENS
	"invert_y": false,
	"fov": 78.0,
	"fullscreen": false,
	"vsync": true,
	"camera_shake": 1.0,          ## 0 turns it off entirely — accessibility
	"head_bob": 1.0,
	"subtitles": true,
	"show_damage_flash": true,
}

var values: Dictionary = {}

signal changed(key: String)

func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	load_from_disk()
	apply_all()

func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))

func set_value(key: String, v: Variant, persist := true) -> void:
	if not DEFAULTS.has(key):
		Log.w("unknown setting '%s'" % key, "Settings")
		return
	values[key] = v
	_apply(key)
	changed.emit(key)
	if persist:
		save_to_disk()

func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate(true)
	apply_all()
	save_to_disk()
	changed.emit("")

# ------------------------------------------------------------------ applying
func apply_all() -> void:
	for k in DEFAULTS:
		_apply(k)

func _apply(key: String) -> void:
	match key:
		"master_volume", "sfx_volume", "music_volume":
			if Engine.has_singleton("AudioMgr") or AudioMgr != null:
				AudioMgr.master_volume = float(get_value("master_volume"))
				AudioMgr.sfx_volume = float(get_value("sfx_volume"))
				AudioMgr.music_volume = float(get_value("music_volume"))
		"fullscreen":
			# Guarded: a headless run has no window to resize, and every test
			# harness in this project is headless.
			if DisplayServer.get_name() == "headless":
				return
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if bool(get_value("fullscreen"))
				else DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			if DisplayServer.get_name() == "headless":
				return
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(get_value("vsync"))
				else DisplayServer.VSYNC_DISABLED)
		"fov":
			var p = _player()
			if p != null and p.camera != null:
				p.camera.fov = float(get_value("fov"))

func _player():
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).get_first_node_in_group("player")

# ------------------------------------------------------------------ disk
func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("options", k, values[k])
	cfg.save(PATH)

func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		if cfg.has_section_key("options", k):
			# Typed against the default, so a hand-edited file that says
			# "loud" for a float cannot take the audio bus with it.
			var raw: Variant = cfg.get_value("options", k)
			if typeof(raw) == typeof(DEFAULTS[k]):
				values[k] = raw
