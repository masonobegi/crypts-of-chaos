class_name Street
extends Node3D
## Somewhere that is not the hospital.
##
## The evening used to be a top-down 2D screen with dots on it, and the note
## after playing it was "the crime minigames should be in 3D as well, the one I
## just played sucked". Correct: the ward is a first-person stealth game about
## lines of sight, and abstracting the one place where that is the ENTIRE game
## into a diagram threw away the only thing it had going for it.
##
## So this is a street you walk down. Same player, same controls, same rules
## about who can see you — a road, two pavements, a terrace either side, lamps
## that make a pool of light you can stand outside of, and enough parked things
## to hide behind. Built from primitives at load time like everything else.

const LENGTH := 74.0
const ROAD_HALF := 4.0
const PAVE := 4.2
const BUILD_DEPTH := 9.0
const WALL_H := 9.0

## Warm sodium, because the whole point of a street lamp here is that it is a
## place you can choose not to stand in.
const LAMP := Color(1.0, 0.78, 0.42)

var lamps: Array[Vector3] = []
var mark_route: PackedVector3Array = PackedVector3Array()
var watcher_spots: Array[Dictionary] = []      ## {pos, facing}
var hazard_spot := Vector3.ZERO
var player_start := Vector3.ZERO
var place_id := ""

func build(spec: Dictionary) -> void:
	place_id = String(spec.get("id", "street"))
	_ground()
	# Half the building's depth, not all of it: the house's FRONT has to land on
	# the far edge of the pavement. The first version put its centre there and
	# left four and a half metres of nothing between kerb and doorstep, which
	# photographed as a black trench running the length of the street.
	var front: float = ROAD_HALF + PAVE + BUILD_DEPTH * 0.5
	_terrace(front)
	_terrace(-front)
	_street_furniture()
	_lamps(int(spec.get("lamps", 2)))
	_layout_people(int(spec.get("watchers", 3)))

# ------------------------------------------------------------------ ground
func _ground() -> void:
	# The road. Dark, wet-looking, and the widest thing in shot.
	var road := Build.wall(Vector3(LENGTH, 0.4, ROAD_HALF * 2.0),
		Color(0.20, 0.20, 0.24), Vector3(0, -0.2, 0), 0.0, 0.0)
	road.name = "Road"
	add_child(road)
	for i in 15:
		add_child(Build.box_mi(Vector3(2.2, 0.02, 0.22), Color(0.52, 0.50, 0.42),
			Vector3(-LENGTH * 0.5 + 3.0 + float(i) * 5.0, 0.011, 0.0), 0.85, 0.0))

	# The ends of the street. Invisible, because a street that stops at a wall
	# you can see is a set; one that stops at a wall you cannot is a street.
	for side in [1.0, -1.0]:
		var cap := Build.wall(Vector3(0.6, 12.0, 44.0), Color(0.10, 0.11, 0.16),
			Vector3(side * (LENGTH * 0.5 + 0.3), 6.0, 0.0), 0.0, 0.0)
		cap.name = "StreetEnd"
		add_child(cap)

	for side in [1.0, -1.0]:
		var z: float = side * (ROAD_HALF + PAVE * 0.5)
		var pave := Build.wall(Vector3(LENGTH, 0.34, PAVE),
			Color(0.38, 0.39, 0.42), Vector3(0, 0.03, z), 0.0, 0.0)
		pave.name = "Pavement"
		add_child(pave)
		# The kerb, which is the line that tells you where the road stops.
		add_child(Build.box_mi(Vector3(LENGTH, 0.22, 0.16), Color(0.30, 0.30, 0.29),
			Vector3(0, 0.11, side * ROAD_HALF), 0.8, 0.0))
		# Paving slabs, as scored lines. Cheap, and it stops four hundred square
		# metres of grey reading as a plane.
		for i in 25:
			add_child(Build.box_mi(Vector3(0.05, 0.02, PAVE - 0.3),
				Color(0.14, 0.15, 0.17),
				Vector3(-LENGTH * 0.5 + 1.5 + float(i) * 3.0, 0.21, z), 0.9, 0.0))

