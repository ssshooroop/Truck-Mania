extends TextureRect
const PHOTO=preload("res://assets/artwork/menu/modals/open-extra-slot.png")
const COIN=preload("res://assets/artwork/menu/coin.png")
const AD=preload("res://assets/artwork/menu/ad-player.png")
const BUY=Rect2(32,645,476,98)
const VIDEO=Rect2(32,825,476,82)
const UNDO=Rect2(50,990,190,85)
const RETRY=Rect2(296,990,190,85)
const PICTURE=Rect2(45,228,450,396)
func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture=PHOTO
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var shader=Shader.new()
	shader.code="""shader_type canvas_item;
uniform vec2 rect_size=vec2(450.0,396.0);
varying vec2 mask_uv;
void vertex(){ mask_uv=VERTEX/rect_size; }
void fragment(){
 vec2 q=abs(mask_uv-vec2(0.5))-vec2(0.40);
 float d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-0.10;
 vec4 c=texture(TEXTURE,UV);
 c.a*=1.0-smoothstep(-0.075,0.0,d);
 COLOR=c;
}"""
	var effect=ShaderMaterial.new()
	effect.shader=shader
	material=effect
func sync(game):
	visible=game.overlay=="stuck"
	var t:Transform2D=game._panel_transform()
	position=t*PICTURE.position
	size=PICTURE.size*t.get_scale()
	material.set_shader_parameter("rect_size",size)
static func icon(game,tex,center:Vector2,side:float):
	var region=Rect2(tex.get_image().get_used_rect())
	var extent=region.size*minf(side/region.size.x,side/region.size.y)
	game.draw_texture_rect_region(tex,Rect2(center-extent/2,extent),region)
static func box(game,rect:Rect2,fill:Color,edge:Color):
	var style=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(28)
	game.draw_style_box(style,rect)
static func draw_ui(game):
	var cream=Color("fff0ac")
	var green=Color("51dc68")
	var mint=Color("a0e0ca")
	game._juicy_text("Парковка",145,49,cream)
	game._juicy_text("заполнена!",202,49,cream)
	box(game,BUY,Color(0,0,0,0),green)
	var available=game.model.open_bay_count<game.Model.BAY_COUNT
	game._text("Открыть дополнительное",Vector2(270,682),24,green,true)
	game._text("место за 100",Vector2(248,718),25,cream,true)
	icon(game,COIN,Vector2(365,710),40)
	if not available: game._text("Все места уже открыты",Vector2(270,769),18,mint,true)
	else: game._text("или",Vector2(270,792),35,mint,true)
	box(game,VIDEO,Color(0,0,0,0),Color("a2afc4"))
	game._text("за просмотр",Vector2(223,856),23,mint,true)
	game._text("рекламы",Vector2(223,886),23,mint,true)
	icon(game,AD,Vector2(414,866),76)
	game._text("Реклама пока недоступна",Vector2(270,939),17,Color("bbc5d5"),true)
	box(game,UNDO,Color("5a95f2"),Color.TRANSPARENT)
	game._text("Отмена",Vector2(145,1025),25,cream,true)
	var gifts:int=int(game.economy.state.inventory.get("undo",0))
	game._text("хода ×%d"%gifts if gifts>0 else "хода 20",Vector2(132,1057),25,cream,true)
	if gifts==0:icon(game,COIN,Vector2(210,1048),36)
	box(game,RETRY,Color("5a95f2"),Color.TRANSPARENT)
	game._text("Попробовать",Vector2(391,1025),20,cream,true)
	game._text("заново",Vector2(391,1055),23,cream,true)
	if game.toast_time>0: game._text(game.toast,Vector2(270,1122),18,Color.WHITE,true)
