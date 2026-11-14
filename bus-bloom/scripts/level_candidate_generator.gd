class_name LevelCandidateGenerator
extends RefCounted

## Offline candidate generator for Truck Mania / Cargo Yard (Godot 4.5).
## Generates geometry-valid candidates. It does NOT certify solvability.
## Feed the results into LevelSolver / LevelEvaluator before shipping any level.

const GameModel = preload("res://scripts/game_model.gd")
const KINDS := [0, 1, 2]
const DIRECTIONS := 8

var rng := RandomNumberGenerator.new()
var model = GameModel.new()

## queue_window: how many consecutive trucks of the dispatch order share the
## conveyor at once. 1 gives contiguous cargo per truck (solvable with one
## slot); a wider window interleaves cargo and needs up to that many slots.
## max_run: the longest uninterrupted run of one truck's cargo in the queue.
## same_color_chance: probability that a truck joining the window copies the
## colour of a truck already in it. Two open trucks of one colour make the
## dispatch order a decision (cargo goes to the fuller one) and break the
## window certificate; 0 keeps window colours distinct where colours allow.
func generate(level_seed: int, vehicle_count: int = 10, color_count: int = 4,
		placement_attempts: int = 2500, queue_window: int = 1, max_run: int = 3,
		same_color_chance: float = 0.0, compact_rounds: int = 0) -> Dictionary:
	assert(vehicle_count >= 1 and vehicle_count <= 30)
	assert(color_count >= 1 and color_count <= GameModel.COLORS)
	rng.seed = level_seed
	var vehicles: Array = []
	# blockers[i]: bitmask of placed vehicles in the exit sweep of vehicle i.
	var blockers: Array = []
	var attempts := 0
	# Dense layouts: when random placement stalls, slide the placed trucks
	# towards a corner (keeping the blocking graph acyclic) and place more
	# trucks into the freed space, up to compact_rounds times.
	var budget := placement_attempts
	var rounds_left := maxi(0, compact_rounds)
	while true:
		while vehicles.size() < vehicle_count and attempts < budget:
			attempts += 1
			_try_place(vehicles, blockers, color_count)
		if vehicles.size() >= vehicle_count or rounds_left == 0:
			break
		rounds_left -= 1
		_compact(vehicles, blockers)
		budget += placement_attempts
	if vehicles.size() != vehicle_count:
		return {"ok": false, "seed": level_seed, "reason": "placement_exhausted",
			"placed": vehicles.size(), "attempts": attempts}
	return _finish(level_seed, vehicles, vehicle_count, color_count, attempts, queue_window,
		max_run, same_color_chance)

## One random placement attempt; appends the truck when it fits.
func _try_place(vehicles: Array, blockers: Array, color_count: int) -> void:
	var kind: int = KINDS[rng.randi_range(0, KINDS.size() - 1)]
	var heading: int = rng.randi_range(0, DIRECTIONS - 1)
	var angle: float = heading * PI / 4.0
	var size: Vector2 = Vector2(GameModel.WIDTHS[kind], GameModel.LENGTHS[kind])
	# Sample a centre, then reject any rotated body that crosses the yard.
	var centre := Vector2(
		rng.randf_range(GameModel.YARD_RECT.position.x, GameModel.YARD_RECT.end.x),
		rng.randf_range(GameModel.YARD_RECT.position.y, GameModel.YARD_RECT.end.y))
	var vehicle := {
		"id": vehicles.size(),
		"color": rng.randi_range(0, color_count - 1),
		"position": centre,
		"angle": angle,
		"kind": kind,
		"capacity": GameModel.CAPACITIES[kind],
		"load": 0,
		"status": "yard",
		"bay": -1
	}
	if not _inside_yard(vehicle, size):
		return
	var valid := true
	for other: Dictionary in vehicles:
		# Reuse the production SAT collision test, with a small safety margin.
		if model._rectangles_overlap(vehicle.position, model.forward(vehicle), size + Vector2(4, 4),
				other.position, model.forward(other), model.vehicle_size(other) + Vector2(4, 4)):
			valid = false
			break
	if valid:
		valid = _add_without_cycle(vehicle, vehicles, blockers)
	if valid:
		vehicles.append(vehicle)

