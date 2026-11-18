extends SceneTree
func _initialize(): run.call_deferred()
func run():
	DirAccess.make_dir_recursive_absolute("res://artifacts/hint-visibility")
	for height in [720,1171]:
		root.content_scale_size=Vector2i(540,height);root.size=Vector2i(540,height)
		var game=preload("res://scripts/main.gd").new()
		game.save_enabled=false;game.automation=true
		root.add_child(game)
		game._load_level(0);game.intro_delays.clear()
		game._hint()
		var id:int=game.hint_bus
		assert(id>=0)
		game.elapsed+=7.0;game._validate_hint()
		assert(game.hint_bus==id,"Hint must persist beyond toast duration")
		for reduced in [false,true]:
			game.reduced_motion=reduced
			for phase in [0.0,0.7]:
				game.elapsed=game.hint_started+phase
				await process_frame;await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/hint-visibility/%d-%s-%s.png"%[height,str(reduced),str(phase)])
		game.model.queue.pop_front();game._validate_hint()
		assert(game.hint_bus==-1,"Cargo change must invalidate hint")
		game._load_level(0);game.intro_delays.clear();game._hint()
		game.model.buses[game.hint_bus].status="arriving";game._validate_hint()
		assert(game.hint_bus==-1,"Dispatched truck must stop highlighting")
		game._load_level(0)
		assert(game.hint_bus==-1,"Reload must clear hint")
		game.queue_free();await process_frame
	print("PASS: persistent hints, cargo/dispatch/reload invalidation; phone/tablet and reduced motion captures")
	quit()
