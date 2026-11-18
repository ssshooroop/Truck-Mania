extends SceneTree
const Model=preload("res://scripts/game_model.gd")
const Rules=preload("res://scripts/ufo_rules.gd")
const Solver=preload("res://scripts/level_solver.gd")
func model_count():return Model.new().level_count()
func verify_finish(model):
	var solver=Solver.new(model.buses,model.queue)
	solver.maneuver_model=model
	for a in model.buses:
		var mask=0
		for b in model.buses:
			if a.id!=b.id and model._sweep_hits(a,b):mask |= 1<<b.id
		solver.blockers[a.id]=mask
	solver._node_limit=20000
	var path=[]
	assert(solver._search(solver.state_from_model(model,model.open_bay_count),path),"No full solution after UFO")
	for id in path:
		assert(model.dispatch(id));assert(model.arrive(id))
		while model.next_boarding()>=0:
			var loader=model.next_boarding()
			assert(model.board_batch(loader,model.batch_size(loader)))
			if model.buses[loader].status=="leaving":assert(model.depart(loader))
	assert(model.is_won(),"Live game cannot replay UFO solution")
func _initialize():run.call_deferred()
func run():
	var count:=0
	for tablet in [false,true]:
		for level in range(29,model_count()):
			var model=Model.new()
			model.tablet_layout=tablet
			model.load_level(level)
			var before=model.snapshot()
			var targets=Rules.safe_targets(model)
			if level==100:
				for bad in [0,2,5,6,9,14,15,16,18]:assert(bad not in targets,"Level 101 cycle accepted")
			assert(model.buses==before.buses)
			for id in targets:
				assert(Rules.commit(model,id))
				var free:=false
				for bus in model.buses:
					if model.can_dispatch(bus.id):free=true
				assert(free,"UFO must preserve an available departure")
				assert(model.queue==before.queue and model.bays==before.bays)
				assert(model.restore(model.snapshot()),"Flipped orientations must survive undo snapshots")
				verify_finish(model)
				assert(model.restore(before))
				count+=1
			model.bays=[0,1,2,3,4,5]
			assert(Rules.safe_targets(model).is_empty())
	# Mid-level turns must preserve the actual remaining queue and occupied bays.
	for tablet in [false,true]:
		var partial=Model.new();partial.tablet_layout=tablet;partial.load_level(100)
		for raw in Model.campaign_levels()[100].solution:
			var snapshot=partial.snapshot()
			for target in Rules.safe_targets(partial):
				assert(Rules.commit(partial,target))
				verify_finish(partial)
				assert(partial.restore(snapshot))
			var id=int(raw)
			assert(partial.dispatch(id));assert(partial.arrive(id))
			while partial.next_boarding()>=0:
				var loader=partial.next_boarding()
				partial.board_batch(loader,partial.batch_size(loader))
				if partial.buses[loader].status=="leaving":partial.depart(loader)
		assert(partial.is_won())
	var regression=Model.new();regression.load_level(100)
	var unchanged=regression.snapshot()
	assert(not Rules.commit(regression,18))
	assert(regression.snapshot()==unchanged,"Rejected UFO changed the game")
	var model=Model.new()
	model.load_level(28)
	assert(Rules.safe_targets(model).is_empty())
	var game=preload("res://scripts/main.gd").new()
	game.automation=true;game.save_enabled=false
	root.add_child(game)
	game._load_level(29)
	game._cancel_animation()
	var ids=Rules.safe_targets(game.model)
	assert(not ids.is_empty())
	var id:int=ids[0]
	var angle:float=game.model.buses[id].angle
	game._start_ufo(id)
	assert(game.busy and not game.ufo_state.is_empty())
	game.overlay="settings"
	game._update_ufo(2.0)
	assert(game.ufo_state.time==0.0)
	game.overlay=""
	game._update_ufo(3.8)
	assert(game.ufo_events==1 and not is_equal_approx(game.model.buses[id].angle,angle))
	game._update_ufo(2.0)
	assert(game.ufo_state.is_empty() and not game.busy)
	game._start_ufo(id)
	game._load_level(0)
	assert(game.ufo_state.is_empty() and game.ufo_events==0)
	game.queue_free();await process_frame
	print("PASS: %d safe rotations on levels 30-150, phone/tablet, snapshot restore, pause, completion, reload, full parking"%count)
	quit()
