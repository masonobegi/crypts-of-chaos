class_name NightSystem
extends Node
## The other half of the day.
##
## The ward has a supply problem that the game never acknowledged: patients
## arrive because a table said so. A doctor whose income depends on occupancy,
## in a building with five beds, has an obvious and appalling solution to an
## empty ward, and the whole tone of the thing points at it.
##
## So the evening is a phase. You go out, you find somebody, and if you are not
## seen doing it they are on your list in the morning with an injury that
## matches the place you found them in.
##
## IT IS THE SAME GAME AS THE WARD
##
## Deliberately. The ward is a stealth game about lines of sight and about who
## can later say what they saw; the street is that game with the furniture
## removed. Cones of vision, a lamp that makes you visible, a person walking a
## route, and a timer. Nothing here is a combat system and nothing here is
## graphic: the act itself is a single beat and a sound, and everything before
## it is positioning.
##
## What comes back is a PATIENT, with a name, in a bed, who has an opinion about
## how they got there — which is where the risk lives. A clean night is an
## admission. A messy one is an admission who remembers a face.

signal night_resolved(result: Dictionary)

## Where you go, who is there, and what they turn up with. Each place maps onto
## a different procedure, so a week of evenings fills a ward with variety rather
## than with five identical forearms.
const PLACES := [
	{
		"id": "ladder_yard", "name": "The Ladder Yard",
		"blurb": "Scaffolders finishing up. Everything here is already leaning.",
		"condition": "acute_shatter", "watchers": 3, "lamps": 2, "hazard": "",
		"pay": 1.0, "mark_speed": 62.0,
	},
	{
		"id": "ossory_steps", "name": "Ossory Street steps",
		"blurb": "Forty-one wet steps and one handrail, on the wrong side.",
		"condition": "fractured_ankle", "watchers": 2, "lamps": 1, "hazard": "",
		"pay": 0.9, "mark_speed": 48.0,
	},
	{
		"id": "the_anchor", "name": "The Anchor, at closing",
		"blurb": "Nobody in this street is a reliable witness and all of them are here.",
		"condition": "cracked_ribs", "watchers": 5, "lamps": 3, "hazard": "drunk",
		"pay": 1.25, "mark_speed": 40.0,
	},
	{
		"id": "multi_storey", "name": "The multi-storey, level four",
		"blurb": "One camera, pointed at the barrier. Concrete everywhere else.",
		"condition": "dislocated_shoulder", "watchers": 2, "lamps": 2, "hazard": "camera",
		"pay": 1.15, "mark_speed": 70.0,
	},
	{
		"id": "allotments", "name": "The allotments",
		"blurb": "Uneven ground, low fences, and a man who is always there.",
		"condition": "torn_knee", "watchers": 1, "lamps": 0, "hazard": "dog",
		"pay": 0.75, "mark_speed": 44.0,
	},
	{
		"id": "tram_stop", "name": "The tram stop on Fell Row",
		"blurb": "Well lit, well used, and the last tram was twenty minutes ago.",
		"condition": "percussive_sinus", "watchers": 4, "lamps": 3, "hazard": "tram",
		"pay": 1.1, "mark_speed": 56.0,
	},
]

## What else is in the street, besides people who might look up.
##
## Six identical evenings with a different number of pedestrians is one evening
## played six times. Each place gets a thing that behaves differently, so the
## question changes: a camera never blinks and has to be waited out, a dog comes
## to YOU, a drunk cannot be predicted, and a tram lights the whole street for a
## second and a half whatever you were doing at the time.
const HAZARDS := {
	"camera": "One camera, on the barrier. It does not get bored.",
	"dog": "Somebody's dog is loose and it has noticed you.",
	"drunk": "One of them is not walking in a straight line.",
	"tram": "A tram every half minute, and its lights go everywhere.",
}

static func hazard_note(id: String) -> String:
	return String(HAZARDS.get(String(place(id).get("hazard", "")), ""))

