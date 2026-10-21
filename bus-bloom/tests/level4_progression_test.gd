extends SceneTree
const Model=preload("res://scripts/game_model.gd")
var m=Model.new()
var memo={}
func available(mask:int)->Array:
 if memo.has(mask):return memo[mask]
 var ids=[]
 for b in m.buses:
  if (mask & (1<<int(b.id)))==0:continue
  var blocked=false
  for o in m.buses:
   if o.id!=b.id and (mask & (1<<int(o.id)))!=0 and m._sweep_hits(b,o):blocked=true
  if not blocked or not m.maneuver_paths(b.id,mask).is_empty():ids.append(b.id)
 memo[mask]=ids
 return ids
func _initialize():
 m.load_level(3)
 var failures=0
 for b in m.buses:
  var size=m.vehicle_size(b)
  var f=m.forward(b)
  var half=(Vector2(-f.y,f.x).abs()*size.x+f.abs()*size.y)*0.5
  if not Model.YARD_RECT.encloses(Rect2(b.position-half,half*2)): failures+=1
  for o in m.buses:
   if o.id>b.id and m._rectangles_overlap(b.position,f,size+Vector2(6,6),o.position,m.forward(o),m.vehicle_size(o)+Vector2(6,6)):
    print("SPACING FAILURE ",b.id," ",o.id)
    failures+=1
 var pending=[511]
 var visited={}
 var max_new=0
 while not pending.is_empty():
  var mask:int=pending.pop_back()
  if visited.has(mask):continue
  visited[mask]=true
  var current=available(mask)
  if mask!=0 and current.is_empty():failures+=1
  for id in current:
   var child=mask & ~(1<<id)
   var fresh=0
   for next in available(child):
    if next not in current:fresh+=1
   max_new=maxi(max_new,fresh)
   pending.append(child)
 var order=[0,4,8,2,1,5,6,7,3]
 var mask=511
 var profile=[]
 for id in order:
  var ids=available(mask)
  profile.append(ids.size())
  if id not in ids:failures+=1
  mask &= ~(1<<id)
 if available(511).size()!=4 or max_new>2:failures+=1
 var report={"initial_free":available(511),"initial_blocked":9-available(511).size(),"reference_order":order,"available_counts":profile,"reachable_yard_states":visited.size(),"max_newly_released_by_one_move":max_new,"failures":failures}
 FileAccess.open("res://artifacts/level4-repacked-audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report))
 quit(1 if failures else 0)
