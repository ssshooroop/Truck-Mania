extends RefCounted
const TUTORIAL_LEVEL = 2
const PRICE = 100
const CONE = preload("res://assets/artwork/cargo/traffic-cone.png")
const COIN = preload("res://assets/artwork/menu/coin.png")
static var cone_region: Rect2
static var coin_region: Rect2

static func price(_bay:int) -> int:
	return PRICE

static func draw_cone(canvas:CanvasItem,center:Vector2) -> void:
	if cone_region.size==Vector2.ZERO: cone_region = Rect2(CONE.get_image().get_used_rect())
	var size: Vector2 = cone_region.size*(62.0/cone_region.size.y)
	canvas.draw_texture_rect_region(CONE,Rect2(center+Vector2(0,-3)-size/2,size),cone_region)

static func draw_pop(canvas:CanvasItem,center:Vector2,age:float,reduced:bool) -> void:
	if coin_region.size==Vector2.ZERO: coin_region = Rect2(COIN.get_image().get_used_rect())
	var burst: float = clampf((age-0.72)/0.28,0.0,1.0)
	var fade: float = 1.0-burst
	var zoom: float = 1.0 if reduced else lerpf(0.65,1.0,minf(age/0.13,1.0))+burst*0.15
	var pos: Vector2 = center+Vector2(0,-52-(0.0 if reduced else minf(age,0.72)*18))
	canvas.art_transform(pos,0,Vector2.ONE*zoom)
	if burst<0.5:
		canvas.draw_style_box(_bubble(Color(0.08,0.17,0.28,fade)),Rect2(-57,-22,114,44))
		canvas._text("−100",Vector2(-13,9),26,Color(1,1,1,fade),true)
		var size: Vector2 = coin_region.size*(30.0/coin_region.size.y)
		canvas.draw_texture_rect_region(COIN,Rect2(Vector2(33,0)-size/2,size),coin_region,Color(1,1,1,fade))
	if burst>0 and not reduced:
		for i in 8:
			var dir := Vector2.from_angle(i*TAU/8.0)
			canvas.draw_line(dir*(30+burst*20),dir*(37+burst*27),Color(1,0.87,0.36,fade),2.5,true)
	canvas.art_transform(Vector2.ZERO)

static func _bubble(color:Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(22)
	style.border_color = Color(1,0.89,0.47,color.a)
	style.set_border_width_all(2)
	return style
