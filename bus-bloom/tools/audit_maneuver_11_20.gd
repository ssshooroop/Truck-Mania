extends SceneTree
const M=preload("res://scripts/game_model.gd")
func _initialize():
	for index in range(10,20):
		var m=M.new()
		m.load_level(index)
		var mask:int=(1<<m.buses.size())-1
		var direct:Array=[]
		var turns:Array=[]
		for b in m.buses:
			if m.blocking_ids(b.id).is_empty():direct.append(b.id)
			elif not M.YardManeuver.paths(m,b.id,mask).is_empty():turns.append(b.id)
			if index==12:print("L13 ",b," blockers=",m.blocking_ids(b.id))
		print("LEVEL ",index+1," direct ",direct," extra maneuvers ",turns)
	quit()
