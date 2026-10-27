extends Control
## One modal window drawn from a plain Dictionary spec (see modal_catalog.gd).
## The owner listens to `action(id)` and decides what happens; the modal never
## touches the economy itself. Layout is computed in a 540-wide design space and
## scaled down on short screens so the whole card always fits.
signal action(id:String)
signal tapped
signal closed

const Style := preload("res://scripts/ui/modal_style.gd")
const BLOCK_GAP := 14.0
const INNER_X := Style.CARD_X+Style.PAD
const INNER_W := Style.CARD_W-Style.PAD*2
const OPEN_TIME := 0.30
const CLOSE_TIME := 0.16
const PACK_H := 196.0
const FLIGHT_COINS := 14
const DAY_H := 140.0
const CHECK := preload("res://assets/artwork/menu/green-checkmark.png")
const COIN_PILES := [
	preload("res://assets/artwork/menu/coin.png"),
	preload("res://assets/artwork/menu/coins-stack-small.png"),
	preload("res://assets/artwork/menu/coins-stack-medium.png"),
	preload("res://assets/artwork/menu/coins-stack-big.png"),
]

var spec: Dictionary = {}
var reduced_motion := false
var age := 0.0
var closing_age := -1.0
var card_rect := Rect2()
var placed: Array = []
var hits: Dictionary = {}
var pressed_id := ""
var press_inside := false
var press: Dictionary = {}
var busy: Dictionary = {}
var flash_text := ""
var flash_time := 0.0
var base := Transform2D.IDENTITY
var _laid_out_for := Vector2.ZERO
var flight_start := 0.0
var reward_coin := Vector2.ZERO
var switches: Dictionary = {}

func _init(value:Dictionary={}) -> void:
	spec = value

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(func(): _laid_out_for = Vector2.ZERO)

## Replace the content without replaying the entrance (e.g. ad finished).
func update_spec(value:Dictionary) -> void:
	spec = value
	if value.get("replay_flight",false): flight_start = age
	_laid_out_for = Vector2.ZERO
	queue_redraw()

func set_busy(id:String,on:bool) -> void:
	if on: busy[id] = true
	else: busy.erase(id)

func flash(value:String,seconds:float=2.6) -> void:
	flash_text = value
	flash_time = seconds

func is_closing() -> bool:
	return closing_age>=0.0

func close() -> void:
	if closing_age<0.0: closing_age = 0.0

## Android back / Escape: runs the spec's "back" action, if any.
func back() -> void:
	var id: String = spec.get("back","")
	if id!="" and not is_closing(): action.emit(id)

func _process(delta:float) -> void:
	age += delta
	flash_time = maxf(0.0,flash_time-delta)
	var appear := minf(1.0,age/(OPEN_TIME*0.6))
	if closing_age>=0.0: appear = 1.0-clampf(closing_age/CLOSE_TIME,0,1)
	modulate.a = appear
	for id in press.keys():
		var target := 1.0 if id==pressed_id and press_inside else 0.0
		press[id] = move_toward(press[id],target,delta/0.08)
		if press[id]==0.0 and id!=pressed_id: press.erase(id)
	if closing_age>=0.0:
		closing_age += delta
		if closing_age>=CLOSE_TIME or reduced_motion:
			closed.emit()
			queue_free()
			return
	queue_redraw()

# ---------------------------------------------------------------- layout

func _block_height(b:Dictionary) -> float:
	match b.get("type",""):
		"art": return float(b.get("height",200))
		"hero": return float(b.get("size",150))+24.0
		"text": return Style.paragraph_height(b.text,INNER_W,int(b.get("size",22)))
		"button": return 91.0+(26.0 if b.has("note") else 0.0)
		"row": return 96.0
		"link": return 40.0
		"timer": return 44.0
		"bundle": return 132.0
		"reward": return 96.0
		"steps": return 16.0
		"status": return 64.0
		"gap": return float(b.get("height",8))
		"label": return 26.0
		"nav","toggle": return 80.0
		"days": return DAY_H*2.0+130.0+20.0
		"deal": return 158.0
		"packs":
			var rows := ceili(float(b.tiles.size())/float(b.get("columns",3)))
			return rows*PACK_H+(rows-1)*12.0
	return 0.0

