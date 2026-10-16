class_name LevelSequencer
extends RefCounted

## Orders evaluated levels into a campaign. Every gate_every-th level is a
## gate whose type cycles through gate_pattern (from first_gate_level on);
## the levels between gates follow the `rhythm` of tiers, so a breather
## always follows a gate. Inside each tier the target fail rate grows with
## the level number, and so does the preferred number of trucks.

const FALLBACKS := {
	"easy": ["medium"],
	"medium": ["easy", "hard"],
	"hard": ["medium", "very_hard"],
	"very_hard": ["hard"],
	"soft_gate": ["very_hard", "hard"],
	"slot_gate": ["soft_gate", "very_hard", "hard"],
}

var level_count := 100
var onboarding: Array = ["easy", "easy", "medium", "easy"]
var rhythm: Array = ["easy", "medium", "hard", "medium"]
var gate_every := 5
var gate_pattern: Array = ["soft_gate", "hard", "hard", "hard"]
var first_gate_level := 20
## Levels that teach the shuffle: unsolvable without it, a hint offers it.
var shuffle_tutorial_levels: Array = []
## Levels that teach one booster: winnable alone, a novice usually deadlocks,
## the hint gives the booster for free.
var booster_tutorial_levels: Array = [3]
## The first early_levels levels must take a novice at most early_max_attempts
## expected attempts without boosters (LevelEvaluator novice_attempts).
var early_levels := 10
var early_max_attempts := 3.5
## Which evaluation field measures attempts (early cap and regular targets).
var attempts_key := "ordinary_attempts"
## Regular tiers and soft gates are matched on attempts_key instead of the
## greedy fail rate; targets bands are then in attempts.
var measure_attempts := true
## From min_critical_from_level on, a level needs at least this share of
## decisions where some move is a proven trap (no trap-free levels).
var min_critical_share := 0.1
var min_critical_from_level := 3
var ramp_levels := 100
## Target band per type: [value at level 1, value at ramp_levels]. Regular
## tiers and soft gates use the base-slot fail rate; slot gates use the fail
## rate that remains after one rescue.
var targets := {
	"easy": [0.02, 0.15],
	"medium": [0.15, 0.30],
	"hard": [0.30, 0.50],
	"very_hard": [0.50, 0.70],
	"soft_gate": [0.55, 0.80],
	"slot_gate": [0.05, 0.35],
	"shuffle_tutorial": [0.0, 0.1],
	"booster_tutorial": [0.0, 0.1],
}
## Preferred truck count [min, max] at level 1 and at ramp_levels.
var vehicles_start: Array = [8, 11]
var vehicles_end: Array = [14, 20]
var vehicle_penalty := 0.02
var repeat_penalty := 0.05
## Interest (LevelEvaluator._interest) lowers the cost of a pick; levels below
## min_interest are never placed.
var interest_weight := 0.15
var min_interest := 0.25

func configure(settings: Dictionary) -> void:
	level_count = int(settings.get("level_count", level_count))
	onboarding = settings.get("onboarding", onboarding)
	rhythm = settings.get("rhythm", rhythm)
	gate_every = int(settings.get("gate_every", gate_every))
	gate_pattern = settings.get("gate_pattern", gate_pattern)
	first_gate_level = int(settings.get("first_gate_level", first_gate_level))
	shuffle_tutorial_levels = settings.get("shuffle_tutorial_levels", shuffle_tutorial_levels)
	booster_tutorial_levels = settings.get("booster_tutorial_levels", booster_tutorial_levels)
	early_levels = int(settings.get("early_levels", early_levels))
	early_max_attempts = float(settings.get("early_max_attempts", early_max_attempts))
	attempts_key = str(settings.get("attempts_key", attempts_key))
	measure_attempts = bool(settings.get("measure_attempts", measure_attempts))
	min_critical_share = float(settings.get("min_critical_share", min_critical_share))
	min_critical_from_level = int(settings.get("min_critical_from_level", min_critical_from_level))
	ramp_levels = int(settings.get("ramp_levels", ramp_levels))
	targets.merge(settings.get("targets", {}), true)
	vehicles_start = settings.get("vehicles_start", vehicles_start)
	vehicles_end = settings.get("vehicles_end", vehicles_end)
	vehicle_penalty = float(settings.get("vehicle_penalty", vehicle_penalty))
	repeat_penalty = float(settings.get("repeat_penalty", repeat_penalty))
	interest_weight = float(settings.get("interest_weight", interest_weight))
	min_interest = float(settings.get("min_interest", min_interest))

