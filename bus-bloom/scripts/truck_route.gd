extends RefCounted
## Forward-only tangent arc / straight / arc connections, checked against actual bodies.
const Model=preload("res://scripts/game_model.gd")
var sampling_step:=3.0
var model
var size:Vector2
var obstacles:Array=[]
var reverse:=false
var connections:=0

func setup(game,id:int,backward:bool=false):
 model=game.model
 size=model.vehicle_size(model.buses[id])
 reverse=backward
 obstacles=[]
 for b:Dictionary in model.buses:
  if b.id!=id and b.status in ["yard","arriving","docked","leaving"]:
   var v:Dictionary=game.bus_visuals[b.id]
   if b.status=="arriving":
    # Arrival endpoints stay reserved. A timed route checks the moving body;
    # an arrival still waiting to plan also occupies its current position.
    if not game.traffic.routes.has(b.id):
     _obstacle(v.position,v.angle,model.vehicle_size(b))
    _obstacle(game._bay_position(b.bay,b.kind),game.BAY_ANGLE,model.vehicle_size(b))
    continue
   var f:Vector2=model.forward({"angle":v.angle})
   var dimensions:Vector2=model.vehicle_size(b)
   obstacles.append({"position":v.position,"forward":f,"side":Vector2(-f.y,f.x),"size":dimensions,
    "hw":dimensions.x*0.5,"hl":dimensions.y*0.5,"radius2":pow((size.length()+dimensions.length())*0.5+24,2)})

func _obstacle(p:Vector2,angle:float,dimensions:Vector2) -> void:
 var f:Vector2=model.forward({"angle":angle})
 obstacles.append({"position":p,"forward":f,"side":Vector2(-f.y,f.x),"size":dimensions,
  "hw":dimensions.x*0.5,"hl":dimensions.y*0.5,"radius2":pow((size.length()+dimensions.length())*0.5+24,2)})

func clear_pose(p:Vector2,a:float,margin:float=0.0,footprint:Vector2=Vector2.ZERO)->bool:
 var body:Vector2=size if footprint==Vector2.ZERO else footprint
 var f:=Vector2(cos(a),sin(a))
 var half:Vector2=(Vector2(-f.y,f.x).abs()*body.x+f.abs()*body.y)*0.5
 # Keep the body out of the conveyor and at least a sliver visible at the perimeter.
 if p.y-half.y<200 or p.x< -25 or p.x>565 or p.y>(700 if model.tablet_layout else 1196): return false
 var side:=Vector2(-f.y,f.x)
 var hw:float=(body.x+margin)*0.5
 var hl:float=(body.y+margin)*0.5
 for o:Dictionary in obstacles:
  var delta:Vector2=o.position-p
  if delta.length_squared()>o.radius2: continue
  var c:float=absf(f.dot(o.forward))
  var s:float=absf(side.dot(o.forward))
  if absf(delta.dot(f))>hl+o.hl*c+o.hw*s-0.001: continue
  if absf(delta.dot(side))>hw+o.hl*s+o.hw*c-0.001: continue
  if absf(delta.dot(o.forward))>o.hl+hl*c+hw*s-0.001: continue
  if absf(delta.dot(o.side))>o.hw+hl*s+hw*c-0.001: continue
  return false
 return true

func clear_sweep(a:Vector3,b:Vector3)->bool:
 var delta:=Vector2(b.x-a.x,b.y-a.y)
 var angle:=lerp_angle(a.z,b.z,0.5)
 var turn:=absf(angle_difference(a.z,b.z))*0.5
 var f:=Vector2(cos(angle),sin(angle))
 var side:=Vector2(-f.y,f.x)
 # This oriented envelope contains every interpolated body between two poses.
 # The turn per sample is small enough that both extent functions are monotone.
 var extent:=Vector2(absf(delta.dot(side)),absf(delta.dot(f)))
 extent+=Vector2(size.x*cos(turn)+size.y*sin(turn),size.y*cos(turn)+size.x*sin(turn))
 return clear_pose(Vector2(a.x+b.x,a.y+b.y)*0.5,angle,0.0,extent)

