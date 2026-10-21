extends SceneTree
const Probe = preload("res://tests/motion_probe.gd")
var game
var failures := 0
var checks := 0
func check(value:bool,message:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	game = Probe.new()
	root.add_child.call_deferred(game)
	_run.call_deferred()
func stuck() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	for attempt in 100:
		game._load_level(2)
		for step in 20:
			var available: Array = []
			for bus: Dictionary in game.model.buses:
				if game.model.can_dispatch(bus.id): available.append(bus.id)
			if available.is_empty(): break
			var id: int = available[rng.randi_range(0,available.size()-1)]
			game.model.dispatch(id)
			game.model.arrive(id)
			game.moves += 1
			while game.model.next_boarding()>=0:
				var next: int = game.model.next_boarding()
				game.model.board_batch(next,game.model.batch_size(next))
				if game.model.buses[next].status=="leaving": game.model.depart(next)
		if game.model.is_stuck():
			game._sync_visuals()
			game.overlay = "stuck"
			return
	check(false,"A seeded novice reaches a tutorial deadlock")
func _run() -> void:
	check(game.coins==50,"New player starts with 50 coins")
	game._load_level(0)
	check(game._claim_level_reward(0)==26,"Runtime awards configured reward")
	var wallet: int = game.coins
	check(game._claim_level_reward(0)==0 and game.coins==wallet,"Replay cannot farm reward")
	stuck()
	game._check_end()
	check(game.overlay=="slot_offer","First deadlock triggers spotlight")
	game._purchase_slot()
	check(game.model.open_bay_count==4 and game.coins==wallet,"Tutorial slot is free")
	check(game.economy.state.tutorial_done,"Tutorial completion persists")
	game._open_slot_offer(4)
	game.coins = 1000
	game._purchase_slot()
	check(game.model.open_bay_count==5 and game.coins==900,"Next slot uses first paid rescue price")
	game._load_level(3)
	check(game.model.open_bay_count==3,"Extra slots reset on new attempt")
	game.economy.state.tutorial_done = false
	check(game._free_tutorial_slot(),"Skipped tutorial remains available after level 3")
	game.economy.state.tutorial_done = true
	for tool in ["crane","swap","shuffle"]:
		stuck()
		game.coins = 1000
		game.overlay = "rescue_menu"
		var total_before: int = game.model.queue.size()
		for bus: Dictionary in game.model.buses: total_before += int(bus.load)
		check(game._can_rescue(tool),"Tool available: "+tool)
		await game._purchase_rescue(tool)
		# A rescue may also complete the level and immediately credit its reward.
		check(game.coins-game.level_reward==1000-int(game.economy.config.rescue[tool+"_cost"]),"Charge tool exactly once: "+tool)
		var total_after: int = game.model.queue.size()
		for bus: Dictionary in game.model.buses: total_after += int(bus.load)
		check(total_before==total_after,"Cargo conserved: "+tool)
		check(game.model.restore(game.model.snapshot()),"Undo snapshots valid after "+tool)
		check(game.rescue_count==1 and game.attempt_rescued,"Rescue accounting: "+tool)
		check(game.history.is_empty(),"Undo cannot duplicate paid rescue")
	game.save_enabled = true
	game.save_path = "user://campaign_test.cfg"
	game._save()
	var saved_coins: int = game.coins
	game.coins = 0
	game.economy.state.tutorial_done = false
	game._load_save()
	check(game.coins==saved_coins and game.economy.state.tutorial_done,"Wallet and tutorial restore")
	DirAccess.remove_absolute(game.save_path)
	game.save_enabled = false
	game.queue_free()
	await process_frame
	print("Campaign UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