## A row of houses. Each one is a block with a door and some windows, a few of
## which are lit — which is what makes a street at night read as a place people
## live rather than as two long walls.
func _terrace(z: float) -> void:
	var facing: float = -1.0 if z > 0.0 else 1.0
	var n := 9
	var w: float = LENGTH / float(n)
	for i in n:
		var x: float = -LENGTH * 0.5 + w * (float(i) + 0.5)
		var h: float = WALL_H * (0.78 + 0.22 * fposmod(sin(float(i) * 12.9898 + z) * 43758.5, 1.0))
		var brick := Color(0.62, 0.46, 0.40).lerp(Color(0.50, 0.50, 0.60),
			fposmod(float(i) * 0.37, 1.0))
		var block := Build.wall(Vector3(w - 0.2, h, BUILD_DEPTH), brick,
			Vector3(x, h * 0.5, z), 0.0, 0.02)
		block.name = "House"
		add_child(block)
		# Face of the house, toward the road.
		var face_z: float = z + facing * (BUILD_DEPTH * 0.5 + 0.06)
		# A door.
		add_child(Build.box_mi(Vector3(1.0, 2.1, 0.10), Color(0.16, 0.20, 0.26),
			Vector3(x - w * 0.22, 1.05, face_z), 0.8, 0.010))
		# Windows, some of them on.
		for row in 2:
			for col in 2:
				var lit: bool = (i * 7 + row * 3 + col) % 5 < 2
				var wx: float = x - w * 0.18 + float(col) * w * 0.34
				var wy: float = 1.6 + float(row) * 2.4
				if wy + 0.7 > h:
					continue
				add_child(Build.box_mi(Vector3(0.9, 1.15, 0.08),
					Color(0.10, 0.11, 0.14), Vector3(wx, wy, face_z), 0.8, 0.008))
				if lit:
					var pane := Build.mi(Build.box_mesh(Vector3(0.74, 0.96, 0.02)),
						Build.unshaded(Color(1.0, 0.86, 0.52)),
						Vector3(wx, wy, face_z + facing * 0.06))
					add_child(pane)

# ------------------------------------------------------------------ dressing
func _street_furniture() -> void:
	# A parked van, which is the only proper cover in the street and therefore
	# the most important object in it.
	var van := Build.wall(Vector3(5.2, 2.3, 2.1), Color(0.44, 0.46, 0.50),
		Vector3(-8.0, 1.15, ROAD_HALF - 1.3), 0.0, 0.016)
	van.name = "Van"
	add_child(van)
	add_child(Build.box_mi(Vector3(1.9, 1.0, 2.0), Color(0.26, 0.32, 0.40),
		Vector3(-10.6, 1.75, ROAD_HALF - 1.3), 0.5, 0.012))
	for dx in [-1.6, 1.6]:
		for dz in [-0.95, 0.95]:
			add_child(Build.mi(Build.cyl_mesh(0.42, 0.28, 12),
				Build.mat(Color(0.10, 0.10, 0.12), 0.9),
				Vector3(-8.0 + dx, 0.42, ROAD_HALF - 1.3 + dz),
				Vector3(0, 0, PI * 0.5)))

	# Wheelie bins, in twos, on both pavements.
	for spot in [Vector3(14.0, 0, ROAD_HALF + 1.4), Vector3(15.2, 0, ROAD_HALF + 1.4),
			Vector3(-24.0, 0, -ROAD_HALF - 1.4), Vector3(-22.8, 0, -ROAD_HALF - 1.4),
			Vector3(28.0, 0, -ROAD_HALF - 1.5)]:
		var bin := Build.wall(Vector3(0.72, 1.1, 0.68), Color(0.20, 0.32, 0.26),
			spot + Vector3(0, 0.55 + 0.2, 0), 0.0, 0.012)
		bin.name = "Bin"
		add_child(bin)
		add_child(Build.box_mi(Vector3(0.76, 0.08, 0.72), Color(0.26, 0.40, 0.32),
			spot + Vector3(0, 1.34, 0), 0.6, 0.008))

	# A post box, and a phone box nobody has used this century.
	add_child(Build.mi(Build.cyl_mesh(0.32, 1.5, 14),
		Build.mat(Color(0.56, 0.12, 0.12), 0.8), Vector3(4.0, 0.95, ROAD_HALF + 2.4)))
	var kiosk := Build.wall(Vector3(1.0, 2.4, 1.0), Color(0.52, 0.12, 0.12),
		Vector3(-30.0, 1.4, ROAD_HALF + 2.2), 0.0, 0.014)
	kiosk.name = "Kiosk"
	add_child(kiosk)

