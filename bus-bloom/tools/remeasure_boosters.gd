extends SceneTree

## Re-measures booster utility (slots, smart shuffle, truck swap) for the
## levels of an existing campaign and updates generated_levels/levels.json in
## place, without regenerating the candidate pool. Run from the repository root:
##   godot --headless --path bus-bloom --script res://tools/remeasure_boosters.gd

const Generator = preload("res://scripts/level_candidate_generator.gd")
const Solver = preload("res://scripts/level_solver.gd")
const CONFIG_PATH := "res://config/level_pipeline.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var output_dir: String = config.get("output_dir", "res://generated_levels")
	var path := output_dir.path_join("levels.json")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Cannot read " + path)
		quit(1)
		return
	var e: Dictionary = config.evaluation
	var started := Time.get_ticks_msec()
	for level: Dictionary in data.levels:
		var candidate: Dictionary = Generator.from_json_data(level)
		var solver = Solver.new(candidate.vehicles, candidate.queue)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("boosters:%d" % int(level.seed))
		var profile: Dictionary = solver.booster_profile(int(e.base_slots), int(e.max_slots),
			int(e.get("booster_runs", 150)), int(e.get("shuffles_per_deadlock", 6)),
			float(e.player_skill), rng, e.get("shuffle_strengths", [1]))
		var entry: Dictionary = level.campaign
		for key in ["fail_by_slots", "slot_again", "swap_again", "crane_again", "shuffle_by_strength"]:
			entry[key] = profile[key]
		entry["shuffle_again"] = profile.shuffle_again
		entry["shuffle_hopeless"] = snappedf(float(profile.shuffle_hopeless), 0.001)
		entry["shuffle_spread"] = snappedf(float(profile.shuffle_spread), 0.001)
		print("  level %d: swap again %s, slot again %s (%.0f s)" % [int(entry.level), str(profile.swap_again),
			str(profile.slot_again), (Time.get_ticks_msec() - started) / 1000.0])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	quit(0)
