extends Control
const LocalText = preload("res://scripts/ui/localized_text.gd")
## Reward definitions and persisted calendar state are supplied by the game.
signal closed
signal reward_requested(index:int)
const FONT=preload("res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf")
const DAY_FONT=preload("res://assets/fonts/MPLUSRounded1c-Medium.ttf")
const CHECK=preload("res://assets/artwork/menu/green-checkmark.png")
const TAPE=preload("res://assets/artwork/menu/yellow-black-tape.png")
const COINS=preload("res://assets/artwork/menu/coins-stack-medium.png")
const UNDO=preload("res://assets/artwork/menu/undo.png")
const CRATE=preload("res://assets/artwork/menu/сrate.png")
const PRIZE=preload("res://assets/sound/fx/prize.wav")
const BASE=Vector2(540,960)
var cards:Array=["claimed","claimed","available","locked","locked","locked","locked"]
var catalog=preload("res://scripts/daily_rewards.gd").new()
var rewards:Array=catalog.definitions()
var item_icons:Dictionary={}
var animation_index:=-1
var animation_age:=0.0
var player:AudioStreamPlayer
var sound_enabled:=true
var regions:Dictionary={}
func _ready():
	mouse_filter=Control.MOUSE_FILTER_STOP
	player=AudioStreamPlayer.new()
	player.stream=PRIZE
	player.volume_db=-9
	add_child(player)
	for tex in [CHECK,COINS,UNDO,CRATE]: regions[tex]=Rect2(tex.get_image().get_used_rect())
	for key in catalog.config.items:
		var tex=load("res://assets/artwork/menu/"+catalog.config.items[key].icon)
		item_icons[key]=tex
		regions[tex]=Rect2(tex.get_image().get_used_rect())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func configure(definitions:Array,states:Array):
	rewards=definitions.duplicate(true)
	cards=states.duplicate()
	queue_redraw()
func reveal(index:int):
	if index<0 or index>=7 or cards[index]=="claimed": return
	cards[index]="claimed"
	animation_index=index
	animation_age=0.0
	if sound_enabled and player: player.play()
func _process(delta):
	animation_age+=delta
	queue_redraw()
func transform_layout()->Transform2D:
	var zoom=minf(size.x/BASE.x,size.y/BASE.y)
	return Transform2D(0,Vector2.ONE*zoom,0,(size-BASE*zoom)/2)
func card_rect(index:int)->Rect2:
	if index==6: return Rect2(46,602,448,164)
	return Rect2(46+(index%3)*154,220+(index/3)*191,140,177)
func label(value:String,center:Vector2,font_size:int,tint:Color):
	LocalText.draw(self,value,center,FONT,font_size,tint,HORIZONTAL_ALIGNMENT_CENTER)
func box(rect:Rect2,tint:Color,radius:int=18,bottom_only:bool=false,border:bool=true):
	var style=StyleBoxFlat.new()
	style.bg_color=tint
	style.set_corner_radius_all(radius)
	if bottom_only:
		style.corner_radius_top_left=0
		style.corner_radius_top_right=0
	draw_style_box(style,rect)
	if border:
		var points=PackedVector2Array()
		var centers=[rect.position+Vector2(radius,radius),Vector2(rect.end.x-radius,rect.position.y+radius),rect.end-Vector2(radius,radius),Vector2(rect.position.x+radius,rect.end.y-radius)]
		for corner in 4:
			if bottom_only and corner<2:
				points.append(rect.position if corner==0 else Vector2(rect.end.x,rect.position.y))
			else:
				for step in 9:
					var angle=PI+corner*PI/2+step*PI/16
					points.append(centers[corner]+Vector2(cos(angle),sin(angle))*radius)
		points.append(points[0])
		var distance:=0.0
		for j in range(points.size()-1):
			var length=points[j].distance_to(points[j+1])
			var offset:=0.0
			while offset<length:
				var segment=minf(3.0-fmod(distance,3.0),length-offset)
				if fmod(distance,6.0)<3.0:draw_line(points[j].lerp(points[j+1],offset/length),points[j].lerp(points[j+1],(offset+segment)/length),Color("658d91"),0.8,true)
				offset+=maxf(segment,0.001)
				distance+=maxf(segment,0.001)