## Planned type of a 1-based level number.
func slot_type(number: int) -> String:
	for tutorial in booster_tutorial_levels:
		if int(tutorial) == number:
			return "booster_tutorial"
	for tutorial in shuffle_tutorial_levels:
		if int(tutorial) == number:
			return "shuffle_tutorial"
	if number <= onboarding.size():
		return onboarding[number - 1]
	if gate_every > 0 and number % gate_every == 0:
		if number < first_gate_level or gate_pattern.is_empty():
			return "hard"
		# The first gate on or after first_gate_level takes gate_pattern[0].
		var gate_index := (number - first_gate_level) / gate_every
		return gate_pattern[gate_index % gate_pattern.size()]
	var position := (number - 1) % maxi(1, gate_every)
	return rhythm[position % rhythm.size()]

## records: [{"index": int, "evaluation": Dictionary}]; every record is used
## at most once. Returns {"levels": [...], "summary": {...}}.
func build(records: Array) -> Dictionary:
	var used := {}
	var levels: Array = []
	var previous := {}
	for number in range(1, level_count + 1):
		var wanted := slot_type(number)
		var progress := _progress(number)
		var order: Array = [wanted]
		order.append_array(FALLBACKS.get(wanted, []))
		var pick := {}
		var actual := ""
		for type: String in order:
			pick = _best(records, used, type, progress, previous, number)
			if not pick.is_empty():
				actual = type
				break
		if pick.is_empty():
			levels.append({"level": number, "planned": wanted, "type": "missing"})
			continue
		used[pick.record.index] = true
		var evaluation: Dictionary = pick.record.evaluation
		previous = evaluation
		levels.append({
			"level": number,
			"planned": wanted,
			"type": actual,
			"fallback": actual != wanted,
			"record_index": pick.record.index,
			"seed": evaluation.seed,
			"target": snappedf(pick.target, 0.001),
			"measure": snappedf(pick.measure, 0.001),
			"fail_rate": snappedf(float(evaluation.fail_rate), 0.001),
			"post_rescue_fail": snappedf(float(evaluation.post_rescue_fail), 0.001),
			"expected_rescues": snappedf(float(evaluation.expected_rescues), 0.001),
			"speed_bonus_rate": snappedf(float(evaluation.speed_bonus_rate), 0.001),
			"clutch_rate": snappedf(float(evaluation.clutch_rate), 0.001),
			"min_slots": evaluation.min_slots,
			"vehicle_count": evaluation.vehicle_count,
			"color_count": evaluation.color_count,
			"queue_window": evaluation.queue_window,
			"same_color_overlaps": evaluation.get("same_color_overlaps", 0),
			"fail_by_slots": evaluation.get("fail_by_slots", {}),
			"slot_again": evaluation.get("slot_again", []),
			"swap_again": evaluation.get("swap_again", []),
			"crane_again": evaluation.get("crane_again", []),
			"shuffle_again": evaluation.get("shuffle_again", []),
			"shuffle_hopeless": snappedf(float(evaluation.get("shuffle_hopeless", 0.0)), 0.001),
			"shuffle_spread": snappedf(float(evaluation.get("shuffle_spread", 0.0)), 0.001),
			"shuffle_by_strength": evaluation.get("shuffle_by_strength", {}),
			"tutorial_post_win": snappedf(float(evaluation.get("tutorial_post_win", 0.0)), 0.001),
			"tutorial_mean_tries": snappedf(float(evaluation.get("tutorial_mean_tries", 0.0)), 0.01),
			"blocking_depth": evaluation.blocking_depth,
			"fail_by_skill": evaluation.get("fail_by_skill", {}),
			"near_miss": snappedf(float(evaluation.get("near_miss", 0.0)), 0.001),
			"interest": snappedf(float(evaluation.get("interest", 0.0)), 0.001),
			"trap_ratio": snappedf(float(evaluation.get("trap_ratio", 0.0)), 0.001),
			"critical_share": snappedf(float(evaluation.get("critical_share", 0.0)), 0.001),
			"novice_attempts": snappedf(float(evaluation.get("novice_attempts", 0.0)), 0.01),
			"ordinary_attempts": snappedf(float(evaluation.get("ordinary_attempts", 0.0)), 0.01),
			"strong_attempts": snappedf(float(evaluation.get("strong_attempts", 0.0)), 0.01),
			"onboarding_deadlock_rate": snappedf(float(evaluation.get("onboarding_deadlock_rate", 0.0)), 0.001),
			"onboarding_post_win": snappedf(float(evaluation.get("onboarding_post_win", 0.0)), 0.001),
		})
	return {"levels": levels, "summary": _summary(levels, records.size(), used.size())}

