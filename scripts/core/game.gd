class_name Game
extends Node3D
## Root of a run. Builds the world, spawns the systems in dependency order,
## staffs the ward, and owns the UI routing.

## The whole roster, not the number on the floor. Who is actually rostered on
## any given shift comes from DB.ROTA — the rest are at home, and their memories
## come back with them tomorrow.
const NURSE_COUNT := 5
const DOCTOR_COUNT := 3

var hospital: Hospital
var player: Player
var suspicion: SuspicionSystem
var patient_system: PatientSystem
var treatment: TreatmentSystem
var economy: EconomySystem
var records: RecordsSystem
var investigations: InvestigationSystem
var events: RandomEventSystem
var appointments: AppointmentSystem
var shift: ShiftSystem
var legal: LegalSystem
var night: NightSystem
var brawl: BrawlSystem
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
	# Where the objective IS, not just what it says. The first playtester got
	# lost inside two minutes with nothing but a line of text naming a room in
	# a building they had never been in.
	var marker := ObjectiveMarker.new()
	marker.name = "ObjectiveMarker"
	add_child(marker)
	_register_saves()
	EventBus.game_over.connect(_on_game_over)
	_start()

# ------------------------------------------------------------------ world
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	# A real sky rather than a dark grey void. It is only ever seen through the
	# windows and off the ends of the corridor, and those were the two places
	# the building looked like it had been cut out of a larger, sadder game.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.60, 0.95)
	sky_mat.sky_horizon_color = Color(0.62, 0.80, 0.96)
	sky_mat.ground_bottom_color = Color(0.52, 0.72, 0.55)
	sky_mat.ground_horizon_color = Color(0.62, 0.80, 0.96)
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.82, 0.92)
	# High enough that the building is BRIGHT and nothing sits in a black
	# corner, low enough that switching a ward's lights off is still an obvious,
	# visible act — which it has to be, because it is a mechanic. The room lamps
	# were raised to match, so the on/off delta is bigger than it was even at
	# this much higher floor.
	env.ambient_light_energy = 0.30

	# No fog. Distance haze is what makes a corridor look grim, and this one is
	# sixty-two metres long — it was the single biggest reason the far end of
	# the ward read as a bad place to be.
	env.fog_enabled = false

	# FILMIC, not LINEAR. Linear keeps colours pure right up to 1.0 and then
	# clips flat, and this scene has an ambient term, a key, a fill and a ceiling
	# lamp every five metres all landing on the same white wall — the first
	# render of this restyle was a photograph of a lightbulb. Filmic rolls the
	# top off, which is what lets everything below it be bright.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Pulled down from 0.92/3.2. With rounded geometry and an outline pass the
	# scene stopped needing to be quite so bright to read, and the far end of a
	# sixty-two metre corridor was clipping to flat white — every sign, door and
	# person past about thirty metres dissolved into it.
	env.tonemap_exposure = 0.78
	env.tonemap_white = 2.6

	# One global knob for "more cartoon". Everything else in the restyle is a
	# colour choice somewhere; this is the finish over the top of all of them.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.24
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 1.0

	# Soft bloom on the lamps and the signage, which is most of what makes a
	# stylised interior feel lit rather than merely visible.
	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.glow_bloom = 0.03
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.35

	# Contact shading. Rounded geometry with an outline round it still floats
	# without something darkening where two things meet — this is what puts the
	# chairs on the floor rather than in front of it. Forward+ only; the
	# screenshot harness runs Compatibility and will not show it.
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.35
	env.ssao_power = 1.6
	env.ssao_light_affect = 0.25
	we.environment = env
	add_child(we)
	_env = env
	_sky_mat = sky_mat

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.98, 0.93)
	sun.shadow_enabled = true
	# Soft, pale shadows. A hard black shadow under every chair is the other
	# half of "grim"; this style wants shape, not drama.
	sun.shadow_blur = 2.4
	sun.directional_shadow_blend_splits = true
	sun.light_specular = 0.35
	add_child(sun)

	# A cold fill from the opposite side, at a fifth of the key. Nothing in a
	# cartoon has a black side — it has a cooler side.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 148, 0)
	fill.light_energy = 0.22
	fill.light_color = Color(0.74, 0.86, 1.0)
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	add_child(fill)
	_sun = sun
	_fill = fill
	EventBus.shift_started.connect(func(_d): apply_shift_look())
	# The score follows the shift, for the same reason the light does: three
	# shifts that differ only in a spreadsheet are not three choices.
	EventBus.shift_started.connect(func(_d): AudioMgr.play_music(GameState.shift_kind))
	# ...and start it NOW rather than waiting for a shift to begin. The briefing,
	# the shift-select screen and the whole first minute of a run happen before
	# shift_started fires, and all of it was silent.
	AudioMgr.play_music(GameState.shift_kind)
	apply_shift_look()

