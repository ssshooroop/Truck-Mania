extends RefCounted
## World coordinates stay unchanged: one similarity transform preserves all clearances.
const SPLIT := 185.0
static func world(view:Vector2) -> Transform2D:
	var factor:float = minf(view.x/540.0,(view.y-SPLIT-80.0)/(1090.0-SPLIT))
	factor = maxf(0.25,factor)
	return Transform2D(0.0,Vector2.ONE*factor,0.0,Vector2((view.x-540.0*factor)*0.5,SPLIT*(1.0-factor)))
static func panel(view:Vector2) -> Transform2D:
	var factor:float = minf(view.x/540.0,view.y/1171.0)
	return Transform2D(0.0,Vector2.ONE*factor,0.0,(view-Vector2(540,1171)*factor)*0.5)

static func yard(buses:Array,target:Rect2) -> Transform2D:
	var best := Transform2D.IDENTITY
	var best_scale := 0.0
	for angle:float in [0.0,PI/2]:
		var bounds := Rect2()
		var first := true
		for bus:Dictionary in buses:
			var length:float = [98.24,139.37,182.79][bus.kind]
			for x in [-28.0,28.0]:
				for y in [-length/2,length/2]:
					var p:Vector2 = (bus.position+Vector2(x,y).rotated(bus.angle)).rotated(angle)
					if first: bounds=Rect2(p,Vector2.ZERO); first=false
					else: bounds=bounds.expand(p)
		var factor:float = minf(0.85,minf(target.size.x/bounds.size.x,target.size.y/bounds.size.y))
		if factor <= best_scale*1.05: continue
		best_scale=factor
		best=Transform2D(angle,Vector2.ONE*factor,0.0,target.get_center()-bounds.get_center()*factor)
	return best
