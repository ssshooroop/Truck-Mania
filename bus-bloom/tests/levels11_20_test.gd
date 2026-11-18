extends SceneTree
const M=preload("res://scripts/game_model.gd")
func _initialize():
	var before:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/levels11-20-before.json"))
	for index in range(10,20):
		var model=M.new()
		model.load_level(index)
		var tablet=M.new()
		tablet.tablet_layout=true
		tablet.load_level(index)
		var original=M.new()
		original.load_level(index)
		for v in before.levels[index].vehicles:
			original.buses[int(v.id)].position=Vector2(v.x,v.y)
			original.buses[int(v.id)].angle=float(v.angle)
		for b in model.buses:
			assert(model.blocking_ids(b.id)==tablet.blocking_ids(b.id),"Tablet blocker mismatch")
			assert(original.blocking_ids(b.id).is_empty() or not model.blocking_ids(b.id).is_empty(),"Existing blocker lost")
			if not model.blocking_ids(b.id).is_empty():
				assert(model.maneuver_paths(b.id).is_empty(),"Initial blocker bypassed")
		var mask:int=(1<<model.buses.size())-1
		var turn_count:=0
		for vehicle_id in M.campaign_levels()[index].solution:
			var id:=int(vehicle_id)
			assert(model.can_dispatch(id),"Solution blocked")
			for b in model.buses:
				if b.status!="yard" or model.blocking_ids(b.id).is_empty():continue
				for path in model.maneuver_paths(b.id,mask):
					var obstacles:Array=[]
					for other in model.buses:
						if other.id!=b.id and other.status=="yard":obstacles.append(other)
					for step in range(1,path.size()):
						assert(M.YardManeuver.clear_segment(model,model.vehicle_size(b),path[step-1],path[step],obstacles))
					turn_count+=1
			model.buses[id].status="gone"
			mask &= ~(1<<id)
		print("Level %d: initial blockers preserved; progressive turns checked %d"%[index+1,turn_count])
	quit()
