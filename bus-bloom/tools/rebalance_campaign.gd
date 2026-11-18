extends SceneTree
const M=preload("res://scripts/game_model.gd")
const S=preload("res://scripts/level_solver.gd")
const REV="challenge-20261104"
func _initialize():
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/campaign.json"))
	var backup="res://artifacts/before-"+REV+".json"
	if not FileAccess.file_exists(backup):FileAccess.open(backup,FileAccess.WRITE).store_string(JSON.stringify(data))
	var report:Array=[]
	for index in range(4,data.levels.size()):
		var m=M.new();m.load_level(index)
		var s=S.new(m.buses,m.queue);s.maneuver_model=m
		var rng=RandomNumberGenerator.new();rng.seed=2026110400+index
		var original=m.queue.duplicate()
		var before=s.simulate(3,120,1.0,0,3,rng)
		var target:float=[0.35,0.5,0.65,0.4,0.75][index%5] if index<10 else [0.65,0.8,0.55,0.8,0.9][index%5]
		var best=original.duplicate();var best_path:Array=data.levels[index].solution
		var best_score:float=-INF
		var best_profile:Dictionary={}
		for attempt in 500:
			var q:Array=best.duplicate() if attempt%4!=0 else original.duplicate()
			if attempt>0:
				for swap in rng.randi_range(1,6):
					var a=rng.randi_range(0,q.size()-1);var b=rng.randi_range(0,q.size()-1)
					var tmp=q[a];q[a]=q[b];q[b]=tmp
			s.queue=q
			var solved=s.solve(3,10000)
			if solved.status!="solvable":continue
			var stats=s.simulate(3,40,1.0,0,3,rng)
			var score:float=-absf(float(stats.fail_rate)-maxf(target,float(before.fail_rate)))
			if score<=best_score:continue
			var profile=s.trap_profile(3,solved.path,10000)
			if profile.trap_unknown>0:continue
			if profile.decisions*profile.critical_share<(1 if index<10 else 2):continue
			best_score=score;best=q.duplicate();best_path=solved.path.duplicate();best_profile=profile
			if score>=-0.025 and attempt>=80:break
		s.queue=best
		var after=s.simulate(3,400,1.0,0,3,rng)
		# Do not ship a regression masked by the smaller candidate sample.
		if float(after.fail_rate)+0.03<float(before.fail_rate):
			best=original;best_path=data.levels[index].solution;s.queue=best
			after=s.simulate(3,400,1.0,0,3,rng)
		best_profile=s.trap_profile(3,best_path,20000)
		data.levels[index].queue=best
		data.levels[index].solution=best_path
		data.levels[index].campaign.solution=best_path
		data.levels[index].queue_audit={"revision":REV,"not_player_win_rate":true,"policy_greedy_failure":after.fail_rate,"profile":best_profile}
		var row={"level":index+1,"changed":best!=original,"before":before.fail_rate,"after":after.fail_rate,"profile":best_profile}
		report.append(row);print(JSON.stringify(row))
		FileAccess.open("res://artifacts/"+REV+"-candidate.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
		FileAccess.open("res://artifacts/"+REV+"-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	data.revision=REV
	FileAccess.open("res://artifacts/"+REV+"-candidate.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	quit()
