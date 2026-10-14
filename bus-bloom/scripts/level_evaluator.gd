class_name LevelEvaluator
extends RefCounted

## Grades one generated candidate: exact solvability per slot count, a
## Monte Carlo player model at the base slots, structure metrics, a tier and
## a category used by LevelSequencer.
##
## Categories:
## - "regular": solvable with base_slots; tier from the player fail rate.
##   soft_gate_eligible marks hard levels inside the soft gate band: winnable
##   without help, but most players hit a deadlock and buy a rescue.
## - "slot_gate": proven unsolvable with base_slots, solvable with one more;
##   every player needs exactly one Extra Slot rescue.
## - "rejected": needs two or more extra slots, or the solver timed out.

const Solver = preload("res://scripts/level_solver.gd")

var base_slots := 3
var max_slots := 5
var node_limit := 300000
var player_runs := 200
var player_skill := 0.7
var max_rescues := 2
## Ascending upper bounds of the base-slot fail rate per tier.
var tiers: Array = [
	{"name": "easy", "max_fail": 0.15},
	{"name": "medium", "max_fail": 0.30},
	{"name": "hard", "max_fail": 0.50},
	{"name": "very_hard", "max_fail": 1.0},
]
var soft_gate_fail := [0.50, 0.85]
## A slot gate must be fair after the rescue: post-rescue fail rate at most this.
var slot_gate_max_post_rescue_fail := 0.40
## Player skills for the fail curve fed to the economy model.
var skill_grid := [0.0, 0.35, 0.7, 0.95]
var trap_node_limit := 20000
## Booster utility probe: runs per measurement and shuffles per deadlock.
var booster_runs := 200
var shuffles_per_deadlock := 10
## Smart shuffle strengths to measure (best of k permutations, 1 = plain).
var shuffle_strengths := [1, 2, 4, 8, 16]
## Shuffle onboarding: small levels proven unsolvable with base slots whose
## every sampled deadlock a verified smart shuffle turns into a win.
var tutorial_max_vehicles := 10
var tutorial_runs := 40
var tutorial_tries := 40
var tutorial_strength := 8
var tutorial_min_recoverable := 1.0
var tutorial_min_post_win := 0.6
## interest = gap * skill_gap + traps * trap_score + near_miss * near_miss
##          + tension * mean_peak_fill, times luck_penalty when experts fail.
var interest_weights := {"gap": 0.35, "traps": 0.25, "near_miss": 0.2, "tension": 0.2}
var ideal_trap_ratio := 0.35
var expert_fail_limit := 0.25
var luck_penalty := 0.7

func configure(settings: Dictionary) -> void:
	base_slots = int(settings.get("base_slots", base_slots))
	max_slots = int(settings.get("max_slots", max_slots))
	node_limit = int(settings.get("solver_node_limit", node_limit))
	player_runs = int(settings.get("player_runs", player_runs))
	player_skill = float(settings.get("player_skill", player_skill))
	max_rescues = int(settings.get("max_rescues", max_rescues))
	tiers = settings.get("tiers", tiers)
	soft_gate_fail = settings.get("soft_gate_fail", soft_gate_fail)
	slot_gate_max_post_rescue_fail = float(settings.get("slot_gate_max_post_rescue_fail",
		slot_gate_max_post_rescue_fail))
	skill_grid = settings.get("skill_grid", skill_grid)
	trap_node_limit = int(settings.get("trap_node_limit", trap_node_limit))
	booster_runs = int(settings.get("booster_runs", booster_runs))
	shuffles_per_deadlock = int(settings.get("shuffles_per_deadlock", shuffles_per_deadlock))
	shuffle_strengths = settings.get("shuffle_strengths", shuffle_strengths)
	var tutorial: Dictionary = settings.get("shuffle_tutorial", {})
	tutorial_max_vehicles = int(tutorial.get("max_vehicles", tutorial_max_vehicles))
	tutorial_runs = int(tutorial.get("runs", tutorial_runs))
	tutorial_tries = int(tutorial.get("tries", tutorial_tries))
	tutorial_strength = int(tutorial.get("strength", tutorial_strength))
	tutorial_min_recoverable = float(tutorial.get("min_recoverable", tutorial_min_recoverable))
	tutorial_min_post_win = float(tutorial.get("min_post_win", tutorial_min_post_win))
	interest_weights.merge(settings.get("interest_weights", {}), true)
	ideal_trap_ratio = float(settings.get("ideal_trap_ratio", ideal_trap_ratio))
	expert_fail_limit = float(settings.get("expert_fail_limit", expert_fail_limit))
	luck_penalty = float(settings.get("luck_penalty", luck_penalty))

