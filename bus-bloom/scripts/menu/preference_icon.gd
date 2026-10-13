extends BaseButton
@export var icon: Texture2D
var region:Rect2

func _ready() -> void:
	toggle_mode = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon: region = Rect2(icon.get_image().get_used_rect())
	toggled.connect(func(_enabled:bool): queue_redraw())
	resized.connect(queue_redraw)

func _draw() -> void:
	if not icon: return
	var fit = minf((size.x-12)/region.size.x,(size.y-12)/region.size.y)
	var drawn = region.size*fit
	draw_texture_rect_region(icon,Rect2((size-drawn)*0.5,drawn),region)
	if not button_pressed:
		var a = Vector2(size.x*0.19,size.y*0.81)
		var b = Vector2(size.x*0.81,size.y*0.19)
		draw_line(a,b,Color(1,1,1,0.9),7,true)
		draw_line(a,b,Color("f02d32"),4,true)
	if has_focus(): draw_style_box(get_theme_stylebox("focus","Button"),Rect2(Vector2.ZERO,size))
