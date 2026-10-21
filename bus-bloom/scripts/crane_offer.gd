extends "res://scripts/parking_full.gd"
const CRANE_PICTURE=preload("res://assets/artwork/menu/Cheerful Crane-Suspended Construction Worker.png")
const ART=Rect2(40,228,460,450)
const CALL=Rect2(36,768,468,64)
const INTRO_LEVEL=15
const REPEAT_PRICE=150
func _ready():
	super._ready()
	texture=CRANE_PICTURE
func sync(game):
	visible=game.overlay=="crane_preview"
	var t:Transform2D=game._panel_transform()
	position=t*ART.position
	size=ART.size*t.get_scale()
	material.set_shader_parameter("rect_size",size)
static func draw_crane(game):
	var cream=Color("fff0ac")
	var green=Color("31e762")
	game._juicy_text("Закончились",148,49,cream)
	game._juicy_text("ходы?",205,49,cream)
	game._juicy_text("Вызовите кран!",724,34,Color.WHITE)
	box(game,CALL,Color.TRANSPARENT,Color("40ad52"))
	game._text("Вызвать бесплатно",Vector2(270,808),30,green,true)
	game._text("В первый раз бесплатно,",Vector2(270,887),27,green,true)
	game._text("потом —",Vector2(270,920),27,green,true)
	game._text(str(REPEAT_PRICE),Vector2(251,979),32,Color("fff329"),true)
	icon(game,COIN,Vector2(328,968),43)
	var undo=Rect2(45,1050,190,80)
	var retry=Rect2(305,1050,190,80)
	box(game,undo,Color("5a95f2"),Color.TRANSPARENT)
	game._text("Отмена",Vector2(136,1081),25,cream,true)
	game._text("хода 20",Vector2(126,1113),25,cream,true)
	icon(game,COIN,Vector2(207,1103),36)
	box(game,retry,Color("5a95f2"),Color.TRANSPARENT)
	game._text("Попробовать",Vector2(400,1081),20,cream,true)
	game._text("заново",Vector2(400,1113),23,cream,true)
