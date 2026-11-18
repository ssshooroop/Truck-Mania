extends SceneTree
const Game=preload("res://scripts/main.gd")
const Rules=preload("res://scripts/thief_rules.gd")
func _initialize(): run.call_deferred()
func run():
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
	var before:Array=g.model.queue.duplicate()
	print("Scene candidate: ",Rules.choose(g.model,0)," busy=",g.busy," overlay=",g.overlay)
	g._run_thief(g.generation)
	await create_timer(2.6).timeout
	assert(g.thief_state.taken and g.thief_events==1)
	assert(g.model.queue.size()==before.size() and g.model.queue.back()==before[0])
	assert(is_equal_approx(g._belt_position(0).x,468-g.BELT_STEP))
	assert(g.ThiefArt.pose(g.thief_state).kind=="sit")
	var status:String=g.model.buses[0].status
	g._dispatch(0)
	assert(g.model.buses[0].status==status)
	if "--visual" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/thief-belt.png")
	await create_timer(1.3).timeout
	assert(g._belt_position(0).x>468-g.BELT_STEP and g._belt_position(0).x<468)
	await create_timer(0.4).timeout
	assert(is_equal_approx(g._belt_position(0).x,468))
	await create_timer(1.5).timeout
	assert(g.thief_state.is_empty())
	g._load_level(19)
	g._cancel_animation()
	g.overlay=""
	g.intro_age=10
	var bus:Dictionary={}
	var event:Dictionary={}
	for id in g.model.buses.size():
		g.model.load_level(19)
		bus=g.model.buses[id]
		bus.status="docked"
		bus.load=1
		bus.bay=0
		g.model.bays[0]=bus.id
		g.model.queue.remove_at(g.model.queue.find(bus.color))
		event=Rules.choose(g.model,0)
		if not event.is_empty(): break
	var color:int=bus.color
	g.boarded=1
	g._sync_visuals()
	assert(not event.is_empty() and event.kind=="truck")
	g._run_thief(g.generation)
	await create_timer(2.6).timeout
	assert(g.thief_state.taken and bus.load==0 and g.boarded==0)
	assert(g.model.queue.back()==color)
	if "--visual" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/thief-truck.png")
	g._load_level(0)
	assert(g.thief_state.is_empty() and g.thief_events==0)
	await create_timer(2.0).timeout
	assert(g.model.level_index==0 and g.thief_state.is_empty())
	g.queue_free()
	await process_frame
	print("Thief scene: both thefts, atomic contact, dispatch guard, count updates and restart cancellation passed")
	quit()
