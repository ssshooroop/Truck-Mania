extends SceneTree
class TrafficGame:
 extends "res://scripts/main.gd"
 func _settle(_ticket:int) -> void: pass
 func _draw() -> void: pass
func _initialize():run.call_deferred()
func run():
 root.content_scale_size=Vector2i(540,720)
 root.size=Vector2i(1080,1440)
 var g=TrafficGame.new()
 root.add_child(g)
 g.save_enabled=false
 g.sound_enabled=false
 g.automation=true
 g.speed_factor=0.15
 var failures=0
 for variant in ([10] if "--five" in OS.get_cmdline_user_args() else range(10)):
  var level=variant if variant<10 else 7
  g._load_level(level)
  if variant==10:
   g.model.unlock_next_bay()
   g.model.unlock_next_bay()
  var sent=[]
  for b in g.model.buses:
   if g.model.can_dispatch(b.id):
    g._dispatch(b.id)
    sent.append(b.id)
   if sent.size()==g.model.open_bay_count:break
  var deadline=Time.get_ticks_msec()+20000
  var collisions=0
  while not g.arrival_ids.is_empty() and Time.get_ticks_msec()<deadline:
   await process_frame
   for a in g.model.buses:
    for b in g.model.buses:
     if a.id>=b.id or a.status=="gone" or b.status=="gone":continue
     var va=g.bus_visuals[a.id]
     var vb=g.bus_visuals[b.id]
     if g.model._rectangles_overlap(va.position,g.model.forward({"angle":va.angle}),g.model.vehicle_size(a),vb.position,g.model.forward({"angle":vb.angle}),g.model.vehicle_size(b)):
      collisions+=1
      if collisions<3:print("COLLISION level=",level+1," ids=",a.id,",",b.id)
  if collisions>0 or not g.arrival_ids.is_empty():failures+=1
  print("Parallel level ",level+1," sent=",sent," collisions=",collisions," unfinished=",g.arrival_ids.size())
 print("Parallel campaign failures: ",failures)
 g._cancel_animation()
 g.queue_free()
 await process_frame
 quit(1 if failures else 0)