func _layout() -> void:
	if _laid_out_for==size and not placed.is_empty(): return
	_laid_out_for = size
	var coach: bool = spec.get("layout","card")=="coach"
	var top_pad: float = 80.0 if coach else Style.HEADER_H+Style.TAPE_H+22.0
	var h := top_pad
	var heights: Array = []
	var flexible := 0.0
	for b: Dictionary in spec.get("blocks",[]):
		var bh := _block_height(b)
		heights.append(bh)
		h += bh+BLOCK_GAP
		if b.get("type","") in ["art","hero"]: flexible += maxf(0.0,bh-(240.0 if b.get("fit","")=="contain" else 110.0))
	h += Style.PAD-BLOCK_GAP+6.0
	var view := size if size.x>0 else Vector2(540,960)
	var zoom := view.x/Style.WIDTH
	var top_margin := 30.0 if coach else 78.0
	var needed := h+top_margin+40.0
	# Short screens: first give up picture height (down to 110), only then scale.
	var overflow := needed-view.y/zoom
	if overflow>0.0 and flexible>0.0:
		var k := minf(1.0,overflow/flexible)
		var blocks: Array = spec.get("blocks",[])
		for i in blocks.size():
			if blocks[i].get("type","") in ["art","hero"]:
				var minimum := 240.0 if blocks[i].get("fit","")=="contain" else 110.0
				var cut: float = maxf(0.0,heights[i]-minimum)*k
				heights[i] -= cut
				h -= cut
		needed = h+top_margin+40.0
	if view.y/zoom<needed: zoom = view.y/needed
	var design_h := view.y/zoom
	base = Transform2D(0.0,Vector2.ONE*zoom,0.0,Vector2((view.x-Style.WIDTH*zoom)*0.5,0.0))
	var top: float
	if coach:
		top = design_h-h-34.0
		# Never cover the highlighted object: move the coach card above it.
		if spec.has("spotlight"):
			var target: Vector2 = base.affine_inverse()*Vector2(spec.spotlight.center)
			var r: float = spec.spotlight.get("radius",70.0)/zoom
			if target.y+r+20.0>top: top = maxf(90.0,target.y-r-120.0-h)
	else: top = maxf(top_margin,(design_h-h)*0.5+18.0)
	card_rect = Rect2(Style.CARD_X,top,Style.CARD_W,h)
	placed.clear()
	hits.clear()
	var y := top+top_pad
	var blocks: Array = spec.get("blocks",[])
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		var rect := Rect2(INNER_X,y,INNER_W,heights[i])
		placed.append({"block":b,"rect":rect})
		if b.type=="packs":
			for t in b.tiles.size():
				if b.tiles[t].get("enabled",true): hits[b.tiles[t].id] = _pack_rect(b,rect,t)
		var id: String = b.get("id","")
		if id!="" and b.get("enabled",true):
			match b.type:
				"button": hits[id] = Rect2(rect.position,Vector2(rect.size.x,91))
				"row": hits[id] = _row_button(rect)
				"link": hits[id] = rect.grow_individual(-90,6,-90,6)
				"deal","nav","toggle": hits[id] = rect
		y += heights[i]+BLOCK_GAP
	if spec.get("close",false): hits["close"] = Rect2(_close_center()-Vector2(32,32),Vector2(64,64))

func _pack_rect(b:Dictionary,rect:Rect2,i:int) -> Rect2:
	var cols := int(b.get("columns",3))
	var w := (rect.size.x-12.0*(cols-1))/cols
	return Rect2(rect.position.x+(i%cols)*(w+12.0),rect.position.y+(i/cols)*(PACK_H+12.0),w,PACK_H)

func _row_button(rect:Rect2) -> Rect2:
	return Rect2(rect.end.x-152,rect.position.y+16,140,57)

func _close_center() -> Vector2:
	return Vector2(card_rect.end.x-14,card_rect.position.y+12)

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_layout()
	var coach: bool = spec.get("layout","card")=="coach"
	var scrim: Color = Style.SCRIM_LIGHT if coach else Style.SCRIM
	if spec.has("spotlight"): _draw_spotlight(scrim)
	else: draw_rect(Rect2(Vector2.ZERO,size),scrim)
	draw_set_transform_matrix(base*_card_anim())
	if coach: _draw_coach_frame()
	else:
		Style.card(self,card_rect)
		Style.juicy(self,spec.get("title",""),Vector2(270,card_rect.position.y+58),36,Style.TITLE,card_rect.size.x-120)
	for item: Dictionary in placed: _draw_block(item.block,item.rect)
	if spec.get("close",false): Style.close_button(self,_close_center(),press.get("close",0.0))
	if spec.has("ribbon"): _draw_ribbon(spec.ribbon)
	if flash_time>0.0: _draw_flash()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if int(spec.get("balance",-1))>=0 and not coach:
		var shown := int(spec.balance)
		if spec.has("balance_from"): shown = displayed_balance(int(spec.balance_from),shown,age-flight_start,reduced_motion)
		Style.balance(self,shown)
	if spec.get("fly",false) and not reduced_motion: _draw_flight()

func _draw_coach_frame() -> void:
	Style.card(self,card_rect,false)
	var avatar: Texture2D = spec.get("avatar")
	var c := Vector2(card_rect.position.x+66,card_rect.position.y+8)
	draw_circle(c+Vector2(0,5),52,Style.INK_DEEP)
	draw_circle(c,52,Style.INK)
	if avatar:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 48:
			var d := Vector2.from_angle(TAU*i/48.0)
			pts.append(c+d*47)
			uvs.append(Vector2(0.5,0.47)+d*0.44)
		draw_polygon(pts,PackedColorArray([Color.WHITE]),uvs,avatar)
	var name_rect := Rect2(card_rect.position.x+128,card_rect.position.y+18,card_rect.size.x-150,44)
	Style.text(self,spec.get("title",""),Vector2(name_rect.get_center().x,name_rect.position.y+34),30,Style.INK,Style.BLACK,name_rect.size.x)

