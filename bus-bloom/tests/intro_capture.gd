extends SceneTree
const Game=preload("res://scripts/main.gd")
func _initialize(): run.call_deferred()
func run():
	root.size=Vector2i(540,1171)
	var g=Game.new()
	root.add_child(g)
	g.save_enabled=false
	g.automation=true
	g._load_level(3)
	g.set_process(false)
	for age in [0.2,0.45,1.05]:
		g.intro_age=age
		g.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/intro-%s.png" % age)
	g.queue_free()
	await process_frame
	quit()
