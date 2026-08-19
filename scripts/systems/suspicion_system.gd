class_name SuspicionSystem
extends Node
## Routes world events to whoever could perceive them, handles corroboration
## between witnesses, spreads rumours across the social graph, and converts
## personal suspicion into institutional Heat.
##
## This is the only place that knows about ALL minds, which is what makes
## corroboration possible: two people seeing the same thing must know about each
## other, or "make sure there's only one witness" would not be a strategy.

const GOSSIP_INTERVAL_MIN := 25       ## in-game minutes between gossip passes
const GOSSIP_RANGE := 5.0

var minds: Dictionary = {}            ## id -> Mind
var _bodies: Dictionary = {}          ## id -> NPCBody (bodiless minds are absent)
var _last_gossip := 0
## Incidents that have already produced a formal complaint, so one act cannot
## be escalated by the same person twice.
var _escalated: Dictionary = {}

func _ready() -> void:
	add_to_group("suspicion_system")
	EventBus.world_event.connect(_on_world_event)
	EventBus.clock_tick.connect(_on_clock_tick)
	_ensure_institutions()

# ------------------------------------------------------------------ registry
## The institutions have minds too. They never witness anything directly — they
## only ever learn things from reports, records and audits, which is exactly why
## paperwork is more dangerous than being seen.
func _ensure_institutions() -> void:
	_add_institution("admin", "Hospital Administration", "rule_follower", 0.55, 0.5)
	_add_institution("insurer", "Meridian Mutual", "investigator", 0.75, 0.35)
	_add_institution("board", "Medical Board", "investigator", 0.9, 0.5)

func _add_institution(id: String, disp: String, arch: String, skep: float, trust: float) -> void:
	if minds.has(id):
		return
	var m := DB.make_mind(id, disp, "institution", arch)
	m.skepticism = skep
	m.trust = trust
	m.observance = 0.0        # institutions cannot see
	m.talkativeness = 0.1
	minds[id] = m

func register(mind: Mind, body: NPCBody = null) -> void:
	minds[mind.id] = mind
	if body:
		_bodies[mind.id] = body
		body.mind = mind

func unregister(id: String) -> void:
	minds.erase(id)
	_bodies.erase(id)

func mind_of(id: String) -> Mind:
	return minds.get(id, null)

func body_of(id: String) -> NPCBody:
	return _bodies.get(id, null)

func all_minds() -> Array[Mind]:
	var out: Array[Mind] = []
	for k in minds:
		out.append(minds[k])
	return out

# ------------------------------------------------------------------ witnessing
func _on_world_event(evt) -> void:
	var e: WorldEvent = evt
	if e.actor != "player":
		return

	# Private rooms genuinely reduce how much a witness can make out through a
	# closed door and a curtain.
	var witness_scale := Upgrades.witness_scale()

	# Pass one: who perceived it, and how well.
	var witnesses: Array = []
	for id in _bodies:
		var body: NPCBody = _bodies[id]
		if body == null or not is_instance_valid(body) or body.perception == null:
			continue
		var res: Dictionary = body.perception.evaluate(e)
		if res.is_empty():
			continue
		witnesses.append({"id": id, "res": res})

	_record_on_camera(e)

	if witnesses.is_empty():
		return

	# Pass two: record it, with every other witness listed as a corroborator.
	# Corroboration is superlinear, so being seen by two people is far worse
	# than twice as bad — isolating witnesses is a real tactic.
	var ids: Array[String] = []
	for w in witnesses:
		ids.append(String(w["id"]))

	for w in witnesses:
		var id: String = String(w["id"])
		var res: Dictionary = w["res"]
		var mind: Mind = minds.get(id, null)
		if mind == null:
			continue
		var ev := Evidence.from_world_event(e, res["source"],
			float(res["weight"]) * witness_scale, float(res["certainty"]))
		for other in ids:
			if other != id:
				ev.corroborators.append(other)
		var stored := mind.add_evidence(ev)
		EventBus.evidence_recorded.emit(_bodies.get(id, null), stored)
		if e.visual_weight > 0.25:
			GameState.stats.witnessed_acts += 1
		_react(id, mind, stored)

	EventBus.suspicion_changed.emit(ids[0], suspicion_of(ids[0]))

## Cameras do not have personalities, do not forget, and cannot be talked to.
## Buying them raises hospital reputation AND creates a permanent record of
## anything you do in a covered room — the cleanest example of an upgrade that
## makes you richer and more visible at the same time.
func _record_on_camera(e: WorldEvent) -> void:
	if e.visual_weight < 0.2:
		return
	if not Upgrades.camera_rooms().has(e.room):
		return
	var inst: Mind = minds.get("admin", null)
	if inst == null:
		return
	var ev := Evidence.from_world_event(e, Evidence.Source.RECORD,
		e.visual_weight * 0.85, 1.0)
	ev.summary = "on camera: %s" % (e.summary if e.summary != "" else e.kind.replace("_", " "))
	ev.tags.append("camera")
	inst.add_evidence(ev)

