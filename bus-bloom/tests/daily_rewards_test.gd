extends SceneTree
func _initialize():run.call_deferred()
func run():
	var rewards=preload("res://scripts/daily_rewards.gd").new()
	var inventory={}
	var total:=0
	for day in 7:
		var result=rewards.claim(100+day,inventory)
		assert(result.index==day)
		total+=int(result.coins)
		assert(rewards.claim(100+day,inventory).index==-1)
	assert(total==400 and inventory.undo==3)
	var restored=preload("res://scripts/daily_rewards.gd").new()
	restored.restore(rewards.calendar.state.duplicate(true))
	assert(restored.claim(106,inventory).index==-1)
	restored.config.weeks.append({"days":[{"rewards":[{"item":"crane","quantity":2},{"item":"extra_slot","quantity":1}]}]})
	assert(restored.claim(107,inventory).index==0)
	assert(inventory.crane==2 and inventory.extra_slot==1)
	var game=preload("res://scripts/main.gd").new()
	game.automation=true
	game.save_enabled=false
	root.add_child(game)
	await process_frame
	assert(game.daily_screen==null)
	game.queue_free()
	await process_frame
	print("Daily rewards: 400 coins, 3 undo, duplicate protection, week templates and game startup passed")
	quit()
