extends RefCounted
## CAN A STRANGER BUY THIS, INSTALL IT, PLAY IT, QUIT, AND COME BACK.
##
## Every other layer in `tests/` asks whether the GAME works. This one asks
## whether the BUILD does, which is a different set of questions and had nothing
## looking at it at all: what the file calls itself, what happens when the save
## on disk is not a save, whether the randomness a career runs on survives being
## reloaded, whether a shipped build leaves an artefact behind when it crashes,
## and how long the screen is frozen between pressing New Career and standing in
## the ward.
##
## None of it is reachable from the property tests, because none of it is a
## property of the ward. All of it is the first ten minutes of owning the game.

var tree: SceneTree = null
var bad := 0
var checks := 0
var game: Node = null
var frames := 0
var stage := "static"

## A slot of our own. `list_saves()` walks the whole directory, so a probe that
## used AUTOSAVE would both read and destroy whatever career is sitting in the
## container's user:// from the last harness that ran.
const SLOT := "ship_probe"

const AUTOLOADS := ["GameState", "EventBus", "AudioMgr", "RNG", "DB", "Settings",
	"SaveSystem", "Log"]

## HOW LONG THE TITLE SCREEN IS ALLOWED TO SIT FROZEN, in milliseconds.
##
## `Game._ready` builds the environment, the whole procedural hospital, every
## system, the player, the staff and the UI synchronously, and until it returns
## the last drawn menu frame is still on screen. `--fixed-fps` reports a stalled
## frame as a sixtieth of a second however long it really took, which is why no
## harness could see this and why the number has to be taken with a clock rather
## than counted in frames.
##
## Measured on this container at 312 ms, of which 120 ms is `Hospital.build()`.
## The budget is roughly five times that: it is a regression alarm — somebody
## quadrupled the build — and not a performance bar that goes red on a slow
## laptop, because a number that fails on hardware nobody in this repo has is a
## number everybody learns to re-run.
const BUILD_BUDGET_MSEC := 1500

## AND THE ALLOWLIST IS EMPTY, WHICH IS WHERE IT SHOULD ALWAYS END UP.
##
## It held one entry for about an hour: `patient_npc.gd` read
## `GameState.shift_kind`, which went with the three shift types, inside
## `_on_shift_started`, which had no caller — so it threw nothing only because
## nothing reached it. The excuse was deliberately not a mute; the check below
## FAILS when an entry stops matching anything, so whoever fixed the read was
## told to delete the line rather than leave a permanent hole behind them. That
## is what happened: the sleeping-patient system is wired to the one clock the
## game actually has, and the read is gone.
##
## Leave this empty. If something has to go in it, write down why here, and the
## check will make sure it comes out again.
const KNOWN_DEAD_READS := {}

func _ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok    " + what)
	else:
		bad += 1
		print("  FAIL  " + what)

# ============================================================== the static half
func run_static() -> void:
	print("\n--- what the build calls itself ---")
	_check_the_build_has_a_name_and_one_version()
	print("\n--- what it prints when it goes wrong ---")
	_check_a_crash_leaves_something_to_send()
	print("\n--- what the compiler cannot see ---")
	_check_no_autoload_read_is_a_throw()
	print("\n--- the save on disk is not always a save ---")
	_check_rubbish_in_a_save_slot_is_refused()
	_check_a_torn_write_costs_one_shift_and_not_a_career()
	print("\n--- the randomness a career runs on ---")
	_check_a_stream_resumes_where_it_stopped()
	print("\n--- the licences that have to travel with the build ---")
	_check_every_licence_the_build_owes_is_in_it()

