extends SceneTree
const Model=preload("res://scripts/game_model.gd")
const Contact=preload("res://scripts/collision_feedback.gd")
var failures:=0
func _initialize(): run.call_deferred()
func run():
	var checked:=0
	for level in 10:
		var original=Model.new()
		original.load_level(level)
		var tablet=Model.new()
		tablet.tablet_layout=true
		tablet.load_level(level)
		for bus in original.buses:
			if original.blocking_ids(bus.id).is_empty(): continue
			var a=Contact.contact(original,bus.id)
			var b=Contact.contact(tablet,bus.id)
			if a.is_empty() or b.is_empty():
				failures+=1
				continue
			checked+=1
			if absf(b.distance-a.distance*tablet.layout_scale)>0.01 or b.obstacle!=a.obstacle:
				push_error("Contact mismatch level %d bus %d" % [level+1,bus.id])
				failures+=1
	print("Scaled contacts verified: ",checked," failures: ",failures)
	var game=preload("res://scripts/main.gd").new()
	root.content_scale_size=Vector2i(540,720)
	root.add_child(game)
	game.save_enabled=false
	game.automation=true
	game._load_level(3)
	game.intro_delays.clear()
	var id: int = -1
	for bus in game.model.buses:
		if game.model.blocking_ids(bus.id).is_empty(): continue
		if Contact.contact(game.model,bus.id).get("distance",0)>2:
			id=bus.id
			break
	if id<0:
		failures+=1
	else:
		var start: Vector2 = game.bus_visuals[id].position
		var hit=Contact.contact(game.model,id)
		game.blockers=game.model.blocking_ids(id)
		game._blocked_bump(id)
		var peak:=0.0
		while game.road_busy:
			await process_frame
			peak=maxf(peak,start.distance_to(game.bus_visuals[id].position))
		print("Animated forward distance: ",peak," expected: ",hit.distance," returned: ",game.bus_visuals[id].position.distance_to(start))
		if peak<hit.distance*0.9 or game.bus_visuals[id].position.distance_to(start)>0.01: failures+=1
	game.queue_free()
	await process_frame
	quit(failures)

