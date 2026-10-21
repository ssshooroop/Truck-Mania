extends RefCounted
## Trial rule: advance in the arrow direction, then turn into a clear exit lane.
## Uses the same remaining-yard mask for live rules and hypothetical hint states.
static func paths(model, id:int, mask:int) -> Array:
	var bus:Dictionary = model.buses[id]
	var size:Vector2 = model.vehicle_size(bus)
	var start:Vector2 = bus.position
	var heading:float = bus.angle
	var obstacles:Array = []
	for other:Dictionary in model.buses:
		if other.id!=id and (mask & (1<<int(other.id)))!=0: obstacles.append(other)
	var result:Array = []
	for distance:float in [size.y*0.35,size.y*0.65,size.y]:
		var end:Vector2 = start+model.forward(bus)*distance
		var prefix:Array = [{"position":start,"angle":heading,"distance":0.0}]
		var steps:int = ceili(distance/3.0)
		var valid := true
		for i in range(1,steps+1):
			var pose := {"position":start.lerp(end,float(i)/steps),"angle":heading,"distance":distance*i/steps}
			if not clear_segment(model,size,prefix.back(),pose,obstacles):
				valid=false
				break
			prefix.append(pose)
		if not valid: break # A longer forward approach hits the same obstacle.
		for turn:float in [-PI/4,PI/4,-PI/2,PI/2,-3*PI/4,3*PI/4,PI,-PI]:
			var rotated:Dictionary = bus.duplicate()
			rotated.position=end
			rotated.angle=heading+turn
			valid=true
			for other:Dictionary in obstacles:
				if model._sweep_hits(rotated,other):
					valid=false
					break
			if not valid: continue
			var path:Array = prefix.duplicate()
			steps=ceili(absf(turn)/deg_to_rad(2.0))
			for i in range(1,steps+1):
				var pose := {"position":end,"angle":heading+turn*i/steps,
					"distance":distance+absf(turn)*size.length()*0.5*i/steps}
				if not clear_segment(model,size,path.back(),pose,obstacles):
					valid=false
					break
				path.append(pose)
			if valid: result.append(path)
	return result

static func clear_segment(model,size:Vector2,a:Dictionary,b:Dictionary,obstacles:Array) -> bool:
	var angle:float = lerp_angle(a.angle,b.angle,0.5)
	var f := Vector2(sin(angle),-cos(angle))
	var side := Vector2(-f.y,f.x)
	var delta:Vector2 = b.position-a.position
	var turn:float = absf(angle_difference(a.angle,b.angle))*0.5
	# Envelope includes all intermediate rotations, not just sampled endpoints.
	var extent := Vector2(size.x*cos(turn)+size.y*sin(turn),size.y*cos(turn)+size.x*sin(turn))
	extent += Vector2(absf(delta.dot(side)),absf(delta.dot(f)))+Vector2(2,2)
	var p:Vector2 = (a.position+b.position)*0.5
	var half:Vector2 = (side.abs()*extent.x+f.abs()*extent.y)*0.5
	if p.x-half.x<0 or p.x+half.x>540 or p.y-half.y<500 or p.y+half.y>1120: return false
	for other:Dictionary in obstacles:
		if model._rectangles_overlap(p,f,extent,other.position,model.forward(other),model.vehicle_size(other)): return false
	return true