static func place(id: String) -> Dictionary:
	for p in PLACES:
		if String(p["id"]) == id:
			return p
	return PLACES[0]

## Names for people who are about to have an accident. Kept apart from the
## ward's own name pool so a mark never shares a name with somebody in a bed.
const MARK_NAMES := [
	"Wendell Tosh", "Bridie Kellaway", "Norbert Flitch", "Sable Ganney",
	"Ruthven Pike", "Delia Moss", "Aubrey Sprint", "Hettie Vaunt",
	"Cosmo Pell", "Ida Brannock", "Percy Loam", "Marguerite Ock",
]

## How exposed you were when it happened, and what that means.
const CLEAN := 0.26
const MESSY := 0.62

# ------------------------------------------------------------------ the street
## Everything the evening needs while it is happening, and nothing once it is
## over. The street is built when you go out and freed when you come home; the
## hospital is hidden rather than unloaded, because a ward is four thousand
## nodes and rebuilding it to walk down a road would be absurd.
var street: Street = null
var mark: NightMark = null
var watchers: Array = []
## One flat fan on the pavement per watcher, showing exactly where they are
## looking. Not decoration: the street asks you to route around three cones and
## a lamp, and a cone you cannot see is not a decision, it is a coin toss.
var cones: Array = []
var active := false
var exposure := 0.0
var _place: Dictionary = {}
var _mark_name := ""
var _player_was := Transform3D.IDENTITY
var _hospital_was := true
var _elapsed := 0.0
var _hazard_node: Node3D = null
var _hz_face := 0.0
var _hz_cone: MeshInstance3D = null
var _hidden: Array = []
var _tram := -1.0

## How far a person can see you, and how wide their attention is. Narrower and
## shorter than daylight on purpose: it is dark, they are going home, and the
## whole street is a negotiation with two lamp posts.
const SIGHT := 17.0
const CONE := 0.62
const EXPOSURE_RATE := 0.42
## Cool for "looking somewhere", hot for "looking at you". Deliberately NOT the
## sodium of the lamps: the street already has warm pools on the ground and a
## second warm shape on the ground would read as more of them. A cone has to be
## something a person can tell apart from a puddle of light at a glance, because
## the whole phase is deciding which one you are standing in.
const CONE_CLEAR := Color(0.42, 0.88, 0.86, 0.22)
const CONE_HOT := Color(1.0, 0.26, 0.22, 0.46)

var patient_system: PatientSystem = null
var legal = null
## Set while the evening's result is waiting to be reported in the morning.
var last_result: Dictionary = {}
## One outing per night. The rest of the evening is yours.
var used_tonight := false

func _ready() -> void:
	add_to_group("night_system")
	set_physics_process(false)
	patient_system = get_tree().get_first_node_in_group("patient_system")
	legal = get_tree().get_first_node_in_group("legal_system")