## The identity fields, which are invisible from inside the game and therefore
## from every harness in this repo.
##
## It shipped as `com.example.chroniccare` — the bundle id Apple refuses — by a
## company called "—", which is the string Windows puts in the file's Details
## tab, at version 0.1.0, while `config/version` said 0.1.0 and was read by
## nothing anywhere in `scripts/`. Four places to write a version number is three
## copies waiting to disagree (gotcha 48), so this asserts they are the same
## number rather than that any particular one is right.
func _check_the_build_has_a_name_and_one_version() -> void:
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	_ok(version != "" and version != "0.1.0",
		"project.godot names a version (%s)" % version)
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	_ok(not presets.contains("com.example"),
		"no placeholder bundle identifier")
	_ok(not presets.contains('company_name="—"'),
		"no placeholder company name")
	var mismatched: Array = []
	for field in ["application/short_version", "application/version",
			"application/file_version", "application/product_version"]:
		if not presets.contains(field + "="):
			continue
		if not presets.contains('%s="%s"' % [field, version]):
			mismatched.append(field)
	_ok(mismatched.is_empty(), "every export preset carries the same version%s"
		% ("" if mismatched.is_empty()
			else " — stale: " + ", ".join(PackedStringArray(mismatched))))
	# AND THE GAME CAN SAY IT OUT LOUD. A build number nothing displays cannot
	# reach a bug report, because the artefact a player sends is a photograph of
	# their screen.
	var menu: GDScript = load("res://scripts/ui/main_menu.gd")
	_ok(menu != null and String(menu.version_string()).contains(version),
		"and the title screen prints it (%s)" % (
			"" if menu == null else menu.version_string()))

## A shipped build's stdout goes nowhere. Godot's `file_logging` defaults to off
## for a release export, so `Log`'s 400-line ring — whose own docstring says it
## exists "so the bug-report dump can show recent history" — was being written to
## a console no buyer has open. "It crashes on day three" with no artefact to ask
## for is the end of that conversation.
func _check_a_crash_leaves_something_to_send() -> void:
	_ok(bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging", false)),
		"a shipped build writes a log file")
	_ok(int(ProjectSettings.get_setting("debug/file_logging/max_log_files", 0)) >= 2,
		"and keeps more than one of them")

## THE OTHER HALF OF GOTCHA 20, and it is the half that cost a whole verb.
##
## smoke_impl's check greps `Autoload.method(` and asks the autoload whether it
## has one. It requires the `(`, so a PROPERTY read is skipped entirely — and
## `GameState.stats.items_broken += 1` in `prop.gd` was a read of a dictionary
## deleted with the career stats, which throws, and a throw ABORTS THE FUNCTION.
## Everything below that line in `_break()` had silently not run for as long as
## the deletion: no `item_broke` signal (the camera kick), no `soil()` on the
## room, no `prop_broken` WorldEvent carrying the mess and facilities tags that
## four rules read, no darkened material, no un-freeze. A prop broke, played a
## glass sound, and stayed pristine.
##
## Proven red by putting `GameState.nonsense` back into a script.
func _check_no_autoload_read_is_a_throw() -> void:
	var missing: Array = []
	var excused := {}
	var read_count := 0
	for path in _all_scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		for name in AUTOLOADS:
			var node := tree.root.get_node_or_null(NodePath(name))
			if node == null:
				continue
			var members := _members_of(node)
			for m in _reads_on(src, name):
				read_count += 1
				if members.has(m):
					continue
				var file := String(path).get_file()
				if KNOWN_DEAD_READS.has(file) and Array(KNOWN_DEAD_READS[file]).has(m):
					excused["%s/%s" % [file, m]] = true
					continue
				missing.append("%s.%s in %s" % [name, m, file])
	_ok(read_count > 40, "%d autoload property reads to check" % read_count)
	_ok(missing.is_empty(), "and every one of them resolves%s"
		% ("" if missing.is_empty() else " — " + ", ".join(PackedStringArray(missing))))
	# THE EXCUSE HAS TO STILL BE TRUE. An allowlist that outlives the fault it
	# was written for is a permanent hole in the check, so a stale entry is a
	# failure and the message says what to do about it.
	var want := 0
	for f in KNOWN_DEAD_READS:
		want += Array(KNOWN_DEAD_READS[f]).size()
	_ok(excused.size() == want,
		"the %d known dead read(s) are all still there (delete the KNOWN_DEAD_READS entry when one is fixed)"
			% want)

