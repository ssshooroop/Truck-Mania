class_name BusGameModel
extends RefCounted
## Pure construction-yard rules. The view owns the timing of all animations.

const BAY_COUNT := 5
const CRANE_BAY := 5
const TOTAL_BAYS := 6
const COLORS := 6
const CAPACITIES := [2, 4, 6]
const WIDTHS := [56.0, 56.0, 56.0]
const LENGTHS := [98.24, 139.37, 182.79]
const YARD_RECT := Rect2(35, 610, 470, 480)
const LEVELS := [
	{"name": "Первая поставка", "count": 8},
	{"name": "Стройка оживает", "count": 10},
	{"name": "Плотная парковка", "count": 12},
	{"name": "Большая разгрузка", "count": 14},
	{"name": "Рабочий квартал", "count": 16},
	{"name": "Строительный час пик", "count": 18},
]
## Authored packed layouts: local X, local Y, heading in eighth-turns, vehicle kind.
## Every later body clears every earlier forward sweep; IDs certify solvability.
## A two-pixel border around each body leaves at least four pixels between trucks.
const LAYOUTS := [
	[
		Vector4(398.09785, 76.92313, 1, 1),
		Vector4(57.36050, 57.36050, 7, 0),
		Vector4(51.12000, 145.00000, 6, 0),
		Vector4(270.40125, 30.00000, 2, 2),
		Vector4(145.00000, 93.39500, 0, 2),
		Vector4(205.00000, 111.62954, 0, 0),
		Vector4(307.76673, 162.27974, 7, 1),
		Vector4(202.47446, 227.51107, 5, 0),
	],
	[
		Vector4(87.25344, 342.74656, 5, 2),
		Vector4(71.90215, 71.90215, 7, 1),
		Vector4(209.71339, 394.93151, 6, 2),
		Vector4(57.36050, 142.43579, 7, 0),
		Vector4(182.30685, 71.90215, 7, 1),
		Vector4(252.52925, 147.36947, 1, 2),
		Vector4(305.00000, 313.32800, 4, 0),
		Vector4(197.36204, 277.76221, 3, 1),
		Vector4(142.42730, 172.46236, 5, 0),
		Vector4(272.52947, 217.50221, 1, 0),
	],
	[
		Vector4(412.63950, 57.36050, 1, 0),
		Vector4(87.25344, 97.27278, 7, 2),
		Vector4(418.88000, 185.00000, 2, 0),
		Vector4(398.31500, 270.00000, 2, 1),
		Vector4(265.34393, 30.00000, 2, 2),
		Vector4(51.12000, 250.00000, 6, 0),
		Vector4(150.00000, 297.97184, 4, 1),
		Vector4(250.17196, 90.00000, 2, 2),
		Vector4(57.36050, 152.44464, 7, 0),
		Vector4(252.58777, 340.00000, 6, 1),
		Vector4(270.40125, 160.00000, 2, 2),
		Vector4(267.52554, 252.53321, 3, 0),
	],
	[
		Vector4(97.27016, 342.74656, 5, 2),
		Vector4(71.90215, 71.90215, 7, 1),
		Vector4(418.88000, 105.00000, 2, 0),
		Vector4(337.87710, 358.09785, 3, 1),
		Vector4(30.00000, 225.13375, 0, 2),
		Vector4(418.88000, 230.00000, 2, 0),
		Vector4(398.31500, 165.00000, 2, 1),
		Vector4(209.71339, 400.00000, 6, 2),
		Vector4(418.88000, 290.00000, 2, 0),
		Vector4(172.27006, 76.92313, 7, 1),
		Vector4(154.08286, 202.32877, 6, 2),
		Vector4(313.08603, 90.00000, 2, 0),
		Vector4(227.47241, 297.84612, 5, 1),
		Vector4(307.55698, 227.51107, 3, 0),
	],
	[
		Vector4(398.09785, 76.92313, 1, 1),
		Vector4(57.36050, 57.36050, 7, 0),
		Vector4(440.00000, 358.31500, 4, 1),
		Vector4(93.39500, 339.17808, 6, 2),
		Vector4(51.12000, 145.00000, 6, 0),
		Vector4(338.01408, 400.00000, 2, 1),
		Vector4(270.40125, 30.00000, 2, 2),
		Vector4(412.63950, 147.44022, 1, 0),
		Vector4(71.68500, 245.00000, 6, 1),
		Vector4(145.00000, 93.39500, 0, 2),
		Vector4(418.88000, 235.00000, 2, 0),
		Vector4(230.00000, 358.31500, 4, 1),
		Vector4(322.64626, 282.63053, 3, 2),
		Vector4(205.00000, 111.62954, 0, 0),
		Vector4(307.76673, 162.27974, 7, 1),
		Vector4(202.47446, 227.51107, 5, 0),
	],
	[
		Vector4(76.92055, 358.09785, 5, 1),
		Vector4(98.45232, 30.00000, 6, 2),
		Vector4(402.63164, 372.63950, 3, 0),
		Vector4(435.00000, 71.68500, 0, 1),
		Vector4(93.39500, 90.82192, 6, 2),
		Vector4(418.88000, 275.00000, 2, 0),
		Vector4(375.00000, 76.71360, 0, 1),
		Vector4(30.00000, 220.06688, 0, 2),
		Vector4(418.88000, 215.00000, 2, 0),
		Vector4(182.23669, 400.00000, 6, 1),
		Vector4(315.00000, 336.60500, 4, 2),
		Vector4(225.00000, 51.12000, 0, 0),
		Vector4(315.00000, 71.68500, 0, 1),
		Vector4(154.08286, 166.84932, 6, 2),
		Vector4(111.57370, 255.00000, 6, 0),
		Vector4(195.00000, 297.97184, 4, 1),
		Vector4(255.00000, 313.32800, 4, 0),
		Vector4(313.08603, 190.00000, 2, 0),
	],
]
static var _level_cache: Dictionary = {}
static var campaign: Array = []