func _progress(number: int) -> float:
	return clampf(float(number - 1) / maxf(1.0, ramp_levels - 1.0), 0.0, 1.0)

func _matches(evaluation: Dictionary, type: String) -> bool:
	match type:
		"shuffle_tutorial":
			return evaluation.get("shuffle_tutorial_eligible", false)
		"booster_tutorial":
			return evaluation.category == "regular" and evaluation.get("booster_tutorial_eligible", false)
		"slot_gate":
			return evaluation.category == "slot_gate"
		"soft_gate":
			return evaluation.category == "regular" and evaluation.get("soft_gate_eligible", false)
		_:
			return evaluation.category == "regular" and evaluation.get("tier", "") == type

func _measure(evaluation: Dictionary, type: String) -> float:
	if type == "shuffle_tutorial":
		return 1.0 - float(evaluation.get("tutorial_post_win", 0.0))
	if type == "booster_tutorial":
		return 1.0 - float(evaluation.get("onboarding_post_win", 0.0))
	if measure_attempts and type != "slot_gate":
		return float(evaluation.get(attempts_key, 1.0))
	return float(evaluation.post_rescue_fail) if type == "slot_gate" else float(evaluation.fail_rate)

func _best(records: Array, used: Dictionary, type: String, progress: float,
		previous: Dictionary, number: int = 0) -> Dictionary:
	var band: Array = targets.get(type, [0.0, 1.0])
	var target := lerpf(float(band[0]), float(band[1]), progress)
	var low := roundi(lerpf(float(vehicles_start[0]), float(vehicles_end[0]), progress))
	var high := roundi(lerpf(float(vehicles_start[1]), float(vehicles_end[1]), progress))
	var best := {}
	var best_cost := INF
	for record: Dictionary in records:
		if used.has(record.index):
			continue
		var evaluation: Dictionary = record.evaluation
		if not _matches(evaluation, type) or float(evaluation.get("interest", 1.0)) < min_interest:
			continue
		# Early levels keep progress continuous even for a novice (tutorials excepted).
		if number <= early_levels and type != "booster_tutorial" \
				and float(evaluation.get(attempts_key, 99.0)) > early_max_attempts:
			continue
		if number >= min_critical_from_level \
				and float(evaluation.get("critical_share", 1.0)) < min_critical_share:
			continue
		var measure := _measure(evaluation, type)
		var count: int = evaluation.vehicle_count
		var cost := absf(measure - target) - interest_weight * float(evaluation.get("interest", 0.0))
		cost += vehicle_penalty * (maxi(0, low - count) + maxi(0, count - high))
		if not previous.is_empty():
			if count == int(previous.vehicle_count):
				cost += repeat_penalty
			if evaluation.color_count == previous.color_count and evaluation.queue_window == previous.queue_window:
				cost += repeat_penalty
		if cost < best_cost:
			best_cost = cost
			best = {"record": record, "target": target, "measure": measure}
	return best

func _summary(levels: Array, pool_size: int, used_count: int) -> Dictionary:
	var by_type := {}
	var fallbacks: Array = []
	var missing: Array = []
	var rescues_per_ten: Array = []
	for entry: Dictionary in levels:
		by_type[entry.type] = int(by_type.get(entry.type, 0)) + 1
		if entry.type == "missing":
			missing.append(entry.level)
			continue
		if entry.fallback:
			fallbacks.append("%d:%s->%s" % [entry.level, entry.planned, entry.type])
		var decade: int = (int(entry.level) - 1) / 10
		while rescues_per_ten.size() <= decade:
			rescues_per_ten.append(0.0)
		rescues_per_ten[decade] = float(rescues_per_ten[decade]) + float(entry.expected_rescues)
	for index in rescues_per_ten.size():
		rescues_per_ten[index] = snappedf(rescues_per_ten[index], 0.01)
	return {
		"levels": levels.size(),
		"pool_size": pool_size,
		"pool_used": used_count,
		"by_type": by_type,
		"fallbacks": fallbacks,
		"missing": missing,
		"expected_rescues_per_10_levels": rescues_per_ten,
	}
