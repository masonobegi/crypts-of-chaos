class_name ShiftSystem
extends Node
## The day loop: morning briefing → shift → chart review → statement → upgrades
## → next day. Owns the pacing of every other system.

signal briefing_ready(data: Dictionary)
signal review_ready(data: Dictionary)
signal statement_ready(data: Dictionary)

## Fraction of a day that passes per in-game minute during the shift.
const DAY_PER_MINUTE := 1.0 / float(GameState.MINUTES_PER_DAY)

var patient_system: PatientSystem = null
var economy: EconomySystem = null
var investigations: InvestigationSystem = null
var events: RandomEventSystem = null
var suspicion: SuspicionSystem = null
var records: RecordsSystem = null

var shift_start_snapshot := {}
var _pending_briefing := {}

func _ready() -> void:
	add_to_group("shift_system")
	patient_system = get_tree().get_first_node_in_group("patient_system")
	economy = get_tree().get_first_node_in_group("economy")
	investigations = get_tree().get_first_node_in_group("investigation_system")
	events = get_tree().get_first_node_in_group("random_events")
	suspicion = get_tree().get_first_node_in_group("suspicion_system")
	records = get_tree().get_first_node_in_group("records_system")
	EventBus.clock_tick.connect(_on_clock_tick)
	EventBus.hour_tick.connect(_maybe_emergency_admission)

# ================================================================ morning
## Everything that happens before you clock in.
func begin_day() -> Dictionary:
	GameState.set_phase(GameState.Phase.PRE_SHIFT)
	GameState.minute_of_day = GameState.SHIFT_START_HOUR * 60

	var debt_result := economy.settle_debts()
	var pressure := economy.debt_pressure_lines(debt_result["missed"])
	if int(GameState.flag("missed_rent_days", 0)) >= 4:
		GameState.set_flag("evicted", true)

	var fired := events.roll_daily()
	# Yesterday's warning has to actually mean something, or the notice is just
	# a scary-sounding no-op.
	if GameState.flag("inspection_tomorrow", false):
		GameState.set_flag("inspection_tomorrow", false)
		investigations.open("inspector", 0)
	_run_service_contract()
	_run_second_opinions()
	investigations.daily_check()
	investigations.daily_tick()

	var arrivals := _admit_morning_patients()

	_pending_briefing = {
		"day": GameState.day,
		"events": fired,
		"arrivals": arrivals,
		"debts_paid": debt_result["paid"],
		"debts_missed": debt_result["missed"],
		"pressure": pressure,
		"personal": GameState.personal_money,
		"hospital": GameState.hospital_money,
		"open_investigations": investigations.active_titles(),
		"sanction": GameState.SANCTIONS[GameState.sanction_level],
		"census": patient_system.active_count(),
		"projected_revenue": patient_system.total_daily_revenue(),
	}
	briefing_ready.emit(_pending_briefing)
	return _pending_briefing

## Equipment service contract: machines get serviced, which fixes miscalibration
## — and a technician who finds a machine badly out of calibration writes that
## down. The upgrade that protects your equipment also audits it.
func _run_service_contract() -> void:
	if not GameState.has_upgrade("maintenance_contract"):
		return
	for f in get_tree().get_nodes_in_group("fixture"):
		if not (f is TreatmentMachine):
			continue
		var m: TreatmentMachine = f
		if not m.is_miscalibrated():
			continue
		var was := m.calibration
		m.calibration = 1.0
		if was < 0.65:
			suspicion.report_to_institution("admin", "machine_miscalibrated", 0.3,
				"%s found significantly out of calibration during service" % m.fixture_name,
				"", ["equipment"])
			EventBus.toast.emit("%s was serviced. It needed it." % m.fixture_name, "suspicion")
		else:
			EventBus.toast.emit("%s serviced." % m.fixture_name, "info")

## Second opinion policy: a colleague signs off every extended stay. Great for
## the hospital's standing, and it means another doctor reads all of your
## extensions — with a chart audit attached.
func _run_second_opinions() -> void:
	if not GameState.has_upgrade("second_opinion_policy"):
		return
	var reviewer: DoctorNPC = null
	for d in get_tree().get_nodes_in_group("staff"):
		if d is DoctorNPC:
			reviewer = d
			break
	if reviewer == null:
		return
	var extended: Array[Patient] = []
	for p in patient_system.active():
		if p.days_admitted > p.expected_stay_days + 0.5:
			extended.append(p)
	if extended.is_empty():
		return
	reviewer.review_charts(extended)