static func campaign_levels() -> Array:
	if campaign.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://config/campaign.json"))
		if data is Dictionary: campaign = data.get("levels",[])
	return campaign

func level_title(index:int) -> String:
	return "Склад %d" % (index+1)


var buses: Array = []
var tablet_layout := false
var layout_transform := Transform2D.IDENTITY
var layout_scale := 1.0
var yard_rect := YARD_RECT
var queue: Array = []
var open_bay_count := 3
var bays: Array = [-1, -1, -1, -1, -1, -1]
var level_index := -1
var level_name := ""
var _search_deadline := 0
var _search_aborted := false
var _maneuver_cache:Dictionary = {}
const YardManeuver = preload("res://scripts/yard_maneuver.gd")

func level_count() -> int:
	return campaign_levels().size()

func load_level(index: int) -> bool:
	if index < 0 or index >= level_count():
		return false
	layout_transform = preload("res://scripts/responsive_layout.gd").yard(_raw_level_template(index).buses,Rect2(45,390,450,235)) if tablet_layout else Transform2D.IDENTITY
	layout_scale = layout_transform.get_scale().x
	yard_rect = Rect2(35,380,470,255) if tablet_layout else YARD_RECT
	var template := _level_template(index)
	level_index = index
	_maneuver_cache.clear()
	level_name = level_title(index)
	buses = template["buses"].duplicate(true)
	queue = template["queue"].duplicate()
	bays = [-1, -1, -1, -1, -1, -1]
	open_bay_count = 3
	return true

func _level_template(index: int) -> Dictionary:
	var template:Dictionary = _raw_level_template(index).duplicate(true)
	for bus:Dictionary in template.buses:
		bus.position=layout_transform*bus.position
		bus.angle+=layout_transform.get_rotation()
	return template

