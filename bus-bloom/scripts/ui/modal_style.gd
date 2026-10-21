extends RefCounted
## Shared look of every modal window: "a foreman's sign board".
## Rules (keep them when adding new windows):
## - Card: warm paper body, navy frame with a pressed "lip", navy header plate,
##   hazard-tape strip under the header. Corner scale: card 30, button 26,
##   tile/row 20, pill 14. Spacing unit 8.
## - Colour carries meaning, never decoration: GREEN = commit (buy, continue),
##   BLUE = watch an ad, YELLOW = coins and rewards, CREAM/NAVY = everything else.
## - One title per window, in the Black face with the navy outline used by the
##   rest of the game. Buttons say what happens ("Открыть место"), price sits on
##   the button itself.

const BLACK := preload("res://assets/fonts/MPLUSRounded1c-Black.ttf")
const HEAVY := preload("res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf")
const BOLD := preload("res://assets/fonts/MPLUSRounded1c-Bold.ttf")
const COIN := preload("res://assets/artwork/menu/coin.png")
const AD := preload("res://assets/artwork/menu/ad-player.png")
const TAPE := preload("res://assets/artwork/menu/yellow-black-tape.png")

const WIDTH := 540.0
const CARD_X := 30.0
const CARD_W := 480.0
const PAD := 24.0
const HEADER_H := 84.0
const TAPE_H := 14.0
const LIP := 8.0

const R_CARD := 30
const R_BUTTON := 26
const R_TILE := 20
const R_PILL := 14

const SCRIM := Color(0.024,0.063,0.133,0.80)
const SCRIM_LIGHT := Color(0.024,0.063,0.133,0.55)
const PAPER := Color("fff4d6")
const PAPER_DEEP := Color("f2e2b8")
const TILE := Color("fffbef")
const TILE_EDGE := Color("e8d6a6")
const INK := Color("132d50")
const INK_DEEP := Color("08182e")
const HEADER := Color("1d4478")
const TEXT := Color("243449")
const MUTED := Color("6a768a")
const TITLE := Color("fff0ac")
const GOLD := Color("ffc400")
const GOLD_TEXT := Color("ffe04d")

const BUTTONS := {
	"primary": {"face":Color("4ccb5e"),"lip":Color("23893a"),"outline":Color("1b6a2d"),"text":Color.WHITE},
	"ad": {"face":Color("3d8ef0"),"lip":Color("2659a8"),"outline":Color("1d4686"),"text":Color.WHITE},
	"secondary": {"face":Color("fffbef"),"lip":Color("d5c294"),"outline":Color.TRANSPARENT,"text":Color("243449")},
	"disabled": {"face":Color("d9d1bd"),"lip":Color("b4ab95"),"outline":Color.TRANSPARENT,"text":Color("8a826f")},
}

static var _regions: Dictionary = {}
static var _styles: Dictionary = {}

static func region(tex:Texture2D) -> Rect2:
	if not _regions.has(tex): _regions[tex] = Rect2(tex.get_image().get_used_rect())
	return _regions[tex]

static func icon(c:CanvasItem,tex:Texture2D,center:Vector2,extent:float,alpha:float=1.0) -> void:
	if tex==null: return
	var r := region(tex)
	var fit := r.size*minf(extent/r.size.x,extent/r.size.y)
	c.draw_texture_rect_region(tex,Rect2(center-fit*0.5,fit),r,Color(1,1,1,alpha))

static func round_rect(c:CanvasItem,rect:Rect2,fill:Color,radius:int,border:Color=Color.TRANSPARENT,width:int=0) -> void:
	var key := "%s|%d|%s|%d" % [fill.to_html(),radius,border.to_html(),width]
	if not _styles.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = fill
		s.set_corner_radius_all(radius)
		s.border_color = border
		s.set_border_width_all(width)
		s.anti_aliasing = true
		s.corner_detail = 12
		_styles[key] = s
	c.draw_style_box(_styles[key],rect)

static func text(c:CanvasItem,value:String,center:Vector2,size:int,color:Color,font:Font=BOLD,max_width:float=0.0) -> void:
	var actual := size
	if max_width>0.0:
		while actual>12 and font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual).x>max_width: actual -= 1
	var w := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual).x
	c.draw_string(font,center-Vector2(w*0.5,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual,color)

static func text_left(c:CanvasItem,value:String,pos:Vector2,size:int,color:Color,font:Font=BOLD,max_width:float=0.0) -> void:
	var actual := size
	if max_width>0.0:
		while actual>12 and font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual).x>max_width: actual -= 1
	c.draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual,color)

