extends SceneTree
const Game=preload("res://scripts/main.gd")
func _initialize(): run.call_deferred()
func run():
	root.content_scale_size=Vector2i(540,720)
	root.size=Vector2i(1080,1440)
	var g=Game.new()
	root.add_child(g)
	g.save_enabled=false
	g.automation=true
	g._load_level(7)
	g.intro_delays.clear()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/tablet-1080x1440.png")
	g._open_slot_offer(3)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/tablet-slot.png")
	g._close_slot_offer()
	g.overlay="win"
	g.level_reward=20
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/tablet-win.png")
	g.overlay=""
	root.size=Vector2i(1080,1920)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/phone-1080x1920.png")
	g.queue_free()
	await process_frame
	quit()
