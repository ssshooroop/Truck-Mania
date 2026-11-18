extends SceneTree
func _initialize():run.call_deferred()
func run():
	var g=preload("res://scripts/main.gd").new();g.automation=true;g.save_enabled=false;root.add_child(g)
	root.size=Vector2i(540,720)
	await process_frame
	g._load_level(14);g._cancel_animation();g.overlay="";g.intro_age=10;g.economy.state.inventory.undo=3
	var b=g.model.buses[0];b.bay=5;b.status="docked";g.model.bays[5]=0
	g._sync_visuals();await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/undo-crane-tablet.png")
	g.queue_free();await process_frame;quit()