func _lamps(count: int) -> void:
	lamps.clear()
	count = maxi(count, 1)
	for i in count:
		var t: float = (float(i) + 0.5) / float(count)
		var x: float = -LENGTH * 0.45 + LENGTH * 0.9 * t
		var z: float = (ROAD_HALF + 1.0) * (1.0 if i % 2 == 0 else -1.0)
		var post := Node3D.new()
		post.name = "Lamp"
		add_child(post)
		post.position = Vector3(x, 0, z)
		post.add_child(Build.mi(Build.cyl_mesh(0.10, 5.0, 10),
			Build.mat(Color(0.16, 0.17, 0.19), 0.6), Vector3(0, 2.5, 0)))
		var arm_dir: float = -1.0 if z > 0.0 else 1.0
		post.add_child(Build.box_mi(Vector3(0.10, 0.10, 1.4), Color(0.16, 0.17, 0.19),
			Vector3(0, 4.95, arm_dir * 0.7), 0.6, 0.008))
		var head := Vector3(0, 4.8, arm_dir * 1.35)
		post.add_child(Build.mi(Build.box_mesh(Vector3(0.5, 0.18, 0.9)),
			Build.unshaded(Color(1.0, 0.90, 0.62)), head))
		var light := OmniLight3D.new()
		light.light_color = LAMP
		light.light_energy = 7.5
		light.omni_range = 18.0
		light.shadow_enabled = false
		light.position = head + Vector3(0, -0.2, 0)
		post.add_child(light)
		lamps.append(post.position + head)

# ------------------------------------------------------------------ people
## Where everybody starts, and where the mark is walking. Deliberately laid out
## so the mark's route passes through at least one pool of lamplight: the
## decision the street is asking is "do I take them here, or wait".
func _layout_people(watchers: int) -> void:
	player_start = Vector3(-LENGTH * 0.44, 1.0, ROAD_HALF + 1.6)
	mark_route = PackedVector3Array([
		Vector3(LENGTH * 0.46, 0.4, ROAD_HALF + 1.8),
		Vector3(LENGTH * 0.10, 0.4, ROAD_HALF + 1.8),
		Vector3(-LENGTH * 0.06, 0.4, ROAD_HALF + 2.6),
		Vector3(-LENGTH * 0.30, 0.4, ROAD_HALF + 2.2),
		Vector3(-LENGTH * 0.47, 0.4, ROAD_HALF + 2.0),
	])
	watcher_spots.clear()
	for i in maxi(watchers, 0):
		var t: float = (float(i) + 0.7) / float(maxi(watchers, 1))
		var x: float = -LENGTH * 0.36 + LENGTH * 0.72 * t
		var far: bool = i % 2 == 1
		var z: float = (-ROAD_HALF - 2.0) if far else (ROAD_HALF + 3.1)
		watcher_spots.append({
			"pos": Vector3(x, 0.4, z),
			"facing": (PI * 0.5 if far else -PI * 0.5) + sin(float(i) * 2.3) * 0.8,
		})
	hazard_spot = Vector3(LENGTH * 0.18, 0.4, -ROAD_HALF - 2.4)