## A CORRUPT SAVE MUST NOT LOOK LIKE A NEW CAREER.
##
## `load_game` used to refuse only a file that would not parse as a dictionary,
## so `[1,2,3]`, `{}` and a save from a NEWER build all reached
## `GameState.from_dict`, which defaults every field it cannot find. The player
## got day 1, no cash, seed 0 and a debt falling back through `flag()` — without
## `start_new_career()`, so `DoctorRecord.wipe()` never ran and the previous
## career's strikes were still on the record. That is not a failed load, it is a
## career that looks new and is not one, and the only symptom was a `Continue`
## button with no day printed on it.
func _check_rubbish_in_a_save_slot_is_refused() -> void:
	var cases := {
		"a truncated write": "{",
		"the wrong shape entirely": "[1, 2, 3]",
		"a save with no career in it": '{"version": 1, "saved_at": "x"}',
		"a save from a newer build": '{"version": 99, "game_state": {"day": 4}}',
		"a save from an unknown older build": '{"version": 0, "game_state": {"day": 4}}',
		"nothing at all": "",
	}
	var refused: Array = []
	for what in cases:
		_write_slot(String(cases[what]))
		var loaded: bool = SaveSystem.load_game(SLOT)
		var listed: bool = not SaveSystem.readable_save(SLOT).is_empty()
		if loaded or listed:
			refused.append(what)
	SaveSystem.delete_save(SLOT)
	_ok(refused.is_empty(), "every unreadable save is refused, and offered to nobody%s"
		% ("" if refused.is_empty() else " — accepted: " + ", ".join(PackedStringArray(refused))))
	# AND THE TITLE SCREEN AGREES WITH THE LOADER. A listing more permissive
	# than the loader is what put a bare "Continue" on the screen for a save the
	# loader then refused — two functions reading one file under two sets of
	# rules, which is the fault CLAUDE.md 48 and 55 are both about.
	_ok(SaveSystem.readable_save(SLOT).is_empty(),
		"and a slot with no file in it offers nothing")

## A TORN WRITE COSTS ONE SHIFT, NOT NINE NIGHTS.
##
## `save_game` opened the real path with FileAccess.WRITE, which truncates, and
## then wrote into it. A crash, a full disk or a power cut inside that window
## left a zero-length file where a career had been, with one slot and no way
## back. It writes a temporary and renames now, keeping the previous file as a
## `.bak` that `load_game` falls back to.
func _check_a_torn_write_costs_one_shift_and_not_a_career() -> void:
	GameState.start_new_career(4242)
	GameState.day = 5
	GameState.cash = 1234
	_ok(SaveSystem.save_game(SLOT), "a save is written")
	_ok(not FileAccess.file_exists(SaveSystem.slot_path(SLOT) + ".tmp"),
		"and the temporary it was written through is gone")
	# A second save, so there is a previous shift to fall back TO.
	GameState.day = 6
	SaveSystem.save_game(SLOT)
	_ok(FileAccess.file_exists(SaveSystem.backup_path(SLOT)),
		"the shift before it is kept beside it")
	# Now tear the primary the way a power cut does — and ONLY the primary. The
	# first version of this used `_write_slot`, which clears the `.bak` so the
	# refusal cases above start from a clean slot, so it deleted the very file it
	# was about to assert a recovery from and reported the recovery as broken.
	# A harness fault that looks exactly like a product fault, which is the
	# lesson gotcha 62 is about: check what the test is standing on first.
	_corrupt_primary("{")
	GameState.day = 1
	var recovered: bool = SaveSystem.load_game(SLOT)
	_ok(recovered and GameState.day == 5,
		"and a torn primary recovers the previous shift (day %d)" % GameState.day)
	# AND DELETING A SLOT DELETES ITS BACKUP. `screen_day_over` deletes the
	# autosave when a career ends so "Continue — Day 9" cannot resurrect a
	# struck-off doctor; a surviving `.bak` would hand him straight back.
	SaveSystem.delete_save(SLOT)
	_ok(not FileAccess.file_exists(SaveSystem.backup_path(SLOT)),
		"and deleting the slot deletes the backup with it")

