extends SceneTree

const Model = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
var total_trucks := 0
var total_cargo := 0
var max_hint_ms := 0.0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	check(Model.WIDTHS == [56.0, 56.0, 56.0], "Every truck uses the same measured width")
	check(Model.LENGTHS == [98.24, 139.37, 182.79], "Truck lengths preserve measured capacity proportions")
	var headings: Dictionary = {}
	for level in range(Model.LEVELS.size()):
		var model = Model.new()
		check(model.load_level(level), "Factory level loads")
		total_trucks += model.buses.size()
		total_cargo += model.queue.size()
		var initial_cargo: int = model.queue.size()
		for bus: Dictionary in model.buses:
			headings[roundi(float(bus["angle"]) / (PI / 4.0)) % 8] = true
			var size: Vector2 = model.vehicle_size(bus)
			var forward: Vector2 = model.forward(bus)
			var side := Vector2(-forward.y, forward.x)
			for x in [-1, 1]:
				for y in [-1, 1]:
					var corner: Vector2 = bus["position"] + side * size.x * 0.5 * x + forward * size.y * 0.5 * y
					check(Model.YARD_RECT.grow(0.01).has_point(corner), "Every rotated body stays inside the parking field")
			for other: Dictionary in model.buses:
				if other["id"] <= bus["id"]:
					continue
				check(not model._footprints_overlap(bus, other), "Parked truck bodies never overlap")
				check(not model._rectangles_overlap(bus["position"], forward, size + Vector2(3.8, 3.8),
					other["position"], model.forward(other), model.vehicle_size(other) + Vector2(3.8, 3.8)),
					"Packed trucks retain at least a small visible clearance")
		# The authored ascending order is a geometric certificate independently of loading.
		var certificate = Model.new()
		certificate.load_level(level)
		for id in range(certificate.buses.size()):
			check(certificate.blocking_ids(id).is_empty(), "The certified removal order is physically clear")
			certificate.buses[id]["status"] = "gone"
		var moves := 0
		var loaded := 0
		while not model.is_won() and moves < model.buses.size() + 1:
			var before := Time.get_ticks_usec()
			var id: int = model.find_hint()
			max_hint_ms = maxf(max_hint_ms, (Time.get_ticks_usec() - before) / 1000.0)
			check(id >= 0, "Every reachable certified state has a hint")
			if id < 0:
				break
			check(model.dispatch(id) and model.arrive(id), "A hinted truck reaches a free dock")
			while model.next_boarding() >= 0:
				var boarding: int = model.next_boarding()
				var count: int = model.batch_size(boarding)
				check(count > 0 and model.board_batch(boarding, count), "Consecutive materials load up to the free capacity")
				loaded += count
				if model.get_bus(boarding)["status"] == "leaving":
					check(model.depart(boarding), "A full truck releases its dock")
			var snapshot: Dictionary = model.snapshot()
			check(not snapshot.is_empty() and model.restore(snapshot), "Undo snapshots validate after each settled move")
			moves += 1
		check(model.is_won(), "Every factory level can be completed")
		check(loaded == initial_cargo, "Every cargo item is delivered exactly once")
	check(headings.size() == 8, "The six layouts include all eight departure directions")
	print("Factory geometry checks: %d; trucks: %d; cargo: %d; max hint: %.2f ms; failures: %d" %
		[checks, total_trucks, total_cargo, max_hint_ms, failures])
	quit(0 if failures == 0 else 1)