func _draw_spotlight(scrim:Color) -> void:
	var s: Dictionary = spec.spotlight
	var center: Vector2 = s.center
	var r: float = s.get("radius",70.0)
	for i in 72:
		var a := Vector2.from_angle(TAU*i/72.0)
		var b := Vector2.from_angle(TAU*(i+1)/72.0)
		draw_colored_polygon(PackedVector2Array([center+a*r,center+b*r,center+b*4000,center+a*4000]),scrim)
	var pulse := 0.5 if reduced_motion else (sin(age*TAU/1.3)+1.0)*0.5
	draw_arc(center,r+2+pulse*4,0,TAU,72,Color(1,0.88,0.35,0.55+0.4*pulse),4,true)
	var away := Vector2.DOWN if (base*card_rect.get_center()).y<center.y else Vector2.UP
	if center.y+away.y*(r+110)<0 or center.y+away.y*(r+110)>size.y:
		away = Vector2.LEFT if center.x>size.x*0.5 else Vector2.RIGHT
	preload("res://scripts/ui/tutorial_pointer.gd").draw(self,center+away*(r+18),-away,age,reduced_motion)

func _draw_ribbon(label:String) -> void:
	# Sits on the top-left corner of the first picture, clear of the title.
	var c := Vector2(card_rect.position.x+16,card_rect.position.y+Style.HEADER_H+Style.TAPE_H+34)
	var r := Rect2(c-Vector2(8,24),Vector2(104,48))
	draw_set_transform_matrix(base*Transform2D(-0.22,r.get_center())*Transform2D(0,-r.get_center()))
	Style.round_rect(self,Rect2(r.position+Vector2(0,5),r.size),Color("b32a1f"),Style.R_PILL)
	Style.round_rect(self,r,Color("f04b3a"),Style.R_PILL,Color.WHITE,3)
	Style.text(self,label,r.get_center()+Vector2(0,9),26,Color.WHITE,Style.BLACK,r.size.x-12)
	draw_set_transform_matrix(base)

