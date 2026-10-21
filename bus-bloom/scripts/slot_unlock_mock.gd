extends Node2D
## Visual approval scene only. The 150-coin price is not applied to the game economy.
const CONE=preload("res://assets/artwork/cargo/traffic-cone.png")
const COIN=preload("res://assets/artwork/menu/coin.png")
const AD=preload("res://assets/artwork/menu/ad-player.png")
const BACK=preload("res://assets/artwork/menu/arrow-blue.png")
const FONT=preload("res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf")
const BASE=Vector2(540,960)
var glow:GradientTexture2D
var age:=0.0
func _ready():
	var gradient=Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,0.48,0.68,1.0])
	gradient.colors=PackedColorArray([Color(0.80,0.84,0.12,0.65),Color(0.80,0.84,0.12,0.60),Color(0.80,0.84,0.12,0.28),Color(0.80,0.84,0.12,0.0)])
	glow=GradientTexture2D.new()
	glow.gradient=gradient
	glow.width=256
	glow.height=256
	glow.fill=GradientTexture2D.FILL_RADIAL
	glow.fill_from=Vector2(0.5,0.5)
	glow.fill_to=Vector2(1.0,0.5)
func _process(delta):
	age+=delta
	queue_redraw()
func text_center(value:String,center:Vector2,font_size:int,color:Color):
	var width=FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(FONT,center-Vector2(width/2,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func icon(tex:Texture2D,center:Vector2,extent:float):
	var region=Rect2(tex.get_image().get_used_rect())
	var fit=region.size*minf(extent/region.size.x,extent/region.size.y)
	draw_texture_rect_region(tex,Rect2(center-fit/2,fit),region)
func button(rect:Rect2,radius:int):
	var style=StyleBoxFlat.new()
	style.bg_color=Color("202e49")
	style.border_color=Color("36945c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	draw_style_box(style,rect)
func _draw():
	draw_rect(get_viewport_rect(),Color("202e49"))
	var factor=minf(get_viewport_rect().size.x/BASE.x,get_viewport_rect().size.y/BASE.y)
	draw_set_transform((get_viewport_rect().size-BASE*factor)/2,0,Vector2.ONE*factor)
	draw_texture_rect_region(BACK,Rect2(19,17,-80,80),Rect2(BACK.get_image().get_used_rect()))
	text_center("Убрать",Vector2(270,132),48,Color("b9c9e9"))
	text_center("конус?",Vector2(270,181),48,Color("b9c9e9"))
	var pulse=1.0+sin(age*2.4)*0.025
	draw_texture_rect(glow,Rect2(Vector2(270,446)-Vector2.ONE*218*pulse,Vector2.ONE*436*pulse),false)
	icon(CONE,Vector2(270,389),300)
	button(Rect2(39,664,488,84),18)
	text_center("150",Vector2(242,721),40,Color("40b66a"))
	icon(COIN,Vector2(333,706),50)
	text_center("или",Vector2(270,790),36,Color("eef3f7"))
	button(Rect2(39,816,488,108),48)
	icon(AD,Vector2(135,870),110)
	text_center("посмотреть",Vector2(358,862),32,Color("efa4e7"))
	text_center("рекламу",Vector2(358,901),32,Color("efa4e7"))