func _admit_morning_patients() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var free := patient_system.free_wards().size()
	if free <= 0:
		return out
	# Volume scales with reputation — a good ward is a busy ward.
	var base := 1 + int(round(GameState.rep("hospital") * 2.0))
	var count := clampi(RNG.randi_range_s("arrivals", base, base + 2), 1, free)
	for i in count:
		var p := patient_system.generate()
		if patient_system.admit(p):
			out.append({
				"name": p.display_name,
				"condition": p.condition_name(),
				"stay": p.expected_stay_days,
				"insurance": DB.insurance_name(p.insurance),
				"revenue": p.daily_revenue(),
				"room": p.room,
				"archetype": DB.archetype_name(p.archetype),
			})
	return out

# ================================================================ shift
func clock_in() -> void:
	shift_start_snapshot = {
		"heat": GameState.heat,
		"complaints": GameState.stats.complaints,
		"witnessed": GameState.stats.witnessed_acts,
		"personal": GameState.personal_money,
		"complications": GameState.stats.complications_caused,
		"discharged": GameState.stats.patients_discharged,
	}
	GameState.set_phase(GameState.Phase.SHIFT)
	GameState.stats.shifts_worked += 1
	EventBus.shift_started.emit(GameState.day)
	EventBus.toast.emit("Shift started — %s" % GameState.time_string(), "info")
	EventBus.objective_changed.emit("Get through the shift.")
	AudioMgr.play("ding", -10.0)

## Emergency admissions arrive mid-shift with no warning. That is the entire
## mechanic: a bed you were using fills up, a patient appears in a corridor you
## were about to do something in, and everyone on the floor turns to look.
func _maybe_emergency_admission(hour: int) -> void:
	if not GameState.unlocked_departments.has("emergency"):
		return
	if hour < GameState.SHIFT_START_HOUR + 1 or GameState.shift_over():
		return
	# A full ward no longer turns emergencies away: once Intake is open they
	# land on a trolley in it, which is exactly the sort of thing a hospital
	# does and exactly the sort of thing that gets written about.
	if patient_system.free_wards().is_empty() and patient_system.free_trolleys() == 0:
		return
	if not RNG.chance("emergency_arrival", 0.22):
		return
	var p := patient_system.generate(_random_emergency_condition())
	if not patient_system.admit(p):
		return
	AudioMgr.play("alarm", -8.0)
	EventBus.toast.emit("EMERGENCY: %s — %s" % [p.display_name, p.condition_name()], "bad")
	# It happens in Intake, at the far west end of the floor, and it is loud
	# enough that everybody hears it. That is the hidden second half of buying
	# Emergency: every arrival drags the staff to the opposite end of the
	# building from the wards. The department pays twice — once in day rate, and
	# once in the quiet minute it buys you in Room 105.
	var h = get_tree().get_first_node_in_group("hospital")
	var where: Vector3 = h.point_in("intake", "emergency_spot") if h != null else Vector3.ZERO
	WorldEvent.new("emergency_admission", "").at(where, "intake") \
		.heard(0.0, 60.0).tag("noise").tag("chaos") \
		.says("emergency admission").emit()

func _random_emergency_condition() -> String:
	var pool: Array = []
	for id in DB.CONDITIONS:
		if String(DB.CONDITIONS[id].get("dept", "ward")) == "emergency":
			pool.append(String(id))
	return String(RNG.pick("emergency_cond", pool)) if not pool.is_empty() else ""

func _on_clock_tick(_minute: int) -> void:
	if GameState.phase != GameState.Phase.SHIFT:
		return
	patient_system.tick(DAY_PER_MINUTE)
	_auto_discharge_ready()
	if GameState.shift_over():
		end_shift()

## Patients who have fully recovered and whose paperwork is done leave on their
## own. You have to actively NOT finish their paperwork to keep them.
func _auto_discharge_ready() -> void:
	for p in patient_system.active():
		if not p.ready_for_discharge():
			continue
		if p.days_admitted < p.expected_stay_days:
			continue
		# A patient who is well, is past their date, and has noticed, discharges
		# themselves. Being slow is not a free way to hold someone forever.
		if p.mind and p.overdue_days > 1.5 and RNG.chance("self_discharge", 0.02):
			EventBus.toast.emit("%s has discharged themselves." % p.display_name, "bad")
			GameState.adjust_rep("patient_sat", -0.05)
			patient_system.discharge(p, "self_discharge")