## Immediate on-the-spot reaction: a line of dialogue and a hard stare.
func _react(id: String, mind: Mind, ev: Evidence) -> void:
	var body: NPCBody = _bodies.get(id, null)
	if body == null or not is_instance_valid(body):
		return
	var tier := mind.tier(GameState.career_minutes, GameState.active_covers)
	if tier <= mind.reacted_tier or tier < 1:
		return
	mind.reacted_tier = tier
	var line := Dialogue.witness_line(mind, ev, tier)
	if line != "":
		body.say(line, 3.4)
	if tier >= 2:
		AudioMgr.play("suspicion", -14.0)
	if tier >= 3:
		_consider_complaint(id, mind)

# ------------------------------------------------------------------ gossip
func _on_clock_tick(_minute: int) -> void:
	if GameState.career_minutes - _last_gossip < GOSSIP_INTERVAL_MIN:
		return
	_last_gossip = GameState.career_minutes
	_gossip_pass()
	_decay_pass()

## Anyone chatty who is standing near someone else may pass on the worst thing
## they know. Retellings degrade, so a rumour three hops out is weak — but it
## has reached three more people, and corroboration does the rest.
func _gossip_pass() -> void:
	var ids: Array = _bodies.keys()
	for id in ids:
		var speaker: Mind = minds.get(id, null)
		var body: NPCBody = _bodies.get(id, null)
		if speaker == null or body == null or not is_instance_valid(body):
			continue
		if not RNG.chance("gossip", speaker.talkativeness * 0.5):
			continue
		var worst := speaker.strongest(GameState.career_minutes)
		if worst == null or worst.current_weight(GameState.career_minutes) < 0.12:
			continue
		for other_id in ids:
			if other_id == id:
				continue
			var listener_body: NPCBody = _bodies.get(other_id, null)
			if listener_body == null or not is_instance_valid(listener_body):
				continue
			if listener_body.global_position.distance_to(body.global_position) > GOSSIP_RANGE:
				continue
			var listener: Mind = minds.get(other_id, null)
			if listener == null:
				continue
			# People tell the colleagues they actually get on with. Which two
			# nurses happen to be friendly decides how fast something travels.
			var closeness: float = float(speaker.affinity.get(other_id, 0.5))
			if not RNG.chance("gossip_affinity", closeness):
				continue
			# Don't re-tell someone something they already saw with their own eyes.
			var already := false
			for ev in listener.evidence:
				if ev.kind == worst.kind and ev.patient_id == worst.patient_id:
					already = true
			if already:
				continue
			var retold := worst.retold()
			retold.corroborators.append(id)
			listener.add_evidence(retold)
			EventBus.rumor_spread.emit(id, other_id, retold)
			body.say(Dialogue.gossip_line(speaker, worst), 3.0)
			break

func _decay_pass() -> void:
	for id in minds:
		(minds[id] as Mind).prune(GameState.career_minutes)

# ------------------------------------------------------------------ escalation
## A convinced, escalation-prone character files something. That is the moment
## a private belief becomes an institutional fact.
func _consider_complaint(id: String, mind: Mind) -> void:
	var key := "%s_%d" % [id, mind.reacted_tier]
	if _escalated.has(key):
		return
	if not RNG.chance("complaint", mind.escalation * 0.55):
		return
	_escalated[key] = true
	var sev := mind.suspicion(GameState.career_minutes, GameState.active_covers)
	file_complaint(id, sev)

func file_complaint(from_id: String, severity: float) -> void:
	var m: Mind = minds.get(from_id, null)
	var who: String = m.display_name if m else from_id
	GameState.stats.complaints += 1
	GameState.add_heat(severity * 0.16, "complaint by %s" % who)
	GameState.adjust_rep("patient_sat", -0.03)
	EventBus.complaint_filed.emit("player", from_id, severity)
	EventBus.toast.emit("%s has filed a formal complaint." % who, "bad")

	# The complaint itself becomes a RECORD in the institutional minds — and
	# records barely decay, which is why one bad afternoon can follow you for
	# a whole career.
	var target := "admin"
	if m and m.role == "patient":
		target = "insurer"
	var inst: Mind = minds.get(target, null)
	if inst:
		var ev := Evidence.new()
		ev.kind = "complaint_filed"
		ev.about_actor = "player"
		ev.source = Evidence.Source.RECORD
		ev.time = GameState.career_minutes
		ev.base_weight = clampf(severity * 0.7, 0.1, 0.9)
		ev.certainty = 0.9
		ev.summary = "complaint from %s" % who
		ev.tags = PackedStringArray(["complaint"])
		inst.add_evidence(ev)