## A SEED IS NOT A POSITION.
##
## `RNG.save_state` returned `{"seed": seed_value}` and `load_state` called
## `reseed()`, which clears every cached stream — so loading a career put all of
## them back to draw zero and the next `chance("lead_oduya")` returned whatever
## the first ask of the whole career had returned, identically on every reload.
## Neither function had a caller: RNG was not a registered save provider at all,
## so a loaded career simply inherited whatever positions the title screen left
## behind. The ward was right the whole time (`Cases.draw_five` reads
## `GameState.seed_value` directly), which is exactly why nobody saw the rest go.
func _check_a_stream_resumes_where_it_stopped() -> void:
	RNG.reseed(4242)
	var first := RNG.randf_s("gossip")
	for i in 6:
		RNG.randf_s("gossip")
	var snapshot := RNG.save_state()
	var expected := RNG.randf_s("gossip")

	# Through JSON, because that is the only route a save ever takes and a
	# 64-bit generator state does not survive a double. It goes as a decimal
	# STRING for that reason; a state above 2^53 written as a number comes back
	# rounded and every stream resumes a few draws from where it stopped.
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(snapshot))
	_ok(typeof(round_tripped) == TYPE_DICTIONARY, "a stream snapshot survives JSON")

	# Scribble over the generator the way a main menu does.
	RNG.reseed(31337)
	for i in 4:
		RNG.randf_s("gossip")
	RNG.load_state(round_tripped)
	var got := RNG.randf_s("gossip")
	_ok(is_equal_approx(got, expected),
		"a loaded career resumes the stream where it stopped")
	_ok(not is_equal_approx(got, first),
		"and does NOT rewind it to the first draw of the career")
	_ok(RNG.seed_value == 4242, "and the run seed comes back with it")

## The fonts are the one asset class this project ships, and the OFL asks that
## the notice travel with them. The three licence files are forced into the pack
## by `export_presets.cfg`'s include_filter and smoke asserts they exist; what
## this adds is the other source a reader needs — Godot's own MIT notice and the
## copyright blocks for everything it bundles, which are compiled into the binary
## and reachable through `Engine`, so shipping them costs no file at all.
func _check_every_licence_the_build_owes_is_in_it() -> void:
	var licences := ["res://assets/fonts/OFL-IBMPlex.txt",
		"res://assets/fonts/OFL-InstrumentSans.txt",
		"res://assets/fonts/OFL-NothingYouCouldDo.txt"]
	var short: Array = []
	for p in licences:
		var txt := FileAccess.get_file_as_string(p)
		if txt.length() < 500 or not txt.to_upper().contains("SIL OPEN FONT LICENSE"):
			short.append(p.get_file())
	_ok(short.is_empty(), "the three OFL notices ship intact%s"
		% ("" if short.is_empty() else " — bad: " + ", ".join(PackedStringArray(short))))
	_ok(Engine.get_license_text().length() > 500,
		"and the engine's own notice is readable from inside the build")
	_ok(Engine.get_copyright_info().size() > 5,
		"along with %d third-party copyright blocks" % Engine.get_copyright_info().size())

# ================================================================ the live half
func start() -> void:
	run_static()
	print("\n--- the scene a stranger waits for ---")
	var packed: PackedScene = load("res://scenes/Game.tscn")
	if packed == null:
		_ok(false, "Game.tscn loads")
		stage = "done"
		return
	GameState.start_new_career(4242)
	GameState.set_flag("tutorial_done", true)
	game = packed.instantiate()
	tree.root.add_child(game)

