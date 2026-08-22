class_name SuspicionSystem
extends Node
## Routes world events to whoever could perceive them, handles corroboration
## between witnesses, spreads rumours across the social graph, and converts
## personal suspicion into institutional Heat.
##
## This is the only place that knows about ALL minds, which is what makes
## corroboration possible: two people seeing the same thing must know about each
## other, or "make sure there's only one witness" would not be a strategy.

## Injuries a normal ward acquires per patient per shift. Not zero: people do
## fall over in hospitals, which is exactly why "an unwitnessed fall" is a story
## worth telling.
##
## Tuned against a FIVE BED ward, which is a much smaller denominator than a
## real hospital's. At a stricter baseline the second injury in a fortnight was
## already a statistical outlier, and no amount of care or paperwork could get
## a career past it — the statistic stopped being something to manage and became
## a countdown.
const BASELINE_INJURY_RATE := 0.06
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
	GameState.minute_passed.connect(_on_clock_tick)
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
		# Visitors go home, investigators finish their round, patients are
		# discharged — and every one of them frees its own body. A freed body
		# left in this dictionary poisons EVERY pass over it (see _body), so the
		# registry has to hear about it the moment the body leaves.
		var on_exit := _on_body_exiting.bind(mind.id)
		if not body.tree_exiting.is_connected(on_exit):
			body.tree_exiting.connect(on_exit)

func _on_body_exiting(id: String) -> void:
	# The MIND stays. Somebody who saw you switch the labels and then went home
	# still saw you switch the labels, and can still file a complaint about it.
	_bodies.erase(id)

func unregister(id: String) -> void:
	minds.erase(id)
	_bodies.erase(id)

## Read a body out of the registry. Deliberately untyped, and every read of
## `_bodies` must go through it.
##
## Assigning a freed object to a `var b: NPCBody` local does not merely produce
## null — it raises "Trying to assign invalid previously freed instance" and
## ABORTS THE FUNCTION, so the `is_instance_valid` guard on the next line never
## runs. One departed visitor left in the dictionary was enough to abort
## _on_world_event before it reached the nurse standing in front of you, which
## silently switched off witnessing for the rest of the shift: the entire
## stealth game stopped working and nothing failed loudly enough to notice.
func _body(id):
	var b = _bodies.get(id, null)
	if b == null or not is_instance_valid(b):
		_bodies.erase(id)
		return null
	# Somebody who is not rostered on is not in the building. They keep every
	# memory they already have; they simply cannot acquire new ones tonight.
	if not b.on_duty:
		return null
	return b

func mind_of(id: String) -> Mind:
	return minds.get(id, null)

func body_of(id: String) -> NPCBody:
	return _body(id)

func all_minds() -> Array[Mind]:
	var out: Array[Mind] = []
	for k in minds:
		out.append(minds[k])
	return out

# ------------------------------------------------------------------ witnessing
## Hearing only, no evidence. Anybody in earshot is distracted by it and gets a
## chance to go and look; nobody writes anything down, because nothing about a
## clatter says who caused it.
func _broadcast_noise(e: WorldEvent) -> void:
	if e.hear_radius <= 0.0:
		return
	for id in _bodies.keys():
		var body = _body(id)
		if body == null or body.perception == null:
			continue
		if not body.perception.can_hear(e.pos, e.hear_radius):
			continue
		body.perception.distract(0.55)
		if body.has_method("on_heard_noise"):
			body.call("on_heard_noise", e)

func _on_world_event(evt) -> void:
	var e: WorldEvent = evt
	# A noise nobody can be blamed for still MOVES people — and moving people is
	# the entire reason props are throwable.
	#
	# This early return dropped every event that was not the player's own doing
	# before it reached a single perception, which quietly deleted the whole
	# distraction layer of the game. Prop._emit_noise emits with no actor, on
	# purpose, with a comment saying "what it does is move NPCs, which is far
	# more useful" — and it moved nobody. Nor did the emergency admission that
	# is supposed to drag every member of staff to the far end of the building,
	# nor the random events that clatter. Four systems, three of them working,
	# and the chain never run end to end by any test until now.
	if e.actor != "player":
		_broadcast_noise(e)
		return

	# Private rooms genuinely reduce how much a witness can make out through a
	# closed door and a curtain.
	# Private rooms were an upgrade that halved who could see you. There are no
	# upgrades now; the only thing that changes who can see you is where you
	# stand and whether the door is shut.
	var witness_scale := 1.0

	# Pass one: who perceived it, and how well.
	var witnesses: Array = []
	for id in _bodies.keys():
		var body = _body(id)
		if body == null or body.perception == null:
			continue
		var res: Dictionary = body.perception.evaluate(e)
		if res.is_empty():
			continue
		witnesses.append({"id": id, "res": res})


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
		EventBus.evidence_recorded.emit(_body(id), stored)
		_react(id, mind, stored)

	EventBus.suspicion_changed.emit(ids[0], suspicion_of(ids[0]))

