extends RefCounted
## All coordinates share the truck's world space, including tablet layouts.
const BASE = preload("res://assets/artwork/crane/crane-base-section.png")
const MID = preload("res://assets/artwork/crane/crane-mid-section.png")
const END = preload("res://assets/artwork/crane/crane-end-section.png")
const MAGNET = preload("res://assets/artwork/crane/magnet-hoist.png")
const DURATION = 6.2
const CONTACT = 2.15

static func phase(t:float,a:float,b:float) -> float:
	return smoothstep(0.0,1.0,clampf((t-a)/(b-a),0.0,1.0))

static func pose(t:float,start:Vector2,destination:Vector2) -> Dictionary:
	var transport := phase(t,2.65,4.15)
	var tip := start.lerp(destination,transport)
	var arrival := phase(t,0.0,0.85)
	var extension := phase(t,0.85,1.65)
	var retract := phase(t,4.85,5.55)
	var exit := phase(t,5.55,DURATION)
	var y := lerpf(-100.0,tip.y,arrival)
	y = lerpf(y,-100.0,exit)
	var x := lerpf(420.0,tip.x,extension*(1.0-retract))
	var lift := phase(t,CONTACT,2.65)*(1.0-phase(t,4.15,4.7))
	var magnet_scale := 1.0-0.16*phase(t,1.65,CONTACT)+0.16*phase(t,CONTACT,2.65)
	magnet_scale -= 0.16*phase(t,4.15,4.7)
	magnet_scale += 0.16*phase(t,4.7,4.85)
	return {"tip":Vector2(x,y),"truck":tip,"lift":lift,"turn":transport,"magnet_scale":magnet_scale,"attached":t>=CONTACT and t<4.7}

static func segment(c:CanvasItem,texture:Texture2D,left:float,right:float,y:float,scale:float) -> void:
	var width := minf(right-left,texture.get_width()*scale)
	if width<=0: return
	var height := texture.get_height()*scale
	c.draw_texture_rect_region(texture,Rect2(right-width,y-height*0.5,width,height),Rect2(texture.get_width()-width/scale,0,width/scale,texture.get_height()))

static func draw_arm(c:CanvasItem,state:Dictionary) -> void:
	var tip:Vector2 = state.tip
	var span := 554.0-tip.x
	var length := minf(216.0,span)
	var extension := maxf(0.0,span-length)
	# Inner sections sit behind their sleeves; overlap hides the joins.
	segment(c,END,tip.x,tip.x+minf(193.0,span),tip.y,0.42)
	segment(c,MID,554.0-length-extension*0.5,554.0-length+30.0,tip.y,0.42)
	segment(c,BASE,554.0-length,554.0,tip.y,0.36)

static func draw_magnet(c:CanvasItem,state:Dictionary) -> void:
	var size := Vector2(64,64)*float(state.magnet_scale)
	c.draw_texture_rect(MAGNET,Rect2(Vector2(state.tip)-size*0.5,size),false)
