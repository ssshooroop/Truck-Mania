extends SceneTree

## Targeted hard levels: generates a layout, then climbs towards a difficulty
## tier by mutating only the cargo queue (swapping two units of different
## colours) and truck colours (swapping two trucks of equal capacity, so the
## cargo still matches). Every accepted mutant is proven solvable with the
## base slots by the exact solver, so no level needs a booster.
## The finished candidate gets the full LevelEvaluator grading; its tier is
## then set from the full player measurements by the same thresholds.
## Run (one shard of a parallel batch):
##   godot --headless --path bus-bloom --script res://tools/harden_levels.gd -- \
##     --config=res://config/level_pipeline_101_150.json --shard=0 --shards=16 --dump=PATH
## The dumps are sequenced by build_levels.gd --from=PATH1,PATH2,...

const Generator = preload("res://scripts/level_candidate_generator.gd")
const Evaluator = preload("res://scripts/level_evaluator.gd")
const Solver = preload("res://scripts/level_solver.gd")

var _settings := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := _user_args()
	var config = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("config", ""))))
	if not config is Dictionary or not config.has("harden"):
		push_error("Config with a harden section is required")
		quit(1)
		return
	_settings = config.harden
	var pool: Dictionary = config.pool
	var shard := int(args.get("shard", 0))
	var shards := maxi(1, int(args.get("shards", 1)))
	var seeds := int(args.get("seeds", _settings.get("seeds", 64)))
	var generator = Generator.new()
	var evaluator = Evaluator.new()
	evaluator.configure(config.evaluation)
	var base_slots: int = evaluator.base_slots
	var started := Time.get_ticks_msec()
	var stats := {}
	var dumped: Array = []
	for offset in seeds:
		if offset % shards != shard:
			continue
		var level_seed: int = int(pool.first_seed) + offset
		var params := RandomNumberGenerator.new()
		params.seed = hash("pool:%d" % level_seed)
		var vehicle_count := params.randi_range(int(pool.vehicles[0]), int(pool.vehicles[1]))
		var colors := params.randi_range(int(pool.colors[0]), int(pool.colors[1]))
		var window := params.randi_range(int(pool.queue_windows[0]), int(pool.queue_windows[1]))
		var twins: Array = pool.get("same_color_chance", [0.0, 0.0])
		var same_color := params.randf_range(float(twins[0]), float(twins[1]))
		var max_run := params.randi_range(int(pool.max_run[0]), int(pool.max_run[1]))
		var candidate: Dictionary = generator.generate(level_seed, vehicle_count, colors,
			int(pool.placement_attempts), window, max_run, same_color)
		if not candidate.ok:
			_count(stats, "generator:" + str(candidate.reason))
			continue
		# Colour swaps keep the colour counts, so an imbalance cannot be climbed away.
		var counts := {}
		for vehicle: Dictionary in candidate.vehicles:
			counts[int(vehicle.color)] = int(counts.get(int(vehicle.color), 0)) + 1
		if counts.size() < evaluator.minimum_colors \
				or float(counts.values().max()) / vehicle_count > evaluator.max_color_share:
			_count(stats, "color_imbalance")
			continue
		var tier := _pick_tier(level_seed)
		var climb := _climb(candidate, tier, base_slots, level_seed)
		_count(stats, "climb:%s:%s" % [tier, "reached" if climb.reached else "missed"])
		if not climb.reached:
			continue
		candidate.metrics["hardened_steps"] = climb.steps
		candidate.metrics["hardened_target"] = tier
		var evaluation: Dictionary = evaluator.evaluate(candidate, hash("play:%d" % level_seed))
		if evaluation.category != "regular":
			_count(stats, "graded:" + str(evaluation.get("reason", evaluation.category)))
			continue
		var final_tier := _classify({"o": evaluation.ordinary_fail, "s": evaluation.strong_fail,
			"e": evaluation.get("expert_fail", 0.0)})
		evaluation["tier"] = final_tier
		evaluation["soft_gate_eligible"] = false
		# The generator's certificate was for the original queue; keep the solver's.
		candidate["dispatch_order"] = evaluation.solution
		_count(stats, "graded:" + final_tier)
		dumped.append({"evaluation": evaluation, "candidate": generator.to_json_data(candidate)})
		print("  seed %d: %s -> %s after %d steps, %.1f s" % [level_seed, tier, final_tier,
			climb.steps, (Time.get_ticks_msec() - started) / 1000.0])
	var file := FileAccess.open(str(args.dump), FileAccess.WRITE)
	file.store_string(JSON.stringify({"stats": stats, "records": dumped,
		"seconds": snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1)}, "  "))
	file.close()
	print("Hardened %d levels: %s" % [dumped.size(), JSON.stringify(stats)])
	quit(0)

