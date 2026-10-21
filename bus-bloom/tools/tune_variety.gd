extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const Generator = preload("res://scripts/level_candidate_generator.gd")
const Solver = preload("res://scripts/level_solver.gd")
const Evaluator = preload("res://scripts/level_evaluator.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/campaign-before-variety.json"))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/level_pipeline.json"))
	var generator = Generator.new()
	var evaluator = Evaluator.new()
	evaluator.configure(config.evaluation)
	var model = Model.new()
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/campaign.json"))
	var only_first: bool = "--only-first" in OS.get_cmdline_user_args()
	var output: Array = []
	var report: Array = []
	for index in data.levels.size():
		var old: Dictionary = data.levels[index]
		if only_first and index>0:
			var kept: Dictionary = current.levels[index]
			output.append(kept)
			report.append({"level":index+1,"colors":kept.metrics.color_count,"old_fail":old.campaign.fail_rate,"new_fail":kept.campaign.fail_rate,"novice_attempts":kept.campaign.novice_attempts,"target":kept.campaign.target})
			continue
		model.load_level(index)
		var colors: int = 4 if index<5 else (5 if index<10 or index%3==0 else 6)
		var target: float = clampf(float(old.campaign.fail_rate)+0.06,0.10,0.78)
		if index==2: target = 0.36
		var best: Dictionary = {}
		var best_cost := INF
		for attempt in 500:
			var seed_value: int = 610000+index*1000+attempt
			generator.rng.seed = seed_value
			var vehicles: Array = model.buses.duplicate(true)
			var labels: Array = []
			for i in vehicles.size(): labels.append(i%colors)
			for i in range(labels.size()-1,0,-1):
				var j: int = generator.rng.randi_range(0,i)
				var tmp = labels[i]; labels[i] = labels[j]; labels[j] = tmp
			for i in vehicles.size(): vehicles[i].color = labels[i]
			var order: Array = []
			for id in old.dispatch_order: order.append(int(id))
			var overlaps := [0]
			var window: int = 2 if index<2 or attempt%3==0 else 3
			var cargo: Array = generator._build_queue(vehicles,order,window,3,colors,0.08,overlaps)
			var counts := {}
			var units := {}
			for v: Dictionary in vehicles:
				counts[v.color] = int(counts.get(v.color,0))+1
				units[v.color] = int(units.get(v.color,0))+int(v.capacity)
			if counts.size()!=colors: continue
			if counts.values().max()>ceili(float(vehicles.size())/colors)+1: continue
			if float(counts.values().max())/vehicles.size()>0.40 or float(units.values().max())/cargo.size()>0.45: continue
			var solver = Solver.new(vehicles,cargo)
			var solved: Dictionary = solver.solve(3,100000)
			if solved.status!="solvable": continue
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value+2000000
			var profile: Dictionary = solver.simulate(3,200,0.7,2,5,rng)
			if profile.fail_rate>maxf(0.15,float(old.campaign.fail_rate)+0.12): continue
			solver.simulate(3,100,0.0,0,3,rng)
			var novice: Dictionary = solver.simulate(3,100,0.35,0,3,rng)
			if index==0 and novice.fail_rate>0.33: continue
			if index==1 and novice.fail_rate>0.40: continue
			if index<10 and novice.fail_rate>0.71: continue
			if index==2:
				var tutorial: Dictionary = solver.onboarding_profile(3,120,0.35,"slot",rng)
				if tutorial.onboarding_deadlock_rate<0.6 or tutorial.onboarding_post_win<0.9: continue
			var cost: float = absf(profile.fail_rate-target)
			if cost<best_cost:
				best_cost = cost
				best = {"ok":true,"seed":seed_value,"vehicles":vehicles,"queue":cargo,"dispatch_order":order,
					"metrics":{"vehicle_count":vehicles.size(),"cargo_count":cargo.size(),"color_count":colors,
					"queue_window":window,"color_switches":generator._count_switches(cargo),"same_color_chance":0.08,
					"same_color_overlaps":overlaps[0],"placement_attempts":0,"initially_dispatchable":generator._count_initially_dispatchable(vehicles)}}
			if best_cost<=0.025: break
		if best.is_empty():
			push_error("No diverse candidate for level %d" % (index+1))
			quit(1)
			return
		# Vary the palette across levels instead of always taking the first N colours.
		var palette: Array = [0,1,2,3,4,5]
		generator.rng.seed = 99000+index
		for i in range(5,0,-1):
			var j: int = generator.rng.randi_range(0,i)
			var tmp = palette[i]; palette[i] = palette[j]; palette[j] = tmp
		for v: Dictionary in best.vehicles: v.color = palette[v.color]
		for i in best.queue.size(): best.queue[i] = palette[best.queue[i]]
		var evaluation: Dictionary = evaluator.evaluate(best,int(best.seed)+2000000)
		if evaluation.category=="rejected":
			push_error("Rejected final candidate at level %d" % (index+1)); quit(1); return
		var level: Dictionary = generator.to_json_data(best)
		level.solver_verified = true
		level.min_slots = evaluation.min_slots
		level.solution = evaluation.solution
		level.campaign = evaluation.duplicate(true)
		level.campaign.level = index+1
		level.campaign.type = old.campaign.type
		level.campaign.planned = old.campaign.planned
		level.campaign.target = target
		level.campaign.revision = "variety-2026-10-15"
		if index==2:
			level.tutorial = {"booster":"slot","hint":"first_deadlock","free":true,
				"novice_deadlock_rate":evaluation.onboarding_deadlock_rate,"post_booster_win":evaluation.onboarding_post_win}
		output.append(level)
		report.append({"level":index+1,"colors":colors,"old_fail":old.campaign.fail_rate,"new_fail":evaluation.fail_rate,
			"novice_attempts":evaluation.novice_attempts,"target":target,"selection_error":best_cost})
		print("TUNED %d colors=%d fail=%.3f -> %.3f" % [index+1,colors,old.campaign.fail_rate,evaluation.fail_rate])
	data.levels = output
	data.revision = "variety-2026-10-15"
	for path in ["res://config/campaign.json","res://generated_levels/levels.json"]:
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	FileAccess.open("res://generated_levels/variety_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TUNING_COMPLETE ",output.size())
	quit()
