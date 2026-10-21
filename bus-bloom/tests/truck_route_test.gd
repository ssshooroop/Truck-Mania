extends SceneTree
const Probe=preload("res://tests/motion_probe.gd")
const Route=preload("res://scripts/truck_route.gd")
var game
func _initialize():
 game=Probe.new()
 root.add_child.call_deferred(game)
 _run.call_deferred()
func _run():
 var failures:=0
 var worst:=0
 var total:=0
 var until:=100
 var first:=0
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--count="): until=int(arg.trim_prefix("--count="))
  if arg.begins_with("--first="): first=int(arg.trim_prefix("--first="))-1
 for level in range(first,until):
  game._load_level(level)
  for id_value in game.Model.campaign_levels()[level].solution:
   var id:=int(id_value)
   var b:Dictionary=game.model.buses[id]
   var planner=Route.new()
   planner.setup(game,id)
   var start:=Time.get_ticks_msec()
   var path:Array=planner.plan(b.position,b.angle,game._bay_position(game.model.free_bay(),b.kind),game.BAY_ANGLE)
   var ms:=Time.get_ticks_msec()-start
   worst=maxi(worst,ms)
   total+=ms
   if path.is_empty():
    failures+=1
    print("START_CLEAR=",planner.clear_pose(b.position,b.angle-PI/2)," BAY=",game.model.free_bay()," can=",game.model.can_dispatch(id)," edges=",planner.connections)
    for dist in [48.0,120.0,240.0,320.0,420.0]:
     var endpoint:Vector2=b.position+game.model.forward(b)*dist
     print("ANCHOR ",endpoint," clear=",planner.clear_pose(endpoint,b.angle-PI/2)," edge=",planner.direct_plan(b.position,b.angle,endpoint,b.angle).size())
    print("NO_ROUTE level=",level+1," id=",id," at=",b.position," kind=",b.kind," angle=",b.angle," ms=",ms)
   game.model.dispatch(id)
   game.model.arrive(id)
   game._sync_visuals()
   while game.model.next_boarding()>=0:
    var next:int=game.model.next_boarding()
    game.model.board_batch(next,game.model.batch_size(next))
    if game.model.buses[next].status=="leaving": game.model.depart(next)
  print("ROUTE_LEVEL_",level+1," failures=",failures," total_ms=",total," worst_ms=",worst)
 print("TOTAL_NO_ROUTE=",failures)
 quit(1 if failures else 0)
