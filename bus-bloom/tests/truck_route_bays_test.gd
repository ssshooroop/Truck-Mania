extends SceneTree
const Probe=preload("res://tests/motion_probe.gd")
const Route=preload("res://scripts/truck_route.gd")
var failures:=0
func _initialize(): _run.call_deferred()
func _run():
 var g=Probe.new()
 root.add_child(g)
 for kind in 3:
  for bay in 5:
   g._load_level(1)
   for b:Dictionary in g.model.buses: b.status="gone"
   for slot in 5:
    if slot==bay: continue
    g.model.buses[slot].status="docked"
    g.model.buses[slot].bay=slot
    g.model.buses[slot].kind=2
    g.bus_visuals[slot].position=g._bay_position(slot,2)
    g.bus_visuals[slot].angle=g.BAY_ANGLE
   var moving:Dictionary=g.model.buses[5]
   moving.kind=kind
   moving.position=Vector2(270,800)
   moving.angle=0.0
   moving.status="yard"
   var planner=Route.new()
   planner.setup(g,5)
   var path:Array=planner.plan(moving.position,moving.angle,g._bay_position(bay,kind),g.BAY_ANGLE)
   if path.is_empty():
    failures+=1
    print("BAY_ARRIVAL_FAIL kind=",kind," bay=",bay)
   moving.status="leaving"
   g.bus_visuals[5].position=g._bay_position(bay,kind)
   g.bus_visuals[5].angle=g.BAY_ANGLE
   var departure:Array=g._departure_route(5)
   if departure.is_empty():
    failures+=1
    print("BAY_DEPART_FAIL kind=",kind," bay=",bay)
   else:
    var forward_phase:bool=not departure.any(func(p):return p.get("gear_change",false))
    for i in range(1,departure.size()):
     if departure[i-1].get("gear_change",false): forward_phase=true
     var delta:Vector2=departure[i].position-departure[i-1].position
     if delta.length()<0.1: continue
     var angle:float=lerp_angle(departure[i-1].angle,departure[i].angle,0.5)
     var alignment:float=delta.normalized().dot(Vector2(sin(angle),-cos(angle)))
     if (forward_phase and alignment<0.99) or (not forward_phase and alignment> -0.99):
      failures+=1
      print("GEAR_DIRECTION_FAIL kind=",kind," bay=",bay)
      break
    if not forward_phase:
     failures+=1
     print("EXIT_MUST_BE_FORWARD")
 print("All five bays / three truck sizes: ",failures," failures")
 quit(1 if failures else 0)
