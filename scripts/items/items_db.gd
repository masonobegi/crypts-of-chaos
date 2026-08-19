class_name Items
extends RefCounted
## Every physical object in the hospital, as data. Adding an item is one entry
## here plus (optionally) a behaviour script.
##
## `tool` matches DBuild.TREATMENTS[*].tool — holding an item whose id equals a
## treatment's tool is what makes that treatment available on a patient.

const SPECS := {
	# ---------------------------------------------------------- treatment tools
	"mallet": {
		"name": "Approved Percussion Mallet", "mass": 1.4, "size": Vector3(0.1, 0.1, 0.5),
		"blurb": "Rubber. Approved. Alarmingly satisfying.",
		"shape": "mallet", "color": Color(0.55, 0.30, 0.22),
	},
	"syringe": {
		"name": "Dosing Syringe", "mass": 0.3, "size": Vector3(0.06, 0.06, 0.28),
		"blurb": "Refillable. Relabellable. That's on the hospital, not you.",
		"shape": "syringe", "color": Color(0.88, 0.90, 0.93),
		"contents": "chalkinol", "label": "Chalkinol",
	},
	"iv_bag": {
		"name": "IV Bag", "mass": 1.0, "size": Vector3(0.24, 0.34, 0.1),
		"blurb": "Hangs on a stand. Falls off a stand.",
		"shape": "bag", "color": Color(0.80, 0.90, 0.85),
		"contents": "saline", "label": "Standard Saline",
	},
	"compress": {
		"name": "Warm Compress", "mass": 0.4, "size": Vector3(0.26, 0.08, 0.18),
		"blurb": "Warm for approximately nine minutes.",
		"shape": "box", "color": Color(0.86, 0.55, 0.48),
	},
	"blanket": {
		"name": "Gravitational Blanket", "mass": 3.2, "size": Vector3(0.5, 0.14, 0.4),
		"blurb": "Extremely heavy. Reassuringly so.",
		"shape": "box", "color": Color(0.35, 0.42, 0.62),
	},
	"colour_lamp": {
		"name": "Colour Therapy Lamp", "mass": 2.6, "size": Vector3(0.24, 0.42, 0.24),
		"blurb": "Six settings. Two are legal in most jurisdictions.",
		"shape": "lamp", "color": Color(0.92, 0.72, 0.30),
	},
	"steam_kit": {
		"name": "Steam Tent Kit", "mass": 3.0, "size": Vector3(0.4, 0.3, 0.3),
		"blurb": "A tent. Some steam. Assembly required.",
		"shape": "box", "color": Color(0.60, 0.72, 0.78),
	},
	"duster": {
		"name": "Ultrasonic Duster", "mass": 1.2, "size": Vector3(0.12, 0.12, 0.42),
		"blurb": "Emits a frequency. The frequency is not for you.",
		"shape": "duster", "color": Color(0.45, 0.65, 0.72),
	},
	"wrench": {
		"name": "Spleen Torque Wrench", "mass": 2.2, "size": Vector3(0.09, 0.09, 0.55),
		"blurb": "Calibrated. Do not overtighten. Please.",
		"shape": "wrench", "color": Color(0.62, 0.64, 0.70),
	},

	# ---------------------------------------------------------- paperwork
	"chart": {
		"name": "Patient Chart", "mass": 0.6, "size": Vector3(0.3, 0.04, 0.42),
		"blurb": "The official version of events.",
		"shape": "clipboard", "color": Color(0.90, 0.88, 0.80),
		"script": "res://scripts/items/chart_prop.gd",
		"incriminating_tag": "paperwork", "incriminating_weight": 0.0,
	},
	"blank_form": {
		"name": "Blank Form 27-B", "mass": 0.2, "size": Vector3(0.26, 0.02, 0.36),
		"blurb": "Every complication needs one. Allegedly.",
		"shape": "paper", "color": Build.PAPER,
	},
	"incident_report": {
		"name": "Incident Report", "mass": 0.2, "size": Vector3(0.26, 0.02, 0.36),
		"blurb": "Somebody filed this. Somebody will read it.",
		"shape": "paper", "color": Color(0.95, 0.80, 0.55),
		"incriminating_tag": "paperwork", "incriminating_weight": 0.35,
	},

	# ---------------------------------------------------------- environment
	"bedpan": {
		"name": "Bedpan", "mass": 1.1, "size": Vector3(0.32, 0.12, 0.26),
		"blurb": "Empty. Probably. Mostly.",
		"shape": "bowl", "color": Color(0.78, 0.80, 0.84),
	},
	"mop": {
		"name": "Mop", "mass": 2.0, "size": Vector3(0.1, 0.1, 1.4),
		"blurb": "The single most respected object in this building.",
		"shape": "mop", "color": Color(0.45, 0.35, 0.25),
	},
	"bucket": {
		"name": "Mop Bucket", "mass": 4.0, "size": Vector3(0.4, 0.36, 0.4),
		"blurb": "Wheels. Water. Consequences.",
		"shape": "bucket", "color": Color(0.85, 0.75, 0.30),
		"contents": "mop_water",
	},
	"wet_floor_sign": {
		"name": "Wet Floor Sign", "mass": 1.0, "size": Vector3(0.3, 0.6, 0.3),
		"blurb": "Legally, this makes the floor safe.",
		"shape": "sign", "color": Color(0.95, 0.78, 0.15),
	},
	"coffee": {
		"name": "Break Room Coffee", "mass": 0.4, "size": Vector3(0.1, 0.14, 0.1),
		"blurb": "Free. Correspondingly good.",
		"shape": "cup", "color": Color(0.35, 0.25, 0.18), "fragile": true,
	},
	"flowers": {
		"name": "Get Well Flowers", "mass": 1.2, "size": Vector3(0.22, 0.4, 0.22),
		"blurb": "From someone who is going to ask questions later.",
		"shape": "flowers", "color": Color(0.85, 0.45, 0.55), "fragile": true,
	},
	"pillow": {
		"name": "Pillow", "mass": 0.5, "size": Vector3(0.5, 0.14, 0.34),
		"blurb": "Standard issue. Aerodynamic.",
		"shape": "box", "color": Build.LINEN,
	},
	"clipboard_blank": {
		"name": "Spare Clipboard", "mass": 0.5, "size": Vector3(0.28, 0.04, 0.4),
		"blurb": "Carrying one of these makes you look busy. Genuinely useful.",
		"shape": "clipboard", "color": Color(0.72, 0.66, 0.52),
	},
	"wheelchair": {
		"name": "Wheelchair", "mass": 20.0, "size": Vector3(0.66, 1.0, 0.8),
		"blurb": "Rolls. Keeps rolling. Nobody has ever found the brake.",
		"shape": "wheelchair", "color": Color(0.28, 0.32, 0.38),
	},
	"extinguisher": {
		"name": "Fire Extinguisher", "mass": 8.0, "size": Vector3(0.18, 0.55, 0.18),
		"blurb": "Heavy. Loud. Last inspected during a previous administration.",
		"shape": "extinguisher", "color": Build.BAD,
	},
	"dread_canister": {
		"name": "Dread Canister", "mass": 5.0, "size": Vector3(0.26, 0.44, 0.26),
		"blurb": "Full. Should not be full.",
		"shape": "canister", "color": Color(0.38, 0.34, 0.46),
		"contents": "ambient_dread", "label": "EMPTY — SAFE TO REFIT",
		"incriminating_tag": "equipment", "incriminating_weight": 0.3,
	},
	"pill_bottle": {
		"name": "Pill Bottle", "mass": 0.2, "size": Vector3(0.09, 0.14, 0.09),
		"blurb": "The label is a suggestion.",
		"shape": "cylinder", "color": Color(0.85, 0.60, 0.25),
		"contents": "chalkinol", "label": "Chalkinol 40mg",
	},
	"thermometer": {
		"name": "Ward Thermometer", "mass": 0.3, "size": Vector3(0.08, 0.2, 0.05),
		"blurb": "Reads the room. Literally.",
		"shape": "box", "color": Color(0.9, 0.9, 0.95),
	},
	"tray": {
		"name": "Instrument Tray", "mass": 1.6, "size": Vector3(0.42, 0.06, 0.3),
		"blurb": "Holds things. Drops things.",
		"shape": "box", "color": Build.METAL,
	},
	"stapler": {
		"name": "Stapler", "mass": 0.9, "size": Vector3(0.08, 0.09, 0.22),
		"blurb": "Nobody knows whose it is.",
		"shape": "box", "color": Color(0.25, 0.28, 0.32),
	},
	"keycard": {
		"name": "Staff Keycard", "mass": 0.05, "size": Vector3(0.09, 0.01, 0.06),
		"blurb": "Opens most things. Records that it opened them.",
		"shape": "box", "color": Color(0.30, 0.62, 0.72),
	},
}

