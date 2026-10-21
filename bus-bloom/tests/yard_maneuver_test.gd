extends SceneTree
const Probe=preload("res://tests/motion_probe.gd")
var failures=0
func check(ok:bool,label:String):
 print(label,": ",ok)
 if not ok: failures+=1
func _initialize(): run.call_deferred()
func run():
 var game=Probe.new()
 root.add_child(game)
 game._load_level(3)
 var blocked=0
 for bus in game.model.buses:
  if not game.model.can_dispatch(bus.id): blocked+=1
 check(blocked>0,"Packed initial layout retains blocked trucks")
 print("Initial blocked trucks: ",blocked)
 for target in [3,6]:
  game._load_level(3)
  # Preserve the original open-space regression, independent of campaign edits.
  for v in JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/maneuver-open-yard.json")):
   var id=int(v.id)
   game.model.buses[id].position=Vector2(v.x,v.y)
   game.model.buses[id].angle=v.angle
   game.bus_visuals[id].position=Vector2(v.x,v.y)
   game.bus_visuals[id].angle=v.angle
  for bus in game.model.buses:
   if bus.id not in [3,5,6,7,1,8]: bus.status="gone"
  game.model.bays=[8,1,-1,-1,-1]
  for id in [8,1]:
   var bus=game.model.buses[id]
   bus.status="docked"
   bus.bay=0 if id==8 else 1
   game.bus_visuals[id].position=game._bay_position(bus.bay,bus.kind)
   game.bus_visuals[id].angle=game.BAY_ANGLE
  check(not game.model.blocking_ids(target).is_empty(),"Green %d originally blocked"%target)
  check(game.model.can_dispatch(target),"Green %d legal maneuver"%target)
  var start=Time.get_ticks_usec()
  var path=game._maneuver_arrival(target)
  print("Route planning ms: ",(Time.get_ticks_usec()-start)/1000.0)
  check(not path.is_empty(),"Green %d complete route to free bay"%target)
  if not path.is_empty(): await game._follow_route(target,path)
 check(game.collision_segments==0,"No collisions through sampled maneuvers")
 check(game.invisible_samples==0,"Vehicles stay visible")
 game._load_level(2)
 for bus in game.model.buses: check(game.model.maneuver_paths(bus.id).is_empty(),"Other levels unchanged")
 print("Maneuver tests failures: ",failures)
 game.queue_free()
 await process_frame
 quit(1 if failures else 0)
