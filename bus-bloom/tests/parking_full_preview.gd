extends SceneTree
func _initialize(): run.call_deferred()
func run():
	root.content_scale_size=Vector2i(540,720)
	root.size=Vector2i(1080,1440)
	var game=preload("res://scripts/main.gd").new()
	root.add_child(game)
	game.save_enabled=false
	game.automation=true
	game._load_level(3)
	game.intro_delays.clear()
	game.worker_position=Vector2(280,365)
	game.worker_carry=0
	game.worker_batch_count=3
	game.worker_walking=false
	game.overlay="stuck"
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/parking-full-preview.png")
	game.coins=120
	game.history.append({"state":game.model.undo_snapshot(),"moves":0,"boarded":0})
	game._overlay_input(game.ParkingFull.UNDO.get_center())
	assert(game.coins==100 and game.overlay=="", "Paid undo")
	game.overlay="stuck"
	game.economy.state.tutorial_done=true
	game._overlay_input(game.ParkingFull.BUY.get_center())
	assert(game.coins==0 and game.model.open_bay_count==4 and game.overlay=="", "Paid slot")
	game.overlay="stuck"
	game._overlay_input(game.ParkingFull.VIDEO.get_center())
	assert(game.coins==0 and game.model.open_bay_count==4, "No reward without ad")
	game._overlay_input(game.ParkingFull.RETRY.get_center())
	assert(game.model.open_bay_count==3 and game.overlay=="", "Retry")
	print("Parking actions passed")
	game.queue_free()
	await process_frame
	quit()
