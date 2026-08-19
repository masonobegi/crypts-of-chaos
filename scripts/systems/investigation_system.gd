class_name InvestigationSystem
extends Node
## Opens, runs and resolves investigations, and applies the sanction ladder.
##
## Getting caught is never instant. It is a ladder with nine rungs, and every
## rung is a chance to behave impeccably for two shifts and climb back down —
## which produces much better play than a hard fail state.

const KINDS := {
	"admin_audit": {
		"title": "Internal Chart Review", "inst": "admin", "covert_chance": 0.35,
		"days": 2, "threshold": 1.1,
		"blurb": "Administration is pulling charts from your ward.",
	},
	"insurance": {
		"title": "Insurance Utilisation Review", "inst": "insurer", "covert_chance": 0.5,
		"days": 3, "threshold": 1.4,
		"blurb": "Meridian Mutual has flagged your length-of-stay figures.",
	},
	"inspector": {
		"title": "Health Inspection", "inst": "admin", "covert_chance": 0.0,
		"days": 1, "threshold": 0.9,
		"blurb": "An inspector is on the floor. Today.",
	},
	"undercover": {
		"title": "Undercover Patient", "inst": "insurer", "covert_chance": 1.0,
		"days": 4, "threshold": 1.0,
		"blurb": "Someone on your ward is not who they say they are.",
	},
	"attorney": {
		"title": "Malpractice Enquiry", "inst": "board", "covert_chance": 0.2,
		"days": 3, "threshold": 1.6,
		"blurb": "A solicitor has requested records for one of your patients.",
	},
	"serious_incident": {
		"title": "Serious Incident Review", "inst": "board", "covert_chance": 0.0,
		"days": 2, "threshold": 1.15,
		"blurb": "Somebody has counted the injuries on your ward.",
	},
	"police": {
		"title": "Police Enquiry", "inst": "board", "covert_chance": 0.1,
		"days": 4, "threshold": 2.2,
		"blurb": "This is no longer a hospital matter.",
	},
}

var open_investigations: Array[Investigation] = []
var closed_investigations: Array[Investigation] = []
var _next := 1
var suspicion: SuspicionSystem = null
var patient_system: PatientSystem = null

func _ready() -> void:
	add_to_group("investigation_system")
	suspicion = get_tree().get_first_node_in_group("suspicion_system")
	patient_system = get_tree().get_first_node_in_group("patient_system")

# ------------------------------------------------------------------ triggers
## Called once at the start of each day. Heat is the main driver, but a
## sufficiently annoyed insurer can open one on its own.
## How many people can be looking into you at once.
##
## A flat cap of two was the single biggest reason a butcher survived eighteen
## days at 93% heat with 528 witnessed acts: the queue was full, so nothing else
## could start, and each one had to finish before the next began. Being under a
## police investigation does not stop an insurer auditing you. It makes it more
## likely.
func concurrent_cap() -> int:
	return clampi(2 + int(GameState.sanction_level / 3), 2, 4)

func daily_check() -> void:
	if open_investigations.size() >= concurrent_cap():
		return
	var heat := GameState.heat
	var scrutiny := GameState.rep("gov_scrutiny")
	var chance := heat * 0.55 + scrutiny * 0.35
	# Insurers audit money, not morals: rich patients staying long is the signal.
	var insurer_sus: float = suspicion.suspicion_of("insurer") if suspicion else 0.0
	chance += insurer_sus * 0.3
	if GameState.sanction_level >= 3:
		chance += 0.15
	# The injury review is not a heat roll. Heat is a thing you can manage —
	# behave for two shifts and it comes down — and if ward-acquired injuries
	# only ever arrived through it, a patient enough player could run a ward
	# full of broken people indefinitely by being nice in between. This one
	# comes from the arithmetic, so the only way to stop it is to stop.
	# Deliberately NOT an early return. An incident review has to be pressure ON
	# TOP of whatever heat was already going to bring, not instead of it —
	# crowding out a malpractice enquiry by breaking more legs is exactly the
	# wrong incentive, and it is what happened the first time this was wired up.
	if _injury_review_due():
		open("serious_incident")
	if open_investigations.size() >= concurrent_cap():
		return
	if not RNG.chance("investigation_open", clampf(chance, 0.0, 0.85)):
		return
	open(_pick_kind(insurer_sus))
	# Trouble arrives in more than one envelope. One opening per day meant that
	# however loud a ward got, the rate at which the institution noticed it was
	# constant — a butcher and a careful operator drew the same volume of post,
	# just with different contents. Above two-thirds heat, a second one lands.
	if GameState.heat > 0.66 and open_investigations.size() < concurrent_cap() \
			and RNG.chance("investigation_second", (GameState.heat - 0.66) * 1.6):
		open(_pick_kind(insurer_sus))

