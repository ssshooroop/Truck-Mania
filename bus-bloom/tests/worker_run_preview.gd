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
	game.worker_carry=-1
	game.worker_batch_count=0
	game.worker_walking=true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/worker-run2-preview.png")
	game.queue_free()
	await process_frame
	quit()
