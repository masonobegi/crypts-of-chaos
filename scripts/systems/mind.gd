class_name Mind
extends RefCounted
## Everything a character believes about you. Patients, nurses, doctors, family,
## and the faceless institutions (Administration, the insurer, the medical board)
## all get one — which is why "Greg's wife" can be more dangerous than Greg.

var id: String = ""
var display_name: String = ""
var role: String = "patient"        ## patient|nurse|doctor|family|admin|insurer|inspector|police
var archetype: String = ""
var patient_id: String = ""         ## for family: who they're here for

var evidence: Array[Evidence] = []

## 0..1. High trust discounts new evidence; genuinely curing people buys it.
var trust: float = 0.5
## How good they are at noticing things at all (perception roll).
var observance: float = 0.5
## How much weight they put on what they notice.
var skepticism: float = 0.5
## How likely they are to tell someone else.
var talkativeness: float = 0.4
## How readily they escalate to a formal complaint instead of just grumbling.
var escalation: float = 0.4

## Who they talk to, and how much they're believed. id -> 0..1
var affinity: Dictionary = {}

## Cover stories the player has burned on this character (tag -> times used).
var burned_covers: Dictionary = {}

## Highest suspicion tier this mind has already reacted to, so a nurse doesn't
## re-confront you every frame.
var reacted_tier: int = 0
## Set while the player is actively being watched — drives the "tell" behaviours.
var watching: bool = false

func _init(p_id: String = "", p_name: String = "", p_role: String = "patient") -> void:
	id = p_id
	display_name = p_name
	role = p_role

# --------------------------------------------------------------- suspicion
## Derived, never stored. 0..1.
func suspicion(now: int, active_covers: Dictionary = {}) -> float:
	var total := 0.0
	for ev in evidence:
		var covered: bool = ev.cover_tag != "" and active_covers.has(ev.cover_tag)
		total += ev.current_weight(now, covered)
	total *= 0.55 + skepticism
	# Trust is a genuine buffer — this is why saint-mode stretches are worth it.
	total /= (1.0 + trust * 1.6)
	# Squash so suspicion approaches but never reaches 1 from evidence alone.
	return clampf(1.0 - exp(-total), 0.0, 1.0)

func suspicion_pct(now: int, active_covers: Dictionary = {}) -> int:
	return int(round(suspicion(now, active_covers) * 100.0))

## 0=calm 1=uneasy 2=suspicious 3=convinced 4=acting on it
func tier(now: int, active_covers: Dictionary = {}) -> int:
	var s := suspicion(now, active_covers)
	if s < 0.15: return 0
	if s < 0.35: return 1
	if s < 0.58: return 2
	if s < 0.80: return 3
	return 4

# --------------------------------------------------------------- evidence ops
func add_evidence(ev: Evidence) -> Evidence:
	# Merge duplicates rather than stacking — seeing the same thing twice should
	# raise certainty, not double-count it.
	for existing in evidence:
		if existing.kind == ev.kind and existing.patient_id == ev.patient_id \
				and absi(existing.time - ev.time) < 90:
			existing.certainty = clampf(existing.certainty + 0.18, 0.0, 1.0)
			existing.base_weight = maxf(existing.base_weight, ev.base_weight)
			if existing.neutralized and ev.source == Evidence.Source.WITNESSED:
				existing.neutralized = false   # seeing it again reopens the question
			return existing
	evidence.append(ev)
	return ev

func has_evidence_about(pid: String) -> bool:
	for ev in evidence:
		if ev.patient_id == pid and not ev.neutralized:
			return true
	return false

func evidence_about(pid: String) -> Array[Evidence]:
	var out: Array[Evidence] = []
	for ev in evidence:
		if ev.patient_id == pid:
			out.append(ev)
	return out

## The single most damning thing they hold — what they'll bring up in dialogue.
func strongest(now: int) -> Evidence:
	var best: Evidence = null
	var bw := 0.0
	for ev in evidence:
		if ev.neutralized:
			continue
		var w := ev.current_weight(now)
		if w > bw:
			bw = w
			best = ev
	return best

func prune(now: int) -> void:
	var kept: Array[Evidence] = []
	for ev in evidence:
		if not ev.is_stale(now):
			kept.append(ev)
	evidence = kept

func forget_all() -> void:
	evidence.clear()
	reacted_tier = 0

# --------------------------------------------------------------- trust
func adjust_trust(delta: float) -> void:
	trust = clampf(trust + delta, 0.0, 1.0)

func burn_cover(tag: String) -> void:
	burned_covers[tag] = int(burned_covers.get(tag, 0)) + 1

func cover_effectiveness(tag: String) -> float:
	## Excuses wear out. The third time you blame the paperwork, nobody buys it.
	var used := int(burned_covers.get(tag, 0))
	return maxf(0.0, 1.0 - float(used) * 0.34)

# --------------------------------------------------------------- serialization
func to_dict() -> Dictionary:
	var evs: Array = []
	for ev in evidence:
		evs.append(ev.to_dict())
	return {
		"id": id, "name": display_name, "role": role, "arch": archetype,
		"pid": patient_id, "ev": evs, "trust": trust, "obs": observance,
		"skep": skepticism, "talk": talkativeness, "esc": escalation,
		"aff": affinity, "burn": burned_covers, "rt": reacted_tier,
	}

static func from_dict(d: Dictionary) -> Mind:
	var m := Mind.new(d.get("id", ""), d.get("name", ""), d.get("role", "patient"))
	m.archetype = d.get("arch", "")
	m.patient_id = d.get("pid", "")
	for e in d.get("ev", []):
		m.evidence.append(Evidence.from_dict(e))
	m.trust = float(d.get("trust", 0.5))
	m.observance = float(d.get("obs", 0.5))
	m.skepticism = float(d.get("skep", 0.5))
	m.talkativeness = float(d.get("talk", 0.4))
	m.escalation = float(d.get("esc", 0.4))
	m.affinity = d.get("aff", {})
	m.burned_covers = d.get("burn", {})
	m.reacted_tier = int(d.get("rt", 0))
	return m
