extends SceneTree
const Main=preload("res://scripts/main.gd")
func _initialize(): run.call_deferred()
func run():
	var game=Main.new()
	game.automation=true
	root.add_child(game)
	for height in [720,1171]:
		root.size=Vector2i(540,height)
		await process_frame
		game._load_level(12)
		await create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/level13-%d.png"%height)
	game.queue_free()
	await process_frame
	quit()