func _react(id: String, mind: Mind, ev: Evidence) -> void:
	var body = _body(id)
	if body == null:
		return
	# A NOTICE beat, below the tier ladder.
	#
	# The tiers need roughly 0.28 of accumulated evidence before anybody says a
	# word, and a one-notch machine deviation is worth 0.05 — so for the first
	# several shifts you could be watched committing the entire premise of the
	# game and the world would not move. Being clocked has to be perceptible the
	# first time it happens, or the stealth layer is invisible exactly when the
	# player is trying to learn it. Throttled per mind so it stays a glance
	# rather than a chorus.
	if ev.base_weight >= 0.1 and GameState.career_minutes - mind.last_noticed_at >= 20:
		mind.last_noticed_at = GameState.career_minutes
		var p = get_tree().get_first_node_in_group("player")
		if p != null:
			body.look_toward(p.global_position)
		if RNG.chance("notice_bark", 0.55):
			body.say(String(RNG.pick("notice_bark_line", [
				"...sorry, what was that?",
				"Everything alright in here?",
				"Hm.",
				"Doctor?",
				"Was that meant to happen?",
			])), 2.6)
		AudioMgr.play_at_var("tick", body.global_position, -20.0)

	# Anything they saw with their own eyes and thought worth keeping, they write
	# down where you can see them do it. Deliberately gated on WITNESSED: a thing
	# somebody was told in a corridor is not something they stop and minute.
	if ev.source == Evidence.Source.WITNESSED and ev.base_weight >= 0.18 \
			and body.has_method("make_a_note"):
		body.make_a_note()

	var tier := mind.tier(GameState.career_minutes, GameState.active_covers)
	if tier <= mind.reacted_tier or tier < 1:
		return
	mind.reacted_tier = tier
	var line := witness_line(tier)
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
		var body = _body(id)
		if speaker == null or body == null:
			continue
		if not RNG.chance("gossip", speaker.talkativeness * 0.5):
			continue
		var worst := speaker.strongest(GameState.career_minutes)
		if worst == null or worst.current_weight(GameState.career_minutes) < 0.12:
			continue
		for other_id in ids:
			if other_id == id:
				continue
			var listener_body = _body(other_id)
			if listener_body == null:
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
			# Make it a scene rather than a line of dialogue with nobody in it.
			#
			# Gossip is how a thing one person half-saw becomes a thing four
			# people are certain of, and it was completely invisible: one NPC
			# said a line into the air and a number moved inside another one.
			# Now they turn to each other, and then the listener looks straight
			# at the player — which is the entire content of the moment and needs
			# no words at all.
			body.look_toward(listener_body.global_position)
			listener_body.look_toward(body.global_position)
			body.say(gossip_line(), 3.0)
			var p = get_tree().get_first_node_in_group("player")
			if p != null and listener_body.perception != null \
					and listener_body.perception.can_see(p.global_position):
				listener_body.look_toward(p.global_position)
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

## What one of them says to another when they think you cannot hear it. The
## player learns that a belief has SPREAD by overhearing it, which is the reason
## the nurses' station is a place you can stand near rather than a menu.
const GOSSIP_LINES := [
	"...no, I know. I'm just saying it's the third one this week.",
	"...she asked me to look at it and I looked at it. That's all I'll say.",
	"...well, somebody wrote it. It didn't write itself.",
]

static func gossip_line() -> String:
	return String(RNG.pick("gossip_line", GOSSIP_LINES))