# ------------------------------------------------------------------ being seen
## The same question the ward asks, outdoors: is anybody looking at you, and is
## there enough light on you for it to matter.
##
## Deliberately a plain geometric check rather than the ward's full perception
## pass. There is no cover story for what happens here, nobody to explain it to
## afterwards, and no chart — so all that is left is distance, facing, a wall in
## the way, and how bright it is where you are standing.
func _physics_process(delta: float) -> void:
	if not active or street == null:
		return
	if _striking >= 0.0:
		_striking -= delta
		# They go down. A CharacterBody3D does not fall over on its own and
		# nothing here wants a ragdoll — a pitch and a sink reads as collapsing
		# from any angle you might be standing at.
		if mark != null and is_instance_valid(mark):
			mark.rotation.x = lerpf(mark.rotation.x, -PI * 0.46,
				clampf(delta * 6.0, 0.0, 1.0))
			mark.position.y -= delta * 0.55
		if _striking <= 0.0:
			_striking = -1.0
			finish(true)
		return
	_elapsed += delta
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var eye: Vector3 = player.global_position + Vector3(0, 1.2, 0)

	var seen := 0.0
	for i in watchers.size():
		var w = watchers[i]
		if not is_instance_valid(w):
			continue
		# They look about. A person standing still staring one way for a whole
		# evening is a turret, not somebody waiting for a taxi.
		var face: float = float(w.get_meta("facing", 0.0)) \
			+ sin(_elapsed * 0.7 + float(w.get_meta("phase", 0.0))) \
				* float(w.get_meta("sweep", 0.6))
		w.rotation.y = face
		var mine := _looks_at(w.global_position + Vector3(0, 1.5, 0), face,
			CONE, SIGHT, eye)
		seen = maxf(seen, mine)
		if i < cones.size():
			_aim_cone(cones[i], w.global_position, face, mine)
	var hz_seen := _hazard_sees(eye, delta)
	seen = maxf(seen, hz_seen)
	if _hz_cone != null and _hazard_node != null and is_instance_valid(_hazard_node):
		_aim_cone(_hz_cone, _hazard_node.global_position,
			_hazard_node.rotation.y, hz_seen)

	var light := _light_on(player.global_position)
	if seen > 0.0:
		exposure = clampf(exposure + seen * (0.55 + light * 0.9) * EXPOSURE_RATE * delta,
			0.0, 1.0)
		if fmod(_elapsed, 0.55) < delta:
			AudioMgr.play("tick", -26.0, 1.3)
	else:
		exposure = maxf(0.0, exposure - delta * 0.04)
	EventBus.objective_changed.emit("Get next to %s. [hold E]  ·  %s" % [
		_mark_name, exposure_word()])

	# They get home eventually, and then the evening is over whatever you did.
	if mark != null and is_instance_valid(mark) and mark.home():
		finish(false)
		return
	# And so can you. Walking back past the end you came in at is the way out —
	# without one, a player who decided halfway down that this was a bad idea
	# had nothing to do but stand in the dark waiting for somebody else's walk
	# home to finish.
	if street != null and player.global_position.x < Street.ORIGIN.x - Street.LENGTH * 0.47:
		finish(false)

func exposure_word() -> String:
	if exposure < 0.12:
		return "nobody has looked at you"
	if exposure < CLEAN:
		return "a glance, maybe"
	if exposure < MESSY:
		return "somebody has definitely seen you"
	return "you are being watched"

## Can somebody at `from`, facing `face`, see `target`? Distance, then cone,
## then a wall.
func _looks_at(from: Vector3, face: float, cone: float, reach: float,
		target: Vector3) -> float:
	var to := target - from
	to.y = 0.0
	var dist := to.length()
	if dist > reach or dist < 0.05:
		return 0.0
	var facing := Vector3(sin(face), 0.0, cos(face))
	var off: float = acos(clampf(facing.dot(to.normalized()), -1.0, 1.0))
	if off > cone:
		return 0.0
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, target)
	q.collision_mask = 1
	if not space.intersect_ray(q).is_empty():
		return 0.0
	return clampf((1.0 - off / cone) * (1.0 - dist / reach), 0.0, 1.0)

