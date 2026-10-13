extends SceneTree

const Model = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
var max_hint_ms := 0.0

func _initialize() -> void:
	_test_geometry()
	_test_dispatch_and_deadlock()
	_test_material_and_bay_rules()
	_test_batch_loading()
	_test_snapshot_validation()
	_test_every_level()
	_test_batch_equivalence_every_level()
	print("Model checks: %d; max hint: %.2f ms; failures: %d" % [checks, max_hint_ms, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _truck(id: int, position: Vector2, angle: float, kind := 0, material := 0) -> Dictionary:
	return {"id": id, "position": position, "angle": angle, "kind": kind,
		"color": material, "capacity": Model.CAPACITIES[kind], "load": 0, "status": "yard", "bay": -1}

func _test_geometry() -> void:
	var model = Model.new()
	model.buses = [_truck(0, Vector2(270, 710), 0.0), _truck(1, Vector2(270, 600), 0.0)]
	check(model.blocking_ids(0) == [1], "A truck ahead blocks departure")
	check(model.blocking_ids(1).is_empty(), "A truck behind does not block departure")
	var saved: Array = model.buses.duplicate(true)
	check(not model.dispatch(0) and model.buses == saved, "Blocked click leaves all trucks unchanged")
	model.buses[1]["position"] = Vector2(300, 600)
	check(model.blocking_ids(0) == [1], "Swept truck edge catches an obstacle outside its center ray")
	model.buses[1]["position"] = Vector2(327, 600)
	check(model.blocking_ids(0).is_empty(), "Parallel bodies with positive side clearance do not block")
	model.buses[0] = _truck(0, Vector2(170, 740), PI / 4.0)
	var direction: Vector2 = model.forward(model.buses[0])
	var side := Vector2(-direction.y, direction.x)
	model.buses[1] = _truck(1, Vector2(170, 740) + direction * 110 + side * 55, PI / 4.0)
	check(model.blocking_ids(0) == [1], "Diagonal sweep includes full body width")
	model.buses[1]["position"] = Vector2(170, 740) + direction * 110 + side * 57
	check(model.blocking_ids(0).is_empty(), "Diagonal parallel clearance stays navigable")
	model.buses[1]["position"] = Vector2(170, 740) - direction * 110
	check(model.blocking_ids(0).is_empty(), "Diagonal obstacle behind the moving body does not block")
	model.buses[0] = _truck(0, Vector2(180, 740), PI / 4.0, 2)
	model.buses[1] = _truck(1, Vector2(258, 662), -PI / 4.0, 2)
	check(model.blocking_ids(0) == [1], "Crossing oblique long trailers are detected")
	model.buses[1]["status"] = "arriving"
	check(model.blocking_ids(0).is_empty(), "Dispatched trucks no longer occupy yard geometry")
	for angle_step in range(8):
		model.buses[0] = _truck(0, Vector2(270, 664), angle_step * PI / 4.0, 2)
		var exit: Vector2 = model.exit_position(0)
		var clear_rect: Rect2 = Model.YARD_RECT.grow(model.vehicle_size(model.buses[0]).length() * 0.5 + 9.9)
		check(not clear_rect.has_point(exit), "Exit clears the full rotational radius at direction %d" % angle_step)

func _invariants(model) -> bool:
	var remaining: Array = [0, 0, 0, 0, 0, 0]
	var occupied: Array = []
	var total := 0
	var initial_total := 0
	for bus in model.buses:
		if bus["load"] < 0 or bus["load"] > bus["capacity"] or bus["capacity"] != Model.CAPACITIES[bus["kind"]]:
			return false
		total += bus["load"]
		initial_total += bus["capacity"]
		remaining[bus["color"]] += bus["capacity"] - bus["load"]
		if bus["status"] in ["arriving", "docked", "leaving"]:
			if bus["bay"] < 0 or bus["bay"] >= Model.BAY_COUNT or occupied.has(bus["bay"]) or model.bays[bus["bay"]] != bus["id"]:
				return false
			occupied.append(bus["bay"])
		elif bus["bay"] != -1:
			return false
	for material in model.queue:
		remaining[material] -= 1
	for count in remaining:
		if count != 0:
			return false
	return total + model.queue.size() == initial_total

func _test_dispatch_and_deadlock() -> void:
	var model = Model.new()
	check(not model.is_won(), "Uninitialized model cannot be won")
	model.load_level(3)
	var checkpoint: Dictionary = model.snapshot()
	var wrong: Array = []
	for bus in model.buses:
		if bus["color"] != model.queue[0] and model.can_dispatch(bus["id"]):
			wrong.append(bus["id"])
			check(model.dispatch(bus["id"]), "A free truck reserves a dock")
			if wrong.size() == Model.BAY_COUNT:
				break
	check(wrong.size() == Model.BAY_COUNT, "Level offers five wrong-material choices for a genuine deadlock")
	check(not model.is_stuck(), "Arriving animation is not a deadlock")
	check(model.snapshot().is_empty(), "Moving trucks cannot become an undo checkpoint")
	check(not model.can_dispatch(0), "Five reservations prevent a sixth truck from overbooking")
	for id in wrong:
		check(not model.board_one(id), "Moving trucks cannot load")
		check(model.arrive(id), "Arrival completes")
		check(not model.arrive(id), "Duplicate arrival rejected")
	check(model.is_stuck(), "Five wrong-material docks create a real deadlock")
	check(model.next_boarding() == -1, "The conveyor cannot skip its first material")
	check(model.find_hint() == -1, "A proven deadlock has no invented hint")
	check(_invariants(model), "Deadlock conserves every material unit")
	check(model.restore(checkpoint), "Undo recovers the original playable state from deadlock")
	check(model.snapshot() == checkpoint, "Undo exactly restores parking, conveyor and docks")
	check(not model.arrive(999) and not model.depart(-1) and not model.dispatch(999), "Invalid IDs are rejected")

func _test_material_and_bay_rules() -> void:
	var model = Model.new()
	model.level_index = 0
	model.buses = [_truck(0, Vector2(120, 550), 0.0, 0, 0),
		_truck(1, Vector2(270, 550), 0.0, 1, 0), _truck(2, Vector2(420, 550), 0.0, 2, 1)]
	model.queue = [0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
	model.dispatch(1)
	model.dispatch(0)
	model.arrive(0)
	model.board_one(0)
	model.arrive(1)
	check(model.bays == [1, 0, -1, -1, -1], "Different capacities reserve separate docks immediately")
	check(not model.board_one(1), "Wrong material cannot bypass the conveyor head")
	model.dispatch(2)
	model.arrive(2)
	for unit in range(6):
		check(model.next_boarding() == 2 and model.board_one(2), "The six-unit trailer loads exactly six matching units")
		check(_invariants(model), "Loading conserves materials and capacities")
	check(model.buses[2]["status"] == "leaving" and model.bays.has(2), "A full trailer retains its dock during departure")
	check(not model.board_one(2), "A full trailer cannot overfill")
	check(not model.is_won(), "Victory waits for physical departures")
	model.depart(2)
	check(model.next_boarding() == 0, "Partially filled van gets priority over an empty same-material tipper")
	model.board_one(0)
	model.depart(0)
	for unit in range(4):
		check(model.next_boarding() == 1 and model.board_one(1), "The four-unit tipper fills to its own capacity")
	check(not model.is_won(), "Last departure animation must finish before victory")
	model.depart(1)
	check(model.is_won() and model.bays == [-1, -1, -1, -1, -1], "All delivered materials and departed trucks complete the level")
	check(not model.is_stuck() and model.find_hint() == -1, "A won level needs neither recovery nor hint")

func _test_batch_loading() -> void:
	var model = Model.new()
	model.level_index = 0
	model.buses = [_truck(0, Vector2(120, 550), 0.0, 2, 1),
		_truck(1, Vector2(270, 550), 0.0, 0, 5)]
	model.queue = [1, 1, 1, 5, 5]
	model.dispatch(0)
	model.arrive(0)
	model.buses[0]["load"] = 3
	model.dispatch(1)
	model.arrive(1)
	var before: Dictionary = model.snapshot()
	check(model.batch_size(0) == 3, "Worker collects three consecutive bricks for three empty trailer places")
	check(model.snapshot() == before, "Preview and a cancelled pickup leave all cargo and vehicle state unchanged")
	check(model.batch_size(1) == 0 and not model.board_batch(1, 2), "Slate truck cannot skip bricks at the conveyor head")
	check(model.batch_size(-1) == 0 and model.batch_size(99) == 0, "Invalid IDs have no collectable batch")
	for count in [-1, 0, 4, 99]:
		check(not model.board_batch(0, count), "Invalid or oversize delivery is rejected before any mutation")
		check(model.snapshot() == before, "Rejected batch preserves queue, loads, statuses and dock reservations")
	check(not model.board_batch(99, 1) and model.snapshot() == before, "Invalid delivery target leaves all state unchanged")
	check(model.board_batch(0, 3), "Three bricks load in one delivery")
	check(model.buses[0]["load"] == 6 and model.buses[0]["status"] == "leaving", "Batch fills a partially loaded trailer exactly")
	check(model.queue == [5, 5] and model.bays.has(0), "Only the brick run is consumed and departure keeps its dock")
	check(model.next_boarding() == 1 and model.batch_size(1) == 2, "The next run is two slate packs for their matching van")
	check(model.board_batch(1, 2) and model.buses[1]["status"] == "leaving", "Worker delivers both slate packs together")
	check(_invariants(model), "Multiple material runs conserve every cargo unit")
	check(model.batch_size(0) == 0 and not model.board_batch(0, 1), "Empty conveyor and departing trucks cannot load")
	check(model.depart(0) and model.depart(1) and model.is_won(), "Batch deliveries complete a level only after departures")

	# A run may be longer than a truck, or shorter than the available space.
	model.buses = [_truck(0, Vector2(120, 550), 0.0, 0, 1)]
	model.buses[0]["status"] = "docked"
	model.buses[0]["bay"] = 0
	model.bays = [0, -1, -1, -1, -1]
	model.queue = [1, 1, 1, 1, 5]
	check(model.batch_size(0) == 2, "Collection is capped at the smaller van capacity")
	before = model.snapshot()
	check(not model.board_batch(0, 3) and model.snapshot() == before, "An oversized same-material batch cannot overfill the van")
	check(model.board_batch(0, 2) and model.queue == [1, 1, 5], "Extra matching cargo remains for a later truck")
	model.buses[0]["kind"] = 2
	model.buses[0]["capacity"] = 6
	model.buses[0]["load"] = 0
	model.buses[0]["status"] = "docked"
	check(model.batch_size(0) == 2, "Material change stops collection even when four more places are free")
	check(model.board_batch(0, 2) and model.buses[0]["load"] == 2 and model.buses[0]["status"] == "docked",
		"A shorter run leaves the truck docked with its partially filled load")
	model.queue = [1, 1]
	for status in ["yard", "arriving", "leaving", "gone"]:
		model.buses[0]["status"] = status
		var saved_buses: Array = model.buses.duplicate(true)
		check(model.batch_size(0) == 0 and not model.board_batch(0, 1), "Only docked trucks can receive a batch")
		check(model.buses == saved_buses and model.queue == [1, 1], "Rejected status keeps queue and truck unchanged")

func _test_snapshot_validation() -> void:
	var model = Model.new()
	model.load_level(2)
	var original: Dictionary = model.snapshot()
	var invalid: Dictionary = original.duplicate(true)
	invalid["bays"][0] = 0
	check(not model.restore(invalid), "Dangling bay rejected")
	invalid = original.duplicate(true)
	invalid["buses"][0]["load"] = 1
	check(not model.restore(invalid), "Wrong cargo totals rejected")
	invalid = original.duplicate(true)
	invalid["buses"][0]["capacity"] = 100
	check(not model.restore(invalid), "Changed vehicle capacity rejected")
	invalid = original.duplicate(true)
	invalid["buses"][0]["angle"] += 0.1
	check(not model.restore(invalid), "Changed parking geometry rejected")
	invalid = original.duplicate(true)
	invalid["queue"][0] = 9
	check(not model.restore(invalid), "Unknown building material rejected")
	invalid = original.duplicate(true)
	invalid["queue"].reverse()
	check(not model.restore(invalid), "Reordered conveyor rejected")
	for bus in model.buses:
		if not model.blocking_ids(bus["id"]).is_empty():
			invalid = original.duplicate(true)
			invalid["buses"][bus["id"]]["status"] = "docked"
			invalid["buses"][bus["id"]]["bay"] = 0
			invalid["bays"][0] = bus["id"]
			check(not model.restore(invalid), "A snapshot cannot teleport a blocked truck through another")
			break
	invalid = original.duplicate(true)
	invalid["buses"][0]["status"] = "arriving"
	check(not model.restore(invalid), "In-progress animation snapshot rejected")
	check(not model.restore({}) and not model.load_level(-1) and not model.load_level(99), "Invalid level and incomplete checkpoint rejected")
	check(model.snapshot() == original, "Rejected restores leave live state unchanged")
	check(model.restore(original), "A valid checkpoint restores")
	original["buses"][0]["load"] = 2
	check(model.buses[0]["load"] == 0, "Restored dictionaries do not alias the checkpoint")

func _drain(model) -> void:
	var id: int = model.next_boarding()
	while id != -1:
		check(model.board_one(id), "Matching material loads")
		check(_invariants(model), "Each loading step preserves material conservation")
		if model.buses[id]["status"] == "leaving":
			check(model.depart(id), "A full truck leaves")
		id = model.next_boarding()

func _test_every_level() -> void:
	var model = Model.new()
	check(model.level_count() == 6, "Six construction levels are available")
	for level in range(model.level_count()):
		model.load_level(level)
		check(model.buses.size() == Model.LEVELS[level]["count"], "Level has the intended dense fleet size")
		check(_invariants(model), "Initial fleet capacities exactly match the conveyor")
		var types: Array = []
		var materials: Array = []
		var directions: Array = []
		var blocked := 0
		for bus in model.buses:
			if not types.has(bus["kind"]):
				types.append(bus["kind"])
			if not materials.has(bus["color"]):
				materials.append(bus["color"])
			var angle: int = posmod(roundi(bus["angle"] / (PI / 4)), 8)
			if not directions.has(angle):
				directions.append(angle)
			if not model.blocking_ids(bus["id"]).is_empty():
				blocked += 1
			for other in model.buses:
				if bus["id"] != other["id"]:
					check(not model._footprints_overlap(bus, other), "Parked oriented truck bodies never overlap")
		check(types.size() == 3 and materials.size() == 6, "Each level offers all three vehicle classes and six materials")
		check(directions.size() >= 5, "Each level uses varied cardinal and diagonal exit directions")
		check(blocked >= 2, "Each level contains real blocking dependencies")
		for step in range(model.buses.size()):
			var before: Dictionary = model.snapshot()
			var started := Time.get_ticks_usec()
			var id: int = model.find_hint()
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			max_hint_ms = maxf(max_hint_ms, elapsed)
			check(model.snapshot() == before, "Hint leaves all gameplay state unchanged")
			check(id >= 0 and model.can_dispatch(id), "Level %d hint identifies a legal solvable move" % (level + 1))
			if id < 0:
				break
			model.dispatch(id)
			check(_invariants(model), "Dispatch conserves dock reservations and materials")
			model.arrive(id)
			_drain(model)
		check(model.is_won(), "Following hints completes level %d" % (level + 1))
	check(max_hint_ms < 150.0, "Hints stay within a responsive desktop time budget")

func _test_batch_equivalence_every_level() -> void:
	# The generated layout certifies that ascending IDs form a legal complete
	# solution. Compare each batch against the established single-unit rules.
	var singles = Model.new()
	var batches = Model.new()
	var multiple_deliveries := 0
	for level in range(singles.level_count()):
		singles.load_level(level)
		batches.load_level(level)
		for truck_id in range(singles.buses.size()):
			check(singles.dispatch(truck_id) and batches.dispatch(truck_id), "Certified solution dispatches in both loading modes")
			check(singles.arrive(truck_id) and batches.arrive(truck_id), "Both modes dock the same truck")
			var id: int = batches.next_boarding()
			while id != -1:
				var count: int = batches.batch_size(id)
				check(count > 0, "Every selected truck has a positive batch")
				if count <= 0:
					break
				if count > 1:
					multiple_deliveries += 1
				check(batches.board_batch(id, count), "Every valid reserved batch commits in full")
				for unit in range(count):
					check(singles.next_boarding() == id and singles.board_one(id), "Batch target agrees with every sequential single-unit selection")
				check(batches.buses == singles.buses and batches.queue == singles.queue and batches.bays == singles.bays,
					"Batch and single-unit loading produce identical cargo, vehicles and dock states")
				check(_invariants(batches), "Batch loading preserves capacity and material conservation across complete levels")
				if batches.buses[id]["status"] == "leaving":
					check(batches.depart(id) and singles.depart(id), "Both loading modes release the same full truck")
				id = batches.next_boarding()
		check(batches.is_won() and singles.is_won(), "Batch loading completes construction level %d with the same final state" % (level + 1))
	check(multiple_deliveries >= 6, "Complete-level coverage exercises multiple-item deliveries")