# ================================================================ chart review
func end_shift() -> void:
	GameState.set_phase(GameState.Phase.CHART_REVIEW)
	EventBus.shift_ended.emit(GameState.day)

	# Colleagues read your charts on their way out.
	for d in get_tree().get_nodes_in_group("staff"):
		if d is DoctorNPC:
			d.review_charts(patient_system.active())

	_settle_imaging_requests()
	_run_ward_clerk()
	var findings := records.pending_findings()
	var data := {
		"day": GameState.day,
		"findings": findings,
		"exposure": records.total_exposure(),
		"undocumented": _undocumented_complications(),
		"patients": _patient_summaries(),
	}
	review_ready.emit(data)
	EventBus.objective_changed.emit("Finish your paperwork before you leave.")

## A colleague who asked for a scan this morning notices at going-home time that
## it never happened. There is no way to explain this in the record, because
## nothing about it is IN the record — which is exactly why it lands on the one
## person who asked rather than on the paperwork.
func _settle_imaging_requests() -> void:
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus == null:
		return
	for p in patient_system.active():
		if not p.imaging_requested():
			continue
		if p.imaging_requested_day >= GameState.day:
			# Asked today, still time tomorrow. Only an ignored request counts.
			continue
		var asker = sus.mind_of(p.imaging_requested_by)
		p.clear_imaging_request()
		if asker == null:
			continue
		var ev := Evidence.new()
		ev.kind = "declined_imaging"
		ev.about_actor = "player"
		ev.patient_id = p.id
		ev.source = Evidence.Source.INFERRED
		ev.time = GameState.career_minutes
		ev.base_weight = 0.34
		ev.certainty = 0.8
		ev.summary = "Asked for imaging on %s. It was not done." % p.display_name
		asker.add_evidence(ev)
		GameState.adjust_rep("insurer_trust", -0.02)
		EventBus.toast.emit("%s never got their scan. Somebody noticed." % p.display_name,
			"suspicion")

## Ward clerk: chases up your undocumented complications so they stop being
## record gaps. She files them as "idiopathic", which is plausible for most
## things — but she also notices how often she has to do it, and mentions it.
func _run_ward_clerk() -> void:
	if GameState.has_upgrade("records_consultant"):
		_run_records_consultant()
		return
	if not GameState.has_upgrade("admin_assistant"):
		return
	var filed := 0
	for p in patient_system.active():
		for c in p.active_complications():
			if c.documented_cause != "":
				continue
			if not c.plausible_causes.has("idiopathic"):
				continue
			c.documented_cause = "idiopathic"
			c.documented_at = GameState.career_minutes
			filed += 1
	if filed == 0:
		return
	EventBus.toast.emit("The ward clerk tidied up %d unfiled complication(s)." % filed, "info")
	if filed >= 3:
		suspicion.report_to_institution("admin", "clerk_pattern", 0.18 * float(filed),
			"ward clerk filed %d complications with no stated cause this shift" % filed,
			"", ["records", "statistics"])

## The consultant does the job properly: each complication gets a cause the
## chart actually accepts, not a blanket "idiopathic". She is worth the money —
## and she keeps her own notes, so a heavy shift still shows up somewhere.
func _run_records_consultant() -> void:
	var filed := 0
	for p in patient_system.active():
		for c in p.active_complications():
			if c.documented_cause != "" or c.plausible_causes.is_empty():
				continue
			c.documented_cause = String(RNG.pick("consultant_cause",
				Array(c.plausible_causes)))
			c.documented_at = GameState.career_minutes
			filed += 1
	if filed == 0:
		return
	EventBus.toast.emit("The records consultant closed %d gap(s)." % filed, "good")
	if filed >= 4:
		suspicion.report_to_institution("insurer", "consultant_volume", 0.12 * float(filed),
			"records consultant closed %d complication gaps in a single shift" % filed,
			"", ["records", "statistics"])

func _undocumented_complications() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in patient_system.active():
		for c in p.active_complications():
			if c.documented_cause == "":
				out.append({
					"patient_id": p.id, "patient": p.display_name,
					"complication": c.display_name, "id": c.id,
				})
	return out