func _hazard_sees(eye: Vector3, delta: float) -> float:
	var hz := String(_place.get("hazard", ""))
	match hz:
		"camera":
			if _hazard_node == null:
				return 0.0
			_hz_face = PI + sin(_elapsed * 0.38) * 0.7
			_hazard_node.rotation.y = _hz_face
			return _looks_at(_hazard_node.global_position, _hz_face, 0.5, 26.0, eye)
		"dog":
			if _hazard_node == null or not is_instance_valid(_hazard_node):
				return 0.0
			# It comes to you. The only thing out here that closes distance.
			var to: Vector3 = eye - _hazard_node.global_position
			to.y = 0.0
			if to.length() < 22.0 and to.length() > 1.6:
				_hazard_node.global_position += to.normalized() * 2.2 * delta
				_hazard_node.rotation.y = atan2(to.x, to.z)
			return _looks_at(_hazard_node.global_position + Vector3(0, 0.6, 0),
				_hazard_node.rotation.y, 1.2, 11.0, eye)
		"drunk":
			if _hazard_node == null or not is_instance_valid(_hazard_node):
				return 0.0
			_hazard_node.global_position += Vector3(
				sin(_elapsed * 0.6), 0.0, cos(_elapsed * 0.41)) * 1.1 * delta
			_hz_face = sin(_elapsed * 1.4) * 2.4
			_hazard_node.rotation.y = _hz_face
			return _looks_at(_hazard_node.global_position + Vector3(0, 1.5, 0),
				_hz_face, 0.7, 14.0, eye)
		"tram":
			# Every twenty seconds the whole street is daylight for a moment,
			# and being anywhere at all is being somewhere lit.
			var phase: float = fposmod(_elapsed, 20.0)
			_tram = phase if phase < 3.0 else -1.0
	return 0.0

## How lit you are where you stand. A lamp does not make anybody look at you; it
## makes what they see usable.
func _light_on(at: Vector3) -> float:
	var best := 0.0
	if _tram >= 0.0:
		best = clampf(sin(_tram / 3.0 * PI), 0.0, 1.0) * 0.9
	if street == null:
		return best
	for l in street.lamps:
		var d: float = Vector2(at.x - l.x, at.z - l.z).length()
		best = maxf(best, clampf(1.0 - d / 8.5, 0.0, 1.0))
	return best

# ------------------------------------------------------------------ the act
## They are within reach and you have held the button down.
## The moment itself, and it is not instant.
##
## Cutting straight from the button to a results card threw away the only three
## pieces of feedback the phase has: the noise, them going down, and every head
## in the street coming round to look. Whether any of those heads actually SAW
## anything was decided long before this by the exposure you walked in with —
## this is them hearing it, which is a different and much better beat.
const STRIKE_BEAT := 1.4
var _striking := -1.0

func strike() -> void:
	if not active or _striking >= 0.0:
		return
	AudioMgr.play("crack", -5.0)
	AudioMgr.play("gasp", -10.0)
	_striking = STRIKE_BEAT
	var player = get_tree().get_first_node_in_group("player")
	if mark != null and is_instance_valid(mark):
		mark.stop_moving()
	if player == null:
		return
	for w in watchers:
		if not is_instance_valid(w):
			continue
		var to: Vector3 = player.global_position - w.global_position
		if Vector2(to.x, to.z).length() > 26.0:
			continue
		var face: float = atan2(to.x, to.z)
		w.rotation.y = face
		# Their sweep resumes from where they turned to, not from where they
		# were standing before the noise.
		w.set_meta("facing", face)
		w.startle(1.0)

## Come home, whatever happened.
func finish(reached: bool) -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	var res := resolve(String(_place["id"]), _mark_name, exposure, reached)
	leave()
	EventBus.request_ui.emit("night", {"result": res})

func leave() -> void:
	_set_night_look(false)
	# The daytime sky, put back. The shift look owns it the rest of the time.
	var game = get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("apply_shift_look"):
		game.apply_shift_look()
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		player.global_transform = _player_was
		player.velocity = Vector3.ZERO
	var hospital = get_tree().get_first_node_in_group("hospital")
	if hospital != null:
		hospital.visible = _hospital_was
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	watchers.clear()
	cones.clear()
	mark = null
	_hazard_node = null
	_hz_cone = null
	if street != null and is_instance_valid(street):
		street.queue_free()
	street = null