## Target tier of a seed, drawn from harden.mix (weights per tier).
func _pick_tier(level_seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tier:%d" % level_seed)
	var mix: Dictionary = _settings.mix
	var total := 0.0
	for name: String in mix:
		total += float(mix[name])
	var roll := rng.randf() * total
	for name: String in mix:
		roll -= float(mix[name])
		if roll <= 0.0:
			return name
	return mix.keys()[-1]

## Hill climb on the band distance of `tier`. Returns {reached, steps}.
func _climb(candidate: Dictionary, tier: String, base_slots: int, level_seed: int) -> Dictionary:
	var solver = Solver.new(candidate.vehicles, candidate.queue)
	var node_limit := int(_settings.get("node_limit", 200000))
	if solver.solve(base_slots, node_limit).status != "solvable":
		return {"reached": false, "steps": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("climb:%d" % level_seed)
	var current := _distance(_quick(solver, base_slots, level_seed), tier)
	var steps := 0
	var max_steps := int(_settings.get("steps", 300))
	while current > 0.0 and steps < max_steps:
		steps += 1
		var undo := _mutate(candidate, rng)
		if undo.is_empty():
			continue
		if solver.solve(base_slots, node_limit).status != "solvable":
			_revert(candidate, undo)
			continue
		var distance := _distance(_quick(solver, base_slots, level_seed), tier)
		if distance <= current:
			current = distance
		else:
			_revert(candidate, undo)
	return {"reached": current <= 0.0, "steps": steps}

## Fail rates of the three planners with common random numbers per level.
func _quick(solver, base_slots: int, level_seed: int) -> Dictionary:
	var runs: Dictionary = _settings.quick_runs
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("quick:%d" % level_seed)
	var o: float = solver.simulate_planner(base_slots, int(runs.o), 2, 0.1, rng).fail_rate
	var s: float = solver.simulate_planner(base_slots, int(runs.s), 3, 0.05, rng).fail_rate
	var e := 0.0
	# The expert is the expensive one; it only matters once the strong player fails.
	if s >= float(_settings.get("expert_from_strong", 0.5)):
		e = solver.simulate_planner(base_slots, int(runs.e), 5, 0.0, rng).fail_rate
	return {"o": o, "s": s, "e": e}

## Sum of distances of each measure from its [low, high] band of the tier.
func _distance(measure: Dictionary, tier: String) -> float:
	var bands: Dictionary = _settings.tiers[tier]
	var total := 0.0
	for key: String in bands:
		var band: Array = bands[key]
		var value := float(measure.get(key, 0.0))
		total += maxf(0.0, float(band[0]) - value) + maxf(0.0, value - float(band[1]))
	return total

## Hardest tier whose bands all contain the measures; "unclassified" otherwise.
func _classify(measure: Dictionary) -> String:
	for tier: String in ["very_hard", "hard", "medium", "easy"]:
		if _settings.tiers.has(tier) and _distance(measure, tier) <= 0.0:
			return tier
	return "unclassified"

## One random mutation; returns what _revert needs, or {} if none applied.
func _mutate(candidate: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var queue: Array = candidate.queue
	if rng.randf() < float(_settings.get("queue_share", 0.8)):
		var reach := int(_settings.get("swap_reach", 8))
		for attempt in 20:
			var i := rng.randi_range(0, queue.size() - 1)
			var j := clampi(i + rng.randi_range(-reach, reach), 0, queue.size() - 1)
			if queue[i] != queue[j]:
				var tmp: int = queue[i]
				queue[i] = queue[j]
				queue[j] = tmp
				return {"queue": [i, j]}
		return {}
	var vehicles: Array = candidate.vehicles
	for attempt in 20:
		var a: Dictionary = vehicles[rng.randi_range(0, vehicles.size() - 1)]
		var b: Dictionary = vehicles[rng.randi_range(0, vehicles.size() - 1)]
		if a.capacity == b.capacity and a.color != b.color:
			var tmp: int = a.color
			a.color = b.color
			b.color = tmp
			return {"colors": [a.id, b.id]}
	return {}

func _revert(candidate: Dictionary, undo: Dictionary) -> void:
	if undo.has("queue"):
		var queue: Array = candidate.queue
		var i: int = undo.queue[0]
		var j: int = undo.queue[1]
		var tmp: int = queue[i]
		queue[i] = queue[j]
		queue[j] = tmp
	else:
		var a: Dictionary = candidate.vehicles[undo.colors[0]]
		var b: Dictionary = candidate.vehicles[undo.colors[1]]
		var tmp: int = a.color
		a.color = b.color
		b.color = tmp

func _user_args() -> Dictionary:
	var result := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.substr(2).split("=", true, 1)
			result[pair[0]] = pair[1]
	return result

func _count(stats: Dictionary, key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1
