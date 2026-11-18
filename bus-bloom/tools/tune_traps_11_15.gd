extends SceneTree
const M=preload("res://scripts/game_model.gd")
const S=preload("res://scripts/level_solver.gd")
func _initialize():
	var rng=RandomNumberGenerator.new()
	rng.seed=23101542
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/campaign.json"))
	FileAccess.open("res://artifacts/before-traps-11-15.json",FileAccess.WRITE).store_string(JSON.stringify(data))
	var report:Array=[]
	for index in range(10,15):
		var m=M.new()
		m.load_level(index)
		var solver=S.new(m.buses,m.queue)
		solver.maneuver_model=m
		var old=solver.simulate(3,300,1.0,0,3,rng)
		var original_q:Array=m.queue.duplicate()
		var original_colors:Array=[]
		for b in m.buses:original_colors.append(b.color)
		var best_q=original_q.duplicate()
		var best_colors=original_colors.duplicate()
		var best_score=-INF
		var best_path:Array=[]
		var target:float=[0.65,0.75,0.85,0.55,0.8][index-10]
		for attempt in 2400:
			var candidate:Array=best_q.duplicate() if attempt%4!=0 else original_q.duplicate()
			var colors:Array=best_colors.duplicate() if attempt%4!=0 else original_colors.duplicate()
			for swap in rng.randi_range(1,5):
				var a=rng.randi_range(0,candidate.size()-1)
				var b=rng.randi_range(0,candidate.size()-1)
				var tmp=candidate[a];candidate[a]=candidate[b];candidate[b]=tmp
			if attempt%2==0:
				var a=rng.randi_range(0,colors.size()-1)
				var b=rng.randi_range(0,colors.size()-1)
				if m.buses[a].capacity==m.buses[b].capacity:
					var tmp=colors[a];colors[a]=colors[b];colors[b]=tmp
			for i in colors.size():m.buses[i].color=int(colors[i])
			solver.queue=candidate
			var solved=solver.solve(3,12000)
			if solved.status!="solvable":continue
			var greedy=solver.simulate(3,40,1.0,0,3,rng)
			if greedy.fail_rate<0.35:continue
			var profile=solver.trap_profile(3,solved.path,12000)
			if profile.trap_unknown>0 or profile.decisions*profile.critical_share<2:continue
			var score=-absf(greedy.fail_rate-target)+profile.critical_share*0.25+profile.trap_ratio*0.15
			if score>best_score:
				best_score=score;best_q=candidate.duplicate();best_colors=colors.duplicate();best_path=solved.path.duplicate()
		if best_path.is_empty():
			push_error("No candidate %d"%(index+1));quit(1);return
		for i in best_colors.size():
			m.buses[i].color=int(best_colors[i])
			data.levels[index].vehicles[i].color=int(best_colors[i])
		solver.queue=best_q
		var profile=solver.trap_profile(3,best_path)
		var stats=solver.simulate(3,1000,1.0,0,3,rng)
		data.levels[index].queue=best_q
		data.levels[index].solution=best_path
		data.levels[index].campaign.solution=best_path
		data.levels[index].min_slots=solver.min_slots(3).min_slots
		data.levels[index].queue_audit={"revision":"traps-11-15-20261023","not_player_win_rate":true,"policy_greedy_failure":stats.fail_rate,"profile":profile}
		report.append({"level":index+1,"before":old.fail_rate,"after":stats.fail_rate,"profile":profile,"solution":best_path})
		print(report.back())
	data.revision="traps-11-15-20261023"
	FileAccess.open("res://config/campaign.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	FileAccess.open("res://artifacts/traps-11-15-audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()
