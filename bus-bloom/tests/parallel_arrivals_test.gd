extends SceneTree
class TrafficGame:
 extends "res://scripts/main.gd"
 func _settle(_ticket:int) -> void: pass
 func _draw() -> void: pass
var failures=0
func check(ok:bool,label:String):
 print(label,": ",ok)
 if not ok:failures+=1
func _initialize(): run.call_deferred()
func run():
 var g=TrafficGame.new()
 root.add_child(g)
 g.save_enabled=false
 g.sound_enabled=false
 g.automation=true
 g.speed_factor=0.25
 g._load_level(3)
 g._dispatch(0)
 g._dispatch(2)
 g._dispatch(4)
 check(g.model.bays.slice(0,3)==[0,2,4],"Click order reserves first free bays")
 check(g.arrival_ids.size()==3,"Three accepted arrivals without waiting for docking")
 var moves=g.moves
 g._dispatch(0)
 g._dispatch(8)
 check(g.moves==moves and g.model.buses[8].status=="yard","Duplicate and fourth click cannot overbook")
 g._open_settings()
 var before=g.bus_visuals.duplicate(true)
 for i in 5: await process_frame
 check(g.bus_visuals==before,"All arrivals pause together")
 g._resume()
 var overlap=0
 var concurrent=false
 var last=g.bus_visuals.duplicate(true)
 var deadline=Time.get_ticks_msec()+15000
 while not g.arrival_ids.is_empty() and Time.get_ticks_msec()<deadline:
  await process_frame
  var moving=0
  for id in [0,2,4]:
   if g.bus_visuals[id].position.distance_to(last[id].position)>0.01:moving+=1
  if moving>=2: concurrent=true
  last=g.bus_visuals.duplicate(true)
  for a in g.model.buses:
   for b in g.model.buses:
    if b.id<=a.id or a.status=="gone" or b.status=="gone":continue
    var va=g.bus_visuals[a.id]
    var vb=g.bus_visuals[b.id]
    if g.model._rectangles_overlap(va.position,g.model.forward({"angle":va.angle}),g.model.vehicle_size(a),vb.position,g.model.forward({"angle":vb.angle}),g.model.vehicle_size(b)):
     overlap+=1
     if overlap<4:print("COLLISION ",a.id," ",b.id)
 check(concurrent,"At least two trucks visibly move together")
 check(overlap==0,"Concurrent routes do not intersect truck bodies")
 check(g.arrival_ids.is_empty(),"All arrivals finish without deadlock")
 check(g.history.size()==3,"Each overlapping dispatch has its own undo checkpoint")
 g._undo()
 check(g.model.bays==[0,2,-1,-1,-1] and g.moves==2 and g.model.buses[4].status=="yard","Undo returns only the last truck and keeps earlier arrivals")
 g._undo()
 check(g.model.bays==[0,-1,-1,-1,-1] and g.moves==1,"Second undo retains the first move")
 g._undo()
 check(g.model.bays==[-1,-1,-1,-1,-1] and g.moves==0,"Third undo returns to the beginning")
 g._dispatch(0)
 g._dispatch(2)
 g._load_level(3)
 for i in 5: await process_frame
 check(g.arrival_ids.is_empty() and g.traffic.routes.is_empty() and g.model.bays==[-1,-1,-1,-1,-1],"Restart cancels all routes and reservations")
 print("Parallel arrivals failures: ",failures)
 g.queue_free()
 await process_frame
 quit(1 if failures else 0)
