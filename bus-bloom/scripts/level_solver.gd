class_name LevelSolver
extends RefCounted

## Offline analysis of one level on the production rules of BusGameModel:
## FIFO cargo, automatic boarding into the fullest matching docked truck and
## forward-sweep blocking. The slot count is a parameter, so one level can be
## checked with the base slots and again after Extra Slot rescues.

const GameModel = preload("res://scripts/game_model.gd")
const Boosters = preload("res://scripts/level_boosters.gd")

var vehicles: Array = []
var queue: Array = []
## blockers[id]: bitmask of the vehicles standing in the exit sweep of id.
var blockers: Array = []

var _nodes := 0
var _node_limit := 0
var _aborted := false
var _seen := {}

## Vehicle ids must equal their array index, as in BusGameModel.buses.
func _init(level_vehicles: Array, level_queue: Array) -> void:
	assert(level_vehicles.size() <= 62)
	vehicles = level_vehicles
	queue = level_queue
	var model = GameModel.new()
	for vehicle: Dictionary in vehicles:
		var mask := 0
		for other: Dictionary in vehicles:
			if other.id != vehicle.id and model._sweep_hits(vehicle, other):
				mask |= 1 << int(other.id)
		blockers.append(mask)

## Exhaustive search for a winning dispatch order with `slots` slots.
## status: "solvable" (path is a certificate), "unsolvable" (proven) or
## "timeout" (node_limit reached; nothing is proven).
func solve(slots: int, node_limit: int = 200000) -> Dictionary:
	_nodes = 0
	_node_limit = node_limit
	_aborted = false
	_seen = {}
	var path: Array = []
	var found := _search(_initial_state(slots), path)
	var status := "solvable" if found else ("timeout" if _aborted else "unsolvable")
	return {"status": status, "path": path if found else [], "nodes": _nodes}

## Smallest slot count with a solution. proven is false when a smaller count
## timed out, so the true minimum may be lower than reported.
func min_slots(max_slots: int, node_limit: int = 200000) -> Dictionary:
	var statuses := {}
	var proven := true
	for slots in range(1, max_slots + 1):
		var result := solve(slots, node_limit)
		statuses[str(slots)] = result.status
		if result.status == "solvable":
			return {"min_slots": slots, "proven": proven, "statuses": statuses, "path": result.path}
		if result.status == "timeout":
			proven = false
	return {"min_slots": -1, "proven": proven, "statuses": statuses, "path": []}

