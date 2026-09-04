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
	# WARM-NEUTRAL, NOT SKY-BLUE. Ambient is the only bounce light this renderer
	# has, so it is what every vertical surface in the building is actually lit
	# by — and a blue ambient on cream walls is why the ward went slate the
	# moment the normals were corrected and the walls stopped catching the
	# directional lights from every direction at once.
	env.ambient_light_color = Color(0.88, 0.87, 0.84)
	# High enough that the building is BRIGHT and nothing sits in a black
	# corner, low enough that switching a ward's lights off is still an obvious,
	# visible act — which it has to be, because it is a mechanic. The room lamps
	# were raised to match, so the on/off delta is bigger than it was even at
	# this much higher floor.
	# AND MUCH MORE OF IT. 0.30 was tuned against geometry that was shaded with
	# sphere normals: every flat surface picked up light from directions it does
	# not face, which hid how little of the room the lights were reaching. With
	# the normals honest, a wall gets what actually lands on it — and in a room
	# lit by downward-facing ceiling fittings, that is almost nothing but this.
	# There is no global illumination on the Compatibility renderer; this is the
	# bounce, and it has to do the whole job. Measured rather than guessed: a
	# cream wall in the ward reads (113, 124, 129) at 0.62 and (195, 197, 194)
	# at 3.0, so the knob works and the old value was simply an order out. 3.0
	# flattens the building into a white-out with no shading left in it; the
	# figure below came out of the grade sweep described further down, which
	# scored six settings of this and the tonemap together.
	env.ambient_light_energy = 1.15
	# Says out loud what the ambient source already implies: the interior takes
	# its fill from the colour above and not from the sky. Measured to be a
	# no-op on this backend with AMBIENT_SOURCE_COLOR — the default of 1.0
	# renders identically, pixel for pixel — so it is here as a statement of
	# intent rather than a fix, and the blue cast on the ward's left-hand wall
	# is the cool DirectionalLight3D fill, not the sky.
	env.ambient_light_sky_contribution = 0.0

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
	# Both chosen by the sweep described under the adjustments below. A lower
	# exposure against a HIGHER white point is what buys colour back: the white
	# point is where the curve finally saturates, so pushing it out keeps the
	# midtones off the shoulder, and the exposure then sets where the room
	# sits on the straight part. The far end of a sixty-two metre corridor was
	# clipping to flat white at 0.92 and every sign, door and person past about
	# thirty metres dissolved into it.
	env.tonemap_exposure = 0.70
	env.tonemap_white = 3.2

	# One global knob for "more cartoon". Everything else in the restyle is a
	# colour choice somewhere; this is the finish over the top of all of them.
	#
	# THE WHOLE GRADE WAS CHOSEN BY MEASUREMENT. Six settings of ambient,
	# exposure, white point, saturation and contrast were applied to the live
	# ward in one boot and photographed from the same two vantages, then scored
	# on mean saturation, luminance spread and how much of the frame was
	# clipped. This one carries the most colour (0.161 against 0.132) and the
	# most contrast (sd 44.7 against 41.9) for no extra clipping. ACES was
	# brighter and clipped 12% of the frame; a near-linear white point at 6.0
	# was flatter than what it replaced.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.35
	env.adjustment_contrast = 1.16
	env.adjustment_brightness = 1.0

	# Soft bloom on the lamps and the signage, which is most of what makes a
	# stylised interior feel lit rather than merely visible.
	# GLOW THAT CAN ACTUALLY FIRE. The threshold was 1.35 against a tonemap
	# exposure of 0.78, so nothing in the building ever got near it: the pass
	# was enabled, cost its bandwidth every frame, and had never once bloomed
	# anything. The lit panel in a ceiling fitting is the one thing in an
	# interior that should bloom, and now does.
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# ABOVE ONE, so only the lit panels and the signage get in. At 0.92 half the
	# frame entered the glow buffer and SOFTLIGHT cooled and darkened every wall
	# in the building — the fix for "glow never fires" is a brighter light, not
	# a lower bar. `Build.lit_panel` emits at 2.4.
	env.glow_hdr_threshold = 1.05

	# Contact shading. Rounded geometry with an outline round it still floats
	# without something darkening where two things meet — this is what puts the
	# chairs on the floor rather than in front of it. Forward+ only; the
	# screenshot harness runs Compatibility and will not show it.
	# ONLY WHERE IT EXISTS. SSAO is Forward+ only, and this project ships on
	# Compatibility — the one renderer that can be run and therefore verified
	# here. Enabling it anyway printed "Screen-space ambient occlusion (SSAO)
	# can only be enabled when using the Forward+ rendering backend" on every
	# single launch of the shipped build, and did nothing.
	#
	# What replaced it is `Build.blob_shadow`: a patch under everything that
	# stands on the floor, which works on any backend. Left switched on where
	# the backend supports it, because the two are complementary rather than
	# alternatives — contact shadows ground an object, ambient occlusion darkens
	# the corners of a room.
	if _renderer() == "forward_plus":
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
	# NO SHADOW ON THE SUN, and it is a saving of four full-scene depth passes.
	#
	# This is an interior game. Every room in the building has a ceiling slab
	# over it, so the sun reaches nothing the player can see — and a directional
	# shadow map is rendered in four cascades over all 236,000 shadow-casting
	# triangles in the hospital whether it lands on anything or not. What it
	# actually produced was the broad soft diagonal banding across every ceiling
	# in every screenshot this project has taken: the underside of a slab, at a
	# grazing angle, shadow-tested against a blurred cascade. The ceiling
	# fittings carry the shaping now, which is where it belongs.
	sun.shadow_enabled = false
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
	# EVERY MINUTE, not once a shift. `apply_shift_look` reads
	# `GameState.minute_of_day` and was called only when a shift STARTED, which
	# is always eight in the morning — so `warmth` was always zero, the sun
	# never moved, the sky never changed and the whole function was a constant.
	# It is cheap (a handful of property writes and eleven fittings) and it is
	# the difference between a ward that gets late and a ward that does not.
	GameState.minute_passed.connect(func(_m): apply_shift_look())

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
	# AND THE FITTINGS INSIDE. `Hospital.set_lamp_look` existed, worked, and had
	# no caller anywhere in the project — the ward sister's eight o'clock and
	# the last hour of a shift were lit by identical bulbs, in a game whose
	# entire pressure is the evening arriving. The lamps go warmer and a little
	# stronger as the daylight goes, which is what actually happens in a
	# building: the interior lighting does not change, the balance does.
	if hospital:
		hospital.set_lamp_look(
			Color(1.0, 0.97, 0.90).lerp(Color(1.0, 0.88, 0.70), warmth),
			lerpf(0.62, 0.78, warmth))

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

