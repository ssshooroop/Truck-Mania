extends SceneTree

const Game = preload("res://scripts/main.gd")
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

func _wait_until(predicate: Callable, label: String, seconds := 12.0) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < limit:
		await process_frame
	var reached: bool = predicate.call()
	check(reached, label)
	return reached

func _tap(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = position
	release.pressed = false
	Input.parse_input_event(release)

func _fresh(index := 0) -> void:
	game._load_level(index)
	game.automation = true
	game.save_enabled = false
	game.sound_enabled = false
	game.reduced_motion = true

func _blocked_id() -> int:
	for bus in game.model.buses:
		if not game.model.blocking_ids(bus.id).is_empty(): return bus.id
	return -1

func _diagonal_id() -> int:
	for bus in game.model.buses:
		var direction: Vector2 = game.model.forward(bus)
		if absf(direction.x) > 0.1 and absf(direction.y) > 0.1 and game.model.can_dispatch(bus.id):
			return bus.id
	return -1

func _rotated_touch_point(id: int) -> Vector2:
	var bus: Dictionary = game.model.get_bus(id)
	var size: Vector2 = game.model.vehicle_size(bus)
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var offset := Vector2(size.x * 0.42 * sx, size.y * 0.42 * sy).rotated(bus.angle)
			if absf(offset.x) > size.x * 0.5 or absf(offset.y) > size.y * 0.5:
				return bus.position + offset
	return bus.position

func _leaving_id() -> int:
	for bus in game.model.buses:
		if bus.status == "leaving": return bus.id
	return -1

func _restart_from_settings() -> void:
	game._open_settings()
	game._overlay_input(Vector2(270,620))

func _run() -> void:
	root.size = Vector2i(540,1171)
	game = Game.new()
	root.add_child(game)
	_fresh()
	await process_frame
	var baseline_nodes: int = get_node_count()
	print("CARGO_UI_LIFECYCLE_START")
	check(game.model.bays.size() == 5, "The factory layout provides five loading bays")
	_tap(Vector2(500,40))
	await process_frame
	check(game.overlay == "settings", "The compact top pause control responds to phone touch")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.overlay == "", "Android Back resumes after using the compact pause control")
	_tap(Vector2(270,1130))
	await process_frame
	check(game.hint_bus >= 0 and game.model.can_dispatch(game.hint_bus),
		"The compact bottom hint control highlights a truck that can leave")
	_fresh()

	var blocked := _blocked_id()
	check(blocked >= 0, "The parking fixture contains a geometrically blocked truck")
	if blocked >= 0:
		var before_blocked: Dictionary = game.model.snapshot()
		_tap(game.model.get_bus(blocked).position)
		await process_frame
		await _wait_until(func(): return not game.road_busy, "Blocked truck returns after visible contact")
		check(game.model.snapshot() == before_blocked and game.moves == 0 and not game.busy,
			"Touching a blocked truck leaves the parking, conveyor, and move count unchanged")
		check(game.history.is_empty() and game.rejected_bus == blocked and not game.blockers.is_empty(),
			"Blocked touch identifies the obstacle without recording an undo step")

	var diagonal := _diagonal_id()
	check(diagonal >= 0, "The parking fixture contains a freely departing diagonal truck")
	if diagonal >= 0:
		var position := _rotated_touch_point(diagonal)
		var offset: Vector2 = position - game.model.get_bus(diagonal).position
		var size: Vector2 = game.model.vehicle_size(game.model.get_bus(diagonal))
		check(absf(offset.x) > size.x * 0.5 or absf(offset.y) > size.y * 0.5,
			"Touch fixture lies inside the rotated body and outside its unrotated rectangle")
		_tap(position)
		await process_frame
		check(game.moves == 1 and game.busy and game.model.get_bus(diagonal).status == "arriving",
			"Emulated phone touch dispatches the diagonal truck through its rotated hit area")
		_tap(game.model.get_bus((diagonal + 1) % game.model.buses.size()).position)
		await process_frame
		check(game.moves == 1 and game.history.size() == 1,
			"A second touch cannot dispatch another truck during an active move")
		await _wait_until(func(): return not game.busy, "Diagonal touch dispatch finishes")

	_fresh()
	var initial_state: Dictionary = game.model.snapshot()
	var initial_units: int = game.model.queue.size()
	game._dispatch(0)
	check(game.model.bays[0] == 0 and game.busy and game.model.get_bus(0).status == "arriving",
		"Dispatch reserves a loading bay before the truck starts driving")
	game.automation = false
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	game.automation = true
	var paused_position: Vector2 = game.bus_visuals[0].position
	var paused_queue: Array = game.model.queue.duplicate()
	await create_timer(0.12).timeout
	check(game.overlay == "settings", "Backgrounding opens pause settings")
	check(game.bus_visuals[0].position == paused_position and game.model.queue == paused_queue,
		"Background pause freezes the driving truck and conveyor queue")
	game._resume()
	await _wait_until(func(): return not game.busy, "Arrival and initial loading finish after resume")
	check(game.boarded > 0 and game.boarded == initial_units - game.model.queue.size(),
		"Resuming preserves the number of transferred material units")
	check(game.history.size() == 1, "One completed dispatch creates one undo checkpoint")
	game._undo()
	check(game.moves == 0 and game.boarded == 0 and game.model.snapshot() == initial_state,
		"Undo restores the whole parking layout, cargo queue, load counters, and loading bays")

	game._dispatch(0)
	await create_timer(0.02).timeout
	_restart_from_settings()
	var fresh_state: Dictionary = game.model.snapshot()
	await create_timer(0.50).timeout
	check(game.model.snapshot() == fresh_state and not game.busy and game.moves == 0,
		"Restart during driving prevents callbacks from changing the new level")
	check(game.history.is_empty() and game.active_tween == null and get_node_count() == baseline_nodes,
		"Driving restart clears undo and animation state without leaking scene nodes")

	game._dispatch(0)
	if await _wait_until(func(): return game.worker_carry >= 0 and game.worker_batch_count > 0 and game.worker_walking and not game.collecting,
		"The worker takes a material batch and carries it toward a matching truck"):
		game._open_settings()
		var worker_position: Vector2 = game.worker_position
		var carried: int = game.worker_carry
		var carried_count: int = game.worker_batch_count
		var queue_during_carry: Array = game.model.queue.duplicate()
		var boarded_during_carry: int = game.boarded
		await create_timer(0.12).timeout
		check(game.worker_position == worker_position and game.worker_carry == carried and game.worker_batch_count == carried_count and
			game.model.queue == queue_during_carry and game.boarded == boarded_during_carry,
			"Pause freezes the walking worker, carried material batch, and cargo accounting")
		game._resume()
	await _wait_until(func(): return not game.busy, "Worker loading resumes after pause")
	check(game.worker_carry == -1 and game.worker_batch_count == 0 and not game.worker_walking and
		game.boarded == initial_units - game.model.queue.size(),
		"Finishing loading clears the carried object and preserves cargo accounting")

	_fresh()
	game._dispatch(0)
	await _wait_until(func(): return game.worker_carry >= 0, "A material is being carried before restart")
	_restart_from_settings()
	fresh_state = game.model.snapshot()
	await create_timer(0.65).timeout
	check(game.model.snapshot() == fresh_state and game.worker_carry == -1 and game.worker_batch_count == 0 and game.batch_pickup == 0.0 and
		game.boarded == 0 and not game.worker_walking and not game.collecting and not game.busy,
		"Restart while carrying cannot move cargo into or remove cargo from the new level")
	check(game.active_tween == null and game.paused_tween == null and get_node_count() == baseline_nodes,
		"Worker restart clears paused animations without leaking scene nodes")

	_fresh()
	game._dispatch(0)
	await _wait_until(func(): return not game.busy, "First truck waits for its next material batch")
	game._dispatch(1)
	if await _wait_until(func(): return _leaving_id() >= 0, "A full truck begins its animated departure"):
		var leaving := _leaving_id()
		var departure_bay: int = game.model.get_bus(leaving).bay
		game._open_settings()
		var departure_position: Vector2 = game.bus_visuals[leaving].position
		await create_timer(0.12).timeout
		check(game.model.bays[departure_bay] == leaving and game.bus_visuals[leaving].position == departure_position,
			"Pausing a full truck preserves its loading-bay reservation and departure position")
		game._resume()
		await _wait_until(func(): return not game.busy, "Full departure and remaining loading resume")
		check(game.model.get_bus(leaving).status == "gone" and game.model.bays[departure_bay] == -1,
			"Completing departure frees its bay only after the truck leaves")
		var first_batch_units: int = game.model.get_bus(0).capacity + game.model.get_bus(1).capacity
		check(game.boarded == first_batch_units and game.model.queue.size() == initial_units - first_batch_units,
			"Two differently sized trucks receive exactly their combined capacity")

	game._open_settings()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.overlay == "", "Android Back resumes paused play")
	check(not quit_on_go_back, "Android Back automatic quit is disabled")
	game._open_settings()
	game._overlay_input(Vector2(270,689))
	check(game.overlay == "road_menu" and game.road_menu.visible, "The settings level button opens the road menu")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.overlay == "", "Android Back returns from the road menu to paused play")

	_fresh(5)
	for id in range(game.model.buses.size()):
		check(game.model.dispatch(id), "Certified final-level truck can dispatch: %d" % id)
		game.model.arrive(id)
		var loading: int = game.model.next_boarding()
		while loading >= 0:
			game.model.board_one(loading)
			game.boarded += 1
			if game.model.get_bus(loading).status == "leaving": game.model.depart(loading)
			loading = game.model.next_boarding()
	game._sync_visuals()
	game._check_end()
	check(game.overlay == "win", "The completed final construction level shows victory")
	game._overlay_input(Vector2(270,601))
	check(game.overlay == "road_menu", "Final victory opens the road menu")
	game._open_settings()
	check(game.overlay == "settings", "Final-victory road menu can open settings")
	game._resume()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.overlay == "road_menu", "Android Back keeps the main menu after final victory")
	game.road_menu.level_selected.emit(0)
	check(game.overlay == "" and game.model.level_index == 0 and not game.busy,
		"Selecting an unlocked level after victory starts fresh play")
	game._cancel_animation()
	print("Cargo UI lifecycle checks: %d; failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