func _draw_flash() -> void:
	var a := clampf(flash_time/0.25,0,1)
	var w := Style.BOLD.get_string_size(flash_text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+40
	var r := Rect2(Vector2(270-w*0.5,card_rect.end.y-22),Vector2(w,44))
	Style.round_rect(self,r,Color(Style.INK,0.96*a),Style.R_PILL+8)
	Style.text(self,flash_text,r.get_center()+Vector2(0,7),18,Color(1,1,1,a))

func _pulse(b:Dictionary) -> float:
	if reduced_motion or not b.get("pulse",false) or age<1.0 or closing_age>=0.0: return 1.0
	var cycle := fmod(age-1.0,2.4)
	return 1.0+0.035*sin(clampf(cycle/0.7,0,1)*PI)

func _draw_block(b:Dictionary,rect:Rect2) -> void:
	match b.get("type",""):
		"art": _draw_art(b,rect)
		"hero":
			var center := rect.get_center()
			if b.get("rays",true): Style.rays(self,center,rect.size.y*0.62,0.0 if reduced_motion else age*0.35)
			var s := minf(float(b.get("size",150)),rect.size.y-24.0)
			var bounce := 0.0 if reduced_motion else sin(age*2.2)*3.0
			Style.icon(self,b.texture,center+Vector2(0,bounce),s)
			if b.has("badge"):
				var badge := Rect2(center+Vector2(s*0.18,s*0.22),Vector2(84,40))
				Style.round_rect(self,badge,Style.INK,Style.R_PILL)
				Style.text(self,b.badge,badge.get_center()+Vector2(0,8),24,Color.WHITE,Style.HEAVY,76)
		"text":
			Style.paragraph(self,b.text,rect.position,rect.size.x,int(b.get("size",22)),b.get("color",Style.TEXT))
		"button": _draw_button(b,rect)
		"row": _draw_row(b,rect)
		"link":
			var pressed: float = press.get(b.get("id",""),0.0)
			Style.text(self,b.label,rect.get_center()+Vector2(0,8+pressed*2),21,Style.MUTED.darkened(0.15*pressed),Style.HEAVY)
			var w := Style.HEAVY.get_string_size(b.label,HORIZONTAL_ALIGNMENT_LEFT,-1,21).x
			draw_line(rect.get_center()+Vector2(-w*0.5,13),rect.get_center()+Vector2(w*0.5,13),Color(Style.MUTED,0.45),2)
		"timer": _draw_timer(b,rect)
		"bundle": _draw_bundle(b,rect)
		"label": Style.text_left(self,b.text,rect.position+Vector2(4,21),22,Style.TEXT,Style.HEAVY)
		"nav","toggle": _draw_setting(b,rect)
		"days": _draw_days(b,rect)
		"deal": _draw_deal(b,rect)
		"packs":
			for t in b.tiles.size(): _draw_pack(b.tiles[t],_pack_rect(b,rect,t))
		"reward":
			var c := rect.get_center()
			var label := "+%d" % int(b.amount)
			var w := Style.BLACK.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,56).x
			var start := c.x-(w+84)*0.5
			reward_coin = Vector2(start+36,c.y)
			Style.rays(self,reward_coin,70,0.0 if reduced_motion else age*0.4,0.8)
			Style.icon(self,Style.COIN,reward_coin,78)
			Style.juicy(self,label,Vector2(start+84+w*0.5,c.y+20),56,Color("7cf08a"),300,Color("17602a"))
		"steps":
			var n := int(b.count)
			for i in n:
				var p := rect.get_center()+Vector2((i-(n-1)*0.5)*26,0)
				var on: bool = i==int(b.index)
				Style.round_rect(self,Rect2(p-Vector2(14 if on else 6,6),Vector2(28 if on else 12,12)),Style.GOLD if on else Style.TILE_EDGE,6)
		"status":
			var c := rect.get_center()
			if b.get("spinner",false):
				Style.spinner(self,c+Vector2(-Style.BOLD.get_string_size(b.text,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x*0.5-26,0),14,age,Color("3d8ef0"))
			Style.text(self,b.text,c+Vector2(8 if b.get("spinner",false) else 0,7),20,b.get("color",Style.MUTED))

static func contained_art_rect(texture_size:Vector2,rect:Rect2) -> Rect2:
	var fitted := texture_size*minf(rect.size.x/texture_size.x,rect.size.y/texture_size.y)
	return Rect2(rect.get_center()-fitted*0.5,fitted)

func _draw_art(b:Dictionary,rect:Rect2) -> void:
	var tex: Texture2D = b.texture
	var tex_size := tex.get_size()
	if b.get("fit","")=="contain":
		draw_texture_rect(tex,contained_art_rect(tex_size,rect),false)
		return
	# Cover-crop around an optional focus point (0..1), keeping the art's aspect.
	var focus: Vector2 = b.get("focus",Vector2(0.5,0.5))
	var scale := maxf(rect.size.x/tex_size.x,rect.size.y/tex_size.y)
	var src_size := rect.size/scale
	var src_pos := (tex_size*focus-src_size*0.5).clamp(Vector2.ZERO,tex_size-src_size)
	var radius := float(Style.R_TILE)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var corners := [rect.position+Vector2(radius,radius),Vector2(rect.end.x-radius,rect.position.y+radius),rect.end-Vector2(radius,radius),Vector2(rect.position.x+radius,rect.end.y-radius)]
	for corner in 4:
		for step in 9:
			var p: Vector2 = corners[corner]+Vector2.from_angle(PI+corner*PI*0.5+step*PI/16.0)*radius
			pts.append(p)
			uvs.append((src_pos+(p-rect.position)/scale)/tex_size)
	Style.round_rect(self,Rect2(rect.position+Vector2(0,5),rect.size),Style.TILE_EDGE,Style.R_TILE)
	draw_polygon(pts,PackedColorArray([Color.WHITE]),uvs,tex)
	pts.append(pts[0])
	draw_polyline(pts,Style.INK,4,true)

func _draw_button(b:Dictionary,rect:Rect2) -> void:
	var id: String = b.get("id","")
	var enabled: bool = b.get("enabled",true)
	var kind: String = b.get("kind","primary") if enabled else "disabled"
	var area := Rect2(rect.position,Vector2(rect.size.x,84))
	var k := _pulse(b) if enabled else 1.0
	if k!=1.0:
		var c := area.get_center()
		draw_set_transform_matrix(base*_card_anim()*Transform2D(0,Vector2.ONE*k,0,c-c*k))
	var face := Style.button(self,area,kind,press.get(id,0.0))
	var price: Dictionary = b.get("price",{})
	var tex: Texture2D = b.get("icon",Style.AD if b.get("kind","")=="ad" else null)
	var left := face.position.x+18
	if tex:
		Style.icon(self,tex,Vector2(face.position.x+46,face.get_center().y),58)
		left = face.position.x+82
	var right := face.end.x-14
	if busy.has(id):
		Style.spinner(self,Vector2(face.end.x-46,face.get_center().y),14,age,Color.WHITE)
		right = face.end.x-80
	elif not price.is_empty():
		right = Style.price_tag(self,face,price,kind).position.x-8
	Style.button_label(self,"Загружаем…" if busy.has(id) else b.label,Vector2((left+right)*0.5,face.get_center().y),int(b.get("size",28)),kind,right-left)
	if k!=1.0: draw_set_transform_matrix(base*_card_anim())
	if b.has("note"): Style.text(self,b.note,Vector2(rect.get_center().x,rect.position.y+91+20),17,Style.MUTED)

func _draw_row(b:Dictionary,rect:Rect2) -> void:
	var id: String = b.get("id","")
	var enabled: bool = b.get("enabled",true)
	Style.round_rect(self,rect,Style.TILE,Style.R_TILE,Style.TILE_EDGE,3)
	Style.icon(self,b.icon,Vector2(rect.position.x+44,rect.get_center().y),62,1.0 if enabled else 0.5)
	var text_w := rect.size.x-88-160
	Style.text_left(self,b.title,Vector2(rect.position.x+86,rect.position.y+42),22,Style.TEXT if enabled else Style.MUTED,Style.HEAVY,text_w)
	Style.text_left(self,b.get("subtitle",""),Vector2(rect.position.x+86,rect.position.y+70),16,Style.MUTED,Style.BOLD,text_w)
	var btn := _row_button(rect)
	var kind: String = b.get("kind","primary") if enabled else "disabled"
	var face := Style.button(self,Rect2(btn.position,Vector2(btn.size.x,btn.size.y-7)),kind,press.get(id,0.0))
	var price: Dictionary = b.get("price",{})
	if busy.has(id): Style.spinner(self,face.get_center(),12,age,Color.WHITE)
	elif price.has("coins"):
		var label := str(price.coins)
		var w := Style.HEAVY.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,24).x+38
		var x := face.get_center().x-w*0.5
		Style.icon(self,Style.COIN,Vector2(x+15,face.get_center().y),30)
		var p: Dictionary = Style.BUTTONS[kind]
		var pos := Vector2(x+36,face.get_center().y+9)
		if p.outline.a>0: draw_string_outline(Style.HEAVY,pos,label,HORIZONTAL_ALIGNMENT_LEFT,-1,24,6,p.outline)
		draw_string(Style.HEAVY,pos,label,HORIZONTAL_ALIGNMENT_LEFT,-1,24,p.text)
	elif b.get("kind","")=="ad":
		Style.icon(self,Style.AD,face.get_center(),54)
	else:
		Style.button_label(self,b.get("action_label","Взять"),face.get_center(),22,kind,face.size.x-16)

