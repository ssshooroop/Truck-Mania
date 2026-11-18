extends RefCounted
const Loc = preload("res://scripts/localization.gd")
const COIN = preload("res://assets/artwork/menu/coin.png")
static var coin_region := Rect2()
static var fonts:Dictionary = {}

static func localized_font(original:Font) -> Font:
	Loc.initialize()
	if Loc.locale not in ["ko","zh","ar"]: return original
	var key := Loc.locale+original.resource_path
	if not fonts.has(key):
		var names := {"ko":"NotoSansKR","zh":"NotoSansSC","ar":"NotoSansArabic"}
		var chosen := FontVariation.new()
		chosen.base_font = load("res://assets/fonts/localization/"+names[Loc.locale]+".ttf")
		chosen.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):900 if "Black" in original.resource_path else (800 if "ExtraBold" in original.resource_path else (700 if "Bold" in original.resource_path else 500))}
		fonts[key] = chosen
	return fonts[key]

static func line(value:String,font:Font,size:int) -> TextLine:
	value = Loc.text(value)
	font = localized_font(font)
	var shaped := TextLine.new()
	shaped.direction = TextServer.DIRECTION_RTL if Loc.locale=="ar" else TextServer.DIRECTION_AUTO
	var pieces := value.split("{{coin}}")
	for i in pieces.size():
		shaped.add_string(pieces[i],font,size,Loc.locale)
		if i<pieces.size()-1: shaped.add_object(i,Vector2.ONE*size,INLINE_ALIGNMENT_CENTER)
	return shaped

static func width(value:String,font:Font,size:int) -> float:
	return line(value,font,size).get_line_width()

static func draw(c:CanvasItem,value:String,pos:Vector2,font:Font,size:int,color:Color,align:int=HORIZONTAL_ALIGNMENT_LEFT,max_width:float=0.0,outline:int=0,outline_color:Color=Color.BLACK) -> void:
	var shaped := line(value,font,size)
	while max_width>0 and shaped.get_line_width()>max_width and size>12:
		size -= 1
		shaped = line(value,font,size)
	var origin := pos-Vector2(0,shaped.get_line_ascent())
	if align==HORIZONTAL_ALIGNMENT_CENTER: origin.x -= shaped.get_line_width()*0.5
	elif align==HORIZONTAL_ALIGNMENT_RIGHT: origin.x -= shaped.get_line_width()
	if outline>0: shaped.draw_outline(c.get_canvas_item(),origin,outline,outline_color)
	shaped.draw(c.get_canvas_item(),origin,color)
	if coin_region.size==Vector2.ZERO: coin_region = Rect2(COIN.get_image().get_used_rect())
	for key in shaped.get_objects():
		var r := shaped.get_object_rect(key)
		r.position += origin
		c.draw_texture_rect_region(COIN,r,coin_region,Color(1,1,1,color.a))

static func paragraph(value:String,font:Font,size:int,max_width:float,align:int=HORIZONTAL_ALIGNMENT_CENTER) -> TextParagraph:
	value = Loc.text(value)
	font = localized_font(font)
	var shaped := TextParagraph.new()
	shaped.width = max_width
	shaped.alignment = align
	shaped.direction = TextServer.DIRECTION_RTL if Loc.locale=="ar" else TextServer.DIRECTION_AUTO
	var pieces := value.split("{{coin}}")
	for i in pieces.size():
		shaped.add_string(pieces[i],font,size,Loc.locale)
		if i<pieces.size()-1: shaped.add_object(i,Vector2.ONE*size,INLINE_ALIGNMENT_CENTER)
	return shaped

static func draw_paragraph(c:CanvasItem,value:String,pos:Vector2,font:Font,size:int,color:Color,max_width:float,align:int=HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var shaped := paragraph(value,font,size,max_width,align)
	shaped.draw(c.get_canvas_item(),pos,color)
	if coin_region.size==Vector2.ZERO: coin_region = Rect2(COIN.get_image().get_used_rect())
	var y := 0.0
	for i in shaped.get_line_count():
		for key in shaped.get_line_objects(i):
			var r := shaped.get_line_object_rect(i,key)
			r.position += pos+Vector2(0,y)
			c.draw_texture_rect_region(COIN,r,coin_region,Color(1,1,1,color.a))
		y += shaped.get_line_size(i).y

