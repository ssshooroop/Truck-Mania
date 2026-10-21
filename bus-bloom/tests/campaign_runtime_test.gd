extends SceneTree
const Model = preload("res://scripts/game_model.gd")
const Economy = preload("res://scripts/runtime_economy.gd")
var checks := 0
var failures := 0
func check(value:bool,message:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var model = Model.new()
	check(model.level_count()==100,"Runtime loads 100 levels")
	for index in model.level_count():
		check(model.load_level(index),"Load campaign level")
		check(model.open_bay_count==3,"Three initial bays")
		var level: Dictionary = Model.campaign_levels()[index]
		var colors := {}
		for bus: Dictionary in model.buses: colors[bus.color] = int(colors.get(bus.color,0))+1
		check(colors.size()>=4 and colors.size()==int(level.metrics.color_count),"Actual colour diversity matches metadata")
		check(float(colors.values().max())/model.buses.size()<=0.40,"No colour dominates more than 40 percent of trucks")
		if index<10 and index!=2: check(float(level.campaign.novice_attempts)<=3.5,"Early difficulty remains capped")
		if index==2: check(float(level.tutorial.post_booster_win)>=0.9,"Teaching slot still rescues the novice")
		for bus: Dictionary in model.buses:
			for other: Dictionary in model.buses:
				if bus.id<other.id: check(not model._footprints_overlap(bus,other),"No initial overlaps level %d" % (index+1))
		for id in level.solution:
			check(model.dispatch(int(id)),"Certificate dispatch level %d truck %d" % [index+1,int(id)])
			model.arrive(int(id))
			while model.next_boarding()>=0:
				var next: int = model.next_boarding()
				model.board_batch(next,model.batch_size(next))
				if model.get_bus(next).status=="leaving": model.depart(next)
			check(model.restore(model.snapshot()),"Snapshots restore with campaign data")
		check(model.is_won(),"Certified solution wins level %d" % (index+1))
	var economy = Economy.new()
	check(economy.base_reward(1)==21 and economy.base_reward(100)==35,"Square root reward formula")
	check(economy.completion(0,1,26,false,3,3).total==26,"First clean win grants 21+5")
	check(economy.completion(1,2,30,false,3,3).streak==10,"Clean series grows")
	check(economy.completion(2,3,24,true,3,4).streak==0 and economy.state.clean_streak==2,"Rescue freezes series without bonus")
	economy.failure(3)
	check(economy.state.clean_streak==0,"Restart resets clean series")
	var milestone: Dictionary = economy.completion(9,10,30,false,3,3)
	check(milestone.chest==50 and milestone.achievements==50,"Tenth completion grants chest and achievement")
	check(economy.completion(10,11,30,false,3,3).achievements==0,"Achievement pays once")
	check(economy.daily_reward(200)==0,"First visit initializes calendar")
	check(economy.daily_reward(201)==20 and economy.daily_reward(201)==0,"Daily login once per UTC day")
	check(economy.daily_reward(202)==30 and economy.daily_reward(205)==20,"Daily sequence and missed day reset")
	var restored = Economy.new()
	restored.restore(economy.state.duplicate(true))
	check(restored.daily_reward(205)==0,"Login cannot repeat after restore")
	print("Campaign runtime: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