## THE ONLY WAY THE PLAYER IS EVER TOLD THAT SOMEBODY IS UNEASY.
##
## There is no suspicion meter, no standing word in the corner and no personality
## label on the tablet. What there is, is a person who says something slightly
## different from what they said this morning. Whether that means anything is the
## player's problem, which is the entire point of removing the number.
const WITNESS_LINES := {
	1: [
		"Sorry — were you looking for something?",
		"Oh. I didn't see you come in.",
		"Everything all right, doctor?",
	],
	2: [
		"That's the second time you've been in there.",
		"I'll just make a note of the time, if that's all right.",
		"You're writing that up now? At this hour?",
	],
	3: [
		"I read the notes. I'd like to talk about the notes.",
		"I've asked Sister to have a look at that chart.",
		"No, I heard you. I'm asking what you meant.",
	],
}

static func witness_line(tier: int) -> String:
	var pool: Array = WITNESS_LINES.get(clampi(tier, 1, 3), [])
	return String(RNG.pick("witness_line", pool)) if not pool.is_empty() else ""

func file_complaint(from_id: String, severity: float) -> void:
	var m: Mind = minds.get(from_id, null)
	var who: String = m.display_name if m else from_id

	# A reporter in the lobby does not make the ward any more watchful. What it
	# changes is where a complaint ENDS UP: on a press day the same grumble from
	# the same relative leaves the building, and the medical board reads it.
	# The event used to set a flag that picked one tannoy line and nothing else,
	# so "Local Press" was a day you had no reason to play differently. It is
	# now the day you either keep your head down or accept that everything costs
	# roughly three times as much.
	var press := bool(GameState.flag("press_present", false))
	EventBus.complaint_filed.emit("player", from_id, severity)
	if press:
		GameState.adjust_rep("gov_scrutiny", severity * 0.10)
		EventBus.toast.emit(
			"%s complained. The reporter in the lobby wrote it all down." % who, "bad")
	else:
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
		complication_rate: float = -1.0, injury_rate: float = -1.0) -> void:
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

	# Injuries per patient-shift. Deliberately measured against how many people
	# are ON the ward rather than how many left it: the complication rate goes
	# blind on a ward that never discharges anybody, and "fill every bed with
	# people you hurt and discharge none of them" would otherwise be the way to
	# switch the statistics off entirely.
	if injury_rate >= 0.0 and injury_rate > BASELINE_INJURY_RATE * 2.0:
		var over := injury_rate / maxf(BASELINE_INJURY_RATE, 0.0001)
		var w := clampf((over - 1.9) * 0.11, 0.04, 0.85)
		_file_statistic("injury_rate_outlier", w,
			"ward-acquired injuries running %.1fx the expected rate" % over)
		EventBus.toast.emit(
			"Somebody has run the numbers on ward-acquired injuries.", "suspicion")

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
## Who can see the player right now.
##
## Cached for a tenth of a second. This fires one physics raycast per registered
## body and the HUD asked for it EVERY FRAME to update a text panel — fifteen
## raycasts at 60Hz to redraw the same three names. A tenth of a second is
## below the point at which anybody notices the panel is late, and it is the
## single largest saving in the frame.
## Counted in PHYSICS FRAMES, not seconds. A wall-clock cache is a different
## amount of staleness depending on how fast the machine happens to be running,
## which makes a --fixed-fps harness stop being deterministic — it cost two
## intermittent live-run failures before the cause was obvious. Six frames is a
## tenth of a second at 60Hz and is exactly six frames everywhere.
const WATCHERS_CACHE_FRAMES := 6
var _watchers_cache: Array[NPCBody] = []
var _watchers_at := -1

func watchers() -> Array[NPCBody]:
	var now := int(Engine.get_physics_frames())
	if _watchers_at >= 0 and now - _watchers_at < WATCHERS_CACHE_FRAMES:
		# Somebody in the cached list may have been freed since it was built.
		var live: Array[NPCBody] = []
		for w in _watchers_cache:
			if is_instance_valid(w):
				live.append(w)
		_watchers_cache = live
		return _watchers_cache
	var out: Array[NPCBody] = []
	for id in _bodies.keys():
		var b = _body(id)
		if b and b.is_inside_tree() and b.perception and b.perception.sees_player():
			out.append(b)
	_watchers_cache = out
	_watchers_at = now
	return out

func is_observed() -> bool:
	return not watchers().is_empty()

func refresh_tells(player_pos: Vector3) -> void:
	for id in _bodies.keys():
		var b = _body(id)
		if b:
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
