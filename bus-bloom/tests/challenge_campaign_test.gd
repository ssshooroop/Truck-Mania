extends SceneTree
const M=preload("res://scripts/game_model.gd")
const S=preload("res://scripts/level_solver.gd")
func solver_for(m):
	var solver=S.new(m.buses,m.queue)
	solver.maneuver_model=m
	# Tablet trucks have scaled bodies. Build the graph with the live model,
	# not the solver constructor's default phone-sized geometry.
	for bus in m.buses:
		var mask:=0
		for other in m.buses:
			if bus.id!=other.id and m._sweep_hits(bus,other):mask |= 1<<other.id
		solver.blockers[bus.id]=mask
	return solver
func settle(m):
	while m.next_boarding()>=0:
		var id:int=m.next_boarding()
		assert(m.board_batch(id,m.batch_size(id)))
		if m.get_bus(id).status=="leaving":assert(m.depart(id))
func _initialize():
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/challenge-20261104-candidate.json"))
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/before-challenge-20261104.json"))
	assert(data.revision=="challenge-20261104","Candidate is incomplete")
	M.campaign=data.levels
	var changed:=0
	var trap_checks:=0
	for index in data.levels.size():
		var level:Dictionary=data.levels[index]
		if index<4:assert(level==old.levels[index],"Onboarding changed")
		assert(level.vehicles==old.levels[index].vehicles,"Geometry/colors/capacities changed")
		var a:Array=level.queue.duplicate();var b:Array=old.levels[index].queue.duplicate()
		a.sort();b.sort();assert(a==b,"Cargo conservation")
		var updated:bool=level.queue!=old.levels[index].queue
		if updated:changed+=1
		for tablet in [false,true]:
			var m=M.new();m.tablet_layout=tablet;m.load_level(index)
			for id in level.solution:
				assert(m.dispatch(int(id)),"Cannot dispatch level %d truck %d"%[index+1,id])
				assert(m.arrive(int(id)));settle(m)
			assert(m.is_won(),"No live win on level %d"%(index+1))
			if not updated:continue
			m.load_level(index)
			var s=solver_for(m)
			var profile=s.trap_profile(3,level.solution)
			assert(profile.trap_unknown==0)
			assert(profile.decisions*profile.critical_share>=(1 if index<10 else 2))
			# Replay a proven losing choice in the real boarding/dispatch model.
			var found:=false
			for correct in level.solution:
				var probe=solver_for(m)
				var state=probe.state_from_model(m,3)
				for wrong in probe._available(state):
					if wrong==int(correct):continue
					var child=state.duplicate(true)
					child.yard &= ~(1<<wrong);child.bays[child.bays.find(-1)]=wrong
					if probe._solve_state(child,20000)!="unsolvable":continue
					assert(m.dispatch(wrong));assert(m.arrive(wrong));settle(m)
					for step in m.buses.size():
						var moved:=false
						for bus in m.buses:
							if m.can_dispatch(bus.id):
								assert(m.dispatch(bus.id));assert(m.arrive(bus.id));settle(m);moved=true;break
						if not moved:break
					assert(m.is_stuck() and not m.is_won())
					found=true;trap_checks+=1;break
				if found:break
				assert(m.dispatch(int(correct)));assert(m.arrive(int(correct)));settle(m)
			assert(found,"Missing live trap")
		print("Verified level ",index+1)
	print("PASS: 100 levels, phone + tablet; changed=",changed," live dead ends=",trap_checks)
	quit()
