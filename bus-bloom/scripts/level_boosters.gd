class_name LevelBoosters
extends RefCounted

## Pure state helpers. Integration into BusGameModel, animations, wallet and saves
## must be performed separately. No solver calls are made by Shuffle.
const START_SLOTS := 3
const MAX_SLOTS := 5

static func can_unlock_slot(open_slots: int) -> bool:
	return open_slots >= START_SLOTS and open_slots < MAX_SLOTS

static func unlock_slot(open_slots: int) -> int:
	return mini(MAX_SLOTS, open_slots + 1) if can_unlock_slot(open_slots) else open_slots

## The caller must first pause conveyor/worker actions. reserved_prefix is the
## number of queued items already committed to an in-flight animation; these
## are not shuffled. Returns a NEW array and never changes the source array.
## Fisher-Yates is uniform over permutations of the movable positions.
static func shuffle_remaining(queue: Array, rng: RandomNumberGenerator,
		reserved_prefix: int = 0) -> Array:
	var result := queue.duplicate()
	var start := clampi(reserved_prefix, 0, result.size())
	for i in range(result.size() - 1, start, -1):
		var j := rng.randi_range(start, i)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result

## Smart shuffle: draws `candidates` uniform permutations of the movable part
## and keeps the one the docked trucks can use best (see shuffle_score).
## candidates = 1 is the plain shuffle. More candidates help more often, but
## every candidate is random, so a deadlock is not always resolved.
## docked: [{"color", "free", "load"}] for the trucks in the bays, in bay order.
static func smart_shuffle(queue: Array, rng: RandomNumberGenerator, reserved_prefix: int,
		docked: Array, candidates: int) -> Array:
	var best: Array = []
	var best_score := -1
	for attempt in maxi(1, candidates):
		var option := shuffle_remaining(queue, rng, reserved_prefix)
		var score := shuffle_score(option, reserved_prefix, docked)
		if score > best_score:
			best_score = score
			best = option
	return best

## How much a queue helps the docked trucks: every truck it fills (which frees
## a slot) counts 1000, plus every unit loaded before the conveyor blocks.
## Boarding follows BusGameModel.next_boarding: the fullest matching truck.
static func shuffle_score(queue: Array, start: int, docked: Array) -> int:
	var free: Array = []
	var load: Array = []
	for truck: Dictionary in docked:
		free.append(int(truck.free))
		load.append(int(truck.get("load", 0)))
	var units := 0
	var filled := 0
	for index in range(clampi(start, 0, queue.size()), queue.size()):
		var best := -1
		for bay in docked.size():
			if int(free[bay]) > 0 and int(docked[bay].color) == int(queue[index]) \
					and (best == -1 or int(load[bay]) > int(load[best])):
				best = bay
		if best == -1:
			break
		free[best] = int(free[best]) - 1
		load[best] = int(load[best]) + 1
		units += 1
		if int(free[best]) == 0:
			filled += 1
	return filled * 1000 + units

## Trucks waiting in the bays of a BusGameModel, in the format smart_shuffle takes.
static func docked_trucks(model) -> Array:
	var result: Array = []
	for id: int in model.bays:
		if id != -1:
			var bus: Dictionary = model.buses[id]
			if bus["status"] == "docked":
				result.append({"color": bus["color"], "load": int(bus["load"]),
					"free": int(bus["capacity"]) - int(bus["load"])})
	return result