## Monte Carlo model of a player. With probability `skill` the player sends
## the truck whose material the conveyor needs soonest, otherwise any truck
## that can leave. When the slots are full and nothing can board, the run
## spends an Extra Slot rescue while rescues and slots last.
## Buffer fill is measured after boarding settles, i.e. trucks left waiting.
func simulate(slots: int, runs: int, skill: float, max_rescues: int, max_slots: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var wins_by_rescues: Array = []
	wins_by_rescues.resize(max_rescues + 1)
	wins_by_rescues.fill(0)
	var rescues_total := 0
	var speed_bonus := 0
	var clutch := 0
	var fill_sum := 0.0
	var near_miss_sum := 0.0
	var deadlocked_runs := 0
	for run in runs:
		var state := _initial_state(slots)
		var bays: Array = state["bays"]
		var rescues := 0
		var peak := 0
		var won := false
		while true:
			_settle(state)
			peak = maxi(peak, bays.size() - bays.count(-1))
			if int(state["yard"]) == 0 and int(state["offset"]) == queue.size():
				won = true
				break
			var free: int = bays.find(-1)
			var available: Array = _available(state) if free != -1 else []
			if available.is_empty():
				if rescues == 0:
					# Share of cargo already loaded at the first deadlock.
					near_miss_sum += float(state["offset"]) / maxi(1, queue.size())
					deadlocked_runs += 1
				if rescues < max_rescues and bays.size() < max_slots:
					bays.append(-1)
					rescues += 1
					continue
				break
			var choice := _player_choice(state, available, skill, rng)
			state["yard"] = int(state["yard"]) & ~(1 << choice)
			bays[free] = choice
		rescues_total += rescues
		fill_sum += float(peak) / slots
		if won:
			wins_by_rescues[rescues] = int(wins_by_rescues[rescues]) + 1
			if rescues == 0:
				if peak * 2 <= slots:
					speed_bonus += 1
				if peak == slots - 1:
					clutch += 1
	var clean: int = wins_by_rescues[0]
	var with_one: int = clean + (int(wins_by_rescues[1]) if max_rescues >= 1 else 0)
	var total_wins := 0
	for count: int in wins_by_rescues:
		total_wins += count
	return {
		"runs": runs,
		"fail_rate": 1.0 - float(clean) / runs,
		"post_rescue_fail": 1.0 - float(with_one) / runs,
		"final_fail_rate": 1.0 - float(total_wins) / runs,
		"expected_rescues": float(rescues_total) / runs,
		"wins_by_rescues": wins_by_rescues,
		"speed_bonus_rate": float(speed_bonus) / runs,
		"clutch_rate": float(clutch) / runs,
		"mean_peak_fill": fill_sum / runs,
		"near_miss": near_miss_sum / deadlocked_runs if deadlocked_runs > 0 else 0.0
	}

## Walks a winning path and, at every decision with two or more legal
## trucks, checks each alternative with a small exact search.
## trap_ratio: share of alternatives that are proven dead ends.
## critical_share: share of decisions where at least one alternative is a trap.
func trap_profile(slots: int, path: Array, node_limit: int = 20000) -> Dictionary:
	var state := _initial_state(slots)
	var decisions := 0
	var critical := 0
	var alternatives := 0
	var traps := 0
	var unknown := 0
	for chosen: int in path:
		_settle(state)
		var bays: Array = state["bays"]
		var free: int = bays.find(-1)
		var moves := _available(state)
		if moves.size() >= 2:
			decisions += 1
			var dead_here := false
			for id: int in moves:
				if id == chosen:
					continue
				alternatives += 1
				var child: Dictionary = state.duplicate(true)
				child["yard"] = int(child["yard"]) & ~(1 << id)
				child["bays"][free] = id
				var status: String = _solve_state(child, node_limit)
				if status == "unsolvable":
					traps += 1
					dead_here = true
				elif status == "timeout":
					unknown += 1
			if dead_here:
				critical += 1
		state["yard"] = int(state["yard"]) & ~(1 << chosen)
		bays[free] = chosen
	return {
		"decisions": decisions,
		"trap_ratio": float(traps) / alternatives if alternatives > 0 else 0.0,
		"critical_share": float(critical) / decisions if decisions > 0 else 0.0,
		"trap_unknown": unknown,
	}

## What each kind of help is worth on this level for a player of `skill`.
## - fail_by_slots[n]: deadlock rate when the level starts with n slots
##   (Extra Slot bought before the level).
## - slot_again[j]: chance of another deadlock after the (j+1)-th +1 slot,
##   among runs that reached deadlock number j+1.
## - shuffle_by_strength[k].again[j]: chance of another deadlock after a smart
##   shuffle of strength k (LevelBoosters.smart_shuffle, best of k random
##   permutations) at deadlock number j+1 instead of adding a slot. Every
##   deadlock is probed with `shuffles` draws; nothing is in flight at a
##   settled deadlock, so only loaded cargo stays in place. k = 1 is the plain
##   shuffle and is also reported as shuffle_again.
## - hopeless: share of probed deadlocks where no draw helped.
## - spread: mean within-deadlock standard deviation of the outcome, from 0
##   (predictable) to 0.5 (a coin toss).
func booster_profile(base_slots: int, max_slots: int, runs: int, shuffles: int, skill: float,
		rng: RandomNumberGenerator, strengths: Array = [1]) -> Dictionary:
	var fail_by_slots := {}
	for slots in range(base_slots, max_slots + 1):
		fail_by_slots[str(slots)] = simulate(slots, runs, skill, 0, slots, rng).fail_rate
	var stages := max_slots - base_slots
	var reached: Array = []
	reached.resize(stages + 1)
	reached.fill(0)
	var stats := {}
	for k in strengths:
		var misses: Array = []
		misses.resize(stages)
		misses.fill(0)
		var tries: Array = []
		tries.resize(stages)
		tries.fill(0)
		stats[int(k)] = {"misses": misses, "tries": tries, "hopeless": 0, "spread": 0.0}
	var probed := 0
	var swap_misses: Array = []
	swap_misses.resize(stages)
	swap_misses.fill(0)
	var swap_tries: Array = []
	swap_tries.resize(stages)
	swap_tries.fill(0)
	var crane_misses: Array = []
	crane_misses.resize(stages)
	crane_misses.fill(0)
	for run in runs:
		var state := _initial_state(base_slots)
		var stage := 0
		while not _play_until_deadlock(state, skill, rng):
			reached[stage] = int(reached[stage]) + 1
			if stage >= stages:
				break
			probed += 1
			var docked := _docked(state)
			for k: int in stats:
				var s: Dictionary = stats[k]
				var helped := 0
				for attempt in shuffles:
					var probe: Dictionary = state.duplicate(true)
					probe["queue"] = Boosters.smart_shuffle(state.get("queue", queue), rng,
						int(state["offset"]), docked, k)
					if _play_until_deadlock(probe, skill, rng):
						helped += 1
				s.tries[stage] = int(s.tries[stage]) + shuffles
				s.misses[stage] = int(s.misses[stage]) + shuffles - helped
				var share := float(helped) / shuffles
				s.spread = float(s.spread) + sqrt(share * (1.0 - share))
				if helped == 0:
					s.hopeless = int(s.hopeless) + 1
			var swapped := 0
			for attempt in shuffles:
				var probe: Dictionary = state.duplicate(true)
				if swap_truck(probe) and _play_until_deadlock(probe, skill, rng):
					swapped += 1
			swap_tries[stage] = int(swap_tries[stage]) + shuffles
			swap_misses[stage] = int(swap_misses[stage]) + shuffles - swapped
			var craned := 0
			for attempt in shuffles:
				var probe: Dictionary = state.duplicate(true)
				if crane_truck(probe) and _play_until_deadlock(probe, skill, rng):
					craned += 1
			crane_misses[stage] = int(crane_misses[stage]) + shuffles - craned
			state["bays"].append(-1)
			stage += 1
	var slot_again: Array = []
	var swap_again: Array = []
	var crane_again: Array = []
	for j in stages:
		slot_again.append(float(reached[j + 1]) / reached[j] if int(reached[j]) > 0 else 0.0)
		swap_again.append(float(swap_misses[j]) / swap_tries[j] if int(swap_tries[j]) > 0 else 0.0)
		crane_again.append(float(crane_misses[j]) / swap_tries[j] if int(swap_tries[j]) > 0 else 0.0)
	var by_strength := {}
	for k: int in stats:
		var s: Dictionary = stats[k]
		var again: Array = []
		for j in stages:
			again.append(float(s.misses[j]) / s.tries[j] if int(s.tries[j]) > 0 else 0.0)
		by_strength[str(k)] = {"again": again,
			"hopeless": float(s.hopeless) / probed if probed > 0 else 0.0,
			"spread": float(s.spread) / probed if probed > 0 else 0.0}
	var plain: Dictionary = by_strength.get("1", by_strength.values()[0] if not by_strength.is_empty() else {})
	return {
		"fail_by_slots": fail_by_slots,
		"slot_again": slot_again,
		"swap_again": swap_again,
		"crane_again": crane_again,
		"shuffle_by_strength": by_strength,
		"shuffle_again": plain.get("again", []),
		"shuffle_hopeless": plain.get("hopeless", 0.0),
		"shuffle_spread": plain.get("spread", 0.0),
		"deadlocks_probed": probed,
	}

## Onboarding check for a level that is proven unsolvable with base_slots.
## Players of mixed skill (skill_grid, round robin) play until their first
## deadlock; there the tutorial draws up to `tries` smart shuffles of strength
## `strength` and keeps the first one after which the exact solver finds a win.
## - recoverable: share of sampled deadlocks where such a shuffle was found;
## - mean_tries: draws needed on average (the game pays that in solver time);
## - post_win: share of those players who then win without further help.
func tutorial_profile(base_slots: int, runs: int, tries: int, strength: int, node_limit: int,
		skill_grid: Array, rng: RandomNumberGenerator) -> Dictionary:
	var recovered := 0
	var draws := 0
	var wins := 0
	for run in runs:
		var skill := float(skill_grid[run % skill_grid.size()])
		var state := _initial_state(base_slots)
		if _play_until_deadlock(state, skill, rng):
			continue   # cannot happen on a proven unsolvable level; skip if it does
		var found := {}
		for attempt in tries:
			var probe: Dictionary = state.duplicate(true)
			probe["queue"] = Boosters.smart_shuffle(state.get("queue", queue), rng,
				int(state["offset"]), _docked(state), strength)
			draws += 1
			if _solve_state(probe.duplicate(true), node_limit) == "solvable":
				found = probe
				break
		if found.is_empty():
			continue
		recovered += 1
		if _play_until_deadlock(found, skill, rng):
			wins += 1
	return {
		"tutorial_recoverable": float(recovered) / runs,
		"tutorial_mean_tries": float(draws) / runs,
		"tutorial_post_win": float(wins) / recovered if recovered > 0 else 0.0,
	}

## Booster onboarding check for a level that is winnable without help. A
## player of `skill` plays `runs` times; at the first deadlock the tutorial
## gives `booster` ("slot", "crane" or "shuffle") for free.
## - deadlock_rate: share of runs that hit a deadlock, i.e. see the hint;
## - post_win: share of those that then win without further help.
func onboarding_profile(base_slots: int, runs: int, skill: float, booster: String,
		rng: RandomNumberGenerator, strength: int = 16) -> Dictionary:
	var deadlocks := 0
	var wins := 0
	for run in runs:
		var state := _initial_state(base_slots)
		if _play_until_deadlock(state, skill, rng):
			continue
		deadlocks += 1
		var helped := false
		match booster:
			"crane":
				helped = crane_truck(state)
			"shuffle":
				state["queue"] = Boosters.smart_shuffle(state.get("queue", queue), rng,
					int(state["offset"]), _docked(state), strength)
				helped = true
			_:
				state["bays"].append(-1)
				helped = true
		if helped and _play_until_deadlock(state, skill, rng):
			wins += 1
	return {
		"onboarding_deadlock_rate": float(deadlocks) / runs,
		"onboarding_post_win": float(wins) / deadlocks if deadlocks > 0 else 0.0,
	}

## Runtime helper for the onboarding hint: a smart shuffle of `strength` that
## the exact solver confirms winnable from `state`, or the last draw if none
## was found within `tries`. state: as built by state_from_model.
func verified_shuffle(state: Dictionary, rng: RandomNumberGenerator, tries: int = 40,
		strength: int = 8, node_limit: int = 20000) -> Array:
	var option: Array = []
	for attempt in tries:
		option = Boosters.smart_shuffle(state.get("queue", queue), rng, int(state["offset"]),
			_docked(state), strength)
		var probe: Dictionary = state.duplicate(true)
		probe["queue"] = option
		if _solve_state(probe, node_limit) == "solvable":
			return option
	return option

## Solver state for a live BusGameModel with `open_slots` usable bays.
## The model's queue already lacks loaded cargo, so the offset starts at 0.
func state_from_model(model, open_slots: int) -> Dictionary:
	var yard := 0
	var loads: Array = []
	for bus: Dictionary in model.buses:
		loads.append(int(bus["load"]))
		if bus["status"] == "yard":
			yard |= 1 << int(bus["id"])
	var bays: Array = []
	for bay in open_slots:
		var id: int = model.bays[bay] if bay < model.bays.size() else -1
		bays.append(id if id != -1 and model.buses[id]["status"] == "docked" else -1)
	return {"yard": yard, "offset": 0, "bays": bays, "loads": loads, "queue": model.queue.duplicate()}

## Truck swap booster, applied to `state` in place at a deadlock. The docked
## truck with the least cargo drives back to its parking spot and the worker
## returns its cargo to the end of the conveyor; the largest parked truck of
## the colour at the conveyor head takes its bay, even if it is blocked.
## Every colour keeps exactly the capacity its cargo needs, so the level stays
## winnable in principle. Returns false when there is nothing to swap.
## Variants: pick = "least_loaded" | "needed_last" (the truck whose colour the
## conveyor needs last); keep_cargo = true lets the leaving truck park with its
## cargo on board instead of returning it to the conveyor.
func swap_truck(state: Dictionary, pick: String = "least_loaded", keep_cargo: bool = false) -> bool:
	var cargo: Array = state.get("queue", queue).duplicate()
	var offset: int = state["offset"]
	if offset >= cargo.size():
		return false
	var color := int(cargo[offset])
	var bays: Array = state["bays"]
	var loads: Array = state["loads"]
	var leaving := -1
	var leaving_need := -1
	for id: int in bays:
		if id == -1:
			continue
		if pick == "needed_last":
			var need := _next_need(state, int(vehicles[id].color))
			if leaving == -1 or need > leaving_need:
				leaving = id
				leaving_need = need
		elif leaving == -1 or int(loads[id]) < int(loads[leaving]):
			leaving = id
	var yard: int = state["yard"]
	var arriving := -1
	for id in vehicles.size():
		if ((yard >> id) & 1) == 1 and int(vehicles[id].color) == color \
				and (arriving == -1 or int(vehicles[id].capacity) > int(vehicles[arriving].capacity)):
			arriving = id
	if leaving == -1 or arriving == -1:
		return false
	if not keep_cargo:
		for unit in int(loads[leaving]):
			cargo.append(int(vehicles[leaving].color))
		loads[leaving] = 0
	bays[bays.find(leaving)] = arriving
	state["yard"] = (yard & ~(1 << arriving)) | (1 << leaving)
	state["queue"] = cargo
	return true

## Crane booster, applied to `state` in place at a deadlock: a temporary extra
## slot opens (for the rest of the round, within MAX_SLOTS) and the crane lifts
## the largest parked truck of the conveyor-head colour into it, even if it is
## blocked. No truck or cargo is added: the lifted truck is one of the level's
## own trucks, taken out of turn. Returns false with no slot place left.
func crane_truck(state: Dictionary, max_slots: int = 5) -> bool:
	var bays: Array = state["bays"]
	if bays.size() >= max_slots:
		return false
	var cargo: Array = state.get("queue", queue)
	var offset: int = state["offset"]
	if offset >= cargo.size():
		return false
	var color := int(cargo[offset])
	var yard: int = state["yard"]
	var lifted := -1
	for id in vehicles.size():
		if ((yard >> id) & 1) == 1 and int(vehicles[id].color) == color \
				and (lifted == -1 or int(vehicles[id].capacity) > int(vehicles[lifted].capacity)):
			lifted = id
	if lifted == -1:
		return false
	bays.append(lifted)
	state["yard"] = yard & ~(1 << lifted)
	return true

func _docked(state: Dictionary) -> Array:
	var loads: Array = state["loads"]
	var result: Array = []
	for id: int in state["bays"]:
		if id != -1:
			result.append({"color": int(vehicles[id].color), "load": int(loads[id]),
				"free": int(vehicles[id].capacity) - int(loads[id])})
	return result

## Plays the player policy from `state` (modified in place). True on a win,
## false at the first deadlock.
func _play_until_deadlock(state: Dictionary, skill: float, rng: RandomNumberGenerator) -> bool:
	var bays: Array = state["bays"]
	var length: int = state.get("queue", queue).size()
	while true:
		_settle(state)
		if int(state["yard"]) == 0 and int(state["offset"]) == length:
			return true
		var free: int = bays.find(-1)
		var available: Array = _available(state) if free != -1 else []
		if available.is_empty():
			return false
		var choice := _player_choice(state, available, skill, rng)
		state["yard"] = int(state["yard"]) & ~(1 << choice)
		bays[free] = choice
	return false

func _solve_state(state: Dictionary, node_limit: int) -> String:
	_nodes = 0
	_node_limit = node_limit
	_aborted = false
	_seen = {}
	var found := _search(state, [])
	return "solvable" if found else ("timeout" if _aborted else "unsolvable")

func _initial_state(slots: int) -> Dictionary:
	var bays: Array = []
	bays.resize(slots)
	bays.fill(-1)
	var loads: Array = []
	loads.resize(vehicles.size())
	loads.fill(0)
	return {"yard": (1 << vehicles.size()) - 1, "offset": 0, "bays": bays, "loads": loads}

## Mirrors BusGameModel.next_boarding: the head unit goes to the docked truck
## of that colour with the highest load, the first bay winning ties.
func _settle(state: Dictionary) -> void:
	var cargo: Array = state.get("queue", queue)
	var bays: Array = state["bays"]
	var loads: Array = state["loads"]
	var offset: int = state["offset"]
	while offset < cargo.size():
		var material: int = cargo[offset]
		var best := -1
		for id: int in bays:
			if id != -1 and int(vehicles[id].color) == material \
					and (best == -1 or int(loads[id]) > int(loads[best])):
				best = id
		if best == -1:
			break
		loads[best] = int(loads[best]) + 1
		offset += 1
		if int(loads[best]) == int(vehicles[best].capacity):
			bays[bays.find(best)] = -1
	state["offset"] = offset

func _available(state: Dictionary) -> Array:
	var yard: int = state["yard"]
	var result: Array = []
	for id in vehicles.size():
		if ((yard >> id) & 1) == 1 and (int(blockers[id]) & yard) == 0:
			result.append(id)
	return result

## Queue distance to the first unit of `color` that no docked truck of the
## same colour will absorb first; queue.size() when the colour is not needed.
func _next_need(state: Dictionary, color: int) -> int:
	var covered := 0
	var loads: Array = state["loads"]
	for id: int in state["bays"]:
		if id != -1 and int(vehicles[id].color) == color:
			covered += int(vehicles[id].capacity) - int(loads[id])
	var offset: int = state["offset"]
	var cargo: Array = state.get("queue", queue)
	for index in range(offset, cargo.size()):
		if int(cargo[index]) == color:
			if covered == 0:
				return index - offset
			covered -= 1
	return queue.size()

func _player_choice(state: Dictionary, available: Array, skill: float,
		rng: RandomNumberGenerator) -> int:
	if rng.randf() >= skill:
		return available[rng.randi_range(0, available.size() - 1)]
	var best: Array = []
	var best_need := queue.size() + 1
	for id: int in available:
		var need := _next_need(state, int(vehicles[id].color))
		if need < best_need:
			best_need = need
			best = [id]
		elif need == best_need:
			best.append(id)
	return best[rng.randi_range(0, best.size() - 1)]

func _search(state: Dictionary, path: Array) -> bool:
	_nodes += 1
	if _nodes > _node_limit:
		_aborted = true
		return false
	_settle(state)
	if int(state["yard"]) == 0 and int(state["offset"]) == queue.size():
		return true
	var bays: Array = state["bays"]
	var free: int = bays.find(-1)
	if free == -1:
		return false
	var key := _key(state)
	if _seen.has(key):
		return false
	_seen[key] = true
	# Try the trucks the conveyor needs soonest first; it finds most
	# solutions on the first branch and does not affect unsolvability proofs.
	var moves := _available(state)
	var needs := {}
	for id: int in moves:
		needs[id] = _next_need(state, int(vehicles[id].color))
	moves.sort_custom(func(a: int, b: int) -> bool:
		return int(needs[a]) < int(needs[b]) or (needs[a] == needs[b] and a < b))
	for id: int in moves:
		var child: Dictionary = state.duplicate(true)
		child["yard"] = int(child["yard"]) & ~(1 << id)
		child["bays"][free] = id
		path.append(id)
		if _search(child, path):
			return true
		path.pop_back()
		if _aborted:
			return false
	return false

func _key(state: Dictionary) -> String:
	var parts := PackedStringArray([str(state["yard"]), str(state["offset"])])
	var loads: Array = state["loads"]
	for id: int in state["bays"]:
		parts.append("%d/%d" % [id, int(loads[id]) if id != -1 else 0])
	return ",".join(parts)
