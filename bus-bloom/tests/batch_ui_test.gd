extends SceneTree

const Game = preload("res://scripts/main.gd")
const Model = preload("res://scripts/game_model.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _wait_until(predicate: Callable, label: String, seconds := 15.0) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < limit:
		await process_frame
	var reached: bool = predicate.call()
	check(reached, label)
	return reached

func _truck(id: int, material: int, kind: int, load: int) -> Dictionary:
	return {"id": id, "position": Vector2(120 + id * 150, 550), "angle": 0.0,
		"kind": kind, "color": material, "capacity": Model.CAPACITIES[kind],
		"load": load, "status": "docked", "bay": id}

func _fixture(capacity_split := false) -> void:
	game._load_level(0)
	game.automation = true
	game.save_enabled = false
	game.sound_enabled = false
	game.reduced_motion = false
	game.speed_factor = 1.0
	if capacity_split:
		game.model.buses = [_truck(0, 1, 0, 0), _truck(1, 1, 1, 0)]
		game.model.queue = [1, 1, 1, 1, 1, 1]
		game.boarded = 0
		game.total_passengers = 6
	else:
		game.model.buses = [_truck(0, 1, 2, 3), _truck(1, 5, 0, 0)]
		game.model.queue = [1, 1, 1, 5, 5]
		game.boarded = 3
		game.total_passengers = 8
	game.model.bays = [0, 1, -1, -1, -1]
	game._sync_visuals()

func _observe_brick_collection() -> void:
	var stop_indices: Array[int] = []
	var stop_positions: Array[Vector2] = []
	var stop_frames: Array[int] = [0, 0, 0]
	var picked_counts: Array[int] = [0]
	var all_stopped := true
	var all_cargo_reserved := true
	var limit := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < limit:
		var picked: int = game.worker_batch_count
		if picked != picked_counts.back(): picked_counts.append(picked)
		if game.collecting and game.worker_carry == 1:
			all_stopped = all_stopped and not game.worker_walking
			if picked >= 0 and picked < 3:
				stop_frames[picked] += 1
				if not stop_indices.has(picked):
					stop_indices.append(picked)
					stop_positions.append(game.worker_position)
				else:
					all_stopped = all_stopped and game.worker_position.distance_to(stop_positions[stop_indices.find(picked)]) < 0.1
		all_cargo_reserved = all_cargo_reserved and game.model.queue == [1, 1, 1, 5, 5] and game.boarded == 3 and game.model.get_bus(0).load == 3
		if picked == 3 and game.worker_walking and not game.collecting: break
		await process_frame
	check(stop_indices == [0, 1, 2], "The worker stops separately at each of the three consecutive bricks")
	check(picked_counts == [0, 1, 2, 3], "The carried stack grows by one item after each pickup")
	check(all_stopped, "Each individual pickup is performed with the walking animation stopped")
	check(stop_frames.min() >= 2, "Every pickup stop persists for multiple rendered frames")
	if stop_positions.size() == 3:
		check(stop_positions[0].distance_to(stop_positions[1]) >= 40.0 and
			stop_positions[1].distance_to(stop_positions[2]) >= 40.0,
			"The worker walks between distinct item positions instead of taking the whole run from one place")
		for i in stop_positions.size():
			check(stop_positions[i].distance_to(Vector2(468 - i * 60, 185)) < 0.1,
				"Pickup %d takes place beside its own conveyor item" % (i + 1))
	check(all_cargo_reserved, "All individual pickups reserve cargo until the complete batch reaches its truck")

func _settle_fixture() -> void:
	var ticket: int = game.generation
	game.busy = true
	await game._settle(ticket)
	if ticket != game.generation:
		return
	game.busy = false
	game._check_end()

func _run() -> void:
	root.size = Vector2i(540, 1171)
	game = Game.new()
	root.add_child(game)
	_fixture()
	await process_frame
	var baseline_nodes: int = get_node_count()
	print("CARGO_BATCH_UI_START")

	_settle_fixture()
	await _observe_brick_collection()
	if await _wait_until(func(): return game.worker_batch_count == 3 and game.worker_walking and game.worker_carry == 1,
		"Worker carries all three consecutive bricks in one trip"):
		check(game.model.queue == [1, 1, 1, 5, 5] and game.model.get_bus(0).load == 3 and game.boarded == 3,
			"Pickup and walking reserve the batch visually without committing cargo early")
		game._open_settings()
		var position: Vector2 = game.worker_position
		var pickup: float = game.batch_pickup
		var elapsed: float = game.elapsed
		await create_timer(0.18).timeout
		check(game.worker_position == position and game.worker_batch_count == 3 and game.worker_carry == 1 and
			game.batch_pickup == pickup and game.elapsed == elapsed and game.model.queue == [1, 1, 1, 5, 5] and game.boarded == 3,
			"Pausing a three-unit delivery freezes the complete stack, animation and cargo accounting")
		game._resume()
	if await _wait_until(func(): return game.boarded == 6, "All three bricks commit together when the worker reaches the trailer"):
		check(game.model.queue == [5, 5] and game.model.get_bus(0).load == 6 and game.model.get_bus(0).status == "leaving",
			"Dropping one stack consumes precisely the brick run and fills the trailer")
		check(game.worker_carry == -1 and game.worker_batch_count == 0,
			"Delivered cargo clears the worker stack before the next collection")
	if await _wait_until(func(): return game.worker_batch_count == 2 and game.worker_carry == 5 and game.worker_walking,
		"Worker switches to both consecutive slate packs for the matching van"):
		check(game.model.queue == [5, 5] and game.model.get_bus(1).load == 0 and game.boarded == 6,
			"Different materials never share a carried batch and slate remains uncommitted during transport")
	await _wait_until(func(): return not game.busy, "Both complete batches finish their loading and departure animations")
	check(game.model.is_won() and game.boarded == 8 and game.worker_batch_count == 0 and game.worker_carry == -1,
		"Two stack deliveries preserve totals and finish only after both trucks depart")
	check(game.cargo_trips == 2, "Three bricks followed by two slate packs require exactly two worker trips")

	_fixture()
	_settle_fixture()
	if await _wait_until(func(): return game.collecting and game.worker_batch_count == 1 and game.batch_pickup > 0.0 and game.batch_pickup < 1.0,
		"Restart fixture reaches the middle of picking up the second brick"):
		check(game.model.queue == [1, 1, 1, 5, 5] and game.boarded == 3,
			"The model is unchanged while items are still being gathered")
		game._open_settings()
		var pickup_position: Vector2 = game.worker_position
		var pickup_progress: float = game.batch_pickup
		var pickup_elapsed: float = game.elapsed
		await create_timer(0.18).timeout
		check(game.worker_position == pickup_position and game.batch_pickup == pickup_progress and game.elapsed == pickup_elapsed and
			game.collecting and not game.worker_walking and game.worker_batch_count == 1 and game.model.queue == [1, 1, 1, 5, 5],
			"Pause freezes a single-item pickup while preserving the previously collected brick")
		game._on_menu_action("restart")
		var restarted: Dictionary = game.model.snapshot()
		await create_timer(0.75).timeout
		check(game.model.snapshot() == restarted and game.worker_batch_count == 0 and game.batch_pickup == 0.0 and
			game.worker_carry == -1 and game.boarded == 0 and not game.busy and not game.worker_walking and not game.collecting,
			"Restart cancels an unfinished pickup without stale callbacks consuming the new conveyor")
		check(game.active_tween == null and game.paused_tween == null and get_node_count() == baseline_nodes,
			"Cancelled multi-item pickup clears paused animation state and releases its scene resources")
		check(game.cargo_trips == 0, "A cancelled pickup never counts as a completed delivery")

	_fixture(true)
	_settle_fixture()
	if await _wait_until(func(): return game.worker_batch_count == 2 and game.worker_carry == 1 and game.worker_walking,
		"The first collection respects a two-place van despite six identical items in a row"):
		check(game.model.queue.size() == 6 and game.model.get_bus(0).load == 0,
			"Capacity-limited cargo is also committed only at drop-off")
	if await _wait_until(func(): return game.worker_batch_count == 4 and game.worker_carry == 1 and game.worker_walking,
		"Worker collects the remaining four items for the next four-place truck"):
		check(game.boarded == 2 and game.model.queue == [1, 1, 1, 1] and game.model.get_bus(0).status == "gone",
			"First capacity-limited delivery leaves the remainder intact for its next truck")
	await _wait_until(func(): return not game.busy, "Both capacity-limited trips finish")
	check(game.model.is_won() and game.boarded == 6 and game.worker_batch_count == 0,
		"Splitting a long material run fills both vehicles exactly without duplicated or lost cargo")
	check(game.cargo_trips == 2, "Six identical cargo items use two capacity-limited trips instead of six single-unit trips")
	game._cancel_animation()
	print("Cargo batch UI checks: %d; failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
