extends SceneTree
const Game=preload("res://scripts/main.gd")
const Catalog=preload("res://scripts/ui/modal_catalog.gd")
var failures:=0
func check(ok:bool,label:String):
	if not ok:
		failures+=1
		push_error(label)
func _initialize():run.call_deferred()
func touch(p:Vector2,down:bool):
	var e=InputEventScreenTouch.new()
	e.index=0
	e.position=p
	e.pressed=down
	Input.parse_input_event(e)
func run():
	root.size=Vector2i(540,1171)
	var g=Game.new()
	g.automation=true
	g.save_enabled=false
	root.add_child(g)
	g._show_road_menu(false)
	g._open_shop(["road_menu"])
	await create_timer(0.4).timeout
	var before=g.generation
	var p:Vector2=g.road_menu.markers[0].global_position
	for down in [true,false]:
		touch(p,down)
		await process_frame
	check(g.generation==before and g.modal!=null,"Touch must not start a level behind shop")
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.position=p
		e.pressed=down
		Input.parse_input_event(e)
		await process_frame
	check(g.generation==before and g.modal!=null,"Mouse must not start a level behind shop")
	g._open_shortfall(100,["road_menu"])
	await process_frame
	check(g.road_menu.input_blocked,"Replacing modal must keep map blocked")
	g._close_modal()
	check(g.road_menu.input_blocked,"Closing animation must keep map blocked")
	await create_timer(0.3).timeout
	check(not g.road_menu.input_blocked,"Closing modal restores map input")
	p=g.road_menu.markers[0].global_position
	touch(p,true)
	touch(p,false)
	await process_frame
	check(g.generation!=before,"Map works again after modal closes")
	g._show_road_menu(false)
	g._open_shop(["road_menu"])
	g._close_modal(true)
	check(not g.road_menu.input_blocked,"Instant close restores map input")
	for bays in [3,4,5]:
		for help in [true,false]:
			var spec=Catalog.stuck({"slot_available":bays<5,"can_crane":bays<5,"rescue_left":help,"crane_price":150})
			var ids=[]
			for b in spec.blocks:
				if b.has("id"):ids.append(b.id)
			check(("crane" in ids)==(bays<5 and help),"Crane availability follows usable bays and rescue limit")
			if bays<5 and help:check("slot_coins" in ids,"Slot and crane must both be offered")
	var free=Catalog.stuck({"slot_available":true,"can_crane":true,"crane_price":0})
	for b in free.blocks:
		if b.get("id","")=="crane":check(b.price.is_empty(),"Gift crane has no coin price")
	g.queue_free()
	await process_frame
	print("Modal regressions: ",failures," failures")
	quit(1 if failures else 0)