func _finish(level_seed: int, vehicles: Array, vehicle_count: int, color_count: int, attempts: int,
		queue_window: int, max_run: int, same_color_chance: float) -> Dictionary:
	# Choose an order that respects all forward-sweep blockers.
	# A cycle means no geometrically valid complete dispatch order exists.
	var remaining: Array = []
	for id in vehicle_count:
		remaining.append(id)
	var order: Array = []
	while not remaining.is_empty():
		var available: Array = []
		for id: int in remaining:
			var blocked := false
			for other_id: int in remaining:
				if other_id != id and model._sweep_hits(vehicles[id], vehicles[other_id]):
					blocked = true
					break
			if not blocked:
				available.append(id)
		if available.is_empty():
			return {"ok": false, "seed": level_seed, "reason": "blocking_cycle",
				"placed": vehicle_count}
		var chosen: int = available[rng.randi_range(0, available.size() - 1)]
		order.append(chosen)
		remaining.erase(chosen)

	# Construct FIFO cargo in dispatch order, interleaving at most queue_window
	# trucks at a time. With distinct window colours, dispatching in this order
	# with queue_window free slots wins; LevelSolver rechecks every candidate.
	var window := maxi(1, queue_window)
	var overlaps := [0]
	var cargo := _build_queue(vehicles, order, window, maxi(1, max_run), color_count,
		clampf(same_color_chance, 0.0, 1.0), overlaps)

	return {
		"ok": true,
		"seed": level_seed,
		"vehicles": vehicles,
		"queue": cargo,
		"dispatch_order": order,
		"metrics": {
			"vehicle_count": vehicle_count,
			"cargo_count": cargo.size(),
			"color_count": color_count,
			"queue_window": window,
			"color_switches": _count_switches(cargo),
			"same_color_chance": snappedf(same_color_chance, 0.01),
			"same_color_overlaps": overlaps[0],
			"placement_attempts": attempts,
			"initially_dispatchable": _count_initially_dispatchable(vehicles)
		}
	}

## Slides every truck towards a random yard corner in shrinking steps. A move
## is kept only if the truck stays inside the yard, overlaps nothing and the
## blocking graph stays acyclic; blockers is rebuilt for the moved truck.
func _compact(vehicles: Array, blockers: Array) -> void:
	var yard: Rect2 = GameModel.YARD_RECT
	var corner := Vector2(yard.position.x if rng.randf() < 0.5 else yard.end.x,
		yard.position.y if rng.randf() < 0.5 else yard.end.y)
	for step: float in [8.0, 4.0, 2.0, 1.0]:
		for iteration in 25:
			var changed := false
			for vehicle: Dictionary in vehicles:
				var start: Vector2 = vehicle.position
				var delta: Vector2 = corner - start
				for move: Vector2 in [delta.normalized() * step, Vector2(signf(delta.x) * step, 0.0),
						Vector2(0.0, signf(delta.y) * step)]:
					if move == Vector2.ZERO:
						continue
					vehicle.position = start + move
					if _fits(vehicle, vehicles) and _rebuild_blockers(vehicle, vehicles, blockers):
						changed = true
						break
					vehicle.position = start
				if vehicle.position == start:
					_rebuild_blockers(vehicle, vehicles, blockers)
			if not changed:
				break

func _fits(vehicle: Dictionary, vehicles: Array) -> bool:
	var size: Vector2 = model.vehicle_size(vehicle)
	if not _inside_yard(vehicle, size):
		return false
	for other: Dictionary in vehicles:
		if other.id != vehicle.id and model._rectangles_overlap(vehicle.position, model.forward(vehicle),
				size + Vector2(4, 4), other.position, model.forward(other),
				model.vehicle_size(other) + Vector2(4, 4)):
			return false
	return true

## Recomputes the blocking bits of `vehicle` at its current position. Returns
## false (leaving blockers unchanged) if that would create a blocking cycle.
func _rebuild_blockers(vehicle: Dictionary, vehicles: Array, blockers: Array) -> bool:
	var index: int = vehicle.id
	var updated := blockers.duplicate()
	var own := 0
	for other: Dictionary in vehicles:
		var id: int = other.id
		if id == index:
			continue
		if model._sweep_hits(vehicle, other):
			own |= 1 << id
		if model._sweep_hits(other, vehicle):
			updated[id] = int(updated[id]) | (1 << index)
		else:
			updated[id] = int(updated[id]) & ~(1 << index)
	updated[index] = own
	var remaining := (1 << vehicles.size()) - 1
	while remaining != 0:
		var free := 0
		for id in vehicles.size():
			if (remaining >> id) & 1 == 1 and (int(updated[id]) & remaining) == 0:
				free |= 1 << id
		if free == 0:
			return false
		remaining &= ~free
	for id in vehicles.size():
		blockers[id] = updated[id]
	return true

## Accepts a placement only if the blocking graph stays acyclic, so every
## finished layout has a complete dispatch order. Updates blockers on success.
func _add_without_cycle(vehicle: Dictionary, vehicles: Array, blockers: Array) -> bool:
	var index := vehicles.size()
	var own := 0      # placed vehicles that block the new one
	var victims := 0  # placed vehicles the new one blocks
	for other: Dictionary in vehicles:
		if model._sweep_hits(vehicle, other):
			own |= 1 << int(other.id)
		if model._sweep_hits(other, vehicle):
			victims |= 1 << int(other.id)
	# A cycle exists if a victim is reachable from the new vehicle's blockers.
	var reached := own
	var frontier := own
	while frontier != 0:
		var next := 0
		for id in index:
			if (frontier >> id) & 1 == 1:
				next |= int(blockers[id])
		frontier = next & ~reached
		reached |= next
	if reached & victims != 0:
		return false
	for id in index:
		if (victims >> id) & 1 == 1:
			blockers[id] = int(blockers[id]) | (1 << index)
	blockers.append(own)
	return true

