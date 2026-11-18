extends SceneTree
const M=preload("res://scripts/game_model.gd")
func _initialize():
	var m=M.new()
	m.load_level(12)
	for b in m.buses:
		if b.color==0 and not m.blocking_ids(b.id).is_empty():
			assert(m.maneuver_paths(b.id).is_empty(),"Yellow truck must bump initially")
	# An otherwise open yard is not permission to pivot away from a close nose blocker.
	m.buses=[{"id":0,"kind":1,"position":Vector2(270,850),"angle":0.0,"status":"yard"},{"id":1,"kind":0,"position":Vector2(270,729),"angle":0.0,"status":"yard"}]
	assert(not m.blocking_ids(0).is_empty())
	assert(M.YardManeuver.paths(m,0,3).is_empty())
	m.buses[1].position=Vector2(270,550)
	var paths:Array=M.YardManeuver.paths(m,0,3)
	assert(not paths.is_empty(),"A genuinely clear forward approach still permits turns")
	for path in paths:
		var last:Vector2=path[0].position
		for pose in path:
			if not is_equal_approx(pose.angle,0.0):
				assert(last.distance_to(path[0].position)>=m.vehicle_size(m.buses[0]).y*0.349)
				break
			last=pose.position
	print("Close blockers bump; forward clearance required before every turn")
	quit()
