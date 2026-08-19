class_name Investigation
extends RefCounted
## One open inquiry into your conduct.
##
## Investigations can be COVERT. An undercover patient is just a patient as far
## as you know, and a records audit happens in an office you never visit. You
## are meant to spend some shifts quietly wondering whether this is one of them.

enum Stage { OPENED, GATHERING, INTERVIEWS, VERDICT, CLOSED }

var id := ""
var kind := "admin_audit"     ## admin_audit|insurance|inspector|undercover|attorney|police
var title := ""
var blurb := ""
var institution := "admin"    ## whose evidence pool decides the verdict
var stage: Stage = Stage.OPENED
var covert := false
var days_left := 2
var opened_on_day := 1
var focus_patient := ""
## Evidence the investigator has personally dug up, on top of what the
## institution already believed.
var gathered: Array[Evidence] = []
var interviewed: Array[String] = []
var threshold := 1.0          ## total weight needed for an adverse finding
var npc_id := ""              ## body in the world, if this one walks around
var outcome := ""

func is_open() -> bool:
	return stage != Stage.CLOSED

func gathered_weight(now: int) -> float:
	var total := 0.0
	for e in gathered:
		total += e.current_weight(now)
	return total

func to_dict() -> Dictionary:
	var g: Array = []
	for e in gathered:
		g.append(e.to_dict())
	return {
		"id": id, "kind": kind, "title": title, "blurb": blurb,
		"inst": institution, "stage": int(stage), "covert": covert,
		"days": days_left, "opened": opened_on_day, "focus": focus_patient,
		"gathered": g, "interviewed": interviewed, "thr": threshold,
		"npc": npc_id, "outcome": outcome,
	}

static func from_dict(d: Dictionary) -> Investigation:
	var i := Investigation.new()
	i.id = d.get("id", "")
	i.kind = d.get("kind", "admin_audit")
	i.title = d.get("title", "")
	i.blurb = d.get("blurb", "")
	i.institution = d.get("inst", "admin")
	i.stage = int(d.get("stage", 0)) as Stage
	i.covert = bool(d.get("covert", false))
	i.days_left = int(d.get("days", 2))
	i.opened_on_day = int(d.get("opened", 1))
	i.focus_patient = d.get("focus", "")
	for e in d.get("gathered", []):
		i.gathered.append(Evidence.from_dict(e))
	var iv: Array = d.get("interviewed", [])
	for x in iv:
		i.interviewed.append(String(x))
	i.threshold = float(d.get("thr", 1.0))
	i.npc_id = d.get("npc", "")
	i.outcome = d.get("outcome", "")
	return i