## A truck joining the window copies an open truck's colour with probability
## same_color_chance, otherwise takes a colour unused in the window (when one
## exists). overlaps[0] counts the joins that share a colour with the window.
func _build_queue(vehicles: Array, order: Array, window: int, max_run: int,
		color_count: int, same_color_chance: float, overlaps: Array) -> Array:
	var cargo: Array = []
	var open: Array = []
	var left := {}
	var next := 0
	while true:
		while open.size() < window and next < order.size():
			var id: int = order[next]
			var taken := {}
			for other: int in open:
				taken[int(vehicles[other].color)] = true
			if not open.is_empty() and rng.randf() < same_color_chance:
				var twin: int = open[rng.randi_range(0, open.size() - 1)]
				vehicles[id].color = vehicles[twin].color
			elif taken.has(int(vehicles[id].color)) and taken.size() < color_count:
				var free_colors: Array = []
				for color in color_count:
					if not taken.has(color):
						free_colors.append(color)
				vehicles[id].color = free_colors[rng.randi_range(0, free_colors.size() - 1)]
			if taken.has(int(vehicles[id].color)):
				overlaps[0] = int(overlaps[0]) + 1
			open.append(id)
			left[id] = int(vehicles[id].capacity)
			next += 1
		if open.is_empty():
			break
		var pick: int = open[rng.randi_range(0, open.size() - 1)]
		var run := mini(int(left[pick]), rng.randi_range(1, max_run))
		for unit in run:
			cargo.append(vehicles[pick].color)
		left[pick] = int(left[pick]) - run
		if int(left[pick]) == 0:
			open.erase(pick)
	return cargo

func _count_switches(cargo: Array) -> int:
	var switches := 0
	for index in range(1, cargo.size()):
		if cargo[index] != cargo[index - 1]:
			switches += 1
	return switches

func _inside_yard(vehicle: Dictionary, size: Vector2) -> bool:
	var f: Vector2 = model.forward(vehicle)
	var side := Vector2(-f.y, f.x)
	var half_x := absf(side.x) * size.x * 0.5 + absf(f.x) * size.y * 0.5 + 2.0
	var half_y := absf(side.y) * size.x * 0.5 + absf(f.y) * size.y * 0.5 + 2.0
	var p: Vector2 = vehicle.position
	return p.x - half_x >= GameModel.YARD_RECT.position.x \
		and p.x + half_x <= GameModel.YARD_RECT.end.x \
		and p.y - half_y >= GameModel.YARD_RECT.position.y \
		and p.y + half_y <= GameModel.YARD_RECT.end.y

func _count_initially_dispatchable(vehicles: Array) -> int:
	var count := 0
	for vehicle: Dictionary in vehicles:
		var blocked := false
		for other: Dictionary in vehicles:
			if other.id != vehicle.id and model._sweep_hits(vehicle, other):
				blocked = true
				break
		if not blocked:
			count += 1
	return count

func to_json_data(candidate: Dictionary) -> Dictionary:
	if not candidate.get("ok", false):
		return candidate.duplicate(true)
	var exported: Array = []
	for v: Dictionary in candidate.vehicles:
		exported.append({
			"id": v.id,
			"kind": v.kind,
			"color": v.color,
			"x": snappedf(v.position.x, 0.001),
			"y": snappedf(v.position.y, 0.001),
			"angle": snappedf(v.angle, 0.000001),
			"capacity": v.capacity
		})
	return {
		"schema_version": 1,
		"seed": candidate.seed,
		"vehicles": exported,
		"queue": candidate.queue,
		"dispatch_order": candidate.dispatch_order,
		"metrics": candidate.metrics,
		"solver_verified": false,
		"initial_bay_count": 3,
		"max_bay_count": GameModel.BAY_COUNT,
		"boosters": {"extra_slot_limit": 2, "shuffle_mode": "uniform_random_remaining_queue"}
	}

## Inverse of to_json_data: restores the runtime vehicle dictionaries.
static func from_json_data(data: Dictionary) -> Dictionary:
	var vehicles: Array = []
	for v: Dictionary in data.vehicles:
		vehicles.append({"id": int(v.id), "color": int(v.color),
			"position": Vector2(float(v.x), float(v.y)), "angle": float(v.angle),
			"kind": int(v.kind), "capacity": int(v.capacity),
			"load": 0, "status": "yard", "bay": -1})
	var cargo: Array = []
	for color in data.queue:
		cargo.append(int(color))
	return {"ok": true, "seed": int(data.seed), "vehicles": vehicles, "queue": cargo,
		"dispatch_order": data.get("dispatch_order", []), "metrics": data.get("metrics", {})}
