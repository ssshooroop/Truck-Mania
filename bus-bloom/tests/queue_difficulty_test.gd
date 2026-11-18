extends SceneTree
const M=preload("res://scripts/game_model.gd")
const Solver=preload("res://scripts/level_solver.gd")
func _initialize():
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/before-queue-tuning-20261023.json"))
	var report:Array=[]
	for index in range(10,20):
		var m=M.new()
		m.load_level(index)
		var old:Array=[]
		for color in baseline.levels[index].queue:old.append(int(color))
		var now:Array=m.queue.duplicate()
		old.sort()
		now.sort()
		assert(old==now,"Cargo quantities changed")
		var solver=Solver.new(m.buses,m.queue)
		solver.maneuver_model=m
		assert(solver.solve(3).status=="solvable")
		var slots2:Dictionary=solver.solve(2)
		var rng=RandomNumberGenerator.new()
		rng.seed=20261023+index
		var after:Dictionary=solver.simulate(3,500,1.0,0,3,rng)
		solver.queue=baseline.levels[index].queue
		rng.seed=20261023+index
		var before:Dictionary=solver.simulate(3,500,1.0,0,3,rng)
		report.append({"level":index+1,"runs":500,"policy":"nearest-needed cargo, random ties; not human win rate","failure_before":before.fail_rate,"failure_after":after.fail_rate,"two_slots":slots2.status})
		print(report.back())
	FileAccess.open("res://artifacts/queue-audit-20261023.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()
