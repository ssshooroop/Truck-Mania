extends SceneTree
const Model=preload("res://scripts/game_model.gd")
func _initialize():
	var m=Model.new()
	assert(m.level_count()==100)
	for i in range(10,100):
		assert(m.load_level(i))
		for b in m.buses:
			for other in m.buses:
				if b.id<other.id:assert(not m._footprints_overlap(b,other),"Overlap level %d"%(i+1))
		for id in Model.campaign_levels()[i].solution:
			assert(m.dispatch(int(id)),"Dispatch level %d truck %d"%[i+1,id])
			m.arrive(int(id))
			while m.next_boarding()>=0:
				var next:int=m.next_boarding()
				m.board_batch(next,m.batch_size(next))
				if m.get_bus(next).status=="leaving":m.depart(next)
		assert(m.is_won(),"Solution level %d"%(i+1))
	print("Levels 11–100: all solutions and initial geometry verified")
	quit()
