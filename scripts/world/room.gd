class_name Room
extends Node3D
## A room's runtime state. Rooms are not scenery: temperature, light, noise and
## cleanliness feed directly into patient recovery, which is what makes
## "open the window and walk away" a viable strategy with a real paper trail.

const IDEAL_TEMP := 21.0

@export var key := ""
@export var display := "Room"
@export var kind := "ward"          ## ward|corridor|lobby|station|supply|office|treatment|bathroom|break
@export var rect := Rect2()

var temperature := 21.0
var lights_on := true
var window_open := false
var cleanliness := 1.0              ## 0 filthy .. 1 spotless
var noise := 0.0                    ## decays; spikes on prop impacts
var occupant_ids: Array[String] = []

## Set when the player has documented an environmental fault here. Filing a
## facilities ticket BEFORE the complication lands is the clean version of
## freezing someone for an extra day.
var facilities_ticket_filed := false
## Thermostat setting, if the ward has one. -1 means "leave it to the HVAC".
var target_override := -1.0

var _drift_accum := 0.0

func _process(delta: float) -> void:
	noise = maxf(0.0, noise - delta * 0.6)
	_drift_accum += delta
	if _drift_accum >= 1.0:
		_drift_accum = 0.0
		_drift_temperature(1.0)

func _drift_temperature(seconds: float) -> void:
	# An open window pulls hard toward outside; otherwise the HVAC creeps back
	# toward comfortable, slowly enough that you have time to leave the ward.
	var target := IDEAL_TEMP
	if target_override > 0.0:
		target = target_override
	if window_open:
		target = 8.0
	if not lights_on:
		target -= 1.0
	temperature = lerpf(temperature, target, 1.0 - exp(-0.035 * seconds))

## Multiplier applied to the recovery rate of every patient in this room.
func comfort() -> float:
	var m := 1.0
	var temp_error := absf(temperature - IDEAL_TEMP)
	m *= clampf(1.0 - temp_error * 0.035, 0.35, 1.05)
	if not lights_on:
		m *= 0.88
	m *= lerpf(0.8, 1.02, cleanliness)
	m *= clampf(1.0 - noise * 0.12, 0.7, 1.0)
	return clampf(m, 0.25, 1.1)

## What a person standing here would notice. Drives NPC comments and evidence.
func complaints() -> Array[String]:
	var out: Array[String] = []
	if temperature < 15.0:
		out.append("it is freezing in here")
	elif temperature > 27.0:
		out.append("it is boiling in here")
	if not lights_on:
		out.append("the lights are off")
	if window_open and temperature < 18.0:
		out.append("the window is wide open")
	if cleanliness < 0.45:
		out.append("this room is a state")
	return out

## True when the room is in a condition someone could reasonably blame on
## facilities rather than on you — provided you filed the ticket.
func has_plausible_fault() -> bool:
	return window_open or not lights_on or cleanliness < 0.5

func set_window(open: bool, by_player: bool) -> void:
	if window_open == open:
		return
	window_open = open
	AudioMgr.play_at("door", global_position, -14.0, 0.7)
	if by_player:
		# Opening a window is barely suspicious on its own. It becomes evidence
		# only once a patient in this room develops a cold-related complication.
		WorldEvent.new("window_opened" if open else "window_closed", "player") \
			.at(global_position, key).seen(0.18 if open else 0.02) \
			.tag("environment").cover("facilities") \
			.says("%s the window in %s" % ["opened" if open else "closed", display]).emit()

func set_lights(on: bool, by_player: bool) -> void:
	if lights_on == on:
		return
	lights_on = on
	# Hide the whole fitting, not just the OmniLight3D inside it.
	#
	# Build.ceiling_light() puts an UNSHADED emissive panel next to the lamp, so
	# recursing for the light alone left every fitting in the room glowing at
	# full brightness with the lights "off". Turning a ward's lights out — one of
	# the few purely environmental levers in the game — looked like nothing had
	# happened at all.
	for c in get_children():
		if c is OmniLight3D:
			(c as OmniLight3D).visible = on
		elif c.has_meta("is_light"):
			(c as Node3D).visible = on
	AudioMgr.play_at("beep_low", global_position, -18.0)
	if by_player:
		WorldEvent.new("lights_off" if not on else "lights_on", "player") \
			.at(global_position, key).seen(0.15 if not on else 0.0) \
			.tag("environment").cover("facilities") \
			.says("turned the lights %s in %s" % ["off" if not on else "on", display]).emit()

func add_noise(amount: float) -> void:
	noise = clampf(noise + amount, 0.0, 3.0)

func soil(amount: float) -> void:
	cleanliness = clampf(cleanliness - amount, 0.0, 1.0)

func clean(amount: float) -> void:
	cleanliness = clampf(cleanliness + amount, 0.0, 1.0)

func contains(pos: Vector3) -> bool:
	return rect.has_point(Vector2(pos.x, pos.z))

func center() -> Vector3:
	return Vector3(rect.get_center().x, 0.0, rect.get_center().y)

func to_dict() -> Dictionary:
	return {
		"temp": temperature, "lights": lights_on, "win": window_open,
		"clean": cleanliness, "ticket": facilities_ticket_filed,
		"target": target_override,
	}

func from_dict(d: Dictionary) -> void:
	temperature = float(d.get("temp", 21.0))
	lights_on = bool(d.get("lights", true))
	window_open = bool(d.get("win", false))
	cleanliness = float(d.get("clean", 1.0))
	facilities_ticket_filed = bool(d.get("ticket", false))
	target_override = float(d.get("target", -1.0))
