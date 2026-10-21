extends SceneTree
const M=preload("res://scripts/game_model.gd")
func _initialize():
 var m=M.new()
 m.load_level(3)
 for b in m.buses:print(b.id," blocks=",m.blocking_ids(b.id))
 var order=[0,4,8,2,1,5,6,7,3]
 for step in range(10):
  var direct=[]
  var legal=[]
  for b in m.buses:
   if b.status!="yard": continue
   if m.blocking_ids(b.id).is_empty():direct.append(b.id)
   if m.can_dispatch(b.id):legal.append(b.id)
  print(step," direct=",direct," maneuver=",legal)
  if step<9:m.buses[order[step]].status="gone"
 quit()