## Ward-acquired injuries running well over the expected rate, with nobody
## already looking into it.
func _injury_review_due() -> bool:
	for inv in open_investigations:
		if inv.kind == "serious_incident":
			return false
	var shift = get_tree().get_first_node_in_group("shift_system")
	if shift == null:
		return false
	var rate: float = shift.rolling_injury_rate()
	if rate < 0.0:
		return false
	return rate > SuspicionSystem.BASELINE_INJURY_RATE * 4.0

func _pick_kind(insurer_sus: float) -> String:
	var weights := {
		"admin_audit": 1.0 + GameState.heat,
		"insurance": 0.5 + insurer_sus * 2.0,
		"inspector": 0.5,
		"undercover": 0.25 + insurer_sus,
		"attorney": maxf(0.0, GameState.sanction_level - 2) * 0.5,
		"police": maxf(0.0, GameState.sanction_level - 5) * 0.7,
	}
	return String(RNG.pick_weighted("investigation_kind", weights))

func open(kind: String, forced_covert := -1) -> Investigation:
	var spec: Dictionary = KINDS.get(kind, KINDS["admin_audit"])
	var inv := Investigation.new()
	inv.id = "inv%d" % _next
	_next += 1
	inv.kind = kind
	inv.title = String(spec["title"])
	inv.blurb = String(spec["blurb"])
	inv.institution = String(spec["inst"])
	inv.days_left = int(spec["days"])
	inv.threshold = float(spec["threshold"])
	inv.opened_on_day = GameState.day
	inv.covert = RNG.chance("covert", float(spec["covert_chance"])) if forced_covert < 0 \
		else bool(forced_covert)

	# Investigations focus on your worst-looking patient, because that is what
	# an actual reviewer would pull first. What "worst" means depends on who is
	# asking: an incident review is not reading length-of-stay figures, it is
	# reading the list of things that happened to somebody here.
	var worst: Patient = null
	var worst_score := -1.0
	for p in patient_system.active():
		var score := 0.0
		if kind == "serious_incident":
			score = float(p.acquired_injuries().size()) * 2.0
			score += float(p.undocumented_injuries().size())
		else:
			score = maxf(0.0, p.days_admitted - p.expected_stay_days)
			for c in p.complications:
				score += c.paper_suspicion()
		if score > worst_score:
			worst_score = score
			worst = p
	if worst:
		inv.focus_patient = worst.id

	open_investigations.append(inv)
	EventBus.investigation_opened.emit(inv)
	if not inv.covert:
		EventBus.toast.emit("%s — %s" % [inv.title, inv.blurb], "bad")
		AudioMgr.play("alarm", -12.0)
	else:
		Log.i("covert investigation opened: %s" % inv.kind, "Invest")
	if kind == "undercover":
		_plant_undercover(inv)
	elif not inv.covert:
		_send_investigator(inv)
	return inv

