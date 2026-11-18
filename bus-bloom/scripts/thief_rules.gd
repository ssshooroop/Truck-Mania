extends RefCounted
const Model = preload("res://scripts/game_model.gd")
const Solver = preload("res://scripts/level_solver.gd")
const CONFIG_PATH = "res://config/thieves.json"
static var config:Dictionary = {}

static func settings() -> Dictionary:
	if config.is_empty(): config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return config

static func mode(level:int) -> String:
	var c := settings()
	if level<int(c.first_level): return "none"
	if c.levels.has(str(level)): return c.levels[str(level)]
	return c.later_pattern[(level-31)%c.later_pattern.size()] if level>=31 else "none"

static func variants(level:int,event:int) -> Array:
	match mode(level):
		"belt": return ["belt"]
		"truck": return ["truck"] if level>=int(settings().first_truck_level) else []
		"alternate": return ["belt" if event%2==0 else "truck"]
		"both": return ["truck","belt"] if event%2 else ["belt","truck"]
	return []

static func commit(model,event:Dictionary) -> bool:
	var color:int = event.color
	if event.kind=="belt":
		var index:int=event.target
		if index<0 or index>=model.queue.size() or model.queue[index]!=color: return false
		model.queue.remove_at(index)
	else:
		var bus:Dictionary=model.get_bus(event.target)
		if bus.is_empty() or bus.status!="docked" or bus.color!=color or bus.load<=0 or bus.load>=bus.capacity: return false
		bus.load-=1
	model.queue.append(color)
	return true

static func safe_candidate(model,event:Dictionary) -> bool:
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
	if not commit(trial,event): return false
	if trial.is_stuck(): return false
	var solver=Solver.new(trial.buses,trial.queue)
	solver.maneuver_model=trial
	# Solver constructor uses canonical dimensions; live tablet geometry is scaled.
	for bus:Dictionary in trial.buses:
		var mask:int=0
		for other:Dictionary in trial.buses:
			if other.id!=bus.id and trial._sweep_hits(bus,other): mask|=1<<int(other.id)
		solver.blockers[bus.id]=mask
	var state:Dictionary=solver.state_from_model(trial,trial.open_bay_count)
	if trial.bays[Model.CRANE_BAY]>=0: state.bays.append(trial.bays[Model.CRANE_BAY])
	return solver._solve_state(state,2500)=="solvable"

static func choose(model,event_index:int) -> Dictionary:
	if not model.is_settled() or model.is_won(): return {}
	for kind in variants(model.level_index+1,event_index):
		var candidates:Array=[]
		if kind=="belt":
			for index in mini(6,model.queue.size()-1):
				var changed:bool=false
				for j in range(index+1,model.queue.size()):
					if model.queue[j]!=model.queue[index]: changed=true;break
				if changed: candidates.append({"kind":"belt","target":index,"color":model.queue[index]})
		else:
			for bus:Dictionary in model.buses:
				if bus.status=="docked" and bus.load>0 and bus.load<bus.capacity:
					candidates.append({"kind":"truck","target":bus.id,"color":bus.color})
		for candidate in candidates.slice(0,3):
			if safe_candidate(model,candidate): return candidate
	return {}