func tick() -> bool:
	frames += 1
	match stage:
		"static":
			if frames < 3:
				return false
			_check_the_freeze_between_the_menu_and_the_ward()
			_check_every_save_provider_is_bound_to_something_alive()
			_start_the_game_the_way_a_player_does()
			return false
		"menu":
			if frames < _menu_at + 12:
				return false
			_check_the_button_actually_reaches_the_ward()
			stage = "done"
	return true

var _menu_at := 0

## THE ONE ROUTE THAT GOES THROUGH THE TITLE SCREEN'S OWN BUTTON.
##
## `boot_check.sh` walks the real entry point and stops AT the main menu, and
## every other harness instantiates Game.tscn directly — so the step between
## them, the one a player takes first, has never been executed by anything. It
## matters more than it used to: New Career and Continue no longer call
## `change_scene_to_file` themselves. They hide the panel, put a card up, and
## await two frames so the scene build happens behind something rather than
## instead of it, and an await that never resumes is a title screen with a dead
## button on it and no error anywhere.
##
## `_go_to_ward()` rather than `_new_career()` on purpose: New Career would erase
## whatever career is in `user://saves`, and a probe that deletes the developer's
## save to prove a point is a worse bug than the one it is testing.
func _start_the_game_the_way_a_player_does() -> void:
	if game != null:
		game.queue_free()
		game = null
	var packed: PackedScene = load("res://scenes/MainMenu.tscn")
	if packed == null:
		_ok(false, "MainMenu.tscn loads")
		stage = "done"
		return
	var menu: Node = packed.instantiate()
	tree.root.add_child(menu)
	menu.call("_go_to_ward")
	_menu_at = frames
	stage = "menu"

func _check_the_button_actually_reaches_the_ward() -> void:
	_ok(tree.get_first_node_in_group("game") != null,
		"the title screen's own button reaches the ward")

func _check_the_freeze_between_the_menu_and_the_ward() -> void:
	var msec: int = game.get_script().get("last_build_msec")
	_ok(msec > 0, "the scene build is timed (%d ms)" % msec)
	_ok(msec < BUILD_BUDGET_MSEC,
		"and comes up inside the %d ms budget" % BUILD_BUDGET_MSEC)

## A PROVIDER BOUND TO AN OBJECT THAT IS REPLACED EVERY MORNING SAVES NOTHING.
##
## `_register_saves` bound `ward.records.to_dict` to the `Records` instance that
## existed at `Game._ready()`. `_start()` then calls `ward.start()`, which does
## `records = Records.new()` — every single morning, its own comment says so — so
## the provider served an orphan from before the player pressed anything and
## `systems.records` in every autosave ever written was an empty chart. It read
## as a working save provider, which is what made it dangerous.
##
## The key is gone rather than fixed, because fixed would be wrong: `load_game`
## runs BEFORE `ward.start()` (it has to — what carries out of a save is exactly
## what `start()` reads) and `start()` would throw the restored chart away, and
## restoring it later would put yesterday's chart into today's ward. The chart is
## per-day state and the save should not pretend otherwise.
##
## Proven red by re-registering the bound form.
func _check_every_save_provider_is_bound_to_something_alive() -> void:
	var keys: Array = SaveSystem._providers.keys()
	_ok(keys.has("rng"),
		"the randomness a career runs on is saved with it")
	_ok(not keys.has("records"),
		"and no key is registered for state the next morning rebuilds%s"
			% ("" if not keys.has("records") else " — 'records' is back"))
	var dead: Array = []
	for k in keys:
		var fn: Callable = SaveSystem._providers[k]["save"]
		if not fn.is_valid():
			dead.append(String(k))
	_ok(dead.is_empty(), "every registered provider is bound to a live object%s"
		% ("" if dead.is_empty() else " — dead: " + ", ".join(PackedStringArray(dead))))

	# AND THE WHOLE THING ROUND-TRIPS THROUGH A REAL FILE. Every check above is
	# about one field; this is the one that fails if a provider throws.
	GameState.cash = 777
	var wrote: bool = SaveSystem.save_game(SLOT)
	var advanced := RNG.randf_s("gossip")
	GameState.cash = 0
	var read_back: bool = SaveSystem.load_game(SLOT)
	_ok(wrote and read_back and GameState.cash == 777,
		"a whole career round-trips through a file on disk")
	_ok(is_equal_approx(RNG.randf_s("gossip"), advanced),
		"and comes back with the stream positions it was saved at")
	SaveSystem.delete_save(SLOT)

