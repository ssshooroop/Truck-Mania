extends SceneTree

## Level pipeline: generate a candidate pool, grade every candidate, order the
## campaign and write it out. Run from the repository root:
##   godot --headless --path bus-bloom --script res://tools/build_levels.gd
## Optional user arguments after "--": --config=res://... --pool=N --levels=N
## Parallel runs: --shard=K --shards=N evaluates every N-th candidate and,
## with --dump=PATH, writes the graded pool and stops. --from=PATH1,PATH2
## sequences the campaign from such dumps instead of generating.

const Generator = preload("res://scripts/level_candidate_generator.gd")
const Evaluator = preload("res://scripts/level_evaluator.gd")
const Sequencer = preload("res://scripts/level_sequencer.gd")
const DEFAULT_CONFIG := "res://config/level_pipeline.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := _user_args()
	var config_path: String = args.get("config", DEFAULT_CONFIG)
	var config = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not config is Dictionary:
		push_error("Cannot read config: " + config_path)
		quit(1)
		return
	var pool: Dictionary = config.pool
	if args.has("pool"):
		pool["size"] = int(args.pool)
	if args.has("levels"):
		config.sequence["level_count"] = int(args.levels)

	var generator = Generator.new()
	var evaluator = Evaluator.new()
	evaluator.configure(config.evaluation)
	var sequencer = Sequencer.new()
	sequencer.configure(config.sequence)

	var started := Time.get_ticks_msec()
	var records: Array = []
	var candidates: Array = []
	var stats := {}
	_shard = int(args.get("shard", 0))
	_shards = maxi(1, int(args.get("shards", 1)))
	if args.has("from"):
		for path: String in str(args.from).split(","):
			_load_dump(path, records, candidates, stats)
	else:
		if pool.get("size", 0) > 0:
			_generate_pool(pool, "", generator, evaluator, records, candidates, stats, started)
		# Small levels for the shuffle onboarding come from a pool of their own.
		if config.has("tutorial_pool"):
			_generate_pool(config.tutorial_pool, "tutorial ", generator, evaluator, records, candidates,
				stats, started)
		# Further targeted pools, e.g. for hard levels: [{"label": ..., size, first_seed, ...}].
		for extra: Dictionary in config.get("extra_pools", []):
			_generate_pool(extra, str(extra.get("label", "extra")) + " ", generator, evaluator, records,
				candidates, stats, started)
	if args.has("dump"):
		var dumped: Array = []
		for record: Dictionary in records:
			dumped.append({"evaluation": record.evaluation,
				"candidate": generator.to_json_data(candidates[record.index])})
		var saved := _write(str(args.dump), {"stats": stats, "records": dumped,
			"seconds": snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1)})
		print("Dumped %d graded candidates: %s" % [dumped.size(), JSON.stringify(stats)])
		quit(0 if saved else 1)
		return

	var campaign: Dictionary = sequencer.build(records)
	campaign.summary["pool_breakdown"] = stats
	campaign.summary["seconds"] = snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1)
	var exported: Array = []
	for entry: Dictionary in campaign.levels:
		if entry.type == "missing":
			continue
		var level: Dictionary = generator.to_json_data(candidates[entry.record_index])
		var evaluation: Dictionary = records[entry.record_index].evaluation
		level["solver_verified"] = true
		level["min_slots"] = evaluation.min_slots
		level["solution"] = evaluation.solution
		level["campaign"] = entry
		if entry.type == "booster_tutorial":
			# The level is winnable alone; at the first deadlock the game shows a hint
			# and gives this booster for free.
			level["tutorial"] = {"booster": evaluator.onboarding_booster, "hint": "first_deadlock",
				"free": true, "novice_deadlock_rate": entry.onboarding_deadlock_rate,
				"post_booster_win": entry.onboarding_post_win}
		if entry.type == "shuffle_tutorial":
			# The game shows the shuffle hint at the first deadlock, gives the shuffle
			# for free and picks it with LevelSolver.verified_shuffle.
			level["tutorial"] = {"booster": "shuffle", "hint": "first_deadlock", "free": true,
				"strength": evaluator.tutorial_strength, "verified_by_solver": true}
		exported.append(level)

	var output_dir: String = config.get("output_dir", "res://generated_levels")
	var suffix: String = config.get("output_suffix", "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	# Keep the editor from importing generated JSON as resources.
	FileAccess.open(output_dir.path_join(".gdignore"), FileAccess.WRITE).close()
	var ok := _write(output_dir.path_join("levels%s.json" % suffix), {"schema_version": 1,
		"base_slots": evaluator.base_slots, "first_level": sequencer.first_level, "levels": exported})
	ok = _write(output_dir.path_join("report%s.json" % suffix), campaign) and ok
	_print_report(campaign)
	quit(0 if ok and campaign.summary.missing.is_empty() else 1)

func _generate_pool(pool: Dictionary, label: String, generator, evaluator, records: Array,
		candidates: Array, stats: Dictionary, started: int) -> void:
	for offset in int(pool["size"]):
		if offset % _shards != _shard:
			continue
		var level_seed: int = int(pool.first_seed) + offset
		# Pool parameters use their own stream so they do not correlate with
		# the generator's first draws for the same seed.
		var params := RandomNumberGenerator.new()
		params.seed = hash("pool:%d" % level_seed)
		var vehicle_count := params.randi_range(int(pool.vehicles[0]), int(pool.vehicles[1]))
		var colors := params.randi_range(int(pool.colors[0]), int(pool.colors[1]))
		var window := params.randi_range(int(pool.queue_windows[0]), int(pool.queue_windows[1]))
		var twins: Array = pool.get("same_color_chance", [0.0, 0.0])
		var same_color := params.randf_range(float(twins[0]), float(twins[1]))
		var runs = pool.max_run
		var max_run: int = params.randi_range(int(runs[0]), int(runs[1])) if runs is Array else int(runs)
		var candidate: Dictionary = generator.generate(level_seed, vehicle_count, colors,
			int(pool.placement_attempts), window, max_run, same_color, int(pool.get("compact_rounds", 0)))
		if not candidate.ok:
			_count(stats, label + "generator:" + str(candidate.reason))
			continue
		var evaluation: Dictionary = evaluator.evaluate(candidate, hash("play:%d" % level_seed))
		var key: String = evaluation.category
		if key == "regular":
			key += ":" + str(evaluation.tier)
		elif key == "rejected":
			key += ":" + str(evaluation.reason)
		_count(stats, label + key)
		if evaluation.get("shuffle_tutorial_eligible", false):
			_count(stats, label + "shuffle_tutorial_eligible")
		if evaluation.category != "rejected":
			records.append({"index": candidates.size(), "evaluation": evaluation})
			candidates.append(candidate)
		if (offset + 1) % 25 == 0:
			print("  %s%d/%d candidates, %.1f s" % [label, offset + 1, int(pool["size"]),
				(Time.get_ticks_msec() - started) / 1000.0])

var _shard := 0
var _shards := 1

func _load_dump(path: String, records: Array, candidates: Array, stats: Dictionary) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Cannot read dump: " + path)
		return
	for key: String in data.stats:
		stats[key] = int(stats.get(key, 0)) + int(data.stats[key])
	for entry: Dictionary in data.records:
		var evaluation: Dictionary = entry.evaluation
		evaluation["seed"] = int(evaluation.seed)
		records.append({"index": candidates.size(), "evaluation": evaluation})
		candidates.append(Generator.from_json_data(entry.candidate))

func _user_args() -> Dictionary:
	var result := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.substr(2).split("=", true, 1)
			result[pair[0]] = pair[1]
	return result

func _count(stats: Dictionary, key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1

func _write(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write: " + path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true

func _print_report(campaign: Dictionary) -> void:
	print("  L  planned    type        fail  after1  rescues  trucks  colors  window")
	for entry: Dictionary in campaign.levels:
		if entry.type == "missing":
			print("%3d  %-10s MISSING" % [entry.level, entry.planned])
			continue
		print("%3d  %-10s %-10s %5.2f  %6.2f  %7.2f  %6d  %6d  %6d%s" % [entry.level,
			entry.planned, entry.type, entry.fail_rate, entry.post_rescue_fail,
			entry.expected_rescues, entry.vehicle_count, entry.color_count,
			entry.queue_window, "  (fallback)" if entry.fallback else ""])
	print("Summary: ", JSON.stringify(campaign.summary))
