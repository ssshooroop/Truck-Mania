extends SceneTree

const Model = preload("res://scripts/game_model.gd")
const Generator = preload("res://scripts/level_candidate_generator.gd")
const Solver = preload("res://scripts/level_solver.gd")
const Evaluator = preload("res://scripts/level_evaluator.gd")
const Sequencer = preload("res://scripts/level_sequencer.gd")
const Boosters = preload("res://scripts/level_boosters.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_solver_matches_shipped_levels()
	_test_generated_levels_replay_in_game()
	_test_same_color_windows()
	_test_truck_swap()
	_test_slot_monotonicity()
	_test_evaluator_categories()
	_test_sequencer_schedule()
	_test_boosters()
	print("Level pipeline checks: %d; failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

## Plays a dispatch order on the production model, letting cargo board and
## full trucks leave between dispatches. Returns true when the level is won.
func _replay(model, path: Array) -> bool:
	_settle_game(model)
	for id: int in path:
		if not model.dispatch(id):
			return false
		model.arrive(id)
		_settle_game(model)
	return model.is_won()

func _settle_game(model) -> void:
	while true:
		var id: int = model.next_boarding()
		if id == -1:
			return
		model.board_batch(id, model.batch_size(id))
		if model.get_bus(id)["status"] == "leaving":
			model.depart(id)

func _test_solver_matches_shipped_levels() -> void:
	for index in Model.new().level_count():
		var model = Model.new()
		model.load_level(index)
		var solver = Solver.new(model.buses, model.queue)
		var result: Dictionary = solver.solve(Model.BAY_COUNT, 2000000)
		check(result.status == "solvable", "Shipped level %d is solvable with five bays" % index)
		check(_replay(model, result.path), "Solver path wins shipped level %d in BusGameModel" % index)

func _test_generated_levels_replay_in_game() -> void:
	var generator = Generator.new()
	var tested := 0
	for level_seed in range(500, 540):
		var candidate: Dictionary = generator.generate(level_seed, 10, 4, 8000, 3, 3)
		if not candidate.ok:
			continue
		tested += 1
		var solver = Solver.new(candidate.vehicles, candidate.queue)
		var result: Dictionary = solver.solve(3, 500000)
		check(result.status != "unsolvable", "Window-3 candidate %d is not proven unsolvable with three slots" % level_seed)
		if result.status == "solvable":
			var model = Model.new()
			model.level_index = 0
			model.buses = candidate.vehicles.duplicate(true)
			model.queue = candidate.queue.duplicate()
			check(_replay(model, result.path), "Three-slot solution of %d wins in BusGameModel" % level_seed)
		var plain: Dictionary = generator.generate(level_seed, 10, 4, 8000, 1, 3)
		if plain.ok:
			var single: Dictionary = Solver.new(plain.vehicles, plain.queue).solve(1, 500000)
			check(single.status == "solvable", "Contiguous queue %d is solvable with one slot" % level_seed)
	check(tested >= 10, "At least ten generated candidates were tested (got %d)" % tested)

func _test_same_color_windows() -> void:
	var generator = Generator.new()
	var overlaps := 0
	var replayed := 0
	for level_seed in range(800, 830):
		var candidate: Dictionary = generator.generate(level_seed, 10, 4, 20000, 3, 3, 0.8)
		if not candidate.ok:
			continue
		overlaps += int(candidate.metrics.same_color_overlaps)
		var result: Dictionary = Solver.new(candidate.vehicles, candidate.queue).solve(5, 500000)
		if result.status != "solvable":
			continue
		var model = Model.new()
		model.level_index = 0
		model.buses = candidate.vehicles.duplicate(true)
		model.queue = candidate.queue.duplicate()
		check(_replay(model, result.path), "Same-colour level %d: solver path wins in BusGameModel" % level_seed)
		replayed += 1
	check(overlaps > 0, "same_color_chance puts same-colour trucks into one window")
	check(replayed >= 10, "At least ten same-colour levels were replayed (got %d)" % replayed)

func _test_truck_swap() -> void:
	var generator = Generator.new()
	var swaps := 0
	for level_seed in range(900, 930):
		var candidate: Dictionary = generator.generate(level_seed, 12, 4, 20000, 4, 3, 0.4)
		if not candidate.ok:
			continue
		var solver = Solver.new(candidate.vehicles, candidate.queue)
		var rng := RandomNumberGenerator.new()
		rng.seed = level_seed
		var state: Dictionary = solver._initial_state(3)
		if solver._play_until_deadlock(state, 0.5, rng):
			continue
		var head: int = state.get("queue", candidate.queue)[state.offset]
		if not solver.swap_truck(state):
			continue
		swaps += 1
		# Remaining capacity per colour must equal the cargo still on the conveyor.
		var need := {}
		for id in candidate.vehicles.size():
			var in_play: bool = ((int(state.yard) >> id) & 1) == 1 or state.bays.has(id)
			if in_play:
				var color: int = candidate.vehicles[id].color
				need[color] = int(need.get(color, 0)) + int(candidate.vehicles[id].capacity) - int(state.loads[id])
		var left := {}
		var cargo: Array = state.queue
		for index in range(int(state.offset), cargo.size()):
			left[cargo[index]] = int(left.get(cargo[index], 0)) + 1
		check(need == left, "Swap keeps cargo and capacity balanced on %d" % level_seed)
		var docked_head := false
		for id: int in state.bays:
			if id != -1 and int(candidate.vehicles[id].color) == head:
				docked_head = true
		check(docked_head, "Swap brings a truck for the conveyor head on %d" % level_seed)
	check(swaps >= 10, "At least ten swaps were tested (got %d)" % swaps)
	var cranes := 0
	for level_seed in range(930, 960):
		var candidate: Dictionary = generator.generate(level_seed, 12, 4, 20000, 4, 3, 0.4)
		if not candidate.ok:
			continue
		var solver = Solver.new(candidate.vehicles, candidate.queue)
		var rng := RandomNumberGenerator.new()
		rng.seed = level_seed
		var state: Dictionary = solver._initial_state(3)
		if solver._play_until_deadlock(state, 0.5, rng):
			continue
		var head: int = candidate.queue[state.offset]
		var yard_before: int = state.yard
		if not solver.crane_truck(state):
			continue
		cranes += 1
		var lifted: int = state.bays[3]
		check(state.bays.size() == 4 and int(candidate.vehicles[lifted].color) == head,
			"Crane opens one slot with a truck for the conveyor head on %d" % level_seed)
		check(((yard_before >> lifted) & 1) == 1 and not state.has("queue"),
			"Crane lifts a parked truck and leaves the cargo untouched on %d" % level_seed)
		state.bays.append(-1)
		check(not solver.crane_truck(state, 5), "Crane respects the five-slot limit on %d" % level_seed)
	check(cranes >= 10, "At least ten crane lifts were tested (got %d)" % cranes)

func _test_slot_monotonicity() -> void:

	var generator = Generator.new()
	for level_seed in range(600, 620):
		var candidate: Dictionary = generator.generate(level_seed, 12, 4, 8000, 4, 3)
		if not candidate.ok:
			continue
		var solver = Solver.new(candidate.vehicles, candidate.queue)
		var solvable_before := false
		for slots in range(1, 6):
			var status: String = solver.solve(slots, 300000).status
			if status == "timeout":
				break
			check(not (solvable_before and status == "unsolvable"),
				"More slots never break a solvable level (%d, %d slots)" % [level_seed, slots])
			solvable_before = solvable_before or status == "solvable"

func _test_evaluator_categories() -> void:
	var generator = Generator.new()
	var evaluator = Evaluator.new()
	evaluator.player_runs = 60
	var seen := {}
	for level_seed in range(700, 760):
		var window := 1 + level_seed % 4
		var candidate: Dictionary = generator.generate(level_seed, 12, 4, 8000, window, 3)
		if not candidate.ok:
			continue
		var queue_before: Array = candidate.queue.duplicate()
		var evaluation: Dictionary = evaluator.evaluate(candidate, level_seed)
		seen[evaluation.category] = true
		check(candidate.queue == queue_before, "Shuffle probes leave the level queue of %d untouched" % level_seed)
		if evaluation.category != "rejected":
			var by_slots: Dictionary = evaluation.fail_by_slots
			check(by_slots.has("3") and by_slots.has("5"), "fail_by_slots covers 3..5 slots")
			check(float(by_slots["5"]) <= float(by_slots["3"]) + 0.15,
				"Five starting slots are not worse than three on %d" % level_seed)
			for value in evaluation.slot_again + evaluation.shuffle_again:
				check(float(value) >= 0.0 and float(value) <= 1.0, "Booster rates are probabilities")
			if evaluation.category == "slot_gate":
				check(is_equal_approx(float(by_slots["3"]), 1.0), "Slot gate %d always deadlocks with three slots" % level_seed)
		match evaluation.category:
			"regular":
				check(evaluation.min_slots <= 3, "Regular level %d is solvable with base slots" % level_seed)
				check(evaluation.fail_rate >= 0.0 and evaluation.fail_rate <= 1.0, "Fail rate is a probability")
			"slot_gate":
				check(evaluation.min_slots == 4 and evaluation.min_slots_proven,
					"Slot gate %d is proven to need exactly one extra slot" % level_seed)
				check(is_equal_approx(evaluation.fail_rate, 1.0), "Nobody clears slot gate %d without a rescue" % level_seed)
				check(evaluation.expected_rescues >= 1.0, "Slot gate %d always costs a rescue" % level_seed)
	check(seen.has("regular"), "The evaluator produces regular levels")
	print("  evaluator categories seen: ", seen.keys())

func _test_sequencer_schedule() -> void:
	var config = JSON.parse_string(FileAccess.get_file_as_string("res://config/level_pipeline.json"))
	var sequencer = Sequencer.new()
	sequencer.configure(config.sequence)
	check(sequencer.slot_type(1) == "easy", "Level 1 is onboarding")
	check(sequencer.slot_type(3) == "booster_tutorial", "Level 3 teaches one booster")
	check(sequencer.slot_type(5) == "hard" and sequencer.slot_type(10) == "hard",
		"Gates before first_gate_level are plain hard levels")
	check(sequencer.slot_type(20) == "soft_gate" and sequencer.slot_type(40) == "soft_gate",
		"A soft gate every 20 levels")
	check(sequencer.slot_type(25) == "hard" and sequencer.slot_type(30) == "hard", "Hard levels between gates")
	check(sequencer.slot_type(21) == "easy", "A breather follows every gate")
	for number in range(1, 101):
		check(not sequencer.slot_type(number) in ["slot_gate", "shuffle_tutorial"],
			"Level %d never needs a booster by construction" % number)
	# Synthetic pool: the sequencer must honour types, the early cap and never reuse a level.
	var records: Array = []
	for index in 300:
		var fail := float(index % 97) / 96.0
		records.append({"index": index, "evaluation": {"seed": index, "category": "regular",
			"tier": _tier_of(fail), "soft_gate_eligible": fail >= 0.5 and fail <= 0.85,
			"fail_rate": fail, "post_rescue_fail": float(index % 7) / 20.0, "expected_rescues": fail,
			"speed_bonus_rate": 0.0, "clutch_rate": 0.0, "min_slots": 3, "vehicle_count": 8 + index % 13,
			"color_count": 3 + index % 3, "queue_window": 1 + index % 4, "blocking_depth": 3,
			"novice_attempts": 1.0 / maxf(0.05, 1.0 - minf(0.95, fail * 1.4)),
			"booster_tutorial_eligible": index % 25 == 5, "onboarding_post_win": 0.95}})
	sequencer.level_count = 40
	var campaign: Dictionary = sequencer.build(records)
	var used := {}
	for entry: Dictionary in campaign.levels:
		check(entry.type != "missing", "Level %d was filled" % entry.level)
		check(not used.has(entry.record_index), "Record %d is used once" % entry.record_index)
		used[entry.record_index] = true
		if entry.level <= 10 and entry.type != "booster_tutorial":
			check(float(entry.novice_attempts) <= 3.5, "Level %d takes a novice at most 3.5 attempts" % entry.level)
	check(campaign.levels[2].type == "booster_tutorial", "Level 3 is the booster tutorial")
	check(campaign.summary.by_type.get("soft_gate", 0) == 2, "Forty levels hold two soft gates")

func _tier_of(fail: float) -> String:
	if fail <= 0.15:
		return "easy"
	if fail <= 0.30:
		return "medium"
	if fail <= 0.50:
		return "hard"
	return "very_hard"

func _test_boosters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var source := [0, 1, 2, 3, 0, 1, 2, 3, 0, 1]
	var shuffled: Array = Boosters.shuffle_remaining(source, rng, 3)
	check(source == [0, 1, 2, 3, 0, 1, 2, 3, 0, 1], "Shuffle leaves the source queue unchanged")
	check(shuffled.slice(0, 3) == source.slice(0, 3), "Shuffle keeps the reserved prefix")
	var sorted_a := source.duplicate()
	var sorted_b := shuffled.duplicate()
	sorted_a.sort()
	sorted_b.sort()
	check(sorted_a == sorted_b, "Shuffle keeps every unit of cargo")
	check(Boosters.unlock_slot(3) == 4 and Boosters.unlock_slot(5) == 5, "Extra slots stop at five")
	var docked := [{"color": 2, "load": 1, "free": 3}, {"color": 1, "load": 0, "free": 2}]
	var smart: Array = Boosters.smart_shuffle(source, rng, 3, docked, 8)
	var sorted_c := smart.duplicate()
	sorted_c.sort()
	check(sorted_c == sorted_a and smart.slice(0, 3) == source.slice(0, 3),
		"Smart shuffle keeps every unit and the loaded prefix")
	var plain_score := 0
	var smart_score := 0
	for trial in 200:
		plain_score += Boosters.shuffle_score(Boosters.smart_shuffle(source, rng, 3, docked, 1), 3, docked)
		smart_score += Boosters.shuffle_score(Boosters.smart_shuffle(source, rng, 3, docked, 16), 3, docked)
	check(smart_score > plain_score, "A stronger smart shuffle scores better on average")
	check(Boosters.shuffle_score([1, 1, 2, 2, 2, 0], 0, docked) == 2005,
		"shuffle_score counts filled trucks and loaded units")
