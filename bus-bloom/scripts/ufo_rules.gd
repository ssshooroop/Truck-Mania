extends RefCounted
const Model = preload("res://scripts/game_model.gd")
const Solver = preload("res://scripts/level_solver.gd")
const FIRST_LEVEL := 30
const NODE_LIMIT := 20000

static func eligible(model) -> bool:
	if model.level_index+1<FIRST_LEVEL or not model.is_settled() or model.free_bay()<0: return false
	# The extra crane berth is not a normal available loading slot.
	for index in range(model.open_bay_count,model.bays.size()):
		if model.bays[index]>=0: return false
	return true

static func _copy_model(model):
	var trial=Model.new()
	trial.level_index=model.level_index
	trial.buses=model.buses.duplicate(true)
	trial.queue=model.queue.duplicate()
	trial.bays=model.bays.duplicate()
	trial.open_bay_count=model.open_bay_count
	trial.layout_scale=model.layout_scale
	trial.tablet_layout=model.tablet_layout
	trial.layout_transform=model.layout_transform
	trial.yard_rect=model.yard_rect
	return trial

static func _safe_turn(trial,id:int) -> bool:
	if id<0 or id>=trial.buses.size() or trial.buses[id].status!="yard": return false
	var bus:Dictionary=trial.buses[id]
	bus.angle=wrapf(float(bus.angle)+PI,-PI,PI)
	trial._maneuver_cache.clear()
	var solver=Solver.new(trial.buses,trial.queue)
	solver.maneuver_model=trial
	# Use actual scaled bodies and the current yard, not constructor defaults.
	for vehicle:Dictionary in trial.buses:
		var mask:=0
		for other:Dictionary in trial.buses:
			if vehicle.id!=other.id and trial._sweep_hits(vehicle,other): mask |= 1<<other.id
		solver.blockers[vehicle.id]=mask
	var state:Dictionary=solver.state_from_model(trial,trial.open_bay_count)
	# Reject cyclic geometric dependencies before the more expensive cargo search.
	var remaining:int=state.yard
	while remaining!=0:
		var previous:=remaining
		for vehicle:Dictionary in trial.buses:
			if remaining & (1<<vehicle.id) and not (solver.blockers[vehicle.id] & remaining): remaining &= ~(1<<vehicle.id)
		if remaining==previous: return false
	# Unknown/timeout is not a certificate: skip this turn rather than risk a dead end.
	return solver._solve_state(state,NODE_LIMIT)=="solvable"

static func safe_targets(model) -> Array[int]:
	var result:Array[int]=[]
	if not eligible(model): return result
	var trial=_copy_model(model)
	for bus:Dictionary in trial.buses:
		if bus.status!="yard": continue
		var original:float=bus.angle
		if _safe_turn(trial,bus.id): result.append(bus.id)
		bus.angle=original
	return result

static func commit(model,id:int) -> bool:
	if not eligible(model) or not _safe_turn(_copy_model(model),id): return false
	model.buses[id].angle=wrapf(float(model.buses[id].angle)+PI,-PI,PI)
	model._maneuver_cache.clear()
	return true
