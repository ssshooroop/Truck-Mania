extends SceneTree
const Model=preload("res://scripts/game_model.gd")
func valid(m, id:int, links:Array) -> bool:
 var b:Dictionary=m.buses[id]
 var half:Vector2=(Vector2(cos(b.angle),sin(b.angle)).abs()*m.vehicle_size(b).x+m.forward(b).abs()*m.vehicle_size(b).y)*0.5
 if not Model.YARD_RECT.encloses(Rect2(b.position-half,half*2)): return false
 for other:Dictionary in m.buses:
  if other.id==id: continue
  if m._rectangles_overlap(b.position,m.forward(b),m.vehicle_size(b)+Vector2(6,6),other.position,m.forward(other),m.vehicle_size(other)+Vector2(6,6)): return false
  if m._sweep_hits(b,other)!=links[id][other.id] or m._sweep_hits(other,b)!=links[other.id][id]: return false
 return true
func _initialize():
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/campaign-before-compact.json"))
 var report:Array=[]
 for index in data.levels.size():
  var m=Model.new()
  m.load_level(index)
  for v:Dictionary in data.levels[index].vehicles:
   m.buses[int(v.id)].position=Vector2(v.x,v.y)
  var links:Array=[]
  var center:=Vector2.ZERO
  for b:Dictionary in m.buses:
   center+=b.position
   var row:Array=[]
   for other:Dictionary in m.buses: row.append(m._sweep_hits(b,other))
   links.append(row)
  center/=m.buses.size()
  var before:=0.0
  for b:Dictionary in m.buses: before+=b.position.distance_to(center)
  for step in [4.0,2.0,1.0]:
   for iteration in 60:
    var changed:=false
    for b:Dictionary in m.buses:
     var start:Vector2=b.position
     var delta:Vector2=center-start
     for move in [delta.normalized()*step,Vector2(signf(delta.x)*step,0),Vector2(0,signf(delta.y)*step)]:
      if (start+move).distance_squared_to(center)>=start.distance_squared_to(center): continue
      b.position=start+move
      if valid(m,b.id,links):
       changed=true
       break
      b.position=start
    if not changed: break
  var after:=0.0
  for b:Dictionary in m.buses:
   after+=b.position.distance_to(center)
   data.levels[index].vehicles[b.id].x=b.position.x
   data.levels[index].vehicles[b.id].y=b.position.y
  report.append({"level":index+1,"radius_before":before/m.buses.size(),"radius_after":after/m.buses.size()})
 data.revision="compact-2026-10-15"
 for path in ["res://config/campaign.json","res://generated_levels/levels.json"]:
  FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
 FileAccess.open("res://artifacts/compaction-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print("Compacted 100 levels without changing any blocking relationships")
 quit()
