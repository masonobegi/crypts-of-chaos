class_name Game
extends Node3D
## Root of a run. Builds the world, spawns the systems in dependency order,
## staffs the ward, and owns the UI routing.

## The whole roster, not the number on the floor. Who is actually rostered on
## any given shift comes from DB.ROTA — the rest are at home, and their memories
## come back with them tomorrow.
## One nurse on the floor. A five-bed ward does not need a rota, and every
## extra body is another pair of eyes that has to mean something.
const NURSE_COUNT := 1
const DOCTOR_COUNT := 0

var hospital: Hospital
var player: Player
var suspicion: SuspicionSystem
var patient_system: PatientSystem
var ward: WardDay
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
	# The LIGHT follows the shift. The music does not, and there is deliberately
	# no shift_started hook for it: there is one score, it starts on the title
	# screen, and it plays through the briefing, the shift and the evening
	# without a seam. There used to be a second connection here that called
	# play_music on every shift_started — which by then could only ever re-level
	# the volume, because play_music has been a no-op after the first call from
	# anywhere since the three moods were collapsed into one. A line that fires
	# every day of a career and does nothing is worse than no line: it reads as
	# the mechanism by which the music changes, and there isn't one.
	AudioMgr.play_music()
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
## One look, because there is one shift. The three-way branch on shift_kind went
## with the shift types; a day that runs eight to eight only needs the light to
## move once, and it does that on the clock rather than on a mode.
var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null

func apply_shift_look() -> void:
	if _env == null or _sun == null:
		return
	# Late afternoon by six, dark by eight. The evening arriving is the pressure.
	var t: float = clampf(float(GameState.minute_of_day - 8 * 60) / float(12 * 60), 0.0, 1.0)
	var warmth: float = smoothstep(0.55, 1.0, t)
	_sun.light_energy = lerpf(1.05, 0.22, warmth)
	_sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.72, 0.48), warmth)
	_sun.rotation_degrees = Vector3(lerpf(-58.0, -12.0, warmth), -38, 0)
	if _fill:
		_fill.light_energy = lerpf(0.35, 0.16, warmth)
	if _sky_mat:
		_sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.86).lerp(Color(0.30, 0.28, 0.40), warmth)

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

	var pa := PASystem.new()
	pa.name = "PASystem"
	add_child(pa)

	var ambience := AmbienceSystem.new()
	ambience.name = "AmbienceSystem"
	add_child(ambience)

	var tutorial := TutorialSystem.new()
	tutorial.name = "TutorialSystem"
	add_child(tutorial)

	# The day. Everything the player does to a chart goes through this, and the
	# ward sister reads what it kept. It replaces ShiftSystem, TreatmentSystem,
	# EconomySystem, RecordsSystem, InvestigationSystem, AppointmentSystem,
	# LegalSystem, NightSystem and BrawlSystem, all of which are gone.
	ward = WardDay.new()
	ward.name = "WardDay"
	add_child(ward)

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
	# You start in the corridor, outside the ward, because the first thing this
	# game asks you to do is walk in and look at somebody.
	player.global_position = hospital.point_in("corridor") + Vector3(0, 0.2, 0)
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

## One nurse, and she is not random. Adeyemi is a named person the player will
## argue with about a written discharge plan, so she is authored like the
## patients are rather than rolled out of an archetype table.
func _spawn_staff() -> void:
	_spawn_nurse("rule_follower", 0)
	_seed_social_graph()

func _spawn_nurse(arch: String, index: int) -> void:
	var n := NurseNPC.new()
	n.npc_id = "nurse_%d" % index
	n.archetype = arch
	n.display = "Nurse %s" % DB.WARD_NURSE
	n.set_colours(_random_skin(), Build.SCRUB_BLUE if arch != "corrupt" else Build.SCRUB_GREEN,
		Color(0.2, 0.15, 0.11))
	add_child(n)
	n.global_position = hospital.point_in("station", "nurse_spawn")
	var mind := DB.make_mind(n.npc_id, n.display, "nurse", arch)
	suspicion.register(mind, n)

## There is no second doctor. The only other clinician on this ward is the
## sister who reads the folder in the morning, and she does not need a body on
## the floor to do that — she needs the chart, which is where she gets her
## questions from.

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
	SaveSystem.register("hospital", hospital.to_dict, hospital.from_dict)
	SaveSystem.register("records", ward.records.to_dict, ward.records.from_dict)

## Nothing on this ward keeps a device log any more — the machines, the
## thermostats and the window units all went with the redesign. What is evidence
## now is the chart, and the chart is saved with the records above.

func _start() -> void:
	patient_system.populate()
	ward.start()
	if GameState.flag("headless_sim", false):
		return
	GameState.start_day()
	EventBus.request_ui.emit("morning", {})

func _physics_process(_delta: float) -> void:
	if player and suspicion:
		suspicion.refresh_tells(player.global_position)

## The slice has no endings table. A day closes at the handover and that screen
## says what happened; anything past it belongs to a game that has more days.
func _on_game_over(_reason: String) -> void:
	EventBus.request_ui.emit("review", {})