func connection(a:Vector3,b:Vector3)->Array:
 connections+=1
 var candidates:Array=[]
 for base_radius in [12.0,24.0,42.0,64.0]:
  var radius:float=base_radius*model.layout_scale
  for s1 in [-1.0,1.0]:
   for s2 in [-1.0,1.0]:
    var ca:Vector2=Vector2(a.x,a.y)+Vector2(-sin(a.z),cos(a.z))*radius*s1
    var cb:Vector2=Vector2(b.x,b.y)+Vector2(-sin(b.z),cos(b.z))*radius*s2
    var d:Vector2=cb-ca
    if d.length()<absf(radius*(s2-s1))+0.001: continue
    var heading:float=d.angle()-asin(clampf(radius*(s2-s1)/d.length(),-1,1))
    var arc1:=fposmod((heading-a.z)*s1,TAU)
    var arc2:=fposmod((b.z-heading)*s2,TAU)
    if arc1>TAU-0.00001: arc1=0.0
    if arc2>TAU-0.00001: arc2=0.0
    if arc1>PI*1.25 or arc2>PI*1.25 or arc1+arc2>PI*1.5: continue
    var straight:=sqrt(maxf(0,d.length_squared()-pow(radius*(s2-s1),2)))
    candidates.append({"length":radius*(arc1+arc2)+straight,"r":radius,"s1":s1,"s2":s2,"arc1":arc1,"arc2":arc2,"straight":straight})
 candidates.sort_custom(func(x,y):return x.length+(10000 if is_equal_approx(x.r,12*model.layout_scale) else 0)<y.length+(10000 if is_equal_approx(y.r,12*model.layout_scale) else 0))
 for c:Dictionary in candidates:
  var poses:Array=[a]
  var pose:=a
  var valid:=true
  for seg in [[c.arc1*c.r,c.s1/c.r],[c.straight,0.0],[c.arc2*c.r,c.s2/c.r]]:
   var n:=maxi(1,ceili(seg[0]/sampling_step))
   var distance:float=seg[0]/n
   for k in n:
    var heading:float=pose.z+seg[1]*distance
    var point:Vector2
    if absf(seg[1])<0.0001: point=Vector2(pose.x,pose.y)+Vector2(cos(pose.z),sin(pose.z))*distance
    else: point=Vector2(pose.x,pose.y)+Vector2(sin(heading)-sin(pose.z),cos(pose.z)-cos(heading))/seg[1]
    var previous_pose:Vector3=pose
    pose=Vector3(point.x,point.y,heading)
    if not clear_sweep(previous_pose,pose):
     valid=false
     break
    poses.append(pose)
   if not valid: break
  if valid:
   if Vector2(pose.x,pose.y).distance_to(Vector2(b.x,b.y))>0.1: continue
   poses[poses.size()-1]=b
   return poses
 return []

func length_of(path:Array)->float:
 var length:=0.0
 for i in range(1,path.size()): length+=Vector2(path[i].x-path[i-1].x,path[i].y-path[i-1].y).length()
 return length

func direct_plan(start:Vector2,angle:float,finish:Vector2,end_angle:float)->Array:
 var a:=Vector3(start.x,start.y,angle-PI/2+(PI if reverse else 0.0))
 var b:=Vector3(finish.x,finish.y,end_angle-PI/2+(PI if reverse else 0.0))
 var path:=connection(a,b)
 return [] if path.is_empty() else _convert(path)

