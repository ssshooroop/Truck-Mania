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
func block_gap(m,a:Dictionary,b:Dictionary) -> float:
 var f:Vector2=m.forward(a)
 var side:=Vector2(-f.y,f.x)
 var g:Vector2=m.forward(b)
 var across:=Vector2(-g.y,g.x)
 var sa:Vector2=m.vehicle_size(a)
 var sb:Vector2=m.vehicle_size(b)
 var delta:Vector2=b.position-a.position
 var enter:=0.0
 for axis:Vector2 in [f,side,g,across]:
  var speed:float=f.dot(axis)
  if absf(speed)<0.00001: continue
  var radius:float=absf(axis.dot(side))*sa.x/2+absf(axis.dot(f))*sa.y/2+absf(axis.dot(across))*sb.x/2+absf(axis.dot(g))*sb.y/2
  enter=maxf(enter,minf((delta.dot(axis)-radius)/speed,(delta.dot(axis)+radius)/speed))
 return enter

func cost(m,links:Array,center:Vector2) -> float:
 var value:=0.0
 for a:Dictionary in m.buses:
  value+=a.position.distance_to(center)*0.15
  var nearest:=INF
  for b:Dictionary in m.buses:
   if a.id!=b.id and links[a.id][b.id]: nearest=minf(nearest,block_gap(m,a,b))
  if is_finite(nearest): value+=pow(maxf(0,nearest-18),2)
 return value

func _initialize():
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/playtest10-before-density.json"))
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
  # Reduce remote-looking blockers as well as the parking footprint.
  var score:float=cost(m,links,center)
  for step in [4.0,2.0,1.0]:
   for iteration in 35:
    var changed:=false
    for b:Dictionary in m.buses:
     var start:Vector2=b.position
     var best:=start
     for turn in 8:
      b.position=start+Vector2.from_angle(turn*PI/4)*step
      if not valid(m,b.id,links): continue
      var candidate:float=cost(m,links,center)
      if candidate<score-0.001:
       score=candidate
       best=b.position
     b.position=best
     if best!=start: changed=true
    if not changed: break
  var after:=0.0
  for b:Dictionary in m.buses:
   after+=b.position.distance_to(center)
   data.levels[index].vehicles[b.id].x=b.position.x
   data.levels[index].vehicles[b.id].y=b.position.y
  report.append({"level":index+1,"radius_before":before/m.buses.size(),"radius_after":after/m.buses.size()})
 data.revision="playtest10-compact-2026-10-17"
 for path in ["res://config/campaign.json"]:
  FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
 FileAccess.open("res://artifacts/playtest10-compaction-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print("Compacted 10 playtest levels without changing any blocking relationships")
 quit()
