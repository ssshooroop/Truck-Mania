extends SceneTree
const Game = preload("res://scripts/main.gd")
var failures := 0
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
	print(label," ",ok)
	if not ok: failures += 1
func capture(name:String):
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+name+".png")
func run():
	root.content_scale_size=Vector2i(540,720)
	root.size=Vector2i(810,1080)
	var g=Game.new()
	root.add_child(g)
	g.save_enabled=false
	g.automation=true
	g.economy.state.tutorial_done=false
	g._load_level(2)
	g.intro_delays.clear()
	g.coins=250
	g._open_slot_offer(3)
	check(g.overlay=="slot_offer","First use has spotlight")
	await capture("cone-first-use")
	g._purchase_slot()
	check(g.economy.state.tutorial_done and g.model.open_bay_count==4 and g.coins==250,"First use free and remembered")
	g._open_slot_offer(4)
	check(g.overlay=="" and g.coins==150 and g.model.open_bay_count==5,"Fifth slot direct purchase 100")
	g._load_level(3)
	g.intro_delays.clear()
	g._open_slot_offer(3)
	check(g.overlay=="" and g.coins==50 and g.model.open_bay_count==4,"Next level no spotlight and costs 100")
	g.slot_pops[0].age=0.35
	await capture("cone-purchase")
	g.slot_pops[0].age=0.82
	await capture("cone-burst")
	g._open_slot_offer(4)
	check(g.model.open_bay_count==4 and g.coins==50 and g.overlay=="","Insufficient balance keeps slot closed")
	g.coins=250
	g.overlay="stuck"
	g._open_slot_offer(4)
	check(g.model.open_bay_count==5 and g.coins==150 and g.overlay=="","Second paid slot also costs 100")
	g._open_slot_offer(4)
	check(g.coins==150,"Repeated tap cannot charge twice")
	g._load_level(3)
	check(g.model.open_bay_count==3 and g.slot_pops.is_empty(),"New attempt resets slots and effects")
	g.queue_free()
	await process_frame
	quit(failures)
