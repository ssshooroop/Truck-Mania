extends SceneTree
const Game=preload("res://scripts/main.gd")
const Art=preload("res://scripts/thief_art.gd")
func _initialize(): run.call_deferred()
func run():
	for target in [Vector2(468,110),Vector2(80,250)]:
		var state:Dictionary={"time":3.7,"position":target,"kind":"truck","taken":true}
		var previous:Vector2=Art.pose(state).feet
		var cleared_crates:=false
		for step in range(1,191):
			state.time=3.7+step*0.01
			var p:Dictionary=Art.pose(state)
			assert(p.feet.distance_to(previous)<6.0)
			if p.feet.x>=0 and p.feet.x<=35:
				assert(p.kind=="jump" and p.feet.y<125.0)
				cleared_crates=true
			previous=p.feet
		assert(cleared_crates and previous.x<-44.0)
	assert(Art.should_jump(Vector2(70,185),Vector2(68,185),Vector2(30,185),Vector2(120,0),0.016))
	assert(not Art.should_jump(Vector2(70,92),Vector2(68,92),Vector2(30,185),Vector2(120,0),0.016))
	assert(not Art.should_jump(Vector2(70,185),Vector2(68,185),Vector2(30,185),Vector2(-200,0),0.016))
	Art.prepare()
	assert(Art.frames.jump_empty.size()==4)
	assert(Art.frames.jump_empty[0].get_height()==300)
	var g=Game.new()
	g.automation=true
	g.save_enabled=false
	root.add_child(g)
	root.size=Vector2i(540,720)
	await process_frame
	g._load_level(16)
	g._cancel_animation()
	g.overlay=""
	g.intro_age=10
	if "--visual-exit" in OS.get_cmdline_user_args():
		g.thief_state={"time":3.7+(456.0-15.0)/511.0*1.9,"position":Vector2(468,110),"kind":"belt","taken":true,"color":0}
		g.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/thief-exit.png")
		g.thief_state.clear()
	await g._run_thief(g.generation)
	assert(g.thief_state.taken and g.thief_state.time<4.3)
	# Billy is allowed to walk while the thief escapes; force a head-on encounter.
	while float(g.thief_state.time)<3.7: await process_frame
	var feet:Vector2=Art.pose(g.thief_state).feet
	g.worker_position=feet-Vector2(45,0)
	g.thief_state.worker_previous=g.worker_position
	var walk=g.create_tween()
	walk.tween_property(g,"worker_position",feet+Vector2(60,0),0.8)
	await create_timer(0.3).timeout
	assert(g.thief_state.has("hop_start"))
	assert(Art.pose(g.thief_state).kind=="jump")
	assert(Art.pose(g.thief_state).feet.y<155)
	if "--visual" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/thief-jump.png")
	g._open_settings()
	var stopped:float=g.thief_state.time
	await create_timer(0.2).timeout
	assert(is_equal_approx(stopped,g.thief_state.time))
	g._resume()
	await create_timer(0.1).timeout
	assert(g.thief_state.time>stopped)
	g._load_level(0)
	assert(g.thief_tween==null and g.thief_state.is_empty())
	g.queue_free()
	await process_frame
	print("Thief jump: proximity, sprites, concurrent walk, pause/resume and cancellation passed")
	quit()