# ======================================================================= plumbing
## Put `text` in the slot AND clear any backup, so a refusal case is testing the
## refusal and not a recovery.
func _write_slot(text: String) -> void:
	if FileAccess.file_exists(SaveSystem.backup_path(SLOT)):
		DirAccess.remove_absolute(SaveSystem.backup_path(SLOT))
	_corrupt_primary(text)

## Damage only the primary, the way a power cut during a rename does.
func _corrupt_primary(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveSystem.SAVE_DIR)
	var f := FileAccess.open(SaveSystem.slot_path(SLOT), FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

## Everything an autoload will answer to: properties, methods, signals, and the
## script's own constants and enums. `"NAME" in node` is not enough on its own —
## a `const` is not a property and does not appear in `get_property_list()`, so a
## check built on `in` alone reports every constant in the project as missing.
func _members_of(node: Node) -> Dictionary:
	var out := {}
	for p in node.get_property_list():
		out[String(p["name"])] = true
	for m in node.get_method_list():
		out[String(m["name"])] = true
	for s in node.get_signal_list():
		out[String(s["name"])] = true
	var sc: Script = node.get_script()
	if sc != null:
		for k in sc.get_script_constant_map():
			out[String(k)] = true
	return out

## `Name.identifier` occurrences that are NOT calls — the half smoke_impl skips.
func _reads_on(src: String, autoload: String) -> Array:
	var out: Array = []
	for raw in src.split("\n"):
		var line := _code_only(raw)
		var from := 0
		while true:
			var at := line.find(autoload + ".", from)
			if at < 0:
				break
			from = at + 1
			# A whole word before the dot, and not the tail of a path.
			if at > 0:
				var prev := line[at - 1]
				if _ident_char(prev) or prev == "." or prev == "/":
					continue
			var rest := line.substr(at + autoload.length() + 1)
			var end := 0
			while end < rest.length() and _ident_char(rest[end]):
				end += 1
			if end == 0:
				continue
			# A CALL is smoke_impl's check, and it already runs.
			if end < rest.length() and rest[end] == "(":
				continue
			var name := rest.substr(0, end)
			if not out.has(name):
				out.append(name)
	return out

## The line with its string literals blanked and any trailing comment cut off.
##
## Both halves were needed and both would have produced a false failure. This
## repo's comments quote the faults they are explaining — `prop.gd` now has the
## literal text `GameState.stats.items_broken` in a comment describing why it was
## fatal — and a scanner that reads comments would report the explanation as the
## bug. And `load("res://scripts/autoload/GameState.gd")` reads as `GameState.gd`
## with a perfectly good word boundary in front of it.
##
## Blanking rather than deleting, so every column index still means what it did.
func _code_only(line: String) -> String:
	var out := ""
	var in_str := false
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if in_str:
			out += " "
			if c == quote and (i == 0 or line[i - 1] != "\\"):
				in_str = false
		elif c == "\"" or c == "'":
			in_str = true
			quote = c
			out += " "
		elif c == "#":
			break
		else:
			out += c
		i += 1
	return out

func _ident_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
		or (c >= "0" and c <= "9")

func _all_scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := dir + "/" + f
		if d.current_is_dir():
			out.append_array(_all_scripts(full))
		elif f.ends_with(".gd"):
			out.append(full)
		f = d.get_next()
	d.list_dir_end()
	return out