## An investigation you can SEE. The body walks to each chart, each nurse and
## each machine in turn, which means every one of those is something you can get
## to first — hide the chart, pull the nurse away, fix the calibration.
##
## Covert investigations deliberately get no body: you are meant to spend some
## shifts wondering whether this is one of them.
func _send_investigator(inv: Investigation) -> void:
	var hospital = get_tree().get_first_node_in_group("hospital")
	if hospital == null:
		return
	var npc := InvestigatorNPC.new()
	npc.npc_id = "inv_%s" % inv.id
	npc.archetype = "investigator"
	npc.set_colours(RNG.pick("inv_skin", [
		Color(0.95, 0.83, 0.72), Color(0.76, 0.60, 0.46), Color(0.44, 0.31, 0.22)]),
		Color(0.20, 0.22, 0.30), Color(0.15, 0.13, 0.12))
	var parent: Node = get_parent()
	if parent == null:
		parent = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(npc)
	# Away from the doors and from whoever is standing about, so nobody spawns
	# wedged against the player or a chair.
	var spot: Vector3 = hospital.point_in("lobby", "inv_spawn")
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		for i in 6:
			if spot.distance_to(player.global_position) > 3.0:
				break
			spot = hospital.point_in("lobby", "inv_spawn")
	npc.position = spot
	var mind := DB.make_mind(npc.npc_id, npc.display, "inspector", "investigator")
	mind.trust = 0.25
	if suspicion:
		suspicion.register(mind, npc)
	npc.begin(inv, inv.kind)
	inv.npc_id = npc.npc_id

## The undercover patient is a real patient with a real condition who happens to
## be extremely observant and reports everything they see. You will never be
## told which one they are.
func _plant_undercover(inv: Investigation) -> void:
	var candidates := patient_system.active()
	if candidates.is_empty():
		return
	var target: Patient = RNG.pick("undercover_target", candidates)
	target.archetype = "observant"
	if target.mind:
		target.mind.archetype = "observant"
		target.mind.observance = 0.98
		target.mind.skepticism = 0.9
		target.mind.trust = 0.3
		target.mind.talkativeness = 0.1     # they don't gossip; they report
	inv.focus_patient = target.id
	GameState.set_flag("undercover_" + target.id, true)

# ------------------------------------------------------------------ running
## Advance every open investigation by a day.
func daily_tick() -> void:
	for inv in open_investigations.duplicate():
		_advance(inv)

func _advance(inv: Investigation) -> void:
	inv.days_left -= 1
	# An investigation with a body on the floor gathers its evidence by walking
	# around and looking at things, not by fiat — skip the abstract passes so the
	# player's interference actually counts for something.
	var has_body := inv.npc_id != "" and _body_for(inv) != null
	match inv.stage:
		Investigation.Stage.OPENED:
			inv.stage = Investigation.Stage.GATHERING
			if not has_body:
				_gather_records(inv)
		Investigation.Stage.GATHERING:
			inv.stage = Investigation.Stage.INTERVIEWS
			if not has_body:
				_interview_staff(inv)
		Investigation.Stage.INTERVIEWS:
			inv.stage = Investigation.Stage.VERDICT
	EventBus.investigation_stage.emit(inv, int(inv.stage))
	if inv.days_left <= 0 or inv.stage == Investigation.Stage.VERDICT:
		_resolve(inv)

## Pull the charts and diff them against what actually happened. This is where
## phantom billing and impossible causes finally come due.
func _gather_records(inv: Investigation) -> void:
	for p in patient_system.active():
		if inv.focus_patient != "" and p.id != inv.focus_patient \
				and not RNG.chance("audit_spread", 0.4):
			continue
		for f in p.chart.audit(p.actual_treatments, p.complications):
			var ev := Evidence.new()
			ev.kind = String(f["kind"])
			ev.about_actor = "player"
			ev.patient_id = p.id
			ev.source = Evidence.Source.RECORD
			ev.time = GameState.career_minutes
			ev.base_weight = float(f["weight"])
			ev.certainty = 0.95
			ev.summary = String(f["text"])
			inv.gathered.append(ev)
	# Device logs are records too, and nobody ever remembers to check them.
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is TreatmentMachine:
			for entry in f.suspicious_log_entries():
				var ev := Evidence.new()
				ev.kind = "machine_log_deviation"
				ev.about_actor = "player"
				ev.patient_id = String(entry.get("patient", ""))
				ev.source = Evidence.Source.RECORD
				ev.time = GameState.career_minutes
				ev.base_weight = clampf(absf(float(entry["deviation"])) * 0.12, 0.1, 0.7)
				ev.certainty = 0.98
				ev.summary = "%s run at %d for %s (prescribed %d)" % [
					f.fixture_name, int(entry["dial"]), entry.get("patient_name", "a patient"),
					int(entry["prescribed"])]
				inv.gathered.append(ev)
			if f.log_cleared_count > 0:
				var ev2 := Evidence.new()
				ev2.kind = "machine_log_cleared"
				ev2.about_actor = "player"
				ev2.source = Evidence.Source.RECORD
				ev2.time = GameState.career_minutes
				ev2.base_weight = 0.5 * float(f.log_cleared_count)
				ev2.certainty = 1.0
				ev2.summary = "%s device log has been cleared %d time(s)" % [
					f.fixture_name, f.log_cleared_count]
				inv.gathered.append(ev2)
		elif f is Thermostat:
			for entry in f.suspicious_log_entries():
				var tev := Evidence.new()
				tev.kind = "thermostat_log"
				tev.about_actor = "player"
				tev.source = Evidence.Source.RECORD
				tev.time = GameState.career_minutes
				tev.base_weight = 0.3
				tev.certainty = 0.95
				tev.summary = "%s set to %d on day %d" % [
					f.fixture_name, int(entry["setting"]), int(entry["day"])]
				inv.gathered.append(tev)