func evaluate(candidate: Dictionary, rng_seed: int) -> Dictionary:
	var solver = Solver.new(candidate.vehicles, candidate.queue)
	var exact: Dictionary = solver.min_slots(max_slots, node_limit)
	var minimum: int = exact.min_slots
	var result := {
		"seed": candidate.seed,
		"min_slots": minimum,
		"min_slots_proven": exact.proven,
		"solver_statuses": exact.statuses,
		"solution": exact.path,
		"blocking_depth": _blocking_depth(solver.blockers),
	}
	result.merge(candidate.metrics)
	var tutorial_ok := false
	if exact.statuses.get(str(base_slots), "") == "unsolvable" \
			and int(candidate.metrics.vehicle_count) <= tutorial_max_vehicles:
		var tutorial_rng := RandomNumberGenerator.new()
		tutorial_rng.seed = rng_seed + 1
		var profile: Dictionary = solver.tutorial_profile(base_slots, tutorial_runs, tutorial_tries,
			tutorial_strength, trap_node_limit, skill_grid, tutorial_rng)
		result.merge(profile)
		tutorial_ok = float(profile.tutorial_recoverable) >= tutorial_min_recoverable \
			and float(profile.tutorial_post_win) >= tutorial_min_post_win
	result["shuffle_tutorial_eligible"] = tutorial_ok
	if not tutorial_ok and (minimum == -1 or minimum > base_slots + 1):
		result["category"] = "rejected"
		result["reason"] = "needs_too_many_slots" if minimum != -1 else "unsolved"
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	result.merge(solver.simulate(base_slots, player_runs, player_skill, max_rescues, max_slots, rng))
	var fail_by_skill := {}
	for skill in skill_grid:
		var runs := player_runs if is_equal_approx(float(skill), player_skill) else maxi(20, player_runs / 2)
		fail_by_skill[str(skill)] = solver.simulate(base_slots, runs, float(skill), 0, base_slots, rng).fail_rate
	fail_by_skill[str(player_skill)] = result.fail_rate
	result["fail_by_skill"] = fail_by_skill
	if not exact.path.is_empty():
		result.merge(solver.trap_profile(maxi(minimum, base_slots), exact.path, trap_node_limit))
	else:
		result.merge({"decisions": 0, "trap_ratio": 0.0, "critical_share": 0.0, "trap_unknown": 0})
	result.merge(solver.booster_profile(base_slots, max_slots, booster_runs, shuffles_per_deadlock,
		player_skill, rng, shuffle_strengths))
	result["interest"] = _interest(result, minimum == -1 or minimum > base_slots)
	if tutorial_ok and (minimum == -1 or minimum > base_slots + 1):
		result["category"] = "shuffle_tutorial"
	elif minimum <= base_slots:
		var fail: float = result.fail_rate
		result["category"] = "regular"
		result["tier"] = _tier(fail)
		result["soft_gate_eligible"] = fail >= float(soft_gate_fail[0]) and fail <= float(soft_gate_fail[1])
	elif not exact.proven or exact.statuses.get(str(base_slots), "") != "unsolvable":
		result["category"] = "rejected"
		result["reason"] = "base_slots_not_proven_unsolvable"
	elif float(result.post_rescue_fail) > slot_gate_max_post_rescue_fail:
		result["category"] = "shuffle_tutorial" if tutorial_ok else "rejected"
		result["reason"] = "too_hard_after_rescue"
	else:
		result["category"] = "slot_gate"
		result["tier"] = "slot_gate"
	return result

## 0..1. Rewards levels where skill matters, wrong choices exist but do not
## dominate, deadlocks come late ("almost made it") and the buffer gets tight.
func _interest(metrics: Dictionary, slot_gate: bool) -> float:
	var curve: Dictionary = metrics.fail_by_skill
	var novice := float(curve.get(str(skill_grid[0]), metrics.fail_rate))
	var expert := float(curve.get(str(skill_grid[-1]), metrics.fail_rate))
	# A slot gate fails for everyone at base slots; its skill gap is irrelevant.
	var skill_gap := 0.5 if slot_gate else clampf(novice - expert, 0.0, 1.0)
	var trap_ratio := float(metrics.trap_ratio)
	var trap_score := 1.0 - minf(1.0, absf(trap_ratio - ideal_trap_ratio) / ideal_trap_ratio)
	var w := interest_weights
	var value := float(w.gap) * skill_gap + float(w.traps) * trap_score \
		+ float(w.near_miss) * float(metrics.near_miss) + float(w.tension) * float(metrics.mean_peak_fill)
	if not slot_gate and expert > expert_fail_limit:
		value *= luck_penalty
	return clampf(value, 0.0, 1.0)

func _tier(fail: float) -> String:
	for tier: Dictionary in tiers:
		if fail <= float(tier.max_fail):
			return tier.name
	return tiers[-1].name

## Longest chain of trucks that must leave one after another.
func _blocking_depth(blockers: Array) -> int:
	var depth: Array = []
	depth.resize(blockers.size())
	depth.fill(-1)
	var best := 0
	for id in blockers.size():
		best = maxi(best, _depth_of(id, blockers, depth))
	return best

func _depth_of(id: int, blockers: Array, depth: Array) -> int:
	if int(depth[id]) != -1:
		return depth[id]
	var result := 1
	var mask: int = blockers[id]
	for other in blockers.size():
		if ((mask >> other) & 1) == 1:
			result = maxi(result, 1 + _depth_of(other, blockers, depth))
	depth[id] = result
	return result
