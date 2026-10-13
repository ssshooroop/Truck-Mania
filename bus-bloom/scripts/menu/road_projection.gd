extends Resource

@export_range(0.1,1.55) var curvature: float = 1.43
@export_range(0.2,2.0) var span: float = 0.72
@export_range(0.0,0.9) var perspective: float = 0.64
# Normalized texture coordinates; editable in the inspector.
@export var centerline: PackedVector2Array = PackedVector2Array()

func center_x(world: float) -> float:
	var v = fposmod(world,1.0)
	if centerline.is_empty(): return 0.5
	for i in range(1,centerline.size()):
		if v <= centerline[i].y:
			var a = centerline[i-1]
			var b = centerline[i]
			var correction = 0.0029686*(smoothstep(0.94,1.0,v)-(1.0-smoothstep(0.0,0.06,v)))
			return lerpf(a.x,b.x,inverse_lerp(a.y,b.y,v))-correction
	return centerline[-1].x

func project(world: float, lateral: float, scroll: float, area: Rect2) -> Vector3:
	var t = (world-scroll)*2.0/span
	var angle = minf(t,0.0)*curvature
	var depth = lerpf(1.0,cos(angle),perspective)
	var screen_y = sin(angle)/sin(curvature) if t<0.0 else t*curvature/sin(curvature)
	return Vector3(area.get_center().x+(center_x(world)-0.5+lateral)*area.size.x*depth, area.get_center().y+screen_y*area.size.y*0.5, depth if t>-1.0 and screen_y<1.0 else 0.0)

func world_at_y(y:float, area:Rect2) -> float:
	var t = clampf((y-area.get_center().y)/(area.size.y*0.5),-1.0,1.0)
	var surface = asin(t*sin(curvature))/curvature if t<0.0 else t*sin(curvature)/curvature
	return surface*span*0.5