func plan(start:Vector2,angle:float,finish:Vector2,end_angle:float)->Array:
 var a:=Vector3(start.x,start.y,angle-PI/2+(PI if reverse else 0.0))
 var b:=Vector3(finish.x,finish.y,end_angle-PI/2+(PI if reverse else 0.0))
 var direct:=connection(a,b)
 if not direct.is_empty(): return _convert(direct)
 var nodes:Array=[a,b]
 if sampling_step<=1.0:
  for distance in [100.0,160.0,220.0,280.0,340.0]:
   var p:Vector2=finish-Vector2(cos(b.z),sin(b.z))*distance
   if clear_pose(p,b.z): nodes.append(Vector3(p.x,p.y,b.z))
 for distance in [24.0,48.0,80.0,120.0,180.0,240.0,320.0,420.0,540.0,680.0]:
  var p:Vector2=start+Vector2(cos(a.z),sin(a.z))*distance
  if clear_pose(p,a.z): nodes.append(Vector3(p.x,p.y,a.z))
 var direction:=Vector2(cos(a.z),sin(a.z))
 for radius in [12.0,24.0]:
  if absf(direction.x)>0.01:
   for edge in [-18.0,8.0,532.0,558.0]:
    var distance:float=(edge-signf(direction.x)*radius-start.x)/direction.x
    var p:Vector2=start+direction*distance
    if distance>0 and clear_pose(p,a.z): nodes.append(Vector3(p.x,p.y,a.z))
  if absf(direction.y)>0.01:
   for edge in ([350.0,375.0,670.0] if model.tablet_layout else [475.0,500.0,1184.0]):
    var distance:float=(edge-signf(direction.y)*radius-start.y)/direction.y
    var p:Vector2=start+direction*distance
    if distance>0 and clear_pose(p,a.z): nodes.append(Vector3(p.x,p.y,a.z))
 # These are optional routing poses, not mandatory stops. Both sides compete by distance.
 for x in [-18.0,8.0,532.0,558.0]:
  for y in ([350.0,clampf(start.y,390,625),670.0] if model.tablet_layout else [500.0,clampf(start.y,570,1080),1184.0]):
   for heading in [-PI/2]: nodes.append(Vector3(x,y,heading))
 for x in [100.0,270.0,440.0]:
  for heading in [0.0,PI]: nodes.append(Vector3(x,670 if model.tablet_layout else 1184,heading))
 for x in [90.0,270.0,450.0]:
  for heading in [0.0,PI]: nodes.append(Vector3(x,350 if model.tablet_layout else 475,heading))
 var cost:Array=[]
 var previous:Array=[]
 var paths:Dictionary={}
 var closed:Dictionary={}
 for i in nodes.size():
  cost.append(INF)
  previous.append(-1)
 cost[0]=0.0
 for iteration in nodes.size():
  var current:=-1
  var score:=INF
  for i in nodes.size():
   if closed.has(i): continue
   var h:=Vector2(nodes[i].x-b.x,nodes[i].y-b.y).length()
   if cost[i]+h<score:
    score=cost[i]+h
    current=i
  if current<0: break
  if current==1:
   var route:Array=[]
   var cursor:=1
   while cursor!=0:
    route=paths[cursor]+route
    cursor=previous[cursor]
   return _convert(route)
  closed[current]=true
  var order:Array=range(1,nodes.size())
  order.sort_custom(func(i,j):return Vector2(nodes[i].x-b.x,nodes[i].y-b.y).length_squared()<Vector2(nodes[j].x-b.x,nodes[j].y-b.y).length_squared())
  for next:int in order:
   if closed.has(next): continue
   var lower:float=cost[current]+Vector2(nodes[current].x-nodes[next].x,nodes[current].y-nodes[next].y).length()
   if lower>=cost[next] or lower+Vector2(nodes[next].x-b.x,nodes[next].y-b.y).length()>=cost[1]: continue
   if not clear_pose(Vector2(nodes[next].x,nodes[next].y),nodes[next].z): continue
   var edge:=connection(nodes[current],nodes[next])
   if edge.is_empty(): continue
   var total:float=cost[current]+length_of(edge)
   if total<cost[next]:
    cost[next]=total
    previous[next]=current
    paths[next]=edge
 if sampling_step>1.0:
  sampling_step=1.0
  return plan(start,angle,finish,end_angle)
 return []

func _convert(path:Array)->Array:
 var result:Array=[]
 var length:=0.0
 var last:=Vector2(path[0].x,path[0].y)
 for pose:Vector3 in path:
  var p:=Vector2(pose.x,pose.y)
  length+=last.distance_to(p)
  if not result.is_empty() and last.distance_squared_to(p)<0.00001: continue
  result.append({"position":p,"angle":pose.z+PI/2-(PI if reverse else 0.0),"distance":length})
  last=p
 return result