func _draw_timer(b:Dictionary,rect:Rect2) -> void:
	var left := maxi(0,int(b.ends_at)-int(b.get("now",Time.get_unix_time_from_system())))
	var label := "%s  %s" % [b.get("label","Осталось"),_format_left(left)]
	var w := Style.HEAVY.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x+64
	var r := Rect2(rect.get_center()-Vector2(w*0.5,22),Vector2(w,44))
	Style.round_rect(self,r,Style.INK,Style.R_PILL+8)
	var clock := r.position+Vector2(26,22)
	draw_circle(clock,11,Style.GOLD)
	draw_line(clock,clock+Vector2(0,-7),Style.INK,2.5,true)
	draw_line(clock,clock+Vector2(5,2),Style.INK,2.5,true)
	Style.text_left(self,label,r.position+Vector2(46,29),20,Color.WHITE,Style.HEAVY)

static func _format_left(seconds:int) -> String:
	var d := seconds/86400
	var h := (seconds%86400)/3600
	var m := (seconds%3600)/60
	if d>0: return "%d д %d ч" % [d,h]
	if h>0: return "%d ч %02d мин" % [h,m]
	return "%d:%02d" % [m,seconds%60]

## Wide offer card: picture left, contents and price right; the whole card is the target.
func _draw_deal(b:Dictionary,rect:Rect2) -> void:
	var id: String = b.get("id","")
	var p: float = press.get(id,0.0)
	var r := Rect2(rect.position+Vector2(0,p*3),rect.size)
	Style.round_rect(self,Rect2(rect.position+Vector2(0,5),rect.size),Style.TILE_EDGE,Style.R_TILE)
	Style.round_rect(self,r,Style.TILE,Style.R_TILE,Style.TILE_EDGE,3)
	var pic := Rect2(r.position+Vector2(8,8),Vector2(148,r.size.y-16))
	if b.has("art"): _draw_art({"texture":b.art,"focus":b.get("focus",Vector2(0.5,0.4))},pic)
	else:
		Style.round_rect(self,pic,Style.PAPER_DEEP,Style.R_TILE-6)
		if not reduced_motion: Style.rays(self,pic.get_center(),70,age*0.35,0.7)
		Style.icon(self,b.icon,pic.get_center(),104)
	var x := pic.end.x+14
	var right := r.end.x-12
	Style.text_left(self,b.title,Vector2(x,r.position.y+32),22,Style.TEXT,Style.HEAVY,right-x)
	if b.has("subtitle"): Style.text_left(self,b.subtitle,Vector2(x,r.position.y+54),15,Style.MUTED,Style.BOLD,right-x)
	var ix := x
	for it: Dictionary in b.get("items",[]):
		Style.icon(self,it.texture,Vector2(ix+15,r.position.y+78),30)
		Style.text_left(self,it.count,Vector2(ix+32,r.position.y+85),17,Style.TEXT,Style.HEAVY)
		ix += 36+Style.HEAVY.get_string_size(it.count,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x+8
	var btn := Rect2(right-128,r.end.y-54,128,42)
	var face := Style.button(self,btn,"primary",p)
	if busy.has(id): Style.spinner(self,face.get_center(),12,age,Color.WHITE)
	else: Style.button_label(self,b.price,face.get_center(),22,"primary",face.size.x-14)
	if b.has("old_price"):
		var old_c := Vector2(btn.position.x-40,face.get_center().y+6)
		Style.text(self,b.old_price,old_c,16,Style.MUTED,Style.BOLD)
		var w := Style.BOLD.get_string_size(b.old_price,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		draw_line(old_c+Vector2(-w*0.5-2,-5),old_c+Vector2(w*0.5+2,-5),Color("e0453a"),2.5,true)
	if b.has("tag"): _tag(b.tag,Vector2(r.position.x+30,r.position.y+6),-0.12)

## Shop tile: tag on top, icon, amount, bonus, price button. Kind "ad" = free tile.
func _draw_pack(t:Dictionary,r:Rect2) -> void:
	var id: String = t.id
	var enabled: bool = t.get("enabled",true)
	var p: float = press.get(id,0.0)
	var best: bool = t.has("tag")
	Style.round_rect(self,r,Color("fff3c4") if best else Style.TILE,Style.R_TILE,Style.GOLD if best else Style.TILE_EDGE,4 if best else 3)
	var c := r.get_center()
	Style.icon(self,t.icon,Vector2(c.x,r.position.y+60),84,1.0 if enabled else 0.5)
	Style.juicy(self,t.amount,Vector2(c.x,r.position.y+128),28,Color.WHITE,r.size.x-16)
	if t.has("bonus"):
		var bw := Style.HEAVY.get_string_size(t.bonus,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x+16
		var br := Rect2(Vector2(r.end.x-bw-6,r.position.y+78),Vector2(bw,24))
		Style.round_rect(self,br,Color("2f9e47"),12)
		Style.text(self,t.bonus,br.get_center()+Vector2(0,5.5),15,Color.WHITE,Style.HEAVY)
	var kind: String = t.get("kind","primary") if enabled else "disabled"
	var face := Style.button(self,Rect2(r.position.x+8,r.end.y-58,r.size.x-16,46),kind,p)
	if busy.has(id): Style.spinner(self,face.get_center(),12,age,Color.WHITE)
	elif t.get("kind","")=="ad":
		Style.icon(self,Style.AD,Vector2(face.position.x+24,face.get_center().y),38)
		Style.button_label(self,t.price,face.get_center()+Vector2(16,0),19,kind,face.size.x-56)
	else: Style.button_label(self,t.price,face.get_center(),21,kind,face.size.x-12)
	if best: _tag(t.tag,Vector2(r.position.x-6,r.position.y-10),-0.10)

func _tag(label:String,pos:Vector2,angle:float) -> void:
	var w := Style.BLACK.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x+22
	var r := Rect2(pos,Vector2(maxf(76,w),28))
	var m := Transform2D(angle,r.get_center())*Transform2D(0,-r.get_center())
	var prev := base*_card_anim()
	draw_set_transform_matrix(prev*m)
	Style.round_rect(self,Rect2(r.position+Vector2(0,3),r.size),Color("b32a1f"),12)
	Style.round_rect(self,r,Color("f04b3a"),12,Color.WHITE,2)
	Style.text(self,label,r.get_center()+Vector2(0,6),17,Color.WHITE,Style.BLACK,r.size.x-8)
	draw_set_transform_matrix(prev)

## Coins leave the reward and land in the balance counter, which counts up as
## they arrive (see displayed_balance). Drawn in screen space over everything.
func _draw_flight() -> void:
	var t := age-flight_start
	var from: Vector2 = base*reward_coin
	var to: Vector2 = Style.BALANCE_RECT.position+Vector2(24,22)
	var zoom := base.get_scale().x
	for i in FLIGHT_COINS:
		var p := coin_progress(i,t)
		if p<0.0: continue
		var eased := p*p*(2.0-p)
		var pos := from.lerp(to,eased)+Vector2(48+(i%4)*9,0)*zoom*sin(PI*p)
		var size := lerpf(48*zoom,30,p)
		draw_set_transform(pos,sin(p*TAU+i)*0.18)
		Style.icon(self,Style.COIN,Vector2.ZERO,size)
	draw_set_transform_matrix(Transform2D.IDENTITY)

## Flight progress 0..1 of coin `i` at time `t`, or -1 when not flying.
static func coin_progress(i:int,t:float) -> float:
	var p := (t-(0.5+i*0.065))/(0.68+i*0.018)
	return p if p>=0.0 and p<1.0 else -1.0

## Counter value while coins fly: starts with the first arrival, ends with the last.
static func displayed_balance(before:int,after:int,t:float,reduced:bool) -> int:
	if reduced or after<=before: return after
	var first := 0.5+0.68
	var last := 0.5+(FLIGHT_COINS-1)*(0.065+0.018)+0.68
	return roundi(lerpf(before,after,clampf((t-first)/(last-first),0.0,1.0)))

## Settings row: icon, title, optional subtitle; right side is either a value
## with a chevron (nav) or a switch (toggle). The whole row is the target.
func _draw_setting(b:Dictionary,rect:Rect2) -> void:
	var id: String = b.get("id","")
	var enabled: bool = b.get("enabled",true)
	var p: float = press.get(id,0.0)
	Style.round_rect(self,rect,Style.TILE.darkened(0.04*p),Style.R_TILE,Style.TILE_EDGE,3)
	var icon_c := Vector2(rect.position.x+42,rect.get_center().y)
	if b.has("icon"): Style.icon(self,b.icon,icon_c,52,1.0 if enabled else 0.5)
	elif b.get("glyph","")=="motion": _motion_glyph(icon_c)
	elif b.get("glyph","")=="check" and b.get("checked",false):
		draw_circle(icon_c,18,Color("4ccb5e"))
		draw_polyline(PackedVector2Array([icon_c+Vector2(-8,0),icon_c+Vector2(-2,6),icon_c+Vector2(9,-6)]),Color.WHITE,4,true)
	var x := rect.position.x+(80 if b.has("icon") or b.has("glyph") else 20)
	var right := rect.end.x-16
	var tint := Style.TEXT if enabled else Style.MUTED
	if b.has("subtitle"):
		Style.text_left(self,b.title,Vector2(x,rect.position.y+36),22,tint,Style.HEAVY,right-x-90)
		Style.text_left(self,b.subtitle,Vector2(x,rect.position.y+60),15,Style.MUTED,Style.BOLD,right-x-90)
	else: Style.text_left(self,b.title,Vector2(x,rect.get_center().y+8),22,tint,Style.HEAVY,right-x-90)
	if b.type=="toggle":
		var on: bool = b.get("on",false)
		var k: float = switches.get(id,1.0 if on else 0.0)
		var target := 1.0 if on else 0.0
		k = target if reduced_motion else move_toward(k,target,get_process_delta_time()/0.15)
		switches[id] = k
		var track := Rect2(right-64,rect.get_center().y-18,64,36)
		Style.round_rect(self,track,Style.TILE_EDGE.lerp(Color("4ccb5e"),k),18)
		var knob := Vector2(lerpf(track.position.x+18,track.end.x-18,Style.ease_out(k)),track.get_center().y)
		draw_circle(knob+Vector2(0,2),14,Color(0,0,0,0.18))
		draw_circle(knob,14,Color.WHITE)
	elif b.get("chevron",true):
		var chevron := Vector2(right-6,rect.get_center().y)
		draw_polyline(PackedVector2Array([chevron+Vector2(-7,-9),chevron,chevron+Vector2(-7,9)]),Style.MUTED,3.5,true)
		if b.has("value"):
			var w := Style.BOLD.get_string_size(b.value,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
			Style.text_left(self,b.value,Vector2(right-22-w,rect.get_center().y+7),18,Style.MUTED,Style.BOLD)

## Drawn stand-in for a "less motion" icon until artwork exists.
func _motion_glyph(c:Vector2) -> void:
	draw_circle(c,24,Color("3d8ef0"))
	draw_circle(c+Vector2(7,0),9,Color.WHITE)
	for i in 3:
		var y := c.y-8+i*8
		draw_line(Vector2(c.x-15,y),Vector2(c.x-4-(i%2)*3,y),Color.WHITE,3,true)

## Seven-day calendar: six tiles in two rows and a wide seventh day.
## Day states come from daily_calendar.gd: claimed, available, locked, missed.
func _draw_days(b:Dictionary,rect:Rect2) -> void:
	var w := (rect.size.x-20.0)/3.0
	for i in 7:
		var r := Rect2(rect.position.x+(i%3)*(w+10.0),rect.position.y+(i/3)*(DAY_H+10.0),w,DAY_H)
		if i==6: r = Rect2(rect.position.x,rect.position.y+2*(DAY_H+10.0),rect.size.x,130.0)
		_draw_day(i,b.days[i],r,b.get("pop",-1)==i)

func _draw_day(i:int,day:Dictionary,r:Rect2,pop:bool) -> void:
	var state: String = day.state
	var today: bool = state=="available"
	Style.round_rect(self,r,Color("fff3c4") if today else Style.TILE,Style.R_TILE,Style.GOLD if today else Style.TILE_EDGE,4 if today else 3)
	if not today: Style.text_left(self,"День %d" % (i+1),r.position+Vector2(12,24),15,Style.MUTED,Style.HEAVY)
	var rewards: Array = day.rewards
	var art_y := r.position.y+(64 if i<6 else 60)
	for j in rewards.size():
		var x := r.position.x+r.size.x*(j+1)/(rewards.size()+1)
		var item: Dictionary = rewards[j]
		var size := 96.0 if i==6 else (74.0 if rewards.size()==1 else 54.0)
		var c := Vector2(x,art_y)
		if today and j==0 and not reduced_motion: Style.rays(self,c,size*0.85,age*0.4,0.6)
		if item.item=="coins":
			_coin_pile(int(item.quantity),c,size)
			if today or pop: reward_coin = c
		else: Style.icon(self,item.texture,c,size*0.85)
		var label := str(int(item.quantity)) if item.item=="coins" else "×%d" % int(item.quantity)
		Style.juicy(self,label,Vector2(x,r.end.y-(18 if i<6 else 16)),24 if rewards.size()==1 else 20,Color.WHITE,r.size.x/rewards.size()-8)
	if state in ["claimed","missed"]:
		Style.round_rect(self,r,Color(1,1,1,0.5),Style.R_TILE)
	if state=="claimed":
		var k := 1.0
		if pop and not reduced_motion:
			var t := clampf((age-flight_start)/0.35,0.0,1.0)
			k = Style.back_out(t)
		if k>0.01: Style.icon(self,CHECK,Vector2(r.end.x-20,r.position.y+18),46*k)
	elif state=="missed":
		var pill := Rect2(Vector2(r.get_center().x-50,art_y-14),Vector2(100,28))
		Style.round_rect(self,pill,Color("53617a"),Style.R_PILL)
		Style.text(self,"Пропущен",pill.get_center()+Vector2(0,6),16,Color.WHITE,Style.HEAVY)
	elif state=="locked":
		var angle := -0.22 if i<6 else -0.08
		var c := r.get_center()+Vector2(0,4)
		draw_set_transform_matrix(base*_card_anim()*Transform2D(angle,c))
		Style.tape(self,Rect2(-r.size.x*0.5+6,-9,r.size.x-12,18))
		draw_set_transform_matrix(base*_card_anim())
	if today: _tag("Сегодня",Vector2(r.position.x-6,r.position.y-12),-0.10)

## Bigger amounts are shown as bigger piles, combining the coin pictures.
func _coin_pile(amount:int,c:Vector2,size:float) -> void:
	for p in coin_pile(amount):
		Style.icon(self,COIN_PILES[p.art],c+Vector2(p.dx,p.dy)*size,size*p.scale)

## Layout of the pile for an amount: [{art, dx, dy, scale}], back to front.
static func coin_pile(amount:int) -> Array:
	if amount<25: return [{"art":0,"dx":0.0,"dy":0.0,"scale":0.8}]
	if amount<45: return [{"art":1,"dx":0.0,"dy":0.0,"scale":1.0}]
	if amount<80: return [{"art":2,"dx":0.0,"dy":0.0,"scale":1.0}]
	if amount<120: return [{"art":3,"dx":0.0,"dy":0.0,"scale":1.05}]
	if amount<200: return [{"art":3,"dx":-0.28,"dy":-0.04,"scale":1.0},{"art":2,"dx":0.32,"dy":0.08,"scale":0.8}]
	return [{"art":3,"dx":-0.34,"dy":-0.04,"scale":1.0},{"art":2,"dx":0.36,"dy":0.02,"scale":0.8},{"art":1,"dx":0.0,"dy":0.16,"scale":0.62}]

func _draw_bundle(b:Dictionary,rect:Rect2) -> void:
	var items: Array = b.items
	var n := items.size()
	var gap := 12.0
	var w := (rect.size.x-gap*(n-1))/n
	for i in n:
		var it: Dictionary = items[i]
		var r := Rect2(rect.position.x+i*(w+gap),rect.position.y,w,rect.size.y)
		Style.round_rect(self,r,Style.TILE,Style.R_TILE,Style.TILE_EDGE,3)
		Style.icon(self,it.texture,r.position+Vector2(w*0.5,52),minf(74,w-24))
		Style.juicy(self,it.count,Vector2(r.get_center().x,r.end.y-18),26,Color.WHITE,w-12)

func _card_anim() -> Transform2D:
	var t := age/OPEN_TIME
	var pop := 1.0 if reduced_motion else lerpf(0.90,1.0,Style.back_out(t))
	if closing_age>=0.0: pop *= lerpf(1.0,0.96,clampf(closing_age/CLOSE_TIME,0,1))
	var pivot := card_rect.get_center()
	var coach: bool = spec.get("layout","card")=="coach"
	if coach: pivot = Vector2(pivot.x,card_rect.end.y)
	var slide := 0.0 if reduced_motion or not coach else (1.0-Style.ease_out(t))*60.0
	return Transform2D(0.0,Vector2.ONE*pop,0.0,pivot-pivot*pop+Vector2(0,slide))

# ---------------------------------------------------------------- input

func design_point(screen:Vector2) -> Vector2:
	return base.affine_inverse()*screen

func _hit(p:Vector2) -> String:
	for id in hits:
		if hits[id].has_point(p): return id
	return ""

func _gui_input(event:InputEvent) -> void:
	if is_closing() or age<0.12:
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var id := _hit(design_point(event.position))
		if event.pressed:
			pressed_id = id
			press_inside = true
			if id!="":
				press[id] = press.get(id,0.0)
				tapped.emit()
		else:
			var fire := pressed_id!="" and id==pressed_id and not busy.has(id)
			pressed_id = ""
			if fire: action.emit(id)
		accept_event()
	elif event is InputEventMouseMotion and pressed_id!="":
		press_inside = _hit(design_point(event.position))==pressed_id
		accept_event()

## Test helper: press and release an element by id, as a finger would.
func tap(id:String) -> bool:
	_layout()
	if not hits.has(id) or busy.has(id): return false
	action.emit(id)
	return true
