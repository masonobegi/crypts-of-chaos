class_name Game
extends Node3D
## Root of a run. Builds the world, spawns the systems in dependency order,
## staffs the ward, and owns the UI routing.

const NURSE_COUNT := 2
const DOCTOR_COUNT := 1

var hospital: Hospital
var player: Player
var suspicion: SuspicionSystem
var patient_system: PatientSystem
var treatment: TreatmentSystem
var economy: EconomySystem
var records: RecordsSystem
var investigations: InvestigationSystem
var events: RandomEventSystem
var shift: ShiftSystem
var codex: Codex
var ui: Node

func _ready() -> void:
	add_to_group("game")
	_build_environment()
	_build_world()
	_spawn_systems()
	_spawn_player()
	_spawn_staff()
	_spawn_ui()
	_register_saves()
	EventBus.game_over.connect(_on_game_over)
	_start()

# ------------------------------------------------------------------ world
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.70)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.60, 0.64)
	env.fog_density = 0.006
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = false
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.7
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	add_child(sun)

func _build_world() -> void:
	hospital = Hospital.new()
	hospital.name = "Hospital"
	add_child(hospital)
	hospital.build()

func _spawn_systems() -> void:
	# Order matters: each system looks up the ones before it in _ready().
	suspicion = SuspicionSystem.new()
	suspicion.name = "SuspicionSystem"
	add_child(suspicion)

	patient_system = PatientSystem.new()
	patient_system.name = "PatientSystem"
	add_child(patient_system)

	treatment = TreatmentSystem.new()
	treatment.name = "TreatmentSystem"
	add_child(treatment)

	economy = EconomySystem.new()
	economy.name = "EconomySystem"
	add_child(economy)

	records = RecordsSystem.new()
	records.name = "RecordsSystem"
	add_child(records)

	investigations = InvestigationSystem.new()
	investigations.name = "InvestigationSystem"
	add_child(investigations)

	events = RandomEventSystem.new()
	events.name = "RandomEventSystem"
	add_child(events)

	codex = Codex.new()
	codex.name = "Codex"
	add_child(codex)

	var pa := PASystem.new()
	pa.name = "PASystem"
	add_child(pa)

	var tutorial := TutorialSystem.new()
	tutorial.name = "TutorialSystem"
	add_child(tutorial)

	var obstruction := ObstructionMonitor.new()
	obstruction.name = "ObstructionMonitor"
	add_child(obstruction)

	var ambience := AmbienceSystem.new()
	ambience.name = "AmbienceSystem"
	add_child(ambience)

	shift = ShiftSystem.new()
	shift.name = "ShiftSystem"
	add_child(shift)

func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	var cs := CollisionShape3D.new()
	cs.name = "Collider"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = Player.STAND_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, Player.STAND_HEIGHT * 0.5, 0)
	player.add_child(cs)

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, Player.STAND_HEIGHT - 0.18, 0)
	player.add_child(head)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 78.0
	cam.near = 0.05
	head.add_child(cam)

	var inter := RayCast3D.new()
	inter.name = "Interactor"
	inter.set_script(load("res://scripts/player/interactor.gd"))
	cam.add_child(inter)

	add_child(player)
	player.global_position = hospital.point_in("lobby", "player_spawn") + Vector3(0, 0.2, 0)
	player.face(Vector3(hospital.point_in("corridor").x, 0, 2.0))

func _spawn_staff() -> void:
	var nurse_archetypes: Array = ["gossip", "suspicious", "lazy", "loyal",
		"rule_follower", "corrupt", "incompetent"]
	var used: Array = []
	for i in NURSE_COUNT:
		var arch := String(RNG.pick("nurse_arch", nurse_archetypes))
		var guard := 0
		while used.has(arch) and guard < 12:
			arch = String(RNG.pick("nurse_arch", nurse_archetypes))
			guard += 1
		used.append(arch)
		_spawn_nurse(arch, i)
	for i in DOCTOR_COUNT:
		_spawn_doctor(String(RNG.pick("doc_arch",
			["competitive", "oblivious", "ethical", "arrogant", "investigator", "corrupt_doc"])), i)