func _raw_level_template(index: int) -> Dictionary:
	if _level_cache.has(index):
		return _level_cache[index]
	var data: Dictionary = campaign_levels()[index]
	var result: Array = []
	for v: Dictionary in data.vehicles:
		result.append({"id":int(v.id),"color":int(v.color),"position":Vector2(v.x,v.y),
			"angle":float(v.angle),"kind":int(v.kind),"capacity":int(v.capacity),
			"load":0,"status":"yard","bay":-1})
	var cargo: Array = []
	for color in data.queue: cargo.append(int(color))
	_level_cache[index] = {"buses":result,"queue":cargo}
	return _level_cache[index]

func get_bus(id: int) -> Dictionary:
	return buses[id] if id >= 0 and id < buses.size() else {}

func vehicle_size(bus: Dictionary) -> Vector2:
	var kind: int = bus.get("kind", 0)
	return Vector2(WIDTHS[kind], LENGTHS[kind])*layout_scale

func forward(bus: Dictionary) -> Vector2:
	var angle: float = bus["angle"]
	return Vector2(sin(angle), -cos(angle))

func exit_position(id: int) -> Vector2:
	var bus := get_bus(id)
	return _exit_for(bus) if not bus.is_empty() else Vector2.ZERO

func _exit_for(bus: Dictionary) -> Vector2:
	var point: Vector2 = bus["position"]
	var direction := forward(bus)
	var safe_rect := yard_rect.grow(vehicle_size(bus).length() * 0.5 + 10.0)
	var distance := INF
	if direction.x > 0.0001:
		distance = minf(distance, (safe_rect.end.x - point.x) / direction.x)
	elif direction.x < -0.0001:
		distance = minf(distance, (safe_rect.position.x - point.x) / direction.x)
	if direction.y > 0.0001:
		distance = minf(distance, (safe_rect.end.y - point.y) / direction.y)
	elif direction.y < -0.0001:
		distance = minf(distance, (safe_rect.position.y - point.y) / direction.y)
	return point + direction * maxf(0.0, distance)

func _footprints_overlap(a: Dictionary, b: Dictionary) -> bool:
	return _rectangles_overlap(a["position"], forward(a), vehicle_size(a),
		b["position"], forward(b), vehicle_size(b))

func _sweep_hits(moving: Dictionary, parked: Dictionary) -> bool:
	var start: Vector2 = moving["position"]
	var finish := _exit_for(moving)
	var size := vehicle_size(moving)
	# Translation along the longitudinal axis sweeps an exact rectangle.
	# SAT against all four body axes catches side and diagonal edge contact.
	size.y += start.distance_to(finish)
	return _rectangles_overlap((start + finish) * 0.5, forward(moving), size,
		parked["position"], forward(parked), vehicle_size(parked))

func _rectangles_overlap(a_center: Vector2, a_forward: Vector2, a_size: Vector2,
		b_center: Vector2, b_forward: Vector2, b_size: Vector2) -> bool:
	var a_side := Vector2(-a_forward.y, a_forward.x)
	var b_side := Vector2(-b_forward.y, b_forward.x)
	var delta := b_center - a_center
	for axis: Vector2 in [a_forward, a_side, b_forward, b_side]:
		var a_radius := absf(axis.dot(a_side)) * a_size.x * 0.5 + absf(axis.dot(a_forward)) * a_size.y * 0.5
		var b_radius := absf(axis.dot(b_side)) * b_size.x * 0.5 + absf(axis.dot(b_forward)) * b_size.y * 0.5
		if absf(delta.dot(axis)) > a_radius + b_radius - 0.001:
			return false
	return true

func blocking_ids(id: int) -> Array:
	var bus := get_bus(id)
	var result: Array = []
	if bus.is_empty() or bus["status"] != "yard":
		return result
	for other: Dictionary in buses:
		if other["id"] != id and other["status"] == "yard" and _sweep_hits(bus, other):
			result.append(other["id"])
	return result