## Outlined "juicy" text, same recipe as the in-game titles.
static func juicy(c:CanvasItem,value:String,center:Vector2,size:int,tint:Color,max_width:float=440.0,outline:Color=INK) -> void:
	var actual := size
	while actual>14 and BLACK.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual).x>max_width: actual -= 1
	var w := BLACK.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual).x
	var pos := center-Vector2(w*0.5,0)
	var thick := maxi(4,roundi(actual*0.2))
	c.draw_string_outline(BLACK,pos+Vector2(0,4),value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual,thick+2,INK_DEEP)
	c.draw_string_outline(BLACK,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual,thick,outline)
	c.draw_string(BLACK,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual,tint)

static func paragraph_height(value:String,width:float,size:int) -> float:
	return BOLD.get_multiline_string_size(value,HORIZONTAL_ALIGNMENT_CENTER,width,size).y

static func paragraph(c:CanvasItem,value:String,top_left:Vector2,width:float,size:int,color:Color,align:=HORIZONTAL_ALIGNMENT_CENTER) -> void:
	c.draw_multiline_string(BOLD,top_left+Vector2(0,BOLD.get_ascent(size)),value,align,width,size,-1,color)

## Hazard tape strip cropped from the supplied artwork (skips its baked checkerboard).
static func tape(c:CanvasItem,rect:Rect2) -> void:
	var src := Rect2(150,40,620,55)
	var step := src.size.x*rect.size.y/src.size.y
	var x := rect.position.x
	while x<rect.end.x:
		var w := minf(step,rect.end.x-x)
		c.draw_texture_rect_region(TAPE,Rect2(x,rect.position.y,w,rect.size.y),Rect2(src.position,Vector2(src.size.x*w/step,src.size.y)))
		x += step

## The sign board: frame, lip, paper, header plate, tape and bolts.
static func card(c:CanvasItem,rect:Rect2,header:bool=true) -> void:
	round_rect(c,Rect2(rect.position+Vector2(0,LIP),rect.size),INK_DEEP,R_CARD)
	round_rect(c,rect,PAPER,R_CARD,INK,5)
	if not header: return
	var head := Rect2(rect.position+Vector2(5,5),Vector2(rect.size.x-10,HEADER_H-5))
	var s := StyleBoxFlat.new()
	s.bg_color = HEADER
	s.corner_radius_top_left = R_CARD-5
	s.corner_radius_top_right = R_CARD-5
	s.anti_aliasing = true
	c.draw_style_box(s,head)
	tape(c,Rect2(rect.position.x+5,rect.position.y+HEADER_H,rect.size.x-10,TAPE_H))
	for x in [rect.position.x+24,rect.end.x-24]:
		c.draw_circle(Vector2(x,rect.position.y+26),6,Color("0f2a4d"))
		c.draw_circle(Vector2(x,rect.position.y+25),4.5,Color("8fa6c4"))

## Chunky game button with a pressed lip. `pressed` 0..1 sinks it onto the lip.
static func button(c:CanvasItem,rect:Rect2,kind:String,pressed:float=0.0) -> Rect2:
	var p: Dictionary = BUTTONS.get(kind,BUTTONS.secondary)
	var lip := 7.0*(1.0-pressed*0.75)
	var face := Rect2(rect.position+Vector2(0,7.0-lip),rect.size)
	round_rect(c,Rect2(rect.position+Vector2(0,7),rect.size),p.lip,R_BUTTON)
	if kind=="secondary": round_rect(c,face,p.face,R_BUTTON,TILE_EDGE,3)
	else:
		round_rect(c,face,p.face,R_BUTTON)
		round_rect(c,Rect2(face.position+Vector2(10,6),Vector2(face.size.x-20,face.size.y*0.36)),Color(1,1,1,0.20),R_PILL)
	return face

static func button_label(c:CanvasItem,value:String,center:Vector2,size:int,kind:String,max_width:float) -> void:
	var p: Dictionary = BUTTONS.get(kind,BUTTONS.secondary)
	var actual := size
	while actual>14 and HEAVY.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual).x>max_width: actual -= 1
	var w := HEAVY.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual).x
	var pos := center+Vector2(-w*0.5,actual*0.36)
	if p.outline.a>0: c.draw_string_outline(HEAVY,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual,6,p.outline)
	c.draw_string(HEAVY,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual,p.text)