# ------------------------------------------------------------------ going out
## Leave the hospital and walk down a street.
##
## The evening used to be a top-down screen with dots on it. It is the same game
## as the ward now — same player, same controls, same question about who can see
## you — because that question IS the game and drawing it as a diagram threw
## away the only thing the phase had.
func enter(place_id: String) -> void:
	if active:
		return
	_place = place(place_id)
	_mark_name = mark_name(place_id + str(GameState.day))
	var game = get_tree().get_first_node_in_group("game")
	var player = get_tree().get_first_node_in_group("player")
	if game == null or player == null:
		return

	street = Street.new()
	street.name = "Street"
	game.add_child(street)
	street.build(_place)

	var hospital = get_tree().get_first_node_in_group("hospital")
	if hospital != null:
		_hospital_was = hospital.visible
		hospital.visible = false
	# And everybody in it. Staff and patients are not children of the building,
	# so hiding the building left a consultant in a white coat with his name
	# over his head walking down a street eleven miles from work.
	_hidden.clear()
	for n in get_tree().get_nodes_in_group("npc"):
		if n is Node3D and n.visible:
			_hidden.append(n)
			n.visible = false
	_player_was = player.global_transform
	player.global_position = street.player_start
	player.velocity = Vector3.ZERO

	_spawn_people()
	_set_night_look(true)
	exposure = 0.0
	_elapsed = 0.0
	_striking = -1.0
	_tram = -1.0
	active = true
	set_physics_process(true)
	EventBus.objective_changed.emit(
		"Get next to %s without being seen. [hold E]" % _mark_name)
	EventBus.toast.emit("%s. %s" % [String(_place["name"]), String(_place["blurb"])],
		"info")
	EventBus.toast.emit("Walk back the way you came if you change your mind.", "info")
	AudioMgr.play("door", -12.0)

func _spawn_people() -> void:
	mark = NightMark.new()
	mark.name = "Mark"
	mark.display = _mark_name
	mark.set_colours(Color(0.86, 0.72, 0.60), Color(0.30, 0.28, 0.36),
		Color(0.22, 0.16, 0.12))
	street.add_child(mark)
	mark.start(street.mark_route)

	watchers.clear()
	cones.clear()
	for spot in street.watcher_spots:
		var w := NPCBody.new()
		w.display = ""
		w.set_colours(Color(0.80, 0.66, 0.54), Color(0.24, 0.26, 0.32),
			Color(0.20, 0.18, 0.16))
		street.add_child(w)
		w.global_position = Vector3(spot["pos"])
		w.rotation.y = float(spot["facing"])
		w.set_meta("facing", float(spot["facing"]))
		w.set_meta("sweep", 0.5 + randf() * 0.5)
		w.set_meta("phase", randf() * TAU)
		watchers.append(w)
		var cone := _cone_node(CONE, SIGHT)
		street.add_child(cone)
		cones.append(cone)

	_hazard_node = null
	_hz_cone = null
	var hz := String(_place.get("hazard", ""))
	if hz == "dog" or hz == "drunk":
		var h := NPCBody.new()
		h.display = ""
		h.set_colours(Color(0.62, 0.48, 0.36), Color(0.36, 0.28, 0.24),
			Color(0.18, 0.14, 0.12))
		if hz == "dog":
			h.height_scale = 0.55
		street.add_child(h)
		h.global_position = street.hazard_spot
		_hazard_node = h
	elif hz == "camera":
		var cam := Node3D.new()
		street.add_child(cam)
		cam.global_position = street.hazard_spot + Vector3(0, 4.2, 0)
		cam.add_child(Build.mi(Build.cyl_mesh(0.07, 4.2, 8),
			Build.mat(Color(0.18, 0.19, 0.21), 0.6), Vector3(0, -2.1, 0)))
		cam.add_child(Build.box_mi(Vector3(0.36, 0.26, 0.5), Color(0.30, 0.32, 0.36),
			Vector3.ZERO, 0.5, 0.010))
		cam.add_child(Build.mi(Build.sphere_mesh(0.07),
			Build.unshaded(Color(0.95, 0.24, 0.20)), Vector3(0, 0, 0.28)))
		_hazard_node = cam
	if _hazard_node != null and hz != "tram":
		var spread: float = 0.5 if hz == "camera" else (1.2 if hz == "dog" else 0.7)
		var reach: float = 26.0 if hz == "camera" else (11.0 if hz == "dog" else 14.0)
		_hz_cone = _cone_node(spread, reach)
		street.add_child(_hz_cone)