func maneuver_paths(id:int, mask:int=-1) -> Array:
	# Enable manoeuvres only for layouts audited with the turn-clearance rules.
	if level_index!=3 and (level_index<10 or level_index>19): return []
	if mask<0:
		mask=0
		for bus:Dictionary in buses:
			if bus.status=="yard": mask |= 1<<int(bus.id)
	var key := Vector2i(id,mask)
	if not _maneuver_cache.has(key):
		if tablet_layout:
			# Evaluate the exact same puzzle in canonical coordinates, then map
			# its legal manoeuvres rigidly with the rest of the arrangement.
			var canonical = get_script().new()
			canonical.load_level(level_index)
			var paths:Array = YardManeuver.paths(canonical,id,mask)
			var mapped:Array = []
			for path:Array in paths:
				var mapped_path:Array = []
				for pose:Dictionary in path:
					var point:Dictionary=pose.duplicate()
					point.position=layout_transform*pose.position
					point.angle+=layout_transform.get_rotation()
					point.distance*=layout_scale
					mapped_path.append(point)
				mapped.append(mapped_path)
			_maneuver_cache[key]=mapped
		else: _maneuver_cache[key]=YardManeuver.paths(self,id,mask)
	return _maneuver_cache[key]

func free_bay(slots:Array=[]) -> int:
	if slots.is_empty(): slots = bays
	for index in range(open_bay_count):
		if slots[index]==-1: return index
	return -1

func crane_bay() -> int:
	var available := free_bay()
	return available if available>=0 else (CRANE_BAY if bays[CRANE_BAY]==-1 else -1)

func unlock_next_bay() -> bool:
	if open_bay_count>=BAY_COUNT: return false
	open_bay_count += 1
	return true

func can_dispatch(id: int) -> bool:
	var bus := get_bus(id)
	return not bus.is_empty() and bus["status"] == "yard" and free_bay()>=0 and (blocking_ids(id).is_empty() or not maneuver_paths(id).is_empty())

func dispatch(id: int) -> bool:
	if not can_dispatch(id):
		return false
	var bay: int = free_bay()
	bays[bay] = id
	buses[id]["bay"] = bay
	buses[id]["status"] = "arriving"
	return true

func arrive(id: int) -> bool:
	var bus := get_bus(id)
	if bus.is_empty() or bus["status"] != "arriving":
		return false
	bus["status"] = "docked"
	return true

func next_boarding() -> int:
	if queue.is_empty():
		return -1
	var best_id := -1
	var best_load := -1
	for id in bays:
		if id == -1:
			continue
		var bus: Dictionary = buses[id]
		if bus["status"] == "docked" and bus["color"] == queue[0] and bus["load"] < bus["capacity"]:
			if bus["load"] > best_load:
				best_id = id
				best_load = bus["load"]
	return best_id

func batch_size(id: int) -> int:
	# The worker may collect only the uninterrupted run at the conveyor head.
	# This is a read-only preview: cargo is committed when the worker drops it.
	var bus := get_bus(id)
	if bus.is_empty() or queue.is_empty() or bus["status"] != "docked":
		return 0
	var available: int = bus["capacity"] - bus["load"]
	var count := 0
	while count < mini(available, queue.size()) and queue[count] == bus["color"]:
		count += 1
	return count

func board_batch(id: int, count: int) -> bool:
	# Validate the whole delivery before touching the queue or vehicle so an
	# interrupted animation or stale delivery cannot consume a partial batch.
	if count <= 0 or count > batch_size(id):
		return false
	var bus := get_bus(id)
	for unit in range(count):
		queue.pop_front()
	bus["load"] += count
	if bus["load"] == bus["capacity"]:
		bus["status"] = "leaving"
	return true

func board_one(id: int) -> bool:
	return board_batch(id, 1)

