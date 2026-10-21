extends RefCounted
## Presentation only: the wallet is saved before this animation starts.
const PICTURE = preload("res://assets/artwork/menu/Contented Construction Worker’s Ice Cream Break.png")
const COIN = preload("res://assets/artwork/menu/coin.png")
const AD = preload("res://assets/artwork/menu/ad-player.png")
const HEAVY = preload("res://assets/fonts/MPLUSRounded1c-Black.ttf")
const LABEL = preload("res://assets/fonts/MPLUSRounded1c-Bold.ttf")
const PHOTO = Rect2(54,218,432,432)
const REPLAY = Rect2(46,999,194,88)
const NEXT = Rect2(294,999,194,88)
const DOUBLE = Rect2(28,832,484,82)
const ORIGIN = Vector2(194,749)
const PARTICLES = 14
const FIRST_ARRIVAL = 1.18
const END = 2.26
var coin_region: Rect2
var ad_region: Rect2

func _init() -> void:
	coin_region = Rect2(COIN.get_image().get_used_rect())
	ad_region = Rect2(AD.get_image().get_used_rect())

static func displayed_balance(before:int,after:int,age:float,reduced:bool) -> int:
	if reduced or after<=before: return after
	var progress := clampf((age-FIRST_ARRIVAL)/(END-FIRST_ARRIVAL),0.0,1.0)
	return roundi(lerpf(before,after,progress))

static func flight(index:int,age:float,target:Vector2) -> Dictionary:
	var start_time := 0.50+index*0.065
	var duration := 0.68+index*0.018
	var t := (age-start_time)/duration
	if t<0.0 or t>=1.0: return {}
	var progress := t*t*(2.0-t)
	var start := ORIGIN+Vector2((index%3-1)*7,12)
	var bend := Vector2(48+(index%4)*9,0)
	var position := start.lerp(target,progress)+bend*sin(PI*progress)
	return {"position":position,"size":lerpf(48,14,progress),"angle":sin(t*TAU+index)*0.18,"progress":progress}

func _text(canvas:CanvasItem,value:String,center:Vector2,size:int,color:Color,font:Font=LABEL) -> void:
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	canvas.draw_string(font,center-Vector2(width*0.5,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _coin(canvas:CanvasItem,center:Vector2,size:float,angle:float=0.0) -> void:
	var drawn := coin_region.size*minf(size/coin_region.size.x,size/coin_region.size.y)
	canvas.art_transform(center,angle)
	canvas.draw_texture_rect_region(COIN,Rect2(-drawn*0.5,drawn),coin_region)
	canvas.art_transform(Vector2.ZERO)

func draw(canvas,age:float,reward:int,target:Vector2,reduced:bool,last_level:bool) -> void:
	_text(canvas,"Груз",Vector2(270,139),52,Color("fff0ac"),HEAVY)
	_text(canvas,"отправлен!",Vector2(270,194),52,Color("fff0ac"),HEAVY)
	# Rounded textured polygon, preserving the square illustration's aspect ratio.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var radius := 28.0
	var corners := [PHOTO.position+Vector2(radius,radius),Vector2(PHOTO.end.x-radius,PHOTO.position.y+radius),PHOTO.end-Vector2(radius,radius),Vector2(PHOTO.position.x+radius,PHOTO.end.y-radius)]
	for corner in 4:
		for step in 13:
			var angle := PI+corner*PI*0.5+step*PI/24.0
			var point: Vector2 = corners[corner]+Vector2.from_angle(angle)*radius
			points.append(point)
			uvs.append((point-PHOTO.position)/PHOTO.size)
	canvas.draw_polygon(points,PackedColorArray([Color.WHITE]),uvs,PICTURE)
	var wobble := 0.0
	if not reduced and reward>0 and age<0.55: wobble = sin(clampf(age/0.55,0.0,1.0)*PI)
	_coin(canvas,ORIGIN+Vector2(0,wobble*13),108,wobble*0.14)
	_text(canvas,"+%d" % reward,Vector2(314,764),53,Color("54db72"),HEAVY)
	if reward==0: _text(canvas,"Награда уже получена",Vector2(270,802),20,Color("cbd6e7"))
	# Ad service is not connected: the offer must never award an unearned bonus.
	canvas._round(DOUBLE,Color(0.12,0.18,0.28,0.35),27,true,Color("8296ac"),1)
	_text(canvas,"УДВОИТЬ?",Vector2(219,884),33,Color("9cb7b1"))
	var ad_size := ad_region.size*minf(86.0/ad_region.size.x,58.0/ad_region.size.y)
	canvas.draw_texture_rect_region(AD,Rect2(Vector2(432,873)-ad_size*0.5,ad_size),ad_region,Color(1,1,1,0.65))
	_text(canvas,"Реклама пока недоступна",Vector2(270,943),16,Color("9eacc0"))
	for rect: Rect2 in [REPLAY,NEXT]:
		canvas._round(Rect2(rect.position+Vector2(0,4),rect.size),Color("3567b2"),24)
		canvas._round(rect,Color("548fea"),24)
	_text(canvas,"Сыграть",REPLAY.get_center()+Vector2(0,-3),25,Color("fff0ac"))
	_text(canvas,"ещё раз",REPLAY.get_center()+Vector2(0,28),25,Color("fff0ac"))
	_text(canvas,"Карта" if last_level else "Следующий",NEXT.get_center()+Vector2(0,-3),23,Color("fff0ac"))
	_text(canvas,"уровней" if last_level else "уровень",NEXT.get_center()+Vector2(0,28),25,Color("fff0ac"))
	if reward>0 and not reduced:
		for i in PARTICLES:
			var pose := flight(i,age,target)
			if not pose.is_empty(): _coin(canvas,pose.position,pose.size,pose.angle)