func _spawn_nurse(arch: String, index: int) -> void:
	var n := NurseNPC.new()
	n.npc_id = "nurse_%d" % index
	n.archetype = arch
	n.display = "Nurse %s" % RNG.pick("nurse_name", DB.STAFF_FIRST)
	n.set_colours(_random_skin(), Build.SCRUB_BLUE if arch != "corrupt" else Build.SCRUB_GREEN,
		Color(0.2, 0.15, 0.11))
	add_child(n)
	n.global_position = hospital.point_in("station", "nurse_spawn")
	var mind := DB.make_mind(n.npc_id, n.display, "nurse", arch)
	if GameState.flag("perk_loyal_ward", false):
		mind.trust = clampf(mind.trust + 0.25, 0.0, 1.0)
		mind.talkativeness = maxf(0.05, mind.talkativeness - 0.3)
	suspicion.register(mind, n)

func _spawn_doctor(arch: String, index: int) -> void:
	var d := DoctorNPC.new()
	d.npc_id = "doctor_%d" % index
	d.archetype = arch
	d.display = "Dr %s" % RNG.pick("doc_name", DB.LAST_NAMES)
	d.set_colours(_random_skin(), Color(0.90, 0.91, 0.93), Color(0.18, 0.14, 0.11))
	add_child(d)
	d.global_position = hospital.point_in("corridor", "doc_spawn")
	var mind := DB.make_mind(d.npc_id, d.display, "doctor", arch)
	suspicion.register(mind, d)

func _random_skin() -> Color:
	return RNG.pick("staff_skin", [
		Color(0.95, 0.83, 0.72), Color(0.87, 0.72, 0.60), Color(0.76, 0.60, 0.46),
		Color(0.60, 0.44, 0.32), Color(0.44, 0.31, 0.22), Color(0.33, 0.23, 0.17)])

func _spawn_ui() -> void:
	# The balance harness drives the systems directly with no player present and
	# no frames between actions; spawning the UI there only creates orphaned
	# tweens and timers.
	if GameState.flag("headless_sim", false):
		return
	ui = load("res://scripts/ui/ui_root.gd").new()
	ui.name = "UI"
	add_child(ui)

# ------------------------------------------------------------------ lifecycle
func _register_saves() -> void:
	SaveSystem.register("suspicion", suspicion.to_dict, suspicion.from_dict)
	SaveSystem.register("patients", patient_system.to_dict, patient_system.from_dict)
	SaveSystem.register("economy", economy.to_dict, economy.from_dict)
	SaveSystem.register("investigations", investigations.to_dict, investigations.from_dict)
	SaveSystem.register("events", events.to_dict, events.from_dict)
	SaveSystem.register("hospital", hospital.to_dict, hospital.from_dict)
	SaveSystem.register("codex", codex.to_dict, codex.from_dict)
	SaveSystem.register("devices", _save_devices, _load_devices)

## Every device that keeps a log has to be saved, because those logs ARE
## evidence — losing a thermostat's history on load would quietly delete a paper
## trail the player deliberately created.
func _save_devices() -> Dictionary:
	var out := {}
	var m := 0
	var t := 0
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is TreatmentMachine:
			out["m%d" % m] = f.to_dict()
			m += 1
		elif f is Thermostat:
			out["t%d" % t] = f.to_dict()
			t += 1
	return out

func _load_devices(d: Dictionary) -> void:
	var m := 0
	var t := 0
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is TreatmentMachine:
			if d.has("m%d" % m):
				f.from_dict(d["m%d" % m])
			m += 1
		elif f is Thermostat:
			if d.has("t%d" % t):
				f.from_dict(d["t%d" % t])
			t += 1

func _start() -> void:
	if GameState.flag("headless_sim", false):
		shift.begin_day()
		return
	if GameState.flag("continue_save", false):
		GameState.set_flag("continue_save", false)
		SaveSystem.load_game(SaveSystem.AUTOSAVE)
		shift.begin_day()
		return
	shift.begin_day()
	if not GameState.flag("tutorial_done", false):
		EventBus.request_ui.emit("tutorial", {})

func _physics_process(_delta: float) -> void:
	if player and suspicion:
		suspicion.refresh_tells(player.global_position)

func _on_game_over(ending_id: String) -> void:
	GameState.set_phase(GameState.Phase.GAME_OVER)
	Meta.record_ending(ending_id)
	EventBus.request_ui.emit("game_over", {"ending": ending_id})
