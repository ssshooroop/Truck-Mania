extends RefCounted
## Reserved arrival routes share a clock. Intersections yield; unrelated routes run together.
var routes:Dictionary = {}

static func pose(route:Dictionary,time:float) -> Dictionary:
	var path:Array=route.path
	var distance:float=path.back().distance*clampf((time-route.delay)/route.duration,0,1)
	var low=0
	var high=path.size()-1
	while high-low>1:
		var mid:int=(low+high)/2
		if path[mid].distance<distance: low=mid
		else: high=mid
	var weight:float=clampf(inverse_lerp(path[low].distance,path[high].distance,distance),0,1)
	return {"position":Vector2(path[low].position).lerp(path[high].position,weight),
		"angle":lerp_angle(path[low].angle,path[high].angle,weight)}

func reserve(game,id:int,path:Array) -> bool:
	var size:Vector2=game.model.vehicle_size(game.model.buses[id])
	var duration:float=game._duration(maxf(0.06,path.back().distance/420.0))
	var gain=1.0
	for i in range(1,path.size()):
		var d:float=path[i].distance-path[i-1].distance
		if d<=0: continue
		var travel:float=path[i].position.distance_to(path[i-1].position)
		travel+=absf(angle_difference(path[i-1].angle,path[i].angle))*size.length()*0.5
		gain=maxf(gain,travel/d)
	var route={"path":path,"size":size,"duration":duration,"delay":0.0,"elapsed":0.0,
		"corner_speed":gain*path.back().distance/duration}
	var limit=0.0
	for other:Dictionary in routes.values():limit=maxf(limit,other.delay+other.duration-other.elapsed)
	var step:float=game._duration(0.08)
	for attempt in range(ceili(limit/step)+2):
		route.delay=attempt*step
		var clear=true
		for other:Dictionary in routes.values():
			if _conflicts(game.model,route,other,game._duration(0.02)):
				clear=false
				break
		if clear:
			routes[id]=route
			return true
	return false

func _conflicts(model,a:Dictionary,b:Dictionary,step:float) -> bool:
	var end:float=maxf(a.delay+a.duration,b.delay+b.duration-b.elapsed)
	var samples:int=maxi(1,ceili(end/step))
	var dt:float=end/samples
	for i in samples:
		var time:float=(i+0.5)*dt
		var pa:Dictionary=pose(a,time)
		var pb:Dictionary=pose(b,time+b.elapsed)
		# A corner moves no more than speed*dt/2 from this midpoint pose.
		# Inflating the rectangles therefore covers the complete time interval.
		var pad_a:float=a.corner_speed*dt*0.5+1.0
		var pad_b:float=b.corner_speed*dt*0.5+1.0
		if time+dt*0.5<=a.delay or time-dt*0.5>=a.delay+a.duration:pad_a=1.0
		if time+b.elapsed+dt*0.5<=b.delay or time+b.elapsed-dt*0.5>=b.delay+b.duration:pad_b=1.0
		var radius:float=(a.size.length()+b.size.length())*0.5+pad_a+pad_b
		if pa.position.distance_squared_to(pb.position)>radius*radius:continue
		var fa=Vector2(sin(pa.angle),-cos(pa.angle))
		var fb=Vector2(sin(pb.angle),-cos(pb.angle))
		if model._rectangles_overlap(pa.position,fa,a.size+Vector2.ONE*pad_a*2,pb.position,fb,b.size+Vector2.ONE*pad_b*2):return true
	return false

func advance(game,delta:float) -> void:
	for id in routes.keys():
		var route:Dictionary=routes[id]
		route.elapsed+=delta
		if route.elapsed>route.delay and not route.get("start_sound",false):
			route.start_sound=true
			game._sound_effect("start")
		if route.elapsed>=route.delay+route.duration-minf(route.duration*0.2,game._duration(0.2)) and not route.get("skid_sound",false):
			route.skid_sound=true
			game._sound_effect("skid")
		var p:Dictionary=pose(route,route.elapsed)
		game.bus_visuals[id].position=p.position
		game.bus_visuals[id].angle=p.angle
		if route.elapsed>=route.delay+route.duration:routes.erase(id)