## Institutions learn from paperwork, not eyes. Called by the records/audit code.
func report_to_institution(inst_id: String, kind: String, weight: float, summary: String,
		patient_id := "", tags: Array = []) -> void:
	var inst: Mind = minds.get(inst_id, null)
	if inst == null:
		return
	var ev := Evidence.new()
	ev.kind = kind
	ev.about_actor = "player"
	ev.patient_id = patient_id
	ev.source = Evidence.Source.RECORD
	ev.time = GameState.career_minutes
	ev.base_weight = weight
	ev.certainty = 0.95
	ev.summary = summary
	for t in tags:
		ev.tags.append(String(t))
	inst.add_evidence(ev)

## Statistical inference — run at end of shift. Nobody saw anything, but your
## numbers are wrong and someone who reads numbers for a living noticed.
##
## Two independent signals, because they catch different play:
##  * length of stay catches stalling
##  * complication RATE catches the immaculately-documented player, whose every
##    complication is plausible and filed on time, but who produces three times
##    as many of them as anyone else on the floor. Perfect paperwork is not a
##    defence against being a statistical outlier — that is the whole point of
##    an analytics team, and it is what stops clean filing being a free win.
const BASELINE_COMPLICATION_RATE := 0.34   ## per discharged patient, ward average

func run_statistical_review(avg_overstay: float, sample: int,
		complication_rate: float = -1.0) -> void:
	if sample < 3:
		return
	if avg_overstay >= 0.6:
		var weight := clampf((avg_overstay - 0.5) * 0.35, 0.05, 0.75)
		_file_statistic("length_of_stay_outlier", weight,
			"average length of stay running %.1f days over projection" % avg_overstay)
		EventBus.toast.emit("Your average length of stay is drifting.", "suspicion")

	if complication_rate >= 0.0 and complication_rate > BASELINE_COMPLICATION_RATE * 1.6:
		var excess := complication_rate / BASELINE_COMPLICATION_RATE
		var weight := clampf((excess - 1.5) * 0.22, 0.04, 0.7)
		_file_statistic("complication_rate_outlier", weight,
			"complication rate running %.1fx the ward average" % excess)
		EventBus.toast.emit(
			"Your complication rate is well above the ward average.", "suspicion")

func _file_statistic(kind: String, weight: float, summary: String) -> void:
	for inst_id in ["admin", "insurer"]:
		var inst: Mind = minds.get(inst_id, null)
		if inst == null:
			continue
		var ev := Evidence.new()
		ev.kind = kind
		ev.about_actor = "player"
		ev.source = Evidence.Source.INFERRED
		ev.time = GameState.career_minutes
		ev.base_weight = weight
		ev.certainty = 0.8
		ev.summary = summary
		ev.tags = PackedStringArray(["statistics"])
		inst.add_evidence(ev)

# ------------------------------------------------------------------ queries
func suspicion_of(id: String) -> float:
	var m: Mind = minds.get(id, null)
	if m == null:
		return 0.0
	return m.suspicion(GameState.career_minutes, GameState.active_covers)

func suspicion_pct(id: String) -> int:
	return int(round(suspicion_of(id) * 100.0))

## Sorted list for the tablet UI. Only includes people you have actually met,
## because your character's estimate of a stranger is worthless.
func ranked_suspicions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in minds:
		var m: Mind = minds[id]
		var s := m.suspicion(GameState.career_minutes, GameState.active_covers)
		if s <= 0.005 and m.role != "institution":
			continue
		out.append({
			"id": id, "name": m.display_name, "role": m.role,
			"value": s, "pct": int(round(s * 100.0)),
			"tier": m.tier(GameState.career_minutes, GameState.active_covers),
		})
	out.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	return out

func highest_suspicion() -> float:
	var top := 0.0
	for id in minds:
		top = maxf(top, suspicion_of(id))
	return top

## Anyone currently able to see the player. Drives the HUD "eyes on you" tell.
func watchers() -> Array[NPCBody]:
	var out: Array[NPCBody] = []
	for id in _bodies:
		var b: NPCBody = _bodies[id]
		if b and is_instance_valid(b) and b.is_inside_tree() \
				and b.perception and b.perception.sees_player():
			out.append(b)
	return out

func is_observed() -> bool:
	return not watchers().is_empty()

func refresh_tells(player_pos: Vector3) -> void:
	for id in _bodies:
		var b: NPCBody = _bodies[id]
		if b and is_instance_valid(b):
			b.refresh_tell(player_pos)

# ------------------------------------------------------------------ save/load
func to_dict() -> Dictionary:
	var out := {}
	for id in minds:
		out[id] = (minds[id] as Mind).to_dict()
	return {"minds": out, "escalated": _escalated, "last_gossip": _last_gossip}

func from_dict(d: Dictionary) -> void:
	var stored: Dictionary = d.get("minds", {})
	for id in stored:
		var m := Mind.from_dict(stored[id])
		if minds.has(id):
			# Keep the live body binding; replace only the beliefs.
			var existing: Mind = minds[id]
			existing.evidence = m.evidence
			existing.trust = m.trust
			existing.burned_covers = m.burned_covers
			existing.reacted_tier = m.reacted_tier
		else:
			minds[id] = m
	_escalated = d.get("escalated", {})
	_last_gossip = int(d.get("last_gossip", 0))