## What time of day it is, in light.
##
## The three shifts differed in pay, staffing, appointment count, admissions and
## scrutiny — five real numbers — and the building looked identical in all three.
## A player picking "Night" got a different spreadsheet and the same room, which
## is the least persuasive way to offer a choice.
##
## Nothing here is decorative. Night is genuinely darker, so the same act is
## genuinely harder to see; the shift screen already promises "Nobody is
## watching", and now that is a thing the player can see rather than a claim.
const SHIFT_LOOK := {
	"night": {
		"sky_top": Color(0.03, 0.05, 0.13), "sky_horizon": Color(0.10, 0.14, 0.26),
		"ambient": Color(0.30, 0.38, 0.58), "ambient_energy": 0.16,
		"sun": Color(0.60, 0.70, 1.00), "sun_energy": 0.16,
		"fill": Color(0.40, 0.50, 0.80), "fill_energy": 0.08,
		"lamp": Color(1.00, 0.94, 0.80), "lamp_energy": 1.35,
	},
	"day": {
		"sky_top": Color(0.24, 0.60, 0.95), "sky_horizon": Color(0.62, 0.80, 0.96),
		"ambient": Color(0.72, 0.82, 0.92), "ambient_energy": 0.34,
		"sun": Color(1.00, 0.98, 0.93), "sun_energy": 0.85,
		"fill": Color(0.74, 0.86, 1.00), "fill_energy": 0.22,
		"lamp": Color(1.00, 0.97, 0.90), "lamp_energy": 1.05,
	},
	"evening": {
		"sky_top": Color(0.20, 0.34, 0.66), "sky_horizon": Color(0.98, 0.66, 0.40),
		"ambient": Color(0.78, 0.66, 0.62), "ambient_energy": 0.26,
		"sun": Color(1.00, 0.80, 0.58), "sun_energy": 0.52,
		"fill": Color(0.62, 0.70, 0.96), "fill_energy": 0.16,
		"lamp": Color(1.00, 0.95, 0.84), "lamp_energy": 1.20,
	},
}

var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null