func depart(id: int) -> bool:
	var bus := get_bus(id)
	if bus.is_empty() or bus["status"] != "leaving":
		return false
	bays[bus["bay"]] = -1
	bus["bay"] = -1
	bus["status"] = "gone"
	return true

func is_settled() -> bool:
	if level_index < 0:
		return false
	for bus in buses:
		if bus["status"] in ["arriving", "leaving"]:
			return false
	return true

func is_won() -> bool:
	if level_index < 0 or not queue.is_empty():
		return false
	for bus in buses:
		if bus["status"] != "gone":
			return false
	return true

func is_stuck() -> bool:
	if not is_settled() or is_won() or next_boarding() != -1:
		return false
	for bus in buses:
		if can_dispatch(bus["id"]):
			return false
	return true

func snapshot() -> Dictionary:
	if not is_settled():
		return {}
	return {"level_index": level_index, "buses": buses.duplicate(true),
		"queue": queue.duplicate(), "bays": bays.duplicate()}

func undo_snapshot() -> Dictionary:
	# Record committed cargo only. Earlier accepted arrivals retain their bays;
	# on restoration they are already parked, rather than stranded mid-route.
	var state := {"level_index": level_index, "buses": buses.duplicate(true),
		"queue": queue.duplicate(), "bays": bays.duplicate()}
	for bus:Dictionary in state.buses:
		if bus.status == "arriving": bus.status = "docked"
		elif bus.status == "leaving":
			state.bays[bus.bay] = -1
			bus.bay = -1
			bus.status = "gone"
	return state

func restore(state: Dictionary) -> bool:
	if not _valid_snapshot(state):
		return false
	level_index = state["level_index"]
	level_name = level_title(level_index)
	buses = state["buses"].duplicate(true)
	queue = state["queue"].duplicate()
	bays = state["bays"].duplicate()
	return true

func _valid_snapshot(state: Dictionary) -> bool:
	if not state.has_all(["level_index", "buses", "queue", "bays"]) or typeof(state["level_index"]) != TYPE_INT:
		return false
	var index: int = state["level_index"]
	if index < 0 or index >= level_count():
		return false
	if not state["buses"] is Array or not state["queue"] is Array or not state["bays"] is Array:
		return false
	var saved_buses: Array = state["buses"]
	var saved_queue: Array = state["queue"]
	var saved_bays: Array = state["bays"]
	var template := _level_template(index)
	var original_buses: Array = template["buses"]
	var original_queue: Array = template["queue"]
	if saved_buses.size() != original_buses.size() or saved_bays.size() != TOTAL_BAYS or saved_queue.size() > original_queue.size():
		return false
	var remaining: Array = [0, 0, 0, 0, 0, 0]
	var total_loaded := 0
	for id in range(saved_buses.size()):
		if not saved_buses[id] is Dictionary:
			return false
		var bus: Dictionary = saved_buses[id]
		if not bus.has_all(["id", "color", "position", "angle", "kind", "capacity", "load", "status", "bay"]):
			return false
		for field in ["id", "color", "kind", "capacity"]:
			if typeof(bus[field]) != TYPE_INT or bus[field] != original_buses[id][field]:
				return false
		if typeof(bus["angle"]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(bus["angle"])): return false
		var angle_delta:float=absf(wrapf(float(bus["angle"])-float(original_buses[id]["angle"]),-PI,PI))
		var valid_angle:bool=is_zero_approx(angle_delta) or (index>=29 and is_equal_approx(angle_delta,PI))
		if bus["position"] != original_buses[id]["position"] or not valid_angle:
			return false
		if typeof(bus["load"]) != TYPE_INT or typeof(bus["bay"]) != TYPE_INT:
			return false
		if bus["load"] < 0 or bus["load"] > bus["capacity"]:
			return false
		if bus["status"] == "yard":
			if bus["load"] != 0 or bus["bay"] != -1:
				return false
		elif bus["status"] == "gone":
			if bus["load"] != bus["capacity"] or bus["bay"] != -1:
				return false
		elif bus["status"] == "docked":
			if bus["load"] >= bus["capacity"] or bus["bay"] < 0 or bus["bay"] >= TOTAL_BAYS or saved_bays[bus["bay"]] != id:
				return false
		else:
			return false
		remaining[bus["color"]] += bus["capacity"] - bus["load"]
		total_loaded += bus["load"]
	for bay in range(TOTAL_BAYS):
		var id = saved_bays[bay]
		if typeof(id) != TYPE_INT or id < -1 or id >= saved_buses.size():
			return false
		if id != -1 and bay>=open_bay_count and bay!=CRANE_BAY: return false
		if id != -1 and (saved_buses[id]["status"] != "docked" or saved_buses[id]["bay"] != bay):
			return false
	if total_loaded + saved_queue.size() != original_queue.size():
		return false
	for offset in range(saved_queue.size()):
		var color = saved_queue[offset]
		if typeof(color) != TYPE_INT or color < 0 or color >= COLORS:
			return false
		remaining[color] -= 1
	for count in remaining:
		if count != 0:
			return false
	return true

