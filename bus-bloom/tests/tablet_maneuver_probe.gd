extends SceneTree
const Game=preload("res://scripts/main.gd")
func _initialize():run.call_deferred()
func run():
 root.content_scale_size=Vector2i(540,720)
 root.size=Vector2i(1080,1440)
 var g=Game.new()
 root.add_child(g)
 g.save_enabled=false
 g.automation=true
 g._load_level(3)
 for id in [0,4,5,8]:
  g.model.buses[id].status="gone"
  g.model.buses[id].load=g.model.buses[id].capacity
 g.model.bays=[2,1,-1,-1,-1]
 for id in [2,1]:
  g.model.buses[id].status="docked"
  g.model.buses[id].bay=0 if id==2 else 1
 g.model.buses[1].load=3
 g.model.queue=g.model.queue.slice(11)
 g._sync_visuals()
 var paths=g.model.maneuver_paths(6)
 print("paths=",paths.size()," actual=",g._maneuver_arrival(6).size())
 var planner=g.TruckRoute.new()
 planner.setup(g,6)
 for path in paths:
  var valid=true
  for i in range(1,path.size()):
   var a=path[i-1]
   var b=path[i]
   if not planner.clear_sweep(Vector3(a.position.x,a.position.y,a.angle-PI/2),Vector3(b.position.x,b.position.y,b.angle-PI/2)):
    print("prefix fail ",i," at ",b.position)
    valid=false
    break
  if valid:print("prefix valid end=",path.back())
 g._cancel_animation()
 g.queue_free()
 await process_frame
 quit()
