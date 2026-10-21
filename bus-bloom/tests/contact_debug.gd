extends SceneTree
const Model=preload("res://scripts/game_model.gd")
const Contact=preload("res://scripts/collision_feedback.gd")
class Game extends "res://scripts/main.gd":
 func _ready(): pass
 func _process(_delta): pass
var failures:=0
func check(ok:bool,label:String):
 if not ok:
  failures+=1
  push_error(label)
func _initialize(): run.call_deferred()
func run():
 var m=Model.new()
 var pairs:=0
 for level in m.level_count():
  m.load_level(level)
  for b in m.buses:
   var blockers=m.blocking_ids(b.id)
   for blocker in blockers:
    for other in m.buses: other.status="yard" if other.id in [b.id,blocker] else "gone"
    var hit=Contact.contact(m,b.id)
    check(not hit.is_empty(),"Contact level %d truck %d blocker %d"%[level+1,b.id,blocker])
    pairs+=1
    for other in m.buses: other.status="yard"
 var g=Game.new()
 g.save_enabled=false
 root.add_child(g)
 g._load_level(10)
 for b in g.model.buses: b.status="yard" if b.id in [4,9] else "gone"
 var start:Vector2=g.bus_visuals[4].position
 g._dispatch(4)
 await create_timer(0.17).timeout
 check(g.bus_visuals[4].position.distance_to(start)>3,"Green truck visibly moves")
 await create_timer(0.5).timeout
 check(g.bus_visuals[4].position.distance_to(start)<0.01,"Green truck returns")
 check(g.impact.get("obstacle",-1)==9,"Correct obstacle feedback")
 check(not g.road_busy,"Road unlocked")
 g.model.bays=[0,1,2,-1,-1]
 g._dispatch(4)
 check(g.road_busy,"Blocked feedback even when bays occupied")
 await create_timer(0.7).timeout
 g.free()
 print("Blocked contact regression: ",pairs," pairs; ",failures," failures")
 quit(1 if failures else 0)
