extends Resource

@export_range(0.1,1.55) var curvature: float = 1.43
@export_range(0.2,2.0) var span: float = 0.72
@export_range(0.0,0.9) var perspective: float = 0.64
# Normalized texture coordinates; editable in the inspector.
@export var centerline: PackedVector2Array = PackedVector2Array()

@export var edges: PackedVector2Array = PackedVector2Array()
# Inverse of road.gdshader's piecewise seam alignment, for markers and scenery.
const SEAM_TOP = [0.0,516.0,600.0,782.0,819.0,1008.0,1082.0,1536.0]
const SEAM_BOTTOM = [0.0,498.0,574.0,755.0,792.0,1012.0,1095.0,1536.0]

func _aligned_x(x:float,v:float) -> float:
	var weight:float = 1.0-smoothstep(0.0,0.06,minf(v,1.0-v))
	var source:Array = SEAM_TOP if v<0.5 else SEAM_BOTTOM
	var px:float = x*1536.0
	for i in 7:
		var left:float = (SEAM_TOP[i]+SEAM_BOTTOM[i])*0.5
		var right:float = (SEAM_TOP[i+1]+SEAM_BOTTOM[i+1])*0.5
		var a:float = lerpf(left,source[i],weight)
		var b:float = lerpf(right,source[i+1],weight)
		if px<=b:
			return lerpf(left,right,(px-a)/(b-a))/1536.0
	return x

func center_x(world:float) -> float:
	var bounds := road_edges(world)
	return (bounds.x+bounds.y)*0.5

func road_edges(world:float) -> Vector2:
	var v:float = fposmod(world,1.0)
	if edges.is_empty(): return Vector2(0.37,0.63)
	var sample:float = v*(edges.size()-1)
	var i:int = mini(floori(sample),edges.size()-2)
	var bounds:Vector2 = edges[i].lerp(edges[i+1],sample-i)
	return Vector2(_aligned_x(bounds.x,v),_aligned_x(bounds.y,v))

# Include the road underneath a tall decoration's upper silhouette.
func scenery_edges(world:float) -> Vector2:
	var bounds := road_edges(world)
	for i in range(1,9):
		var above := road_edges(world-i*0.016)
		bounds.x = minf(bounds.x,above.x)
		bounds.y = maxf(bounds.y,above.y)
	return bounds

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