## A flat fan on the ground, forward along +Z so it can simply take the
## watcher's own facing. Vertex alpha falls off toward the rim, which is what
## stops it reading as a slice of cheese lying in the road.
func _cone_node(half: float, reach: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 20
	for i in steps:
		var a0: float = -half + 2.0 * half * float(i) / float(steps)
		var a1: float = -half + 2.0 * half * float(i + 1) / float(steps)
		st.set_normal(Vector3.UP)
		st.set_color(Color(1, 1, 1, 1))
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.set_color(Color(1, 1, 1, 0.10))
		st.add_vertex(Vector3(sin(a1), 0.0, cos(a1)) * reach)
		st.set_normal(Vector3.UP)
		st.set_color(Color(1, 1, 1, 0.10))
		st.add_vertex(Vector3(sin(a0), 0.0, cos(a0)) * reach)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Cones cross each other constantly and two of them fighting over the same
	# pixel is worse than either being slightly wrong.
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = CONE_CLEAR
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Put a cone where its owner is, pointing where they are pointing, and colour
## it by whether it is currently on you. Warm and faint is "somebody is looking
## over there"; hot is "somebody is looking at you", and the two have to be
## distinguishable at a glance from the far end of the street.
func _aim_cone(cone: MeshInstance3D, at: Vector3, face: float, seen: float) -> void:
	if cone == null or not is_instance_valid(cone):
		return
	cone.global_position = Vector3(at.x, Street.ORIGIN.y + 0.27, at.z)
	cone.rotation.y = face
	var m := cone.material_override as StandardMaterial3D
	if m != null:
		m.albedo_color = CONE_CLEAR.lerp(CONE_HOT, clampf(seen * 2.2, 0.0, 1.0))

## Night, from a street. The hospital's own lighting is for a lit interior and
## makes a road at eleven at night look like a car park at noon.
func _set_night_look(on: bool) -> void:
	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var env = game.get("_env")
	var sun = game.get("_sun")
	var fill = game.get("_fill")
	# Cartoon night, not pitch black. The first version was physically plausible
	# and photographed as a completely black rectangle with two lit windows in
	# it — a street you cannot see is not a stealth level, it is a screensaver.
	# Moonlight does the reading and the lamps do the danger.
	if env != null:
		# sky_contribution is the whole ball game. The shift look leaves it at
		# Godot's default of 1.0, which means "take ambient from the sky and
		# ignore ambient_light_color entirely" — fine at noon under a blue sky,
		# fatal at night when the sky has just been set to near-black. The first
		# street rendered as a blown-out white pavement (all key, no ambient)
		# with pure-black wedges wherever the moon did not reach, because the
		# only thing lighting anything was the directional. Taking ambient off
		# the sky is what lets the moon be dim enough for a lamp to matter.
		env.ambient_light_sky_contribution = 0.0 if on else 1.0
		env.ambient_light_color = Color(0.30, 0.38, 0.64) if on else Color(0.72, 0.82, 0.92)
		env.ambient_light_energy = 0.70 if on else 0.30
		# Sodium lamps are the only bright thing in the frame now, so let them
		# actually bloom instead of sitting under the daytime threshold.
		env.glow_hdr_threshold = 0.85 if on else 1.35
	if sun != null:
		# A moon, doing the reading. The first pass at this was physically
		# plausible and photographed as a black rectangle with two lit windows
		# in it: a street you cannot see is not a stealth level, it is a
		# screensaver. Blue and bright enough to read, dim enough to be night.
		# No moon shadow. A directional shadow across a street at night is a
		# hard black wedge over half the pavement and it is the only thing in
		# frame competing with the lamps — and the lamps ARE the mechanic. With
		# it off, the only light contrast left in the street is the pools you
		# can choose to walk around.
		sun.shadow_enabled = not on
		sun.light_energy = 0.30 if on else 0.9
		sun.light_color = Color(0.62, 0.74, 1.0) if on else Color(1, 0.97, 0.9)
		if on:
			sun.rotation_degrees = Vector3(-56, 26, 0)
	if fill != null:
		fill.light_energy = 0.12 if on else 0.5
		fill.light_color = Color(0.42, 0.52, 0.86) if on else Color(1, 1, 1)
	var sky = game.get("_sky_mat")
	if sky != null and on:
		sky.sky_top_color = Color(0.05, 0.07, 0.18)
		sky.sky_horizon_color = Color(0.16, 0.22, 0.40)
		sky.ground_bottom_color = Color(0.05, 0.06, 0.10)
		sky.ground_horizon_color = Color(0.16, 0.22, 0.40)

## Is there any point going out? A full ward is the one honest reason not to.
func available() -> bool:
	if used_tonight:
		return false
	return not GameState.flag("tutorial_active", false)

func beds_free() -> int:
	if patient_system == null:
		return 0
	return patient_system.free_wards().size()

static func mark_name(seed_key: String) -> String:
	return String(RNG.pick("mark_%s" % seed_key, MARK_NAMES))

## Turn an evening into a morning.
##
## `exposure` is 0..1 — how much of the act happened where somebody could see
## it. `reached` is whether you got to them at all.
func resolve(place_id: String, mark: String, exposure: float, reached: bool) -> Dictionary:
	used_tonight = true
	var spec := place(place_id)
	var res := {
		"place": String(spec["name"]), "mark": mark, "exposure": exposure,
		"admitted": false, "outcome": "missed",
	}
	GameState.stats.night_jobs += 1

	if not reached:
		# You stood in a doorway for twenty minutes and went home. It costs
		# nothing but the evening, which is the correct price for losing nerve.
		res["outcome"] = "missed"
		res["line"] = "They went in before you got near them. You walk home the long way."
		last_result = res
		night_resolved.emit(res)
		return res

	var clean: bool = exposure < CLEAN
	var messy: bool = exposure < MESSY
	res["outcome"] = "clean" if clean else ("messy" if messy else "caught")

	if clean:
		GameState.stats.night_jobs_clean += 1
		res["line"] = "Nobody looked up. They are going to need somebody to look at that."
	elif messy:
		GameState.stats.night_jobs_botched += 1
		GameState.add_heat(0.08, "something on Fell Row")
		res["line"] = "Somebody in a window. Somebody always in a window."
	else:
		GameState.stats.night_jobs_botched += 1
		GameState.add_heat(0.22, "a description given to police")
		res["line"] = "Two people saw the whole thing and one of them ran after you."

	# Whatever happened, they need a hospital, and yours is the near one. Even
	# the caught case sends them your way — which is the joke and the trap: the
	# witness to your evening is now in your ward, in your care, all week.
	if beds_free() > 0 or messy:
		_book_admission(spec, mark, res["outcome"])
		res["admitted"] = true
	else:
		res["line"] += " There is nowhere to put them; they go across town."

	last_result = res
	night_resolved.emit(res)
	Meta.check_achievements()
	return res

## They turn up tomorrow. Held as a booking rather than a patient so the night
## genuinely ends in between — same machinery a readmission uses, because from
## the ward's point of view that is exactly what this is: somebody arriving in
## the morning with a plausible story.
func _book_admission(spec: Dictionary, mark: String, outcome: String) -> void:
	if patient_system == null:
		return
	patient_system.night_admissions.append({
		"condition": String(spec["condition"]),
		"name": mark,
		"day": GameState.day + 1,
		"outcome": outcome,
		"place": String(spec["name"]),
	})

func new_day() -> void:
	used_tonight = false

func to_dict() -> Dictionary:
	return {"used": used_tonight, "last": last_result.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	used_tonight = bool(d.get("used", false))
	last_result = Dictionary(d.get("last", {}))