## Contents you can load into a syringe/bag. `effect_as` maps to a treatment id;
## "" means it does nothing at all, which is the entire point of Saline Plus.
const SUBSTANCES := {
	"chalkinol": {"name": "Chalkinol", "effect_as": "chalkinol", "color": Color(0.85, 0.88, 0.95)},
	"placebex": {"name": "Placebex", "effect_as": "placebex", "color": Color(0.95, 0.92, 0.75)},
	"saline": {"name": "Standard Saline", "effect_as": "fluids", "color": Color(0.85, 0.95, 0.92)},
	"saline_plus": {"name": "Saline Plus", "effect_as": "", "color": Color(0.86, 0.94, 0.90),
		"blurb": "Identical to saline in every respect including effect."},
	# Administering this puts back exactly what you just took out. Entirely
	# physical, entirely deniable-looking, and the funniest loop in the game.
	"ambient_dread": {"name": "Recovered Ambient Dread", "effect_as": "",
		"complication": "ambient_dread", "color": Color(0.4, 0.35, 0.5),
		"blurb": "Was in a patient. Is now in a canister. Should stay in the canister."},
	"mop_water": {"name": "Mop Water", "effect_as": "", "complication": "reactive_shivers",
		"color": Color(0.55, 0.60, 0.50)},
	"cold_coffee": {"name": "Cold Coffee", "effect_as": "", "complication": "rebound_hiccups",
		"color": Color(0.35, 0.25, 0.18)},
}

