extends SceneTree
const Game=preload("res://scripts/main.gd")
const Route=preload("res://scripts/truck_route.gd")
func _initialize(): run.call_deferred()
func run():
 var game=Game.new()
 root.add_child(game)
 game.save_enabled=false
 game._load_level(3)
 for bus in game.model.buses:
  if bus.id not in [3,5,6,7]: bus.status="gone"
 for id in [3,6]:
  var bus=game.model.buses[id]
  var planner=Route.new()
  planner.setup(game,id)
  var clear=true
  var a=bus.angle-PI/2
  for i in 360:
   var p=Vector3(bus.position.x,bus.position.y,a+i*TAU/360)
   var q=Vector3(p.x,p.y,a+(i+1)*TAU/360)
   if not planner.clear_sweep(p,q): clear=false
  print("TRUCK ",id," blockers=",game.model.blocking_ids(id)," full rotation clear=",clear)
 quit()
