extends SceneTree
const M=preload("res://scripts/game_model.gd")
const S=preload("res://scripts/level_solver.gd")
func settle(m):
	while m.next_boarding()>=0:
		var id:int=m.next_boarding()
		assert(m.board_batch(id,m.batch_size(id)))
		if m.get_bus(id).status=="leaving":assert(m.depart(id))
func _initialize():
	var before:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/before-traps-11-15.json"))
	var now=M.campaign_levels()
	var examples:Array=[]
	for i in now.size():
		if i<10 or i>14:assert(now[i]==before.levels[i],"Unrelated level changed")
	for index in range(10,15):
		for tablet in [false,true]:
			var m=M.new();m.tablet_layout=tablet;m.load_level(index)
			var solver=S.new(m.buses,m.queue);solver.maneuver_model=m
			var solution:Array=now[index].solution
			var profile=solver.trap_profile(3,solution)
			assert(profile.trap_unknown==0 and profile.decisions*profile.critical_share>=2)
			var example:Dictionary={}
			var prefix:Array=[]
			for next in solution:
				if example.is_empty():
					var probe=S.new(m.buses,m.queue)
					probe.maneuver_model=m
					var state=probe.state_from_model(m,3)
					for wrong in probe._available(state):
						if wrong==int(next):continue
						var child=state.duplicate(true)
						child.yard &= ~(1<<wrong)
						child.bays[child.bays.find(-1)]=wrong
						if probe._solve_state(child,20000)=="unsolvable":
							example={"level":index+1,"tablet":tablet,"prefix":prefix.duplicate(),"wrong":wrong,"right":int(next)}
							break
				assert(m.dispatch(int(next)));assert(m.arrive(int(next)));settle(m);prefix.append(int(next))
			assert(m.is_won() and not example.is_empty())
			# Replay a proven bad branch in the live model and reach the actual stuck condition.
			m.load_level(index)
			for id in example.prefix:
				assert(m.dispatch(id));m.arrive(id);settle(m)
			assert(m.dispatch(example.wrong));m.arrive(example.wrong);settle(m)
			for step in m.buses.size():
				var moved=false
				for b in m.buses:
					if m.can_dispatch(b.id):
						m.dispatch(b.id);m.arrive(b.id);settle(m);moved=true;break
				if not moved:break
			assert(m.is_stuck() and not m.is_won())
			examples.append(example)
	FileAccess.open("res://artifacts/trap-examples-11-15.json",FileAccess.WRITE).store_string(JSON.stringify(examples,"\t"))
	print("11–15: live wins and proven dead-end choices verified on phone/tablet; other levels unchanged")
	quit()
