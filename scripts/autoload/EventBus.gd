extends Node
## Central signal hub. Systems talk through here so nothing needs a hard reference
## to anything else — which is what lets hospital layout, NPCs, conditions,
## dialogue, items and random events be expanded without touching core code.
##
## NOTE: signal parameters are intentionally UNTYPED. Typing them as Patient /
## WorldEvent / Evidence creates a cyclic dependency (those classes emit through
## EventBus, EventBus resolves those classes) which deadlocks GDScript's script
## loader. The comment after each signal documents the real type instead.

# ---------------------------------------------------------------- world facts
## The single most important signal in the game. ANY observable happening emits
## one of these; perception turns it into Evidence for whoever could see it.
signal world_event(evt)              ## WorldEvent

## Emitted after perception has resolved, once per witness.
signal evidence_recorded(witness, ev) ## Node, Evidence

# ---------------------------------------------------------------- shift / time
signal shift_started(day: int)
signal shift_ended(day: int)
signal clock_tick(minutes_of_day: int)     ## in-game minute changed
signal hour_tick(hour: int)
signal day_advanced(day: int)
signal phase_changed(phase: int)           ## GameState.Phase

# ---------------------------------------------------------------- patients
signal patient_admitted(p)
signal patient_discharged(p, reason: String)
signal patient_state_changed(p)
signal complication_added(p, comp)
signal complication_resolved(p, comp)
signal treatment_applied(p, treatment_id: String, quality: float)

# ---------------------------------------------------------------- suspicion
signal suspicion_changed(who: String, value: float)
signal heat_changed(value: float)
signal rumor_spread(from_id: String, to_id: String, ev)
signal complaint_filed(about: String, by_id: String, severity: float)

# ---------------------------------------------------------------- investigation
signal investigation_opened(inv)
signal investigation_stage(inv, stage: int)
signal investigation_closed(inv, outcome: String)
signal sanction_applied(level: int, reason: String)

# ---------------------------------------------------------------- economy
signal money_changed(personal: int, hospital: int)
signal transaction(label: String, amount: int, is_hospital: bool)
signal bill_due(label: String, amount: int)

# ---------------------------------------------------------------- reputation
signal reputation_changed(track: String, value: float)

# ---------------------------------------------------------------- interaction
signal interact_prompt(text: String, sub: String)
signal interact_prompt_cleared()
signal item_picked_up(item: Node)
signal item_dropped(item: Node)
signal item_broke(item: Node)

# ---------------------------------------------------------------- ui / feedback
signal toast(text: String, kind: String)   ## kind: info|good|bad|money|suspicion
signal subtitle(speaker: String, text: String, seconds: float)
signal dialogue_started(npc)
signal dialogue_ended(npc)
signal codex_unlocked(entry_id: String)
signal objective_changed(text: String)

# ---------------------------------------------------------------- meta
signal random_event_fired(id: String, title: String, body: String)
signal game_over(ending_id: String)
signal game_loaded()
signal upgrade_purchased(id: String)
