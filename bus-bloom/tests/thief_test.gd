extends SceneTree
const Model=preload("res://scripts/game_model.gd")
const Rules=preload("res://scripts/thief_rules.gd")
func totals(m) -> Array:
	var counts:Array=[0,0,0,0,0,0]
	for color in m.queue: counts[color]+=1
	for bus in m.buses: counts[bus.color]+=bus.load
	return counts
func _initialize():
	assert(Rules.mode(16)=="none" and Rules.mode(17)=="belt")
	assert(Rules.mode(18)=="none" and Rules.mode(20)=="truck")
	assert(Rules.variants(22,0)==["belt"] and Rules.variants(22,1)==["truck"])
	assert(Rules.variants(25,1)==["truck","belt"])
	var m=Model.new()
	m.load_level(16)
	var before:Array=totals(m)
	var color:int=m.queue[0]
	assert(Rules.commit(m,{"kind":"belt","target":0,"color":color}))
	assert(m.queue.back()==color and totals(m)==before)
	var bus:Dictionary=m.buses[0]
	var index:int=m.queue.find(bus.color)
	m.queue.remove_at(index)
	bus.load=1
	bus.status="docked"
	bus.bay=0
	m.bays[0]=bus.id
	assert(Rules.commit(m,{"kind":"truck","target":bus.id,"color":bus.color}))
	assert(bus.load==0 and m.queue.back()==bus.color and totals(m)==before)
	assert(not Rules.commit(m,{"kind":"truck","target":bus.id,"color":bus.color}))
	bus.status="leaving"
	bus.load=bus.capacity
	assert(not Rules.commit(m,{"kind":"truck","target":bus.id,"color":bus.color}))
	m.load_level(16)
	var start:int=Time.get_ticks_msec()
	var event:Dictionary=Rules.choose(m,0)
	print("Level 17 initial candidate: ",event," search ms=",Time.get_ticks_msec()-start)
	if not event.is_empty():
		assert(Rules.safe_candidate(m,event))
		assert(Rules.commit(m,event))
		assert(m.restore(m.undo_snapshot()))
	print("Thieves: level modes, cargo conservation, queue tail, empty/leaving guards and solvability passed")
	quit()