func icon(tex,center:Vector2,extent:float,alpha:float=1.0):
	var region:Rect2=regions[tex]
	var fit=region.size*minf(extent/region.size.x,extent/region.size.y)
	draw_texture_rect_region(tex,Rect2(center-fit/2,fit),region,Color(1,1,1,alpha))
func _draw():
	if not player:return
	draw_rect(Rect2(Vector2.ZERO,size),Color("202e49"))
	draw_set_transform_matrix(transform_layout())
	box(Rect2(30,186,480,600),Color("b7eee2"),26,true)
	box(Rect2(20,125,500,76),Color("e467df"),25,false,false)
	label("ЕЖЕДНЕВНЫЙ БОНУС",Vector2(270,173),31,Color.WHITE)
	var palette=["f7c49e","fff0a3","bcecae","b8eda7","a9dcf3","beb0f2","f7c49e"]
	for i in 7:
		var rect=card_rect(i)
		box(rect,Color(palette[i]))
		LocalText.draw(self,"День %d"%(i+1),rect.position+Vector2(12,23),DAY_FONT,15,Color("52617a"))
		var items:Array=rewards[i].rewards
		for j in items.size():
			var reward:Dictionary=items[j]
			var x:float=rect.size.x*(j+1)/(items.size()+1)
			var center=rect.position+Vector2(x,89 if i<6 else 77)
			icon(item_icons[reward.item],center,68 if items.size()>1 else 96)
			label(str(int(reward.quantity)),rect.position+Vector2(x,150 if i<6 else 144),23,Color("274a65"))

		if cards[i] in ["locked","missed"]:
			var a=rect.position+Vector2(5,57)
			var b=rect.position+Vector2(rect.size.x-5,124 if i<6 else 110)
			var perpendicular=(b-a).normalized().orthogonal()*9
			var points=PackedVector2Array([a+perpendicular,b+perpendicular,b-perpendicular,a-perpendicular])
			# Crop the supplied tape artwork, excluding its baked checkerboard.
			var uv=PackedVector2Array([Vector2(150,40),Vector2(770,40),Vector2(770,95),Vector2(150,95)])
			for k in 4:uv[k]/=Vector2(TAPE.get_size())
			draw_polygon(points,PackedColorArray([Color.WHITE]),uv,TAPE)
			if cards[i]=="missed":
				box(Rect2(rect.position+Vector2(8,116),Vector2(rect.size.x-16,28)),Color("53617a"),8)
				label("Пропущен",rect.position+Vector2(rect.size.x/2,137),17,Color.WHITE)
		elif cards[i]=="claimed":
			var t=clampf(animation_age/0.65,0,1) if i==animation_index else 1.0
			var pop=0.55+0.45*t+sin(t*PI)*0.14
			icon(CHECK,rect.position+Vector2(rect.size.x-15,16),52*pop,t)
		else:
			label("Забрать",rect.position+Vector2(rect.size.x/2,115),18,Color("16783d"))
	box(Rect2(150,810,240,48),Color("548fe5"),18,false,false)
	label("Продолжить",Vector2(270,842),22,Color.WHITE)
	label("Заходите каждый день",Vector2(270,893),22,Color("fff0a3"))
	label("и получайте призы!",Vector2(270,924),22,Color("a3ead1"))
func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var p=transform_layout().affine_inverse()*event.position
		if Rect2(150,810,240,48).has_point(p):
			closed.emit()
			accept_event()
			return
		for i in 7:
			if card_rect(i).has_point(p) and cards[i]=="available":
				reward_requested.emit(i)
				accept_event()
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: closed.emit()
