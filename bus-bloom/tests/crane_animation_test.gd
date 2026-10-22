extends SceneTree
const Game = preload("res://scripts/main.gd")
const Crane = preload("res://scripts/crane_animation.gd")
var failures := 0
func check(ok:bool,message:String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): run.call_deferred()
func run():
	var g = Game.new()
	g.automation = true
	g.save_enabled = false
	root.add_child(g)
	g._load_level(14)
	g._cancel_animation()
	g.overlay = ""
	g.intro_age = 10
	g.economy.state.crane_intro_used = false
	check(g._rescue_price("crane")==0,"First crane is free")
	g.economy.state.crane_intro_used = true
	check(g._rescue_price("crane")==150,"Subsequent crane costs 150")
	var id:int = 0
	var start:Vector2 = g.bus_visuals[id].position
	var end:Vector2 = g._bay_position(0,g.model.buses[id].kind)
	for height in [720,1171]:
		root.size=Vector2i(540,height)
		await process_frame
		g._load_level(14)
		g._cancel_animation()
		g.intro_age=10
		g.overlay=""
		start=g.bus_visuals[id].position
		end=g._bay_position(0,g.model.buses[id].kind)
		for time in [0.8,2.15,2.65,3.5,4.7,5.5]:
			g.crane_truck=id
			g.crane_state=Crane.pose(time,start,end)
			g.bus_visuals[id].position=g.crane_state.truck
			g.bus_visuals[id].route=true
			g.bus_visuals[id].crane_scale=1+0.12*g.crane_state.lift
			g.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/crane-%d-%d.png"%[height,roundi(time*100)])
	check(Crane.pose(2.15,start,end).magnet_scale<Crane.pose(2.65,start,end).magnet_scale,"Magnet descends then rises")
	check(Crane.pose(4.7,start,end).truck.is_equal_approx(end),"Crane reaches exact slot position")
	g.bus_visuals[id].position=start
	await g._crane_airlift(id,end,g.BAY_ANGLE)
	check(g.crane_state.is_empty() and g.crane_truck==-1,"Crane leaves after transfer")
	check(g.bus_visuals[id].position.is_equal_approx(end),"Truck is placed exactly in slot")
	g._crane_airlift(id,start,0)
	await create_timer(0.15).timeout
	g._load_level(0)
	check(g.crane_state.is_empty() and g.crane_truck==-1,"Changing level cancels crane")
	g.economy.state.crane_intro_used=true
	var restored=preload("res://scripts/runtime_economy.gd").new()
	restored.restore(g.economy.state)
	check(restored.state.crane_intro_used,"First-use flag persists")
	g._load_level(14)
	g._cancel_animation()
	g.overlay="stuck"
	g.economy.state.crane_intro_used=false
	var color:int=g.model.buses[0].color
	g.model.queue=[color,color,color,color]
	for bay in 3:
		var b:Dictionary=g.model.buses[bay+1]
		b.color=(color+1)%6
		b.status="docked"
		b.bay=bay
		b.load=0
		g.model.bays[bay]=b.id
	g._sync_visuals()
	check(g._can_rescue("crane"),"Crane can rescue full parking at level 15")
	g.model.level_index=13
	check(not g._can_rescue("crane"),"Crane is locked before level 15")
	g.model.level_index=14
	var wallet:int=g.coins
	g._purchase_rescue("crane")
	await create_timer(0.1).timeout
	check(g.model.bays[3]>=0 and g.model.buses[g.model.bays[3]].status=="arriving","Slot reserved before crane transfer")
	check(g.coins==wallet and g.economy.state.crane_intro_used,"Free tutorial consumed once without charging")
	g._load_level(0)
	g._cancel_animation()
	g.free()
	print("Crane animation failures: %d"%failures)
	quit(1 if failures else 0)
