extends SceneTree
const Game=preload("res://scripts/main.gd")
func _initialize():run.call_deferred()
func run():
 var g=Game.new()
 root.add_child(g)
 g.save_enabled=false
 g.automation=true
 g.sound_enabled=false
 g.speed_factor=0.08
 g._load_level(3)
 var order=[0,4,8,2,1,5,6,7,3]
 var next=0
 var collisions=0
 var peak=0
 var during_loading=false
 var deadline=Time.get_ticks_msec()+45000
 while not g.model.is_won() and Time.get_ticks_msec()<deadline:
  if next<order.size() and g.overlay=="" and g.model.can_dispatch(order[next]):
   if g.loading:during_loading=true
   g._dispatch(order[next])
   next+=1
  peak=maxi(peak,g.arrival_ids.size())
  for a in g.model.buses:
   for b in g.model.buses:
    if b.id<=a.id or a.status=="gone" or b.status=="gone":continue
    var va=g.bus_visuals[a.id]
    var vb=g.bus_visuals[b.id]
    var pa=va.position if va.get("route",false) else g.EdgeRoute.position_for(va.position,va.angle,g.model.vehicle_size(a))
    var pb=vb.position if vb.get("route",false) else g.EdgeRoute.position_for(vb.position,vb.angle,g.model.vehicle_size(b))
    if g.model._rectangles_overlap(pa,g.model.forward({"angle":va.angle}),g.model.vehicle_size(a),pb,g.model.forward({"angle":vb.angle}),g.model.vehicle_size(b)):
     collisions+=1
     if collisions<4: print("COLLISION ",a.id," ",b.id," status ",a.status," ",b.status)
  await process_frame
 var failed=not g.model.is_won() or collisions>0 or peak<2 or not during_loading
 print("Parallel full level won=",g.model.is_won()," dispatched=",next," peak arrivals=",peak," during loading=",during_loading," collisions=",collisions)
 g._cancel_animation()
 g.queue_free()
 await process_frame
 quit(1 if failed else 0)
