extends SceneTree
func _initialize(): run.call_deferred()
func run():
	root.content_scale_size=Vector2i(540,960)
	root.size=Vector2i(540,960)
	var screen=preload("res://scripts/daily_bonus.gd").new()
	root.add_child(screen)
	screen.sound_enabled=false
	screen.reveal(2)
	screen.animation_age=1.0
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/daily-bonus-preview.png")
	screen.queue_free()
	await process_frame
	quit()