## Price tag inside a button: {"coins":100} | {"free":true} | {"money":"199 ₽","old":"499 ₽"}.
static func price_width(price:Dictionary) -> float:
	if price.is_empty(): return 0.0
	if price.has("coins"): return 52.0+HEAVY.get_string_size(str(price.coins),HORIZONTAL_ALIGNMENT_LEFT,-1,26).x+14.0
	if price.has("money"): return 28.0+HEAVY.get_string_size(price.money,HORIZONTAL_ALIGNMENT_LEFT,-1,26).x
	return 28.0+HEAVY.get_string_size("Бесплатно",HORIZONTAL_ALIGNMENT_LEFT,-1,20).x

static func price_tag(c:CanvasItem,face:Rect2,price:Dictionary,kind:String) -> Rect2:
	var p: Dictionary = BUTTONS.get(kind,BUTTONS.secondary)
	var w := price_width(price)
	var tag := Rect2(face.end.x-w-10,face.position.y+10,w,face.size.y-20)
	round_rect(c,tag,Color(0,0,0,0.16) if kind!="secondary" else PAPER_DEEP,R_PILL+2)
	var mid := tag.get_center()
	if price.has("coins"):
		icon(c,COIN,Vector2(tag.position.x+24,mid.y),34)
		var label := str(price.coins)
		var pos := Vector2(tag.position.x+46,mid.y+9.5)
		if p.outline.a>0: c.draw_string_outline(HEAVY,pos,label,HORIZONTAL_ALIGNMENT_LEFT,-1,26,6,p.outline)
		c.draw_string(HEAVY,pos,label,HORIZONTAL_ALIGNMENT_LEFT,-1,26,p.text)
	elif price.has("money"):
		button_label(c,price.money,mid,26,kind,w-16)
	else:
		button_label(c,"Бесплатно",mid,20,kind,w-12)
	return tag

## Round "close" button: cream disc with a navy cross, quieter than any CTA.
static func close_button(c:CanvasItem,center:Vector2,pressed:float=0.0) -> void:
	c.draw_circle(center+Vector2(0,4),25,INK_DEEP)
	c.draw_circle(center+Vector2(0,pressed*3),25,INK)
	c.draw_circle(center+Vector2(0,pressed*3),21,TILE)
	for s in [-1,1]:
		c.draw_line(center+Vector2(-8,-8*s+pressed*3),center+Vector2(8,8*s+pressed*3),INK,4.5,true)

## Light rays behind a hero icon; `spin` in radians.
static func rays(c:CanvasItem,center:Vector2,radius:float,spin:float,alpha:float=1.0) -> void:
	c.draw_circle(center,radius*0.62,Color(1,0.86,0.30,0.30*alpha))
	for i in 12:
		var a := spin+i*TAU/12.0
		var pts := PackedVector2Array([center,center+Vector2.from_angle(a-0.12)*radius,center+Vector2.from_angle(a+0.12)*radius])
		c.draw_colored_polygon(pts,Color(1,0.84,0.25,0.22*alpha))

static func spinner(c:CanvasItem,center:Vector2,radius:float,age:float,color:Color) -> void:
	c.draw_arc(center,radius,age*7.0,age*7.0+PI*1.4,24,color,4.0,true)

## The game's coin badge, lifted above the scrim while a purchase is offered.
## Same rect and recipe as coin_badge.gd so it reads as the same object.
const BALANCE_RECT := Rect2(388,18,134,44)
static func balance(c:CanvasItem,amount:int) -> void:
	var r := BALANCE_RECT
	round_rect(c,r,Color("172737"),16)
	icon(c,COIN,r.position+Vector2(24,22),34)
	var label := str(amount)
	var size := 22
	while size>12 and BOLD.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>r.size.x-54: size -= 1
	c.draw_string(BOLD,r.position+Vector2(47,(r.size.y+BOLD.get_ascent(size)-BOLD.get_descent(size))*0.5),label,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color.WHITE)

static func ease_out(t:float) -> float:
	return 1.0-pow(1.0-clampf(t,0.0,1.0),3.0)

static func back_out(t:float) -> float:
	t = clampf(t,0.0,1.0)
	var s := 1.6
	return 1.0+(s+1.0)*pow(t-1.0,3.0)+s*pow(t-1.0,2.0)
