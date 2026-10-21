extends SceneTree
const Game=preload("res://scripts/main.gd")
var failures=0
func check(ok:bool,label:String):
	print(label,": ",ok)
	if not ok: failures+=1
func _initialize(): run.call_deferred()
func run():
	var g=Game.new()
	root.add_child(g)
	g.save_enabled=false
	g.automation=true
	g.sound_enabled=false
	g.speed_factor=0.06
	g._load_level(3)
	var order=[0,4,8,2,1,5,6,7,3]
	var next=0
	var during_loading=false
	var deadline=Time.get_ticks_msec()+40000
	while next<6 and Time.get_ticks_msec()<deadline:
		if g.overlay=="" and g.model.can_dispatch(order[next]):
			during_loading = during_loading or g.loading
			g._dispatch(order[next])
			next+=1
		await process_frame
	while g.busy and Time.get_ticks_msec()<deadline: await process_frame
	check(not g.busy and next==6 and during_loading,"Six moves accepted including during loading")
	check(g.history.size()==6,"Loading does not merge moves")
	for remaining in range(5,-1,-1):
		var returned:int=order[remaining]
		g._undo()
		while g.busy and Time.get_ticks_msec()<deadline: await process_frame
		check(not g.busy and g.moves==remaining and g.history.size()==remaining,"Undo leaves exactly %d moves" % remaining)
		check(g.model.buses[returned].status=="yard" and g.model.buses[returned].load==0,"Last truck returns empty")
		var sum_load=0
		for bus in g.model.buses: sum_load+=bus.load
		check(g.model._valid_snapshot(g.model.snapshot()) and sum_load==g.boarded and sum_load+g.model.queue.size()==g.total_passengers,"Cargo conserved after undo")
		for i in remaining: check(g.model.buses[order[i]].status!="yard","Earlier dispatch retained")
	g._cancel_animation()
	g.queue_free()
	await process_frame
	print("Undo loading failures: ",failures)
	quit(1 if failures else 0)