## Which backend the build is configured for.
##
## The project setting, which is what a shipped build uses — there is no runtime
## accessor for this in 4.3 that GDScript can reach. A `--rendering-method` flag
## on the command line WOULD make this wrong; the only thing in the repo that
## passes one is `screenshots.sh`, and it passes the value already in the file.
## Both `boot_check.sh` and `export.sh` deliberately pass nothing, because
## forcing the renderer in a harness is how "the shipping renderer does not
## start at all" stayed invisible for a whole release.
static func _renderer() -> String:
	return String(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus"))

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
	# THE AUTHORED POINT, NOT A DICE ROLL.
	#
	# `Hospital.spawn_point()` exists and its docstring says "authored so the
	# first frame of a run is composed rather than rolled". Nothing called it.
	# This used `point_in("corridor")`, which is a random nav point anywhere
	# along a sixty-two metre corridor — so the first thing a new player saw was
	# wherever the dice landed, sometimes facing a wall, sometimes nose-first
	# into the ward door with "Open door · or just walk into it" filling the
	# screen. That is the first frame of the game and it was different every
	# launch. It also made every screenshot non-deterministic, which is how a
	# bedside shot ended up being a photograph of a door.
	player.global_position = hospital.spawn_point() + Vector3(0, 0.2, 0)
	player.face(hospital.point_in("ward"))

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
	_refresh_days_visitors()
	_seed_social_graph()
	# EVERY MORNING, NOT ONCE. `_spawn_staff` runs in `_ready`, and both of these
	# are gated on flags that only exist at the END of a night — `auditor_present`
	# and `vinnie_visits` are written by the End of Shift card, long after this
	# has run. A career never reloads Game.tscn (the day rolls over in place, via
	# `_carry` and `PatientSystem.reset_day`), so `_ready` never ran again and
	# neither of them could ever appear.
	#
	# So the game promised, in as many words, "Ms Ferrand from Coding is on the
	# ward for the next two shifts" and "there is a man in the corridor" on the
	# card at the end of every bad night, and then nobody arrived — for the whole
	# life of the feature.
	GameState.day_started.connect(func(_d): _refresh_days_visitors())
	_hook_the_ward_for_visitors()

## Family arrives DURING a shift rather than at the start of one, so it cannot
## come through `_refresh_days_visitors` with the auditor and Vinnie. WardDay
## says when; this says who and where.
func _hook_the_ward_for_visitors() -> void:
	var w = get_tree().get_first_node_in_group("ward_day")
	if w == null or not w.has_signal("visitor_arrived"):
		return
	if not w.visitor_arrived.is_connected(_on_visitor):
		w.visitor_arrived.connect(_on_visitor)

## SOMEBODY IS ACTUALLY IN THE ROOM.
##
## "Ruth Kerrigan is here to see her mother. She has brought a flask." has been
## printed at seven o'clock since the line was written, and nothing has ever
## spawned anybody — the same unkept promise as "Ms Ferrand from Coding is on
## the ward today", which was fixed by making her turn up.
##
## She matters because of what she is: a retired ward sister who reads charts.
## `family_reads_charts` is authored on her mother, `_family_read_it` is a
## finding built on it, and `_who_can_see_me` walks every registered mind — so
## putting her at the bedside means a note typed in front of her is a note she
## saw, without a line of new machinery.
func _on_visitor(pid, who) -> void:
	if hospital == null or suspicion == null:
		return
	var v := VisitorNPC.new()
	v.npc_id = "visitor_%s" % String(pid)
	v.display = String(who)
	v.patient_id = String(pid)
	v.set_look(_look(v.npc_id, 61, Color(0.45, 0.38, 0.42)))
	add_child(v)
	# BESIDE THE BED, ON THE SIDE THE ROOM IS ON. She came to see one person, so
	# "somewhere in the ward" is the wrong answer — and so is a fixed world-space
	# offset, which is what the first version used: +0.9 on z is toward the far
	# wall, because the beds stand head to the plaster, so she was put behind
	# the bedhead facing the plaster. Off the patient's own basis instead, which
	# already points down the bed toward the door.
	var spot := hospital.point_in("ward")
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps != null and ps.has_method("get_body"):
		var body = ps.get_body(String(pid))
		if body != null and is_instance_valid(body) and body.is_inside_tree():
			var t: Transform3D = body.global_transform
			spot = body.global_position + t.basis.z * 0.55 + t.basis.x * 0.95
			spot.y = 0.0
	v.global_position = spot
	# VISITING, not ARRIVING: she is put where she is going. Walking her in
	# from the door needs a nav path from outside the building, and the state
	# she would arrive in has its own documented trap.
	v.stand_and_argue(spot, 60.0)
	# ...and turned toward the bed rather than toward the wall behind it.
	if ps != null and ps.has_method("get_body"):
		var look_at_body = ps.get_body(String(pid))
		if look_at_body != null and is_instance_valid(look_at_body):
			v.look_toward(look_at_body.global_position)
	var mind = suspicion.minds.get(v.npc_id, null)
	if mind == null:
		mind = DB.make_mind(v.npc_id, v.display, "family", "observant")
	suspicion.register(mind, v)

## Who is on the ward today because of what happened last night. Rebuilt each
## morning: whoever should not be here any more goes, whoever should is spawned.
func _refresh_days_visitors() -> void:
	for c in get_children():
		if not (c is NurseNPC):
			continue
		var who := String(c.get("npc_id"))
		if who == "auditor" or who == "vinnie":
			# The BODY goes; SuspicionSystem hears about it through tree_exiting
			# and drops it from the registry. The MIND stays, which is why Ms
			# Ferrand is booked for two shifts and arrives on the second one
			# already knowing what she saw on the first.
			# remove_child BEFORE queue_free: queue_free is deferred to the end
			# of the frame, so a node freed that way is still in the tree — and
			# still visible, and still a registered witness — for the rest of
			# the morning it was supposed to have left.
			remove_child(c)
			c.queue_free()
	_spawn_auditor()
	_spawn_vinnie()

## AND THE PROMISE THE GAME MAKES AND DID NOT KEEP.
##
## After a REFERRED verdict the end-of-day screen says, in as many words:
## "There is an auditor on the ward tomorrow. She is not there to help. You will
## be asked to put things in writing while somebody watches you do it." Nothing
## happened. `auditor_present` was set by the worst verdict in the game and read
## by exactly one line weighting a tannoy announcement.
##
## She is a person now, and she does the thing the sentence describes: she walks
## the ward and the corridor and your office, and the witness system counts her
## like it counts anybody else. Which means the room with a door on it — the one
## place in the building where you can write something nobody saw you write —
## is not private any more. That is the whole of the mechanic, and it is exactly
## what the screen already promised.
## AND VINNIE, IF HE DID NOT GET WHAT HE WANTED.
##
## "He says he will call in — it is on his way" is printed at the end of any
## short night, and for four iterations nothing happened. `vinnie_visits` was
## written in three places and read in none. A man nobody on the ward can
## account for, standing in the corridor all day, is the plainest possible
## version of what that sentence means — and the witness system already knows
## what to do with somebody in the building.
func _spawn_vinnie() -> void:
	if not GameState.flag("vinnie_visits", false):
		return
	var v := NurseNPC.new()
	v.npc_id = "vinnie"
	v.archetype = "observant"
	v.display = "a man in the corridor"
	v.set_look(_look("vinnie", 46, Color(0.16, 0.15, 0.17)))
	v.patrol_rooms = ["corridor"]
	v.home_room = "corridor"
	add_child(v)
	v.global_position = hospital.point_in("corridor", "vinnie_spawn")
	var vm = suspicion.minds.get(v.npc_id, null)
	if vm == null:
		vm = DB.make_mind(v.npc_id, v.display, "institution", "observant")
	suspicion.register(vm, v)
	EventBus.toast.emit(
		"There is a man in the corridor. Adeyemi has asked twice who he is.", "bad")

func _spawn_auditor() -> void:
	if not GameState.flag("auditor_present", false):
		return
	var a := NurseNPC.new()
	a.npc_id = "auditor"
	a.archetype = "observant"
	a.display = "Ms Ferrand, Coding"
	# Not scrubs. She is not staff and she is not pretending to be.
	a.set_look(_look("auditor", 51, Color(0.26, 0.28, 0.34)))
	a.patrol_rooms = ["ward", "corridor", "office", "station"]
	a.home_room = "office"
	add_child(a)
	a.global_position = hospital.point_in("office", "auditor_spawn")
	# Reuse her mind if she has one. A fresh Mind every morning is a woman who
	# arrives for her second shift having forgotten the first.
	var mind = suspicion.minds.get(a.npc_id, null)
	if mind == null:
		mind = DB.make_mind(a.npc_id, a.display, "institution", "observant")
	suspicion.register(mind, a)
	EventBus.toast.emit("Ms Ferrand from Coding is on the ward today.", "bad")

func _spawn_nurse(arch: String, index: int) -> void:
	var n := NurseNPC.new()
	n.npc_id = "nurse_%d" % index
	n.archetype = arch
	n.display = "Nurse %s" % DB.WARD_NURSE
	n.set_look(_look(n.npc_id, 38,
		Build.SCRUB_BLUE if arch != "corrupt" else Build.SCRUB_GREEN))
	add_child(n)
	n.global_position = hospital.point_in("station", "nurse_spawn")
	var mind := DB.make_mind(n.npc_id, n.display, "nurse", arch)
	suspicion.register(mind, n)

## There is no second doctor. The only other clinician on this ward is the
## sister who reads the folder in the morning, and she does not need a body on
## the floor to do that — she needs the chart, which is where she gets her
## questions from.

## THE SAME PERSON EVERY CAREER. `_random_skin()` drew from `RNG`, which is
## seeded per world — so Nurse Adeyemi, whom the entire game is about being
## watched by, had a different face in every playthrough, and Ms Ferrand arrived
## for her second booked shift looking like somebody else. They are named
## characters. `Appearance` keys off the id, so they are stable everywhere.
##
## Their clothes stay authored: scrubs, a suit that is deliberately not scrubs,
## and whatever Vinnie is wearing. That is the half that means something.
func _look(id: String, age: int, uniform: Color) -> Dictionary:
	var look := Appearance.anyone(id, age)
	look["outfit"] = uniform
	return look

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
	# CONTINUE. The main menu set this flag and NOTHING READ IT — pressing
	# Continue restarted the career from day one, with the day number and the
	# money from the save still printed on the button that did it. Loading has
	# to happen before the ward starts, because what carries out of a save is
	# exactly what `WardDay.start()` reads: the day, the carried debt, and the
	# beds the ward sister could not stand up last night.
	if GameState.flag("continue_save", false):
		GameState.set_flag("continue_save", false)
		if not SaveSystem.load_game(SaveSystem.AUTOSAVE):
			Log.e("Continue pressed with no readable save; starting fresh", "Game")
	patient_system.populate()
	ward.start()
	if GameState.flag("headless_sim", false):
		return
	GameState.start_day()
	EventBus.request_ui.emit("morning", {})

var _place_accum := 0.0

func _physics_process(delta: float) -> void:
	if player and suspicion:
		suspicion.refresh_tells(player.global_position)
	# Twice a second is plenty to know which room somebody is standing in, and
	# it is what turns "I was at the bedside" into a claim that can be wrong.
	_place_accum += delta
	if _place_accum < 0.5 or ward == null or hospital == null or player == null:
		return
	_place_accum = 0.0
	var room := String(hospital.room_at(player.global_position))
	ward.observe_player(room, ward._who_can_see_me())