func _patient_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in patient_system.active():
		out.append({
			"id": p.id, "name": p.display_name, "condition": p.condition_name(),
			"days": p.days_admitted, "expected": p.expected_stay_days,
			"state": p.apparent_state(), "revenue": p.daily_revenue(),
			"overdue": p.is_overdue(),
			"complications": p.active_complications().size(),
			"suspicion": p.mind.suspicion_pct(GameState.career_minutes, GameState.active_covers) if p.mind else 0,
		})
	return out

# ================================================================ statement
func clock_out() -> Dictionary:
	GameState.set_phase(GameState.Phase.POST_SHIFT)
	var statement := economy.close_shift()

	# The insurer's analytics team notices what nobody in the building did.
	# Rolling window rather than one shift, so a single bad day is survivable and
	# a sustained pattern is not.
	_record_shift_statistics()
	suspicion.run_statistical_review(patient_system.average_overstay(),
		patient_system.active_count(), rolling_complication_rate())

	if GameState.flag("perk_fast_cooling", false):
		GameState.add_heat(-0.03, "cooperating witness")
	var clean := _was_clean_shift()
	investigations.consider_de_escalation(clean)
	if not clean:
		GameState.set_flag("clean_streak", 0)

	var report := {
		"day": GameState.day,
		"statement": statement,
		"headline": Endings.headline(GameState.stats),
		"heat": GameState.heat,
		"heat_delta": GameState.heat - float(shift_start_snapshot.get("heat", 0.0)),
		"sanction": GameState.SANCTIONS[GameState.sanction_level],
		"suspicions": suspicion.ranked_suspicions().slice(0, 6),
		"census": patient_system.active_count(),
		"overstay": patient_system.average_overstay(),
		"clean": clean,
		"reputation": GameState.reputation.duplicate(),
		"debt": GameState.total_debt(),
		"daily_debt": GameState.daily_debt_payment(),
	}
	statement_ready.emit(report)
	SaveSystem.save_game(SaveSystem.AUTOSAVE)
	return report

## Rolling record of complications caused and patients discharged, per shift.
##
## Stored as raw counts rather than a per-shift ratio on purpose: averaging
## ratios is the wrong statistic here. Complications and discharges do not land
## on the same shifts, so a ward genuinely running three times the normal rate
## averaged out to "slightly above baseline" and never got noticed. Summing the
## window and dividing once is what an analyst would actually compute.
var _complication_window: Array[Dictionary] = []

func _record_shift_statistics() -> void:
	var comps: int = int(GameState.stats.complications_caused) \
		- int(shift_start_snapshot.get("complications", 0))
	var discharged: int = int(GameState.stats.patients_discharged) \
		- int(shift_start_snapshot.get("discharged", 0))
	_complication_window.append({"comps": comps, "discharged": discharged})
	while _complication_window.size() > 6:
		_complication_window.remove_at(0)

## Complications per patient discharged, over the recent window.
func rolling_complication_rate() -> float:
	if _complication_window.size() < 3:
		return -1.0      # not enough data to draw a conclusion from
	var comps := 0.0
	var discharged := 0.0
	for row in _complication_window:
		comps += float(row["comps"])
		discharged += float(row["discharged"])
	if discharged < 2.0:
		return -1.0      # too small a sample to mean anything
	return comps / discharged

func _was_clean_shift() -> bool:
	if GameState.stats.complaints > int(shift_start_snapshot.get("complaints", 0)):
		return false
	if GameState.heat > float(shift_start_snapshot.get("heat", 0.0)) + 0.02:
		return false
	if GameState.stats.witnessed_acts > int(shift_start_snapshot.get("witnessed", 0)):
		return false
	return true

# ================================================================ rollover
func next_day() -> void:
	# The 16 hours you are not on the ward still pass, for everyone.
	patient_system.tick(float(GameState.MINUTES_PER_DAY - GameState.SHIFT_HOURS * 60) * DAY_PER_MINUTE)
	GameState.career_minutes += GameState.MINUTES_PER_DAY - GameState.SHIFT_HOURS * 60
	events.clear_day()
	GameState.day += 1
	EventBus.day_advanced.emit(GameState.day)
	if _check_run_over():
		return
	begin_day()

func _check_run_over() -> bool:
	if GameState.sanction_level >= 8:
		EventBus.game_over.emit(Endings.evaluate(GameState.stats))
		return true
	if GameState.flag("evicted", false):
		EventBus.game_over.emit("bankrupt")
		return true
	if GameState.day > 30:
		EventBus.game_over.emit(Endings.evaluate(GameState.stats))
		return true
	return false

func briefing() -> Dictionary:
	return _pending_briefing
