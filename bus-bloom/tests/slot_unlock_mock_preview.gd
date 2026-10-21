extends SceneTree
func _initialize(): run.call_deferred()
func run():
	root.content_scale_size=Vector2i(540,960)
	root.size=Vector2i(540,960)
	var game=preload("res://scripts/slot_unlock_mock.gd").new()
	root.add_child(game)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/slot-unlock-mock.png")
	game.queue_free()
	await process_frame
	quit()