## Ask the ward what they saw. Staff who like you keep their mouths shut.
func _interview_staff(inv: Investigation) -> void:
	if suspicion == null:
		return
	for m in suspicion.all_minds():
		if m.role == "institution" or inv.interviewed.has(m.id):
			continue
		inv.interviewed.append(m.id)
		var worst := m.strongest(GameState.career_minutes)
		if worst == null:
			continue
		# Loyalty is a real defence — a nurse who trusts you will simply not
		# mention it, which is what staff_trust is for.
		var will_talk := clampf(0.85 - m.trust * 0.7 + m.escalation * 0.3, 0.05, 0.95)
		will_talk *= 1.0 - GameState.rep("staff_trust") * 0.35
		will_talk *= 1.0 - Upgrades.staff_silence_bonus()
		if not RNG.chance("interview", will_talk):
			continue
		var copy := worst.retold()
		copy.source = Evidence.Source.WITNESSED   # a statement is first-hand
		copy.certainty = worst.certainty * 0.9
		copy.summary = "%s: %s" % [m.display_name, worst.label()]
		inv.gathered.append(copy)

# ------------------------------------------------------------------ verdict
func _resolve(inv: Investigation) -> void:
	var now := GameState.career_minutes
	var institutional: float = suspicion.suspicion_of(inv.institution) if suspicion else 0.0
	var total := inv.gathered_weight(now) + institutional * 1.2
	# A solicitor on retainer means findings need to be substantially stronger
	# before anything sticks.
	total /= Upgrades.investigation_threshold_scale()
	# Reputation is armour. A well-regarded doctor genuinely gets the benefit of
	# the doubt, which is the whole reason to have one.
	total *= clampf(1.25 - GameState.rep("doctor") * 0.5, 0.6, 1.4)

	inv.stage = Investigation.Stage.CLOSED
	open_investigations.erase(inv)
	closed_investigations.append(inv)
	var body := _body_for(inv)
	if body and is_instance_valid(body) and body.has_method("_leave"):
		body.call("_leave")

	if total < inv.threshold * 0.55:
		inv.outcome = "cleared"
		GameState.add_heat(-0.12, "investigation cleared")
		GameState.adjust_rep("doctor", 0.03)
		GameState.stats.investigations_survived += 1
		EventBus.toast.emit("%s closed. No findings." % inv.title, "good")
	elif total < inv.threshold:
		inv.outcome = "concerns"
		GameState.add_heat(0.04, "investigation concerns")
		GameState.stats.investigations_survived += 1
		EventBus.toast.emit("%s closed with concerns noted." % inv.title, "info")
		escalate(1, "%s: concerns noted" % inv.title)
	else:
		inv.outcome = "adverse"
		var steps := 1
		if total > inv.threshold * 1.8:
			steps = 2
		if total > inv.threshold * 3.0:
			steps = 3
		EventBus.toast.emit("%s: adverse findings." % inv.title, "bad")
		AudioMgr.play("error", -6.0)
		escalate(steps, "%s: adverse findings" % inv.title)
	EventBus.investigation_closed.emit(inv, inv.outcome)

