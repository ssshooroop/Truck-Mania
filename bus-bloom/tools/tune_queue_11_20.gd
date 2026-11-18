extends SceneTree
const M=preload("res://scripts/game_model.gd")
const Solver=preload("res://scripts/level_solver.gd")
var rng=RandomNumberGenerator.new()
func _initialize():
	rng.seed=23102026
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/before-queue-tuning-20261023.json"))
	# Keep the pre-change baseline immutable.
	var report:Array=[]
	for index in range(10,20):
		var model=M.new()
		model.load_level(index)
		var original:Array=[]
		for color in data.levels[index].queue:original.append(int(color))
		var solver=Solver.new(model.buses,original)
		solver.maneuver_model=model
		var before:Dictionary=solver.simulate(3,80,1.0,0,3,rng)
		var best:Array=original.duplicate()
		var best_score:float=-INF
		var solution:Array=data.levels[index].solution
		var stats:Dictionary={}
		for attempt in 1600:
			var candidate:Array=best.duplicate() if attempt%3!=0 else original.duplicate()
			for swap in rng.randi_range(1,8):
				var a:int=rng.randi_range(0,candidate.size()-1)
				var b:int=rng.randi_range(0,candidate.size()-1)
				var temp=candidate[a]
				candidate[a]=candidate[b]
				candidate[b]=temp
			# Require a certificate under the stricter straight-exit rule too.
			solver.queue=candidate
			solver.maneuver_model=null
			var solved:Dictionary=solver.solve(3,5000)
			if solved.status!="solvable":continue
			if solver.solve(2,3000).status!="unsolvable":continue
			solver.maneuver_model=model
			var greedy:Dictionary=solver.simulate(3,24,1.0,0,3,rng)
			var mixed:Dictionary=solver.simulate(3,40,0.7,0,3,rng)
			var target:float=0.2 if index in [10,14,17] else 0.35
			var score:float=-absf(greedy.fail_rate-maxf(target,before.fail_rate))-absf(mixed.fail_rate-0.6)*0.6
			if greedy.fail_rate<before.fail_rate-0.08:score-=2.0
			if score>best_score:
				best_score=score
				best=candidate.duplicate()
				solution=solved.path.duplicate()
				stats={"greedy_failure":greedy.fail_rate,"mixed_failure":mixed.fail_rate}
		if stats.is_empty():
			push_error("No verified queue candidate for level %d"%(index+1))
			quit(1)
			return
		solver.queue=best
		solver.maneuver_model=model
		var final_greedy:Dictionary=solver.simulate(3,300,1.0,0,3,rng)
		var final_mixed:Dictionary=solver.simulate(3,300,0.7,0,3,rng)
		data.levels[index].queue=best
		data.levels[index].solution=solution
		data.levels[index]["queue_audit"]={"revision":"20261023","slots":3,"runs":300,"policy_greedy_failure":final_greedy.fail_rate,"policy_mixed_failure":final_mixed.fail_rate,"not_player_win_rate":true}
		report.append({"level":index+1,"greedy_before":before.fail_rate,"greedy_after":final_greedy.fail_rate,"mixed_after":final_mixed.fail_rate})
		print(report.back())
	data.revision="queue-challenge-20261023"
	FileAccess.open("res://config/campaign.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	FileAccess.open("res://artifacts/queue-audit-20261023.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()