func find_hint() -> int:
	if not is_settled() or is_won():
		return -1
	var masks: Array = []
	var state := {"yard": 0, "offset": 0, "bays": bays.duplicate(), "loads": []}
	for bus: Dictionary in buses:
		var mask := 0
		if bus["status"] == "yard":
			state["yard"] = int(state["yard"]) | (1 << int(bus["id"]))
		for other: Dictionary in buses:
			if bus["id"] != other["id"] and _sweep_hits(bus, other):
				mask |= 1 << int(other["id"])
		masks.append(mask)
		state["loads"].append(bus["load"])
	_search_deadline = Time.get_ticks_usec() + 75000
	_search_aborted = false
	var path := _solve_compact(state, masks, {})
	if not path.is_empty() and path[0] >= 0:
		return path[0]
	# A search timeout must never be reported as a proven unsolvable state.
	return -3 if _search_aborted else -1

func _settle_compact(state: Dictionary) -> void:
	while state["offset"] < queue.size():
		var material: int = queue[state["offset"]]
		var best := -1
		for id in state["bays"]:
			if id != -1 and buses[id]["color"] == material:
				if best == -1 or state["loads"][id] > state["loads"][best]:
					best = id
		if best == -1:
			return
		state["loads"][best] += 1
		state["offset"] += 1
		if state["loads"][best] == buses[best]["capacity"]:
			state["bays"][state["bays"].find(best)] = -1

func _solve_compact(state: Dictionary, masks: Array, seen: Dictionary) -> Array:
	if Time.get_ticks_usec() > _search_deadline:
		_search_aborted = true
		return []
	_settle_compact(state)
	if state["yard"] == 0 and state["bays"] == [-1, -1, -1, -1, -1, -1] and state["offset"] == queue.size():
		return [-2]
	var free: int = free_bay(state["bays"])
	if free == -1:
		return []
	var key := str([state["yard"], state["offset"], state["bays"], state["loads"]])
	if seen.has(key):
		return []
	seen[key] = true
	# Ascending ID follows the layout certificate; alternate legal moves are
	# explored when earlier player choices require a different recovery path.
	for id in range(buses.size()):
		if (int(state["yard"]) & (1 << id)) == 0:
			continue
		if (masks[id] & int(state["yard"])) != 0 and maneuver_paths(id,int(state["yard"])).is_empty():
			continue
		var child: Dictionary = state.duplicate(true)
		child["yard"] = int(child["yard"]) & ~(1 << id)
		child["bays"][free] = id
		var tail := _solve_compact(child, masks, seen)
		if not tail.is_empty():
			tail.push_front(id)
			return tail
		if _search_aborted:
			return []
	return []

