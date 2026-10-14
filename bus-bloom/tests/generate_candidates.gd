extends SceneTree

const Generator = preload("res://scripts/level_candidate_generator.gd")

const MIN_VEHICLES := 10
const MAX_VEHICLES := 20
const COLOR_COUNT := 4
const FIRST_SEED := 10000
const CANDIDATE_COUNT := 100

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var generator = Generator.new()
	var directory := DirAccess.open("res://")
	if directory == null:
		push_error("Cannot open project directory")
		quit(1)
		return
	directory.make_dir_recursive("generated_candidates")
	var accepted := 0
	var errors := 0
	var distribution := {}
	for seed in range(FIRST_SEED, FIRST_SEED + CANDIDATE_COUNT):
		# Separate RNG ensures vehicle count is stable for a given seed.
		var count_rng := RandomNumberGenerator.new()
		count_rng.seed = hash("count:%d" % seed)
		var vehicle_count := count_rng.randi_range(MIN_VEHICLES, MAX_VEHICLES)
		var result: Dictionary = generator.generate(seed, vehicle_count, COLOR_COUNT, 8000)
		if not result.get("ok", false):
			errors += 1
			continue
		var path := "res://generated_candidates/candidate_%05d.json" % seed
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write: " + path)
			errors += 1
			continue
		file.store_string(JSON.stringify(generator.to_json_data(result), "  "))
		file.close()
		accepted += 1
		distribution[vehicle_count] = int(distribution.get(vehicle_count, 0)) + 1
	print("Generated %d candidates; %d rejected/failed" % [accepted, errors])
	print("Accepted vehicle-count distribution: ", distribution)
	quit(0 if accepted > 0 else 1)