func apply_shift_look() -> void:
	var look: Dictionary = SHIFT_LOOK.get(GameState.shift_kind, SHIFT_LOOK["day"])
	if _sky_mat != null:
		_sky_mat.sky_top_color = look["sky_top"]
		_sky_mat.sky_horizon_color = look["sky_horizon"]
		_sky_mat.ground_horizon_color = look["sky_horizon"]
	if _env != null:
		_env.ambient_light_color = look["ambient"]
		_env.ambient_light_energy = float(look["ambient_energy"])
	if _sun != null:
		_sun.light_color = look["sun"]
		_sun.light_energy = float(look["sun_energy"])
		# The sun is low and orange in the evening and behind the world at night.
		_sun.rotation_degrees = Vector3(
			-14.0 if GameState.shift_kind == "evening" else -52.0, -38, 0)
	if _fill != null:
		_fill.light_color = look["fill"]
		_fill.light_energy = float(look["fill_energy"])
	if hospital != null:
		hospital.set_lamp_look(look["lamp"], float(look["lamp_energy"]))

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

	appointments = AppointmentSystem.new()
	appointments.name = "AppointmentSystem"
	add_child(appointments)

	# The two phases either side of the ward. Both are added before ShiftSystem
	# because it looks them up by group at the end of every day.
	legal = LegalSystem.new()
	legal.name = "LegalSystem"
	add_child(legal)

	night = NightSystem.new()
	night.name = "NightSystem"
	add_child(night)

	# The fight happens in the room, so it is a system on the floor rather than
	# a screen over it.
	brawl = BrawlSystem.new()
	brawl.name = "BrawlSystem"
	brawl.patient_system = patient_system
	brawl.treatment_system = treatment
	add_child(brawl)

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
	# Authored, not random.
	#
	# This used to be a random point in the lobby facing a random x somewhere
	# along a sixty-two metre corridor, which means the first frame of the game
	# — the one image every player sees before they have touched anything — was
	# a dice roll between "a waiting room" and "a blank wall". It is now a fixed
	# spot behind reception looking at the way out: chairs on the right, the
	# desk on the left, the corridor doorway dead ahead and the objective
	# through it.
	# Whatever the player set the last time they were here.
	cam.fov = float(Settings.get_value("fov"))
	player.global_position = hospital.lobby_spawn() + Vector3(0, 0.2, 0)
	player.face(Vector3(5.5, 0, 4.0))

## Seed who talks to whom. Gossip weights by affinity, so which two nurses
## happen to get on decides how fast something you did travels.
func _seed_social_graph() -> void:
	var staff_minds: Array = []
	for id in suspicion.minds:
		var m: Mind = suspicion.minds[id]
		if m.role in ["nurse", "doctor"]:
			staff_minds.append(m)
	for a in staff_minds:
		for b in staff_minds:
			if a.id == b.id:
				continue
			a.affinity[b.id] = RNG.randf_range_s("affinity", 0.15, 1.0)

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
	_seed_social_graph()

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
	# A coat, not a light source. At 0.90 the white clipped against every wall
	# in the building and the only thing defining the shape was the outline.
	d.set_colours(_random_skin(), Color(0.80, 0.83, 0.87), Color(0.18, 0.14, 0.11))
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
	SaveSystem.register("appointments", appointments.to_dict, appointments.from_dict)
	SaveSystem.register("legal", legal.to_dict, legal.from_dict)
	SaveSystem.register("night", night.to_dict, night.from_dict)
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
		_resume_where_the_save_left_off()
		return
	shift.begin_day()
	if not GameState.flag("tutorial_done", false):
		EventBus.request_ui.emit("tutorial", {})

## Put the player back where the save was taken, rather than at the top of the
## morning regardless.
##
## The autosave is written inside clock_out(), with the day just worked still
## current — so "load, then begin_day()" restarted a day that had already
## happened. Debts were settled twice, the morning's events rolled twice, and
## the appointment list was rebuilt for a shift that was over. A save taken from
## the pause menu mid-shift was worse: it put the player back at 8am with the
## ward as it stood at 2pm.
func _resume_where_the_save_left_off() -> void:
	match GameState.phase:
		GameState.Phase.SHIFT:
			# Straight back onto the floor, clock running, nothing re-rolled.
			GameState.set_phase(GameState.Phase.SHIFT)
			EventBus.objective_changed.emit("Get through the shift.")
		GameState.Phase.CHART_REVIEW:
			if not shift.last_review.is_empty():
				EventBus.request_ui.emit("review", shift.last_review)
			else:
				shift.end_shift()
		GameState.Phase.POST_SHIFT:
			# The commonest case by far: the autosave is written at clock-out.
			shift.next_day()
		_:
			shift.begin_day()

func _physics_process(_delta: float) -> void:
	if player and suspicion:
		suspicion.refresh_tells(player.global_position)

func _on_game_over(ending_id: String) -> void:
	GameState.set_phase(GameState.Phase.GAME_OVER)
	Meta.record_ending(ending_id)
	EventBus.request_ui.emit("game_over", {"ending": ending_id})