static func substance_name(id: String) -> String:
	return String(SUBSTANCES.get(id, {}).get("name", id))

static func substance_effect(id: String) -> String:
	return String(SUBSTANCES.get(id, {}).get("effect_as", ""))

## Some substances do nothing therapeutic but reliably cause something. Saline
## Plus is inert; recovered dread is not.
static func substance_complication(id: String) -> String:
	return String(SUBSTANCES.get(id, {}).get("complication", ""))

static func spec(id: String) -> Dictionary:
	return SPECS.get(id, {})

static func display_name(id: String) -> String:
	return String(SPECS.get(id, {}).get("name", id))

# ---------------------------------------------------------------- construction
static func spawn(id: String) -> Prop:
	var s: Dictionary = SPECS.get(id, {})
	if s.is_empty():
		Log.w("unknown item '%s'" % id, "Items")
		return Build.simple_prop(id, id, Vector3(0.2, 0.2, 0.2), Color.MAGENTA)
	var size: Vector3 = s.get("size", Vector3(0.2, 0.2, 0.2))
	var color: Color = s.get("color", Color.WHITE)
	var parts := _shape_parts(String(s.get("shape", "box")), size, color)
	var p := Build.make_prop(id, String(s.get("name", id)), size, float(s.get("mass", 1.0)),
		parts, String(s.get("script", "res://scripts/items/prop.gd")))
	p.blurb = String(s.get("blurb", ""))
	p.fragile = bool(s.get("fragile", false))
	p.contents = String(s.get("contents", ""))
	p.label = String(s.get("label", ""))
	p.incriminating_tag = String(s.get("incriminating_tag", ""))
	p.incriminating_weight = float(s.get("incriminating_weight", 0.0))
	return p

