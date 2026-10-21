extends SceneTree
const Game=preload("res://scripts/main.gd")
const Layout=preload("res://scripts/responsive_layout.gd")
var failures:=0
func check(ok:bool,label:String):
	if not ok:
		failures+=1
		print("FAIL: ",label)
func _initialize(): run.call_deferred()
func run():
	var g=Game.new()
	root.add_child(g)
	g.save_enabled=false
	g.automation=true
	g.set_process(false)
	for size in [Vector2(540,720),Vector2(540,960),Vector2(540,1200)]:
		var t:Transform2D=Layout.world(size)
		for level in g.model.level_count():
			g._load_level(level)
			for bus in g.model.buses:
				var p:Vector2=t*bus.position
				var body:Vector2=g.model.vehicle_size(bus)*t.get_scale().x
				var half:Vector2=(Vector2(cos(bus.angle),sin(bus.angle)).abs()*body.x+Vector2(sin(bus.angle),-cos(bus.angle)).abs()*body.y)*0.5
				check(p.x-half.x>=0 and p.x+half.x<=size.x and p.y-half.y>=185 and p.y+half.y<size.y-72,"Vehicle fits above controls")
				check(g._truck_at(t.affine_inverse()*p)==bus.id,"Scaled truck center hits correct vehicle")
				for other in g.model.buses:
					if other.id<=bus.id:continue
					var original:bool=g.model.vehicles_overlap(bus,other) if g.model.has_method("vehicles_overlap") else g.model._rectangles_overlap(bus.position,g.model.forward(bus),g.model.vehicle_size(bus),other.position,g.model.forward(other),g.model.vehicle_size(other))
					var projected:bool=g.model._rectangles_overlap(p,g.model.forward(bus),body,t*other.position,g.model.forward(other),g.model.vehicle_size(other)*t.get_scale().x)
					check(original==projected,"Projection preserves collision geometry")
		print("Checked all levels at ",size*2)
	g._cancel_animation()
	g.queue_free()
	await process_frame
	print("Responsive failures: ",failures)
	quit(1 if failures else 0)
