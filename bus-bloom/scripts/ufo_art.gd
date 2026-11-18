extends RefCounted
const TEXTURE=preload("res://assets/artwork/ufo/ufo.png")
const DURATION:=5.6
const TURN_START:=1.7
const TURN_END:=3.7

static func turn(t:float) -> float:
	return smoothstep(0.0,1.0,clampf((t-TURN_START)/(TURN_END-TURN_START),0.0,1.0))

static func draw(canvas:CanvasItem,state:Dictionary,reduced:bool) -> void:
	if state.is_empty(): return
	var t:float=state.time
	var target:Vector2=state.center
	var hover:=target+Vector2(0,-105)
	var position:Vector2=hover
	if t<1.4: position=Vector2(-100,hover.y-90).lerp(hover,smoothstep(0,1,t/1.4))
	elif t>4.2: position=hover.lerp(Vector2(650,hover.y-140),smoothstep(0,1,(t-4.2)/1.4))
	var beam:float=clampf((t-1.2)/0.5,0,1)*clampf((4.3-t)/0.5,0,1)
	if beam>0:
		canvas.draw_colored_polygon(PackedVector2Array([position+Vector2(-12,10),position+Vector2(12,10),target+Vector2(48,22),target+Vector2(-48,22)]),Color(0.2,1.0,0.85,0.23*beam))
		canvas.draw_arc(target,48,0,TAU,48,Color(0.4,1,0.8,0.8*beam),3,true)
		canvas.draw_circle(target,42,Color(0.4,1,0.8,0.12*beam))
	canvas.draw_set_transform(position,0.0 if reduced else t*1.8)
	canvas.draw_texture_rect(TEXTURE,Rect2(-50,-50,100,100),false)
	canvas.draw_set_transform(Vector2.ZERO)