## Distinct silhouettes matter more than detail — you need to recognise the
## mallet from across a ward while a nurse is walking toward you.
static func _shape_parts(shape: String, size: Vector3, color: Color) -> Array:
	var m := Build.mat(color)
	var metal := Build.mat(Build.METAL, 0.35, 0.8)
	var dark := Build.mat(color.darkened(0.4))
	match shape:
		"mallet":
			return [
				{"mesh": Build.cyl_mesh(0.022, 0.42), "mat": dark, "rot": Vector3(PI / 2, 0, 0)},
				{"mesh": Build.cyl_mesh(0.055, 0.13), "mat": m, "pos": Vector3(0, 0, -0.21), "rot": Vector3(0, 0, PI / 2)},
			]
		"syringe":
			return [
				{"mesh": Build.cyl_mesh(0.022, 0.19), "mat": m, "rot": Vector3(PI / 2, 0, 0)},
				{"mesh": Build.cyl_mesh(0.004, 0.08), "mat": metal, "pos": Vector3(0, 0, -0.13), "rot": Vector3(PI / 2, 0, 0)},
				{"mesh": Build.box_mesh(Vector3(0.05, 0.012, 0.012)), "mat": dark, "pos": Vector3(0, 0, 0.095)},
			]
		"bag":
			return [
				{"mesh": Build.box_mesh(Vector3(size.x, size.y, 0.06)), "mat": Build.mat(color, 0.3)},
				{"mesh": Build.cyl_mesh(0.012, 0.1), "mat": Build.mat(Build.PLASTIC), "pos": Vector3(0, -size.y * 0.5 - 0.04, 0)},
			]
		"duster":
			return [
				{"mesh": Build.cyl_mesh(0.035, 0.24), "mat": m, "rot": Vector3(PI / 2, 0, 0)},
				{"mesh": Build.cyl_mesh(0.06, 0.1, 12), "mat": Build.mat(color.lightened(0.25), 0.3, 0.0, color * 0.5), "pos": Vector3(0, 0, -0.17), "rot": Vector3(PI / 2, 0, 0)},
				{"mesh": Build.box_mesh(Vector3(0.05, 0.02, 0.06)), "mat": dark, "pos": Vector3(0, 0.04, 0.06)},
			]
		"wrench":
			return [
				{"mesh": Build.box_mesh(Vector3(0.035, 0.035, 0.44)), "mat": metal},
				{"mesh": Build.box_mesh(Vector3(0.12, 0.05, 0.09)), "mat": metal, "pos": Vector3(0, 0, -0.24)},
				{"mesh": Build.box_mesh(Vector3(0.05, 0.05, 0.14)), "mat": Build.mat(Color(0.8, 0.2, 0.2)), "pos": Vector3(0, 0, 0.19)},
			]
		"clipboard":
			return [
				{"mesh": Build.box_mesh(Vector3(size.x, 0.015, size.z)), "mat": Build.mat(Color(0.45, 0.35, 0.25))},
				{"mesh": Build.box_mesh(Vector3(size.x * 0.9, 0.008, size.z * 0.85)), "mat": Build.mat(Build.PAPER), "pos": Vector3(0, 0.014, 0.01)},
				{"mesh": Build.box_mesh(Vector3(size.x * 0.5, 0.02, 0.05)), "mat": metal, "pos": Vector3(0, 0.024, -size.z * 0.42)},
			]
		"paper":
			return [{"mesh": Build.box_mesh(Vector3(size.x, 0.006, size.z)), "mat": m}]
		"bowl":
			return [
				{"mesh": Build.cyl_mesh(size.x * 0.5, size.y, 14), "mat": m},
				{"mesh": Build.cyl_mesh(size.x * 0.38, size.y * 0.6, 14), "mat": Build.mat(color.darkened(0.25)), "pos": Vector3(0, 0.03, 0)},
			]
		"mop":
			return [
				{"mesh": Build.cyl_mesh(0.022, 1.25), "mat": m, "rot": Vector3(PI / 2, 0, 0)},
				{"mesh": Build.box_mesh(Vector3(0.22, 0.1, 0.16)), "mat": Build.mat(Color(0.75, 0.72, 0.6)), "pos": Vector3(0, 0, 0.6)},
			]
		"bucket":
			return [
				{"mesh": Build.cyl_mesh(0.2, 0.34, 14), "mat": m},
				{"mesh": Build.cyl_mesh(0.17, 0.06, 14), "mat": Build.mat(Color(0.5, 0.55, 0.5)), "pos": Vector3(0, 0.1, 0)},
				{"mesh": Build.cyl_mesh(0.05, 0.04, 8), "mat": dark, "pos": Vector3(0.14, -0.17, 0.14)},
				{"mesh": Build.cyl_mesh(0.05, 0.04, 8), "mat": dark, "pos": Vector3(-0.14, -0.17, -0.14)},
			]
		"sign":
			return [
				{"mesh": Build.box_mesh(Vector3(0.28, 0.5, 0.02)), "mat": m, "pos": Vector3(0, 0, 0.06), "rot": Vector3(0.2, 0, 0)},
				{"mesh": Build.box_mesh(Vector3(0.28, 0.5, 0.02)), "mat": m, "pos": Vector3(0, 0, -0.06), "rot": Vector3(-0.2, 0, 0)},
			]
		"cup":
			return [
				{"mesh": Build.cyl_mesh(0.045, 0.13, 12), "mat": Build.mat(Build.PLASTIC)},
				{"mesh": Build.cyl_mesh(0.04, 0.02, 12), "mat": m, "pos": Vector3(0, 0.055, 0)},
			]
		"flowers":
			return [
				{"mesh": Build.cyl_mesh(0.07, 0.16, 10), "mat": Build.mat(Color(0.6, 0.75, 0.8)), "pos": Vector3(0, -0.1, 0)},
				{"mesh": Build.sphere_mesh(0.1), "mat": m, "pos": Vector3(0, 0.08, 0)},
				{"mesh": Build.sphere_mesh(0.06), "mat": Build.mat(Color(0.9, 0.8, 0.35)), "pos": Vector3(0.07, 0.13, 0.03)},
			]
		"lamp":
			return [
				{"mesh": Build.cyl_mesh(0.09, 0.05, 10), "mat": Build.mat(Color(0.3, 0.3, 0.34)), "pos": Vector3(0, -0.19, 0)},
				{"mesh": Build.cyl_mesh(0.012, 0.28), "mat": metal},
				{"mesh": Build.cyl_mesh(0.1, 0.12, 10), "mat": Build.mat(color, 0.4, 0.0, color * 0.7), "pos": Vector3(0, 0.16, 0)},
			]
		"canister":
			return [
				{"mesh": Build.cyl_mesh(0.12, 0.4, 14), "mat": m},
				{"mesh": Build.cyl_mesh(0.05, 0.07, 10), "mat": metal, "pos": Vector3(0, 0.23, 0)},
				{"mesh": Build.box_mesh(Vector3(0.16, 0.09, 0.005)), "mat": Build.mat(Build.PAPER), "pos": Vector3(0, 0.02, 0.121)},
			]
		"wheelchair":
			return [
				{"mesh": Build.box_mesh(Vector3(0.44, 0.06, 0.42)), "mat": m, "pos": Vector3(0, 0.05, 0)},
				{"mesh": Build.box_mesh(Vector3(0.44, 0.5, 0.06)), "mat": m, "pos": Vector3(0, 0.3, -0.2)},
				{"mesh": Build.box_mesh(Vector3(0.06, 0.24, 0.36)), "mat": m, "pos": Vector3(-0.22, 0.18, 0.02)},
				{"mesh": Build.box_mesh(Vector3(0.06, 0.24, 0.36)), "mat": m, "pos": Vector3(0.22, 0.18, 0.02)},
				{"mesh": Build.cyl_mesh(0.28, 0.05, 16), "mat": metal, "pos": Vector3(-0.28, -0.22, -0.04), "rot": Vector3(0, 0, PI / 2)},
				{"mesh": Build.cyl_mesh(0.28, 0.05, 16), "mat": metal, "pos": Vector3(0.28, -0.22, -0.04), "rot": Vector3(0, 0, PI / 2)},
				{"mesh": Build.cyl_mesh(0.09, 0.04, 10), "mat": dark, "pos": Vector3(-0.2, -0.41, 0.3), "rot": Vector3(0, 0, PI / 2)},
				{"mesh": Build.cyl_mesh(0.09, 0.04, 10), "mat": dark, "pos": Vector3(0.2, -0.41, 0.3), "rot": Vector3(0, 0, PI / 2)},
				{"mesh": Build.box_mesh(Vector3(0.36, 0.05, 0.05)), "mat": metal, "pos": Vector3(0, 0.56, -0.22)},
			]
		"extinguisher":
			return [
				{"mesh": Build.cyl_mesh(0.085, 0.45, 12), "mat": m},
				{"mesh": Build.cyl_mesh(0.03, 0.08, 8), "mat": Build.mat(Color(0.15, 0.15, 0.15)), "pos": Vector3(0, 0.26, 0)},
				{"mesh": Build.box_mesh(Vector3(0.03, 0.03, 0.14)), "mat": Build.mat(Color(0.15, 0.15, 0.15)), "pos": Vector3(0, 0.28, 0.06)},
			]
		"cylinder":
			return [{"mesh": Build.cyl_mesh(size.x * 0.5, size.y, 12), "mat": m}]
		_:
			return [{"mesh": Build.box_mesh(size), "mat": m}]