# ------------------------------------------------------------------ sanctions
func escalate(steps: int, reason: String) -> void:
	if steps <= 0:
		return
	var before := GameState.sanction_level
	# The ladder gets much harder to climb past Probation. Losing a licence
	# should take a sustained pattern across many shifts, not one bad week —
	# the whole point of the ladder is that it gives you room to recover.
	if GameState.flag("perk_thick_skin", false) and before <= 1:
		steps = maxi(0, steps - 1)
		if steps <= 0:
			return
	if before >= 4:
		# Scaled by heat: a doctor who has cooled off gets room to recover, one
		# running at maximum institutional heat does not.
		steps = 1 if RNG.chance("late_escalation", 0.28 + GameState.heat * 0.6) else 0
		# The room to recover is for somebody who is recovering. Sitting at the
		# top of the heat scale for a fortnight is not a bad week, it is a
		# pattern, and the throttle that exists to be merciful was the main
		# reason a doctor with four hundred witnessed acts kept his licence for
		# eighteen days.
		if steps > 0 and GameState.heat > 0.85 \
				and RNG.chance("runaway_escalation", GameState.heat - 0.5):
			steps = 2
	elif before >= 2:
		steps = mini(steps, 2)
	if steps <= 0:
		return
	GameState.sanction_level = clampi(before + steps, 0, GameState.SANCTIONS.size() - 1)
	if GameState.sanction_level == before:
		return
	GameState.adjust_rep("gov_scrutiny", 0.07 * float(steps))
	GameState.adjust_rep("doctor", -0.05 * float(steps))
	EventBus.sanction_applied.emit(GameState.sanction_level, reason)
	EventBus.toast.emit("%s — %s" % [
		GameState.SANCTIONS[GameState.sanction_level], reason], "bad")
	_apply_sanction_effects()
	if GameState.sanction_level >= GameState.SANCTIONS.size() - 1:
		EventBus.game_over.emit("prison")
	elif GameState.sanction_level >= 8:
		EventBus.game_over.emit("license_revoked")

func _apply_sanction_effects() -> void:
	match GameState.sanction_level:
		2: GameState.bonus_rate = maxf(0.03, GameState.bonus_rate - 0.01)
		4: GameState.bonus_rate = maxf(0.02, GameState.bonus_rate - 0.02)   # probation
		5: GameState.add_hospital(-4500, "malpractice settlement")
		6: GameState.adjust_rep("hospital", -0.12)

## Behaving impeccably walks the ladder back down. Two clean shifts is the price.
func consider_de_escalation(clean_shift: bool) -> void:
	if not clean_shift or GameState.sanction_level <= 0:
		return
	var streak := int(GameState.flag("clean_streak", 0)) + 1
	GameState.set_flag("clean_streak", streak)
	if streak >= 2:
		GameState.set_flag("clean_streak", 0)
		GameState.sanction_level = maxi(0, GameState.sanction_level - 1)
		GameState.adjust_rep("gov_scrutiny", -0.05)
		EventBus.toast.emit("Standing improved: %s" % GameState.SANCTIONS[GameState.sanction_level], "good")

func _body_for(inv: Investigation) -> Node:
	for n in get_tree().get_nodes_in_group("investigator"):
		if n.npc_id == inv.npc_id:
			return n
	return null

func active_titles() -> Array[String]:
	var out: Array[String] = []
	for inv in open_investigations:
		if not inv.covert:
			out.append(inv.title)
	return out

## True if anything at all is currently looking at you — including covert ones.
## Never surfaced directly to the player; used to bias ambient tension.
func any_active() -> bool:
	return not open_investigations.is_empty()

func to_dict() -> Dictionary:
	var op: Array = []
	for i in open_investigations:
		op.append(i.to_dict())
	var cl: Array = []
	for i in closed_investigations:
		cl.append(i.to_dict())
	return {"open": op, "closed": cl, "next": _next}

func from_dict(d: Dictionary) -> void:
	open_investigations.clear()
	closed_investigations.clear()
	for x in d.get("open", []):
		open_investigations.append(Investigation.from_dict(x))
	for x in d.get("closed", []):
		closed_investigations.append(Investigation.from_dict(x))
	_next = int(d.get("next", 1))
